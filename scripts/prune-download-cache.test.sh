#!/bin/bash
# Tests for scripts/prune-download-cache.py, which build.sh's prepare stage runs
# to delete old downloads from build/download_cache. Run directly:
# ./scripts/prune-download-cache.test.sh
#
# ungoogled-chromium's downloads.py is replaced by a stub with the same
# DownloadInfo interface, so the test runs without the submodule.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
prune="$script_dir/prune-download-cache.py"

failures=0
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

check() {
  local description="$1" condition="$2"
  if [[ "$condition" == "pass" ]]; then
    echo "ok       $description"
  else
    echo "FAIL     $description"
    failures=$((failures + 1))
  fi
}

utils="$workdir/utils"
mkdir -p "$utils"
cat >"$utils/downloads.py" <<'EOF'
import configparser


class DownloadInfo:
    hash_url_delimiter = '|'
    _ini_vars = {'_chromium_version': '157.0.8103.78'}

    class _Properties:
        def __init__(self, section):
            self._section = section

        def __getattr__(self, name):
            if name == 'download_filename':
                return self._section.get(name)
            if name == 'hashes':
                value = self._section.get('hash_url')
                return {'hash_url': value.split('|')} if value else {}
            raise AttributeError(name)

    def __init__(self, ini_paths):
        self._sections = []
        for path in ini_paths:
            data = configparser.ConfigParser(defaults=self._ini_vars)
            data.read(path)
            self._sections += [(name, data[name]) for name in data.sections()]

    def properties_iter(self):
        for name, section in self._sections:
            yield name, self._Properties(section)
EOF

cat >"$workdir/downloads.ini" <<'EOF'
[chromium]
url = https://example.invalid/chromium-%(_chromium_version)s-lite.tar.xz
download_filename = chromium-%(_chromium_version)s-lite.tar.xz
hash_url = chromium|chromium-%(_chromium_version)s-lite.tar.xz.hashes|https://example.invalid/x.hashes
EOF
cat >"$workdir/downloads-arm64.ini" <<'EOF'
[rust]
version = 2026-09-08
url = https://example.invalid/%(version)s/rust.tar.xz
download_filename = rust-nightly-%(version)s-aarch64-apple-darwin.tar.xz
EOF

cache="$workdir/cache"
mkdir -p "$cache/resource_stamps"
echo state >"$cache/resource_stamps/chromium-clone.json"
for name in chromium-157.0.8103.78-lite.tar.xz chromium-157.0.8103.78-lite.tar.xz.hashes \
    chromium-156.0.8078.79-lite.tar.xz chromium-156.0.8078.79-lite.tar.xz.hashes \
    rust-nightly-2026-09-08-aarch64-apple-darwin.tar.xz \
    rust-nightly-2026-09-10-aarch64-apple-darwin.tar.xz \
    rust-nightly-2026-09-10-aarch64-apple-darwin.tar.xz.partial; do
  echo data >"$cache/$name"
done

output="$(python3 "$prune" "$utils" "$cache" "$workdir/downloads.ini" "$workdir/downloads-arm64.ini" 2>&1)"
status=$?
[[ $status -eq 0 ]] && check "exits successfully" pass || check "exits successfully ($status: $output)" fail

kept=1
for name in chromium-157.0.8103.78-lite.tar.xz chromium-157.0.8103.78-lite.tar.xz.hashes \
    rust-nightly-2026-09-08-aarch64-apple-darwin.tar.xz resource_stamps/chromium-clone.json; do
  [[ -f "$cache/$name" ]] || kept=0
done
[[ $kept -eq 1 ]] && check "keeps the named downloads, their hash files and resource_stamps" pass ||
  check "keeps the named downloads, their hash files and resource_stamps" fail

deleted=1
for name in chromium-156.0.8078.79-lite.tar.xz chromium-156.0.8078.79-lite.tar.xz.hashes \
    rust-nightly-2026-09-10-aarch64-apple-darwin.tar.xz \
    rust-nightly-2026-09-10-aarch64-apple-darwin.tar.xz.partial; do
  [[ -e "$cache/$name" ]] && deleted=0
done
[[ $deleted -eq 1 ]] && check "deletes the old versions and partial downloads" pass ||
  check "deletes the old versions and partial downloads" fail

[[ "$output" == *"Deleting rust-nightly-2026-09-10-aarch64-apple-darwin.tar.xz from the download cache"* ]] &&
  check "names each deleted file" pass || check "names each deleted file" fail

if python3 "$prune" "$utils" "$workdir/missing" "$workdir/downloads.ini" >/dev/null 2>&1; then
  check "does nothing when the cache doesn't exist" pass
else
  check "does nothing when the cache doesn't exist" fail
fi

echo data >"$cache/kept-by-error"
if python3 "$prune" "$utils" "$cache" "$workdir/missing.ini" >/dev/null 2>&1 || [[ ! -f "$cache/kept-by-error" ]]; then
  check "rejects a missing INI without deleting anything" fail
else
  check "rejects a missing INI without deleting anything" pass
fi

if python3 "$prune" "$utils" "$cache" >/dev/null 2>&1; then
  check "rejects a missing argument" fail
else
  check "rejects a missing argument" pass
fi

echo
if [[ $failures -gt 0 ]]; then
  echo "$failures test(s) failed"
  exit 1
fi
echo "All tests passed"
