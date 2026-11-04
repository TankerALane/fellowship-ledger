# Releasing

Releases are built by `tools/build_release.py` and published by `.github/workflows/release.yml` when a version tag is pushed. The packaging choice is explained in `docs/DECISIONS.md` (D-052).

## One-time setup (Austin)

1. **GitHub.** Claude creates the public repository and pushes `main`, but only after you confirm the name. Then check **Settings > Actions > General > Workflow permissions** is "Read and write", so the workflow can create releases.
2. **CurseForge.** Sign in yourself (Google), create the project "Fellowship Ledger" (category: Quests & Leveling or Miscellaneous), and note its **Project ID** from the "About Project" box.
   - Claude adds `## X-Curse-Project-ID: <id>` to both TOCs. The ID is not secret.
   - Create an API token at https://legacy.curseforge.com/account/api-tokens and add it to the GitHub repository as the secret **`CF_API_KEY`** (Settings > Secrets and variables > Actions). Never paste the token in chat or commit it.

## Each release

1. Make sure the in-game checks for the release are done (`docs/ROADMAP.md`), and the tests pass:
   `powershell -ExecutionPolicy Bypass -File tools\run_tests.ps1`.
2. Bump the version in all three TOCs and in `Core/Namespace.lua` (a test keeps them equal), and give `CHANGELOG.md` a `## <version>` section.
3. Try a local build: `python tools/build_release.py --tag v<version>`, which writes `dist/FellowshipLedger-<version>.zip`.
4. Commit, then push an annotated tag: `git tag -a v<version> -m "Fellowship Ledger <version>"` and `git push origin v<version>`.
5. The workflow then:
   - runs the tests
   - builds the zip (and fails if the tag does not match the TOCs)
   - creates the GitHub release with the zip
   - uploads to CurseForge if `CF_API_KEY` is set

## CurseForge game versions

`tools/release.config.json` lists the CurseForge game-version names to attach: "12.1.5" for retail and "1.60.1" for Forever. The script looks them up in CurseForge's game-versions list. Any name CurseForge does not list yet (Forever may be missing) is reported as a warning and skipped. When a client patches, update the TOC `## Interface` line and this file.

Check the token and game versions (read-only, uploads nothing): Actions tab > "CurseForge check" > Run workflow.

Dry run with no token needed: `python tools/build_release.py --tag v<version> --upload --dry-run --project <id>`.
