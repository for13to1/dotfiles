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

    def test_german_abbreviation_split(self):
        text = "Es gibt viele Anwendungen, z. B. in der Informatik. Eine weitere ist in der Medizin."
        sentences = polish.split_sentences_in_text(text)
        assert len(sentences) == 2
        assert "z. B." in sentences[0]


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

    def test_decimal_with_spaces_not_split(self):
        text = "The value is 3 . 14 in this case."
        sentences = polish.split_sentences_in_text(text)
        assert len(sentences) == 1

    def test_multiple_decimals(self):
        text = "Pressure reached 101.325 kPa at time t=3.7 seconds."
        sentences = polish.split_sentences_in_text(text)
        assert len(sentences) == 1

    def test_sentence_ending_before_number_splits(self):
        """A real sentence boundary before a number/list marker must split.
        The decimal guard only applies when a digit precedes the dot too
        (e.g. '3 . 14'), not 'End. 2. New.'."""
        sentences = polish.split_sentences_in_text("End. 2. New.")
        assert sentences == ["End.", "2.", "New."]

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

    def test_formula_with_decimal_spaces_protected(self):
        text, mapping = polish.protect_inline_math(
            "Once all the off-grid brightnesses $M _ { o } ( i + 0 . 5 , j + 0 . 5 )$ have been determined"
        )
        assert len(mapping) == 1
        assert list(mapping.values()) == ["$M _ { o } ( i + 0 . 5 , j + 0 . 5 )$"]


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
        assert "$$E=mc^2$$" in result

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

    def test_en_dash_preserved(self):
        """en-dash is meaningful punctuation (e.g. page ranges pp. 12–15) and
        must NOT be rewritten to a hyphen."""
        assert polish.cleanup_ligatures("A–B") == "A–B"
        assert "–" in polish.process("Pages pp. 12–15 cover it.")

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


# ── Inline whitespace normalization ──────────────────────────────────────────


