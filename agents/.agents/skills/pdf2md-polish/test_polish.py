"""Tests for pdf2md-polish deterministic processing pipeline."""

import importlib.util
from pathlib import Path

import pytest

# Load polish.py as a module (it has no __init__.py parent)
_SPEC = importlib.util.spec_from_file_location(
    "polish", Path(__file__).parent / "polish.py"
)
polish = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(polish)


# ── Abbreviation protection ─────────────────────────────────────────────────


class TestAbbreviationProtection:
    """Abbreviation dots must be protected from sentence splitting."""

    @pytest.mark.parametrize(
        "text, expected_sentence_count",
        [
            ("Dr. Smith arrived.", 1),
            ("Results in Fig. 3 show improvement.", 1),
            ("See Eq. 2 for details.", 1),
            ("Published by U.S. Naval Research.", 1),
            ("et al. proposed a method.", 1),
            ("Prof. J. Smith and Dr. A. B. Johnson spoke.", 1),
            ("The IEEE Conf. on Acoustics was held.", 1),
            ("Res. Lab. contributed to the project.", 1),
        ],
    )
    def test_abbreviation_not_split(self, text, expected_sentence_count):
        sentences = polish.split_sentences_in_text(text)
        assert len(sentences) == expected_sentence_count

    def test_cjk_followed_by_abbreviation(self):
        """Core bug: \\b failed when CJK char preceded abbreviation."""
        text = "基于Li et al.提出的框架(见Fig. 3)，我们改进了损失函数。"
        sentences = polish.split_sentences_in_text(text)
        # Should NOT split at "Fig." — only split at 。
        assert len(sentences) == 1

    def test_abbreviation_at_sentence_end(self):
        """Abbreviation at real sentence boundary should still split."""
        text = "The results were published by Dr. Smith. This is confirmed."
        sentences = polish.split_sentences_in_text(text)
        assert len(sentences) == 2

    def test_multiple_abbreviations_in_sentence(self):
        text = "Prof. J. Smith (U.S. Naval Res. Lab.) contributed."
        sentences = polish.split_sentences_in_text(text)
        assert len(sentences) == 1


# ── Sentence splitting ──────────────────────────────────────────────────────


class TestSentenceSplitting:
    def test_basic_split(self):
        text = "First sentence. Second sentence."
        sentences = polish.split_sentences_in_text(text)
        assert len(sentences) == 2

    def test_chinese_period_split(self):
        text = "第一句话。第二句话。"
        sentences = polish.split_sentences_in_text(text)
        assert len(sentences) == 2

    def test_chinese_exclamation(self):
        text = "太好了！真的吗？是的。"
        sentences = polish.split_sentences_in_text(text)
        assert len(sentences) == 3

    def test_decimal_not_split(self):
        text = "The temperature was 36.5 degrees."
        sentences = polish.split_sentences_in_text(text)
        assert len(sentences) == 1

    def test_multiple_decimals(self):
        text = "Pressure reached 101.325 kPa at time t=3.7 seconds."
        sentences = polish.split_sentences_in_text(text)
        assert len(sentences) == 1

    def test_ellipsis_not_split(self):
        text = "The algorithm... converged after 100 iterations."
        sentences = polish.split_sentences_in_text(text)
        assert len(sentences) == 1

    def test_exclamation_marks(self):
        text = "Really?! Yes!!!"
        sentences = polish.split_sentences_in_text(text)
        assert len(sentences) == 2

    def test_url_not_split(self):
        text = "Visit https://example.com/path.to/page for details."
        sentences = polish.split_sentences_in_text(text)
        assert len(sentences) == 1

    def test_email_not_split(self):
        text = "Contact info@example.org for details."
        sentences = polish.split_sentences_in_text(text)
        assert len(sentences) == 1

    def test_quoted_sentence(self):
        text = 'He said "Stop." She replied "No."'
        sentences = polish.split_sentences_in_text(text)
        assert len(sentences) == 2


# ── Inline math ─────────────────────────────────────────────────────────────


