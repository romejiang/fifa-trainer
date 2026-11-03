# Phase 01 — Code Review Disposition

**Source:** `01-REVIEW.md`
**Triaged:** 2026-11-04
**Policy:** code review is advisory for this phase — it never blocks execution. Every finding is recorded here so a triaged item is distinguishable from a forgotten one.

## Severity counts

| Severity | Count |
|----------|-------|
| blocker | 0 |
| high | 0 |
| medium | 4 |
| low | 5 |
| info | 6 |

## Findings → disposition

| ID | Severity | Location | Finding | Disposition |
|----|----------|----------|---------|-------------|
| MED-01 | medium | `desktop/main.py:247` | The `python3 tools/sync_config.py` hint printed by `--write-config` fails when run from `desktop/` (the documented working directory) — the final step of the loop is broken | `open` — fix with a repo-root-safe hint (`cd .. && python3 tools/sync_config.py`) |
| MED-02 | medium | `tools/sync_config.py:139-143` | `.sha256` comparison only checks the first field; malformed sidecars (digest-only, wrong filename, single space, extra line) all pass | `open` — validate the full `<hex>  <basename>` form |
| MED-03 | medium | `tools/test_sync_config.py` | The 23 self-test assertions are never run by the gate or CI; the validator guarding the entire config pipeline is effectively dead code | `open` — add `python3 tools/test_sync_config.py` as a gate step before `--check` |
| MED-04 | medium | `desktop/README.md:121,152,292` | The desktop manual still tells users to hand-edit the generated copy `skills_config.json`, contradicting this phase's core invariant that `shared/skills_config.json` is the only hand-editable source | `open` — rewrite those three passages to edit `shared/` then run the sync tool |
| LOW-01 | low | `tools/verify_clean_clone.sh` | `grep -e "配置"` tamper assertion is effectively always true | `open` |
| LOW-02 | low | `tools/collect_checks.py` | Missing baseline produces a raw traceback instead of a friendly error | `open` |
| LOW-03 | low | `tools/collect_checks.py` | Writes CRLF on Windows, which would make the Linux/macOS gate go falsely red | `open` |
| LOW-04 | low | `.github/workflows/desktop-checks.yml` | No `permissions:` block, no `persist-credentials: false`, no job timeout | `open` |
| LOW-05 | low | `tools/sync_config.py` | Stray-copy scan skips `build`/`dist`, so a copy placed there escapes detection | `open` |
| INFO-01..06 | info | — | Known timing-sensitive test (`test_engine_end_to_end`), `--write-config` can overwrite the single source, pre-existing `shared` vs `DEFAULT_CONFIG` drift, and style notes | `acknowledged` — explicitly out of Phase 1 scope; see `deferred-items.md` |

## Verdict

No blocker or high finding. All four medium findings are refinements to tooling and documentation introduced *by this phase*; none invalidates the phase's mechanical guarantees (230-check gate, single-source config, clean-clone reproduction), which were independently executed and verified.

Recommended follow-up: a single `/gsd-quick` pass covering MED-01…MED-04 plus LOW-04 before Phase 2 begins.