class TestInlineWhitespace:
    def test_prose_multi_space_collapsed(self):
        result = polish.process("Word1    word2     word3.")
        assert "Word1 word2 word3." in result

    def test_prose_multi_space_across_sentences(self):
        result = polish.process("First  sentence.   Second  one.")
        lines = [line for line in result.split("\n") if line.strip()]
        assert lines == ["First sentence.", "Second one."]

    def test_heading_multi_space_collapsed(self):
        assert polish.process("# 1.    Introduction") == "# 1. Introduction\n"

    def test_tab_collapsed_to_space(self):
        result = polish.process("a\t\tb is here.")
        assert "a b is here." in result

    def test_inline_code_spacing_preserved(self):
        result = polish.process("Run `a    b` now. Done.")
        assert "`a    b`" in result

    def test_link_internal_spacing_preserved(self):
        result = polish.process("See [our  paper](http://x.com) here. End.")
        assert "[our  paper](http://x.com)" in result

    def test_inline_math_spacing_not_broken_by_collapse(self):
        """collapse must not corrupt inline math; math normalization still owns
        its spacing (a + b -> a+b)."""
        result = polish.process("We use $a + b$    here. Done.")
        assert "$a+b$" in result

    def test_german_single_space_abbreviation_preserved(self):
        """Single spaces (e.g. in 'z. B.') are no-ops and must survive."""
        result = polish.process("Es gibt viele, z. B. in der Informatik.")
        assert "z. B." in result


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
        assert "$$E=mc^2$$" in result

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
        assert result == "- item detail\n"

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
        assert polish.cleanup_math_body("a + b") == "a+b"  # operator spaces removed

    def test_cleanup_math_body_bracket_spacing(self):
        # square bracket spacing
        assert (
            polish.cleanup_math_body(r"\sqrt{[ a ]^{2}+[ b ]^{2}}")
            == r"\sqrt{[a]^{2}+[b]^{2}}"
        )

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

    def test_extract_headings_ignores_code_block_comments(self):
        text = "# Title\n\n```python\n# Comment\n```"
        expected = "L   1 # Title"
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

    def test_nested_list_reflow(self):
        """Nested list items and parent item should both reflow correctly while keeping nesting structure."""
        text = (
            "- The first objective is to design a high-performance\n"
            "  classifier, which runs in real-time on\n"
            "  embedded platforms.\n"
            "  - Specifically, we target devices with less than\n"
            "    2GB of RAM."
        )
        result = polish.process(text)
        lines = [line for line in result.split("\n") if line.strip()]
        # Parent list item should be reflowed into a single line
        assert (
            lines[0]
            == "- The first objective is to design a high-performance classifier, which runs in real-time on embedded platforms."
        )
        # Sub-list item should also be reflowed into a single line, correctly indented
        assert (
            lines[1] == "  - Specifically, we target devices with less than 2GB of RAM."
        )

    def test_list_item_with_display_math(self):
        """Multi-line display math inside a list item should be preserved."""
        text = "- The formula\n\n  $$\n  E = mc^2\n  $$\n\n  is famous.\n- Next item."
        result = polish.process(text)
        assert "E=mc^2" in result
        assert "- The formula" in result
        assert "- Next item." in result


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
        assert "$x+y$." in result
        assert "$x+y$ ." not in result

    def test_link_with_periods_not_split(self):
        """Markdown links containing dots should not be split into multiple sentences."""
        text = "Check [our paper Fig. 1. Detailed comparison is given.](http://example.com/fig1) for details."
        sentences = polish.split_sentences_in_text(text)
        assert len(sentences) == 1

    def test_image_with_periods_not_split(self):
        """Markdown images with periods in alt text should not cause false splits."""
        text = "See Fig. 1. below."
        sentences = polish.split_sentences_in_text(text)
        assert len(sentences) == 2
        # "Fig." is protected as abbreviation, but "1." triggers a split after protection
        # because "1." is sentence-ending punctuation followed by space.
        # This is the expected behavior — the image alt text test is below.
        text2 = "See ![Fig. 1. Comparison](img.png) for details."
        sentences2 = polish.split_sentences_in_text(text2)
        assert len(sentences2) == 1

    def test_multiple_links_in_sentence(self):
        """Multiple links in one sentence should all be preserved."""
        text = "See [Fig. 1](a.com) and [Fig. 2](b.com) for details."
        sentences = polish.split_sentences_in_text(text)
        assert len(sentences) == 1
        assert "[Fig. 1](a.com)" in sentences[0]
        assert "[Fig. 2](b.com)" in sentences[0]


# ── LaTeX delimiter normalization (\(...\) -> $...$, \[...\] -> $$...$$) ──────


class TestLatexDelimiterNormalization:
    def test_inline_paren_math_to_dollar(self):
        """\\(...\\) inline math is normalized to $...$ and spacing-cleaned."""
        result = polish.process(r"The value \(x + y\) is here. Done.")
        assert "$x+y$" in result
        assert r"\(" not in result and r"\)" not in result

    def test_inline_paren_math_period_not_split(self):
        """A period inside \\(...\\) must not cause a false sentence break."""
        sentences = polish.split_sentences_in_text(
            polish.normalize_inline_paren_math(r"Let \(a = 1.5\) hold. Next.")
        )
        assert len(sentences) == 2

    def test_escaped_backslash_paren_left_alone(self):
        """\\\\( (escaped backslash + paren) is not a math delimiter."""
        result = polish.normalize_inline_paren_math(r"A literal \\(x\\) token.")
        assert result == r"A literal \\(x\\) token."

    def test_display_bracket_math_to_double_dollar(self):
        """\\[...\\] display math is normalized to $$...$$."""
        result = polish.process("Before.\n\n\\[ E = mc^2 \\]\n\nAfter.")
        assert "$$E=mc^2$$" in result
        assert r"\[" not in result and r"\]" not in result

    def test_latex_environment_preserved(self):
        r"""\begin{...} environments are NOT converted (multi-line align etc.)."""
        result = polish.process("\\begin{align}\na &= b\n\\end{align}")
        assert "\\begin{align}" in result
        assert "\\end{align}" in result


