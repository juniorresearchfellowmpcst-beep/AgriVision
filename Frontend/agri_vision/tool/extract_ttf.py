"""Pull a single font out of a TrueType Collection (.ttc) into a .ttf.

    python tool/extract_ttf.py C:\\Windows\\Fonts\\Nirmala.ttc test/fonts/NirmalaUI.ttf

Why this exists: the screenshot renderer needs a Devanagari face so the Hindi
screens come out as text rather than as rows of empty boxes, and the only one
Windows ships is Nirmala -- as a *collection*. Flutter's ``FontLoader`` takes
one sfnt font, not a container of several, and fails quietly on a .ttc, which
is exactly the kind of silence that gets mistaken for "Hindi does not render".

A .ttc is a small header followed by the ordinary table directories of each
font it holds; the tables themselves are shared in one pool. So extracting one
font means writing a normal sfnt header plus that font's directory, and copying
the tables it points at -- no font library required, and nothing here reshapes
or subsets glyphs.
"""

from __future__ import annotations

import struct
import sys


def extract(ttc_path: str, out_path: str, index: int = 0) -> None:
    with open(ttc_path, "rb") as handle:
        data = handle.read()

    tag = data[:4]
    if tag != b"ttcf":
        # Already a single font: copying it is the right answer, not an error.
        with open(out_path, "wb") as handle:
            handle.write(data)
        print(f"{ttc_path} is not a collection; copied as-is -> {out_path}")
        return

    count = struct.unpack(">I", data[8:12])[0]
    if index >= count:
        raise SystemExit(f"{ttc_path} holds {count} font(s); no index {index}")
    offsets = struct.unpack(f">{count}I", data[12:12 + 4 * count])
    directory = offsets[index]

    sfnt_version, num_tables = struct.unpack(">IH", data[directory:directory + 6])
    search_range, entry_selector, range_shift = struct.unpack(
        ">HHH", data[directory + 6:directory + 12]
    )

    entries = []
    for i in range(num_tables):
        start = directory + 12 + 16 * i
        table_tag, checksum, offset, length = struct.unpack(
            ">4sIII", data[start:start + 16]
        )
        entries.append([table_tag, checksum, offset, length])

    # The new file is: header, table directory, then the tables themselves.
    # Tables are 4-byte aligned, which some rasterisers require.
    header_size = 12 + 16 * len(entries)
    body = bytearray()
    rewritten = []
    cursor = header_size
    for table_tag, checksum, offset, length in entries:
        body += data[offset:offset + length]
        padding = (-length) % 4
        body += b"\0" * padding
        rewritten.append((table_tag, checksum, cursor, length))
        cursor += length + padding

    out = bytearray()
    out += struct.pack(
        ">IHHHH", sfnt_version, num_tables, search_range, entry_selector, range_shift
    )
    for table_tag, checksum, offset, length in rewritten:
        out += struct.pack(">4sIII", table_tag, checksum, offset, length)
    out += body

    with open(out_path, "wb") as handle:
        handle.write(out)
    print(f"extracted font {index} of {count}: {out_path} ({len(out):,} bytes)")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    extract(sys.argv[1], sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 0)
