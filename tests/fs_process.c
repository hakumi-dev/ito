#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>
extern int64_t ito_lock(const uint8_t *, int64_t);
extern int64_t ito_unlock(int64_t);
static void wait_ok(pid_t child) {
    int status;
    assert(waitpid(child, &status, 0) == child);
    assert(WIFEXITED(status) && WEXITSTATUS(status) == 0);
}
int main(int argc, char **argv) {
    assert(argc == 2);
    const uint8_t *path = (const uint8_t *)argv[1];
    int64_t length = (int64_t)strlen(argv[1]);
    int64_t held = ito_lock(path, length);
    assert(held >= 0);
    pid_t child = fork();
    assert(child >= 0);
    if (!child) {
        assert(ito_unlock(held) == 0); /* Drop the inherited parent descriptor. */
        _exit(ito_lock(path, length) < 0 ? 0 : 1);
    }
    wait_ok(child);
    assert(ito_unlock(held) == 0);
    child = fork();
    assert(child >= 0);
    if (!child) _exit(ito_lock(path, length) >= 0 ? 0 : 1);
    wait_ok(child); /* Process exit must release its lock without explicit cleanup. */
    held = ito_lock(path, length);
    assert(held >= 0);
    assert(ito_unlock(held) == 0);
    puts("Ito process lock contracts passed");
    return 0;
}
