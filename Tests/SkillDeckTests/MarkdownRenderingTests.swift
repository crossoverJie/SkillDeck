import XCTest
import Markdown
@testable import SkillDeck

/// Unit tests for the SwiftUIMarkdownVisitor — the AST visitor that converts Markdown nodes to SwiftUI views
///
/// Since SwiftUI views cannot be directly introspected in unit tests (they require a running app),
/// these tests focus on:
/// 1. **Parsing correctness**: Verify swift-markdown parses content into expected AST structure
/// 2. **Visitor completeness**: Verify the visitor handles all common node types without crashing
/// 3. **Inline text building**: Verify the inline text concatenation logic
///
/// Visual rendering (fonts, colors, layout) requires manual verification — documented in the PR description.
///
/// XCTest is Swift's testing framework (similar to JUnit). Test classes extend XCTestCase.
final class MarkdownRenderingTests: XCTestCase {

    // MARK: - Parsing Tests

    /// Test that swift-markdown parses a heading into a Heading node
    ///
    /// `Document(parsing:)` creates an AST from a markdown string.
    /// `children` returns the top-level block elements.
    /// We verify the first child is a `Heading` with the correct level.
    func testParseHeading() {
        let doc = Document(parsing: "# Hello World")
        let children = Array(doc.children)

        XCTAssertEqual(children.count, 1)
        // `as?` conditional cast — tests if the child is a Heading type
        let heading = children[0] as? Heading
        XCTAssertNotNil(heading)
        XCTAssertEqual(heading?.level, 1)
    }

    /// Test that H2 heading is parsed correctly
    func testParseH2Heading() {
        let doc = Document(parsing: "## Section Title")
        let children = Array(doc.children)

        XCTAssertEqual(children.count, 1)
        let heading = children[0] as? Heading
        XCTAssertNotNil(heading)
        XCTAssertEqual(heading?.level, 2)
    }

    /// Test that a paragraph with plain text is parsed correctly
    func testParseParagraph() {
        let doc = Document(parsing: "This is a paragraph.")
        let children = Array(doc.children)

        XCTAssertEqual(children.count, 1)
        XCTAssertNotNil(children[0] as? Paragraph)
    }

    /// Test that bold text inside a paragraph creates a Strong node
    func testParseBoldText() {
        let doc = Document(parsing: "This has **bold** text.")
        let children = Array(doc.children)

        // The paragraph should contain inline children including a Strong node
        guard let paragraph = children[0] as? Paragraph else {
            XCTFail("Expected Paragraph")
            return
        }

        // Check that at least one child is a Strong node
        let hasStrong = paragraph.children.contains { $0 is Strong }
        XCTAssertTrue(hasStrong, "Expected a Strong (bold) node in the paragraph")
    }

    /// Test that italic text inside a paragraph creates an Emphasis node
    func testParseItalicText() {
        let doc = Document(parsing: "This has *italic* text.")
        let children = Array(doc.children)

        guard let paragraph = children[0] as? Paragraph else {
            XCTFail("Expected Paragraph")
            return
        }

        let hasEmphasis = paragraph.children.contains { $0 is Emphasis }
        XCTAssertTrue(hasEmphasis, "Expected an Emphasis (italic) node in the paragraph")
    }

    /// Test that inline code creates an InlineCode node
    func testParseInlineCode() {
        let doc = Document(parsing: "Use `console.log()` for debugging.")
        let children = Array(doc.children)

        guard let paragraph = children[0] as? Paragraph else {
            XCTFail("Expected Paragraph")
            return
        }

        let hasInlineCode = paragraph.children.contains { $0 is InlineCode }
        XCTAssertTrue(hasInlineCode, "Expected an InlineCode node in the paragraph")
    }

    /// Test that fenced code blocks are parsed correctly
    func testParseCodeBlock() {
        let markdown = """
        ```python
        print("hello")
        ```
        """
        let doc = Document(parsing: markdown)
        let children = Array(doc.children)

        XCTAssertEqual(children.count, 1)
        let codeBlock = children[0] as? CodeBlock
        XCTAssertNotNil(codeBlock)
        XCTAssertEqual(codeBlock?.language, "python")
        XCTAssertTrue(codeBlock?.code.contains("print") ?? false)
    }

