#!/usr/bin/env bash
set -euo pipefail
ITO_FIXTURE_ROOT="$1"
mkdir -p "$ITO_FIXTURE_ROOT/base/src/ignored"
cat > "$ITO_FIXTURE_ROOT/base/package.json" <<'JSON'
{"name":"fixture","version":"0.1.0","neri":{"units":{"core":{"sources":["src"],"exclude":["src/ignored"]}}}}
JSON
printf 'namespace fixture\n' > "$ITO_FIXTURE_ROOT/base/src/z.hk"
printf '# earlier file\n' > "$ITO_FIXTURE_ROOT/base/src/a.hk"
# Create in a different order and ignore timestamps and unrelated files.
mkdir -p "$ITO_FIXTURE_ROOT/relocated/src"
cp "$ITO_FIXTURE_ROOT/base/src/a.hk" "$ITO_FIXTURE_ROOT/relocated/src/a.hk"
cp "$ITO_FIXTURE_ROOT/base/package.json" "$ITO_FIXTURE_ROOT/relocated/package.json"
cp "$ITO_FIXTURE_ROOT/base/src/z.hk" "$ITO_FIXTURE_ROOT/relocated/src/z.hk"
touch -t 202001010000 "$ITO_FIXTURE_ROOT/relocated/src/a.hk"
printf 'not included' > "$ITO_FIXTURE_ROOT/relocated/README.md"
for name in changed renamed metadata excluded link parent-link invalid-utf8 oversized missing invalid-manifest many; do
  cp -R "$ITO_FIXTURE_ROOT/base" "$ITO_FIXTURE_ROOT/$name"
done
printf '# changed\n' >> "$ITO_FIXTURE_ROOT/changed/src/a.hk"
mv "$ITO_FIXTURE_ROOT/renamed/src/a.hk" "$ITO_FIXTURE_ROOT/renamed/src/b.hk"
printf ' ' >> "$ITO_FIXTURE_ROOT/metadata/package.json"
printf '\377' > "$ITO_FIXTURE_ROOT/excluded/src/ignored/bad.hk"
ln -s "$ITO_FIXTURE_ROOT/base/src/z.hk" "$ITO_FIXTURE_ROOT/link/src/link.hk"
rm "$ITO_FIXTURE_ROOT/parent-link/src/a.hk" "$ITO_FIXTURE_ROOT/parent-link/src/z.hk"
rmdir "$ITO_FIXTURE_ROOT/parent-link/src/ignored" "$ITO_FIXTURE_ROOT/parent-link/src"
ln -s "$ITO_FIXTURE_ROOT/base/src" "$ITO_FIXTURE_ROOT/parent-link/src"
ln -s "$ITO_FIXTURE_ROOT/base" "$ITO_FIXTURE_ROOT/root-link"
printf '\377' > "$ITO_FIXTURE_ROOT/invalid-utf8/src/a.hk"
dd if=/dev/zero of="$ITO_FIXTURE_ROOT/oversized/src/big.hk" bs=1048576 count=5 2>/dev/null
rm -r "$ITO_FIXTURE_ROOT/missing/src"
printf '{}' > "$ITO_FIXTURE_ROOT/invalid-manifest/package.json"
for ((i=0; i<4097; i++)); do
  : > "$ITO_FIXTURE_ROOT/many/src/f$i.hk"
done
