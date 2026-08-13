# Design Notes: Sentence-Stream Addressing for Living Documents

**Status: DESIGN MEMO — NOT IMPLEMENTED.**

This document captures a design for content-addressed sentence-level navigation of polished markdown. It is **not** part of the current workflow. The batch pipeline (`polish` → `headings` → `apply` → `finalize`) is unchanged and sufficient for its model.

**Load this file only when working on document addressing.** Trigger conditions are listed at the bottom; until they fire, treat this as an archive, not a spec.

---

## 1. The model: prose as source code

The polished output's one-sentence-per-line format is not a style preference — it is the **serialization of the sentence stream**: a document is a linear stream of sentences, and each line is one unit of that stream.

| Natural language | Source code | This project |
| --- | --- | --- |
| sentence | statement / line | one line |
| paragraph | function (cohesive unit) | group of lines |
| heading | module / class | hierarchy |
| document | program | file |
| sentence ID | symbol / pointer | content addressing |

Consequence: **line = addressable unit = one sentence (or one atomic block).** Lists, blockquotes, display math, code fences are atomic units (the block parser already treats them as such); prose is split into sentences by `split_sentences_in_text`.

Why sentence granularity: the sentence is the smallest unit of natural language that carries a complete proposition. Paragraphs are organizational (and their boundaries are fuzzy in OCR — the block parser exists partly because of this); headings are hierarchical. **The sentence is the only unit with unambiguous boundaries**, given the terminator-recognition machinery already built (sentinels for abbreviations, decimals, URLs, math, ellipses).

---

## 2. Two kinds of "locating" — and why numbering is for machines only

- **Humans and LLMs navigate by content**: "the sentence about ToF sensors". No numbering needed; fuzzy search (fzf/ripgrep) or semantic reference covers this.
- **Machines need deterministic addressing**: an ID that unambiguously selects a unit so an operation can be applied or referenced exactly.

Numbering exists only for the machine case. The design below is about machine addressing; human navigation is out of scope and solved by search.

---

## 3. The four-layer addressing model

A reference composes identity + location, and resolution uses context:

```text
s-8f3a2b@47
└─identity─┘└location┘
```

### Layer 1 — Identity: pure content hash (`s-<hash>`)

- **ID = hash(sentence content)** — a pure function; **derived on demand, never stored** (see §5).
- **Drift semantics**: content edited → hash changes → old reference fails. This is the correctness property that beats line numbers: line numbers silently apply edits to the wrong place after reflow; content IDs **refuse** when the target changed. Silent corruption → loud error.
- Same model as git blobs: the hash is not in the file; it is computed from the file.

### Layer 2 — Location: sentence-stream ordinal (`@N`)

- **N = ordinal among real sentence terminators** (`。！？.!?` etc., after sentinel protection). "The 47th sentence" = the sentence closed by the 47th real terminator.
- Properties:
  - **Linguistically grounded**: meaningful to humans ("sentence 47" is readable; occurrence indices are not).
  - **Immune to layout**: reflow, line wrapping, heading level changes, whitespace — the ordinal does not move, because it counts the linguistic stream, not the layout stream.
  - **Bypasses paragraph segmentation entirely** — the fuzziest layer of OCR. Paragraphs can be mis-split or merged without affecting sentence ordinals. This is "paragraph + sentence" addressing with the unreliable part removed.
  - **Deterministic and zero-state**: counting reuses the existing terminator machinery (sentinel-protected abbreviation/URL/math/ellipsis handling in `split_sentences_in_text`).
- **Stability (the honest cost)**: any sentence inserted or deleted *before* N renumbers all subsequent ordinals. Positional fragility — shared by every positional scheme, including line numbers and paragraph+sentence.

### Layer 3 — Disambiguation: context as a filter, not a key

- **Duplicates are natural in this corpus**: abstract/conclusion restatements, repeated caption boilerplate ("Fig. 3 shows..."). A duplicate sentence is **one identity, many locations**.
- **Context is a property of location, not identity.** Therefore context must **not** be baked into the ID: `hash(content + neighbors)` means a neighbor edit changes this sentence's ID — false drift, worse than the collision it solves. The identity layer must stay pure.
- Resolution instead: `locate s-8f3a2b` returns **all candidates with ±1 sentence context**; the caller (human or LLM) disambiguates by meaning. Optional filter: `locate s-8f3a2b --ctx "conclusion"`.
- **Apply semantics split**:
  - *Content-semantic operations* (e.g., "demote this heading style to `##`"): apply to **all occurrences** by default — for repeated captions/boilerplate this is usually exactly what is wanted. Ambiguity is a feature here.
  - *Location-specific operations* (edit exactly one occurrence): disambiguate via context filter or ordinal.

**Comparison of locator schemes** (why ordinal was chosen over the alternatives):

