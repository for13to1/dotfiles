"""
pdf2md-polish: Deterministic markdown post-processing for PDF-converted documents.

Handles OCR cleanup, abbreviation-aware sentence splitting, equation wrapping,
and one-sentence-per-line formatting. Run this BEFORE letting the LLM adjust
heading hierarchy and handle ambiguous cases.

Usage:
    python polish.py input.md [-o output.md]
"""

import argparse
import json
import re
import sys
from pathlib import Path

# ── Sentinel placeholders for text protection ──────────────────────────────
# Control characters used to protect specific segments from sentence splitting.
# Cleaned from the input at the start of process() to avoid collision.
_SENTINEL_ABBR = "\x00"  # Protects abbreviation dots
_SENTINEL_URL = "\x01"  # Protects URL and email dots
_SENTINEL_MATH = "\x02"  # Protects math blocks and formula content

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
]

# Sort longest first to avoid partial matches
ABBREVIATIONS.sort(key=len, reverse=True)

# Compile single abbreviation matching pattern using word boundaries to prevent
# false positives (e.g. "signal." matching "al.")
_ABBR_PATTERN = re.compile(
    r"\b(?:" + "|".join(re.escape(abbr) for abbr in ABBREVIATIONS) + ")", re.IGNORECASE
)

# Pattern for single uppercase letter initials: "A.", "B.", etc.
_INITIAL_RE = re.compile(r"(?<![a-zA-Z])([A-Z])\.(?=\s|$|[A-Z])")

# Patterns for ellipsis variants
_ELLIPSIS_RE = re.compile(r"\.\.\.|…|\.\s\.\s\.")


def _protect_abbreviations(text: str) -> str:
    """Replace dots in known abbreviations with a sentinel so sentence
    splitting won't break on them."""
    # Protect ellipsis first (before abbreviation matching changes dots)
    text = _ELLIPSIS_RE.sub(
        lambda m: (
            m.group().replace(".", _SENTINEL_ABBR).replace("…", _SENTINEL_ABBR * 3)
        ),
        text,
    )
    # Protect abbreviations using precompiled pattern with word boundaries
    text = _ABBR_PATTERN.sub(lambda m: m.group().replace(".", _SENTINEL_ABBR), text)
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
    "\u2013": "-",  # en-dash → hyphen (in text; adjust if you prefer –)
    "\ufb05": "st",  # ﬅ
    "\ufb06": "st",  # ﬆ
}


def cleanup_ocr(text: str) -> str:
    """Fix common OCR ligatures and stray artifacts."""
    for lig, repl in _LIGATURES.items():
        text = text.replace(lig, repl)
    # Remove stray single backslashes that are not part of LaTeX commands,
    # Markdown escapes, or common math/delimiter wrappers.
    # We ensure we do not touch double backslashes (\\) which are valid in LaTeX/Markdown.
    text = re.sub(r"(?<!\\)\\(?!\\)(?=[^a-zA-Z()\[\]$%#{}&_*+\-.!\`<>])", "", text)
    return text


# (Equation wrapping removed)


# ── Sentence splitting ──────────────────────────────────────────────────────
# Sentence-ending punctuation (Chinese punctuation + optional quotes/brackets anywhere; English punctuation + optional quotes/brackets followed by space or end of line)
_SENT_END = re.compile(
    r"([。！？]['\"()\]\}”’）】」』〉》]*"
    r"|[!?.]+['\"()\]\}”’）】」』〉》]*(?=\s|$))"
)


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


_PREFIX_RE = re.compile(r"^(\s*(?:[-*+]\s+|\d+\.\s+|>\s*|))")


def get_subsequent_prefix(prefix: str) -> str:
    """Calculate the prefix for subsequent sentences in a split paragraph.
    Preserves '>' for blockquotes, replaces list markers with spaces."""
    if ">" in prefix:
        return prefix
    return re.sub(r"[^\s]", " ", prefix)


