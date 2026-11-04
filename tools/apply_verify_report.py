"""Applies a pasted /fl verify report to the Forever or Retail column of
docs/API-VERIFICATION.md, then lists every check whose result differs between
the two clients.

Usage (from the repo root):
    python tools/apply_verify_report.py docs/verify-reports/retail-2026-11-04.txt

The flavor comes from the report header (flavor=Forever / flavor=Retail).
Cells written: PASS, FAIL, ERROR, INFO. Manual checks are left as they are.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
DOC = ROOT / "docs" / "API-VERIFICATION.md"
ROW = re.compile(r"^\| `([^`]+)` \|(.*)\| ([^|]*) \| ([^|]*) \|$")


def parse_report(text):
    flavor = re.search(r"\bflavor=(\w+)", text)
    if not flavor:
        sys.exit("No flavor= in the report header.")
    flavor = flavor.group(1)
    results = {}
    section = None
    for raw in text.splitlines():
        line = raw.strip()
        if line.startswith("-- "):
            section = line[3:]
            continue
        m = re.match(r"^(PASS|FAIL|ERROR|INFO) ((?:x:|m:|ev:)?[^:\s]+)", line)
        if m and section in ("problems", "details"):
            results[m.group(2)] = m.group(1)
            continue
        if section and section.startswith("api pass"):
            for item in filter(None, (s.strip() for s in line.split(","))):
                results[item] = "PASS"
        elif section and section.startswith("event pass"):
            for item in filter(None, (s.strip() for s in line.split(","))):
                results["ev:" + item] = "PASS"
    return flavor, results


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    flavor, results = parse_report(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
    if flavor not in ("Forever", "Retail"):
        sys.exit(f"Unsupported flavor {flavor!r} in report.")
    out, applied, diffs = [], 0, []
    for line in DOC.read_text(encoding="utf-8").splitlines():
        m = ROW.match(line)
        if m:
            cid, middle, fv, rt = m.group(1), m.group(2), m.group(3).strip(), m.group(4).strip()
            if cid in results:
                if flavor == "Forever":
                    fv = results[cid]
                else:
                    rt = results[cid]
                applied += 1
            line = f"| `{cid}` |{middle}| {fv} | {rt} |"
            done = ("PASS", "FAIL", "ERROR", "INFO")
            if fv in done and rt in done and fv != rt:
                diffs.append(f"  {cid}: Forever {fv}, Retail {rt}")
        out.append(line)
    DOC.write_text("\n".join(out) + "\n", encoding="utf-8", newline="\n")
    missing = [cid for cid in results if f"`{cid}`" not in "\n".join(out)]
    print(f"{flavor}: {applied} cells updated in {DOC.relative_to(ROOT)}")
    if missing:
        print("In the report but not in the doc: " + ", ".join(missing))
    if diffs:
        print("Results that differ between Forever and Retail:")
        print("\n".join(diffs))


if __name__ == "__main__":
    main()