class TestInlineMath:
    def test_currency_not_math(self):
        text, mapping = polish.protect_inline_math("The cost is $100 per unit.")
        assert len(mapping) == 0

    def test_simple_formula(self):
        text, mapping = polish.protect_inline_math("The expression $x + y$ is simple.")
        assert len(mapping) == 1

    def test_formula_starting_with_digit(self):
        text, mapping = polish.protect_inline_math("$3x + 2y$ evaluates to 7.")
        assert len(mapping) == 1

    def test_formula_with_backslash_commands(self):
        text, mapping = polish.protect_inline_math("$\\alpha + \\beta$ is common.")
        assert len(mapping) == 1

    def test_formula_with_period_inside(self):
        """Period inside formula should be protected."""
        text, mapping = polish.protect_inline_math("$f(3) = 9.$ proves the claim.")
        assert len(mapping) == 1

    def test_comma_separated_variables(self):
        text, mapping = polish.protect_inline_math("Variables $a, b, c$ are given.")
        assert len(mapping) == 1

    def test_escaped_dollar_in_formula(self):
        text, mapping = polish.protect_inline_math(r"\$$b$")
        assert len(mapping) == 1
        assert list(mapping.values()) == ["$b$"]

    def test_escaped_dollar_closing(self):
        text, mapping = polish.protect_inline_math(r"$b\$$")
        assert len(mapping) == 1
        assert list(mapping.values()) == [r"$b\$$"]


# ── Display math ────────────────────────────────────────────────────────────


class TestDisplayMath:
    def test_display_math_block_parsed(self):
        text = "Before.\n\n$$E = mc^2$$\n\nAfter."
        blocks = polish.parse_blocks(text)
        kinds = [b.kind for b in blocks]
        assert "display_math" in kinds

    def test_latex_environment_parsed(self):
        text = "\\begin{equation}\na = b\n\\end{equation}"
        blocks = polish.parse_blocks(text)
        assert blocks[0].kind == "display_math"

    def test_display_math_preserved_in_process(self):
        text = "Before.\n\n$$E = mc^2$$\n\nAfter."
        result = polish.process(text)
        assert "$$E = mc^2$$" in result

    def test_display_math_not_sentence_split(self):
        """Display math content should not be processed as prose."""
        text = "$$\\int_0^1 f(x) dx = F(1) - F(0)$$"
        blocks = polish.parse_blocks(text)
        assert blocks[0].kind == "display_math"


# ── OCR cleanup ─────────────────────────────────────────────────────────────


class TestOCRCleanup:
    def test_ligature_fi(self):
        assert polish.cleanup_ligatures("ﬁnal") == "final"

    def test_ligature_fl(self):
        assert polish.cleanup_ligatures("ﬂawless") == "flawless"

    def test_ligature_ffi(self):
        assert polish.cleanup_ligatures("eﬃciently") == "efficiently"

    def test_ligature_ff(self):
        assert polish.cleanup_ligatures("diﬃcult") == "difficult"

    def test_en_dash(self):
        assert polish.cleanup_ligatures("A–B") == "A-B"

    def test_hyphen_reflow(self):
        lines = ["The experi-", "mental results confirm the hy-", "pothesis."]
        result = polish.join_soft_wrapped_lines(lines)
        assert result == "The experimental results confirm the hypothesis."

    def test_caption_reflow(self):
        """Figure/Table captions should reflow across lines."""
        text = "Figure 1. The architecture of the proposed\nframework showing the structure."
        sentences = polish.split_sentences_in_text(text)
        assert len(sentences) == 1
        assert "framework" in sentences[0]

    def test_table_caption_reflow(self):
        text = "Table 2. Comparison of methods\nacross three benchmark datasets."
        sentences = polish.split_sentences_in_text(text)
        assert len(sentences) == 1

    def test_stray_backslash_cleanup(self):
        # Stray backslashes (followed by chars not in exclusions) should be cleaned
        assert polish.cleanup_ocr(r"hello \@ world") == "hello @ world"
        # Valid LaTeX / markdown commands (followed by alphabet) should NOT be cleaned up
        assert polish.cleanup_ocr(r"hello \world") == r"hello \world"
        assert polish.cleanup_ocr(r"LaTeX \alpha command") == r"LaTeX \alpha command"
        # Escaped characters should be preserved
        assert polish.cleanup_ocr(r"escaped \\ character") == r"escaped \\ character"
        assert polish.cleanup_ocr(r"escaped \$ dollar") == r"escaped \$ dollar"
        assert polish.cleanup_ocr(r"escaped \  space") == r"escaped \  space"


# ── CJK handling ────────────────────────────────────────────────────────────


