"""
pdf2md-polish: Deterministic markdown post-processing for PDF-converted documents.

Handles OCR cleanup, abbreviation-aware sentence splitting,
and one-sentence-per-line formatting. Run this BEFORE letting the LLM adjust
heading hierarchy and handle ambiguous cases.

Usage:
    python polish.py polish input.md [-o output.md]
    python polish.py headings input.md [-c CONTEXT] [-o output.md]
    python polish.py apply input.md -m MAPPING [-o output.md]
    python polish.py finalize input.md
"""

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path

# ── Sentinel placeholders for text protection ──────────────────────────────
# Control characters used to protect specific segments from sentence splitting.
# Cleaned from the input at the start of process() to avoid collision.
_SENTINEL_ABBR = "\x00"  # Protects abbreviation dots
_SENTINEL_URL = "\x01"  # Protects URL and email dots
_SENTINEL_MATH = "\x02"  # Protects math blocks and formula content
_SENTINEL_LINK = "\x03"  # Protects markdown links and images
_SENTINEL_WS = "\x04"  # Protects internal whitespace during inline-whitespace collapse


# ── Warning state ───────────────────────────────────────────────────────────
# process() is used recursively for list items and blockquotes. Keep warning
# accounting scoped to the outermost call so CLI history can record a truthful
# count for the full run.
_WARNING_COUNT = 0
_PROCESS_DEPTH = 0


# ── Abbreviations & tokens that should NOT trigger sentence breaks ──────────
ABBREVIATIONS = [
    "et al.",
    "i.e.",
    "e.g.",
    "etc.",
    "vs.",
    "cf.",
    "approx.",
    "Dr.",
    "Mr.",
    "Mrs.",
    "Ms.",
    "Prof.",
    "Sr.",
    "Jr.",
    "Fig.",
    "Figs.",
    "Tab.",
    "Tbl.",
    "Eq.",
    "Eqs.",
    "Vol.",
    "Vols.",
    "No.",
    "Nos.",
    "Ch.",
    "Chs.",
    "Sec.",
    "Secs.",
    "App.",
    "St.",
    "Ave.",
    "Blvd.",
    "Dept.",
    "Univ.",
    "Inc.",
    "Ltd.",
    "Corp.",
    "Jan.",
    "Feb.",
    "Mar.",
    "Apr.",
    "Aug.",
    "Sep.",
    "Oct.",
    "Nov.",
    "Dec.",
    "a.m.",
    "p.m.",
    "U.S.",
    "U.K.",
    "E.U.",
    "U.N.",
    "al.",
    "op.",
    "cit.",
    "ibid.",
    "id.",
    "viz.",
    "ca.",
    "fl.",
    "ed.",
    "eds.",
    "vol.",
    "no.",
    "ch.",
    "sec.",
    "pp.",
    "pg.",
    # Academic & professional
    "Ph.D.",
    "M.D.",
    "B.S.",
    "M.S.",
    "D.Sc.",
    "B.A.",
    "M.A.",
    "D.V.M.",
    "J.D.",
    "LL.B.",
    "LL.M.",
    # Addresses & common
    "P.O.",
    "Doc.",
    "Ref.",
    "Refs.",
    "misc.",
    "natl.",
    "intl.",
    "assoc.",
    "eng.",
    "phys.",
    "math.",
    "chem.",
    "biol.",
    "sci.",
    "technol.",
    "autom.",
    "magn.",
    "lett.",
    "proc.",
    "trans.",
    "symp.",
    "conf.",
    "Conf.",
    "Res.",
    "Lab.",
    "Labs.",
    "Div.",
    # German
    "z. B.",
    "z.B.",
    "d. h.",
    "d.h.",
    "u. a.",
    "u.a.",
    "s. u.",
    "s.u.",
    "s. o.",
    "s.o.",
    "z. T.",
    "z.T.",
    "bzw.",
    "usw.",
    "vgl.",
    "resp.",
    # German academic & professional titles
    "Dipl.-Ing.",
    "Dipl.-Phys.",
    "Dipl.-Math.",
    "Dipl.-Kfm.",
    "Dipl.-Chem.",
    "Dipl.-Inf.",
    "Dipl.-Biol.",
    "Dipl.-Psych.",
    "Dr.-Ing.",
    "Dr. rer. nat.",
    "Dr. med.",
    "Prof. Dr.",
    "Ing.",
    "Mag.",
    # French
    "c.-à-d.",
    "c-à-d.",
    "M.",
    "Mme.",
    "Mlle.",
    # Spanish
    "p. ej.",
    "p.ej.",
    "Sr.",
    "Sra.",
    "Dra.",
]

# Sort longest first to avoid partial matches
ABBREVIATIONS.sort(key=len, reverse=True)

# Abbreviations that can legitimately end a sentence.
# When followed by space + uppercase, their dots are left unprotected
# so the sentence splitter can break there. Other abbreviations (i.e.,
# e.g., vs., cf., etc.) are always protected because they grammatically
# require content after them.
_BREAKABLE_ABBRS = {"etc.", "approx."}

# Compile single abbreviation matching pattern using word boundaries to prevent
# false positives (e.g. "signal." matching "al.")
_ABBR_PATTERN = re.compile(
    r"(?<![a-zA-Z])(?:" + "|".join(re.escape(abbr) for abbr in ABBREVIATIONS) + r")(?![a-zA-Z])",
    re.IGNORECASE,
)

# Pattern for single uppercase letter initials: "A.", "B.", etc.
_INITIAL_RE = re.compile(r"(?<![a-zA-Z])([A-Z])\.(?=\s|$|[A-Z])")

# Patterns for ellipsis variants
_ELLIPSIS_RE = re.compile(r"\.\.\.|…|\.\s\.\s\.")


