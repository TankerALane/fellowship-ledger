"""Regenerates the check table in docs/API-VERIFICATION.md from
FellowshipLedger/Debug/VerifyChecks.lua (one check per line).

Usage (from the repo root):  python tools/gen_verify_doc.py

Only the part between the GENERATED markers is replaced, so hand-written text
and Austin's PASS/FAIL marks outside it are kept. Marks inside the table are
kept too: existing Forever/Retail cells are carried over by check id.
"""
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
CHECKS = ROOT / "FellowshipLedger" / "Debug" / "VerifyChecks.lua"
DOC = ROOT / "docs" / "API-VERIFICATION.md"
BEGIN = "<!-- GENERATED:BEGIN (tools/gen_verify_doc.py) -->"
END = "<!-- GENERATED:END -->"

FIELD = re.compile(r'(\w+)\s*=\s*("(?:[^"\\]|\\.)*"|true|false)')


def parse_checks():
    checks = []
    for line in CHECKS.read_text(encoding="utf-8").splitlines():
        s = line.strip()
        if not s.startswith("{ id ="):
            continue
        fields = {}
        for key, raw in FIELD.findall(s):
            if raw.startswith('"'):
                fields[key] = raw[1:-1].replace('\\"', '"')
            else:
                fields[key] = raw == "true"
        checks.append(fields)
    return checks


def test_command(c):
    kind = c["kind"]
    if kind == "api":
        expect = c.get("expect", "function")
        return f'`/dump type({c["id"]})` -> "{expect}"'
    if kind == "event":
        name = c["id"][3:]
        return f'`/dump C_EventUtils.IsEventValid("{name}")` -> true'
    test = c.get("test", "")
    return f"`{test}`" if test.startswith("/") else test


def existing_marks(text):
    marks = {}
    for line in text.splitlines():
        m = re.match(r"\| `([^`]+)` \|.*\| ([^|]*) \| ([^|]*) \|$", line)
        if m:
            marks[m.group(1)] = (m.group(2).strip(), m.group(3).strip())
    return marks


def build_table(checks, marks):
    out = [BEGIN, ""]
    area = None
    for c in checks:
        if c["area"] != area:
            area = c["area"]
            out += ["", f"### {area}", "",
                    "| ID | Kind | What it is for | In-game test | Forever | Retail |",
                    "|---|---|---|---|---|---|"]
        note = c["why"]
        if c.get("noargs"):
            note += " (probe counts only, no arguments stored)"
        if c.get("probe") is False:
            note += " (not probed: too noisy)"
        fv, rt = marks.get(c["id"], ("?", "?"))
        out.append(f'| `{c["id"]}` | {c["kind"]} | {note} | {test_command(c)} | {fv or "?"} | {rt or "?"} |')
    out += ["", END]
    return "\n".join(out)


def main():
    checks = parse_checks()
    doc = DOC.read_text(encoding="utf-8")
    start, end = doc.index(BEGIN), doc.index(END) + len(END)
    marks = existing_marks(doc[start:end])
    doc = doc[:start] + build_table(checks, marks) + doc[end:]
    DOC.write_text(doc, encoding="utf-8", newline="\n")
    print(f"{len(checks)} checks written to {DOC.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