class TestCJK:
    def test_cjk_no_extra_spaces(self):
        """No space should be inserted between CJK and ASCII."""
        left, right = "你好", "world"
        assert not polish.needs_join_space(left, right)

    def test_cjk_sentence_break_at_period(self):
        text = "他说：好的。然后离开了。"
        sentences = polish.split_sentences_in_text(text)
        assert len(sentences) == 2

    def test_cjk_math_inline(self):
        text = "この式 $E = mc^2$ は有名です。"
        sentences = polish.split_sentences_in_text(text)
        assert len(sentences) == 1
        assert "$E = mc^2$" in sentences[0]


# ── Block parsing ───────────────────────────────────────────────────────────


class TestBlockParsing:
    def test_heading_block(self):
        blocks = polish.parse_blocks("# Title\n\n## Section")
        assert blocks[0].kind == "heading"
        assert blocks[2].kind == "heading"

    def test_code_fence_block(self):
        text = "Before.\n\n```python\ndef f():\n    pass\n```\n\nAfter."
        blocks = polish.parse_blocks(text)
        kinds = [b.kind for b in blocks]
        assert "code_fence" in kinds

    def test_list_block(self):
        text = "- item one\n- item two\n- item three"
        blocks = polish.parse_blocks(text)
        assert blocks[0].kind == "list"

    def test_pipe_table_block(self):
        text = "| A | B |\n|---|---|\n| 1 | 2 |"
        blocks = polish.parse_blocks(text)
        assert blocks[0].kind == "pipe_table"

    def test_image_block(self):
        blocks = polish.parse_blocks("![alt](url.png)")
        assert blocks[0].kind == "image"

    def test_hr_block(self):
        blocks = polish.parse_blocks("---")
        assert blocks[0].kind == "hr"

    def test_blockquote_block(self):
        blocks = polish.parse_blocks("> quoted text")
        assert blocks[0].kind == "blockquote"

    def test_paragraph_block(self):
        blocks = polish.parse_blocks("Just some prose text here.")
        assert blocks[0].kind == "paragraph"

    def test_blank_line(self):
        blocks = polish.parse_blocks("text\n\nmore text")
        assert blocks[1].kind == "blank"


# ── End-to-end process() ────────────────────────────────────────────────────


class TestEndToEnd:
    def test_basic_paragraph(self):
        result = polish.process("First sentence. Second sentence.")
        assert "First sentence." in result
        assert "Second sentence." in result

    def test_preserves_code_block(self):
        text = "Prose here.\n\n```python\nx = 1\n```\n\nMore prose."
        result = polish.process(text)
        assert "```python" in result
        assert "x = 1" in result

    def test_preserves_display_math(self):
        text = "Before.\n\n$$E = mc^2$$\n\nAfter."
        result = polish.process(text)
        assert "$$E = mc^2$$" in result

    def test_ligature_cleanup_e2e(self):
        result = polish.process("The ﬁnal result was ﬂawless.")
        assert "final" in result
        assert "flawless" in result

    def test_cjk_abbreviation_e2e(self):
        """Regression: CJK + abbreviation must not break."""
        text = "基于Li et al.提出的框架(见Fig. 3)，我们改进了损失函数。"
        result = polish.process(text)
        assert "Fig. 3" in result
        # Should be one sentence, not split at Fig.
        lines = [
            line
            for line in result.split("\n")
            if line.strip() and not line.startswith("#")
        ]
        # Only one content line (the sentence)
        assert len(lines) == 1

    def test_hyphen_reflow_e2e(self):
        text = "The experi-\nmental results confirm the hy-\npothesis."
        result = polish.process(text)
        assert "experimental" in result
        assert "hypothesis" in result

    def test_preserves_heading(self):
        text = "# Title\n\n## Section\n\nSome text."
        result = polish.process(text)
        assert "# Title" in result
        assert "## Section" in result

    def test_preserves_list(self):
        text = "- Item one.\n- Item two.\n- Item three."
        result = polish.process(text)
        assert "- Item one." in result
        assert "- Item two." in result

    def test_preserves_image(self):
        text = "![alt](image.png)"
        result = polish.process(text)
        assert "![alt](image.png)" in result

    def test_preserves_table(self):
        text = "| A | B |\n|---|---|\n| 1 | 2 |"
        result = polish.process(text)
        assert "| A | B |" in result

    def test_list_character_eating_regression(self):
        """Bug: list processing sliced based on content_col and ate characters if subsequent lines were less indented than content_col."""
        text = "- item\n detail"
        result = polish.process(text)
        assert result == "- item detail"

    def test_cjk_extensions(self):
        """Test that rare CJK extensions (e.g. SIP planes) are recognized as CJK and don't insert extra spaces."""
        # 𠜎 is U+2070E, which is in SIP
        left, right = "𠜎", "world"
        assert not polish.needs_join_space(left, right)