# ── Block boundary transitions ───────────────────────────────────────────────


class TestBlockBoundaries:
    """Verify correct block detection at transitions between block types."""

    def test_paragraph_to_heading(self):
        text = "Some prose.\n# New Section"
        blocks = polish.parse_blocks(text)
        assert blocks[0].kind == "paragraph"
        assert blocks[1].kind == "heading"

    def test_paragraph_to_list(self):
        text = "Some prose.\n- item one\n- item two"
        blocks = polish.parse_blocks(text)
        assert blocks[0].kind == "paragraph"
        assert blocks[1].kind == "list"

    def test_paragraph_to_display_math(self):
        text = "Some prose.\n$$\nE = mc^2\n$$"
        blocks = polish.parse_blocks(text)
        assert blocks[0].kind == "paragraph"
        assert blocks[1].kind == "display_math"

    def test_list_to_paragraph(self):
        text = "- item one\n- item two\nSome prose."
        blocks = polish.parse_blocks(text)
        assert blocks[0].kind == "list"
        assert blocks[1].kind == "paragraph"

    def test_list_to_heading(self):
        text = "- item one\n# New Section"
        blocks = polish.parse_blocks(text)
        assert blocks[0].kind == "list"
        assert blocks[1].kind == "heading"

    def test_heading_to_paragraph(self):
        text = "# Title\nSome prose."
        blocks = polish.parse_blocks(text)
        assert blocks[0].kind == "heading"
        assert blocks[1].kind == "paragraph"

    def test_display_math_to_paragraph(self):
        text = "$$E = mc^2$$\nSome prose."
        blocks = polish.parse_blocks(text)
        assert blocks[0].kind == "display_math"
        assert blocks[1].kind == "paragraph"

    def test_code_fence_to_paragraph(self):
        text = "```\ncode\n```\nSome prose."
        blocks = polish.parse_blocks(text)
        assert blocks[0].kind == "code_fence"
        assert blocks[1].kind == "paragraph"

    def test_pipe_table_to_paragraph(self):
        text = "| A | B |\n|---|---|\n| 1 | 2 |\nSome prose."
        blocks = polish.parse_blocks(text)
        assert blocks[0].kind == "pipe_table"
        assert blocks[1].kind == "paragraph"

    def test_blockquote_to_paragraph(self):
        text = "> quoted text\nSome prose."
        blocks = polish.parse_blocks(text)
        assert blocks[0].kind == "blockquote"
        assert blocks[1].kind == "paragraph"

    def test_full_document_e2e(self):
        """A realistic document with multiple block types processes without error."""
        text = (
            "# Title\n"
            "\n"
            "First sentence. Second sentence.\n"
            "\n"
            "## Section\n"
            "\n"
            "- Item one. Item two.\n"
            "- Item three.\n"
            "\n"
            "$$E = mc^2$$\n"
            "\n"
            "> Quoted text here. Another sentence.\n"
            "\n"
            "| A | B |\n"
            "|---|---|\n"
            "| 1 | 2 |\n"
        )
        result = polish.process(text)
        # Should process without error and preserve structure
        assert "# Title" in result
        assert "## Section" in result
        assert "First sentence." in result
        assert "Second sentence." in result
        assert "$$E=mc^2$$" in result
        assert "| A | B |" in result

    def test_blockquote_recursive_processing(self):
        """Headings and lists inside blockquotes should be parsed and processed recursively."""
        text = "> # Heading inside blockquote\n> - item one\n> - item two"
        result = polish.process(text)
        assert "> # Heading inside blockquote" in result
        assert "> - item one" in result
        assert "> - item two" in result

    def test_blockquote_with_inline_math(self):
        """Inline math inside blockquotes should be preserved after sentence splitting."""
        text = "> The formula $x + y$ is simple. Another sentence."
        result = polish.process(text)
        assert "> The formula $x+y$ is simple." in result
        assert "> Another sentence." in result

    def test_blockquote_with_display_math(self):
        """Display math inside blockquotes should be preserved."""
        text = "> See below:\n>\n> $$\n> E = mc^2\n> $$"
        result = polish.process(text)
        assert "$$" in result
        assert "E=mc^2" in result

    def test_blockquote_preserves_paragraph_separator(self):
        """Interior blank lines that separate paragraphs inside a blockquote must
        survive recursive processing (regression: the trailing-newline strip must
        not drop interior blanks and merge the paragraphs)."""
        text = "> Para one.\n>\n> Para two."
        result = polish.process(text)
        assert result == "> Para one.\n>\n> Para two.\n"


