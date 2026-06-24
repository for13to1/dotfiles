---
name: pdf2md-polish
description: Use when the user provides a markdown file (.md) and asks to clean up, polish, proofread, reformat, or tidy it up. Also use when the user asks to apply heading/heading-level/equation/sentence-per-line formatting rules to a markdown file. Also use when converting PDF-OCR output, cleaning academic paper markdown, or fixing broken paragraphs from PDF extraction. Trigger keywords: "pdf2md-polish", "polish", "tidy up", "proofread", "reformat", "clean up this markdown", "fix formatting", "one sentence per line", "校对", "格式化", "整理", "清理", "清洗", "OCR 清洗".
---

# Markdown Post-Processing

This skill provides a **hybrid workflow** (script + LLM) for polishing markdown files with OCR artifacts, broken paragraphs, or messy formatting.

## When to Use

Trigger this skill when:
- User provides a markdown file (.md) and asks to clean up, polish, proofread, reformat, or tidy it up
- User asks to apply heading, equation, or sentence-per-line formatting rules to a markdown file
- User explicitly mentions any trigger keyword: "pdf2md-polish", "polish", "tidy up", "proofread", "reformat", "校对", "格式化", "整理", "清理"

## Configuration

This skill reads `config.json` from its directory. If the file is missing, defaults apply.

| Key | Default | Values | Description |
|-----|---------|--------|-------------|
| `overwrite_original` | `true` | `true` / `false` | Overwrite the input file with polished output |
| `language` | `"auto"` | `"auto"`, `"en"`, `"de"`, `"fr"`, `"es"`, `"zh"` | Primary language (affects abbreviation list priority) |
| `heading_style` | `"atx"` | `"atx"`, `"setext"` | Markdown heading syntax |
| `sentence_per_line` | `true` | `true` / `false` | Enable one-sentence-per-line formatting |
| `math_normalization` | `true` | `true` / `false` | Normalize whitespace inside math formulas |
| `en_dash_promotion` | `"llm_only"` | `"llm_only"`, `"off"`, `"aggressive"` | Hyphen→en-dash promotion strategy |

To customize: edit `config.json` directly, or instruct the agent to update it.

## Processing History

The skill maintains `history.json` as an append-only log of processing runs. After each successful polish, append an entry:

```json
{
  "timestamp": "2026-06-24T10:30:00",
  "file": "paper.md",
  "sentences": 142,
  "warnings": 0,
  "language": "de",
  "notes": ""
}
```

The agent reads this file to detect patterns across runs (e.g., recurring OCR issues from the same scanner) and to avoid reprocessing files that were already polished.

## References

Detailed reference material lives in the `references/` directory. The agent reads these on demand when relevant:

- **`references/abbreviation-table.md`** — All abbreviations the script recognizes (100+ entries across English, German, French, Spanish). Consult when the script makes a false sentence break on an abbreviation.
- **`references/ocr-patterns.md`** — Common OCR/PDF artifacts: what the script handles automatically vs. what needs LLM judgment. Consult when reviewing script output for missed patterns.

## Gotchas

These are known edge cases and pitfalls. Read before reviewing the script's output.