def _protect_abbreviations(text: str) -> str:
    """Replace dots in known abbreviations with a sentinel so sentence
    splitting won't break on them. Context-aware abbreviations (etc.,
    approx.) are left unprotected when followed by space + uppercase letter,
    so the sentence splitter can break there."""
    # Protect ellipsis first (before abbreviation matching changes dots)
    text = _ELLIPSIS_RE.sub(
        lambda m: m.group().replace(".", _SENTINEL_ABBR).replace("…", _SENTINEL_ABBR * 3),
        text,
    )

    # Pin the source text so the closure below reads a stable, unmodified
    # string even if the outer `text` variable is rebound later in this
    # function (e.g. after _ABBR_PATTERN.sub reassigns it).
    _source = text

    def _abbr_replacer(m: re.Match) -> str:
        matched = m.group()
        # Check if this is a context-aware abbreviation followed by
        # optional closing punctuation then space + uppercase letter.
        lower = matched.lower()
        if lower in _BREAKABLE_ABBRS:
            end = m.end()
            if end < len(_source):
                rest = _source[end:]
                # Strip optional closing punctuation (quotes, brackets)
                rest_no_punct = rest.lstrip("\"')]}")
                if rest_no_punct.startswith(" "):
                    after_space = rest_no_punct.lstrip(" \t")
                    if after_space and after_space[0].isupper():
                        return matched  # Don't protect — let sentence splitter break here
            # At end of string — also a sentence boundary
            if end == len(_source):
                return matched
        return matched.replace(".", _SENTINEL_ABBR)

    # Protect abbreviations using precompiled pattern with word boundaries
    text = _ABBR_PATTERN.sub(_abbr_replacer, text)
    # Protect single uppercase initials (A., B., C., etc.)
    text = _INITIAL_RE.sub(lambda m: m.group().replace(".", _SENTINEL_ABBR), text)
    return text


def _restore_abbreviations(text: str) -> str:
    """Restore sentinel back to dots."""
    return text.replace(_SENTINEL_ABBR, ".")


# ── OCR artifact cleanup ────────────────────────────────────────────────────
_LIGATURES = {
    "\ufb01": "fi",  # ﬁ
    "\ufb02": "fl",  # ﬂ
    "\ufb03": "ffi",  # ﬃ
    "\ufb04": "ffl",  # ﬄ
    "\ufb00": "ff",  # ﬀ
    "\ufb05": "st",  # ﬅ
    "\ufb06": "st",  # ﬆ
}


# NOTE: en-dash (U+2013) is intentionally NOT in _LIGATURES. It is meaningful
# punctuation (e.g. page ranges "pp. 12-15"); rewriting it to a hyphen would
# alter prose. Only true typographic ligatures are normalized above.


def cleanup_ligatures(text: str) -> str:
    """Fix common OCR ligatures and broadly safe character artifacts."""
    for lig, repl in _LIGATURES.items():
        text = text.replace(lig, repl)
    return text


def cleanup_ocr(text: str) -> str:
    """Fix common OCR ligatures and stray artifacts in prose-like text."""
    text = cleanup_ligatures(text)
    # Remove stray single backslashes that are not part of LaTeX commands,
    # Markdown escapes, or common math/delimiter wrappers.
    # We ensure we do not touch double backslashes (\\) which are valid in LaTeX/Markdown.
    # Includes whitespace, single quote, and double quote in exclusion list to protect valid escapes (e.g. \ , \", \').
    text = re.sub(r"(?<!\\)\\(?!\\)(?=[^a-zA-Z()\[\]$%#{}&_*+\-.!\`<>\"'\s])", "", text)
    # Fix duplicate commas (common OCR artifact): ", ," or ",,"
    text = re.sub(r",\s*,", ",", text)
    return text


# ── Inline whitespace normalization ─────────────────────────────────────────
# Protects inline code spans, inline math, and markdown links/images so their
# internal spacing survives, then collapses runs of spaces/tabs to one space.
_INLINE_CODE_RE = re.compile(r"`+[^`\n]*`+")
_INLINE_MATH_WS_RE = re.compile(r"\$[^$\n]*\$")


def collapse_inline_whitespace(text: str) -> str:
    """Collapse runs of spaces/tabs to a single space within a single line of
    text, protecting inline code spans, inline math (`$...$`), and markdown
    links/images so their internal spacing is preserved.

    Self-contained: protects and restores on its own, so it is safe to call on
    both prose (where math/links may already be sentinel-protected — a no-op
    for those) and raw heading lines (which carry no prior protection)."""
    mapping: dict[str, str] = {}
    counter = [0]

    def _protect(pattern: re.Pattern) -> None:
        def _replacer(m):
            key = f"{_SENTINEL_WS}{counter[0]}{_SENTINEL_WS}"
            counter[0] += 1
            mapping[key] = m.group()
            return key

        nonlocal text
        text = pattern.sub(_replacer, text)

    _protect(_INLINE_CODE_RE)
    _protect(_INLINE_MATH_WS_RE)
    _protect(_LINK_RE)

    text = re.sub(r"[ \t]+", " ", text)

    for key, val in mapping.items():
        text = text.replace(key, val)
    return text


# ── Sentence splitting ──────────────────────────────────────────────────────
# Sentence-ending punctuation (Chinese punctuation + optional quotes/brackets anywhere; English punctuation + optional quotes/brackets followed by space or end of line)
_SENT_END = re.compile(
    r"([。！？]['\"()\]\}”’）】」』〉》]*"
    r"|[!?.]+['\"()\]\}”’）】」』〉》]*(?=\s|$))"
)
_SENT_END_BOUNDARY = re.compile(r"[。！？]|[!?.]\s(?![0-9])")


_URL_EMAIL_RE = re.compile(
    r"https?://\S+"  # URLs with scheme
    r"|www\.\S+"  # www. URLs
    r"|\b[\w.+-]+@[\w-]+\.[\w.-]+\b"  # email addresses
    r"|\b\w+\.(?:com|org|net|edu|gov|io|co|uk|cn|de|fr|jp|kr|ru|info|biz|me|tech|dev|app)\b"  # domain.tld
)


