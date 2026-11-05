"""Draws the addon's two small arrows, white on a transparent background (the game
tints them):
    FellowshipLedger/media/sort-arrow.tga   16x16 triangle pointing down (flipped for "up")
    FellowshipLedger/media/level-arrow.tga  16x16 arrow pointing right ("9 -> 10")
Our own art, made here so nothing from the game is shipped. Run from the repo root:
    python tools/make_sort_arrow.py
"""
import pathlib
import struct

SIZE = 16
SAMPLES = 4  # per axis, for smooth edges


def sort_arrow(x, y):
    # Triangle: top edge from (3, 5) to (13, 5), tip at (8, 11).
    if y < 5 or y > 11:
        return False
    half = 5 * (11 - y) / 6
    return 8 - half <= x <= 8 + half


def level_arrow(x, y):
    # Shaft from x 2 to 9, 2 px thick around y 8; head from x 8.5 to 14, 9 px tall.
    if 2 <= x <= 9 and 7 <= y <= 9:
        return True
    if 8.5 <= x <= 14:
        half = 4.5 * (14 - x) / 5.5
        return 8 - half <= y <= 8 + half
    return False


def write(path, inside):
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
    out = pathlib.Path(path)
    out.write_bytes(header + bytes(pixels))
    print("wrote", out, len(header) + len(pixels), "bytes")


def main():
    write("FellowshipLedger/media/sort-arrow.tga", sort_arrow)
    write("FellowshipLedger/media/level-arrow.tga", level_arrow)


if __name__ == "__main__":
    main()
