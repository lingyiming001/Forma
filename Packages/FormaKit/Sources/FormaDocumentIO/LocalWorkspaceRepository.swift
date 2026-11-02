import FormaApplication
import FormaDomain
import Foundation

/// 文件位置是真实来源；不维护容易与文件移动失步的第二份文档索引。
public actor LocalWorkspaceRepository: WorkspaceRepository {
    public nonisolated let root: URL
    private let fm = FileManager.default
    public init(root: URL) { self.root = root.standardizedFileURL }
    private func prepareRoot() throws {
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try checkDirectory(root)
    }
    func prepareForBackupRestore() throws { try prepareRoot() }
    private func checkDirectory(_ url: URL) throws {
        let value = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard value.isDirectory == true, value.isSymbolicLink != true else { throw WorkspaceError.invalidLocation }
    }
    private func location(_ id: UUID, trashed: Bool) throws -> URL {
        try prepareRoot()
        let base = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try checkDirectory(base)
        let folder = base.appendingPathComponent(trashed ? "Trash" : "Documents", isDirectory: true)
        try checkDirectory(folder)
        return folder
    }
    private func validateName(_ value: String) throws -> String {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80 else { throw WorkspaceError.invalidName }
        return name
    }
    private func navigationURL(_ id: UUID) -> URL {
        root.appendingPathComponent(id.uuidString, isDirectory: true).appendingPathComponent("navigation.json")
    }
    private func navigation(_ id: UUID) throws -> [WorkspacePagePlacement] {
        let url = navigationURL(id)
        guard fm.fileExists(atPath: url.path) else { return [] }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? .max) <= 1_000_000
        else { throw WorkspaceError.invalidLocation }
        return try JSONDecoder().decode([WorkspacePagePlacement].self, from: Data(contentsOf: url))
    }
    private func writeNavigation(_ placements: [WorkspacePagePlacement], workspaceID: UUID) throws {
        try JSONEncoder().encode(placements).write(to: navigationURL(workspaceID), options: .atomic)
    }
    public func workspaces() throws -> [LocalWorkspace] {
        try prepareRoot()
        return try fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles
        ).compactMap { folder in
            guard let id = UUID(uuidString: folder.lastPathComponent) else { return nil }
            try checkDirectory(folder)
            let metadata = folder.appendingPathComponent("workspace.json")
            let values = try metadata.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? .max) <= 64_000
            else { throw WorkspaceError.invalidLocation }
            let workspace = try JSONDecoder().decode(LocalWorkspace.self, from: Data(contentsOf: metadata))
            guard workspace.id == id else { throw WorkspaceError.invalidLocation }
            return workspace
        }.sorted { $0.createdAt < $1.createdAt }
    }
    public func ensureWorkspace(defaultName: String) throws -> [LocalWorkspace] {
        let existing = try workspaces()
        return existing.isEmpty ? [try createWorkspace(name: defaultName)] : existing
    }
    public func createWorkspace(name: String) throws -> LocalWorkspace {
        try prepareRoot()
        let space = LocalWorkspace(name: try validateName(name))
        let base = root.appendingPathComponent(space.id.uuidString, isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: false)
        do {
            for directory in ["Documents", "Trash"] {
                try fm.createDirectory(at: base.appendingPathComponent(directory), withIntermediateDirectories: false)
            }
            try JSONEncoder().encode(space).write(to: base.appendingPathComponent("workspace.json"), options: .atomic)
        } catch {
            try? fm.removeItem(at: base)
            throw error
        }
        return space
    }
    public func renameWorkspace(_ id: UUID, name: String) throws {
        guard var space = try workspaces().first(where: { $0.id == id }) else { throw WorkspaceError.invalidLocation }
        space.name = try validateName(name)
        try writeWorkspace(space)
    }
    public func updateWorkspace(_ id: UUID, name: String, symbol: String, summary: String) throws {
        guard var space = try workspaces().first(where: { $0.id == id }) else { throw WorkspaceError.invalidLocation }
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowedSymbols = Set([
            "square.stack.3d.up.fill", "square.grid.2x2.fill", "folder.fill", "building.2.fill",
            "network", "shippingbox.fill", "lightbulb.fill", "point.3.connected.trianglepath.dotted",
        ])
        guard trimmedSummary.count <= 240, allowedSymbols.contains(symbol) else { throw WorkspaceError.invalidName }
        space.name = try validateName(name)
        space.symbol = symbol
        space.summary = trimmedSummary
        try writeWorkspace(space)
    }
    private func writeWorkspace(_ space: LocalWorkspace) throws {
        try JSONEncoder().encode(space).write(
            to: root.appendingPathComponent(space.id.uuidString).appendingPathComponent("workspace.json"), options: .atomic)
    }
    public func deleteWorkspace(_ id: UUID) throws {
        let spaces = try workspaces()
        guard spaces.count > 1 else { throw WorkspaceError.cannotDeleteOnlyWorkspace }
        let base = root.appendingPathComponent(id.uuidString, isDirectory: true).standardizedFileURL
        guard spaces.contains(where: { $0.id == id }), base.deletingLastPathComponent() == root.standardizedFileURL
        else { throw WorkspaceError.invalidLocation }
        try checkDirectory(base)
        try fm.removeItem(at: base)
    }
    public func files(in id: UUID, trashed: Bool) throws -> [WorkspaceFile] {
        let folder = try location(id, trashed: trashed)
        let navigation = try navigation(id)
        guard Set(navigation.map(\.id)).count == navigation.count else { throw WorkspaceError.invalidLocation }
        let placements = Dictionary(uniqueKeysWithValues: navigation.map { ($0.id, $0) })
        return try fm.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey, .isSymbolicLinkKey],
            options: .skipsHiddenFiles
        ).filter { $0.pathExtension == "forma" }.map { url in
            guard let recordID = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else {
                throw WorkspaceError.invalidLocation
            }
            let attributes = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .contentModificationDateKey])
            guard attributes.isSymbolicLink != true else { throw WorkspaceError.invalidLocation }
            let manifestURL = url.appendingPathComponent("manifest.json")
            let values = try manifestURL.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true, (values.fileSize ?? .max) <= 64_000 else {
                throw WorkspaceError.invalidLocation
            }
            let manifest = try JSONDecoder().decode(DocumentManifest.self, from: Data(contentsOf: manifestURL))
            let document = try (manifest.title == nil || manifest.pageCount == nil) ? DocumentCodec.read(at: url) : nil
            let title = manifest.title ?? document?.activePage.title ?? "Untitled"
            let pageCount = manifest.pageCount ?? document?.pages.count ?? 1
            let placement = placements[recordID]
            return WorkspaceFile(
                id: recordID, workspaceID: id, title: title, url: url,
                modifiedAt: attributes.contentModificationDate ?? .distantPast, isTrashed: trashed,
                parentID: placement?.parentID, sortIndex: placement?.order ?? .max, pageCount: pageCount)
        }
    }
    public func createDocument(_ diagram: Diagram, in id: UUID) throws -> URL {
        try createDocument(DiagramDocument(page: diagram), in: id)
    }
    public func createDocument(_ document: DiagramDocument, in id: UUID) throws -> URL {
        let folder = try location(id, trashed: false)
        let url = folder.appendingPathComponent(document.pages[0].id.uuidString + ".forma", isDirectory: true)
        guard !fm.fileExists(atPath: url.path) else { throw WorkspaceError.destinationExists }
        try DocumentCodec.encode(document).write(to: url, options: .atomic, originalContentsURL: nil)
        return url
    }
    private func verified(_ file: WorkspaceFile) throws -> URL {
        let expected = try location(file.workspaceID, trashed: file.isTrashed).appendingPathComponent(
            file.id.uuidString + ".forma"
        ).standardizedFileURL
        guard expected == file.url.standardizedFileURL else { throw WorkspaceError.invalidLocation }
        guard fm.fileExists(atPath: expected.path) else { throw WorkspaceError.invalidLocation }
        try checkDirectory(expected)
        return expected
    }
    private func relocate(_ file: WorkspaceFile, workspaceID: UUID, trashed: Bool) throws {
        let source = try verified(file)
        let destination = try location(workspaceID, trashed: trashed).appendingPathComponent(
            file.id.uuidString + ".forma")
        guard !fm.fileExists(atPath: destination.path) else { throw WorkspaceError.destinationExists }
        try fm.moveItem(at: source, to: destination)
    }
    public func trash(_ file: WorkspaceFile) throws {
        guard !file.isTrashed else { return }
        try relocate(file, workspaceID: file.workspaceID, trashed: true)
    }
    public func restore(_ file: WorkspaceFile) throws {
        guard file.isTrashed else { return }
        try relocate(file, workspaceID: file.workspaceID, trashed: false)
    }
    public func restoreAll(in id: UUID) throws -> Int {
        let trashedFiles = try files(in: id, trashed: true)
        for file in trashedFiles { try relocate(file, workspaceID: id, trashed: false) }
        return trashedFiles.count
    }
    public func emptyTrash(in id: UUID) throws -> Int {
        let trashedFiles = try files(in: id, trashed: true)
        for file in trashedFiles {
            // verified 确保路径仍位于该工作空间的 Trash 目录内，才允许永久删除。
            try fm.removeItem(at: try verified(file))
        }
        return trashedFiles.count
    }
    public func permanentlyDelete(_ file: WorkspaceFile) throws {
        guard file.isTrashed else { throw WorkspaceError.invalidLocation }
        try fm.removeItem(at: try verified(file))
    }
    public func move(_ file: WorkspaceFile, to id: UUID) throws {
        guard id != file.workspaceID, !file.isTrashed else { return }
        try relocate(file, workspaceID: id, trashed: false)
    }
    public func rename(_ file: WorkspaceFile, title: String) throws {
        let url = try verified(file)
        let name = try validateName(title)
        let modifiedAt = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let activeFiles = try files(in: file.workspaceID, trashed: false)
        let placements = normalizedPlacements(for: activeFiles, existing: try navigation(file.workspaceID))
        var document = try DocumentCodec.read(at: url)
        document.activePage.title = name
        try writeNavigation(placements, workspaceID: file.workspaceID)
        try DocumentCodec.encode(document).write(to: url, options: .atomic, originalContentsURL: url)
        if let modifiedAt {
            try fm.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: url.path)
        }
    }
    public func duplicate(_ file: WorkspaceFile, suffix: String) throws {
        let source = try verified(file)
        var document = try DocumentCodec.read(at: source)
        let activeIndex = document.activeIndex ?? 0
        for index in document.pages.indices { document.pages[index].id = UUID() }
        document.activePageID = document.pages[activeIndex].id
        document.activePage.title += " " + suffix
        let folder = try location(file.workspaceID, trashed: false)
        let destination = folder.appendingPathComponent(document.pages[0].id.uuidString + ".forma", isDirectory: true)
        try DocumentCodec.encode(document).write(to: destination, options: .atomic, originalContentsURL: nil)
    }
    public func movePage(_ fileID: UUID, under parentID: UUID?, in workspaceID: UUID) throws {
        if let parentID {
            try repositionPage(fileID, relativeTo: parentID, position: .inside, in: workspaceID)
            return
        }
        let activeFiles = try files(in: workspaceID, trashed: false)
        let activeIDs = Set(activeFiles.map(\.id))
        guard activeIDs.contains(fileID) else { throw WorkspaceError.invalidLocation }
        var placements = normalizedPlacements(for: activeFiles, existing: try navigation(workspaceID))
        let nextOrder = placements.filter { $0.parentID == nil && $0.id != fileID }.map(\.order).max().map { $0 + 1 } ?? 0
        placements.removeAll { $0.id == fileID }
        placements.append(WorkspacePagePlacement(id: fileID, parentID: nil, order: nextOrder))
        try writeNavigation(placements, workspaceID: workspaceID)
    }
    public func repositionPage(
        _ fileID: UUID, relativeTo targetID: UUID, position: WorkspacePageMovePosition,
        in workspaceID: UUID
    ) throws {
        let activeFiles = try files(in: workspaceID, trashed: false)
        let activeIDs = Set(activeFiles.map(\.id))
        guard fileID != targetID, activeIDs.contains(fileID), activeIDs.contains(targetID) else {
            throw WorkspaceError.invalidLocation
        }
        var placements = normalizedPlacements(for: activeFiles, existing: try navigation(workspaceID))
        let parentByID = Dictionary(uniqueKeysWithValues: placements.map { ($0.id, $0.parentID) })
        let newParent = position == .inside ? targetID : (parentByID[targetID] ?? nil)
        var ancestor = newParent
        var ancestors = Set<UUID>()
        while let current = ancestor {
            guard current != fileID, ancestors.insert(current).inserted else { throw WorkspaceError.invalidLocation }
            ancestor = parentByID[current] ?? nil
        }
        placements.removeAll { $0.id == fileID }
        var siblings = placements.filter { $0.parentID == newParent }.sorted { $0.order < $1.order }
        let insertion: Int
        if position == .inside {
            insertion = siblings.count
        } else {
            let targetIndex = siblings.firstIndex { $0.id == targetID } ?? siblings.count
            insertion = min(siblings.count, targetIndex + (position == .after ? 1 : 0))
        }
        siblings.insert(WorkspacePagePlacement(id: fileID, parentID: newParent, order: insertion), at: insertion)
        let siblingIDs = Set(siblings.map(\.id))
        placements.removeAll { siblingIDs.contains($0.id) }
        placements.append(contentsOf: siblings.enumerated().map {
            WorkspacePagePlacement(id: $0.element.id, parentID: newParent, order: $0.offset)
        })
        try writeNavigation(placements, workspaceID: workspaceID)
    }
    private func normalizedPlacements(
        for files: [WorkspaceFile], existing: [WorkspacePagePlacement]
    ) -> [WorkspacePagePlacement] {
        let activeIDs = Set(files.map(\.id))
        var placements = existing.filter { activeIDs.contains($0.id) }
        let placedIDs = Set(placements.map(\.id))
        var nextRootOrder = placements.filter { $0.parentID == nil }.map(\.order).max().map { $0 + 1 } ?? 0
        for file in files.sorted(by: { $0.modifiedAt > $1.modifiedAt }) where !placedIDs.contains(file.id) {
            placements.append(WorkspacePagePlacement(id: file.id, parentID: nil, order: nextRootOrder))
            nextRootOrder += 1
        }
        return placements
    }
    public func createBackup(at url: URL) throws -> WorkspaceBackupSummary {
        try WorkspaceBackupArchive.create(from: self, at: url)
    }
    public func restoreBackup(from url: URL) throws -> WorkspaceBackupSummary {
        try WorkspaceBackupArchive.restore(into: self, from: url)
    }
}
