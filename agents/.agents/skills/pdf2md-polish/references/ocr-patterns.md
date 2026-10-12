# Common OCR Patterns

This document catalogs recurring OCR/PDF extraction artifacts that `polish.py` handles automatically, plus patterns that require LLM judgment in the semantic review step.

---

## Handled by Script (Deterministic)

### Ligature Replacement

| OCR Glyph | Replacement | Unicode |
| --- | --- | --- |
| ﬁ | fi | U+FB01 |
| ﬂ | fl | U+FB02 |
| ﬃ | ffi | U+FB03 |
| ﬄ | ffl | U+FB04 |
| ﬅ | st | U+FB05 |
| ﬆ | st | U+FB06 |

**Rule**: Always applied. One-way transformation. If original intentionally uses Unicode ligatures (extremely rare), they will be destroyed.

### Inline Whitespace Collapse

Runs of spaces/tabs in prose and headings → single space. Protected zones: inline code, inline math, link/image targets.

### Soft Line Break Reflow

PDF/OCR physical line wraps inside prose paragraphs are rejoined before sentence splitting. Chinese-English mixed prose gets a space at CJK↔ASCII boundaries (`使用 Python`); CJK punctuation and inline math are unaffected.

```markdown
# Input (OCR physical lines):
The first objective is to design a high-performance
classifier, which runs in real-time on
embedded platforms.

# Output (reflowed):
The first objective is to design a high-performance classifier, which runs in real-time on embedded platforms.
```

### Math Delimiter Normalization

| Input | Output |
| --- | --- |
| `\(...\)` inline | `$...$` |
| `\[...\]` display | `$$...$$` |
| `\begin{...}` environments | Treated as math block boundaries and not rewritten to `$$...$$`; internal whitespace normalization may still apply (rewriting would lose alignment/numbering) |

### Inline Math Spacing Normalization

| Input | Output |
| --- | --- |
| `$x _ { i } + y _ { j }$` | `$x_{i}+y_{j}$` |
| `$\mathrm{r e c t}(t)$` | `$\mathrm{rect}(t)$` |
| `$a + b$` | `$a+b$` |

**Rule**: Interior whitespace of math formulas is rewritten for compactness. This is NOT byte-preserving.

### OCR Number Spaces

| Input | Output |
| --- | --- |
| `3 . 14` | `3.14` |

**Note**: The script attempts to merge these, but complex cases may be missed. Check output.

### HTML Tables

`<table>/<tr>/<td>` blocks are converted to GFM pipe tables: first row becomes the header, ragged rows are padded, `|` in cells is escaped, entities (`&amp;` etc.) are unescaped, and cells receive CJK↔ASCII spacing.

**Degrade rule**: if any `rowspan`/`colspan` attribute is present (or no rows parse, or text sits outside the table markup — `<table>…</table>` or bare `<tr>` rows — or a `<table>` opener has no `</table>`), the block is preserved as HTML with a stderr warning. The `check` subcommand flags residual HTML tables.

### Code Fence Repair

| Artifact | Fix |
| --- | --- |
| Two fences of compatible language separated only by blank lines | Merged into one fence (compatible = same language, or both in the C family `{c,h,cpp,m4}`) |
| `` ```m4 `` / `` ```rust `` / `` ```txt `` / untagged fence whose content is C code (`typedef struct`, `#include`, function signatures) | Relabeled `` ```c `` |
| `` ```txt `` / `` ```text `` fence containing Chinese prose (Han + sentence punctuation, no code signatures) | Fence removed; content restored as a paragraph |

