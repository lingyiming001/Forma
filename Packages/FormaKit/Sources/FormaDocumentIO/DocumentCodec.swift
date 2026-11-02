import FormaDomain
import Foundation

public struct DocumentManifest: Codable, Sendable {
    public let formatVersion: Int
    public let minimumReaderVersion: Int
    public let documentID: UUID
    public var title: String?
    public var pageCount: Int?
    public init(
        documentID: UUID, formatVersion: Int = 3, minimumReaderVersion: Int = 3, title: String? = nil,
        pageCount: Int? = nil
    ) {
        self.documentID = documentID
        self.title = title
        self.pageCount = pageCount
        self.formatVersion = formatVersion
        self.minimumReaderVersion = minimumReaderVersion
    }
}

public enum DocumentCodec {
    /// 仅读取已声明的两个文件，先检查大小与符号链接，避免递归加载任意包内容。
    public static func read(at url: URL) throws -> DiagramDocument {
        let root = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard root.isDirectory == true, root.isSymbolicLink != true else { throw DiagramError.corruptFile }
        var wrappers: [String: FileWrapper] = [:]
        for (name, limit) in [("manifest.json", 64_000), ("document.json", 20_000_000)] {
            let file = url.appendingPathComponent(name)
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { throw DiagramError.corruptFile }
            guard let size = values.fileSize, size <= limit else { throw DiagramError.limitExceeded }
            let data = try Data(contentsOf: file)
            guard data.count <= limit else { throw DiagramError.limitExceeded }
            wrappers[name] = FileWrapper(regularFileWithContents: data)
        }
        return try decode(FileWrapper(directoryWithFileWrappers: wrappers))
    }
    public static func encode(_ diagram: Diagram) throws -> FileWrapper {
        try encode(DiagramDocument(page: diagram))
    }
    public static func encode(_ document: DiagramDocument) throws -> FileWrapper {
        _ = try document.validated()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifest = try encoder.encode(
            DocumentManifest(
                documentID: document.pages[0].id, title: document.activePage.title,
                pageCount: document.pages.count))
        let data = try encoder.encode(document)
        return FileWrapper(directoryWithFileWrappers: [
            "manifest.json": FileWrapper(regularFileWithContents: manifest),
            "document.json": FileWrapper(regularFileWithContents: data),
        ])
    }
    public static func decode(_ wrapper: FileWrapper) throws -> DiagramDocument {
        guard wrapper.isDirectory, let files = wrapper.fileWrappers,
            let manifestData = files["manifest.json"]?.regularFileContents,
            let data = files["document.json"]?.regularFileContents
        else { throw DiagramError.corruptFile }
        guard manifestData.count <= 64_000, data.count <= 20_000_000 else { throw DiagramError.limitExceeded }
        let decoder = JSONDecoder()
        let manifest = try decoder.decode(DocumentManifest.self, from: manifestData)
        guard manifest.minimumReaderVersion <= 3, (1...3).contains(manifest.formatVersion) else {
            throw DiagramError.unsupportedVersion
        }
        // v1/v2 为单页 document.json，升级后作为首页；首页 ID 保持 manifest.documentID。
        if manifest.formatVersion <= 2 {
            let diagram = try decoder.decode(Diagram.self, from: data).validated()
            guard manifest.documentID == diagram.id else { throw DiagramError.corruptFile }
            return DiagramDocument(page: diagram)
        }
        let document = try decoder.decode(DiagramDocument.self, from: data).validated()
        guard manifest.documentID == document.pages[0].id else { throw DiagramError.corruptFile }
        return document
    }
}
