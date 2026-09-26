#define _DARWIN_C_SOURCE

#define _POSIX_C_SOURCE 200809L
#ifdef __linux__
#define _GNU_SOURCE
#endif
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>
#ifdef __APPLE__
#include <mach-o/dyld.h>
#endif
#ifdef __linux__
#include <sys/syscall.h>
#include <linux/fs.h>
#endif

/* OS primitives only: package policy, identities and resolution live in Neri.
 * All mutating paths are absolute and traversed with directory descriptors.
 * Callers canonicalize their configured roots before passing paths here. */
static int path_copy(const uint8_t *bytes, int64_t length, char out[4097]) {
    if (length < 2 || length > 4096 || bytes[0] != '/' ||
        bytes[length - 1] == '/' || memchr(bytes, 0, (size_t)length)) return EINVAL;
    memcpy(out, bytes, (size_t)length);
    out[length] = 0;
    const char *start = out + 1;
    for (const char *cursor = start; ; ++cursor) {
        if (*cursor == '/' || !*cursor) {
            size_t size = (size_t)(cursor - start);
            if (!size || (size == 1 && start[0] == '.') ||
                (size == 2 && start[0] == '.' && start[1] == '.')) return EINVAL;
            if (!*cursor) break;
            start = cursor + 1;
        }
    }
    return 0;
}

