# Ito

Ito is a local source-package manager for Neri. The manager is implemented in
Neri; `native/fs.c` supplies filesystem and process primitives. Packages come
from local paths. There is no registry or network resolver.

## Build and verify

Requires Neri, a C compiler (`cc`), `ar`, Bash and ripgrep. `NERI` selects the
compiler executable (default `neri`). From this checkout:

| Operation | Command |
| --- | --- |
| Build the native executable | `scripts/build.sh --release` |
| Install that executable | `./build/ito self-install` |
| Command reference | `ito --help` |
| Validate Debug and Release contracts | `scripts/test.sh` |
| Validate one configuration | `scripts/test.sh debug` or `scripts/test.sh release` |

`self-install` stores an executable under `~/.ito/tools/ito/<sha256>/ito` and
activates `~/.local/bin/ito`; put `~/.local/bin` on `PATH`. `ITO_HOME` changes
the shared storage root. The installed executable is independent of this
checkout and its build directory.

## Application commands

An app has `main.hk`, optional `app/` and optional `tests/`. Set `neri.entry`,
`neri.sources` or `neri.tests` in `package.json` to override the defaults.
`init` creates the package declaration only; it does not generate app source.

| Operation | Command |
| --- | --- |
| Create a declaration | `ito --project ../my-app init my-app` |
| Add a local dependency | `ito --project ../my-app add ../sumi` |
| Restore the pinned graph | `ito --project ../my-app install --locked` |
| Test | `ito --project ../my-app test` |
| Build | `ito --project ../my-app build --release` |
| Run | `ito --project ../my-app run` |

`--project` defaults to the current directory. Dependency paths are relative
to the declaring package. Commit `package.json` and generated `ito.lock`; ignore
`.neri/` and `build/` in app repositories.

`install` resolves a lock only if none exists. Existing locks pin exact source
instances for build/run/test; `install --locked` requires a current lock. Use
`update` to refresh all direct roots, or `update <name>` to refresh one root's
transitive closure while retaining the others. `add`/`remove` preserve
unrelated locked packages. `list` reports the lock without resolving.

`prepare` restores locked dependencies and generates app source views and
`.neri/ito/manifest.json`; it does not compile. `build`, `run` and `test` restore
the lock, verify generated views and invoke `NERI`. They accept `--release` and
`--timings`; `build` also accepts `--output <path>`. Outputs default to
`build/application` and `build/tests`. `run`/`test` execute from the app
directory and release the project lock before transferring control.

Ito snapshots raw `package.json` plus selected UTF-8 `.hk` files into
`~/.ito/packages/<name>/<version>/<sha256>/`; cache instances are immutable.
Missing snapshots can be restored only from identical source bytes. A lock
provides integrity checking, not publisher authentication, and does not pin the
compiler or promise bit-reproducible binaries. See [design contracts](docs/DESIGN.md)
for the package schema, resolution and storage invariants.

Applications using Neri Data can declare `neri.dataMappings` as an array of
package-local mapping paths, for example `["data/mapping.json"]`. `prepare`,
`build`, `run` and `test` invoke `neri-data-generate --ensure` for each mapping
under the application lock before capturing sources. Include the entities and
generated output directories in `neri.sources`. Current generated revisions are
reused; changed inputs regenerate their owned output. Generation failures stop
preparation before compilation. `NERI_DATA_GENERATE` selects the generator
executable; select the generator from the same release as `NERI` and the Data
libraries.
