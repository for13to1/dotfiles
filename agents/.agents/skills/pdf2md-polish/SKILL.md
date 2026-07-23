---
name: pdf2md-polish
description: 'Use when cleaning PDF/OCR-exported markdown (broken paragraphs, heading noise, math/OCR artifacts), or when the user asks for one-sentence-per-line academic markdown cleanup. Prefer this for PDF extraction cleanup rather than general prose editing. Trigger keywords: "pdf2md-polish", "OCR 清洗", "PDF markdown", "one sentence per line", "清洗 OCR", "校对 OCR".'
---

# Markdown Post-Processing

Hybrid workflow (script + LLM) for polishing markdown that came from PDF/OCR extraction.

## References

Load on demand:
- **[abbreviation-table.md](references/abbreviation-table.md)** — Protected abbreviation dots (EN/DE/FR/ES).
- **[ocr-patterns.md](references/ocr-patterns.md)** — Deterministic vs LLM-judgment OCR fixes.
- **[formatting-rules.md](references/formatting-rules.md)** — Heading hierarchy and semantic review rules.

## Configuration & History

- **`config.json`**: currently only `language` is read by `polish.py` (written into `history.json`).

| Key | Default | Used by script? | Description |
|-----|---------|-----------------|-------------|
| `language` | `"auto"` | yes (history only) | Language tag recorded in history |

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

Artifact convention:
- Given `<name>.md`, the raw source is `<name>.md`. Do not edit it during review.
- `<name>-polished.md` is the working copy created by Step 1 and used in Steps 2-3.
- `<name>.origin.md` is the raw-source backup created during finalization.

Subcommands:
- `polish` — deterministic pipeline → `<name>-polished.md`
- `headings` — compact text heading skeleton for hierarchy decisions
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
- Produce fenced `diff` blocks against the polished working copy from Steps 1-2, not against the original input file.
- Apply those edits back to the same polished working copy.

**Output format**: fenced `diff` blocks for changed lines only (not the full document). Then apply with targeted file edits/patches to `<name>-polished.md`.

### Step 4: Finalize Files

Default finalization:
1. If `<name>.origin.md` already exists, stop and ask the user before replacing it.
2. Run `uv run $HOME/.agents/skills/pdf2md-polish/polish.py finalize <name>.md`.
3. The command backs up the original and promotes the polished copy, rolling back if promotion fails.

Example:
- `paper.md` → backup as `paper.origin.md`
- `paper-polished.md` → final deliverable `paper.md`

Rules:
- The polished file is the final artifact to keep.
- The original input is backed up by default for traceability; the user may delete `<name>.origin.md` after verification.
- Step 4 is explicit: run `finalize` only after reviewing the polished working copy; `polish` and `apply` never finalize automatically.

### Reference Examples
- `examples/sample_input.md` — raw OCR/PDF input
- `examples/sample_prepass.md` — script-only output
- `examples/sample_output.md` — script + LLM result

Diff `sample_prepass.md` vs `sample_output.md` to see the LLM-only delta.
