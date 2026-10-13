#!/usr/bin/env python3
"""Lists the files inside a Godot .pck (pack format 2 to 4; Godot 4.x).

Usage: python3 tools/build/list_pack.py <file.pck>
Prints one res:// path per line. Exits 1 on an unreadable or encrypted pack.
"""
import struct
import sys

PACK_DIR_ENCRYPTED = 1 << 0
PACK_REL_FILEBASE = 1 << 1


def list_pack(path):
    with open(path, "rb") as f:
        data = f.read()
    if data[:4] != b"GDPC":
        raise ValueError(f"{path}: not a Godot pack")
    version, _major, _minor, _patch = struct.unpack_from("<IIII", data, 4)
    pos = 20
    flags = 0
    dir_offset = None
    if version >= 2:
        flags, _file_base = struct.unpack_from("<IQ", data, pos)
        pos += 12
    if version >= 3:
        (dir_offset,) = struct.unpack_from("<Q", data, pos)
        pos += 8
    if flags & PACK_DIR_ENCRYPTED:
        raise ValueError(f"{path}: encrypted directory")
    if dir_offset is not None:
        pos = dir_offset
    else:
        pos += 16 * 4  # reserved
    (count,) = struct.unpack_from("<I", data, pos)
    pos += 4
    paths = []
    for _ in range(count):
        (length,) = struct.unpack_from("<I", data, pos)
        pos += 4
        name = data[pos:pos + length].rstrip(b"\0").decode("utf-8")
        pos += length
        pos += 8 + 8 + 16  # offset, size, md5
        if version >= 2:
            pos += 4  # file flags
        paths.append(name if name.startswith("res://") else "res://" + name)
    return paths


def main():
    if len(sys.argv) != 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    try:
        for p in list_pack(sys.argv[1]):
            print(p)
    except (ValueError, struct.error) as exc:
        print(f"list_pack: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
