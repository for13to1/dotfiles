---
name: pdf2md-polish
description: Use when the user provides a markdown file (.md) and asks to clean up, polish, proofread, reformat, or tidy it up. Also use when the user asks to apply heading/heading-level/equation/sentence-per-line formatting rules to a markdown file. Explicit trigger keywords: "pdf2md-polish", "polish", "tidy up", "proofread", "reformat", "校对", "格式化", "整理", "清理".
---

# Markdown Post-Processing

This skill provides a **hybrid workflow** (script + LLM) for polishing markdown files with OCR artifacts, broken paragraphs, or messy formatting.

## When to Use

Trigger this skill when:
- User provides a markdown file (.md) and asks to clean up, polish, proofread, reformat, or tidy it up
- User asks to apply heading, equation, or sentence-per-line formatting rules to a markdown file
- User explicitly mentions any trigger keyword: "pdf2md-polish", "polish", "tidy up", "proofread", "reformat", "校对", "格式化", "整理", "清理"

## Architecture: Hybrid Mode

Responsibilities are split between a deterministic Python script and the LLM:

| Step | Owner | Tasks |
|------|-------|-------|
| 1. OCR cleanup | **Script** | Ligature replacement (`ﬁ`→`fi`), prose-safe stray backslash removal |
| 2. Block parsing | **Script** | Lightweight OCR/PDF-oriented block detection for headings, rules, images, tables, code fences, display math, lists, and paragraphs |
| 3. Math & link protection | **Script** | Preserve display math as structural blocks; protect inline math, links, and images block-locally while processing prose |
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
- **OCR ligature cleanup**: `ﬁ`→`fi`, `ﬂ`→`fl`, `ﬃ`→`ffi`, etc.
- **OCR/PDF block parsing**: Treats headings, horizontal rules, images, HTML tables, pipe tables, code fences, display math, lists, and normal paragraphs as separate processing units.
- **Soft-line reflow**: Rejoins PDF/OCR physical line wraps inside prose paragraphs before sentence splitting.
- **Abbreviation-aware sentence splitting**: Knows common abbreviations (Fig., e.g., et al., z. B., etc.) in multiple languages (English, German, French, Spanish) and does NOT break sentences on their internal dots.
- **Markdown link & image protection**: Preserves links (`[text](url)`) and images (`![alt](url)`) during sentence splitting so that punctuation (such as periods) inside descriptions or URLs does not cause false sentence breaks.
- **Caption handling**: Reflows split figure/table captions such as `Fig. 1.` followed by caption text.
- **Recursive list processing**: Reflows paragraphs inside list items recursively, supporting arbitrarily nested lists, code fences, and display math while preserving original indentation structures.
- **Block-local math handling**: Preserves display math blocks and protects inline math within each prose block; unbalanced math warnings stay local to the affected block.
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
   uv run $HOME/.agents/skills/pdf2md-polish/polish.py apply <polished.md> -m '{"line": "##", ...}'
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

##### Common Issues to Watch For

- **Images splitting sentences**: OCR-converted text sometimes places images/figure captions in the middle of a sentence. Detection: if the line before an image does NOT end with sentence-ending punctuation (`.`, `!`, `?`), the sentence is likely split by the image. Move the image and caption after the complete sentence.
- **Punctuation inside math expressions**: OCR may place commas or periods inside math delimiters, e.g., `$\varphi, $` should be `$\varphi$,`. Check for punctuation followed by a space before the closing `$`.

#### Additional Rules

- Preserve all original content and meaning. Do not add, remove, or rephrase substantive text.
- Use consistent list markers (prefer `-` for unordered lists).
- Remove spurious whitespace and trailing spaces.

### Step 3: Output

Overwrite the original file with the polished result (rename `-polished.md` back to the original filename). Report a brief summary of changes made.
- **Encoding requirement**: Always read and write markdown files using explicit UTF-8 encoding to prevent CP-1252 or platform-specific coding issues and preserve special mathematical symbols, Greek letters, and non-ASCII punctuation.

## Script Location

```
$HOME/.agents/skills/pdf2md-polish/polish.py
```

Dependencies: Python 3.10+ (standard library only, no external packages). Run via `uv run` (uses project Python) or `python3` as fallback.
