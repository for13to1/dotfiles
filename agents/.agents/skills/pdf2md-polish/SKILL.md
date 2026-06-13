---
name: pdf2md-polish
description: Use when the user wants to post-process, proofread, or reformat markdown files converted from PDF (e.g. by minerU, marker, nougat, or similar tools). Also use when the user mentions "markdown校对", "markdown格式化", "pdf2md", or asks to apply heading/heading-level/equation/sentence-per-line formatting rules to markdown.
---

# Markdown Post-Processing for PDF-Converted Documents

This skill provides a **hybrid workflow** (script + LLM) for polishing markdown output from PDF-to-markdown conversion tools (minerU, marker, nougat, etc.).

## When to Use

Trigger this skill when:
- User provides a markdown file converted from PDF and asks to polish/proofread it
- User mentions PDF-to-markdown conversion workflow
- User asks to reformat markdown with specific heading, equation, or sentence rules

## Architecture: Hybrid Mode

Responsibilities are split between a deterministic Python script and the LLM:

| Step | Owner | Tasks |
|------|-------|-------|
| 1. OCR cleanup | **Script** | Ligature replacement (`ﬁ`→`fi`), prose-safe stray backslash removal |
| 2. Block parsing | **Script** | Lightweight OCR/PDF-oriented block detection for headings, rules, images, tables, code fences, display math, lists, and paragraphs |
| 3. Math protection | **Script** | Preserve display math as structural blocks; protect inline math block-locally while processing prose |
| 4. Paragraph reflow & sentence splitting | **Script** | Reflow PDF/OCR soft line breaks, then abbreviation-aware sentence splitting (`Fig. 1`, `e.g.`, `et al.` etc.) into one sentence per line |
| 5. Heading hierarchy | **LLM** | Promote headings so sections start at `##`, infer document title |
| 6. Semantic review | **LLM** | Fix edge cases the script missed, verify meaning preserved |

## Workflow

### Step 1: Run the Python Script

```bash
uv run --python 3.10+ agents/.agents/skills/pdf2md-polish/polish.py polish <input.md>
```

Use `uv run` to ensure a consistent Python environment. `uv` will automatically find or download a suitable Python 3.10+ interpreter. No system Python dependency.

Available subcommands:
- `polish` — Full processing pipeline (default)
- `headings` — Extract heading skeleton for LLM analysis
- `apply` — Apply heading level mapping from LLM

```bash
# Extract headings (compact view for LLM to determine hierarchy)
uv run --python 3.10+ agents/.agents/skills/pdf2md-polish/polish.py headings <polished.md>

# Apply heading changes (JSON mapping: line_number → new prefix)
uv run --python 3.10+ agents/.agents/skills/pdf2md-polish/polish.py apply <polished.md> -m '{"148": "###"}'
```

The script handles:
- **OCR ligature cleanup**: `ﬁ`→`fi`, `ﬂ`→`fl`, `ﬃ`→`ffi`, etc.
- **OCR/PDF block parsing**: Treats headings, horizontal rules, images, HTML tables, pipe tables, code fences, display math, lists, and normal paragraphs as separate processing units.
- **Soft-line reflow**: Rejoins PDF/OCR physical line wraps inside prose paragraphs before sentence splitting.
- **Abbreviation-aware sentence splitting**: Knows common abbreviations (Fig., e.g., et al., etc.) and does NOT break sentences on their internal dots.
- **Caption handling**: Reflows split figure/table captions such as `Fig. 1.` followed by caption text.
- **Conservative list processing**: Reflows simple list-item paragraphs while preserving complex/nested list structures.
- **Block-local math handling**: Preserves display math blocks and protects inline math within each prose block; unbalanced math warnings stay local to the affected block.
- **One sentence per line**: Sentences end at `.`, `!`, `?`, `。`, `！`, `？`. Same-paragraph sentences are adjacent (no blank lines); paragraphs separated by one blank line.
- **Markdown structure preserved**: Headings, rules, lists, code fences, tables, images, and math blocks are not broken by sentence splitting.

Default output: `<input>-polished.md`

### Step 2: LLM Post-Processing (Heading Hierarchy)

After the script runs, adjust heading levels:

1. Extract heading skeleton:
   ```bash
   uv run --python 3.10+ agents/.agents/skills/pdf2md-polish/polish.py headings <polished.md>
   ```
2. Analyze the skeleton to determine correct hierarchy (title = `#`, top-level sections = `##`, subsections = `###`, etc.)
3. Apply changes:
   ```bash
   uv run --python 3.10+ agents/.agents/skills/pdf2md-polish/polish.py apply <polished.md> -m '{"line": "##", ...}'
   ```
   - **JSON format constraint**: Ensure the JSON mapping for the `-m` argument is a valid, single-line JSON string without Markdown code block formatting (e.g., no ```json backticks).


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

#### Additional Rules

- Preserve all original content and meaning. Do not add, remove, or rephrase substantive text.
- Use consistent list markers (prefer `-` for unordered lists).
- Remove spurious whitespace and trailing spaces.

### Step 3: Output

Write the final result to a new file (default: `<original-name>-final.md`) or overwrite in-place if the user prefers. Report a brief summary of changes made.
- **Encoding requirement**: Always read and write markdown files using explicit UTF-8 encoding to prevent CP-1252 or platform-specific coding issues and preserve special mathematical symbols, Greek letters, and non-ASCII punctuation.

## Script Location

```
agents/.agents/skills/pdf2md-polish/polish.py
```

Dependencies: Python 3.10+ (standard library only, no external packages). Run via `uv run --python 3.10+` for portable Python resolution.