**Not touched**: a `` ```txt `` fence holding a single function signature (e.g. `XcamReturn rkAiqExpParamComb(...);`) — that shape is a lost heading; the `headings`/`apply` tools handle it. Incompatible languages are never merged.

### C-Family Re-indent

`` ```c ``/`` ```h ``/`` ```cpp ``/`` ```hpp `` blocks are re-indented by brace depth. If braces are unbalanced (a line dips negative or the block doesn't end at depth 0), the block is left unchanged.

### Table Cell Spacing

CJK↔ASCII spacing is applied inside pipe-table cells and converted HTML cells, with inline code spans and inline math (`$...$`) spans protected. Half-width `,;:` inside table cells is preserved by convention (range notation). Cell-internal runs of spaces are left as-is (they render as one space) and are not a `check` finding.

---

## Requires LLM Judgment (Semantic Review)

### Images Splitting Sentences

OCR sometimes places images/figure captions mid-sentence.

```markdown
# Input (broken by image):
The key components for RFMI-measurement are the

![image](fig1.jpg)

Fig. 1 Scheme of a PMD-array.

2D-mixer and the 2D-detector.

# Expected output (image moved after sentence):
The key components for RFMI-measurement are the 2D-mixer and the 2D-detector.

![image](fig1.jpg)

Fig. 1 Scheme of a PMD-array.
```

**Detection**: If the line before an image does NOT end with `.`, `!`, or `?`, the sentence is likely split.

### Punctuation Inside Math

OCR may place commas/periods inside math delimiters.

```markdown
# Input (comma inside math):
$\\varphi, $

# Expected output (comma outside):
$\\varphi$,
```

**Detection**: Punctuation followed by a space before closing `$`.

### en-dash Degraded to Hyphen

OCR/PDF extraction frequently converts en-dashes (`–`, U+2013) to hyphens (`-`).

**Promote to en-dash when unambiguously a numeric range**:

- Page ranges: `pp. 12-15` → `pp. 12–15`
- Year spans: `2010-2020` → `2010–2020`
- Figure/table ranges: `Figs. 3-5` → `Figs. 3–5`

**Leave as hyphen when in doubt**:

- Identifiers: `COVID-19`, `RTX-4090`
- Hierarchical labels: `Section 3-2`
- Compound words: `state-of-the-art`
- Phone/ISBN/serial numbers

**A wrong promotion is worse than a missed one.**

### OCR Character Confusion

| Pattern | Example | Fix |
| --- | --- | --- |
| `0` vs `O` | `Fig. 0` → `Fig. O` or `10`? | Context-dependent |
| `1` vs `l` | `lntroduction` → `Introduction` | Usually `I` |
| `rn` vs `m` | `rnodify` → `modify` | Common in low-res scans |
| `a the` (double article) | `overview of a the PMD-chip` | Remove the stray article |

### Unbalanced `$$` Delimiters

If `$$` don't pair up, the script preserves the block unchanged and prints `[WARNING]` to stderr. The `check` subcommand also reports it; decide whether to fix or leave it.

### Single-Column Tables

A converted table with one column is often a mis-parsed code block or key-value list (e.g. a signature block that HTML parsing collapsed). `check` flags these — decide whether to keep the table, convert to a fenced code block, or restore a list.

### Lost Numbered Headings

Extraction sometimes demotes numbered titles (`11.5.2.1.2 RkAiqExpParamComb_t`) into plain paragraphs or `` ```txt `` fences. The script *detects* them (`headings` shows `?` entries with a suggested level; `check` flags them) but the LLM assigns the final hierarchy and calls `apply` to promote/restore.

### Detached Pure-Label Captions

`check` reports an image separated from a pure-label caption (`图 AWB 分块示意图`, no referential verbs) by a blank line. Whether to attach it (and whether the line really is a caption vs. a sentence starting with 图) is LLM judgment.

---

## Patterns NOT Handled (Intentional)

| Pattern | Why skipped |
| --- | --- |
| Hyphen → en-dash promotion | Too many legitimate hyphens; LLM judgment required |
| `\begin{align}` → `$$` | Would lose multi-line alignment and equation numbering |
| Ligature → ASCII in intentional Unicode | Extremely rare; false positives worse than misses |
