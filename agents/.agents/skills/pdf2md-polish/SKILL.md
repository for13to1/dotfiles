---
name: pdf2md-polish
description: Use when cleaning PDF/OCR-exported markdown (broken paragraphs, heading noise, math/OCR artifacts), or when the user asks for one-sentence-per-line academic markdown cleanup. Prefer this for PDF extraction cleanup rather than general prose editing. Trigger keywords: "pdf2md-polish", "OCR 清洗", "PDF markdown", "one sentence per line", "清洗 OCR", "校对 OCR".
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

- **`history.json`**: append-only run log, updated automatically by `polish.py`. LLM should not edit it. Write failures are non-fatal.

## Gotchas

- **CJK after abbreviations**: `Li et al.提出` is handled by the script; do not "fix" as a false sentence break.
- **Decimal spaces**: `3 . 14` → `3.14` if the script misses any.
- **Currency vs math**: `$100` vs `$x + y$`; be careful with single-letter math like `$n$`.
- **Hyphen vs en-dash**: script does not promote `-` to `–`; do that in LLM review when appropriate.
- **Unbalanced `$$`**: script warns on stderr; fix delimiters manually.
- **Ligatures / LaTeX envs**: ligatures are normalized; `\\begin{align}`-style blocks are left alone.

## Workflow

### Step 1: Run the Polish Script
Default output is a sibling file, not an in-place overwrite:
```bash
uv run $HOME/.agents/skills/pdf2md-polish/polish.py polish <input.md>
```
Fallback: `python3` if `uv` is unavailable.

Subcommands:
- `polish` — deterministic pipeline → `<input>-polished.md` (or `-o PATH`)
- `headings` — compact text heading skeleton for hierarchy decisions
- `apply` — apply heading level mapping; defaults to overwriting the file passed in (use `-o` to write elsewhere)

### Step 2: Adjust Heading Hierarchy
1. Extract skeleton:
   ```bash
   uv run $HOME/.agents/skills/pdf2md-polish/polish.py headings <polished.md>
   ```
2. Choose hierarchy (title `#`, section `##`, subsection `###`) per [formatting-rules.md](references/formatting-rules.md).
3. Apply mapping with 1-indexed line numbers as JSON keys (`{"148": "##"}`):
   ```bash
   uv run $HOME/.agents/skills/pdf2md-polish/polish.py apply <polished.md> -m '{"148": "##", "203": "###"}'
   ```

### Step 3: Semantic Review & Output

Only fix items on this checklist. Skip silently if clean:

- [ ] Remaining ligatures (`ﬁ`→`fi`, `ﬀ`→`ff`, `ﬃ`→`ffi`)
- [ ] OCR confusions near math/digits (`l`/`1`, `O`/`0`, `S`/`5`) when unambiguous
- [ ] Figure/table captions split from anchors by a spurious blank line
- [ ] Math punctuation placed outside/inside `$...$` incorrectly
- [ ] Unbalanced `$$` reported on stderr

**Output format**: fenced `diff` blocks for changed lines only (not the full document). Then apply with targeted file edits/patches.

### Reference Examples
- `examples/sample_input.md` — raw OCR/PDF input
- `examples/sample_prepass.md` — script-only output
- `examples/sample_output.md` — script + LLM result

Diff `sample_prepass.md` vs `sample_output.md` to see the LLM-only delta.
