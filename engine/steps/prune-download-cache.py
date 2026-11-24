#!/usr/bin/env python3
"""Delete the files in build/download_cache that no downloads INI names.

Each engine update changes some download versions (the Rust nightly, LLVM,
Node.js, the Chromium archive), and the old archives would otherwise stay in
the cache for good. Run by build.sh's prepare stage once the current resources
are retrieved:

    prune-download-cache.py <ungoogled utils dir> <cache dir> <downloads.ini>...

Keeps every file an INI names as its download_filename or as the hash file of
its hash_url, and every directory (resource_stamps holds the clone state).
Parses the INIs with ungoogled-chromium's own DownloadInfo, so the names match
the ones the downloader writes.
"""

import sys
from pathlib import Path


def kept_names(download_info):
    names = set()
    for _, properties in download_info.properties_iter():
        names.add(properties.download_filename)
        hash_url = properties.hashes.get('hash_url')
        if hash_url:
            # hash_url is processor|hash file name|URL.
            names.add(hash_url[1])
    return names


def main(argv):
    if len(argv) < 4:
        print(f'usage: {argv[0]} <utils dir> <cache dir> <downloads.ini>...', file=sys.stderr)
        return 2
    utils_dir, cache_dir = Path(argv[1]), Path(argv[2])
    ini_paths = [Path(path) for path in argv[3:]]
    for ini_path in ini_paths:
        if not ini_path.is_file():
            print(f'not a file: {ini_path}', file=sys.stderr)
            return 1
    if not cache_dir.is_dir():
        return 0

    sys.path.insert(0, str(utils_dir))
    from downloads import DownloadInfo  # pylint: disable=import-outside-toplevel

    keep = kept_names(DownloadInfo(ini_paths))
    freed = 0
    for entry in sorted(cache_dir.iterdir()):
        if entry.is_dir() or entry.name in keep:
            continue
        size = entry.lstat().st_size
        print(f'Deleting {entry.name} from the download cache ({size // 2**20} MB): '
              'no downloads INI names it')
        entry.unlink()
        freed += size
    if freed:
        print(f'Freed {freed // 2**20} MB in the download cache')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