# ── Math spacing ────────────────────────────────────────────────────────────


class TestMathSpacing:
    def test_cleanup_math_body_spaces(self):
        # subscript spacing
        assert polish.cleanup_math_body("x_{ i }") == "x_{i}"
        # digits spacing
        assert polish.cleanup_math_body("1 2 . 3") == "12.3"
        # math function spacing
        assert polish.cleanup_math_body("\\alpha ( x )") == "\\alpha(x)"
        assert polish.cleanup_math_body("a + b") == "a + b"  # regular spacing kept

    def test_cleanup_math_content_spacing(self):
        assert polish.cleanup_math_content_spacing("$x_{ i }$") == "$x_{i}$"
        assert polish.cleanup_math_content_spacing("$$1 2 . 3$$") == "$$12.3$$"

    def test_cleanup_math_boundary_spacing(self):
        # Punctuation spacing
        assert polish._cleanup_math_boundary_spacing("in $x$ .") == "in $x$."
        assert polish._cleanup_math_boundary_spacing("( $x$ )") == "($x$)"
        # Multiple math blocks
        assert polish._cleanup_math_boundary_spacing("if $x$ , $y$") == "if $x$, $y$"


# ── Heading tools ───────────────────────────────────────────────────────────


class TestHeadingTools:
    def test_extract_headings_basic(self):
        text = "# Document Title\nSome text.\n\n## Section 1\nIntroduction here.\n\n### Subsection 1.1\nDetail."
        expected = "L   1 # Document Title  ctx: Some text.\nL   4 ## Section 1  ctx: Introduction here.\nL   7 ### Subsection 1.1  ctx: Detail."
        assert polish.extract_headings(text, context_lines=1) == expected

    def test_extract_headings_with_blockquote(self):
        text = "> # Quoted Title\n> Context here."
        expected = "L   1 # Quoted Title  ctx: > Context here."
        assert polish.extract_headings(text, context_lines=1) == expected

    def test_apply_headings_basic(self):
        text = "# Title\n\n## Section 1\n\n### Section 2"
        mapping = {1: "##", 5: "##"}
        result = polish.apply_headings(text, mapping)
        assert result == "## Title\n\n## Section 1\n\n## Section 2"

    def test_apply_headings_with_blockquote(self):
        text = "> # Title\nSome content."
        mapping = {1: "##"}
        result = polish.apply_headings(text, mapping)
        assert result == "> ## Title\nSome content."


# ── Blockquote boundary ──────────────────────────────────────────────────────


class TestBlockquoteBoundary:
    def test_bare_list_item_not_absorbed_into_blockquote(self):
        """A bare list item after a blockquote (no blank line) must not be absorbed."""
        text = "> quoted text\n- item outside"
        blocks = polish.parse_blocks(text)
        assert blocks[0].kind == "blockquote"
        assert blocks[0].lines == ["> quoted text"]
        assert blocks[1].kind == "list"
        assert blocks[1].lines == ["- item outside"]

    def test_bare_paragraph_not_absorbed_into_blockquote(self):
        """A bare paragraph after a blockquote (no blank line) must not be absorbed."""
        text = "> quoted text\nNext paragraph"
        blocks = polish.parse_blocks(text)
        assert blocks[0].kind == "blockquote"
        assert blocks[1].kind == "paragraph"

    def test_multiline_blockquote(self):
        """Multiple > lines form one blockquote block."""
        text = "> line one\n> line two\n> line three"
        blocks = polish.parse_blocks(text)
        assert len(blocks) == 1
        assert blocks[0].kind == "blockquote"
        assert len(blocks[0].lines) == 3

    def test_blockquote_with_continuation(self):
        """Non-prefixed continuation lines should not be in blockquote."""
        text = "> line one\ncontinuation\n> line two"
        blocks = polish.parse_blocks(text)
        assert blocks[0].kind == "blockquote"
        assert blocks[0].lines == ["> line one"]
        assert blocks[1].kind == "paragraph"