def split_sentences(text: str) -> list[str]:
    """Split text into sentences, respecting abbreviations and URLs.
    Preserves line-level prefixes and indentation."""
    # Protect URLs and emails first (before abbreviation protection changes dots)
    protected, url_map = _protect_urls(text)
    # Then protect abbreviations
    protected = _protect_abbreviations(protected)

    # Split by lines first to preserve markdown structure
    lines = protected.split("\n")
    result = []

    for line in lines:
        # Match leading spaces and optional markdown block markers (list item or blockquote)
        match = _PREFIX_RE.match(line)
        prefix = match.group(1) if match else ""
        content = line[len(prefix) :]

        stripped_content = content.strip()
        if not stripped_content:
            result.append("")
            continue

        # Skip lines that are clearly structural blocks that should not be split
        # (headings, code fences, tables, images)
        if re.match(r"^(#{1,6}\s|```|\|.*\||\$\$|!\[)", stripped_content):
            result.append(_restore_abbreviations(line))
            continue

        # Split on sentence-ending punctuation
        parts = _SENT_END.split(content)
        sentences = []
        current = ""

        # Merge each punctuation mark back with its preceding text,
        # then decide if it's a real sentence boundary.
        for i in range(0, len(parts) - 1, 2):
            text_part = parts[i]
            punct = parts[i + 1]
            combined = text_part + punct
            next_text = parts[i + 2] if i + 2 < len(parts) else ""

            current += combined

            # Skip if this period belongs to an abbreviation
            if punct == "." and len(text_part) > 0 and text_part[-1] == _SENTINEL_ABBR:
                continue

            # Skip decimal numbers: "." followed by digit (e.g., "3.14")
            if punct == "." and next_text and next_text[0].isdigit():
                continue

            # Real sentence boundary
            sentences.append(current.strip())
            current = ""

        # Remaining trailing text without punctuation
        if len(parts) % 2 == 1:
            current += parts[-1]
        if current.strip():
            sentences.append(current.strip())

        # Restore abbreviations in each sentence and preserve correct indentation
        if sentences:
            first_line = prefix + _restore_abbreviations(sentences[0])
            result.append(first_line)

            sub_prefix = get_subsequent_prefix(prefix)
            for s in sentences[1:]:
                line_out = sub_prefix + _restore_abbreviations(s)
                result.append(line_out)

    # Restore URLs and emails
    result = [_restore_urls(line_item, url_map) for line_item in result]

    return result


def format_one_per_line(lines: list[str]) -> str:
    """Join lines with newlines, preserving paragraph boundaries.
    Blank lines in input become blank lines in output (paragraph separators)."""
    output_lines = []
    prev_blank = False

    for line in lines:
        if line == "":
            if not prev_blank:
                output_lines.append("")
            prev_blank = True
        else:
            output_lines.append(line)
            prev_blank = False

    return "\n".join(output_lines)


# ── Math spacing cleanup (Stack-based state machine & spacing optimization) ──


