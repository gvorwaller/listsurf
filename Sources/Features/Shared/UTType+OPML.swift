import UniformTypeIdentifiers

extension UTType {
    /// Backed by the imported type declaration in App/Info.plist. Without that
    /// declaration UTType(importedAs:) silently degrades to a dynamic type and
    /// .opml files stop matching in file pickers.
    static var opml: UTType { UTType(importedAs: "org.opml.opml", conformingTo: .xml) }
}
