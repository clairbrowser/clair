#!/bin/bash
# Tests for retrieve_and_unpack_resource.py's refusal of downloads that declare
# no hash, and for the repository's downloads*.ini declaring one for each
# download. Run directly: ./engine/steps/retrieve-and-unpack-resource.test.sh
#
# The script is copied beside a stub of ungoogled-chromium's utils with the same
# interface, so the test runs without the submodule and downloads nothing.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$script_dir/../.." && pwd)"

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

root="$workdir/root"
utils="$root/ungoogled-chromium/utils"
mkdir -p "$utils"
mkdir -p "$root/engine"
cp "$repo/engine/retrieve_and_unpack_resource.py" "$root/engine/"
cat >"$utils/_common.py" <<'EOF'
import logging


def get_logger():
    return logging.getLogger('test')
EOF
cat >"$utils/downloads.py" <<'EOF'
import configparser
import os
from pathlib import Path


class HashMismatchError(Exception):
    pass


class DownloadInfo:
    _hashes = ('md5', 'sha1', 'sha256', 'sha512')

    class _Properties:
        def __init__(self, section):
            self._section = section

        def __getattr__(self, name):
            if name in ('download_filename', 'output_path'):
                return self._section.get(name)
            if name == 'hashes':
                return {key: self._section.get(key)
                        for key in (*DownloadInfo._hashes, 'hash_url')
                        if self._section.get(key)}
            raise AttributeError(name)

    def __init__(self, ini_paths):
        self._sections = []
        for path in ini_paths:
            data = configparser.ConfigParser(defaults={'_chromium_version': '1'})
            data.read(path)
            self._sections += [(name, data[name]) for name in data.sections()]

    def properties_iter(self):
        for name, section in self._sections:
            yield name, self._Properties(section)


def _record(call):
    with open(os.environ['DOWNLOAD_CALLS'], 'a') as calls:
        calls.write(call + '\n')


def retrieve_downloads(*_args, **_kwargs):
    _record('retrieve')


def check_downloads(*_args, **_kwargs):
    _record('check')


def unpack_downloads(*_args, **_kwargs):
    _record('unpack')
EOF

calls="$workdir/calls"
# Prints "retrieved" or the error, so each case can check both.
retrieve() {
  : >"$calls"
  DOWNLOAD_CALLS="$calls" python3 - "$root/engine/retrieve_and_unpack_resource.py" "$1" <<'EOF' 2>&1
import importlib.util
import sys
from pathlib import Path

spec = importlib.util.spec_from_file_location('resource', sys.argv[1])
resource = importlib.util.module_from_spec(spec)
spec.loader.exec_module(resource)
try:
    resource._retrieve_and_unpack(Path(sys.argv[2]))
    print('retrieved')
except RuntimeError as error:
    print(error)
EOF
}

cat >"$workdir/hashed.ini" <<'EOF'
[pinned]
url = https://example.invalid/pinned.tar.xz
download_filename = pinned.tar.xz
sha256 = 0000000000000000000000000000000000000000000000000000000000000000
output_path = third_party/pinned

[listed]
url = https://example.invalid/listed.tar.xz
download_filename = listed.tar.xz
hash_url = chromium|listed.hashes|https://example.invalid/listed.hashes
output_path = third_party/listed
EOF
output="$(retrieve "$workdir/hashed.ini")"
[[ "$output" == "retrieved" && "$(tr '\n' ' ' <"$calls")" == "retrieve check unpack " ]] \
  && result=pass || result=fail
check "downloads with a hash or a hash URL are retrieved, checked and unpacked" "$result"

cat >"$workdir/unhashed.ini" <<'EOF'
[pinned]
url = https://example.invalid/pinned.tar.xz
download_filename = pinned.tar.xz
sha512 = 00
output_path = third_party/pinned

[toolchain]
url = https://example.invalid/toolchain.tar.xz
download_filename = toolchain.tar.xz
output_path = third_party/toolchain
EOF
output="$(retrieve "$workdir/unhashed.ini")"
[[ "$output" == "unhashed.ini declares no hash for: toolchain" ]] && result=pass || result=fail
check "a download without a hash is refused by name" "$result"
[[ ! -s "$calls" ]] && result=pass || result=fail
check "nothing is downloaded from a file with an unhashed download" "$result"

for ini in "$repo"/engine/downloads*.ini; do
  output="$(retrieve "$ini")"
  [[ "$output" == "retrieved" ]] && result=pass || result=fail
  check "every download in $(basename "$ini") declares a hash" "$result"
  [[ "$result" == "pass" ]] || echo "         $output"
done

if ((failures > 0)); then
  echo "$failures test(s) failed"
  exit 1
fi
echo "all tests passed"
