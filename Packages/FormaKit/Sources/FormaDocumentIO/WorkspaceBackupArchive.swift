import Compression
import CryptoKit
import FormaApplication
import FormaDomain
import Foundation

private struct WorkspaceBackupPayload: Codable {
    var formatVersion: Int
    var createdAt: Date
    var workspaces: [BackedUpWorkspace]
}

private struct BackedUpWorkspace: Codable {
    var workspace: LocalWorkspace
    var documents: [BackedUpDocument]
}

private struct BackedUpDocument: Codable {
    var recordID: UUID
    var diagram: DiagramDocument
    var modifiedAt: Date
    var isTrashed: Bool
    var parentID: UUID?
    var sortIndex: Int?
}

enum WorkspaceBackupArchive {
    private static let magic = Data("FORMABK1".utf8)
    private static let formatVersion: UInt32 = 1
    private static let maximumSize = 512 * 1_024 * 1_024

    static func create(from repository: isolated LocalWorkspaceRepository, at destination: URL) throws
        -> WorkspaceBackupSummary
    {
        let workspaces = try repository.workspaces()
        guard !workspaces.isEmpty else { throw WorkspaceError.emptyBackup }
        var backedUp: [BackedUpWorkspace] = []
        var documentCount = 0
        var trashedCount = 0
        for workspace in workspaces {
            var documents: [BackedUpDocument] = []
            for isTrashed in [false, true] {
                for file in try repository.files(in: workspace.id, trashed: isTrashed) {
                    let document = try DocumentCodec.read(at: file.url).validated()
                    documents.append(
                        BackedUpDocument(
                            recordID: file.id, diagram: document, modifiedAt: file.modifiedAt,
                            isTrashed: isTrashed, parentID: file.parentID,
                            sortIndex: file.sortIndex == .max ? nil : file.sortIndex))
                    documentCount += 1
                    if isTrashed { trashedCount += 1 }
                }
            }
            backedUp.append(BackedUpWorkspace(workspace: workspace, documents: documents))
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let payload = try encoder.encode(
            WorkspaceBackupPayload(formatVersion: 1, createdAt: Date(), workspaces: backedUp))
        guard payload.count <= maximumSize else { throw WorkspaceError.backupTooLarge }
        let compressed = try compress(payload)
        var archive = Data()
        archive.append(magic)
        archive.append(littleEndian: formatVersion)
        archive.append(littleEndian: UInt64(payload.count))
        archive.append(Data(SHA256.hash(data: payload)))
        archive.append(compressed)
        guard archive.count <= maximumSize else { throw WorkspaceError.backupTooLarge }
        try archive.write(to: destination, options: .atomic)
        return WorkspaceBackupSummary(
            workspaceCount: workspaces.count, documentCount: documentCount,
            trashedDocumentCount: trashedCount)
    }

    static func restore(into repository: isolated LocalWorkspaceRepository, from source: URL) throws
        -> WorkspaceBackupSummary
    {
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw WorkspaceError.invalidBackup
        }
        guard let fileSize = values.fileSize, fileSize <= maximumSize else { throw WorkspaceError.backupTooLarge }
        let archive = try Data(contentsOf: source, options: .mappedIfSafe)
        let headerSize = magic.count + 4 + 8 + 32
        guard archive.count > headerSize, archive.prefix(magic.count) == magic else {
            throw WorkspaceError.invalidBackup
        }
        let version = archive.readUInt32(at: magic.count)
        guard version <= formatVersion else { throw WorkspaceError.unsupportedBackup }
        guard version == formatVersion else { throw WorkspaceError.invalidBackup }
        let payloadSize = archive.readUInt64(at: magic.count + 4)
        guard payloadSize > 0, payloadSize <= UInt64(maximumSize), payloadSize <= UInt64(Int.max) else {
            throw WorkspaceError.backupTooLarge
        }
        let hashStart = magic.count + 12
        let expectedHash = archive[hashStart..<(hashStart + 32)]
        let compressed = archive.suffix(from: headerSize)
        let payload = try decompress(Data(compressed), expectedSize: Int(payloadSize))
        guard Data(SHA256.hash(data: payload)) == expectedHash else { throw WorkspaceError.invalidBackup }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup: WorkspaceBackupPayload
        do { backup = try decoder.decode(WorkspaceBackupPayload.self, from: payload) } catch {
            throw WorkspaceError.invalidBackup
        }
        guard backup.formatVersion == 1, !backup.workspaces.isEmpty else { throw WorkspaceError.invalidBackup }
        return try restore(backup, into: repository)
    }

