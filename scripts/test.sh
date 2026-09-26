#!/usr/bin/env bash
set -euo pipefail
ITO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
ITO_WORK="$(mktemp -d)"
ITO_WORK="$(cd "$ITO_WORK" && pwd -P)"
trap 'rm -r -- "$ITO_WORK"' EXIT
cc -std=c11 -Wall -Wextra -Werror -c "$ITO_ROOT/native/fs.c" -o "$ITO_WORK/fs.o"
ar rcs "$ITO_WORK/libito-os.a" "$ITO_WORK/fs.o"
cc -std=c11 -Wall -Wextra -Werror "$ITO_ROOT/tests/fs_process.c" "$ITO_WORK/fs.o" -o "$ITO_WORK/fs-process"
"$ITO_WORK/fs-process" "$ITO_WORK/process.lock"
export NERI_LIBRARY_PATH="$ITO_WORK${NERI_LIBRARY_PATH:+:$NERI_LIBRARY_PATH}"
"$ITO_ROOT/tests/snapshot-fixtures.sh" "$ITO_WORK/fixtures"
for mode in debug release; do
  set --
  if [[ "$mode" == release ]]; then set -- --release; fi
  for suite in json manifest snapshot fs store cache_race graph views; do
    "${NERI:-neri}" build "$ITO_ROOT"/src/*.hk "$ITO_ROOT/tests/$suite.hk" "$@" --output "$ITO_WORK/$suite-$mode"
    if [[ "$suite" == cache_race ]]; then
      "$ITO_WORK/$suite-$mode" "$ITO_WORK/fixtures/base" "$ITO_WORK/race-$mode" > "$ITO_WORK/race-a.log" 2>&1 &
      ITO_FIRST_PID=$!
      "$ITO_WORK/$suite-$mode" "$ITO_WORK/fixtures/base" "$ITO_WORK/race-$mode" > "$ITO_WORK/race-b.log" 2>&1 &
      ITO_SECOND_PID=$!
      ITO_RACE_STATUS=0
      wait "$ITO_FIRST_PID" || ITO_RACE_STATUS=1
      wait "$ITO_SECOND_PID" || ITO_RACE_STATUS=1
      cat "$ITO_WORK/race-a.log" "$ITO_WORK/race-b.log"
      [[ "$ITO_RACE_STATUS" == 0 ]]
      "$ITO_WORK/$suite-$mode" "$ITO_WORK/fixtures/base" "$ITO_WORK/race-$mode" check
    elif [[ "$suite" == fs || "$suite" == store || "$suite" == graph || "$suite" == views ]]; then
      "$ITO_WORK/$suite-$mode" "$ITO_WORK/fixtures" "$mode"
      if [[ "$suite" == views ]]; then
        {
          IFS= read -r ITO_CACHE_FILE
          IFS= read -r ITO_VIEW_FILE
          IFS= read -r ITO_APP_FILE
          IFS= read -r ITO_APP_VIEW_FILE
        } < "$ITO_WORK/fixtures/views-$mode/hardlinks.txt"
        [[ "$ITO_CACHE_FILE" -ef "$ITO_VIEW_FILE" ]]
        [[ ! "$ITO_APP_FILE" -ef "$ITO_APP_VIEW_FILE" ]]
      fi
    elif [[ "$suite" == snapshot ]]; then
      "$ITO_WORK/$suite-$mode" "$ITO_WORK/fixtures"
    else
      "$ITO_WORK/$suite-$mode" "$ITO_ROOT/tests/fixtures/library.json"
    fi
  done
  "${NERI:-neri}" build "$ITO_ROOT"/src/*.hk "$ITO_ROOT/main.hk" "$@" --output "$ITO_WORK/ito-$mode"
  "$ITO_ROOT/tests/cli.sh" "$ITO_WORK/ito-$mode" "$ITO_WORK/cli-$mode" "$ITO_WORK/fixtures"
  "$ITO_ROOT/tests/cli-compile.sh" "$ITO_WORK/ito-$mode" "$ITO_WORK/compile-$mode" "$ITO_WORK/fixtures/views-$mode" "$mode"
  "$ITO_ROOT/tests/self-install.sh" "$ITO_WORK/ito-$mode" "$ITO_WORK/self-install" "$mode"
done