def _protect_urls(text: str) -> tuple[str, dict]:
    """Replace URLs and emails with placeholders to protect dots inside them.
    Returns (protected_text, {placeholder: original})."""
    mapping = {}
    counter = [0]

    def _replacer(m):
        key = f"{_SENTINEL_URL}{counter[0]}{_SENTINEL_URL}"
        counter[0] += 1
        mapping[key] = m.group()
        return key

    return _URL_EMAIL_RE.sub(_replacer, text), mapping


def _restore_urls(text: str, mapping: dict) -> str:
    """Restore URL/email placeholders."""
    for key, val in mapping.items():
        text = text.replace(key, val)
    return text


# Matches standard markdown links/images: ![alt](url) or [text](url)
_LINK_RE = re.compile(r"(!?\[[^\]]*\]\([^)]*\))")


def _protect_links_and_images(text: str) -> tuple[str, dict]:
    """Replace markdown links and images with placeholders to protect internal punctuation."""
    mapping = {}
    counter = [0]

    def _replacer(m):
        key = f"{_SENTINEL_LINK}{counter[0]}{_SENTINEL_LINK}"
        counter[0] += 1
        mapping[key] = m.group()
        return key

    return _LINK_RE.sub(_replacer, text), mapping


def _restore_links_and_images(text: str, mapping: dict) -> str:
    """Restore markdown link and image placeholders."""
    for key, val in mapping.items():
        text = text.replace(key, val)
    return text


# ── Math spacing cleanup (Stack-based state machine & spacing optimization) ──


def cleanup_math_content_spacing(math_text: str) -> str:
    """Optimize spacing inside a LaTeX math formula block."""
    # Identify and strip delimiters
    if math_text.startswith("$$") and math_text.endswith("$$"):
        delim = "$$"
        content = math_text[2:-2]
    elif math_text.startswith("$") and math_text.endswith("$"):
        delim = "$"
        content = math_text[1:-1]
    else:
        # Fallback if no delimiters (e.g. unbalanced)
        delim = ""
        content = math_text

    return f"{delim}{cleanup_math_body(content)}{delim}"


def cleanup_math_body(content: str) -> str:
    """Apply spacing cleanup to math content without adding delimiters."""
    content = content.strip()
    content = re.sub(r"(?<=[\d.])\s+(?=[\d.])", "", content)
    content = re.sub(r"(\\[a-zA-Z]+)\s*([{(])", r"\1\2", content)
    content = re.sub(r"\s*([+\-=<>*/_^])\s*", r"\1", content)
    content = re.sub(r"\s*,\s*", ", ", content)
    content = re.sub(r"([{(])\s+", r"\1", content)
    content = re.sub(r"\s+([})])", r"\1", content)
    content = re.sub(r"([a-zA-Z}])\s+(\()", r"\1\2", content)
    # Clean up spaces inside square brackets used for grouping
    content = re.sub(r"\[\s+", "[", content)
    content = re.sub(r"\s+\]", "]", content)
    # Clean up spaces inside \mathrm{} and \text{} (text-mode commands)
    content = re.sub(
        r"(\\(?:mathrm|text|textbf|textit|textrm|textsf|texttt)\{)([^}]*)\}",
        lambda m: m.group(1) + m.group(2).replace(" ", "") + "}",
        content,
    )
    return content


@dataclass
class Block:
    kind: str
    lines: list[str]
    start_line: int
    end_line: int


_CODE_FENCE_RE = re.compile(r"^\s*(`{3,}|~{3,})")
_HEADING_LINE_RE = re.compile(r"^\s{0,3}#{1,6}\s+")
_HR_LINE_RE = re.compile(r"^\s{0,3}([*_-])(?:\s*\1){2,}\s*$")
_IMAGE_LINE_RE = re.compile(r"^\s*!\[[^\]]*\]\([^)]*\)\s*$")
_BLOCKQUOTE_RE = re.compile(r"^( {0,3}>\s?)(.*)$")
_LIST_MARKER_RE = re.compile(r"^(\s*)([-*+]\s+|\d+[.)]\s+)(.*)$")
_PIPE_ROW_RE = re.compile(r"^(?:[^|\\]|\\.)*(?<!\\)\|")
_UNESCAPED_PIPE_RE = re.compile(r"(?<!\\)\|")


def _count_unescaped_pipes(line: str) -> int:
    return len(_UNESCAPED_PIPE_RE.findall(line))


_PIPE_TABLE_ALIGN_RE = re.compile(r"^\s*\|?\s*:?-{3,}:?\s*(?:\|\s*:?-{3,}:?\s*)+\|?\s*$")
_HTML_TABLE_START_RE = re.compile(r"<\s*(table|tr|td|th)\b", re.IGNORECASE)
_HTML_TABLE_END_RE = re.compile(r"</\s*table\s*>", re.IGNORECASE)
_LATEX_BEGIN_RE = re.compile(r"^\s*\\begin\{(equation\*?|align\*?|aligned|gather\*?|multline\*?|split)\}")
_LATEX_END_TEMPLATE = r"\\end\{%s\}"
_CAPTION_LABEL_RE = re.compile(
    r"^((?:Fig|Figs|Figure|Figures|Table|Tab|Eq|Equation)\.?\s*\d+(?:\.\d+)?[A-Za-z]?)\.(?=\s+\S)",
    re.IGNORECASE,
)


def is_heading_line(line: str) -> bool:
    return bool(_HEADING_LINE_RE.match(line))


def is_hr_line(line: str) -> bool:
    return bool(_HR_LINE_RE.match(line))


def is_image_line(line: str) -> bool:
    return bool(_IMAGE_LINE_RE.match(line))


def is_code_fence_start(line: str) -> re.Match | None:
    return _CODE_FENCE_RE.match(line)


def _is_escaped_at(text: str, index: int) -> bool:
    backslashes = 0
    cursor = index - 1
    while cursor >= 0 and text[cursor] == "\\":
        backslashes += 1
        cursor -= 1
    return backslashes % 2 == 1