- **CJK + abbreviation conflict**: `Li et al.提出` — when CJK characters immediately follow abbreviations like `et al.`, the script's `\b` word-boundary assertion may behave differently than expected. The script handles this via CJK-aware logic, but during LLM semantic review, do NOT flag these as false sentence breaks.
- **Decimal numbers with OCR spaces**: `3 . 14` (OCR inserts spaces in numbers) — the script merges these back to `3.14`. But if you see `3 . 14` in the output, the script missed it; fix it manually.
- **Currency vs inline math**: `$100` is currency (NOT math), `$x + y$` is inline math. The script uses heuristics (starts with digit → currency; contains backslash/letter operators → math). Edge cases like `$n` (single variable) may be misclassified.
- **en-dash intentionally preserved**: The script does NOT convert hyphens to en-dashes. `A–B` (U+2013) stays as-is, but `A-B` (U+002D) also stays as-is. Promoting hyphens to en-dashes in numeric ranges (e.g. `pp. 12-15`) is an LLM-only judgment step — see Step 2 "en-dash flattened to hyphen" instructions.
- **Unbalanced display math**: If `$$` delimiters don't pair up, the script preserves the block unchanged and prints a `[WARNING]` to stderr. The LLM should check stderr output and decide whether to fix the math or leave it.
- **Ligature normalization is one-way**: `ﬁ`→`fi`, `ﬂ`→`fl` etc. are always applied. If the original text intentionally uses Unicode ligatures (rare), they will be destroyed.
- **`\\begin{...}` environments untouched**: LaTeX environments like `align`, `equation`, `gather` are NOT converted to `$$` — converting them would lose multi-line alignment and equation numbering.
- **List/blockquote recursion**: The script processes paragraphs inside list items and blockquotes recursively. Deeply nested structures (>4 levels) may occasionally lose indentation — check output for very deep lists.
- **Trailing hyphen reflow**: The script rejoins lines ending with `-` (OCR soft hyphenation). But legitimate hyphens in compound words (`state-of-the-art` at line end) should NOT be reflowed. The script distinguishes these by checking if the next line starts with a lowercase letter and the hyphenated word is not in a known compound — but false reflows can happen.

## Architecture: Hybrid Mode

Responsibilities are split between a deterministic Python script and the LLM:

| Step | Owner | Tasks |
|------|-------|-------|
| 1. OCR cleanup | **Script** | True-ligature replacement (`ﬁ`→`fi`), prose-safe stray backslash removal, inline whitespace normalization (collapse multi-space/tabs) |
| 2. Block parsing | **Script** | Lightweight OCR/PDF-oriented block detection for headings, rules, images, tables, code fences, display math, lists, blockquotes, and paragraphs |
| 3. Math & link handling | **Script** | Isolate display math as structural blocks and **normalize** their internal spacing; protect inline math, links, and images block-locally while processing prose, normalizing inline-math spacing too |
| 4. Paragraph reflow & sentence splitting | **Script** | Reflow PDF/OCR soft line breaks, then abbreviation-aware multilingual sentence splitting (`Fig. 1`, `z. B.`, `et al.` etc.) into one sentence per line |
| 5. Heading hierarchy | **LLM** | Promote headings so sections start at `##`, infer document title |
| 6. Semantic review | **LLM** | Fix edge cases the script missed, verify meaning preserved |

## Workflow

### Step 1: Run the Python Script

```bash
uv run $HOME/.agents/skills/pdf2md-polish/polish.py polish <input.md>
```

Uses the project's Python environment via `uv run`. If `uv` is unavailable or causes version conflicts, fall back to `python3 $HOME/.agents/skills/pdf2md-polish/polish.py polish <input.md>`.

Available subcommands:
- `polish` — Full processing pipeline (default)
- `headings` — Extract heading skeleton for LLM analysis
- `apply` — Apply heading level mapping from LLM

```bash
# Extract headings (compact view for LLM to determine hierarchy)
uv run $HOME/.agents/skills/pdf2md-polish/polish.py headings <polished.md>

# Apply heading changes (JSON mapping: line_number → new prefix)
uv run $HOME/.agents/skills/pdf2md-polish/polish.py apply <polished.md> -m '{"148": "###"}'
```

