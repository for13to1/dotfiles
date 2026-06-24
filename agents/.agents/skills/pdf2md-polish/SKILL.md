---
name: pdf2md-polish
description: Use when the user provides a markdown file (.md) and asks to clean up, polish, proofread, reformat, or tidy it up. Also use when converting PDF-OCR output, cleaning academic paper markdown, or fixing broken paragraphs from PDF extraction. Trigger keywords: "pdf2md-polish", "polish", "tidy up", "proofread", "reformat", "clean up this markdown", "fix formatting", "one sentence per line", "校对", "格式化", "整理", "清理", "清洗", "OCR 清洗".
---

# Markdown Post-Processing

This skill provides a **hybrid workflow** (script + LLM) for polishing markdown files containing OCR artifacts, broken paragraphs, or messy formatting.

## References

Detailed technical guidelines are separated to keep this skill concise. Consult them on demand:
- **[abbreviation-table.md](references/abbreviation-table.md)** — List of 100+ protected abbreviation dots across English, German, French, and Spanish.
- **[ocr-patterns.md](references/ocr-patterns.md)** — Common OCR artifacts (deterministic fixes vs. LLM-judgment fixes).
- **[formatting-rules.md](references/formatting-rules.md)** — Detailed rules for heading hierarchy, semantic review, and script capabilities.

## Configuration & History

- **`config.json`**: Configures the polish pipeline. Default values:

| Key | Default | Values | Description |
|-----|---------|--------|-------------|
| `overwrite_original` | `true` | `true` / `false` | Overwrite the input file with polished output |
| `language` | `"auto"` | `"auto"`, `"en"`, `"de"`, `"fr"`, `"es"`, `"zh"` | Primary language (affects abbreviation list priority) |
| `heading_style` | `"atx"` | `"atx"`, `"setext"` | Markdown heading syntax |
| `sentence_per_line` | `true` | `true` / `false` | Enable one-sentence-per-line formatting |
| `math_normalization` | `true` | `true` / `false` | Normalize whitespace inside math formulas |
| `en_dash_promotion` | `"llm_only"` | `"llm_only"`, `"off"`, `"aggressive"` | Hyphen→en-dash promotion strategy |

- **`history.json`**: Keeps an append-only run log. **`polish.py` automatically appends records here upon completion** — the LLM does NOT need to write this file manually. Example entry:
  ```json
  {"timestamp": "2026-06-24T10:30:00", "file": "paper.md", "sentences": 142, "warnings": 0, "language": "de", "notes": ""}
  ```

## Gotchas (Common Pitfalls)

Read before reviewing the output:
- **CJK + abbreviation conflict**: `Li et al.提出` — CJK immediately following an abbreviation like `et al.` might bypass standard word boundary checks. The script handles this, do NOT report it as a false sentence break.
- **Decimal spaces**: `3 . 14` -> `3.14`. Fix manually if the script misses any space-in-number OCR errors.
- **Currency vs math**: `$100` is currency (no spaces/operators), `$x + y$` is math. Watch out for single-letter math variables (like `$n$`) misclassified as currency or vice-versa.
- **Hyphen vs en-dash**: The script does NOT convert hyphens. Promoting `-` to `–` in numeric ranges (e.g., `pp. 12-15` -> `pp. 12–15`) must be done during LLM review (see `formatting-rules.md` for guidelines).
- **Unbalanced Display Math**: If `$$` delimiters are unbalanced, the script outputs a `[WARNING]` to stderr. Check stderr and fix the delimiters manually.
- **Ligatures & environments**: Ligatures (`ﬁ`->`fi`) are destroyed. LaTeX environments (like `\begin{align}`) are intentionally left untouched by the script.

## Workflow

### Step 1: Run the Polish Script
Run the deterministic pipeline (creates `<input>-polished.md` and appends to `history.json`):
```bash
uv run $HOME/.agents/skills/pdf2md-polish/polish.py polish <input.md>
```
*Fallback: Use `python3` if `uv` is unavailable.*

Available subcommands:
- `polish` — Full processing pipeline (default). Outputs `<input>-polished.md`.
- `headings` — Extract heading skeleton (compact JSON) for LLM analysis.
- `apply` — Apply heading level changes from a JSON mapping.

### Step 2: Adjust Heading Hierarchy
1. Extract the heading skeleton:
   ```bash
   uv run $HOME/.agents/skills/pdf2md-polish/polish.py headings <polished.md>
   ```
2. Determine correct hierarchy (title = `#`, section = `##`, subsection = `###`) according to [formatting-rules.md](references/formatting-rules.md).
3. Apply the hierarchy mapping (JSON format `{"line_num": "##"}`):
   ```bash
   uv run $HOME/.agents/skills/pdf2md-polish/polish.py apply <polished.md> -m '{"148": "##", "203": "###"}'
   ```

### Step 3: Semantic Review & Output
1. Run a semantic review on the output to fix lingering OCR issues, misplaced math punctuation, or image paragraph splits (see [ocr-patterns.md](references/ocr-patterns.md)). Do NOT rewrite or rephrase the entire document; use targeted replacement edits.
2. Overwrite the original file with the polished result. Ensure encoding is explicit UTF-8.

### Reference Examples
Three-way comparison showing script vs. full pipeline boundaries:
- `examples/sample_input.md` — Raw OCR/PDF input.
- `examples/sample_prepass.md` — Output of `polish.py polish` alone (deterministic script only).
- `examples/sample_output.md` — Full script + LLM pipeline result.

Diffing `sample_prepass.md` vs `sample_output.md` shows exactly what the LLM step adds (image repositioning, OCR character fixes, math punctuation).
