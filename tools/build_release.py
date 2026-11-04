"""Builds the release zip for Fellowship Ledger and, optionally, uploads it to CurseForge.

Usage (from the repo root):
    python tools/build_release.py                    # build dist/FellowshipLedger-<version>.zip
    python tools/build_release.py --tag v0.1.0       # also check the tag matches the TOC versions
    python tools/build_release.py --tag v0.1.0 --upload --dry-run   # show what would be uploaded
    python tools/build_release.py --tag v0.1.0 --upload             # upload (needs CF_API_KEY)

Why not the BigWigs packager: it names the package from a TOC in the repository
root, and this repo keeps the addon in FellowshipLedger/ (see docs/DECISIONS.md D-052).

The zip contains exactly one folder, FellowshipLedger/, plus LICENSE.txt inside it.
CurseForge needs the project ID (TOC "## X-Curse-Project-ID", or --project) and the
token in the CF_API_KEY environment variable. The token is never printed or stored.
"""
import argparse
import json
import os
import pathlib
import re
import sys
import urllib.request
import uuid
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
ADDON = ROOT / "FellowshipLedger"
CONFIG = ROOT / "tools" / "release.config.json"
FLAVOR_TOCS = {"Retail": "FellowshipLedger_Mainline.toc", "Forever": "FellowshipLedger_Forever.toc"}
SKIP = {".gitkeep", "Thumbs.db", "desktop.ini", ".DS_Store"}
CF_API = "https://wow.curseforge.com/api"


def toc_fields(path):
    fields = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        m = re.match(r"^## ([\w-]+):\s*(.*?)\s*$", line)
        if m:
            fields[m.group(1)] = m.group(2)
    return fields


def versions():
    found = {}
    for toc in ADDON.glob("*.toc"):
        found[toc.name] = toc_fields(toc).get("Version")
    return found


def check_versions(tag):
    vs = versions()
    distinct = set(vs.values())
    if len(distinct) != 1:
        sys.exit(f"TOC versions differ: {vs}")
    version = distinct.pop()
    if tag is not None:
        want = tag[1:] if tag.startswith("v") else tag
        if version != want:
            sys.exit(f"Tag {tag} does not match TOC version {version}. Bump the TOCs and Core/Namespace.lua first.")
    return version


def build_zip(version):
    dist = ROOT / "dist"
    dist.mkdir(exist_ok=True)
    out = dist / f"FellowshipLedger-{version}.zip"
    count = 0
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for path in sorted(ADDON.rglob("*")):
            if path.is_file() and path.name not in SKIP:
                z.write(path, pathlib.Path("FellowshipLedger") / path.relative_to(ADDON))
                count += 1
        z.write(ROOT / "LICENSE", "FellowshipLedger/LICENSE.txt")
    return out, count + 1


def changelog_for(version):
    text = (ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
    m = re.search(r"^## [^\n]*\b" + re.escape(version) + r"\b[^\n]*\n(.*?)(?=^## |\Z)", text, re.S | re.M)
    return (m.group(1).strip() if m else f"Fellowship Ledger {version}")


def release_type(version):
    if "alpha" in version or "dev" in version:
        return "alpha"
    if "beta" in version or version.startswith("0."):
        return "beta"  # 0.x releases are pre-releases (D-055)
    return "release"


def wanted_game_versions():
    cfg = json.loads(CONFIG.read_text(encoding="utf-8"))
    return cfg["curseforgeGameVersions"]


def fetch_game_version_ids(token, names):
    req = urllib.request.Request(CF_API + "/game/versions", headers={"X-Api-Token": token})
    with urllib.request.urlopen(req, timeout=30) as r:
        all_versions = json.load(r)
    ids, missing = [], []
    for name in names:
        match = [v["id"] for v in all_versions if v.get("name") == name]
        if match:
            ids.append(match[0])
        else:
            missing.append(name)
    return ids, missing


def upload(zip_path, version, project, token, dry_run):
    by_flavor = wanted_game_versions()
    names = [n for flavor in FLAVOR_TOCS for n in by_flavor.get(flavor, [])]
    metadata = {
        "changelog": changelog_for(version),
        "changelogType": "markdown",
        "displayName": f"Fellowship Ledger {version}",
        "releaseType": release_type(version),
    }
    if dry_run:
        print("DRY RUN - would upload", zip_path.name, "to CurseForge project", project)
        print("  game versions by name:", names)
        print("  metadata:", json.dumps({k: (v[:80] + "..." if isinstance(v, str) and len(v) > 80 else v) for k, v in metadata.items()}))
        return
    ids, missing = fetch_game_version_ids(token, names)
    if missing:
        print("WARNING: CurseForge does not list these game versions yet:", missing)
    if not ids:
        sys.exit("No matching CurseForge game versions; not uploading.")
    metadata["gameVersions"] = ids
    boundary = uuid.uuid4().hex
    body = b"".join([
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"metadata\"\r\n\r\n".encode(),
        json.dumps(metadata).encode(), b"\r\n",
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"{zip_path.name}\"\r\n"
        "Content-Type: application/zip\r\n\r\n".encode(),
        zip_path.read_bytes(), b"\r\n", f"--{boundary}--\r\n".encode(),
    ])
    req = urllib.request.Request(f"{CF_API}/projects/{project}/upload-file", data=body, method="POST", headers={
        "X-Api-Token": token, "Content-Type": f"multipart/form-data; boundary={boundary}"})
    with urllib.request.urlopen(req, timeout=120) as r:
        print("CurseForge upload OK:", r.read().decode()[:200])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag")
    ap.add_argument("--upload", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--project", help="CurseForge project ID (default: TOC X-Curse-Project-ID)")
    args = ap.parse_args()
    version = check_versions(args.tag)
    zip_path, n = build_zip(version)
    notes = ROOT / "dist" / "RELEASE_NOTES.md"
    notes.write_text(changelog_for(version) + "\n", encoding="utf-8")
    print(f"Built {zip_path.relative_to(ROOT)} ({n} files, version {version}); notes in dist/RELEASE_NOTES.md")
    if args.upload:
        project = args.project or toc_fields(ADDON / FLAVOR_TOCS["Retail"]).get("X-Curse-Project-ID")
        if not project:
            sys.exit("No CurseForge project ID: add '## X-Curse-Project-ID: <id>' to both TOCs or pass --project.")
        token = os.environ.get("CF_API_KEY", "")
        if not token and not args.dry_run:
            sys.exit("CF_API_KEY is not set.")
        upload(zip_path, version, project, token, args.dry_run)


if __name__ == "__main__":
    main()