The script handles:
- **True-ligature cleanup**: `ﬁ`→`fi`, `ﬂ`→`fl`, `ﬃ`→`ffi`, etc. (en-dash `–` is intentionally left alone — it is meaningful punctuation, e.g. page ranges `pp. 12–15`).
- **OCR/PDF block parsing**: Treats headings, horizontal rules, images, HTML tables, pipe tables, code fences, display math, lists, blockquotes, and normal paragraphs as separate processing units.
- **Inline whitespace normalization**: In prose and headings, collapses runs of spaces/tabs to a single space (inline code, inline math, and link/image targets are protected, so their internal spacing is preserved). Table cells are left untouched.
- **Soft-line reflow**: Rejoins PDF/OCR physical line wraps inside prose paragraphs before sentence splitting.
- **Abbreviation-aware sentence splitting**: Knows common abbreviations (Fig., e.g., et al., z. B., etc.) in multiple languages (English, German, French, Spanish) and does NOT break sentences on their internal dots.
- **Markdown link & image protection**: Preserves links (`[text](url)`) and images (`![alt](url)`) during sentence splitting so that punctuation (such as periods) inside descriptions or URLs does not cause false sentence breaks.
- **Caption handling**: Reflows split figure/table captions such as `Fig. 1.` followed by caption text.
- **Recursive list & blockquote processing**: Reflows paragraphs inside list items and blockquotes recursively, supporting arbitrarily nested lists, code fences, and display math while preserving original indentation structures.
- **Math delimiter normalization**: `\(...\)` inline math → `$...$` and `\[...\]` display math → `$$...$$`, for consistent, widely-rendered output. `\begin{...}` environments (e.g. `align`, `equation`) are left untouched, since converting them to `$$` would lose multi-line alignment/numbering.
- **Block-local math handling (normalizing)**: Isolates display math blocks and protects inline math within each prose block, then **normalizes spacing inside the formula** (e.g. `x_{ i }`→`x_{i}`, `a + b`→`a+b`, `\mathrm{r e c t}`→`\mathrm{rect}`). This rewrites formula whitespace — it does not preserve it byte-for-byte. Unbalanced math warnings stay local to the affected block.
- **One sentence per line**: Sentences end at `.`, `!`, `?`, `。`, `！`, `？`. Same-paragraph sentences are adjacent (no blank lines); paragraphs separated by one blank line.
- **Markdown structure preserved**: Headings, rules, lists, code fences, tables, images, and math blocks are not broken by sentence splitting.

Default output: `<input>-polished.md`

### Step 2: LLM Post-Processing (Heading Hierarchy)

After the script runs, adjust heading levels:

1. Extract heading skeleton:
   ```bash
   uv run $HOME/.agents/skills/pdf2md-polish/polish.py headings <polished.md>
   ```
2. Analyze the skeleton to determine correct hierarchy (title = `#`, top-level sections = `##`, subsections = `###`, etc.)
3. Apply changes:
   ```bash
   uv run $HOME/.agents/skills/pdf2md-polish/polish.py apply <polished.md> -m '{"148": "##", "203": "###"}'
   ```
   - **JSON format**: The mapping is `{"<line_number>": "<new_prefix>"}` — keys are line numbers (as strings), values are the target heading prefix (`##`, `###`, …). Pass a valid single-line JSON string for `-m`. A surrounding ```json code fence is tolerated (the `apply` command strips it automatically), but prefer passing bare JSON.


#### Heading Rules

- The document title MUST use `#` (h1). If no clear title exists, generate and infer an appropriate title based on the abstract or introduction rather than pausing to ask the user (to maintain unattended execution flow).
- All section headings MUST start from `##` (h2) and form a proper hierarchy: `##`, `###`, `####`, etc.
- **Never** use `###` as the top-level heading. If the source starts with `###`, promote it to `##` and shift all sub-headings accordingly.
- Preserve relative nesting depth; only shift the absolute level.

**Example:**
```
# Document Title              ← h1: document title only

## 1. Introduction             ← h2: top-level sections
## 2. Background

### 2.1 Definitions            ← h3: subsections under h2
### 2.2 Notation

#### 2.2.1 Symbol Table        ← h4: sub-subsections
```

#### Semantic Review

