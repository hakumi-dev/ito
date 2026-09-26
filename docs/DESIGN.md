# Ito contracts

Contracts for package authors, resolver changes and cache safety.

## Manifests and source selection

`package.json` is maintained; `ito.lock` is generated. Package names are
lowercase letters, digits and hyphens, beginning with a letter. Versions are
`major.minor.patch` with an optional safe prerelease suffix. There are no
version ranges or remote origins. Dependency paths are relative to the package
that declares them.

Library manifests declare units, their `.hk` source roots, optional literal
file/subtree exclusions, references to other units, and optional exports.
Omitting exports exports every unit. Local references and cycles are validated
before use. Apps default to `main.hk`, `app/` and `tests/`; `neri.entry`,
`neri.sources` and `neri.tests` override those conventions. Test compilation
requires one test entry point. Selected source paths must be normalized,
package-local, regular UTF-8 `.hk` files; parent traversal and symlinks are
rejected. Neri compilation manifests must be named `manifest.json` or
`neri.json`, and unit sources must remain beneath the manifest root.

Application declaration:

```json
{"name":"my-app","version":"0.1.0","dependencies":{"sumi":{"path":"../sumi"}}}
```

Library declaration:

```json
{
  "name": "sumi",
  "version": "0.1.0-dev",
  "dependencies": {},
  "neri": {
    "units": {
      "core": {"sources": ["src/core"]},
      "http": {"sources": ["src/http"], "references": ["core"]}
    },
    "exports": ["core", "http"]
  }
}
```

Units are libraries; an explicit `kind` must be `library`. A unit can reference
exported units of its package's direct dependencies. `exclude` accepts literal
files or subtrees and applies independently to each unit.

## Lock and update behavior

The lock records schema version, root declarations and the resolved package
graph: versions, source digests, root-relative origins and dependency edges.
Serialization is deterministic for object keys; array order is preserved. One
package name can have one source identity in a graph. Resolution reports
cycles/conflicts explicitly and completes before snapshots or app files are
published.

An existing lock controls install/build/run/test. `install --locked` requires a
current lock. Restoration validates identities, edges, reachability and cycles,
then checks restored manifests. A valid cached snapshot works without its
origin; a missing one can be restored only from matching bytes. Corrupt cache
entries fail without replacement. Changed origins require an explicit update.
`update` refreshes all roots; `update <name>` refreshes that root's closure and
retains other locked closures. `add` and `remove` preserve unrelated roots and
prune unreachable packages. Resolution failures preserve caller manifests.

Do not deduplicate a resolution by source digest alone: equal package bytes at
different origins can have different relative dependency closures. Memoization
must include the resolved origin occurrence; compilation views key the complete
graph as well as package source identity.

## Identity, storage and integrity

- `~/.ito/packages/<name>/<version>/<source-sha256>/`: immutable source cache.
- `~/.ito/graphs/<graph-sha256>/packages/<name>/manifest.json`: shared compiler views.
- `.neri/ito/snapshots/<source-sha256>/`: app-owned source snapshots.
- `.neri/ito/manifest.json`: generated app compiler manifest.
- `.neri/ito/project.lock`: persistent per-project operation lock.
- `~/.ito/tools/ito/<executable-sha256>/ito`: installed manager binary.
- `~/.local/bin/ito`: activated entry point; `ITO_HOME` changes shared storage.

The source digest hashes `ito-source-snapshot-v1` and a NUL, followed by each
file sorted by UTF-8 path bytes: unsigned 64-bit big-endian path length, path,
unsigned 64-bit big-endian payload length and payload. Raw `package.json` is
included, so formatting changes affect identity. Timestamps, absolute origins,
empty directories and generated manifests are excluded.

Rooted no-follow reads capture payloads once. Stages are read back and verified
before no-replace publication. Concurrent publishers converge on a verified
instance; a process removes only its own failed stage. Package views hardlink
the shared cache and therefore require a shared filesystem. App views contain
the captured bytes in separate snapshots and use `sourceMap` to retain stable
logical project paths. Generated views must not be edited. Cache verification
does not prevent a same-user process from changing data between verification and
compilation.

SHA-256 detects inconsistency relative to the lock; it does not authenticate a
publisher or protect an attacker-modified lock. A lock pins source inputs, not
the compiler, environment or binary output, so it does not promise
bit-reproducible builds.

## Filesystem and execution guarantees

Package policy, JSON, graph resolution and compiler orchestration are Neri;
`native/fs.c` provides descriptor-relative/no-follow filesystem operations,
atomic replacement, no-replace directory publication, hardlinks, permissions,
locks and process execution. Writes stage and sync files before rename. Linux
directory publication uses `RENAME_NOREPLACE`; macOS uses `RENAME_EXCL`.
Persistent nonblocking `flock` files serialize project operations and installs
to the same bin directory; lock files are not removed.

Each JSON file replacement is atomic, but `package.json` plus `ito.lock` is not
a multi-file transaction. Interruption between the replacements can leave a
stale lock, which the next install rejects. Failed operations may leave
generated views or cache entries; they do not silently change the resolved
dependencies. `run`/`test` release the project lock, change to the app directory
and replace Ito with the program, preserving that program's environment,
signals and exit status.

Reader limit: JSON documents are at most 1 MiB and depth 64. Resolver limit:
128 units, 256 packages, depth 100 and 4096 visits. Snapshot limits: 4 MiB per
file, 32 MiB total, 4096 files, 4096 entries per directory and 65536 traversal
visits. Paths are bounded to 4096 bytes; the installed manager copy to 64 MiB.

Remote registries, Git downloads, version-range solving, install hooks, binary
library packages, cache collection, sandboxing and automatic editor/LSP
integration are outside the current contract.

## Design references

| Source | Applicable principle |
| --- | --- |
| [Nix: A Safe and Policy-Free System for Software Deployment](https://www.usenix.org/legacy/publications/library/proceedings/lisa04/tech/full_papers/dolstra/dolstra.pdf), LISA 2004 | Hash-derived paths isolate coexisting package instances. Ito hashes sources, not complete build derivations. |
| [Cargo dependency declarations](https://doc.rust-lang.org/cargo/reference/specifying-dependencies.html) and [updates](https://doc.rust-lang.org/cargo/commands/cargo-update.html) | Declarations and locked resolutions have separate roles; updates are explicit. |
| [npm lockfile](https://docs.npmjs.com/cli/v11/configuring-npm/package-lock-json/) | Record exact dependency instances and integrity values; Ito uses its own schema. |
| [Survivable Key Compromise in Software Update Systems](https://theupdateframework.io/papers/survivable-key-compromise-ccs2010.pdf), CCS 2010 | Authenticity and freshness require more than hashes; Ito's local lock provides integrity, not publisher authentication. |