    /// Test that an unordered list is parsed correctly
    func testParseUnorderedList() {
        let markdown = """
        - Item 1
        - Item 2
        - Item 3
        """
        let doc = Document(parsing: markdown)
        let children = Array(doc.children)

        XCTAssertEqual(children.count, 1)
        let list = children[0] as? UnorderedList
        XCTAssertNotNil(list)
        XCTAssertEqual(list?.childCount, 3)
    }

    /// Test that an ordered list is parsed correctly
    func testParseOrderedList() {
        let markdown = """
        1. First
        2. Second
        3. Third
        """
        let doc = Document(parsing: markdown)
        let children = Array(doc.children)

        XCTAssertEqual(children.count, 1)
        let list = children[0] as? OrderedList
        XCTAssertNotNil(list)
        XCTAssertEqual(list?.childCount, 3)
    }

    /// Test that blockquotes are parsed correctly
    func testParseBlockQuote() {
        let markdown = "> This is a quote"
        let doc = Document(parsing: markdown)
        let children = Array(doc.children)

        XCTAssertEqual(children.count, 1)
        XCTAssertNotNil(children[0] as? BlockQuote)
    }

    /// Test that thematic breaks (---) are parsed correctly
    func testParseThematicBreak() {
        let markdown = """
        Above

        ---

        Below
        """
        let doc = Document(parsing: markdown)
        let children = Array(doc.children)

        // Should be: Paragraph, ThematicBreak, Paragraph
        XCTAssertEqual(children.count, 3)
        XCTAssertNotNil(children[1] as? ThematicBreak)
    }

    /// Test that links are parsed correctly
    func testParseLink() {
        let doc = Document(parsing: "Visit [GitHub](https://github.com) for code.")
        let children = Array(doc.children)

        guard let paragraph = children[0] as? Paragraph else {
            XCTFail("Expected Paragraph")
            return
        }

        let hasLink = paragraph.children.contains { $0 is Markdown.Link }
        XCTAssertTrue(hasLink, "Expected a Link node in the paragraph")
    }

    // MARK: - Table Tests

    /// Test that a markdown table is parsed into a Table AST node
    func testParseTable() {
        let markdown = """
        | Name | Type | Description |
        | --- | --- | --- |
        | width | number | Video width |
        | height | number | Video height |
        """
        let doc = Document(parsing: markdown)
        let children = Array(doc.children)

        XCTAssertEqual(children.count, 1)
        let table = children[0] as? Markdown.Table
        XCTAssertNotNil(table, "Expected a Table node")
        // Table should have 2 body rows
        // `Array(table.body.rows)` converts the lazy sequence to an array for counting
        XCTAssertEqual(table.map { Array($0.body.rows).count }, 2)
    }

    /// Test that the visitor handles a table without crashing and produces a view
    func testVisitorTable() {
        let markdown = """
        | Parameter | Type | Required | Default | Description |
        | --- | --- | --- | --- | --- |
        | code | string | Yes | - | React/Remotion code |
        | width | number | No | 1920 | Video width |
        | height | number | No | 1080 | Video height |
        """
        let doc = Document(parsing: markdown)
        var visitor = SwiftUIMarkdownVisitor()

        for child in doc.children {
            let result = visitor.visit(child)
            XCTAssertNotNil(result)
        }
    }

    /// Test that a table with column alignment is parsed correctly
    func testParseTableWithAlignment() {
        let markdown = """
        | Left | Center | Right |
        | :--- | :---: | ---: |
        | a | b | c |
        """
        let doc = Document(parsing: markdown)
        let table = doc.children.first(where: { $0 is Markdown.Table }) as? Markdown.Table
        XCTAssertNotNil(table)

        // Verify column alignments are parsed
        let alignments = table?.columnAlignments
        XCTAssertEqual(alignments?.count, 3)
        XCTAssertEqual(alignments?[0], .left)
        XCTAssertEqual(alignments?[1], .center)
        XCTAssertEqual(alignments?[2], .right)
    }

    // MARK: - Visitor No-Crash Tests

    /// Test that the visitor handles empty markdown without crashing
    ///
    /// Edge case: empty string should produce an empty document with no children.
    func testVisitorEmptyMarkdown() {
        let doc = Document(parsing: "")
        var visitor = SwiftUIMarkdownVisitor()

        // Should not crash — just produces no output
        for child in doc.children {
            let _ = visitor.visit(child)
        }
    }

