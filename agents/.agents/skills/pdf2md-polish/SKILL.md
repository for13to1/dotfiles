---
name: pdf2md-polish
description: 'Cleans up markdown extracted from PDF/OCR: repairs broken sentences and heading hierarchy, fixes math/OCR artifacts and ligatures, normalizes CJK↔ASCII spacing. Trigger: "polish" or "清洗" applied to a .md file.'
---

# Markdown Post-Processing

Hybrid workflow (script + LLM) for polishing markdown that came from PDF/OCR extraction.

Scope: for PDF/OCR extraction cleanup only, not general prose or stylistic editing.

## References

Load on demand:

- **[abbreviation-table.md](references/abbreviation-table.md)** — Protected abbreviation dots (EN/DE/FR/ES).
- **[ocr-patterns.md](references/ocr-patterns.md)** — Deterministic vs LLM-judgment OCR fixes.
- **[formatting-rules.md](references/formatting-rules.md)** — Heading hierarchy and semantic review rules.

## Configuration & History

- **Language detection**: handled automatically by character rules (CJK / CJK punctuation / full-width forms). No `config.json` is needed; the script auto-detects Chinese-English mixed prose and inserts a space at CJK↔ASCII boundaries (`使用 Python`).
- **`history.json`**: append-only run log stored alongside the Skill. LLM should not edit it. Write failures are non-fatal.

## Gotchas

- **CJK after abbreviations**: `Li et al.提出` is handled by the script; do not "fix" as a false sentence break.
- **Decimal spaces**: `3 . 14` → `3.14` if the script misses any.
- **Currency vs math**: `$100` vs `$x + y$`; be careful with single-letter math like `$n$`.
- **Hyphen vs en-dash**: script does not promote `-` to `–`; do that in LLM review when appropriate.
- **Unbalanced `$$`**: script warns on stderr; fix delimiters manually.
- **Ligatures / LaTeX envs**: ligatures are normalized; `\begin{align}`-style blocks are treated as math block boundaries and are not rewritten to `$$...$$`; internal whitespace normalization may still apply.

## Workflow

### Step 1: Run the Polish Script

Default output is a sibling working file, not an in-place overwrite:
```bash
uv run $HOME/.agents/skills/pdf2md-polish/polish.py polish paper.md
```
Fallback: `python3` if `uv` is unavailable.

If `polish` exits non-zero (unreadable input, invalid markdown), stop and report the error; do not continue to later steps.

Artifact convention:

- `<name>.md` is the raw source; it is not edited during review.
- `<name>-polished.md` is the working copy created in Step 1 and used in Steps 2-3.
- After finalization, `<name>.md` is the polished deliverable and `<name>.origin.md` holds the raw-source backup.

Subcommands:

- `polish` — deterministic pipeline → `<name>-polished.md`
- `headings` — compact text heading skeleton for hierarchy decisions (add `-c N` for more context)
- `apply` — apply heading level mapping and overwrite the polished working copy
- `finalize` — back up the original and promote the polished working copy

### Step 2: Adjust Heading Hierarchy

1. Extract skeleton:
   ```bash
   uv run $HOME/.agents/skills/pdf2md-polish/polish.py headings paper-polished.md
   ```
2. Choose hierarchy (title `#`, section `##`, subsection `###`) per [formatting-rules.md](references/formatting-rules.md).
3. Apply mapping with 1-indexed line numbers as JSON keys (`{"148": "##"}`):
   ```bash
   uv run $HOME/.agents/skills/pdf2md-polish/polish.py apply paper-polished.md -m '{"148": "##", "203": "###"}'
   ```
   `apply` updates the same polished working copy in place.

### Step 3: Semantic Review & Output

Only fix items on this checklist. Skip silently if clean:

- [ ] Remaining ligatures (`ﬁ`→`fi`, `ﬀ`→`ff`, `ﬃ`→`ffi`)
- [ ] OCR confusions near math/digits (`l`/`1`, `O`/`0`, `S`/`5`) when unambiguous
- [ ] Figure/table captions split from anchors by a spurious blank line
- [ ] Math punctuation placed outside/inside `$...$` incorrectly
- [ ] Unbalanced `$$` reported on stderr

Review target:

- Produce fenced `diff` blocks for changed lines only (not the full document), against the polished working copy from Steps 1-2, then apply those edits back to it.

### Step 4: Finalize Files

After the semantic review is complete, finalize:

1. Run `uv run $HOME/.agents/skills/pdf2md-polish/polish.py finalize <name>.md`.
2. The command backs up the original as `<name>.origin.md` and promotes the polished copy to `<name>.md`, rolling back if promotion fails.

Exceptions:

- If `<name>.origin.md` already exists, `finalize` refuses to overwrite it; stop and ask the user whether to move the old backup aside, then retry.
- If the user explicitly says they want to keep the working copy `<name>-polished.md` without finalizing (e.g., "just polish, don't finalize"), skip Step 4.

Example:

- `paper.md` → backup as `paper.origin.md`
- `paper-polished.md` → final deliverable `paper.md`

Rules:

- The polished file is the final artifact to keep.
- The original input is backed up by default for traceability; the user may delete `<name>.origin.md` after verification.

### Step 5: Verify & Done

Confirm the run actually completed before stopping:

- `<name>.md` is the polished deliverable and `<name>.origin.md` holds the raw source (in the default path, `<name>-polished.md` was consumed by `finalize`).
- No unbalanced `$$` or remaining Step 3 checklist items.

Then report to the user: deterministic fixes applied, heading mapping used, and the two artifact paths.

### Reference Examples

- `examples/sample_input.md` — raw OCR/PDF input
- `examples/sample_prepass.md` — script-only output
- `examples/sample_output.md` — script + LLM result

Diff `sample_prepass.md` vs `sample_output.md` to see the LLM-only delta.
