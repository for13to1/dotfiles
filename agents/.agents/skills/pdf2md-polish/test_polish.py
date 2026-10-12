"""Tests for pdf2md-polish deterministic processing pipeline."""

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent))

import polish

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
        text = (
            "Es gibt viele Anwendungen, z. B. in der Informatik. Eine weitere ist in der Medizin."
        )
        sentences = polish.split_sentences_in_text(text)
        assert len(sentences) == 2
        assert "z. B." in sentences[0]


# ── Context-aware (breakable) abbreviations ─────────────────────────────────


class TestBreakableAbbreviations:
    """etc. and approx. are left unprotected before space + uppercase so the
    sentence splitter can treat them as sentence boundaries.  All other
    abbreviations are always protected regardless of what follows."""

    # --- etc. splits before uppercase ----------------------------------------

    def test_etc_before_uppercase_splits(self):
        """'etc. The' should produce two sentences."""
        text = "We tested foo, bar, baz, etc. The results were positive."
        sentences = polish.split_sentences_in_text(text)
        assert len(sentences) == 2
        assert sentences[0].endswith("etc.")
        assert sentences[1].startswith("The")

    def test_etc_before_lowercase_does_not_split(self):
        """'etc., and' — etc. mid-sentence should stay on the same line."""
        text = "We used Python, NumPy, etc., and then ran the analysis."
        sentences = polish.split_sentences_in_text(text)
        assert len(sentences) == 1

    def test_etc_with_closing_quote_before_uppercase_splits(self):
        """Closing punctuation between etc. and uppercase should still split."""
        text = "She listed 'foo, bar, etc.' The next topic was different."
        sentences = polish.split_sentences_in_text(text)
        assert len(sentences) == 2

    # --- approx. splits before uppercase -------------------------------------

    def test_approx_before_uppercase_splits(self):
        """'approx. This' should produce two sentences."""
        text = "The delay was approx. This was acceptable."
        sentences = polish.split_sentences_in_text(text)
        assert len(sentences) == 2
        assert sentences[0].endswith("approx.")
        assert sentences[1].startswith("This")

    def test_approx_before_lowercase_does_not_split(self):
        """'approx. 3 ms' — approx. followed by a number should not split."""
        text = "The latency was approx. 3 ms per request."
        sentences = polish.split_sentences_in_text(text)
        assert len(sentences) == 1

    # --- always-protected abbreviations never split --------------------------

    def test_ie_before_uppercase_does_not_split(self):
        """i.e. is always protected — should never trigger a sentence break."""
        text = "The value is fixed, i.e. There is no configuration needed."
        sentences = polish.split_sentences_in_text(text)
        # i.e. must be protected; the whole text is one sentence.
        # (Previous weaker assertions would pass even if i.e. split incorrectly.)
        assert len(sentences) == 1
        assert "i.e." in sentences[0]

    def test_eg_before_uppercase_does_not_split(self):
        """e.g. is always protected — should never trigger a sentence break."""
        text = "Use a fast language, e.g. Python or Go, for scripting."
        sentences = polish.split_sentences_in_text(text)
        assert len(sentences) == 1

    # --- end-of-string edge case ---------------------------------------------

    def test_etc_at_end_of_string_does_not_protect(self):
        """etc. at the very end of the input is also a sentence boundary."""
        text = "We support foo, bar, etc."
        sentences = polish.split_sentences_in_text(text)
        # Single sentence — no split needed, but the abbreviation must not
        # cause a double-dot restoration artifact.
        assert len(sentences) == 1
        assert sentences[0].endswith("etc.")


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

    def test_sentence_break_after_inline_math(self):
        """Period immediately after inline math should still trigger a split."""
        text = "The range is $R_{1}$ and $R_{2}$. This method is illustrated in Figure 7."
        sentences = polish.split_sentences_in_text(text)
        assert len(sentences) == 2
        assert sentences[0].endswith("$R_{2}$.")
        assert sentences[1].startswith("This")


# ── Inline math ─────────────────────────────────────────────────────────────


