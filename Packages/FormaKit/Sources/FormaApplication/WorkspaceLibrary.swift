import FormaDomain
import FormaLocalization
import Foundation
import Observation

public struct LocalWorkspace: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var symbol: String
    public var summary: String
    public var createdAt: Date
    public init(
        id: UUID = UUID(), name: String, symbol: String = "square.stack.3d.up.fill", summary: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.summary = summary
        self.createdAt = createdAt
    }
    private enum CodingKeys: String, CodingKey { case id, name, symbol, summary, createdAt }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        symbol = try values.decodeIfPresent(String.self, forKey: .symbol) ?? "square.stack.3d.up.fill"
        summary = try values.decodeIfPresent(String.self, forKey: .summary) ?? ""
        createdAt = try values.decode(Date.self, forKey: .createdAt)
    }
}
public struct WorkspaceFile: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var workspaceID: UUID
    public var title: String
    public var url: URL
    public var modifiedAt: Date
    public var isTrashed: Bool
    public var parentID: UUID?
    public var sortIndex: Int
    public var pageCount: Int
    public init(
        id: UUID, workspaceID: UUID, title: String, url: URL, modifiedAt: Date, isTrashed: Bool,
        parentID: UUID? = nil, sortIndex: Int = .max, pageCount: Int = 1
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.title = title
        self.url = url
        self.modifiedAt = modifiedAt
        self.isTrashed = isTrashed
        self.parentID = parentID
        self.sortIndex = sortIndex
        self.pageCount = pageCount
    }
}
public struct WorkspaceTreeItem: Identifiable, Equatable, Sendable {
    public var file: WorkspaceFile
    public var depth: Int
    public var id: UUID { file.id }
    public init(file: WorkspaceFile, depth: Int) {
        self.file = file
        self.depth = depth
    }
}
public struct WorkspacePagePlacement: Codable, Equatable, Sendable {
    public var id: UUID
    public var parentID: UUID?
    public var order: Int
    public init(id: UUID, parentID: UUID?, order: Int) {
        self.id = id
        self.parentID = parentID
        self.order = order
    }
}
public enum WorkspacePageMovePosition: Equatable, Sendable {
    case before, inside, after
}
public struct WorkspaceBackupSummary: Equatable, Sendable {
    public var workspaceCount: Int
    public var documentCount: Int
    public var trashedDocumentCount: Int
    public init(workspaceCount: Int, documentCount: Int, trashedDocumentCount: Int) {
        self.workspaceCount = workspaceCount
        self.documentCount = documentCount
        self.trashedDocumentCount = trashedDocumentCount
    }
}
public protocol WorkspaceRepository: Sendable {
    func workspaces() async throws -> [LocalWorkspace]
    func ensureWorkspace(defaultName: String) async throws -> [LocalWorkspace]
    func createWorkspace(name: String) async throws -> LocalWorkspace
    func renameWorkspace(_ id: UUID, name: String) async throws
    func updateWorkspace(_ id: UUID, name: String, symbol: String, summary: String) async throws
    func deleteWorkspace(_ id: UUID) async throws
    func files(in workspaceID: UUID, trashed: Bool) async throws -> [WorkspaceFile]
    func createDocument(_ diagram: Diagram, in workspaceID: UUID) async throws -> URL
    func createDocument(_ document: DiagramDocument, in workspaceID: UUID) async throws -> URL
    func trash(_ file: WorkspaceFile) async throws
    func restore(_ file: WorkspaceFile) async throws
    func restoreAll(in workspaceID: UUID) async throws -> Int
    func emptyTrash(in workspaceID: UUID) async throws -> Int
    func move(_ file: WorkspaceFile, to workspaceID: UUID) async throws
    func rename(_ file: WorkspaceFile, title: String) async throws
    func duplicate(_ file: WorkspaceFile, suffix: String) async throws
    func permanentlyDelete(_ file: WorkspaceFile) async throws
    func movePage(_ fileID: UUID, under parentID: UUID?, in workspaceID: UUID) async throws
    func repositionPage(
        _ fileID: UUID, relativeTo targetID: UUID, position: WorkspacePageMovePosition,
        in workspaceID: UUID
    ) async throws
    func createBackup(at url: URL) async throws -> WorkspaceBackupSummary
    func restoreBackup(from url: URL) async throws -> WorkspaceBackupSummary
}
public enum WorkspaceError: Error, LocalizedError, Sendable {
    case invalidName, invalidLocation, fileInUse, destinationExists, cannotDeleteOnlyWorkspace
    case invalidBackup, unsupportedBackup, backupTooLarge, emptyBackup
    public var errorDescription: String? {
        switch self {
        case .invalidName: "请输入 1 到 80 个字符的名称。"
        case .invalidLocation: "工作空间位置无效或已被外部修改。"
        case .fileInUse: "文档仍在窗口中打开，请先关闭它再进行此操作。"
        case .destinationExists: "目标位置已有同名标识的文档，原文件未被覆盖。"
        case .invalidBackup: "备份文件已损坏、校验失败或包含无效数据。"
        case .unsupportedBackup: "此备份由更高版本的 Forma 创建，当前版本无法恢复。"
        case .backupTooLarge: "备份文件超出当前版本支持的 512 MB 上限。"
        case .emptyBackup: "没有可备份的工作空间。"
        case .cannotDeleteOnlyWorkspace: "至少需要保留一个工作空间。"
        }
    }
}

