"""Draws FellowshipLedger/media/sort-arrow.tga: a 16x16 white triangle pointing
down on a transparent background (the game tints it and flips it for "up").
Our own art, made here so nothing from the game is shipped. Run from the repo root:
    python tools/make_sort_arrow.py
"""
import pathlib
import struct

SIZE = 16
SAMPLES = 4  # per axis, for smooth edges


def inside(x, y):
    # Triangle: top edge from (3, 5) to (13, 5), tip at (8, 11).
    if y < 5 or y > 11:
        return False
    half = 5 * (11 - y) / 6
    return 8 - half <= x <= 8 + half


def main():
    pixels = bytearray()
    for row in range(SIZE):  # top row first (descriptor bit 5 set below)
        for col in range(SIZE):
            hits = 0
            for sy in range(SAMPLES):
                for sx in range(SAMPLES):
                    if inside(col + (sx + 0.5) / SAMPLES, row + (sy + 0.5) / SAMPLES):
                        hits += 1
            alpha = round(255 * hits / (SAMPLES * SAMPLES))
            pixels += bytes((255, 255, 255, alpha))  # BGRA
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 0x28)
    out = pathlib.Path("FellowshipLedger/media/sort-arrow.tga")
    out.write_bytes(header + bytes(pixels))
    print("wrote", out, len(header) + len(pixels), "bytes")


if __name__ == "__main__":
    main()