def _unescaped_count(text: str, token: str) -> int:
    count = 0
    start = 0
    while True:
        idx = text.find(token, start)
        if idx == -1:
            return count
        if not _is_escaped_at(text, idx):
            count += 1
            start = idx + len(token)
        else:
            start = idx + 1


def is_display_math_start(line: str) -> bool:
    stripped = line.lstrip()
    return stripped.startswith("$$") or stripped.startswith(r"\[") or bool(_LATEX_BEGIN_RE.match(line))


def is_html_table_start(line: str) -> bool:
    return bool(_HTML_TABLE_START_RE.search(line))


def is_pipe_table_start(lines: list[str], index: int) -> bool:
    return (
        index + 1 < len(lines)
        and bool(_PIPE_ROW_RE.match(lines[index]))
        and bool(_PIPE_TABLE_ALIGN_RE.match(lines[index + 1]))
    )


def is_list_item_line(line: str) -> re.Match | None:
    return _LIST_MARKER_RE.match(line)


def is_blockquote_line(line: str) -> re.Match | None:
    return _BLOCKQUOTE_RE.match(line)


def is_structural_start(lines: list[str], index: int) -> bool:
    line = lines[index]
    return (
        not line.strip()
        or bool(is_code_fence_start(line))
        or is_display_math_start(line)
        or is_html_table_start(line)
        or is_pipe_table_start(lines, index)
        or is_heading_line(line)
        or is_hr_line(line)
        or is_image_line(line)
        or bool(is_list_item_line(line))
        or bool(is_blockquote_line(line))
    )


def _find_code_fence_end(lines: list[str], start: int, fence: str) -> int:
    char = fence[0]
    min_len = len(fence)
    close_re = re.compile(rf"^\s*{re.escape(char)}{{{min_len},}}\s*$")
    for idx in range(start + 1, len(lines)):
        if close_re.match(lines[idx]):
            return idx + 1
    return len(lines)


def _find_conservative_block_end(lines: list[str], start: int) -> int:
    idx = start + 1
    while idx < len(lines) and lines[idx].strip():
        if (
            is_heading_line(lines[idx])
            or is_hr_line(lines[idx])
            or is_image_line(lines[idx])
            or is_html_table_start(lines[idx])
        ):
            break
        idx += 1
    return idx


def _find_display_math_end(lines: list[str], start: int) -> int:
    stripped = lines[start].lstrip()
    if stripped.startswith("$$"):
        if _unescaped_count(lines[start], "$$") >= 2:
            return start + 1
        for idx in range(start + 1, len(lines)):
            if _unescaped_count(lines[idx], "$$"):
                return idx + 1
        return _find_conservative_block_end(lines, start)

    if stripped.startswith(r"\["):
        if r"\]" in lines[start][lines[start].find(r"\[") + 2 :]:
            return start + 1
        for idx in range(start + 1, len(lines)):
            if r"\]" in lines[idx]:
                return idx + 1
        return _find_conservative_block_end(lines, start)

    m = _LATEX_BEGIN_RE.match(lines[start])
    if m:
        end_re = re.compile(_LATEX_END_TEMPLATE % re.escape(m.group(1)))
        for idx in range(start, len(lines)):
            if end_re.search(lines[idx]):
                return idx + 1
        return _find_conservative_block_end(lines, start)

    return start + 1


def _find_html_table_end(lines: list[str], start: int) -> int:
    for idx in range(start, len(lines)):
        if _HTML_TABLE_END_RE.search(lines[idx]):
            return idx + 1
        if idx > start and not lines[idx].strip():
            return idx
    return len(lines)


def _find_pipe_table_end(lines: list[str], start: int) -> int:
    # The header + align rows at start, start+1 are guaranteed by
    # is_pipe_table_start. For continuation rows, require the same unescaped-
    # pipe count as the align row, so a prose paragraph that happens to contain
    # a single literal `|` does not extend a borderless table above it.
    if start + 1 >= len(lines):
        return min(start + 2, len(lines))
    expected = _count_unescaped_pipes(lines[start + 1])
    idx = start + 2
    while idx < len(lines) and _count_unescaped_pipes(lines[idx]) == expected:
        idx += 1
    return idx


def _find_list_end(lines: list[str], start: int) -> int:
    idx = start + 1
    base_indent = len(lines[start]) - len(lines[start].lstrip())
    while idx < len(lines):
        line = lines[idx]
        if not line.strip():
            # A blank line is allowed if the next non-blank line is:
            # - indented more than base_indent
            # - or is a list item line at base_indent
            next_non_blank = idx + 1
            while next_non_blank < len(lines) and not lines[next_non_blank].strip():
                next_non_blank += 1
            if next_non_blank >= len(lines):
                break
            next_line = lines[next_non_blank]
            next_marker = is_list_item_line(next_line)
            next_indent = len(next_line) - len(next_line.lstrip())
            if next_marker or next_indent > base_indent:
                idx = next_non_blank
                continue
            else:
                break
        marker = is_list_item_line(line)
        indent = len(line) - len(line.lstrip())
        if marker or indent > base_indent:
            idx += 1
            continue
        break
    return idx


def _find_blockquote_end(lines: list[str], start: int) -> int:
    idx = start + 1
    while idx < len(lines):
        if not lines[idx].strip():
            break
        if not is_blockquote_line(lines[idx]):
            break
        idx += 1
    return idx


def _find_paragraph_end(lines: list[str], start: int) -> int:
    idx = start + 1
    while idx < len(lines) and not is_structural_start(lines, idx):
        idx += 1
    return idx