| Scheme | Stability | Problem |
| --- | --- | --- |
| line number | shifts on any edit/reflow | transport only (§4) |
| paragraph + sentence | breaks on paragraph reflow | paragraph boundaries fuzzy in OCR |
| content hash (identity alone) | never drifts unless content changes | duplicates collide |
| occurrence index `#2` | renumbers only when duplicate-class membership changes | opaque ("2nd copy" is not meaningful); renumbers when a new copy is inserted before |
| context baked into ID | neighbor edits invalidate | **false drift — rejected** |
| sentence ordinal `@N` | renumbers on any prior insert/delete | positional, but linguistically meaningful; immune to layout |

Ordinal wins for this use case because references are read by humans and LLMs ("sentence 47" is intelligible), not just consumed by machines. If machine-only stability ever matters more, `#2` is the fallback.

### Layer 4 — Naming: semantic labels (human-authored)

- Hash addressing covers automatic cases; it cannot express *meaning*. For the rare case where a human wants to permanently name a spot ("the note in the conclusion") and keep referencing it across edits, use a **semantic label**:

  ```markdown
  <!-- §conclusion-note -->
  ```

- Human-written, meaningful, optional, and orthogonal to hash addressing. This is LaTeX `\label{...}` in markdown form.

---

## 4. Why not just line numbers

Line numbers are the **transport layer** (LSP uses `line:character`; diff and `grep -n` are native to them). They should not be replaced, only *superseded as the reference layer* — the same way URLs supersede IPs without removing IPs.

Within a **single atomic run** (the current batch model: `headings` → `apply`, no edits in between), line numbers are perfectly stable and `apply`'s current `{"148": "##"}` JSON mapping is correct. The addressing system earns its keep only in the living-document model (§6).

---

## 5. "Derive, don't store"

Because IDs are pure functions of content:

- **The source stays pristine** — no hashes, no anchors, no comments in the human-readable file. Zero pollution (this was a hard requirement: hashes are not for human reading).
- **No sidecar, no sync problem** — there is no index file to go stale; `hash(line)` *is* the index. Like a compiler's symbol table, it is implicit.
- **Recomputable at any time, from any version of the file** — old IDs still resolve against new versions if the content survived.

The only cost: computing a hash per line at query time — negligible.

---

## 6. When this pays off (and the trigger conditions)

The batch model (`polish` → `finalize`, archive, done) never needs addressing. The design targets the **living-document model**: the same file re-polished and edited across sessions, with cross-version references.

Implement only after the need bites — three-strikes rule:

1. The same document is re-polished across **≥ 2 sessions** (not one-shot finalized).
2. You (or an agent conversation) refer to "that sentence" **after edits** — and line numbers no longer locate it reliably.
3. A mapping or edit must survive a version change of the source file (the old silent-corruption failure mode of line numbers actually occurs).

Two of three → implement.

---

## 7. Implementation sketch (when triggered)

Grounded in the existing code; additive, not a rewrite:

- **`polish.py ids <file>`** — emit a table `s-<hash>  @N  L<line>  <text>` for every sentence/atomic block. Never writes to the file (consistent with `headings` writing to stdout).
- **`apply` accepts references, not just line numbers**: `@N`, `s-<hash>`, `s-<hash>@N` alongside the current JSON mapping. **Verify by recomputation before applying; refuse loudly on mismatch** (the drift-detection property).
- **`locate <ref> [--ctx ...]`** — resolve to candidate line(s), print each with ±1 sentence context; duplicate hashes return all candidates (git short-hash ambiguity handling).
- **Reuse, don't rebuild**:
  - Terminator counting: the sentinel machinery in `split_sentences_in_text` already distinguishes real terminators from `et al.`, decimals, URLs, math, ellipses. The ordinal counter is a free by-product.
  - Atomic-unit identification: `parse_blocks` already classifies code fences / display math / tables / lists / blockquotes — these take block-level IDs, not sentence IDs.
  - In one-sentence-per-line output, **sentence ordinal ≈ prose-line ordinal**, so the mapping between the two is nearly free.
- **Hash size**: 6 hex chars (~16M space) is plenty for a ~700-sentence document; collisions resolve to candidate lists, not failures.

## 8. Non-goals (explicit)

- No persistent sidecar index (violates §5).
- No context inside the ID (rejected in §3).
- No pollution of the human-readable source (hard requirement).
- No replacement of the batch workflow — it stays as-is.
- No semantic-label generation by the tool (labels are human-authored by design).

## 9. Acknowledged edge cases

- **Duplicate sentences are expected**, not exceptional, in this corpus. The design treats them as the normal case (Layer 3).
- **First/last sentence**: no left/right context — pad with a sentinel if context display needs it; resolution by ordinal still works.
- **Fragments**: the splitter emits segments that approximate grammatical sentences; fragments receive IDs too — fine for addressing, imperfect linguistically (accepted).
- **Terminator ambiguity** (decimals, abbreviations, URLs, quote-adjacent periods): already solved by the sentinel machinery; the ordinal counter must reuse it, never count raw `.`/`!`/`?`.
