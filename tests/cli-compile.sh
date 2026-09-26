#!/usr/bin/env bash
set -euo pipefail
ITO_EXE="$1"
ITO_CASE="$2"
ITO_SOURCES="$3"
ITO_MODE="$4"
mkdir -p "$ITO_CASE"
ITO_CASE="$(cd "$ITO_CASE" && pwd -P)"
ITO_APP="$ITO_CASE/application dir"
export ITO_HOME="$ITO_CASE/cache"
export ITO_TEST_EXECUTABLE="$ITO_EXE"
export ITO_TEST_ENV='environment passed'
cp -R "$ITO_SOURCES/leaf" "$ITO_CASE/leaf"
cp -R "$ITO_SOURCES/middle" "$ITO_CASE/middle"
"$ITO_EXE" --project "$ITO_APP" init demo
"$ITO_EXE" --project "$ITO_APP" add ../middle
mkdir -p "$ITO_APP/tests"
printf 'working directory passed' > "$ITO_APP/marker.txt"
cat > "$ITO_APP/main.hk" <<'NERI'
use middle
use host
use test
use console

def main(): Void
  test::assertEqual(middle::value(), 12)
  let marker = host::readText("marker.txt")
  test::assertTrue(marker != null)
  if marker != null
    test::assertEqual(marker, "working directory passed")
  end
  let environment = host::environment("ITO_TEST_ENV")
  test::assertTrue(environment != null)
  if environment != null
    test::assertEqual(environment, "environment passed")
  end
  let manager = host::environment("ITO_TEST_EXECUTABLE")
  test::assertTrue(manager != null)
  if manager != null
    let status = host::run(manager, ["list"])
    test::assertTrue(status != null)
    if status != null
      test::assertEqual(status, 0)
    end
  end
  console::println("Ito compiled execution passed")
end
NERI
cp "$ITO_APP/main.hk" "$ITO_APP/tests/contracts.hk"
cp "$ITO_APP/ito.lock" "$ITO_CASE/original.lock"
# Preparation refreshes source manifests without invoking a compiler or creating
# an executable. It preserves locked dependencies and observes source edits.
NERI=/usr/bin/false "$ITO_EXE" --project "$ITO_APP" prepare
[[ -f "$ITO_APP/.neri/ito/manifest.json" && ! -e "$ITO_APP/build/application" ]]
cp "$ITO_APP/.neri/ito/manifest.json" "$ITO_CASE/prepared.json"
if [[ "$(uname -s)" == Darwin ]]; then
  manifest_identity() { stat -f '%d:%i:%m' "$1"; }
else
  manifest_identity() { stat -c '%d:%i:%Y' "$1"; }
fi
touch -t 200001010000 "$ITO_APP/.neri/ito/manifest.json"
manifest_before="$(manifest_identity "$ITO_APP/.neri/ito/manifest.json")"
NERI=/usr/bin/false "$ITO_EXE" --project "$ITO_APP" prepare
manifest_after="$(manifest_identity "$ITO_APP/.neri/ito/manifest.json")"
[[ "$manifest_before" == "$manifest_after" ]] || {
  echo 'Unchanged preparation replaced the generated compiler manifest' >&2
  exit 1
}
cmp "$ITO_APP/.neri/ito/manifest.json" "$ITO_CASE/prepared.json"
printf '\n# Updated source snapshot\n' >> "$ITO_APP/main.hk"
NERI=/usr/bin/false "$ITO_EXE" --project "$ITO_APP" prepare
if cmp -s "$ITO_APP/.neri/ito/manifest.json" "$ITO_CASE/prepared.json"; then
  echo 'Preparation did not refresh changed application sources' >&2
  exit 1
fi
cmp "$ITO_APP/ito.lock" "$ITO_CASE/original.lock"
for option in --release --output --timings; do
  if "$ITO_EXE" --project "$ITO_APP" prepare "$option" ignored > "$ITO_CASE/prepare-error.log" 2>&1; then
    echo 'Preparation accepted a compiler-only option' >&2
    exit 1
  fi