# ── Non-prose ligature cleanup ───────────────────────────────────────────────


class TestNonProseLigatureCleanup:
    def test_ligature_in_pipe_table(self):
        """Ligatures in pipe table cells should be cleaned."""
        text = "| Eﬃcient | Method |\n|---|---|\n| A | B |"
        result = polish.process(text)
        assert "Efficient" in result
        assert "ﬃ" not in result

    def test_ligature_in_image_alt(self):
        """Ligatures in image alt text should be cleaned."""
        text = "![Eﬃcient method](img.png)"
        result = polish.process(text)
        assert "Efficient" in result

    def test_ligature_in_heading(self):
        """Ligatures in headings should be cleaned."""
        text = "# Eﬃcient Methods"
        result = polish.process(text)
        assert "Efficient" in result

    def test_code_fence_ligature_preserved(self):
        """Ligatures inside code fences should NOT be cleaned (it's code)."""
        text = "```\nEﬃcient\n```"
        result = polish.process(text)
        assert "ﬃ" in result


# ── Heading OCR cleanup ──────────────────────────────────────────────────────


class TestHeadingOCRCleanup:
    def test_heading_stray_backslash_removed(self):
        """Stray backslashes in headings should be removed."""
        text = "# Introduction\\@"
        result = polish.process(text)
        assert "Introduction@" in result
        assert "\\" not in result.split("\n")[0].replace("#", "").strip()

    def test_heading_valid_latex_preserved(self):
        """Valid LaTeX commands in headings should be preserved."""
        text = "# Using \\alpha in formulas"
        result = polish.process(text)
        assert "\\alpha" in result


# ── List sentence splitting ──────────────────────────────────────────────────


class TestListSentenceSplitting:
    def test_list_item_sentence_split(self):
        """Simple list items should get sentence splitting."""
        text = "- First sentence. Second sentence.\n- Another item."
        result = polish.process(text)
        lines = [line for line in result.split("\n") if line.strip()]
        # Should have at least 3 lines: two from first item + one from second
        assert len(lines) >= 3

    def test_list_item_preserves_prefix(self):
        """Subsequent sentences in a list item should keep the prefix."""
        text = "- First sentence. Second sentence."
        result = polish.process(text)
        lines = [line for line in result.split("\n") if line.strip()]
        assert lines[0].startswith("- ")
        assert lines[1].startswith("  ")  # continuation indent


# ── Code fence preservation ──────────────────────────────────────────────────


class TestCodeFencePreservation:
    def test_code_fence_content_unchanged(self):
        """Code fence content should pass through unchanged."""
        text = "```\ndef foo():\n    return 42\n```"
        result = polish.process(text)
        assert "def foo():" in result
        assert "    return 42" in result

    def test_code_fence_with_tilde(self):
        """Tilde code fences should be recognized."""
        text = "~~~python\nprint('hello')\n~~~"
        blocks = polish.parse_blocks(text)
        assert blocks[0].kind == "code_fence"

    def test_code_fence_with_inline_dollar(self):
        """Dollar signs inside code fences should not be treated as math."""
        text = "```\n$price = 100\n```"
        result = polish.process(text)
        assert "$price = 100" in result


# ── Inline math edge cases ───────────────────────────────────────────────────


class TestInlineMathEdgeCases:
    def test_escaped_opening_dollar(self):
        r"""Escaped \$ should not open inline math."""
        text, mapping = polish.protect_inline_math(r"price is \$100 and $x+y$ ok")
        assert len(mapping) == 1
        assert list(mapping.values()) == ["$x+y$"]

    def test_consecutive_double_dollars(self):
        """$$ should not be treated as two single $ for inline math."""
        text, mapping = polish.protect_inline_math("$$E = mc^2$$")
        assert len(mapping) == 0

    def test_dollar_followed_by_punctuation(self):
        """$ followed by punctuation is not valid math open."""
        text, mapping = polish.protect_inline_math("$.50 is cheap")
        assert len(mapping) == 0

    def test_empty_formula(self):
        """Empty $$ is not valid inline math."""
        text, mapping = polish.protect_inline_math("price is $$ here")
        assert len(mapping) == 0

    def test_math_boundary_spacing_e2e(self):
        """Boundary spacing cleanup should tighten $ and punctuation."""
        result = polish.process("We found $x + y$ . The result.")
        assert "$x+y$." in result or "$x+y$ ." not in result
