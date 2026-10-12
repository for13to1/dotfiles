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

## Configuration

- **Language detection**: handled automatically by character rules (CJK / CJK punctuation / full-width forms). No `config.json` is needed; the script auto-detects Chinese-English mixed prose and inserts a space at CJK↔ASCII boundaries (`使用 Python`).

## Gotchas

- **CJK after abbreviations**: `Li et al.提出` is handled by the script; do not "fix" as a false sentence break.
- **Decimal spaces**: `3 . 14` → `3.14` if the script misses any.
- **Currency vs math**: `$100` vs `$x + y$`; be careful with single-letter math like `$n$`.
- **Hyphen vs en-dash**: script does not promote `-` to `–`; do that in LLM review when appropriate.
- **Unbalanced `$$`**: the `check` subcommand reports it; fix delimiters manually.
- **Ligatures / LaTeX envs**: ligatures are normalized; `\begin{align}`-style blocks are treated as math block boundaries and are not rewritten to `$$...$$`; internal whitespace normalization may still apply.
- **Single-column pipe tables** after conversion may be mis-parsed lists/code; `check` flags them — verify by eye before keeping.
- **Half-width `,;:` stays in table cells** by design (range notation `[0x0, 0x3ff]`); `check` only flags half-width punctuation next to Han in prose.

## Workflow

### Step 1: Run the Polish Script

Default output is a sibling working file, not an in-place overwrite:
```bash
uv run $HOME/.agents/skills/pdf2md-polish/polish.py polish paper.md
```
Fallback: `python3` if `uv` is unavailable.

If `polish` exits non-zero (unreadable input, invalid markdown), stop and report the error; do not continue to later steps.

Then run the baseline validation on the working copy — exit 1 here is expected, not an error. Treat the report as a scope snapshot (what polish refused, how much LLM work awaits), not a fix-by-line list: Step 2/3 edits shift line numbers, and Step 4 re-runs `check` for authoritative locations:

```bash
uv run $HOME/.agents/skills/pdf2md-polish/polish.py check paper-polished.md
```

Artifact convention:

- `<name>.md` is the raw source; it is not edited during review.
- `<name>-polished.md` is the working copy created in Step 1 and used in Steps 2-4.
- After finalization, `<name>.md` is the polished deliverable and `<name>.origin.md` holds the raw-source backup.

Subcommands:

- `polish` — deterministic pipeline → `<name>-polished.md`
- `headings` — compact text heading skeleton for hierarchy decisions (add `-c N` for more context)
- `apply` — apply heading level mapping and overwrite the polished working copy
- `check` — validation report (exit 1 if any issues); run at Step 1 (baseline scope), Step 4 (gate before finalize), and after any manual edits
- `finalize` — back up the original and promote the polished working copy

What `polish` now does automatically (beyond OCR cleanup and sentence splitting):

- Converts HTML `<table>` blocks to GFM pipe tables (aborts and preserves the HTML if `rowspan`/`colspan` is present, if text sits outside the table markup — `<table>…</table>` or bare `<tr>` rows — or if a `<table>` opener has no `</table>`).
- Inserts CJK↔ASCII spacing inside pipe-table and converted HTML-table cells (inline code/math spans are protected; half-width `,;:` in table cells is a deliberate convention for range notation such as `[0x0, 0x3ff]`).
- Repairs code fences: merges fences that extraction split at blank lines (compatible languages only), relabels `` ```m4 ``/`` ```rust ``/`` ```txt `` fences whose content is clearly C code, and unwraps `` ```txt `` fences that actually contain Chinese prose.
- Re-indents C-family (`c`,`h`,`cpp`,`hpp`) code blocks by brace depth; unbalanced blocks are left unchanged.

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