class TestInlineMath:
    def test_currency_not_math(self):
        _text, mapping = polish.protect_inline_math("The cost is $100 per unit.")
        assert len(mapping) == 0

    def test_simple_formula(self):
        _text, mapping = polish.protect_inline_math("The expression $x + y$ is simple.")
        assert len(mapping) == 1

    def test_formula_starting_with_digit(self):
        _text, mapping = polish.protect_inline_math("$3x + 2y$ evaluates to 7.")
        assert len(mapping) == 1

    def test_formula_with_backslash_commands(self):
        _text, mapping = polish.protect_inline_math("$\\alpha + \\beta$ is common.")
        assert len(mapping) == 1

    def test_formula_with_period_inside(self):
        """Period inside formula should be protected."""
        _text, mapping = polish.protect_inline_math("$f(3) = 9.$ proves the claim.")
        assert len(mapping) == 1

    def test_comma_separated_variables(self):
        _text, mapping = polish.protect_inline_math("Variables $a, b, c$ are given.")
        assert len(mapping) == 1

    def test_escaped_dollar_in_formula(self):
        _text, mapping = polish.protect_inline_math(r"\$$b$")
        assert len(mapping) == 1
        assert list(mapping.values()) == ["$b$"]

    def test_escaped_dollar_closing(self):
        _text, mapping = polish.protect_inline_math(r"$b\$$")
        assert len(mapping) == 1
        assert list(mapping.values()) == [r"$b\$$"]

    def test_formula_with_decimal_spaces_protected(self):
        _text, mapping = polish.protect_inline_math(
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
    def test_insert_cjk_ascii_spacing(self):
        """Chinese-English mixed prose gets spaces at CJK↔ASCII boundaries."""
        assert polish.insert_cjk_ascii_spacing("使用Python和OpenCV") == "使用 Python 和 OpenCV"
        assert polish.insert_cjk_ascii_spacing("数字123") == "数字 123"
        assert polish.insert_cjk_ascii_spacing("纯中文文本") == "纯中文文本"
        assert polish.insert_cjk_ascii_spacing("第一句。第二句") == "第一句。第二句"
        assert polish.insert_cjk_ascii_spacing("公式$x+y$结束") == "公式$x+y$结束"

    def test_cjk_ascii_spacing(self):
        """Space is inserted between CJK and ASCII/numbers (Chinese-English mixed prose)."""
        assert polish.needs_join_space("你好", "world")
        assert polish.needs_join_space("world", "你好")
        assert polish.needs_join_space("数字", "123")

    def test_cjk_cjk_no_space(self):
        """No space between two CJK runs."""
        assert not polish.needs_join_space("你好", "世界")
        assert not polish.needs_join_space("第一句", "。第二句")

    def test_cjk_no_space_before_punctuation(self):
        """No space before ASCII or full-width punctuation."""
        assert not polish.needs_join_space("hello", ",")
        assert not polish.needs_join_space("你好", "，")
        assert not polish.needs_join_space("你好", "。")

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
        lines = [line for line in result.split("\n") if line.strip() and not line.startswith("#")]
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
        """Rare CJK extensions (e.g. SIP planes) are recognized as CJK: space with ASCII, none with CJK."""
        # 𠜎 is U+2070E, which is in SIP
        assert polish.needs_join_space("𠜎", "world")
        assert not polish.needs_join_space("𠜎", "文本")


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
        assert polish.cleanup_math_body(r"\sqrt{[ a ]^{2}+[ b ]^{2}}") == r"\sqrt{[a]^{2}+[b]^{2}}"

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
        assert lines[1] == "  - Specifically, we target devices with less than 2GB of RAM."

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
        _text, mapping = polish.protect_inline_math(r"price is \$100 and $x+y$ ok")
        assert len(mapping) == 1
        assert list(mapping.values()) == ["$x+y$"]

    def test_consecutive_double_dollars(self):
        """$$ should not be treated as two single $ for inline math."""
        _text, mapping = polish.protect_inline_math("$$E = mc^2$$")
        assert len(mapping) == 0

    def test_dollar_followed_by_punctuation(self):
        """$ followed by punctuation is not valid math open."""
        _text, mapping = polish.protect_inline_math("$.50 is cheap")
        assert len(mapping) == 0

    def test_empty_formula(self):
        """Empty $$ is not valid inline math."""
        _text, mapping = polish.protect_inline_math("price is $$ here")
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
        r"""\begin{...} environments are NOT converted to $$...$$."""
        result = polish.process("\\begin{align}\na &= b\n\\end{align}")
        assert "\\begin{align}" in result
        assert "\\end{align}" in result

    def test_latex_environment_keeps_environment_form(self):
        r"""LaTeX environments stay as environments even if internal spacing is normalized."""
        text = "\\begin{align}\na &= b + c \\\\\n d &= e + f\n\\end{align}"
        result = polish.process(text)
        assert "\\begin{align}" in result
        assert "\\end{align}" in result
        assert "b+c" in result
        assert "e+f" in result
        assert "$$" not in result


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
        text = "A | B | C\n---|---|---\n1 | 2 | 3\nNext paragraph has | a literal pipe.\nPlain final line."
        blocks = polish.parse_blocks(text)
        kinds = [b.kind for b in blocks]
        assert "pipe_table" in kinds
        para_blocks = [b for b in blocks if b.kind == "paragraph"]
        assert any(
            "Next paragraph has | a literal pipe." in "\n".join(b.lines) for b in para_blocks
        )

    def test_blank_then_paragraph_ends_list(self):
        """A blank line followed by a non-list, non-indented paragraph must
        terminate the list — the paragraph stays its own block."""
        text = "- a\n- b\n\nNormal paragraph."
        result = polish.process(text)
        assert "- a\n- b\n\nNormal paragraph." in result


# ── Warning accounting ──────────────────────────────────────────────────────


class TestWarningAccounting:
    def test_unbalanced_display_math_increments_warning_count(self):
        polish.process("$$\n\\frac{a}{\n")
        assert polish.get_warning_count() == 1

    def test_warning_count_resets_for_next_top_level_process_call(self):
        polish.process("$$\n\\frac{a}{\n")
        assert polish.get_warning_count() == 1
        polish.process("Plain sentence.")
        assert polish.get_warning_count() == 0

    def test_nested_process_warnings_roll_up_to_outer_call(self):
        text = "> $$\n> \\frac{a}{\n"
        polish.process(text)
        assert polish.get_warning_count() == 1


# ── Idempotency ─────────────────────────────────────────────────────────────


class TestIdempotency:
    """process() must be idempotent: applying it twice on the same input
    must produce the same text as applying it once.

    out1 = process(raw)
    assert process(out1) == out1
    """

    _SAMPLE_INPUT = (Path(__file__).parent / "examples" / "sample_input.md").read_text(
        encoding="utf-8"
    )

    def test_sample_input_idempotent(self):
        """Full realistic OCR fixture: covers soft-wrap, ligatures, German
        abbreviations, inline math, lists, blockquote, and images."""
        out1 = polish.process(self._SAMPLE_INPUT)
        out2 = polish.process(out1)
        assert out2 == out1

    @pytest.mark.parametrize(
        "description, raw",
        [
            (
                "plain paragraph with soft-wrap",
                "The quick brown fox jumps over the lazy\ndog. A second sentence follows.",
            ),
            (
                "abbreviations mid-sentence",
                "Results in Fig. 3 show that, e.g., the method by Li et al. outperforms\nthe baseline.",
            ),
            (
                "breakable abbreviation before uppercase",
                "We covered Python, NumPy, etc. The next section introduces PyTorch.",
            ),
            (
                "inline math with sentence boundary",
                "The value is $x_{i}$. Another sentence with $y^2$ follows.",
            ),
            (
                "display math block",
                "Consider:\n\n$$\n\\frac{a}{b} = c\n$$\n\nThe above holds.",
            ),
            (
                "nested list",
                "- First item.\n  - Sub-item one.\n  - Sub-item two.\n- Second item.",
            ),
            (
                "blockquote",
                "> This is a quote. It has two sentences.\n> Another line of the quote.",
            ),
            (
                "hyphen reflow",
                "This is a hyphen-\nated word inside a soft-wrapped para.",
            ),
            (
                "code fence passthrough",
                "Some text.\n\n```python\nx = 1  # comment.\nprint(x)\n```\n\nMore text.",
            ),
            (
                "pipe table passthrough",
                "| A | B |\n|---|---|\n| 1 | 2 |",
            ),
            (
                "HTML table conversion",
                (
                    "<table><tr><td>输出图像,即</td><td><code>outFrame</code></td></tr>"
                    "<tr><td>参数范围[0x0, 0x3ff]</td><td>ok&amp;ok</td></tr></table>"
                ),
            ),
            (
                "pipe table CJK spacing",
                "| 参数名 | 描述 |\n| --- | --- |\n| 输出图像 | 采样Sample图 |",
            ),
            (
                "false-split fence merge (c + m4)",
                "```c\ntypedef struct {\n    int a;\n} Foo;\n```\n\n```m4\nvoid bar(void)\n{\n    int b;\n}\n```\n",
            ),
            (
                "txt fence with CJK prose unwrap",
                "```txt\n这里是一段被困住的说明。它有句号。\n```\n",
            ),
            (
                "C-code reindent",
                "```c\nvoid f(void)\n{\nint x;\nif (x) {\nx++;\n}\n}\n```\n",
            ),
            (
                "txt fence with C signature preserved",
                "```txt\nXcamReturn rkAiqExpParamComb(const XcamParamComb_t *combp);\n```\n",
            ),
        ],
    )
    def test_parametrized_idempotent(self, description, raw):
        out1 = polish.process(raw)
        out2 = polish.process(out1)
        assert out2 == out1, (
            f"Not idempotent for: {description!r}\n--- pass1 ---\n{out1}\n--- pass2 ---\n{out2}"
        )


class TestFinalization:
    def test_finalize_promotes_polished_and_backs_up_original(self, tmp_path):
        source = tmp_path / "paper.md"
        polished = tmp_path / "paper-polished.md"
        source.write_text("raw", encoding="utf-8")
        polished.write_text("clean", encoding="utf-8")

        final_path, origin_path = polish.finalize_files(source)

        assert final_path.read_text(encoding="utf-8") == "clean"
        assert origin_path.read_text(encoding="utf-8") == "raw"
        assert not polished.exists()

    def test_finalize_refuses_existing_backup(self, tmp_path):
        source = tmp_path / "paper.md"
        polished = tmp_path / "paper-polished.md"
        origin = tmp_path / "paper.origin.md"
        source.write_text("raw", encoding="utf-8")
        polished.write_text("clean", encoding="utf-8")
        origin.write_text("older", encoding="utf-8")

        with pytest.raises(FileExistsError):
            polish.finalize_files(source)

        assert source.read_text(encoding="utf-8") == "raw"
        assert polished.read_text(encoding="utf-8") == "clean"


# ── HTML table conversion ───────────────────────────────────────────────────


class TestHtmlTableConversion:
    def test_multi_column_conversion(self):
        html = (
            "<table><tr><td>参数名</td><td>类型</td><td>描述</td></tr>"
            "<tr><td>outFrame</td><td>frame</td><td>输出图像,即</td></tr></table>"
        )
        out = polish.process(html)
        lines = out.split("\n")
        assert lines[0] == "| 参数名 | 类型 | 描述 |"
        assert lines[1] == "| --- | --- | --- |"
        assert lines[2] == "| outFrame | frame | 输出图像,即 |"

    def test_entity_unescape(self):
        html = "<table><tr><td>a&amp;b</td><td>&lt;x&gt;</td></tr></table>"
        out = polish.process(html)
        assert "| a&b | <x> |" in out

    def test_ragged_rows_padded(self):
        html = "<table><tr><td>a</td><td>b</td><td>c</td></tr><tr><td>only</td></tr></table>"
        out = polish.process(html)
        lines = out.split("\n")
        assert lines[2] == "| only |  |  |"

    def test_pipe_in_cell_escaped(self):
        html = "<table><tr><td>a|b</td><td>c</td></tr></table>"
        out = polish.process(html)
        assert "| a\\|b | c |" in out

    def test_cjk_spacing_in_cells(self):
        html = "<table><tr><td>使用Python编程</td><td>x</td></tr></table>"
        out = polish.process(html)
        assert "| 使用 Python 编程 | x |" in out

    def test_rowspan_aborts_conversion(self):
        html = '<table><tr><td rowspan="2">a</td><td>b</td></tr><tr><td>c</td></tr></table>'
        out = polish.process(html)
        assert "<table>" in out

    def test_empty_table_preserved(self):
        html = "<table></table>"
        out = polish.process(html)
        assert "<table>" in out

    def test_surrounding_text_preserved(self):
        html = "before <table><tr><td>a</td></tr></table> after"
        out = polish.process(html)
        assert "before" in out and "after" in out

    def test_bare_tr_with_surrounding_text_preserved(self):
        cases = (
            ("before <tr><td>a</td><td>b</td></tr> after", ("before", "after")),
            ("<tr><td>a</td><td>b</td></tr> after", ("after",)),
            ("before <tr><td>a</td><td>b</td></tr>", ("before",)),
        )
        for html, present in cases:
            out = polish.process(html)
            for word in present:
                assert word in out, html

    def test_blank_line_inside_table_not_split(self):
        html = "<table>\n<tr><td>a</td></tr>\n\n<tr><td>b</td></tr>\n</table>"
        out = polish.process(html)
        assert out.count("| --- |") == 1

    def test_unclosed_table_does_not_absorb_tail(self):
        # An unclosed <table> must stop at the blank line: swallowing the
        # tail would leave it unpolished and invisible to check/headings.
        doc = "<table>\n<tr><td>a</td></tr>\n\nTail paragraph.\n"
        blocks = polish.parse_blocks(doc)
        kinds = [(b.kind, b.end_line) for b in blocks]
        assert ("html_table", 2) in kinds
        assert any(b.kind == "paragraph" and "Tail" in b.lines[0] for b in blocks)

    def test_unclosed_table_before_prose_and_later_table(self):
        # A later unrelated </table> must not pull prose into this block.
        # First table is unclosed -> preserved per degrade rule; second
        # converts; prose survives between them.
        doc = "<table>\n<tr><td>a</td></tr>\n\nIMPORTANT prose.\n\n<table><tr><td>b</td></tr></table>\n"
        out = polish.process(doc)
        assert "IMPORTANT prose." in out
        assert "<table>" in out
        assert "| b |" in out
        assert out.count("| --- |") == 1

    def test_unclosed_table_before_prose_and_stray_close(self):
        doc = "<table>\n<tr><td>a</td></tr>\n\nIMPORTANT prose.\n\n</table>\n"
        out = polish.process(doc)
        assert "IMPORTANT prose." in out

    def test_out_of_range_entity_kept(self):
        html = "<table><tr><td>&#x110000;</td></tr></table>"
        out = polish.process(html)
        assert "&#x110000;" in out

    def test_surrogate_entity_kept(self):
        # A lone surrogate would survive chr() but crash UTF-8 encoding later.
        html = "<table><tr><td>&#xD800;</td></tr></table>"
        out = polish.process(html)
        assert "&#xD800;" in out
        out.encode("utf-8")  # must not raise

    def test_control_entity_kept_idempotent(self):
        # &#0; would inject a NUL, colliding with the inline-span sentinel.
        html = "<table><tr><td>A&#0;B</td><td>x</td></tr></table>"
        out = polish.process(html)
        assert "&#0;" in out
        assert polish.process(out) == out


# ── Pipe table CJK spacing ──────────────────────────────────────────────────


class TestTableCjkSpacing:
    def test_cell_spacing_inserted(self):
        table = "| 参数名 | 描述 |\n| --- | --- |\n| 使用Python | 采样Sample图 |"
        out = polish.process(table)
        assert "| 使用 Python | 采样 Sample 图 |" in out

    def test_align_row_untouched(self):
        table = "| a | b |\n| --- | --- |\n| 1 | 2 |"
        assert polish.process(table) == table + "\n"

    def test_inline_code_protected(self):
        table = "| 代码 | 说明 |\n| --- | --- |\n| `使用Python` | 正常 |"
        out = polish.process(table)
        assert "| `使用Python` |" in out

    def test_halfwidth_comma_kept_in_cells(self):
        table = "| 范围 | 说明 |\n| --- | --- |\n| [0x0, 0x3ff] | 地址范围 |"
        out = polish.process(table)
        assert "[0x0, 0x3ff]" in out


# ── Code fence repair ───────────────────────────────────────────────────────


class TestFenceRepair:
    def test_merge_same_lang_split(self):
        raw = "```c\nint a;\n```\n\n```c\nint b;\n```\n"
        out = polish.process(raw)
        assert out.count("```") == 2
        assert "int a;" in out and "int b;" in out

    def test_merge_c_and_m4(self):
        raw = "```c\nint a;\n```\n\n```m4\nint b;\n```\n"
        out = polish.process(raw)
        assert out.count("```") == 2
        assert out.startswith("```c")

    def test_incompatible_langs_not_merged(self):
        raw = "```c\nint a;\n```\n\n```python\nx = 1\n```\n"
        out = polish.process(raw)
        assert out.count("```") == 4
        assert "```python" in out

    def test_fence_with_prose_between_not_merged(self):
        raw = "```c\nint a;\n```\n\nSome text.\n\n```c\nint b;\n```\n"
        out = polish.process(raw)
        assert out.count("```") == 4

    def test_m4_with_c_content_sniffed(self):
        raw = "```m4\ntypedef struct {\n    int a;\n} Foo;\n```\n"
        out = polish.process(raw)
        assert out.startswith("```c\n")

    def test_rust_with_c_content_sniffed(self):
        raw = "```rust\n#include <stdio.h>\n```\n"
        out = polish.process(raw)
        assert out.startswith("```c\n")

    def test_txt_fence_with_cjk_prose_unwrapped(self):
        raw = "```txt\n这里是一段被困住的说明文字。它包含句号。\n```\n"
        out = polish.process(raw)
        assert "```" not in out
        assert "这里是一段被困住的说明文字。" in out

    def test_txt_fence_with_c_signature_kept(self):
        raw = "```txt\nXcamReturn rkAiqExpParamComb(const XcamParamComb_t *combp);\n```\n"
        out = polish.process(raw)
        assert out.startswith("```txt\n")

    def test_c_fence_never_unwrapped(self):
        raw = "```c\n// 中文注释。带句号\nint a;\n```\n"
        out = polish.process(raw)
        assert out.startswith("```c\n")


# ── Code reindent ───────────────────────────────────────────────────────────


class TestReindent:
    def test_balanced_struct_reindented(self):
        raw = "```c\ntypedef struct {\nint a;\nint b;\n} Foo;\n```\n"
        out = polish.process(raw)
        assert "    int a;" in out
        assert "    int b;" in out

    def test_nested_braces(self):
        raw = "```c\nvoid f(void)\n{\nint x;\nif (x) {\nx++;\n}\n}\n```\n"
        out = polish.process(raw)
        assert "    int x;" in out
        assert "        x++;" in out

    def test_unbalanced_preserved(self):
        raw = "```c\nvoid f(void)\n{\nint x;\n```\n"
        out = polish.process(raw)
        assert "int x;" in out.split("\n")[3]

    def test_preprocessor_directive_at_col0(self):
        raw = "```c\n#include <stdio.h>\ntypedef struct {\nint a;\n} Foo;\n```\n"
        out = polish.process(raw)
        assert "#include <stdio.h>" in out
        assert "    int a;" in out

    def test_non_c_lang_untouched(self):
        raw = "```python\ndef f():\n    return 1\n```\n"
        out = polish.process(raw)
        assert "    return 1;" not in out  # no semicolon added; content passthrough
        assert "    return 1" in out


# ── Lost-heading restore ────────────────────────────────────────────────────


class TestHeadingRestore:
    def test_plain_numbered_title_detected(self):
        text = "# 11.5 Structs\n\nintro\n\n11.5.2.1.2 RkAiqExpParamComb_t\n"
        out = polish.extract_headings(text)
        assert "RkAiqExpParamComb_t (plain)" in out

    def test_txt_fence_numbered_title_detected(self):
        text = "# 11.5 Structs\n\n```txt\n11.5.2.1.2 RkAiqExpParamComb_t\n```\n"
        out = polish.extract_headings(text)
        assert "RkAiqExpParamComb_t (txt-fence)" in out

    def test_decimal_not_flagged(self):
        text = "The value is 3.14 is pi constant.\n"
        out = polish.extract_headings(text)
        assert "pi" not in out

    def test_lost_headings_in_line_order(self):
        text = "# 11.5 Structs\n\n11.5.1 Intro\n\n## Real Section\n\n11.5.2.1.2 Lost_t\n"
        out = polish.extract_headings(text)
        lines = out.split("\n")
        assert [ln.split()[2] for ln in lines] == ["#", "?", "##", "?"]
        assert "Lost_t" in lines[3] and "(plain)" in lines[3]

    def test_promote_plain_line(self):
        text = "# T\n\n11.5.2.1.2 RkAiqExpParamComb_t\n\nbody\n"
        out = polish.apply_headings(text, {3: "######"})
        assert "###### 11.5.2.1.2 RkAiqExpParamComb_t" in out

    def test_promote_inside_txt_fence_unwraps(self):
        text = "# T\n\n```txt\n11.5.2.1.2 Foo\n```\n\nbody\n"
        out = polish.apply_headings(text, {4: "######"})
        assert "```" not in out
        assert "###### 11.5.2.1.2 Foo" in out

    def test_promote_inside_c_fence_refused(self, capsys):
        text = "# T\n\n```c\n11.5.2.1.2 Foo\n```\n"
        out = polish.apply_headings(text, {4: "######"})
        assert "```c" in out
        assert "######" not in out
        assert "refusing" in capsys.readouterr().err

    def test_demote_heading_to_plain(self):
        text = "## 【成员】\n\ncontent\n"
        out = polish.apply_headings(text, {1: "-"})
        assert out.startswith("【成员】")

    def test_demote_keeps_blockquote_prefix(self):
        text = "> ## Title\n> body\n"
        out = polish.apply_headings(text, {1: "-"})
        assert out.startswith("> Title")

    def test_multiple_ops_with_fence_removal(self):
        text = "# T\n\n```txt\n11.5.2.1.2 Foo\n```\n\n## 【成员】\n\nbody\n"
        out = polish.apply_headings(text, {4: "######", 7: "-"})
        assert "###### 11.5.2.1.2 Foo" in out
        assert "【成员】" in out
        assert "## 【成员】" not in out
        assert "```" not in out


# ── check subcommand ────────────────────────────────────────────────────────


class TestCheckRules:
    def test_cjk_adjacency_flagged(self):
        issues = polish.check_file("使用Python编程。\n")
        assert any("[cjk]" in i for i in issues)

    def test_cjk_spacing_clean(self):
        issues = polish.check_file("使用 Python 编程。\n")
        assert not any("[cjk]" in i for i in issues)

    def test_halfwidth_punct_flagged_in_prose(self):
        issues = polish.check_file("输出图像,即采样图。\n")
        assert any("[punct]" in i for i in issues)

    def test_halfwidth_punct_ok_in_table_cells(self):
        table = "| 范围 | 说明 |\n| --- | --- |\n| [0x0, 0x3ff] | 地址范围 |"
        assert not any("[punct]" in i for i in polish.check_file(table))

    def test_unbalanced_fences(self):
        issues = polish.check_file("```c\nint a;\n")
        assert any("[fence]" in i and "unclosed" in i for i in issues)

    def test_c_code_in_txt_fence(self):
        issues = polish.check_file("```txt\ntypedef struct {\n    int a;\n} Foo;\n```\n")
        assert any("[fence]" in i for i in issues)

    def test_fence_split_flagged(self):
        raw = "```c\nint a;\n```\n\n```c\nint b;\n```\n"
        issues = polish.check_file(raw)
        assert any("[fence-split]" in i for i in issues)

    def test_ragged_pipe_table(self):
        raw = "| a | b |\n| --- | --- |\n| 1 | 2 | 3 |"
        issues = polish.check_file(raw)
        assert any("[table]" in i and "escaped" in i for i in issues)

    def test_residual_html_table(self):
        issues = polish.check_file("<table><tr><td>a</td></tr></table>\n")
        assert any("[table]" in i and "residual" in i for i in issues)

    def test_lost_heading_flagged(self):
        text = "# 11.5 Structs\n\n11.5.2.1.2 Foo_t\n"
        issues = polish.check_file(text)
        assert any("[heading]" in i for i in issues)

    def test_unbalanced_math(self):
        issues = polish.check_file("$$\nx + y\n")
        assert any("[math]" in i for i in issues)

    def test_detached_caption(self):
        issues = polish.check_file("![img](x.jpg)\n\n图 AWB 分块示意图\n")
        assert any("[caption]" in i for i in issues)

    def test_trailing_whitespace(self):
        issues = polish.check_file("text with space   \n")
        assert any("[space]" in i for i in issues)

    def test_ligature_residual(self):
        issues = polish.check_file("E\ufb00cient method\n")
        assert any("[ocr]" in i for i in issues)

    def test_clean_polished_doc_no_cjk_punct_issues(self):
        polished_text = polish.process("# T\n\n使用 Python 编程，很好。\n")
        assert not any("[cjk]" in i for i in polish.check_file(polished_text))

    def test_check_is_report_only(self):
        text = "使用Python。\n"
        polish.check_file(text)
        assert text == "使用Python。\n"

    def test_duplicated_punct_flagged(self):
        issues = polish.check_file("这句话很好。。下一句\n")
        assert any("[punct]" in i and "duplicated" in i for i in issues)

    def test_duplicated_ascii_punct_flagged(self):
        for text in ("Wow!!\n", "a;;b\n", "x??\n"):
            issues = polish.check_file(text)
            assert any("[punct]" in i and "duplicated" in i for i in issues), text

    def test_double_dot_not_flagged(self):
        # "." is deliberately outside the ASCII dup-punct class (decimal numbers).
        assert not any("duplicated" in i for i in polish.check_file("End..\n"))

    def test_unbalanced_quotes_flagged(self):
        issues = polish.check_file("他说“hello world。\n")
        assert any("[punct]" in i and "quotes" in i for i in issues)

    def test_inline_code_not_flagged_as_double_space(self):
        issues = polish.check_file("使用 `inline code` 编程，正常。\n")
        assert not any("[space]" in i for i in issues)

    def test_inline_code_cjk_adjacency_not_flagged(self):
        issues = polish.check_file("使用 `code`正常结束。\n")
        assert not any("[cjk]" in i for i in issues)

    def test_nested_list_indent_not_flagged(self):
        issues = polish.check_file("- outer\n  - inner\n")
        assert not any("[space]" in i for i in issues)

    def test_indented_paragraph_not_flagged(self):
        issues = polish.check_file("    indented paragraph\n")
        assert not any("[space]" in i for i in issues)

    def test_mid_line_double_space_flagged(self):
        issues = polish.check_file("word  word\n")
        assert any("[space]" in i and "consecutive" in i for i in issues)

    def test_sample_output_passes_space_check(self):
        sample = Path(__file__).parent / "examples" / "sample_output.md"
        issues = polish.check_file(sample.read_text())
        assert not any("[space]" in i and "consecutive" in i for i in issues)

    def test_inline_code_punct_not_flagged(self):
        issues = polish.check_file("run `cmd!!` now\n")
        assert not any("duplicated" in i for i in issues)

    def test_inline_code_unbalanced_quotes_not_flagged(self):
        issues = polish.check_file("see `“x` ok\n")
        assert not any("quotes" in i for i in issues)

    def test_borderless_multi_column_not_single(self):
        raw = "a | b | c\n--- | --- | ---\n1 | 2 | 3\n"
        assert not any("single-column" in i for i in polish.check_file(raw))

    def test_single_column_bordered_flagged(self):
        raw = "| a |\n| --- |\n| b |\n"
        assert any("[table]" in i and "single-column" in i for i in polish.check_file(raw))
