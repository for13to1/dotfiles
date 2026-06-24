# Detailed Formatting & Post-Processing Rules

This reference document outlines detailed rules for heading hierarchy, semantic review, and script capabilities to guide the post-processing of OCR/PDF converted markdown documents.

---

## 1. Heading Hierarchy Guidelines

Adjusting heading levels ensures the polished document has a clear and logical hierarchy:
- **Title (h1)**: The document title MUST use a single `#`. If the source document lacks a clear title, infer one based on the abstract or introduction rather than pausing to prompt the user (maintaining automated execution flow).
- **Sections (h2)**: All top-level sections (e.g., Introduction, Methodology, Conclusion) MUST start at `##` (h2).
- **Subsections**: Subsections under h2 must use `###` (h3), sub-subsections must use `####` (h4), and so on.
- **Top-level restriction**: Never use `###` as the top-level section heading. If the source begins at `###`, promote it to `##` and shift all nested sub-headings relative to it to preserve nesting depth.

**Example Hierarchy:**
```markdown
# High-Performance Neural Network Classifier      <-- Title (h1)

## 1. Introduction                                <-- Section (h2)
## 2. Architecture

### 2.1 Layer Design                              <-- Subsection (h3)
### 2.2 Optimizer Selection

#### 2.2.1 Learning Rate Scheduler                <-- Sub-subsection (h4)
```

---

## 2. Semantic Review Rules

During the semantic review step (Step 3), follow these guidelines to fix OCR remnants without modifying content:
- **No full rewrites**: Do NOT output or rewrite the entire document. Use precise line-replacement or diff-editing tools to make targeted semantic fixes. Do not rephrase or summarize unchanged text.
- **Verify reflows & splits**: Check the script's paragraph reflows and sentence splits. Merge any false splits or bad joins (e.g., a sentence split at a decimal number, or an OCR line break that should remain structural).
- **Correct OCR character confusion**: Fix artifacts requiring semantic context (e.g., `0` vs `O`, `1` vs `l`, `rn` vs `m`).
- **Maintain structures**: Keep all images, tables, code blocks, and footnotes intact.
- **Formatting consistency**: Use consistent list markers (prefer `-` for unordered lists) and remove trailing whitespace.

---

## 3. Script Capabilities Reference

The `polish.py` script automatically performs the following deterministic cleanup operations during Step 1:
- **True-ligature cleanup**: Replaces ligatures like `ﬁ`→`fi`, `ﬂ`→`fl`, `ﬃ`→`ffi` (leaves en-dashes `–` intact as they are meaningful punctuation).
- **OCR/PDF block parsing**: Parses headings, rules, images, HTML tables, pipe tables, code fences, display math, lists, blockquotes, and normal paragraphs as separate processing units.
- **Inline whitespace normalization**: Collapses multi-spaces/tabs to a single space in prose and headings (protects inline code, inline math, and link/image targets).
- **Soft-line reflow**: Rejoins PDF/OCR physical line wraps inside prose paragraphs before sentence splitting.
- **Abbreviation-aware sentence splitting**: Protects dots inside common multilingual abbreviations (e.g., `Fig. 1`, `z. B.`, `et al.`) from triggering false sentence breaks.
- **Markdown link & image protection**: Preserves markdown link formats (`[text](url)`) and images (`![alt](url)`) during sentence splitting.
- **Caption handling**: Reflows split figure/table captions.
- **Recursive list & blockquote processing**: Reflows paragraphs inside list items and blockquotes recursively, preserving original indentation structures.
- **Math delimiter normalization**: Converts `\(...\)` inline math to `$...$` and `\[...\]` display math to `$$...$$` (LaTeX environments like `\begin{align}` are left untouched to preserve multi-line alignments).
- **Block-local math handling (normalizing)**: Isolates math formulas and rewrites internal whitespace (e.g. `x_{ i }`→`x_{i}`, `a + b` -> `a+b`).
- **One sentence per line**: Sentences end at `.`, `!`, `?`, `。`, `！`, `？` and are placed on their own line. Same-paragraph sentences are adjacent; paragraphs are separated by one blank line.