def parse_blocks(text: str) -> list[Block]:
    lines = text.split("\n")
    blocks: list[Block] = []
    idx = 0

    while idx < len(lines):
        line = lines[idx]
        start_line = idx + 1

        if not line.strip():
            blocks.append(Block("blank", [line], start_line, start_line))
            idx += 1
            continue

        fence = is_code_fence_start(line)
        if fence:
            end = _find_code_fence_end(lines, idx, fence.group(1))
            blocks.append(Block("code_fence", lines[idx:end], start_line, end))
            idx = end
            continue

        if is_display_math_start(line):
            end = _find_display_math_end(lines, idx)
            blocks.append(Block("display_math", lines[idx:end], start_line, end))
            idx = end
            continue

        if is_html_table_start(line):
            end = _find_html_table_end(lines, idx)
            blocks.append(Block("html_table", lines[idx:end], start_line, end))
            idx = end
            continue

        if is_pipe_table_start(lines, idx):
            end = _find_pipe_table_end(lines, idx)
            blocks.append(Block("pipe_table", lines[idx:end], start_line, end))
            idx = end
            continue

        if is_blockquote_line(line):
            end = _find_blockquote_end(lines, idx)
            blocks.append(Block("blockquote", lines[idx:end], start_line, end))
            idx = end
            continue

        if is_heading_line(line):
            blocks.append(Block("heading", [line], start_line, start_line))
            idx += 1
            continue

        if is_hr_line(line):
            blocks.append(Block("hr", [line], start_line, start_line))
            idx += 1
            continue

        if is_image_line(line):
            blocks.append(Block("image", [line], start_line, start_line))
            idx += 1
            continue

        if is_list_item_line(line):
            end = _find_list_end(lines, idx)
            blocks.append(Block("list", lines[idx:end], start_line, end))
            idx = end
            continue

        end = _find_paragraph_end(lines, idx)
        blocks.append(Block("paragraph", lines[idx:end], start_line, end))
        idx = end

    return blocks


def warn_block(block: Block, message: str) -> None:
    global _WARNING_COUNT
    _WARNING_COUNT += 1
    print(
        f"[WARNING] line {block.start_line}-{block.end_line} {block.kind}: {message}",
        file=sys.stderr,
    )


def get_warning_count() -> int:
    return _WARNING_COUNT


def _is_cjk_or_punctuation(c: str) -> bool:
    if not c:
        return False
    val = ord(c[0])
    return (
        0x4E00 <= val <= 0x9FFF
        or 0x3000 <= val <= 0x303F
        or 0xFF00 <= val <= 0xFFEF
        or 0x3400 <= val <= 0x4DBF
        or 0x20000 <= val <= 0x3FFFF
    )


def needs_join_space(left: str, right: str) -> bool:
    if not left or not right:
        return False
    if right[0] in ",.;:!?)]}”’%":
        return False
    if left[-1] in "([{“‘":
        return False
    return not (_is_cjk_or_punctuation(left[-1]) or _is_cjk_or_punctuation(right[0]))


def join_soft_wrapped_lines(lines: list[str]) -> str:
    parts = [line.strip() for line in lines if line.strip()]
    if not parts:
        return ""

    text = parts[0]
    for part in parts[1:]:
        if text.endswith("-") and part and part[0].islower():
            last_token = text.rsplit(maxsplit=1)[-1]
            if "-" in last_token[:-1]:
                text += part
            else:
                text = text[:-1] + part
        elif needs_join_space(text, part):
            text += " " + part
        else:
            text += part
    return text


def _protect_caption_labels(text: str) -> str:
    return _CAPTION_LABEL_RE.sub(lambda m: m.group(1) + _SENTINEL_ABBR, text)


def split_sentences_in_text(text: str) -> list[str]:
    protected, link_map = _protect_links_and_images(text)
    protected, url_map = _protect_urls(protected)
    protected = _protect_caption_labels(protected)
    protected = _protect_abbreviations(protected)
    protected = collapse_inline_whitespace(protected)

    parts = _SENT_END.split(protected)
    sentences = []
    current = ""

    for idx in range(0, len(parts) - 1, 2):
        text_part = parts[idx]
        punct = parts[idx + 1]
        next_text = parts[idx + 2] if idx + 2 < len(parts) else ""
        current += text_part + punct

        # Protect OCR-split decimals like "3 . 14": only skip the break when the
        # char BEFORE the dot is also a digit. This avoids merging a genuine new
        # sentence that starts with a number/list marker (e.g. "End. 2. New.").
        before = text_part.rstrip()
        if (
            punct == "."
            and before
            and before[-1].isdigit()
            and next_text
            and next_text.lstrip()
            and next_text.lstrip()[0].isdigit()
        ):
            continue

        sentences.append(current.strip())
        current = ""

    if len(parts) % 2 == 1:
        current += parts[-1]
    if current.strip():
        sentences.append(current.strip())

    restored = []
    for sentence in sentences:
        sentence = _restore_abbreviations(sentence)
        sentence = _restore_urls(sentence, url_map)
        sentence = _restore_links_and_images(sentence, link_map)
        restored.append(sentence)
    return restored


def _is_single_dollar(text: str, index: int) -> bool:
    if text[index] != "$" or _is_escaped_at(text, index):
        return False
    if index > 0 and text[index - 1] == "$" and not _is_escaped_at(text, index - 1):
        return False
    return not (index + 1 < len(text) and text[index + 1] == "$" and not _is_escaped_at(text, index + 1))


def _find_closing_dollar(text: str, start_idx: int) -> int | None:
    idx = start_idx + 1
    while True:
        idx = text.find("$", idx)
        if idx == -1:
            return None
        if not _is_escaped_at(text, idx):
            if idx + 1 < len(text) and text[idx + 1] == "$" and not _is_escaped_at(text, idx + 1):
                idx += 2
                continue
            if idx > 0 and text[idx - 1] == "$" and not _is_escaped_at(text, idx - 1):
                idx += 1
                continue
            return idx
        idx += 1


