#!/usr/bin/env bash
set -euo pipefail
ITO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
mkdir -p "$ITO_ROOT/build"
cc -std=c11 -Wall -Wextra -Werror -c "$ITO_ROOT/native/fs.c" -o "$ITO_ROOT/build/fs.o"
ar rcs "$ITO_ROOT/build/libito-os.a" "$ITO_ROOT/build/fs.o"
export NERI_LIBRARY_PATH="$ITO_ROOT/build${NERI_LIBRARY_PATH:+:$NERI_LIBRARY_PATH}"
"${NERI:-neri}" build "$ITO_ROOT"/src/*.hk "$ITO_ROOT/main.hk" "$@" --output "$ITO_ROOT/build/ito"