def parse_math_segments(text: str) -> tuple[list[tuple[str, str]], bool, list[int]]:
    """Parse text into alternating (type, content) segments where type is 'text' or 'math'.
    Returns (segments, is_balanced, unbalanced_line_numbers).

    Line numbers are 1-indexed. The delimiters ($ or $$) are preserved inside the math segment.
    """
    segments = []
    # Match escaped dollar (\\\$), double dollar ($$), or single dollar ($)
    pattern = re.compile(r"(\\\$|\$\$|\$)")

    last_idx = 0
    in_math = False
    math_type = None  # 'inline' or 'block'
    current_math_start = -1
    current_math_delim = ""

    stack = []
    unbalanced_lines = []

    def get_line_number(index: int) -> int:
        return text[:index].count("\n") + 1

    for match in pattern.finditer(text):
        token = match.group(1)
        start, end = match.span()

        if token.startswith("\\"):
            # Escaped dollar, treat as normal text, do not change math state
            continue

        if in_math:
            # We are inside math, check if this token closes it
            if token == current_math_delim:
                # Close math segment!
                # Extract text before opening delimiter as text segment
                before_math = text[last_idx:current_math_start]
                if before_math:
                    segments.append(("text", before_math))
                # Extract math block including delimiters
                math_block = text[current_math_start:end]
                segments.append(("math", math_block))

                in_math = False
                math_type = None
                current_math_delim = ""
                stack.pop()
                last_idx = end
            else:
                # Mismatched delimiter inside math block (unbalanced)
                unbalanced_lines.append(stack[-1][2])
                # Reset math state to the new delimiter
                before_math = text[last_idx:current_math_start]
                if before_math:
                    segments.append(("text", before_math))
                # Extract the old unclosed math as math segment
                math_block = text[current_math_start:start]
                segments.append(("math", math_block))

                current_math_start = start
                current_math_delim = token
                math_type = "block" if token == "$$" else "inline"
                stack[-1] = (math_type, start, get_line_number(start))
                last_idx = start
        else:
            # Outside math, this token opens a math block
            in_math = True
            current_math_start = start
            current_math_delim = token
            math_type = "block" if token == "$$" else "inline"
            stack.append((math_type, start, get_line_number(start)))

    # Add any remaining text
    if in_math:
        # Unclosed math block at end of text
        before_math = text[last_idx:current_math_start]
        if before_math:
            segments.append(("text", before_math))
        segments.append(("math", text[current_math_start:]))
    else:
        remaining = text[last_idx:]
        if remaining:
            segments.append(("text", remaining))

    while stack:
        unbalanced_lines.append(stack.pop()[2])

    is_balanced = len(unbalanced_lines) == 0
    return segments, is_balanced, sorted(list(set(unbalanced_lines)))


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

    # 1. Remove spaces between digits/dots: "0 1 1 1 0" -> "01110"
    content = re.sub(r"(?<=[\d.])\s+(?=[\d.])", "", content)

    # 2. Remove spaces before braces after a LaTeX command
    # e.g., "\mathrm { " -> "\mathrm{"
    content = re.sub(r"(\\[a-zA-Z]+)\s*([{(])", r"\1\2", content)

    # 3. Remove spaces around superscript and subscript operators:
    # e.g., "^ { \mathrm" -> "^{\mathrm"
    # e.g., "_ { 1 }" -> "_{1}"
    content = re.sub(r"([_^])\s*(\{)", r"\1\2", content)

    # 4. Remove space after opening brace/bracket: "{ " -> "{"
    content = re.sub(r"([{(])\s+", r"\1", content)

    # 5. Remove space before closing brace/bracket: " }" -> "}"
    content = re.sub(r"\s+([})])", r"\1", content)

    return f"{delim}{content}{delim}"


def fallback_cleanup_math_spacing(text: str) -> str:
    """Fallback spacing cleanup using basic regex when delimiters are unbalanced."""
    text = re.sub(r"\$\s+([.,;:!?)\]}])", r"$\1", text)
    text = re.sub(r"([([{])\s+\$", r"\1$", text)
    text = re.sub(r"\$\s+([.,;:!?])\s+\$", r"$\1 $", text)
    return text