def _is_valid_inline_math_open(text: str, index: int) -> int | None:
    cursor = index + 1
    while cursor < len(text) and text[cursor].isspace():
        cursor += 1
    if cursor >= len(text):
        return None

    if text[cursor] in ".,;:!?)]}":
        return None

    close_idx = _find_closing_dollar(text, index)
    if close_idx is None:
        return None

    content = text[index + 1 : close_idx]

    if _SENT_END_BOUNDARY.search(content):
        return None

    if text[cursor].isdigit():
        if close_idx + 1 < len(text) and text[close_idx + 1].isdigit():
            return None
        if not any(c in content for c in "\\^_{}+-=<>*/,;") and any(c.isspace() for c in content):
            return None

    if not _is_valid_inline_math_close(text, close_idx):
        return None

    return close_idx


def _is_valid_inline_math_close(text: str, index: int) -> bool:
    cursor = index - 1
    while cursor >= 0 and text[cursor].isspace():
        cursor -= 1
    return cursor >= 0 and (text[cursor] != "$" or _is_escaped_at(text, cursor))


# Normalize \(...\) inline-math delimiters to $...$ so the rest of the pipeline
# (which is built around $) handles them uniformly. Only unescaped \( \) pairs
# are touched; \\( (an escaped backslash + paren) is left alone.
_INLINE_PAREN_MATH_RE = re.compile(r"(?<!\\)\\\(((?:(?!\\\(|\\\)).)*?)(?<!\\)\\\)", re.DOTALL)


def normalize_inline_paren_math(text: str) -> str:
    return _INLINE_PAREN_MATH_RE.sub(lambda m: f"${m.group(1)}$", text)


def protect_inline_math(text: str) -> tuple[str, dict[str, str]]:
    mapping: dict[str, str] = {}
    output = []
    last = 0
    idx = 0

    while idx < len(text):
        if not _is_single_dollar(text, idx):
            idx += 1
            continue

        close_idx = _is_valid_inline_math_open(text, idx)
        if close_idx is not None:
            output.append(text[last:idx])
            key = f"{_SENTINEL_MATH}{len(mapping)}{_SENTINEL_MATH}"
            mapping[key] = text[idx : close_idx + 1]
            output.append(key)
            idx = close_idx + 1
            last = idx
            continue

        idx += 1

    output.append(text[last:])
    return "".join(output), mapping


def restore_inline_math(text: str, mapping: dict[str, str]) -> str:
    for key, value in mapping.items():
        text = text.replace(key, cleanup_math_content_spacing(value))
    return text


def _cleanup_math_boundary_spacing(text: str) -> str:
    text = re.sub(r"\$\s+([.,;:!?)\]}])", r"$\1", text)
    text = re.sub(r"([([{])\s+\$", r"\1$", text)
    text = re.sub(r"\$\s+([.,;:!?])\s+\$", r"$\1 $", text)
    return text


def process_prose_lines(lines: list[str], block: Block) -> list[str]:
    text = join_soft_wrapped_lines(lines)
    if not text:
        return []

    text = normalize_inline_paren_math(text)

    try:
        protected, math_map = protect_inline_math(text)
    except ValueError as exc:
        warn_block(block, str(exc))
        return block.lines

    protected = cleanup_ocr(protected)
    sentences = split_sentences_in_text(protected)
    restored = [restore_inline_math(s, math_map) for s in sentences]
    return [_cleanup_math_boundary_spacing(s) for s in restored]


def process_paragraph_block(block: Block) -> list[str]:
    return process_prose_lines(block.lines, block)


def process_blockquote_block(block: Block) -> list[str]:
    # Contiguous blockquote lines are grouped and processed recursively.
    output = []
    current_prefix = ""
    current_lines = []

    def flush():
        if not current_lines:
            return
        unwrapped_lines = []
        for line in current_lines:
            m = is_blockquote_line(line)
            if m:
                unwrapped_lines.append(m.group(2))
            else:
                unwrapped_lines.append(line)

        unwrapped_text = "\n".join(unwrapped_lines)
        processed_text = process(unwrapped_text)
        # process() ends with a trailing newline; strip only that, not interior
        # blank lines (which separate paragraphs within the blockquote).
        processed_lines = processed_text.rstrip("\n").split("\n")

        for line in processed_lines:
            if line.strip():
                output.append(current_prefix + line)
            else:
                output.append(current_prefix.rstrip())
        current_lines.clear()

    for line in block.lines:
        m = is_blockquote_line(line)
        if m:
            prefix = m.group(1)
            if current_lines and prefix != current_prefix:
                flush()
            current_prefix = prefix
            current_lines.append(line)
        else:
            current_lines.append(line)
    flush()
    return output


def _is_top_level_list_marker(line: str, base_indent: int) -> bool:
    marker = is_list_item_line(line)
    return bool(marker) and len(marker.group(1)) == base_indent


def _list_item_groups(block: Block) -> list[tuple[int, list[str]]]:
    first_marker = is_list_item_line(block.lines[0])
    base_indent = len(first_marker.group(1)) if first_marker else 0
    groups = []
    idx = 0
    while idx < len(block.lines):
        start = idx
        idx += 1
        while idx < len(block.lines) and not _is_top_level_list_marker(block.lines[idx], base_indent):
            idx += 1
        groups.append((start, block.lines[start:idx]))
    return groups


def process_list_block(block: Block) -> list[str]:
    output: list[str] = []
    for _start_idx, item_lines in _list_item_groups(block):
        marker = is_list_item_line(item_lines[0])
        if not marker:
            output.extend(item_lines)
            continue

        prefix = marker.group(1) + marker.group(2)
        content_col = len(prefix)
        content_lines = [marker.group(3)]
        for line in item_lines[1:]:
            if line.startswith(" " * content_col):
                content_lines.append(line[content_col:])
            else:
                content_lines.append(line.lstrip())

        unwrapped_text = "\n".join(content_lines)
        processed_text = process(unwrapped_text)
        # process() ends with a trailing newline; strip only that, not interior
        # blank lines (which separate paragraphs within the list item).
        processed_lines = processed_text.rstrip("\n").split("\n")

        if not processed_lines or (len(processed_lines) == 1 and not processed_lines[0].strip()):
            output.append(prefix)
            continue

        output.append(prefix + processed_lines[0])
        for line in processed_lines[1:]:
            output.append(" " * content_col + line)
    return output