`headings` may list entries marked `?` — numbered titles that lost heading status (plain text or trapped inside a `` ```txt `` fence), with a suggested level. `apply` mapping values:

- `"##"`…`"######"` — set the level of an existing heading; also **promotes** a plain numbered-title line into a heading. If the line is the only content of a `` ```txt ``/`` ```text ``/no-language fence, the fence markers are removed too. Promotion inside C-family fences is refused (warning).
- `"-"` — **demote** a heading to a plain paragraph (`## 【成员】` → `【成员】`).
- Example for restoring lost headings: `-m '{"299": "######", "468": "######", "12": "-"}'`.

### Step 3: Semantic Review & Output

Mechanical findings (ligatures, unbalanced `$$`, detached pure-label captions, spacing, tables, fences) are `check`'s job — Step 4's loop surfaces them with fresh line numbers; don't re-scan by eye. This checklist covers only the judgment cases `check` cannot decide:

- [ ] OCR confusions near math/digits (`l`/`1`, `O`/`0`, `S`/`5`) when unambiguous
- [ ] Figure/table captions split from anchors by a spurious blank line (`check` only flags pure-label ones)
- [ ] Math punctuation placed outside/inside `$...$` incorrectly
- [ ] Hyphen vs en-dash promotion where appropriate (see Gotchas)

Review target:

- Produce fenced `diff` blocks for changed lines only (not the full document), against the polished working copy from Steps 1-2, then apply those edits back to it.

### Step 4: Validate

Gate before finalize: run the validation pass on the working copy, fix findings in place, re-run until it exits 0 (repeat this loop as needed):

```bash
uv run $HOME/.agents/skills/pdf2md-polish/polish.py check paper-polished.md
```

- Exit 0 = clean; exit 1 = findings printed as `L<line> [category] message`.
- Categories: `fence` (unclosed/wrong language/prose trapped), `fence-split`, `table` (ragged/residual HTML/single-column), `heading` (lost numbered titles), `cjk` (missing CJK↔ASCII space), `punct` (half-width punctuation next to Han in prose, duplicated punctuation, unbalanced quotes), `caption` (detached pure-label caption), `math` (unbalanced `$$`), `space` (trailing/double spaces), `ocr` (residual ligatures).
- Judgment-call findings (e.g. single-column table that is actually fine): if they must remain, confirm with the user and record them — Step 6 then checks against this accepted set instead of exit 0.
- `--json` emits machine-readable output; `-o report.md` writes the report to a file.
- Re-run `check` after any manual edits made outside this step.

### Step 5: Finalize Files

After Step 4 passes (check exits 0, or only user-accepted findings remain), finalize:

1. Run `uv run $HOME/.agents/skills/pdf2md-polish/polish.py finalize <name>.md`.
2. The command backs up the original as `<name>.origin.md` and promotes the polished copy to `<name>.md`, rolling back if promotion fails.

Exceptions:

- If `<name>.origin.md` already exists, `finalize` refuses to overwrite it; stop and ask the user whether to move the old backup aside, then retry.
- If the user explicitly says they want to keep the working copy `<name>-polished.md` without finalizing (e.g., "just polish, don't finalize"), skip Step 5.

Example:

- `paper.md` → backup as `paper.origin.md`
- `paper-polished.md` → final deliverable `paper.md`

Rules:

- The polished file is the final artifact to keep.
- The original input is backed up by default for traceability; the user may delete `<name>.origin.md` after verification.

### Step 6: Verify & Done

Confirm the run actually completed before stopping:

- `<name>.md` is the polished deliverable and `<name>.origin.md` holds the raw source (in the default path, `<name>-polished.md` was consumed by `finalize`).
- `check` exits 0 on the final file — or exits 1 with exactly the findings the user accepted at Step 4, nothing more.

Then report to the user: deterministic fixes applied, heading mapping used, and the two artifact paths.

### Reference Examples

- `examples/sample_input.md` — raw OCR/PDF input
- `examples/sample_prepass.md` — script-only output
- `examples/sample_output.md` — script + LLM result

Diff `sample_prepass.md` vs `sample_output.md` to see the LLM-only delta.
