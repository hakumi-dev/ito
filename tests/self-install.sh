#!/usr/bin/env bash
set -euo pipefail
ITO_EXE="$1"
ITO_CASE="$2"
ITO_MODE="$3"
mkdir -p "$ITO_CASE/bootstrap"
ITO_CASE="$(cd "$ITO_CASE" && pwd -P)"
export ITO_HOME="$ITO_CASE/tool storage"
ITO_BIN="$ITO_CASE/bin directory"
ITO_BOOTSTRAP="$ITO_CASE/bootstrap/ito"
cp "$ITO_EXE" "$ITO_BOOTSTRAP"
chmod 755 "$ITO_BOOTSTRAP"
(cd "$ITO_CASE" && "$ITO_BOOTSTRAP" self-install "$ITO_BIN")
[[ -L "$ITO_BIN/ito" && -x "$ITO_BIN/ito" ]]
cmp "$ITO_EXE" "$ITO_BIN/ito"
[[ ! "$ITO_BOOTSTRAP" -ef "$ITO_BIN/ito" ]]
ITO_TARGET="$(readlink "$ITO_BIN/ito")"
"$ITO_BIN/ito" self-install "$ITO_BIN"
[[ "$(readlink "$ITO_BIN/ito")" == "$ITO_TARGET" ]]
rm "$ITO_BOOTSTRAP"
[[ "$(env -u NERI_LIBRARY_PATH "$ITO_BIN/ito" --version)" == 'ito 0.1.0-dev' ]]
ITO_APP="$ITO_CASE/installed-$ITO_MODE"
(cd "$ITO_CASE" && env -u NERI_LIBRARY_PATH "$ITO_BIN/ito" --project "$ITO_APP" init "installed-$ITO_MODE")
cat > "$ITO_APP/main.hk" <<'NERI'
use console

def main(): Void
  console::println("Independently installed Ito passed")
end
NERI
env -u NERI_LIBRARY_PATH "$ITO_BIN/ito" --project "$ITO_APP" run | rg -F 'Independently installed Ito passed'
mkdir -p "$ITO_CASE/occupied-$ITO_MODE" "$ITO_CASE/unmanaged-$ITO_MODE"
printf 'existing user file' > "$ITO_CASE/occupied-$ITO_MODE/ito"
if "$ITO_EXE" self-install "$ITO_CASE/occupied-$ITO_MODE" > "$ITO_CASE/occupied.log" 2>&1; then
  echo 'Installer overwrote an unrelated file' >&2
  exit 1
fi
[[ "$(cat "$ITO_CASE/occupied-$ITO_MODE/ito")" == 'existing user file' ]]
ln -s "$ITO_CASE/occupied-$ITO_MODE/ito" "$ITO_CASE/unmanaged-$ITO_MODE/ito"
if "$ITO_EXE" self-install "$ITO_CASE/unmanaged-$ITO_MODE" > "$ITO_CASE/unmanaged.log" 2>&1; then
  echo 'Installer overwrote an unrelated symlink' >&2
  exit 1
fi
[[ "$(readlink "$ITO_CASE/unmanaged-$ITO_MODE/ito")" == "$ITO_CASE/occupied-$ITO_MODE/ito" ]]
# Reinstallation restores permissions while keeping verified executable bytes.
chmod 600 "$ITO_TARGET"
"$ITO_EXE" self-install "$ITO_BIN"
[[ -x "$ITO_BIN/ito" ]]
printf 'tampered' >> "$ITO_TARGET"
if "$ITO_EXE" self-install "$ITO_BIN" > "$ITO_CASE/corrupt.log" 2>&1; then
  echo 'Installer accepted a corrupt content-addressed executable' >&2
  exit 1
fi
rg -F 'installed executable is missing or corrupt' "$ITO_CASE/corrupt.log" >/dev/null
[[ "$(readlink "$ITO_BIN/ito")" == "$ITO_TARGET" ]]
echo 'Ito independent installation contracts passed'