    /// Test that the visitor handles a complex document without crashing
    ///
    /// This exercises multiple node types in a single document to verify
    /// the visitor doesn't crash on any combination of elements.
    func testVisitorComplexDocument() {
        let markdown = """
        # Main Title

        This is a paragraph with **bold**, *italic*, and `inline code`.

        ## Section 2

        - List item 1
        - List item 2
          - Nested item

        > A blockquote with some text

        ```swift
        let x = 42
        print(x)
        ```

        1. Ordered item 1
        2. Ordered item 2

        ---

        Visit [our docs](https://example.com) for more info.

        ~~strikethrough text~~
        """
        let doc = Document(parsing: markdown)
        var visitor = SwiftUIMarkdownVisitor()

        // Walk all top-level children — none should crash the visitor
        for child in doc.children {
            let result = visitor.visit(child)
            // Verify each visit produces a non-nil view (AnyView is never nil by construction)
            XCTAssertNotNil(result)
        }
    }

    /// Test that the visitor handles unknown/rare node types via defaultVisit
    ///
    /// HTML blocks are not commonly rendered in SwiftUI but should not crash.
    func testVisitorHTMLBlock() {
        let markdown = """
        <div>
        Some HTML content
        </div>
        """
        let doc = Document(parsing: markdown)
        var visitor = SwiftUIMarkdownVisitor()

        for child in doc.children {
            let result = visitor.visit(child)
            XCTAssertNotNil(result)
        }
    }

    // MARK: - Inline Text Building Tests

    /// Test that a simple paragraph produces the expected plain text output
    ///
    /// We verify via the AST structure that the paragraph's children match expectations.
    func testInlineTextPlain() {
        let doc = Document(parsing: "Hello world")
        guard let paragraph = doc.children.first(where: { $0 is Paragraph }) as? Paragraph else {
            XCTFail("Expected Paragraph")
            return
        }

        // Should have one Text child containing "Hello world"
        let textChildren = paragraph.children.compactMap { $0 as? Markdown.Text }
        XCTAssertEqual(textChildren.count, 1)
        XCTAssertEqual(textChildren[0].string, "Hello world")
    }

    /// Test that mixed inline formatting produces the correct AST structure
    ///
    /// "Hello **bold** and *italic*" should produce:
    /// Text("Hello ") + Strong(Text("bold")) + Text(" and ") + Emphasis(Text("italic"))
    func testInlineTextMixed() {
        let doc = Document(parsing: "Hello **bold** and *italic*")
        guard let paragraph = doc.children.first(where: { $0 is Paragraph }) as? Paragraph else {
            XCTFail("Expected Paragraph")
            return
        }

        let childTypes = paragraph.children.map { type(of: $0) }
        // Should contain: Text, Strong, Text, Emphasis
        XCTAssertTrue(childTypes.count >= 4, "Expected at least 4 inline children, got \(childTypes.count)")
    }

    /// Test that code blocks with no language specified are handled correctly
    func testCodeBlockNoLanguage() {
        let markdown = """
        ```
        plain code
        ```
        """
        let doc = Document(parsing: markdown)
        let codeBlock = doc.children.first(where: { $0 is CodeBlock }) as? CodeBlock
        XCTAssertNotNil(codeBlock)
        // Language should be nil or empty when not specified
        XCTAssertTrue(codeBlock?.language == nil || codeBlock?.language?.isEmpty == true)
    }
}

// MARK: - Internal Access Helper

/// Re-export SwiftUIMarkdownVisitor for testing
///
/// The visitor is `private` in MarkdownContentView.swift, but we still want to test it.
/// Since `@testable import SkillDeck` upgrades `internal` to accessible but not `private`,
/// we create a thin test-only wrapper that exercises the visitor through MarkdownNodeView.
///
/// Note: If the visitor were `internal` instead of `private`, we could test it directly.
/// For now, we test it indirectly through the AST parsing + visitor.visit() calls.
/// The `SwiftUIMarkdownVisitor` struct is re-created in tests to exercise its logic.
extension MarkdownRenderingTests {

    /// Helper: verify that visiting a specific markdown string doesn't crash
    /// and produces a result for every top-level node
    func assertMarkdownRendersWithoutCrash(_ markdown: String, file: StaticString = #file, line: UInt = #line) {
        let doc = Document(parsing: markdown)
        var visitor = SwiftUIMarkdownVisitor()

        for child in doc.children {
            let result = visitor.visit(child)
            XCTAssertNotNil(result, "Visitor returned nil for node type: \(type(of: child))", file: file, line: line)
        }
    }
}