def process(text: str) -> str:
    """Full deterministic processing pipeline."""
    # 0. Clean any pre-existing sentinel characters in input to prevent injection/mismatch
    text = (
        text.replace(_SENTINEL_ABBR, "")
        .replace(_SENTINEL_URL, "")
        .replace(_SENTINEL_MATH, "")
    )

    # 1. OCR cleanup
    text = cleanup_ocr(text)

    # 2. Parse math segments to check balance and get AST
    segments, is_balanced, unbalanced_lines = parse_math_segments(text)

    if not is_balanced:
        # Unbalanced fallback: print warning and run old flat regex pipeline
        lines_str = ", ".join(map(str, unbalanced_lines))
        print(
            f"[WARNING] Unbalanced math delimiter '$' detected on line(s): {lines_str}. "
            "Falling back to safe global math spacing regexes.",
            file=sys.stderr,
        )
        text = fallback_cleanup_math_spacing(text)
        lines = split_sentences(text)
        text = format_one_per_line(lines)
        text = re.sub(r"\n{3,}", "\n\n", text)
        return text

    # 3. Balanced flow: replace math segments with placeholders (using sentinel delimiter)
    placeholder_text_parts = []
    for idx, (seg_type, seg_content) in enumerate(segments):
        if seg_type == "math":
            placeholder_text_parts.append(f"{_SENTINEL_MATH}{idx}{_SENTINEL_MATH}")
        else:
            placeholder_text_parts.append(seg_content)

    text_with_placeholders = "".join(placeholder_text_parts)

    # 4. Split sentences on the protected text (formula content is safe!)
    lines = split_sentences(text_with_placeholders)
    processed_text = format_one_per_line(lines)

    # 5. Restore placeholders and clean spacing
    def _restore_placeholder(match):
        idx = int(match.group(1))
        math_content = segments[idx][1]
        cleaned_math = cleanup_math_content_spacing(math_content)
        return cleaned_math

    final_text = re.sub(
        rf"{_SENTINEL_MATH}(\d+){_SENTINEL_MATH}", _restore_placeholder, processed_text
    )

    # 6. Spacing around math boundaries
    final_text = re.sub(r"\$\s+([.,;:!?)\]}])", r"$\1", final_text)
    final_text = re.sub(r"([([{])\s+\$", r"\1$", final_text)
    final_text = re.sub(r"\$\s+([.,;:!?])\s+\$", r"$\1 $", final_text)

    # 7. Collapse extra blank lines
    final_text = re.sub(r"\n{3,}", "\n\n", final_text)
    return final_text


# ── Heading tools for LLM ──────────────────────────────────────────────────
_HEADING_RE = re.compile(r"^(#{1,6})\s+(.*)$")


def extract_headings(text: str, context_lines: int = 1) -> str:
    """Extract heading skeleton with surrounding context for LLM analysis.

    Returns a compact text showing line numbers, heading levels, and a few
    lines of context after each heading so the LLM can determine the correct
    hierarchy.
    """
    lines = text.split("\n")
    entries = []

    for i, line in enumerate(lines):
        m = _HEADING_RE.match(line.strip())
        if m:
            level = len(m.group(1))
            title = m.group(2).strip()
            # Grab context lines after the heading
            ctx_start = i + 1
            ctx_end = min(i + 1 + context_lines, len(lines))
            context = []
            for j in range(ctx_start, ctx_end):
                cl = lines[j].strip()
                if cl:
                    context.append(cl)
            ctx_str = f"  ctx: {' '.join(context[:1])}" if context else ""
            entries.append(f"L{i + 1:4d} {'#' * level} {title}{ctx_str}")

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
            m = _HEADING_RE.match(lines[idx].strip())
            if m:
                title = m.group(2).strip()
                lines[idx] = f"{new_prefix} {title}"
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(
        description="Deterministic markdown post-processing for PDF-converted documents."
    )
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
    ext.add_argument(
        "-o", "--output", type=str, default=None, help="Output file (default: stdout)"
    )

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

    # Support running without subcommand (default to polish)
    parser.add_argument("--input", type=str, help=argparse.SUPPRESS)
    parser.add_argument(
        "-o", "--output", type=str, default=None, help=argparse.SUPPRESS
    )

    args = parser.parse_args()

    # Default to polish if no subcommand
    if args.command is None:
        args.command = "polish"
        # Re-parse with polish defaults
        p2 = argparse.ArgumentParser()
        p2.add_argument("input", type=str)
        p2.add_argument("-o", "--output", type=str, default=None)
        args = p2.parse_args()

    if args.command == "polish":
        input_path = Path(args.input)
        if not input_path.exists():
            print(f"Error: {input_path} not found", file=sys.stderr)
            sys.exit(1)
        output_path = (
            Path(args.output)
            if args.output
            else input_path.with_name(f"{input_path.stem}-polished.md")
        )
        text = input_path.read_text(encoding="utf-8")
        result = process(text)
        output_path.write_text(result, encoding="utf-8")
        print(f"Done. Output: {output_path}")

    elif args.command == "headings":
        input_path = Path(args.input)
        if not input_path.exists():
            print(f"Error: {input_path} not found", file=sys.stderr)
            sys.exit(1)
        result = extract_headings(
            input_path.read_text(encoding="utf-8"), context_lines=args.context
        )
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


if __name__ == "__main__":
    main()