@MainActor @Observable public final class WorkspaceLibrary {
    public private(set) var workspaces: [LocalWorkspace] = []
    public private(set) var files: [WorkspaceFile] = []
    public private(set) var workspaceFiles: [WorkspaceFile] = []
    public var selectedWorkspaceID: UUID?
    public var showingTrash = false
    public var search = ""
    public var activeSession: DocumentSession?
    public var activeFileURL: URL?
    public private(set) var isBusy = false
    public var errorMessage: String?
    public var noticeMessage: String?
    public var templates: [TemplateDescriptor] = []
    @ObservationIgnored public var settingsAction: (() -> Void)?
    @ObservationIgnored public var openAction: ((URL) -> Void)?
    @ObservationIgnored public var openInNewWindowAction: ((URL) -> Void)?
    @ObservationIgnored public var createAction: ((String, UUID) -> Void)?
    @ObservationIgnored public var canMoveFile: ((URL) -> Bool)?
    @ObservationIgnored public var prepareFileMutation: ((URL) async throws -> Void)?
    @ObservationIgnored public var backupAction: (() -> Void)?
    @ObservationIgnored public var restoreBackupAction: (() -> Void)?
    @ObservationIgnored public var revealFileAction: ((URL) -> Void)?
    @ObservationIgnored public var revealWorkspaceAction: ((UUID) -> Void)?
    @ObservationIgnored private let repository: any WorkspaceRepository
    @ObservationIgnored private var generation = 0
    public init(repository: any WorkspaceRepository) { self.repository = repository }
    public var visibleFiles: [WorkspaceFile] {
        files.filter { search.isEmpty || $0.title.localizedStandardContains(search) }.sorted {
            $0.modifiedAt > $1.modifiedAt
        }
    }
    public var currentName: String { workspaces.first { $0.id == selectedWorkspaceID }?.name ?? "工作空间" }
    public var currentWorkspace: LocalWorkspace? { workspaces.first { $0.id == selectedWorkspaceID } }
    public var workspaceTree: [WorkspaceTreeItem] {
        let ids = Set(workspaceFiles.map(\.id))
        let grouped = Dictionary(grouping: workspaceFiles) { file in
            file.parentID.flatMap { ids.contains($0) ? $0 : nil }
        }
        func ordered(_ files: [WorkspaceFile]) -> [WorkspaceFile] {
            files.sorted {
                if $0.sortIndex != $1.sortIndex { return $0.sortIndex < $1.sortIndex }
                return $0.modifiedAt > $1.modifiedAt
            }
        }
        var result: [WorkspaceTreeItem] = []
        var visited = Set<UUID>()
        func append(_ file: WorkspaceFile, depth: Int) {
            guard visited.insert(file.id).inserted else { return }
            result.append(WorkspaceTreeItem(file: file, depth: depth))
            for child in ordered(grouped[file.id] ?? []) { append(child, depth: min(depth + 1, 6)) }
        }
        for root in ordered(grouped[nil] ?? []) { append(root, depth: 0) }
        for orphan in ordered(workspaceFiles) where !visited.contains(orphan.id) { append(orphan, depth: 0) }
        return result
    }
    public func reload() async {
        generation += 1
        let request = generation
        isBusy = true
        defer { if request == generation { isBusy = false } }
        do {
            let spaces = try await repository.ensureWorkspace(defaultName: tr("我的工作空间"))
            guard request == generation else { return }
            workspaces = spaces
            if !spaces.contains(where: { $0.id == selectedWorkspaceID }) { selectedWorkspaceID = spaces.first?.id }
            guard let id = selectedWorkspaceID else { return }
            let items = try await repository.files(in: id, trashed: showingTrash)
            guard request == generation else { return }
            files = items
            if showingTrash {
                let activeItems = try await repository.files(in: id, trashed: false)
                guard request == generation else { return }
                workspaceFiles = activeItems.sorted { $0.modifiedAt > $1.modifiedAt }
            } else {
                workspaceFiles = items.sorted { $0.modifiedAt > $1.modifiedAt }
            }
        } catch { if request == generation { errorMessage = error.localizedDescription } }
    }
    /// 预先读取目标页面的数据，再一次性切换状态，避免回收箱先显示普通文件后再次刷新的闪烁。
    public func setTrashVisible(_ visible: Bool) async {
        guard visible != showingTrash, !isBusy, let id = selectedWorkspaceID else { return }
        generation += 1
        let request = generation
        do {
            async let requestedFiles = repository.files(in: id, trashed: visible)
            async let activeFiles = repository.files(in: id, trashed: false)
            let (targetItems, activeItems) = try await (requestedFiles, activeFiles)
            guard request == generation else { return }
            files = targetItems
            workspaceFiles = activeItems.sorted { $0.modifiedAt > $1.modifiedAt }
            showingTrash = visible
        } catch {
            if request == generation { errorMessage = error.localizedDescription }
        }
    }
    public func showAllFiles() async {
        if showingTrash {
            await setTrashVisible(false)
            guard !showingTrash else { return }
        }
        activeFileURL = nil
        activeSession = nil
    }
    public func select(_ id: UUID) async {
        selectedWorkspaceID = id
        activeSession = nil
        activeFileURL = nil
        showingTrash = false
        search = ""
        await reload()
    }
    public func createWorkspace(_ name: String) async {
        do {
            let space = try await repository.createWorkspace(name: name)
            selectedWorkspaceID = space.id
            activeSession = nil
            activeFileURL = nil
            showingTrash = false
            await reload()
        } catch { errorMessage = error.localizedDescription }
    }
    public func renameWorkspace(_ name: String) async {
        guard let id = selectedWorkspaceID else { return }
        do {
            try await repository.renameWorkspace(id, name: name)
            await reload()
        } catch { errorMessage = error.localizedDescription }
    }
    public func updateWorkspace(name: String, symbol: String, summary: String) async {
        guard !isBusy, let id = selectedWorkspaceID else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await repository.updateWorkspace(id, name: name, symbol: symbol, summary: summary)
            await reload()
        } catch { errorMessage = error.localizedDescription }
    }
    public func deleteCurrentWorkspace() async {
        guard !isBusy, let id = selectedWorkspaceID else { return }
        guard workspaces.count > 1 else {
            errorMessage = WorkspaceError.cannotDeleteOnlyWorkspace.localizedDescription
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let activeFiles = try await repository.files(in: id, trashed: false)
            let trashedFiles = try await repository.files(in: id, trashed: true)
            if let blocking = (activeFiles + trashedFiles).first(where: { canMoveFile?($0.url) == false }) {
                errorMessage = String(format: tr("文档「%@」仍在窗口中打开，请先关闭它。"), blocking.title)
                return
            }
            for file in activeFiles + trashedFiles { try await prepareFileMutation?(file.url) }
            try await repository.deleteWorkspace(id)
            selectedWorkspaceID = workspaces.first { $0.id != id }?.id
            activeSession = nil
            activeFileURL = nil
            showingTrash = false
            search = ""
            await reload()
        } catch { errorMessage = error.localizedDescription }
    }
    public func trash(_ file: WorkspaceFile) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        guard canMoveFile?(file.url) != false else {
            errorMessage = WorkspaceError.fileInUse.localizedDescription
            return
        }
        let wasActive = activeFileURL?.standardizedFileURL == file.url.standardizedFileURL
        do {
            try await prepareFileMutation?(file.url)
            try await repository.trash(file)
            await reload()
        } catch {
            errorMessage = error.localizedDescription
            if wasActive { openAction?(file.url) }
        }
    }
    public func restore(_ file: WorkspaceFile) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await repository.restore(file)
            await reload()
        } catch { errorMessage = error.localizedDescription }
    }
    public func restoreAll() async {
        guard !isBusy, showingTrash, let id = selectedWorkspaceID else { return }
        isBusy = true
        defer { isBusy = false }
        errorMessage = nil
        do {
            let count = try await repository.restoreAll(in: id)
            await reload()
            noticeMessage = String(format: tr("已恢复 %d 个图表。"), count)
        } catch { errorMessage = error.localizedDescription }
    }
    public func emptyTrash() async {
        guard !isBusy, showingTrash, let id = selectedWorkspaceID else { return }
        isBusy = true
        defer { isBusy = false }
        errorMessage = nil
        if let blocking = files.first(where: { canMoveFile?($0.url) == false }) {
            errorMessage = String(format: tr("文档「%@」仍在窗口中打开，请先关闭它。"), blocking.title)
            return
        }
        do {
            let count = try await repository.emptyTrash(in: id)
            await reload()
            noticeMessage = String(format: tr("已永久删除 %d 个图表。"), count)
        } catch { errorMessage = error.localizedDescription }
    }
    public func move(_ file: WorkspaceFile, to id: UUID) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        guard canMoveFile?(file.url) != false else {
            errorMessage = WorkspaceError.fileInUse.localizedDescription
            return
        }
        let wasActive = activeFileURL?.standardizedFileURL == file.url.standardizedFileURL
        do {
            try await prepareFileMutation?(file.url)
            try await repository.move(file, to: id)
            await reload()
        } catch {
            errorMessage = error.localizedDescription
            if wasActive { openAction?(file.url) }
        }
    }
    public func rename(_ file: WorkspaceFile, title: String) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        guard canMoveFile?(file.url) != false else {
            errorMessage = WorkspaceError.fileInUse.localizedDescription
            return
        }
        let wasActive = activeFileURL?.standardizedFileURL == file.url.standardizedFileURL
        do {
            try await prepareFileMutation?(file.url)
            try await repository.rename(file, title: title)
            await reload()
            if wasActive { openAction?(file.url) }
        } catch {
            errorMessage = error.localizedDescription
            if wasActive { openAction?(file.url) }
        }
    }
    public func duplicate(_ file: WorkspaceFile) async {
        guard !isBusy, !file.isTrashed else { return }
        isBusy = true
        defer { isBusy = false }
        guard canMoveFile?(file.url) != false else {
            errorMessage = WorkspaceError.fileInUse.localizedDescription
            return
        }
        let wasActive = activeFileURL?.standardizedFileURL == file.url.standardizedFileURL
        do {
            try await prepareFileMutation?(file.url)
            try await repository.duplicate(file, suffix: tr("副本"))
            await reload()
            if wasActive { openAction?(file.url) }
        } catch {
            errorMessage = error.localizedDescription
            if wasActive { openAction?(file.url) }
        }
    }
    public func permanentlyDelete(_ file: WorkspaceFile) async {
        guard !isBusy, file.isTrashed else { return }
        isBusy = true
        defer { isBusy = false }
        guard canMoveFile?(file.url) != false else {
            errorMessage = WorkspaceError.fileInUse.localizedDescription
            return
        }
        do {
            try await repository.permanentlyDelete(file)
            await reload()
        } catch { errorMessage = error.localizedDescription }
    }
    public func movePage(_ fileID: UUID, under parentID: UUID?) async {
        guard !isBusy, let workspaceID = selectedWorkspaceID, fileID != parentID else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await repository.movePage(fileID, under: parentID, in: workspaceID)
            await reload()
        } catch { errorMessage = error.localizedDescription }
    }
    public func repositionPage(_ fileID: UUID, relativeTo targetID: UUID, position: WorkspacePageMovePosition) async {
        guard !isBusy, let workspaceID = selectedWorkspaceID, fileID != targetID else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await repository.repositionPage(fileID, relativeTo: targetID, position: position, in: workspaceID)
            await reload()
        } catch { errorMessage = error.localizedDescription }
    }
    public func createBackup(at url: URL) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let result = try await repository.createBackup(at: url)
            noticeMessage = String(
                format: tr("备份完成：%d 个工作空间，%d 个图表（含 %d 个回收箱图表）。"),
                result.workspaceCount, result.documentCount, result.trashedDocumentCount)
        } catch { errorMessage = error.localizedDescription }
    }
    public func restoreBackup(from url: URL) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let result = try await repository.restoreBackup(from: url)
            await reload()
            noticeMessage = String(
                format: tr("恢复完成：%d 个工作空间，%d 个图表（含 %d 个回收箱图表）。"),
                result.workspaceCount, result.documentCount, result.trashedDocumentCount)
        } catch { errorMessage = error.localizedDescription }
    }
}