    private static func restore(
        _ backup: WorkspaceBackupPayload, into repository: isolated LocalWorkspaceRepository
    ) throws
        -> WorkspaceBackupSummary
    {
        let existingIDs = Set(try repository.workspaces().map(\.id))
        guard Set(backup.workspaces.map(\.workspace.id)).count == backup.workspaces.count else {
            throw WorkspaceError.invalidBackup
        }
        var reservedIDs = existingIDs
        var plans: [(source: BackedUpWorkspace, target: LocalWorkspace)] = []
        var documentCount = 0
        var trashedCount = 0
        for item in backup.workspaces {
            let trimmedName = item.workspace.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty, trimmedName.count <= 80 else { throw WorkspaceError.invalidBackup }
            let recordIDs = item.documents.map(\.recordID)
            guard Set(recordIDs).count == recordIDs.count else { throw WorkspaceError.invalidBackup }
            for document in item.documents { _ = try document.diagram.validated() }
            var targetID = item.workspace.id
            while reservedIDs.contains(targetID) { targetID = UUID() }
            reservedIDs.insert(targetID)
            plans.append(
                (
                    item,
                    LocalWorkspace(
                        id: targetID, name: trimmedName, symbol: item.workspace.symbol,
                        summary: item.workspace.summary, createdAt: item.workspace.createdAt)
                ))
            documentCount += item.documents.count
            trashedCount += item.documents.count(where: \.isTrashed)
        }

        try repository.prepareForBackupRestore()
        let staging = repository.root.appendingPathComponent(".restore-" + UUID().uuidString, isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        do {
            for plan in plans {
                let workspaceFolder = staging.appendingPathComponent(plan.target.id.uuidString, isDirectory: true)
                try fm.createDirectory(at: workspaceFolder, withIntermediateDirectories: false)
                try JSONEncoder().encode(plan.target).write(
                    to: workspaceFolder.appendingPathComponent("workspace.json"), options: .atomic)
                for name in ["Documents", "Trash"] {
                    try fm.createDirectory(
                        at: workspaceFolder.appendingPathComponent(name, isDirectory: true),
                        withIntermediateDirectories: false)
                }
                for document in plan.source.documents {
                    let folder = workspaceFolder.appendingPathComponent(
                        document.isTrashed ? "Trash" : "Documents", isDirectory: true)
                    let target = folder.appendingPathComponent(
                        document.recordID.uuidString + ".forma", isDirectory: true)
                    try DocumentCodec.encode(document.diagram).write(
                        to: target, options: .atomic, originalContentsURL: nil)
                    try fm.setAttributes([.modificationDate: document.modifiedAt], ofItemAtPath: target.path)
                }
                let navigation = plan.source.documents.compactMap { document -> WorkspacePagePlacement? in
                    guard document.parentID != nil || document.sortIndex != nil else { return nil }
                    return WorkspacePagePlacement(
                        id: document.recordID, parentID: document.parentID,
                        order: document.sortIndex ?? .max)
                }
                if !navigation.isEmpty {
                    try JSONEncoder().encode(navigation).write(
                        to: workspaceFolder.appendingPathComponent("navigation.json"), options: .atomic)
                }
            }
            var installed: [URL] = []
            do {
                for plan in plans {
                    let source = staging.appendingPathComponent(plan.target.id.uuidString, isDirectory: true)
                    let destination = repository.root.appendingPathComponent(
                        plan.target.id.uuidString, isDirectory: true)
                    guard !fm.fileExists(atPath: destination.path) else { throw WorkspaceError.destinationExists }
                    try fm.moveItem(at: source, to: destination)
                    installed.append(destination)
                }
            } catch {
                for url in installed.reversed() {
                    try? fm.moveItem(at: url, to: staging.appendingPathComponent(url.lastPathComponent))
                }
                throw error
            }
        } catch let error as WorkspaceError {
            throw error
        } catch {
            throw WorkspaceError.invalidBackup
        }
        return WorkspaceBackupSummary(
            workspaceCount: plans.count, documentCount: documentCount,
            trashedDocumentCount: trashedCount)
    }

    private static func compress(_ data: Data) throws -> Data {
        var capacity = max(1_024, data.count / 2)
        let maximumCapacity = min(maximumSize, data.count * 2 + 1_024)
        while capacity <= maximumCapacity {
            var output = Data(count: capacity)
            let written = output.withUnsafeMutableBytes { destination in
                data.withUnsafeBytes { source in
                    compression_encode_buffer(
                        destination.bindMemory(to: UInt8.self).baseAddress!, capacity,
                        source.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_LZFSE)
                }
            }
            if written > 0 {
                output.removeSubrange(written..<output.count)
                return output
            }
            capacity = min(maximumCapacity + 1, capacity * 2)
        }
        throw WorkspaceError.invalidBackup
    }

    private static func decompress(_ data: Data, expectedSize: Int) throws -> Data {
        var output = Data(count: expectedSize)
        let written = output.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                compression_decode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!, expectedSize,
                    source.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_LZFSE)
            }
        }
        guard written == expectedSize else { throw WorkspaceError.invalidBackup }
        return output
    }
}

extension Data {
    fileprivate mutating func append<T: FixedWidthInteger>(littleEndian value: T) {
        var value = value.littleEndian
        Swift.withUnsafeBytes(of: &value) { append(contentsOf: $0) }
    }
    fileprivate func readUInt32(at offset: Int) -> UInt32 {
        self[offset..<(offset + 4)].enumerated().reduce(0) { $0 | UInt32($1.element) << ($1.offset * 8) }
    }
    fileprivate func readUInt64(at offset: Int) -> UInt64 {
        self[offset..<(offset + 8)].enumerated().reduce(0) { $0 | UInt64($1.element) << ($1.offset * 8) }
    }
}