def _display_math_is_balanced(text: str) -> bool:
    stripped = text.strip()
    if stripped.startswith("$$"):
        return stripped.endswith("$$") and _unescaped_count(stripped, "$$") >= 2
    if stripped.startswith(r"\["):
        return stripped.endswith(r"\]")
    m = _LATEX_BEGIN_RE.match(stripped)
    if m:
        return bool(re.search(_LATEX_END_TEMPLATE % re.escape(m.group(1)), stripped))
    return True


def process_display_math_block(block: Block) -> list[str]:
    text = "\n".join(block.lines)
    if not _display_math_is_balanced(text):
        warn_block(block, "unbalanced display math delimiter; preserving block")
        return block.lines

    stripped = text.strip()
    if stripped.startswith("$$") and stripped.endswith("$$"):
        return cleanup_math_content_spacing(stripped).split("\n")
    if stripped.startswith(r"\[") and stripped.endswith(r"\]"):
        # Normalize \[...\] display delimiters to $$...$$ for a consistent,
        # widely-rendered output. Preserve LaTeX environment boundaries while
        # allowing their math body to undergo the same whitespace cleanup.
        return ("$$" + cleanup_math_body(stripped[2:-2]) + "$$").split("\n")
    if _LATEX_BEGIN_RE.match(stripped):
        return cleanup_math_body(stripped).split("\n")
    return cleanup_math_body(text).split("\n")


def _process_block_inner(block: Block) -> list[str]:
    if block.kind == "blank":
        return [""]
    if block.kind == "heading":
        return [collapse_inline_whitespace(cleanup_ocr(line)) for line in block.lines]
    if block.kind == "code_fence":
        return block.lines
    if block.kind == "paragraph":
        return process_paragraph_block(block)
    if block.kind == "blockquote":
        return process_blockquote_block(block)
    if block.kind == "list":
        return process_list_block(block)
    if block.kind == "display_math":
        return process_display_math_block(block)
    return [cleanup_ligatures(line) for line in block.lines]


def process_block(block: Block) -> list[str]:
    # Any block-processing failure degrades gracefully: warn and emit the block
    # unchanged rather than aborting the whole document. Applies uniformly to
    # every block kind (not just paragraph/blockquote).
    try:
        return _process_block_inner(block)
    except Exception as exc:
        warn_block(block, f"{exc}; preserving block")
        return block.lines


def process_blocks(blocks: list[Block]) -> list[str]:
    output: list[str] = []
    for block in blocks:
        output.extend(process_block(block))
    return output


def format_processed_blocks(lines: list[str]) -> str:
    output = []
    previous_blank = False
    for line in lines:
        if not line.strip():
            if not previous_blank:
                output.append("")
            previous_blank = True
        else:
            output.append(line.rstrip())
            previous_blank = False
    while output and not output[-1].strip():
        output.pop()
    return "\n".join(output) + "\n"


def process(text: str) -> str:
    """Full deterministic processing pipeline."""
    global _PROCESS_DEPTH, _WARNING_COUNT
    _PROCESS_DEPTH += 1
    if _PROCESS_DEPTH == 1:
        _WARNING_COUNT = 0

    try:
        text = (
            text.replace(_SENTINEL_ABBR, "")
            .replace(_SENTINEL_URL, "")
            .replace(_SENTINEL_MATH, "")
            .replace(_SENTINEL_LINK, "")
            .replace(_SENTINEL_WS, "")
        )

        blocks = parse_blocks(text)
        lines = process_blocks(blocks)
        return format_processed_blocks(lines)
    finally:
        _PROCESS_DEPTH -= 1


# ── Heading tools for LLM ──────────────────────────────────────────────────
_HEADING_RE = re.compile(r"^([ >\t]*)(#{1,6})\s+(.*)$")


def extract_headings(text: str, context_lines: int = 1) -> str:
    """Extract heading skeleton with surrounding context for LLM analysis.

    Returns a compact text showing line numbers, heading levels, and a few
    lines of context after each heading so the LLM can determine the correct
    hierarchy.
    """
    blocks = parse_blocks(text)
    lines = text.split("\n")
    entries = []

    # Identify lines that belong to code fences, display math, or tables, where
    # hash characters (#) are not headings.
    ignored_lines = set()
    for block in blocks:
        if block.kind in {"code_fence", "display_math", "html_table", "pipe_table"}:
            for line_num in range(block.start_line, block.end_line + 1):
                ignored_lines.add(line_num)

    for i, line in enumerate(lines):
        line_num = i + 1
        if line_num in ignored_lines:
            continue

        m = _HEADING_RE.match(line)
        if m:
            level = len(m.group(2))
            title = m.group(3).strip()
            # Grab context lines after the heading
            ctx_start = i + 1
            ctx_end = min(i + 1 + context_lines, len(lines))
            context = []
            for j in range(ctx_start, ctx_end):
                cl = lines[j].strip()
                if cl:
                    context.append(cl)
            ctx_str = f"  ctx: {' '.join(context)}" if context else ""
            entries.append(f"L{line_num:4d} {'#' * level} {title}{ctx_str}")

    return "\n".join(entries)


def apply_headings(text: str, mapping: dict[int, str]) -> str:
    """Apply heading level mapping to the text.

    mapping: {line_number: new_prefix} e.g. {16: "##", 50: "###", ...}
    The line numbers are 1-indexed.
    """
    lines = text.split("\n")
    for line_num, new_prefix in mapping.items():
        idx = line_num - 1
        if 0 <= idx < len(lines):
            m = _HEADING_RE.match(lines[idx])
            if m:
                prefix = m.group(1)
                title = m.group(3).strip()
                lines[idx] = f"{prefix}{new_prefix} {title}"
    return "\n".join(lines)