# ── Defensive block processing ───────────────────────────────────────────────


class TestDefensiveBlockProcessing:
    """Every block kind must degrade gracefully (warn + preserve) on failure,
    not abort the whole document. Guards the uniform try/except in
    process_block."""

    def test_malformed_inputs_do_not_raise(self):
        for txt in [
            "- item one\n- item two",
            "- a\n  - b\n    - c",
            "$$\n\\frac{a}{",  # unbalanced display math
            "| a | b |\n|---|---|\n| 1 | 2 |",
            "<table><tr><td>x</td></tr></table>",
        ]:
            # Must not raise.
            polish.process(txt)

    def test_failing_block_is_preserved_not_dropped(self, monkeypatch):
        """If a block processor raises, that block is emitted unchanged and the
        rest of the document still processes."""

        def boom(block):
            raise RuntimeError("synthetic failure")

        monkeypatch.setattr(polish, "process_list_block", boom)
        text = "Intro sentence.\n\n- list item that will fail\n\n# Heading"
        result = polish.process(text)
        # Surrounding blocks still processed; failing list preserved verbatim.
        assert "Intro sentence." in result
        assert "- list item that will fail" in result
        assert "# Heading" in result

    def test_borderless_pipe_table_block(self):
        """Borderless tables (no outer pipes) should be recognized as pipe tables."""
        text = "A | B\n---|---\n1 | 2"
        blocks = polish.parse_blocks(text)
        assert blocks[0].kind == "pipe_table"

    def test_borderless_table_preserved_e2e(self):
        """Borderless tables should pass through without paragraph reflowing/sentence-splitting."""
        text = "Name | Age\n---|---\nAlice | 20\nBob | 30"
        result = polish.process(text)
        assert "Name | Age" in result
        assert "---|---" in result
        assert "Alice | 20" in result
        assert "Bob | 30" in result

    def test_multi_paragraph_list_preserved(self):
        """Multi-paragraph lists separated by blank lines should preserve indentation and layout."""
        text = "- Item one.\n\n  Paragraph two.\n- Item two."
        result = polish.process(text)
        # Expected output includes indentation for continuation paragraph
        assert "- Item one.\n\n  Paragraph two.\n- Item two." in result

    def test_unbalanced_paren_math_not_matched(self):
        """Unbalanced paren math must not match across other math tags."""
        result = polish.process("Let \\( be a paren, and \\(x + y\\) be math.")
        assert "Let \\( be a paren" in result
        assert "$x+y$" in result

    def test_paragraph_with_fewer_pipes_not_eaten_by_table(self):
        """A borderless table followed (no blank line) by a paragraph whose
        unescaped-pipe count differs from the align row must not extend the
        table block; the paragraph must remain a paragraph."""
        text = (
            "A | B | C\n"
            "---|---|---\n"
            "1 | 2 | 3\n"
            "Next paragraph has | a literal pipe.\n"
            "Plain final line."
        )
        blocks = polish.parse_blocks(text)
        kinds = [b.kind for b in blocks]
        assert "pipe_table" in kinds
        para_blocks = [b for b in blocks if b.kind == "paragraph"]
        assert any(
            "Next paragraph has | a literal pipe." in "\n".join(b.lines)
            for b in para_blocks
        )

    def test_blank_then_paragraph_ends_list(self):
        """A blank line followed by a non-list, non-indented paragraph must
        terminate the list — the paragraph stays its own block."""
        text = "- a\n- b\n\nNormal paragraph."
        result = polish.process(text)
        assert "- a\n- b\n\nNormal paragraph." in result