static int parent_fd(char *path, char **leaf, int create) {
    int fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    if (fd < 0) return -errno;
    char *component = path + 1;
    for (;;) {
        char *slash = strchr(component, '/');
        if (slash) *slash = 0;
        if (!component[0] || !strcmp(component, ".") || !strcmp(component, "..")) {
            close(fd); return -EINVAL;
        }
        if (!slash) { *leaf = component; return fd; }
        if (create && mkdirat(fd, component, 0700) && errno != EEXIST) {
            int error = errno; close(fd); return -error;
        }
        int next = openat(fd, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        int error = errno;
        close(fd);
        if (next < 0) return -error;
        fd = next;
        component = slash + 1;
    }
}

static int write_all(int fd, const uint8_t *bytes, int64_t length) {
    if (length < 0 || length > 67108864) return EINVAL;
    int64_t offset = 0;
    while (offset < length) {
        ssize_t n = write(fd, bytes + offset, (size_t)(length - offset));
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return n < 0 ? errno : EIO;
        offset += n;
    }
    return fsync(fd) ? errno : 0;
}

/* 1 mkdirs; 2 exclusive file; 3 atomic replacement; 4 no-replace directory
 * publication; 5 hardlink; 6 unlink file; 7 remove empty directory; 9 exclusive
 * directory; 10 executable mode; 11 symlink to file; 12 activate staged symlink.
 * Returns zero on success or a captured positive errno. */
int64_t ito_fs(int64_t operation, const uint8_t *path, int64_t path_length,
               const uint8_t *other, int64_t other_length,
               const uint8_t *bytes, int64_t length) {
    char a[4097], b[4097], *leaf = NULL, *target = NULL;
    int error = path_copy(path, path_length, a);
    if (error) return error;
    int fd = parent_fd(a, &leaf, operation == 1);
    if (fd < 0) return -fd;
    if (operation == 1 || operation == 9) {
        if (mkdirat(fd, leaf, 0700) && (errno != EEXIST || operation == 9)) error = errno;
        if (!error) {
            int check = openat(fd, leaf, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
            if (check < 0) error = errno;
            else if (close(check)) error = errno;
        }
    } else if (operation == 2 || operation == 3) {
        char temporary[96];
        const char *name = leaf;
        int output = -1;
        if (operation == 3) {
            /* O_EXCL is the uniqueness guarantee; the name conveys no identity. */
            for (unsigned attempt = 0; attempt < 1024; ++attempt) {
                snprintf(temporary, sizeof temporary, ".ito-write-%ld-%u", (long)getpid(), attempt);
                output = openat(fd, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
                if (output >= 0 || errno != EEXIST) break;
            }
            name = temporary;
        } else {
            output = openat(fd, leaf, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
        }
        if (output < 0) error = errno;
        else {
            error = write_all(output, bytes, length);
            if (close(output) && !error) error = errno;
            if (!error && operation == 3 && renameat(fd, name, fd, leaf)) error = errno;
            if (error) unlinkat(fd, name, 0);
            if (!error && fsync(fd)) error = errno;
        }
    } else if (operation == 10) {
        int executable = openat(fd, leaf, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK);
        if (executable < 0) error = errno;
        else {
            struct stat info;
            if (fstat(executable, &info)) error = errno;
            else if (!S_ISREG(info.st_mode)) error = EINVAL;
            else if (fchmod(executable, 0755)) error = errno;
            else if (fsync(executable)) error = errno;
            if (close(executable) && !error) error = errno;
        }
    } else if (operation == 4 || operation == 5 || operation == 11 || operation == 12) {
        error = path_copy(other, other_length, b);
        int destination = error ? -error : parent_fd(b, &target, 0);
        if (destination < 0) error = -destination;
        else {
            struct stat info;
            if (fstatat(fd, leaf, &info, AT_SYMLINK_NOFOLLOW)) error = errno;
            else if ((operation == 5 || operation == 11) && !S_ISREG(info.st_mode)) error = EINVAL;
            else if (operation == 4 && !S_ISDIR(info.st_mode)) error = EINVAL;
            else if (operation == 12 && !S_ISLNK(info.st_mode)) error = EINVAL;
            else if (operation == 5) {
                if (linkat(fd, leaf, destination, target, 0)) error = errno;
            } else if (operation == 11) {
                char link_text[4097];
                error = path_copy(path, path_length, link_text);
                if (!error && symlinkat(link_text, destination, target)) error = errno;
            } else if (operation == 12) {
                if (renameat(fd, leaf, destination, target)) error = errno;
            } else {
#ifdef __APPLE__
                if (renameatx_np(fd, leaf, destination, target, RENAME_EXCL)) error = errno;
#elif defined(__linux__)
                if (syscall(SYS_renameat2, fd, leaf, destination, target, RENAME_NOREPLACE)) error = errno;
#else
                error = ENOTSUP;
#endif
            }
            if (!error && fsync(destination)) error = errno;
            if (close(destination) && !error) error = errno;
        }
    } else if (operation == 6 || operation == 7) {
        if (unlinkat(fd, leaf, operation == 7 ? AT_REMOVEDIR : 0)) error = errno;
    } else error = EINVAL;
    if (close(fd) && !error) error = errno;
    return error;
}

/* Held descriptors serialize callers and are released by the OS on process exit.
 * Keep the lock file in place: deleting it would allow two independent locks. */
int64_t ito_lock(const uint8_t *path, int64_t length) {
    char buffer[4097], *leaf = NULL;
    int error = path_copy(path, length, buffer);
    if (error) return -error;
    int parent = parent_fd(buffer, &leaf, 0);
    if (parent < 0) return parent;
    int fd = openat(parent, leaf, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK, 0600);
    error = errno;
    close(parent);
    if (fd < 0) return -error;
    struct stat info;
    if (fstat(fd, &info)) error = errno;
    else if (!S_ISREG(info.st_mode)) error = EINVAL;
    else if (flock(fd, LOCK_EX | LOCK_NB)) error = errno;
    else return fd;
    close(fd);
    return -error;
}

int64_t ito_unlock(int64_t descriptor) {
    if (descriptor < 0 || descriptor > INT32_MAX) return EINVAL;
    return close((int)descriptor) ? errno : 0;
}

/* Resolve configured roots through the OS; no package semantics here. */
int64_t ito_canonical(const uint8_t *path, int64_t length, uint8_t *output, int64_t capacity) {
    char buffer[4097];
    if (length < 1 || length > 4096 || memchr(path, 0, (size_t)length)) return -EINVAL;
    memcpy(buffer, path, (size_t)length);
    buffer[length] = 0;
    char *resolved = realpath(buffer, NULL);
    if (!resolved) return -errno;
    size_t size = strlen(resolved);
    if (capacity < 0 || size > (size_t)capacity) { free(resolved); return -ENAMETOOLONG; }
    memcpy(output, resolved, size);
    free(resolved);
    return (int64_t)size;
}

/* Replace Ito after compilation: app PID/signals/exit status belong to the app. */
int64_t ito_exec(const uint8_t *path, int64_t length, const uint8_t *directory, int64_t directory_length) {
    char executable[4097], cwd[4097];
    int error = path_copy(path, length, executable);
    if (error) return error;
    if (directory_length == 1 && directory[0] == '/') strcpy(cwd, "/");
    else {
        error = path_copy(directory, directory_length, cwd);
        if (error) return error;
    }
    if (chdir(cwd)) return errno;
    execl(executable, executable, (char *)NULL);
    return errno;
}

int64_t ito_executable(uint8_t *output, int64_t capacity) {
    char path[4097];
#ifdef __APPLE__
    uint32_t size = sizeof path;
    if (_NSGetExecutablePath(path, &size)) return -ENAMETOOLONG;
#elif defined(__linux__)
    ssize_t size = readlink("/proc/self/exe", path, sizeof path - 1);
    if (size < 0) return -errno;
    if ((size_t)size >= sizeof path - 1) return -ENAMETOOLONG;
    path[size] = 0;
#else
    return -ENOTSUP;
#endif
    return ito_canonical((const uint8_t *)path, (int64_t)strlen(path), output, capacity);
}

int64_t ito_readlink(const uint8_t *path, int64_t length, uint8_t *output, int64_t capacity) {
    char buffer[4097], *leaf = NULL;
    int error = path_copy(path, length, buffer);
    if (error || capacity < 1 || capacity > 4096) return -(error ? error : EINVAL);
    int parent = parent_fd(buffer, &leaf, 0);
    if (parent < 0) return parent;
    ssize_t count = readlinkat(parent, leaf, (char *)output, (size_t)capacity);
    error = errno;
    if (close(parent) && count >= 0) return -errno;
    if (count < 0) return -error;
    if (count == capacity) return -ENAMETOOLONG;
    return count;
}
