"""Draws the addon's two small arrows, white on a transparent background (the game
tints them):
    FellowshipLedger/media/sort-arrow.tga   16x16 triangle pointing down (flipped for "up")
    FellowshipLedger/media/level-arrow.tga  16x16 arrow pointing right ("9 -> 10")
    FellowshipLedger/media/check.tga        16x16 check mark (a quest you have done)
    FellowshipLedger/media/crown.tga        16x16 crown (the best in a comparison, 1.13.0)
    FellowshipLedger/media/switch-track.tga 32x16 rounded bar (an on/off switch, 1.14.0)
    FellowshipLedger/media/switch-knob.tga  16x16 dot (the switch's knob, 1.14.0)
    FellowshipLedger/media/ring.tga         32x32 thin circle (a character's level, 1.14.0)
    FellowshipLedger/media/ring-segments.tga 512x256: 20 pieces of a ring, one per 64x64 cell
                                            (how far through the level, 1.14.5)
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


def _near_segment(x, y, ax, ay, bx, by, r):
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy)))
    px, py = ax + t * dx - x, ay + t * dy - y
    return px * px + py * py <= r * r


def check_mark(x, y):
    # Two strokes, 1.4 px from their centre line: (3, 8.5) to (6.5, 12) to (13, 4).
    return _near_segment(x, y, 3, 8.5, 6.5, 12, 1.4) or _near_segment(x, y, 6.5, 12, 13, 4, 1.4)


def crown(x, y):
    # A band from y 11 to 13.5 under three points: a zigzag top through (2.5, 4),
    # (5.25, 8.5), (8, 3), (10.75, 8.5), (13.5, 4).
    if x < 2.5 or x > 13.5 or y > 13.5:
        return False
    pts = [(2.5, 4), (5.25, 8.5), (8, 3), (10.75, 8.5), (13.5, 4)]
    for (ax, ay), (bx, by) in zip(pts, pts[1:]):
        if ax <= x <= bx:
            top = ay + (by - ay) * (x - ax) / (bx - ax)
            return y >= top
    return False


def switch_track(x, y):
    # 32x16: a bar with round ends, radius 7.5 around y 8.
    r = 7.5
    if 8 <= x <= 24:
        return abs(y - 8) <= r
    cx = 8 if x < 8 else 24
    return (x - cx) ** 2 + (y - 8) ** 2 <= r * r


def switch_knob(x, y):
    return (x - 8) ** 2 + (y - 8) ** 2 <= 7.5 * 7.5


def ring(x, y):
    d = ((x - 16) ** 2 + (y - 16) ** 2) ** 0.5
    return 13.6 <= d <= 15.4


RING_SEGMENTS = 20  # one for each bar of the game's XP bar
SEGMENT_GAP = 5.0   # degrees left empty between two segments


def ring_segments(x, y):
    # 512x256: 8 x 4 cells of 64x64, segment i in cell i (left to right, then down).
    # Segment 0 starts at the top and they run clockwise, a thicker ring than ring.tga
    # (the same circle at twice the size: radius 25.2 to 31.2 of 32).
    import math
    col, row = int(x // 64), int(y // 64)
    i = row * 8 + col
    if i >= RING_SEGMENTS:
        return False
    dx, dy = x - col * 64 - 32, y - row * 64 - 32
    d = (dx * dx + dy * dy) ** 0.5
    if not 25.2 <= d <= 31.2:
        return False
    angle = math.degrees(math.atan2(dx, -dy)) % 360  # 0 at the top, growing clockwise
    span = 360 / RING_SEGMENTS
    return i * span + SEGMENT_GAP / 2 <= angle <= (i + 1) * span - SEGMENT_GAP / 2


def write(path, inside, width=SIZE, height=SIZE):
    pixels = bytearray()
    for row in range(height):  # top row first (descriptor bit 5 set below)
        for col in range(width):
            hits = 0
            for sy in range(SAMPLES):
                for sx in range(SAMPLES):
                    if inside(col + (sx + 0.5) / SAMPLES, row + (sy + 0.5) / SAMPLES):
                        hits += 1
            alpha = round(255 * hits / (SAMPLES * SAMPLES))
            pixels += bytes((255, 255, 255, alpha))  # BGRA
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, width, height, 32, 0x28)
    out = pathlib.Path(path)
    out.write_bytes(header + bytes(pixels))
    print("wrote", out, len(header) + len(pixels), "bytes")


def main():
    write("FellowshipLedger/media/sort-arrow.tga", sort_arrow)
    write("FellowshipLedger/media/level-arrow.tga", level_arrow)
    write("FellowshipLedger/media/check.tga", check_mark)
    write("FellowshipLedger/media/switch-track.tga", switch_track, 32, 16)
    write("FellowshipLedger/media/switch-knob.tga", switch_knob)
    write("FellowshipLedger/media/ring.tga", ring, 32, 32)
    write("FellowshipLedger/media/crown.tga", crown)
    write("FellowshipLedger/media/ring-segments.tga", ring_segments, 512, 256)


if __name__ == "__main__":
    main()
