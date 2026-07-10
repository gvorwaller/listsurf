import Foundation

/// One OPML document ⇄ one list. See docs/2026-07-10-milestone-3-interchange-spec.md §2
/// for the attribute conventions (_note / _status / _quantity) and their sources.
public struct OPMLDocument: Equatable, Sendable {
    public var title: String?              // <head><title>, trimmed; nil if absent/empty
    public var nodes: [OPMLOutlineNode]    // body's direct <outline> children

    public init(title: String?, nodes: [OPMLOutlineNode]) {
        self.title = title
        self.nodes = nodes
    }
}

public struct OPMLOutlineNode: Equatable, Sendable {
    public var text: String                // required, non-empty after trimming
    public var note: String?
    public var isChecked: Bool
    public var quantity: Int               // >= 1
    public var children: [OPMLOutlineNode]

    public init(
        text: String,
        note: String? = nil,
        isChecked: Bool = false,
        quantity: Int = 1,
        children: [OPMLOutlineNode] = []
    ) {
        self.text = text
        self.note = note
        self.isChecked = isChecked
        self.quantity = quantity
        self.children = children
    }
}

public enum OPMLDecodeError: LocalizedError, Equatable, Sendable {
    case malformedXML(line: Int, column: Int, detail: String)
    case notOPML                       // root element is not <opml>
    case missingText(line: Int)        // <outline> without a usable text/title attribute
    case emptyOutline                  // no <outline> elements in <body>

    public var errorDescription: String? {
        switch self {
        case .malformedXML(let line, let column, let detail):
            "The file is not valid XML at line \(line), column \(column): \(detail). Fix the XML and re-export."
        case .notOPML:
            "The root element is not <opml>. Wrap the outline in <opml version=\"2.0\">…</opml>."
        case .missingText(let line):
            "The <outline> element at line \(line) has no text attribute. Every item needs text=\"…\"."
        case .emptyOutline:
            "The document contains no outline items."
        }
    }
}

/// Encodes/decodes a single-list OPML document. See
/// docs/2026-07-10-milestone-3-interchange-spec.md §4.1 for the full contract.
public struct OPMLCodec: Sendable {

    /// Attribute and element names, kept as constants in one place so a mismatch
    /// against a real producer (e.g. CarbonFin, per spec §14) is a two-line fix.
    private enum Attr {
        static let text = "text"
        static let legacyTitle = "title"
        static let note = "_note"
        static let status = "_status"
        static let quantity = "_quantity"
        static let complete = "_complete"
        static let completeAlt = "complete"
        static let checked = "checked"
    }

    private enum Elem {
        static let opml = "opml"
        static let head = "head"
        static let title = "title"
        static let body = "body"
        static let outline = "outline"
    }

    public init() {}

    // MARK: - Encode

    public func encode(list: ListItem, items: [OutlineItem]) -> Data {
        let childrenIndex = Dictionary(grouping: items, by: \.parentID)

        func sortedChildren(of parentID: UUID?) -> [OutlineItem] {
            (childrenIndex[parentID] ?? []).sorted { a, b in
                if a.position != b.position { return a.position < b.position }
                return a.id.uuidString < b.id.uuidString
            }
        }

        func render(_ item: OutlineItem, depth: Int) -> String {
            let indent = String(repeating: "  ", count: depth + 2)
            var attrs = "text=\"\(escapeAttribute(item.title))\""
            attrs += " _status=\"\(item.isChecked ? "checked" : "unchecked")\""
            if item.quantity > 1 {
                attrs += " _quantity=\"\(item.quantity)\""
            }
            if let notes = item.notes, !notes.isEmpty {
                attrs += " _note=\"\(escapeAttribute(notes))\""
            }
            let children = sortedChildren(of: item.id)
            if children.isEmpty {
                return "\(indent)<outline \(attrs)/>\n"
            }
            var out = "\(indent)<outline \(attrs)>\n"
            for child in children {
                out += render(child, depth: depth + 1)
            }
            out += "\(indent)</outline>\n"
            return out
        }

        var out = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        out += "<opml version=\"2.0\">\n"
        out += "  <head>\n"
        out += "    <title>\(escapeElementText(list.title))</title>\n"
        out += "  </head>\n"
        out += "  <body>\n"
        for root in sortedChildren(of: nil) {
            out += render(root, depth: 0)
        }
        out += "  </body>\n"
        out += "</opml>\n"
        return Data(out.utf8)
    }