def finalize_files(input_path: Path) -> tuple[Path, Path]:
    """Back up the raw input and promote its polished sibling."""
    polished_path = input_path.with_name(f"{input_path.stem}-polished{input_path.suffix}")
    origin_path = input_path.with_name(f"{input_path.stem}.origin{input_path.suffix}")

    if not input_path.is_file():
        raise FileNotFoundError(f"Original file not found: {input_path}")
    if not polished_path.is_file():
        raise FileNotFoundError(f"Polished file not found: {polished_path}")
    if origin_path.exists():
        raise FileExistsError(f"Backup already exists: {origin_path}")

    input_path.replace(origin_path)
    try:
        polished_path.replace(input_path)
    except Exception:
        origin_path.replace(input_path)
        raise
    return input_path, origin_path


def main():
    parser = argparse.ArgumentParser(description="Deterministic markdown post-processing for PDF-converted documents.")
    sub = parser.add_subparsers(dest="command")

    # Default: polish
    pol = sub.add_parser("polish", help="Run the full polish pipeline (default)")
    pol.add_argument("input", type=str, help="Input markdown file")
    pol.add_argument(
        "-o",
        "--output",
        type=str,
        default=None,
        help="Output file (default: <input>-polished.md)",
    )

    # Extract headings skeleton
    ext = sub.add_parser("headings", help="Extract heading skeleton with context")
    ext.add_argument("input", type=str, help="Input markdown file")
    ext.add_argument(
        "-c",
        "--context",
        type=int,
        default=1,
        help="Lines of context after each heading (default: 1)",
    )
    ext.add_argument("-o", "--output", type=str, default=None, help="Output file (default: stdout)")

    # Apply heading mapping
    app = sub.add_parser("apply", help="Apply heading level mapping")
    app.add_argument("input", type=str, help="Input markdown file")
    app.add_argument(
        "-m",
        "--mapping",
        type=str,
        required=True,
        help='JSON mapping: {"line_number": "##", ...}',
    )
    app.add_argument(
        "-o",
        "--output",
        type=str,
        default=None,
        help="Output file (default: overwrite input)",
    )

    fin = sub.add_parser("finalize", help="Back up the original and promote the polished working copy")
    fin.add_argument("input", type=str, help="Original markdown file")

    argv = sys.argv[1:]
    if argv and argv[0] not in {"polish", "headings", "apply", "finalize", "-h", "--help"}:
        argv = ["polish", *argv]

    args = parser.parse_args(argv)
    if args.command is None:
        parser.print_help()
        sys.exit(2)

    if args.command == "polish":
        input_path = Path(args.input)
        if not input_path.exists():
            print(f"Error: {input_path} not found", file=sys.stderr)
            sys.exit(1)
        output_path = Path(args.output) if args.output else input_path.with_name(f"{input_path.stem}-polished.md")
        text = input_path.read_text(encoding="utf-8")
        result = process(text)
        output_path.write_text(result, encoding="utf-8")
        print(f"Done. Output: {output_path}")

        # Update history.json automatically
        try:
            history_path = Path(__file__).parent / "history.json"
            history_data = []
            if history_path.exists():
                try:
                    history_data = json.loads(history_path.read_text(encoding="utf-8"))
                    if not isinstance(history_data, list):
                        history_data = []
                except Exception:
                    pass

            # Simple sentence count estimation
            sentences_count = len([s for s in re.split(r"[.!?。！？\n]+", result) if s.strip()])

            # Get language from config.json if available
            lang = "auto"
            config_path = Path(__file__).parent / "config.json"
            if config_path.exists():
                try:
                    cfg = json.loads(config_path.read_text(encoding="utf-8"))
                    lang = cfg.get("language", "auto")
                except Exception:
                    pass

            from datetime import datetime

            history_data.append(
                {
                    "timestamp": datetime.now().isoformat()[:19],
                    "file": input_path.name,
                    "sentences": sentences_count,
                    "warnings": get_warning_count(),
                    "language": lang,
                    "notes": "Automated run log",
                }
            )
            history_path.write_text(json.dumps(history_data, indent=2), encoding="utf-8")
        except Exception as e:
            print(f"Warning: Failed to update history.json: {e}", file=sys.stderr)

    elif args.command == "headings":
        input_path = Path(args.input)
        if not input_path.exists():
            print(f"Error: {input_path} not found", file=sys.stderr)
            sys.exit(1)
        result = extract_headings(input_path.read_text(encoding="utf-8"), context_lines=args.context)
        if args.output:
            Path(args.output).write_text(result, encoding="utf-8")
            print(f"Done. Output: {args.output}")
        else:
            print(result)

    elif args.command == "apply":
        input_path = Path(args.input)
        if not input_path.exists():
            print(f"Error: {input_path} not found", file=sys.stderr)
            sys.exit(1)
        # Clean mapping string in case LLM wraps it in markdown code blocks or adds extra whitespace/newlines
        mapping_str = args.mapping.strip()
        if mapping_str.startswith("```"):
            mapping_str = re.sub(r"^```(?:json)?\s*", "", mapping_str)
            mapping_str = re.sub(r"\s*```$", "", mapping_str)
        mapping_str = mapping_str.strip()

        mapping = json.loads(mapping_str)
        # Keys are strings from JSON, convert to int
        mapping = {int(k): v for k, v in mapping.items()}
        text = input_path.read_text(encoding="utf-8")
        result = apply_headings(text, mapping)
        output_path = Path(args.output) if args.output else input_path
        output_path.write_text(result, encoding="utf-8")
        print(f"Done. Applied {len(mapping)} heading changes to {output_path}")

    elif args.command == "finalize":
        try:
            final_path, origin_path = finalize_files(Path(args.input))
        except (FileNotFoundError, FileExistsError) as exc:
            print(f"Error: {exc}", file=sys.stderr)
            sys.exit(1)
        print(f"Done. Final: {final_path}; backup: {origin_path}")


if __name__ == "__main__":
    main()
