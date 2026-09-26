#!/usr/bin/env bash
set -euo pipefail
ITO_EXE="$1"
ITO_CASE="$2"
ITO_FIXTURES="$3"
mkdir -p "$ITO_CASE"
ITO_CASE="$(cd "$ITO_CASE" && pwd -P)"
ITO_APP="$ITO_CASE/application dir"
export ITO_HOME="$ITO_CASE/storage with spaces/nested/cache"
fail() {
  local expected="$1"
  shift
  if "$ITO_EXE" "$@" > "$ITO_CASE/failure.log" 2>&1; then
    cat "$ITO_CASE/failure.log"
    echo "Expected command failure: $*" >&2
    exit 1
  fi
  if ! rg -F -- "$expected" "$ITO_CASE/failure.log" >/dev/null; then
    cat "$ITO_CASE/failure.log"
    echo "Missing error: $expected" >&2
    exit 1
  fi
}
[[ "$("$ITO_EXE" --version)" == 'ito 0.1.0-dev' ]]
fail 'unknown option' --not-an-option
fail 'unknown command' nonexistent
"$ITO_EXE" --project "$ITO_APP" init demo
cp "$ITO_APP/package.json" "$ITO_CASE/manifest.before"
fail 'already exists' --project "$ITO_APP" init demo
cmp "$ITO_APP/package.json" "$ITO_CASE/manifest.before"
"$ITO_EXE" --project "$ITO_APP" list | rg -F 'No dependencies.'
fail 'ito.lock is missing' --project "$ITO_APP" install --locked
[[ ! -f "$ITO_APP/ito.lock" ]]
cp -R "$ITO_FIXTURES/base" "$ITO_CASE/pkg"
"$ITO_EXE" --project "$ITO_APP" add ../pkg
"$ITO_EXE" --project "$ITO_APP" list | rg '^fixture 0.1.0 sha256:[0-9a-f]{64} \(direct\)$'
cp "$ITO_APP/ito.lock" "$ITO_CASE/lock.before"
printf '# edited source\n' >> "$ITO_CASE/pkg/src/a.hk"
"$ITO_EXE" --project "$ITO_APP" install --locked
cmp "$ITO_APP/ito.lock" "$ITO_CASE/lock.before"
mv "$ITO_CASE/pkg" "$ITO_CASE/hidden-pkg"
"$ITO_EXE" --project "$ITO_APP" install --locked
ITO_SAVED_HOME="$ITO_HOME"
export ITO_HOME="$ITO_CASE/empty-cache"
fail 'locked source is unavailable or changed' --project "$ITO_APP" install --locked
cmp "$ITO_APP/ito.lock" "$ITO_CASE/lock.before"
mv "$ITO_CASE/hidden-pkg" "$ITO_CASE/pkg"
fail 'locked source is unavailable or changed' --project "$ITO_APP" install --locked
export ITO_HOME="$ITO_SAVED_HOME"
"$ITO_EXE" --project "$ITO_APP" update fixture
if cmp -s "$ITO_APP/ito.lock" "$ITO_CASE/lock.before"; then
  echo 'Explicit update did not change the lock' >&2
  exit 1
fi
cp "$ITO_APP/ito.lock" "$ITO_CASE/lock.before"
cp "$ITO_APP/package.json" "$ITO_CASE/manifest.before"
fail 'unknown direct dependency' --project "$ITO_APP" update absent
fail 'cannot add package' --project "$ITO_APP" add ../absent
cmp "$ITO_APP/ito.lock" "$ITO_CASE/lock.before"
cmp "$ITO_APP/package.json" "$ITO_CASE/manifest.before"
ln -s "$ITO_APP" "$ITO_CASE/app-alias"
"$ITO_EXE" --project "$ITO_CASE/app-alias" install --locked
cmp "$ITO_APP/ito.lock" "$ITO_CASE/lock.before"
# Malformed locks block installation; explicit full update can regenerate them.
printf '{}' > "$ITO_APP/ito.lock"
fail 'unsupported or invalid ito.lock version' --project "$ITO_APP" install
"$ITO_EXE" --project "$ITO_APP" update
cmp "$ITO_APP/ito.lock" "$ITO_CASE/lock.before"
while IFS= read -r cached; do
  printf '# tampered cache\n' > "$cached"
done < <(rg --files "$ITO_HOME/packages" -g a.hk)
fail 'cache integrity check failed' --project "$ITO_APP" install --locked
cmp "$ITO_APP/ito.lock" "$ITO_CASE/lock.before"
"$ITO_EXE" --project "$ITO_APP" remove fixture
"$ITO_EXE" --project "$ITO_APP" list | rg -F 'No dependencies.'
"$ITO_EXE" --project "$ITO_APP" install --locked
fail 'name of a direct dependency' --project "$ITO_APP" remove fixture
# Loading malformed application manifests never replaces them.
printf '{broken' > "$ITO_APP/package.json"
cp "$ITO_APP/package.json" "$ITO_CASE/manifest.before"
fail 'invalid JSON in package.json' --project "$ITO_APP" install
cmp "$ITO_APP/package.json" "$ITO_CASE/manifest.before"
echo 'Ito package CLI contracts passed'