- **Do NOT rewrite or output the entire document** during semantic review. If targeted semantic fixes are needed (e.g., merging false splits, fixing OCR typos like `0` vs `O`), use precise line-replacement or diff-editing tools. Do not rewrite, rephrase, or summarize the unchanged text.
- Verify the script's paragraph reflow and sentence splits are correct; merge any false splits or bad joins (e.g. a sentence that got split at a decimal number, or an OCR line break that should remain structural).
- Fix remaining OCR artifacts that require context to identify (e.g. `0` vs `O`, `1` vs `l`).
- Ensure no content was lost or altered during script processing.
- Preserve images, tables, code blocks, and footnotes as-is.

##### Common Issues to Watch For

- **Images splitting sentences**: OCR-converted text sometimes places images/figure captions in the middle of a sentence. Detection: if the line before an image does NOT end with sentence-ending punctuation (`.`, `!`, `?`), the sentence is likely split by the image. Move the image and caption after the complete sentence.
- **Punctuation inside math expressions**: OCR may place commas or periods inside math delimiters, e.g., `$\varphi, $` should be `$\varphi$,`. Check for punctuation followed by a space before the closing `$`.
- **en-dash flattened to hyphen in ranges** (publication-grade only; skip for casual docs): OCR/PDF extraction frequently degrades en-dashes (`–`, U+2013) to plain hyphens (`-`), so a *range* may appear as `pp. 12-15` when it should be `pp. 12–15`. The script deliberately does NOT touch hyphens (too many legitimate uses: `COVID-19`, `state-of-the-art`, `Section 3-2`, model numbers), so this is an LLM-only judgment.
  - **Recall the candidates deterministically** — grep narrows the search so you don't miss any while scanning prose:
    ```bash
    grep -nE '[0-9]+ ?- ?[0-9]+' <polished.md>
    ```
  - **Promote `-` → `–` ONLY when context makes it unambiguously a numeric range**: page ranges (`pp. 12-15`), year/date spans (`2010-2020`), figure/table/equation/section ranges (`Figs. 3-5`, `Eqs. 2-4`), inclusive numeric intervals in prose ("values 5-10").
  - **Leave it as `-` (when in doubt, do nothing) for**: identifiers/model names (`COVID-19`, `RTX-4090`, `IPv6-only`), single hierarchical labels rather than spans (`Section 3-2` meaning "subsection 2 of section 3"), phone/ISBN/serial numbers, hyphenated compounds, and anything you cannot confirm from surrounding text. A wrong promotion is worse than a missed one.

#### Additional Rules

- Preserve all original content and meaning. Do not add, remove, or rephrase substantive text.
- Use consistent list markers (prefer `-` for unordered lists).
- Remove spurious whitespace and trailing spaces.

### Step 3: Output

Overwrite the original file with the polished result (rename `-polished.md` back to the original filename). Report a brief summary of changes made.
- **Encoding requirement**: Always read and write markdown files using explicit UTF-8 encoding to prevent CP-1252 or platform-specific coding issues and preserve special mathematical symbols, Greek letters, and non-ASCII punctuation.

> **Reference examples** (three-way comparison, so the script/LLM boundary is explicit):
> - `examples/sample_input.md` — raw OCR/PDF input.
> - `examples/sample_prepass.md` — output of `polish.py polish` **alone** (deterministic script only). Regenerate with `uv run polish.py polish examples/sample_input.md -o examples/sample_prepass.md`.
> - `examples/sample_output.md` — the **full script + LLM pipeline** result.
>
> Diffing the last two shows exactly what the LLM step adds and the script deliberately leaves alone: moving an image out of the middle of a sentence (§3), OCR character fixes (`a the`→`the`), and moving a stray comma out of math (`$\varphi, $`→`$\varphi$,`) — all context-dependent judgments that belong to the Step 2 LLM pass, not `polish.py`.

## Script Location

```
$HOME/.agents/skills/pdf2md-polish/polish.py
```

Dependencies: Python 3.10+ (standard library only, no external packages). Run via `uv run` (uses project Python) or `python3` as fallback.