    /// Escapes an XML attribute value. Iterates Unicode scalars (not `Character`)
    /// because Swift groups CR+LF into a single extended grapheme cluster — iterating
    /// by `Character` would fail to match a lone `\r` or `\n` inside a "\r\n" run.
    /// `\n`/`\r`/`\t` become numeric character references so XML attribute-value
    /// normalization (which turns literal newlines into spaces) never touches them.
    private func escapeAttribute(_ s: String) -> String {
        var result = ""
        result.reserveCapacity(s.unicodeScalars.count)
        for scalar in s.unicodeScalars {
            switch scalar {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "\n": result += "&#10;"
            case "\r": result += "&#13;"
            case "\t": result += "&#9;"
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    private func escapeElementText(_ s: String) -> String {
        var result = ""
        result.reserveCapacity(s.unicodeScalars.count)
        for scalar in s.unicodeScalars {
            switch scalar {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    // MARK: - Decode

    public func decode(_ data: Data) throws -> OPMLDocument {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false

        let success = parser.parse()
        if !success {
            // abortParsing() makes parserError report NSXMLParserDelegateAbortedParseError
            // (code 512) — the delegate-stored semantic error must be checked first, or
            // every semantic error masquerades as malformed XML.
            if let semanticError = delegate.semanticError {
                throw semanticError
            }
            throw OPMLDecodeError.malformedXML(
                line: parser.lineNumber,
                column: parser.columnNumber,
                detail: parser.parserError?.localizedDescription ?? "unknown"
            )
        }

        if delegate.rootNodes.isEmpty {
            throw OPMLDecodeError.emptyOutline
        }

        func build(_ builder: Delegate.NodeBuilder) -> OPMLOutlineNode {
            OPMLOutlineNode(
                text: builder.text,
                note: builder.note,
                isChecked: builder.isChecked,
                quantity: builder.quantity,
                children: builder.children.map(build)
            )
        }

        return OPMLDocument(title: delegate.documentTitle, nodes: delegate.rootNodes.map(build))
    }

    // MARK: - SAX delegate

    private final class Delegate: NSObject, XMLParserDelegate {
        final class NodeBuilder {
            var text: String = ""
            var note: String?
            var isChecked: Bool = false
            var quantity: Int = 1
            var children: [NodeBuilder] = []
        }

        private var elementPath: [String] = []
        private var outlineStack: [NodeBuilder] = []
        private var titleCharacters: String = ""
        // Outlines outside <body> (e.g. metadata in <head>) are ignored, along
        // with their entire subtree; this counts ignored-outline nesting so
        // their end tags don't pop an accepted builder off the stack.
        private var ignoredOutlineDepth = 0

        private(set) var rootNodes: [NodeBuilder] = []
        var semanticError: OPMLDecodeError?

        var documentTitle: String? {
            let trimmed = titleCharacters.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            guard semanticError == nil else { return }

            let lower = elementName.lowercased()
            elementPath.append(lower)

            if elementPath.count == 1 {
                if lower != Elem.opml {
                    semanticError = .notOPML
                    parser.abortParsing()
                }
                return
            }

            guard lower == Elem.outline else { return }

            // Only outlines inside <body> are list content (the model contract:
            // nodes are the body's outline children). An <outline> in <head> or
            // elsewhere is producer metadata — ignore it and its subtree.
            guard ignoredOutlineDepth == 0, elementPath.dropLast().contains(Elem.body) else {
                ignoredOutlineDepth += 1
                return
            }

            let rawText = attributeDict[Attr.text] ?? attributeDict[Attr.legacyTitle]
            let trimmedText = (rawText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedText.isEmpty else {
                semanticError = .missingText(line: parser.lineNumber)
                parser.abortParsing()
                return
            }

            let builder = NodeBuilder()
            builder.text = trimmedText
            // Empty _note="" means no note — match the app's nil-if-empty convention.
            builder.note = attributeDict[Attr.note].flatMap { $0.isEmpty ? nil : $0 }
            builder.isChecked = Self.isChecked(attributeDict)
            if let quantityString = attributeDict[Attr.quantity], let quantity = Int(quantityString), quantity >= 1 {
                builder.quantity = quantity
            }

            // Node stack is keyed on <outline> elements only, so an outline nested
            // under an unknown wrapper element still attaches to the nearest
            // ancestor outline, or the document root if there is none.
            if let parentBuilder = outlineStack.last {
                parentBuilder.children.append(builder)
            } else {
                rootNodes.append(builder)
            }
            outlineStack.append(builder)
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            guard semanticError == nil else { return }

            let lower = elementName.lowercased()
            if lower == Elem.outline {
                if ignoredOutlineDepth > 0 {
                    ignoredOutlineDepth -= 1
                } else if !outlineStack.isEmpty {
                    outlineStack.removeLast()
                }
            }
            if !elementPath.isEmpty {
                elementPath.removeLast()
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard semanticError == nil else { return }
            if isAtHeadTitlePath {
                titleCharacters += string
            }
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            guard semanticError == nil else { return }
            guard isAtHeadTitlePath, let string = String(data: CDATABlock, encoding: .utf8) else { return }
            titleCharacters += string
        }

        /// True only while the element path is exactly opml > head > title —
        /// text anywhere else (unknown elements, expansionState, ownerName, …)
        /// must never leak into the list title.
        private var isAtHeadTitlePath: Bool {
            elementPath == [Elem.opml, Elem.head, Elem.title]
        }

        /// First match wins: _status ("checked" → true; anything else → false),
        /// else _complete, else complete, else checked — each true iff the value
        /// lowercased is in {"true", "yes", "1", "checked"}.
        private static func isChecked(_ attributes: [String: String]) -> Bool {
            if let status = attributes[Attr.status] {
                return status.lowercased() == "checked"
            }
            let truthy: Set<String> = ["true", "yes", "1", "checked"]
            for key in [Attr.complete, Attr.completeAlt, Attr.checked] {
                if let value = attributes[key] {
                    return truthy.contains(value.lowercased())
                }
            }
            return false
        }
    }
}