done
set --
if [[ "$ITO_MODE" == release ]]; then set -- --release; fi
"$ITO_EXE" --project "$ITO_APP" build "$@" --output 'custom output/program'
[[ -x "$ITO_APP/custom output/program" ]]
"$ITO_EXE" --project "$ITO_APP" run "$@" | rg -F 'Ito compiled execution passed'
"$ITO_EXE" --project "$ITO_APP" test "$@" | rg -F 'Ito compiled execution passed'
cmp "$ITO_APP/ito.lock" "$ITO_CASE/original.lock"
# Transitive origin edits remain invisible until an explicit update.
sed -i '' 's/return 7/return 9/' "$ITO_CASE/leaf/src/library.hk"
"$ITO_EXE" --project "$ITO_APP" run "$@" | rg -F 'Ito compiled execution passed'
cmp "$ITO_APP/ito.lock" "$ITO_CASE/original.lock"
"$ITO_EXE" --project "$ITO_APP" update middle
sed -i '' 's/value(), 12/value(), 14/' "$ITO_APP/main.hk" "$ITO_APP/tests/contracts.hk"
"$ITO_EXE" --project "$ITO_APP" run "$@" | rg -F 'Ito compiled execution passed'
"$ITO_EXE" --project "$ITO_APP" test "$@" | rg -F 'Ito compiled execution passed'
# Compiler selection reaches the actual compiler, without a shell command string.
export ITO_REAL_COMPILER="${NERI:-neri}"
export ITO_COMPILER_LOG="$ITO_CASE/compiler.log"
cat > "$ITO_CASE/compiler.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" > "$ITO_COMPILER_LOG"
exec "$ITO_REAL_COMPILER" "$@"
SH
chmod +x "$ITO_CASE/compiler.sh"
NERI="$ITO_CASE/compiler.sh" "$ITO_EXE" --project "$ITO_APP" build "$@" --timings
rg -F -- '--project' "$ITO_COMPILER_LOG" >/dev/null
rg -F -- '--timings' "$ITO_COMPILER_LOG" >/dev/null
# Exec replacement preserves the application exit status.
cat > "$ITO_APP/main.hk" <<'NERI'
use host

def main(): Void
  host::exit(23)
end
NERI
ITO_STATUS=0
"$ITO_EXE" --project "$ITO_APP" run "$@" > "$ITO_CASE/exit.log" 2>&1 || ITO_STATUS=$?
[[ "$ITO_STATUS" == 23 ]]
printf 'invalid source' > "$ITO_APP/main.hk"
if "$ITO_EXE" --project "$ITO_APP" run "$@" > "$ITO_CASE/error.log" 2>&1; then
  echo 'Invalid source unexpectedly ran' >&2
  exit 1
fi
rg -F 'Neri compilation failed' "$ITO_CASE/error.log" >/dev/null
# Empty dependency graphs also compile through generated manifests.
ITO_PLAIN="$ITO_CASE/plain"
"$ITO_EXE" --project "$ITO_PLAIN" init plain
cat > "$ITO_PLAIN/main.hk" <<'NERI'
use console

def main(): Void
  console::println("Plain application passed")
end
NERI
"$ITO_EXE" --project "$ITO_PLAIN" run "$@" | rg -F 'Plain application passed'
if "$ITO_EXE" --project "$ITO_PLAIN" test "$@" > "$ITO_CASE/no-tests.log" 2>&1; then
  echo 'Missing tests unexpectedly succeeded' >&2
  exit 1
fi
rg -F 'no test sources' "$ITO_CASE/no-tests.log" >/dev/null
[[ ! -d "$ITO_APP/vendor" ]]
[[ ! -f "$ITO_APP/neri.json" ]]
[[ -f "$ITO_APP/.neri/ito/manifest.json" ]]
echo 'Ito compiler CLI contracts passed'
