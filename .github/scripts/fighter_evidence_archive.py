#!/usr/bin/env python3
"""Build a bounded, private ZIP_STORED evidence archive, never an upload.

Screenshots and H.264 video are already compressed. Recompressing them wastes
the limited evidence-finalization budget. The caller must seal this temporary
archive and upload only the authenticated .enc output, never this plaintext.
"""
import argparse
import os
from pathlib import Path
import stat
import sys
import tempfile
import time
import zipfile


BUFFER_BYTES = 1024 * 1024
MAX_ENTRIES = 20_000
MAX_TOTAL_BYTES = 8 * 1024**3
MAX_PATH_BYTES = 1024
MAX_DEPTH = 32


def identity(info):
    return (info.st_dev, info.st_ino, info.st_mode, info.st_size,
            info.st_mtime_ns, info.st_ctime_ns)


def archive_evidence(source, destination):
    """Stream only regular entries beneath source, with no symlink traversal.

    Descriptor-relative opens keep a concurrently replaced directory/file from
    redirecting reads outside the tree. Entry count, depth, names and total bytes
    are bounded, including zipfile's in-memory central directory. An incomplete
    archive stays in a private temporary file and is never published.
    """
    source, destination = Path(source), Path(destination)
    if ".." in source.parts or ".." in destination.parts or source.is_symlink():
        raise ValueError("Unsafe evidence archive path")
    if destination.exists() or destination.is_symlink():
        raise ValueError("Evidence archive requires a new output")
    # Resolve only the parent: resolving the final component would follow a
    # root symlink substituted after the check above, defeating O_NOFOLLOW.
    source = source.parent.resolve(strict=True) / source.name
    destination = destination.parent.resolve(strict=True) / destination.name
    if destination == source or source in destination.parents:
        raise ValueError("Evidence archive must be outside its source tree")
    root_fd = os.open(source, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    temporary = None
    counts = {"entries": 0, "bytes": 0}

    def add_directory(archive, directory_fd, parent="", depth=0):
        before_directory = os.fstat(directory_fd)
        with os.scandir(directory_fd) as entries:
            for entry in entries:
                counts["entries"] += 1
                relative = parent + entry.name
                if (counts["entries"] > MAX_ENTRIES or depth >= MAX_DEPTH
                        or len(relative.encode("utf-8")) > MAX_PATH_BYTES
                        or "\\" in entry.name):
                    raise ValueError("Evidence archive exceeds its entry or path bounds")
                before = entry.stat(follow_symlinks=False)
                if not (stat.S_ISREG(before.st_mode) or stat.S_ISDIR(before.st_mode)):
                    raise ValueError("Evidence archive rejects symlinks and nonregular entries")
                directory = stat.S_ISDIR(before.st_mode)
                flags = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK
                if directory:
                    flags |= os.O_DIRECTORY
                descriptor = os.open(entry.name, flags, dir_fd=directory_fd)
                try:
                    if identity(os.fstat(descriptor)) != identity(before):
                        raise ValueError("Evidence entry changed while archiving")
                    member = zipfile.ZipInfo(relative + ("/" if directory else ""))
                    member.compress_type = zipfile.ZIP_STORED
                    member.external_attr = (stat.S_IFDIR | 0o700 if directory else stat.S_IFREG | 0o600) << 16
                    if directory:
                        member.external_attr |= 0x10
                        archive.writestr(member, b"")
                        add_directory(archive, descriptor, relative + "/", depth + 1)
                    else:
                        counts["bytes"] += before.st_size
                        if counts["bytes"] > MAX_TOTAL_BYTES:
                            raise ValueError("Evidence archive exceeds its total byte bound")
                        member.file_size = before.st_size
                        remaining = before.st_size
                        with archive.open(member, "w", force_zip64=True) as target:
                            while remaining:
                                block = os.read(descriptor, min(BUFFER_BYTES, remaining))
                                if not block:
                                    raise ValueError("Evidence file changed while archiving")
                                target.write(block)
                                remaining -= len(block)
                            if os.read(descriptor, 1):
                                raise ValueError("Evidence file changed while archiving")
                    if identity(os.fstat(descriptor)) != identity(before):
                        raise ValueError("Evidence entry changed while archiving")
                finally:
                    os.close(descriptor)
        if identity(os.fstat(directory_fd)) != identity(before_directory):
            raise ValueError("Evidence directory changed while archiving")

    try:
        fd, temporary = tempfile.mkstemp(prefix=".fighter-archive-", suffix=".tmp", dir=destination.parent)
        with os.fdopen(fd, "w+b") as target:
            with zipfile.ZipFile(target, "w", compression=zipfile.ZIP_STORED, allowZip64=True) as archive:
                add_directory(archive, root_fd)
        os.link(temporary, destination)
        return counts
    finally:
        os.close(root_fd)
        if temporary is not None:
            Path(temporary).unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source")
    parser.add_argument("destination")
    args = parser.parse_args()
    started = time.monotonic()
    print("Building private evidence archive (ZIP_STORED)", flush=True)
    counts = archive_evidence(args.source, args.destination)
    print(f"Private evidence archived: {counts['entries']} entries, {counts['bytes']} source bytes, "
          f"{time.monotonic() - started:.1f} seconds", flush=True)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, zipfile.LargeZipFile) as error:
        # Do not include evidence filenames or payloads in public diagnostics.
        print(f"Private evidence archive failed ({type(error).__name__})", file=sys.stderr)
        sys.exit(1)
