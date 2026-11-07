"""Crop the pictures /fl shots took down to the addon window (D-088).

Run after /fl shots and a /reload (the reload writes the saved variables):

    python tools/crop_shots.py              # Forever (default)
    python tools/crop_shots.py --flavor retail

It reads db.dev.shots from FellowshipLedger.lua in SavedVariables, pairs each step
with the newest game screenshots taken since the run started, and writes
PNGs to assets/screenshots/ named like 01-me-card-ledger.png. Cropping uses Windows'
own System.Drawing through PowerShell, so nothing needs installing.
"""
import argparse
import json
import pathlib
import re
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
CONFIG = ROOT / "tools" / "sync.config.json"
OUT = ROOT / "assets" / "screenshots"
MARGIN = 4  # pixels around the window


class LuaReader:
    """Just enough of Lua's table syntax for SavedVariables."""

    TOKEN = re.compile(r'\s*(?:--\[\[.*?\]\]|--[^\n]*)?\s*', re.S)

    def __init__(self, text):
        self.t, self.i = text, 0

    def skip(self):
        while True:
            m = self.TOKEN.match(self.t, self.i)
            if not m or m.end() == self.i:
                return
            self.i = m.end()

    def value(self):
        self.skip()
        c = self.t[self.i]
        if c == "{":
            return self.table()
        if c == '"':
            m = re.compile(r'"((?:\\.|[^"\\])*)"').match(self.t, self.i)
            self.i = m.end()
            return bytes(m.group(1), "utf-8").decode("unicode_escape")
        m = re.compile(r'-?[\d.]+(?:e-?\d+)?|true|false|nil').match(self.t, self.i)
        self.i = m.end()
        w = m.group(0)
        if w in ("true", "false", "nil"):
            return {"true": True, "false": False, "nil": None}[w]
        return float(w)

    def table(self):
        self.i += 1
        out, arr = {}, []
        while True:
            self.skip()
            if self.t[self.i] == "}":
                self.i += 1
                return out if out else arr
            if self.t[self.i] == "[":
                self.i += 1
                key = self.value()
                self.skip()
                self.i += 1  # ]
                self.skip()
                self.i += 1  # =
                out[key] = self.value()
            else:
                arr.append(self.value())
            self.skip()
            if self.t[self.i] == ",":
                self.i += 1


def game_folder(flavor):
    cfg = json.loads(CONFIG.read_text(encoding="utf-8"))
    dest = cfg.get("destinations", {}).get(flavor.capitalize())
    if not dest:
        raise SystemExit(f"No {flavor} destination in {CONFIG}")
    # ...\_forever_\Interface\AddOns -> ...\_forever_
    return pathlib.Path(dest).parent.parent


def find_shots(sv_dir):
    files = list(sv_dir.glob("*/SavedVariables/FellowshipLedger.lua"))
    if not files:
        raise SystemExit(f"No FellowshipLedger.lua under {sv_dir}")
    best = None
    for f in files:
        text = f.read_text(encoding="utf-8", errors="replace")
        m = re.search(r'\["shots"\]\s*=\s*', text)
        if not m:
            continue
        r = LuaReader(text)
        r.i = m.end()
        shots = r.value()
        if isinstance(shots, dict) and (not best or shots.get("at", 0) > best.get("at", 0)):
            best = shots
    if not best:
        raise SystemExit("No /fl shots run found. Run /fl shots, then /reload, then this script.")
    return best


PS = r'''
param($src, $dst, $x, $y, $w, $h)
Add-Type -AssemblyName System.Drawing
$img = [System.Drawing.Image]::FromFile($src)
$x = [Math]::Max(0, $x); $y = [Math]::Max(0, $y)
$w = [Math]::Min($w, $img.Width - $x); $h = [Math]::Min($h, $img.Height - $y)
$bmp = New-Object System.Drawing.Bitmap $w, $h
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.DrawImage($img, (New-Object System.Drawing.Rectangle 0, 0, $w, $h), (New-Object System.Drawing.Rectangle $x, $y, $w, $h), [System.Drawing.GraphicsUnit]::Pixel)
$bmp.Save($dst, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose(); $img.Dispose()
'''


def image_size(path):
    out = subprocess.run(["powershell", "-NoProfile", "-Command",
                          f"Add-Type -AssemblyName System.Drawing; $i=[System.Drawing.Image]::FromFile('{path}'); "
                          "Write-Output \"$($i.Width) $($i.Height)\"; $i.Dispose()"],
                         capture_output=True, text=True, check=True).stdout.split()
    return int(out[0]), int(out[1])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--flavor", choices=["forever", "retail"], default="forever")
    args = ap.parse_args()
    game = game_folder(args.flavor)
    shots = find_shots(game / "WTF" / "Account")
    steps = shots.get("steps") or []
    pics = sorted((p for p in (game / "Screenshots").glob("WoWScrnShot_*")
                   if p.stat().st_mtime >= shots.get("at", 0) - 5), key=lambda p: p.stat().st_mtime)
    # Pictures taken after the saved run ended belong to a run the game has not
    # written yet (no /reload since): matching them to the old steps would name
    # every picture wrong.
    last_at = max((s.get("at") or 0 for s in steps), default=shots.get("at", 0))
    newer = [p for p in pics if p.stat().st_mtime > last_at + 60]
    if newer:
        raise SystemExit(f"{len(newer)} screenshot(s) are newer than the saved /fl shots run "
                         f"(saved {time.strftime('%m-%d %H:%M', time.localtime(last_at))}). "
                         "Type /reload in the game so it saves the new run, then run this again.")
    if len(pics) < len(steps):
        raise SystemExit(f"{len(steps)} steps but only {len(pics)} screenshots since the run in {game / 'Screenshots'}")
    pics = pics[-len(steps):]  # the newest ones: an earlier run may also be in the window
    OUT.mkdir(parents=True, exist_ok=True)
    script = pathlib.Path(OUT / "_crop.ps1")
    script.write_text(PS, encoding="utf-8")
    try:
        for n, (step, pic) in enumerate(zip(steps, pics), 1):
            parts = [step.get("tab"), step.get("layout") if step.get("tab") in ("me", "friends") and not step.get("mode") else None,
                     step.get("mode"), step.get("skin")]
            name = f"{n:02d}-" + "-".join(p for p in parts if p) + ".png"
            rect = step.get("rect")
            if not rect:
                print(f"{name}: no window position saved, copying the whole picture")
                x, y, (w, h) = 0, 0, image_size(pic)
            else:
                _, ih = image_size(pic)
                k = ih / rect["screen"]
                x = int(rect["left"] * k) - MARGIN
                y = int(ih - rect["top"] * k) - MARGIN
                w = int((rect["right"] - rect["left"]) * k) + 2 * MARGIN
                h = int((rect["top"] - rect["bottom"]) * k) + 2 * MARGIN
            subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(script),
                            str(pic), str(OUT / name), str(x), str(y), str(w), str(h)], check=True, capture_output=True)
            print(f"{pic.name} -> {OUT / name}")
    finally:
        script.unlink(missing_ok=True)


if __name__ == "__main__":
    sys.exit(main())
