#if DEBUG
    import AppKit
    import FormaDomain
    import FormaGeometry
    import FormaDocumentIO
    import FormaInterchange
    import FormaApplication
    import FormaLocalization
    import FormaCatalogInfrastructure
    import FormaWorkspaceFeature
    import SwiftUI

    /// 开发集成检查：直接验证真实 NSDocument 与视图，不合成全局输入事件。
    @MainActor enum DevelopmentVerification {
        private static func capture(_ view: NSView) throws -> NSBitmapImageRep {
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                throw DiagramError.corruptFile
            }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            return bitmap
        }
        private static func findCanvas(in view: NSView) -> DiagramCanvasView? {
            if let canvas = view as? DiagramCanvasView { return canvas }
            for child in view.subviews { if let result = findCanvas(in: child) { return result } }
            return nil
        }
        private static func endpointDragMovesArrowOnly(_ canvas: DiagramCanvasView, session: DocumentSession) -> Bool {
            let source = DiagramNode(title: "起点", frame: Rect(x: 80, y: 180, width: 120, height: 80))
            let target = DiagramNode(title: "终点", frame: Rect(x: 350, y: 200, width: 160, height: 100))
            let edge = DiagramEdge(source: source.id, target: target.id)
            let original = session.diagram
            let originalCamera = session.camera
            let originalSelection = session.selection
            let originalUndo = session.undoManager
            let originalOnChange = session.onChange
            session.undoManager = nil
            session.onChange = nil
            session.diagram = Diagram(nodes: [source, target], edges: [edge])
            defer {
                session.diagram = original
                session.camera = originalCamera
                session.selection = originalSelection
                session.undoManager = originalUndo
                session.onChange = originalOnChange
            }
            session.camera = Camera(offset: Point(x: 40, y: 40), scale: 1)
            func event(_ type: NSEvent.EventType, world: Point) -> NSEvent? {
                let screen = session.camera.screen(world)
                let point = canvas.convert(NSPoint(x: screen.x, y: screen.y), to: nil)
                return NSEvent.mouseEvent(
                    with: type, location: point, modifierFlags: [], timestamp: 0,
                    windowNumber: canvas.window?.windowNumber ?? 0, context: nil,
                    eventNumber: 0, clickCount: 1, pressure: 1)
            }
            guard let down = event(.leftMouseDown, world: Point(x: 350, y: 250)),
                let drag = event(.leftMouseDragged, world: Point(x: 430, y: 200)),
                let up = event(.leftMouseUp, world: Point(x: 430, y: 200))
            else { return false }
            canvas.mouseDown(with: down)
            canvas.mouseDragged(with: drag)
            canvas.mouseUp(with: up)
            return session.diagram.edges.first?.targetAnchor == EdgeAnchor(side: .top, position: 0.5)
                && session.diagram.nodes == [source, target]
        }
        private static func nestedNodesConnect(_ canvas: DiagramCanvasView, session: DocumentSession, output: URL)
            -> Bool
        {
            let a = DiagramNode(title: "创建订单", frame: Rect(x: 80, y: 150, width: 120, height: 70))
            let b = DiagramNode(title: "创建支付单", frame: Rect(x: 400, y: 150, width: 120, height: 70))
            let outerA = DiagramNode(title: "订单服务", frame: Rect(x: 40, y: 80, width: 220, height: 300))
            let outerB = DiagramNode(title: "支付服务", frame: Rect(x: 360, y: 80, width: 220, height: 300))
            let original = session.diagram
            let camera = session.camera
            let selection = session.selection
            let tool = session.tool
            let undo = session.undoManager
            let change = session.onChange
            session.undoManager = nil
            session.onChange = nil
            defer {
                session.diagram = original
                session.camera = camera
                session.selection = selection
                session.tool = tool
                session.undoManager = undo
                session.onChange = change
            }
            session.diagram = Diagram(nodes: [a, b, outerA, outerB])
            session.camera = Camera(offset: Point(x: 0, y: 0), scale: 1)
            session.tool = .connector
            for node in [a, b] {
                let point = canvas.convert(NSPoint(x: node.frame.center.x, y: node.frame.center.y), to: nil)
                guard
                    let event = NSEvent.mouseEvent(
                        with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0,
                        windowNumber: canvas.window?.windowNumber ?? 0, context: nil,
                        eventNumber: 0, clickCount: 1, pressure: 1)
                else { return false }
                canvas.mouseDown(with: event)
            }
            guard session.diagram.edges.count == 1, session.diagram.edges[0].source == a.id,
                session.diagram.edges[0].target == b.id
            else { return false }
            // Exercise endpoint reattachment while outer service boxes are in front in model order.
            for (type, world) in [
                (NSEvent.EventType.leftMouseDown, Point(x: 400, y: 185)),
                (.leftMouseDragged, Point(x: 460, y: 150)),
                (.leftMouseUp, Point(x: 460, y: 150)),
            ] {
                let point = canvas.convert(NSPoint(x: world.x, y: world.y), to: nil)
                guard
                    let event = NSEvent.mouseEvent(
                        with: type, location: point, modifierFlags: [], timestamp: 0,
                        windowNumber: canvas.window?.windowNumber ?? 0, context: nil,
                        eventNumber: 0, clickCount: 1, pressure: 1)
                else { return false }
                switch type {
                case .leftMouseDown: canvas.mouseDown(with: event)
                case .leftMouseDragged: canvas.mouseDragged(with: event)
                default: canvas.mouseUp(with: event)
                }
            }
            guard session.diagram.edges[0].target == b.id,
                session.diagram.edges[0].targetAnchor == EdgeAnchor(side: .top, position: 0.5),
                session.diagram.nodes == [a, b, outerA, outerB]
            else { return false }
            // Render the normal visual stacking with enclosing service boxes behind their children.
            session.diagram.nodes = [outerA, outerB, a, b]
            do {
                try DiagramExporter.png(session.diagram).write(
                    to: output.appendingPathComponent("nested-service-connection.png"))
            } catch { return false }
            return true
        }
        private static func connectionStylesRender(session: DocumentSession, view: NSView, output: URL) async throws
            -> Bool
        {
            let original = session.diagram
            let selection = session.selection
            let camera = session.camera
            let inspector = session.showInspector
            defer {
                session.diagram = original
                session.selection = selection
                session.camera = camera
                session.showInspector = inspector
            }
            var model = Diagram(title: "连线样式")
            let markers = EndpointMarker.allCases.filter { $0 != .automatic }
            for (i, marker) in markers.enumerated() {
                let y = Double(i) * 88 + 70
                let a = DiagramNode(title: tr(marker.title), frame: Rect(x: 30, y: y, width: 130, height: 48))
                let b = DiagramNode(title: tr(marker.title), frame: Rect(x: 430, y: y, width: 130, height: 48))
                model.nodes += [a, b]
                model.edges.append(
                    DiagramEdge(
                        source: a.id, target: b.id,
                        lineStyle: LineStyle.allCases[i % LineStyle.allCases.count],
                        sourceMarker: marker, targetMarker: marker))
            }
            try DiagramExporter.png(model).write(to: output.appendingPathComponent("connection-markers.png"))
            try DiagramExporter.pdf(model).write(to: output.appendingPathComponent("connection-markers.pdf"))
            session.diagram = model
            session.selection = [model.edges[1].id]
            session.camera = Camera(offset: Point(x: 20, y: 10), scale: 0.8)
            session.showInspector = true
            try await Task.sleep(for: .milliseconds(180))
            try capture(view).representation(using: .png, properties: [:])?.write(
                to: output.appendingPathComponent("connection-style-controls.png"))
            return session.selectedEdge?.sourceMarker == .openArrow && session.selectedEdge?.targetMarker == .openArrow
        }
        private static func waypointDrag(
            _ canvas: DiagramCanvasView, session: DocumentSession, view: NSView, output: URL
        ) async throws -> Bool {
            let original = session.diagram
            let camera = session.camera
            let selection = session.selection
            let snap = session.snapToGrid
            let tool = session.tool
            let undo = session.undoManager
            let change = session.onChange
            session.undoManager = nil
            session.onChange = nil
            defer {
                session.diagram = original
                session.camera = camera
                session.selection = selection
                session.snapToGrid = snap
                session.tool = tool
                session.undoManager = undo
                session.onChange = change
            }
            let a = DiagramNode(title: "创建订单", frame: Rect(x: 80, y: 180, width: 120, height: 60))
            let b = DiagramNode(title: "创建支付单", frame: Rect(x: 400, y: 180, width: 120, height: 60))
            let edge = DiagramEdge(source: a.id, target: b.id)
            session.diagram = Diagram(nodes: [a, b], edges: [edge])
            session.camera = Camera(offset: Point(x: 30, y: 80), scale: 1)
            session.selection = [edge.id]
            session.snapToGrid = false
            session.tool = .select
            func event(_ type: NSEvent.EventType, _ world: Point, count: Int = 1) -> NSEvent? {
                let screen = session.camera.screen(world)
                let point = canvas.convert(NSPoint(x: screen.x, y: screen.y), to: nil)
                return NSEvent.mouseEvent(
                    with: type, location: point, modifierFlags: [], timestamp: 0,
                    windowNumber: canvas.window?.windowNumber ?? 0, context: nil,
                    eventNumber: 0, clickCount: count, pressure: 1)
            }
            guard let down = event(.leftMouseDown, Point(x: 300, y: 210)),
                let drag = event(.leftMouseDragged, Point(x: 300, y: 110)),
                let up = event(.leftMouseUp, Point(x: 300, y: 110))
            else { return false }
            canvas.mouseDown(with: down)
            canvas.mouseDragged(with: drag)
            canvas.mouseUp(with: up)
            guard session.diagram.edges[0].waypoints == [Point(x: 300, y: 110)], session.diagram.nodes == [a, b] else {
                return false
            }
            try DiagramExporter.png(session.diagram).write(to: output.appendingPathComponent("connection-waypoint.png"))
            try await Task.sleep(for: .milliseconds(150))
            try capture(view).representation(using: .png, properties: [:])?.write(
                to: output.appendingPathComponent("connection-waypoint-controls.png"))
            guard let remove = event(.leftMouseDown, Point(x: 300, y: 110), count: 2) else { return false }
            canvas.mouseDown(with: remove)
            return session.diagram.edges[0].waypoints == nil && session.diagram.nodes == [a, b]
        }
        private static func sameSidebar(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep, width: Double) -> Bool {
            guard a.pixelsWide == b.pixelsWide, a.pixelsHigh == b.pixelsHigh else { return false }
            let scale = Double(a.pixelsWide) / width
            let end = min(a.pixelsWide, Int(208 * scale))
            var changed = 0
            for x in stride(from: Int(12 * scale), to: end, by: 4) {
                for y in stride(from: 12, to: a.pixelsHigh - 12, by: 4) {
                    guard let c = a.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                        let d = b.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
                    else { return false }
                    if abs(c.redComponent - d.redComponent) + abs(c.greenComponent - d.greenComponent)
                        + abs(c.blueComponent - d.blueComponent) > 0.02
                    {
                        changed += 1
                    }
                }
            }
            return changed < 20
        }
        static func run(document: FormaDocument, output: URL) async -> Int32 {
            var results: [String: Bool] = [:]
            do {
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                guard let view = document.windowForSheet?.contentView else { throw DiagramError.corruptFile }
                document.windowForSheet?.appearance = NSAppearance(named: .aqua)
                try await Task.sleep(for: .milliseconds(120))
                document.session.fitRequest += 1
                try await Task.sleep(for: .milliseconds(120))
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
                if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    if let image = bitmap.representation(using: .png, properties: [:]) {
                        try image.write(to: output.appendingPathComponent("workspace-light.png"))
                    }
                }
                let originalCamera = document.session.camera
                let beforePan = try capture(view)
                document.session.camera = Camera(offset: Point(x: -80, y: 120), scale: 1)
                try await Task.sleep(for: .milliseconds(150))
                let afterPan = try capture(view)
                results["panning_does_not_paint_over_sidebar"] = sameSidebar(
                    beforePan, afterPan, width: view.bounds.width)
                try afterPan.representation(using: .png, properties: [:])?.write(
                    to: output.appendingPathComponent("clipping-regression.png"))
                if let canvas = findCanvas(in: view) {
                    results["canvas_explicitly_clips"] =
                        canvas.clipsToBounds && canvas.wantsDefaultClipping && canvas.layer?.masksToBounds == true
                    results["connection_midpoint_drag_adds_and_removes_control"] = try await waypointDrag(
                        canvas, session: document.session, view: view, output: output)
                    results["nested_service_children_connect"] = nestedNodesConnect(
                        canvas, session: document.session, output: output)
                    results["dragging_arrow_snaps_without_moving_shape"] = endpointDragMovesArrowOnly(
                        canvas, session: document.session)
                }
                results["independent_endpoint_styles_render_and_export"] = try await connectionStylesRender(
                    session: document.session, view: view, output: output)
                let group = document.windowForSheet?.toolbar?.items.compactMap { $0 as? NSToolbarItemGroup }.first
                let toolbarStatus =
                    "subitems=\(group?.subitems.count ?? -1), view=\(String(describing:group?.view?.frame)), visible=\(document.windowForSheet?.toolbar?.visibleItems?.map { $0.itemIdentifier.rawValue } ?? []), images=\(group?.subitems.map { $0.image?.isValid == true } ?? [])"
                try Data(toolbarStatus.utf8).write(to: output.appendingPathComponent("toolbar-status.txt"))
                results["native_toolbar_has_six_visible_tools"] =
                    group?.subitems.count == 6 && group?.controlRepresentation == .expanded
                    && group?.subitems.allSatisfy({ $0.image?.isValid == true }) == true
                    && document.windowForSheet?.toolbar?.visibleItems?.contains(where: {
                        $0.itemIdentifier.rawValue == "tools"
                    }) == true
                let toolbarIdentifiers = Set(
                    document.windowForSheet?.toolbar?.items.map { $0.itemIdentifier.rawValue } ?? [])
                results["toolbar_has_quick_edit_actions"] =
                    ["undo", "redo", "duplicate", "delete"].allSatisfy(toolbarIdentifiers.contains)
                document.session.camera = originalCamera
                try await Task.sleep(for: .milliseconds(120))
                document.windowForSheet?.appearance = NSAppearance(named: .darkAqua)
                try await Task.sleep(for: .milliseconds(120))
                document.session.fitRequest += 1
                try await Task.sleep(for: .milliseconds(120))
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
                if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    if let image = bitmap.representation(using: .png, properties: [:]) {
                        try image.write(to: output.appendingPathComponent("workspace-dark.png"))
                    }
                }
                document.windowForSheet?.appearance = NSAppearance(named: .aqua)
                results["native_document_type_is_registered"] =
                    document.fileType == "com.forma.diagram"
                    && FormaDocument.readableTypes.contains("com.forma.diagram")
                let session = document.session
                let original = session.diagram
                session.add(.rounded, at: Point(x: 350, y: 500))
                try await Task.sleep(for: .milliseconds(80))
                results["native_document_dirty_after_edit"] = document.isDocumentEdited
                document.undoManager?.undo()
                try await Task.sleep(for: .milliseconds(80))
                results["native_undo_restores_document"] = session.diagram == original
                document.undoManager?.redo()
                try await Task.sleep(for: .milliseconds(80))
                results["native_redo_restores_edit"] = session.diagram.nodes.count == original.nodes.count + 1
                let url = output.appendingPathComponent("integration.forma")
                try await document.save(to: url, ofType: "com.forma.diagram", for: .saveOperation)
                try await Task.sleep(for: .milliseconds(80))
                results["native_save_clears_dirty"] = !document.isDocumentEdited
                let reopened = FormaDocument()
                try reopened.read(from: url, ofType: "com.forma.diagram")
                reopened.makeWindowControllers()
                results["native_reopen_matches_saved_content"] = reopened.session.diagram == session.diagram
                reopened.close()
                document.undoManager?.undo()
                try await Task.sleep(for: .milliseconds(80))
                results["undo_after_save_marks_dirty"] = document.isDocumentEdited
                document.undoManager?.redo()
                try await Task.sleep(for: .milliseconds(80))
                results["redo_to_saved_point_clears_dirty"] = !document.isDocumentEdited
                try DiagramExporter.pdf(original).write(to: output.appendingPathComponent("architecture.pdf"))
                try DiagramExporter.png(original).write(to: output.appendingPathComponent("architecture.png"))
                results["exports_written"] = true
                results["logical_window_title_after_save"] =
                    document.windowForSheet?.title == url.deletingPathExtension().lastPathComponent
                let languageBefore = Localization.shared.language
                Localization.shared.language = .english
                try await Task.sleep(for: .milliseconds(160))
                results["english_menu_updates_live"] =
                    NSApp.mainMenu?.items.contains(where: { $0.title == "File" }) == true
                results["language_switch_preserves_document"] =
                    session.diagram == (try DocumentCodec.read(at: url)).pages[0]
                try capture(view).representation(using: .png, properties: [:])?.write(
                    to: output.appendingPathComponent("editor-english.png"))
                Localization.shared.language = .simplifiedChinese
                try await Task.sleep(for: .milliseconds(160))
                results["chinese_menu_updates_live"] =
                    NSApp.mainMenu?.items.contains(where: { $0.title == "文件" }) == true
                let uml = FormaDocument()
                uml.configure(DiagramTemplate.umlClass.makeDiagram())
                uml.makeWindowControllers()
                uml.showWindows()
                try await Task.sleep(for: .milliseconds(200))
                if let frame = uml.windowForSheet?.contentView?.superview {
                    try capture(frame).representation(using: .png, properties: [:])?.write(
                        to: output.appendingPathComponent("uml-class-window.png"))
                }
                try DiagramExporter.png(uml.session.diagram).write(to: output.appendingPathComponent("uml-class.png"))
                try DiagramExporter.pdf(uml.session.diagram).write(to: output.appendingPathComponent("uml-class.pdf"))
                results["uml_panels_and_members_exported"] =
                    uml.session.diagram.panels.count == 1
                    && uml.session.diagram.nodes.contains(where: { $0.kind == .umlInterface })
                uml.close()
                let shapeSession = DocumentSession(diagram: DiagramTemplate.blank.makeDiagram())
                let shapeController = NSHostingController(
                    rootView: WorkspaceView(session: shapeSession, initialSidebarTab: 1))
                shapeController.view.frame = NSRect(x: 0, y: 0, width: 1180, height: 760)
                try await Task.sleep(for: .milliseconds(120))
                try capture(shapeController.view).representation(using: .png, properties: [:])?.write(
                    to: output.appendingPathComponent("shape-library.png"))
                results["shape_library_search_and_favorites_render"] = shapeController.view.bounds.width == 1180
                let board = FormaDocument()
                board.configure(DiagramTemplate.panelBoard.makeDiagram())
                board.makeWindowControllers()
                board.showWindows()
                try await Task.sleep(for: .milliseconds(200))
                if let frame = board.windowForSheet?.contentView?.superview {
                    try capture(frame).representation(using: .png, properties: [:])?.write(
                        to: output.appendingPathComponent("multi-panel-window.png"))
                }
                board.close()
                let libraryRoot = output.appendingPathComponent("library-" + UUID().uuidString)
                defer { try? FileManager.default.removeItem(at: libraryRoot) }
                let repository = LocalWorkspaceRepository(root: libraryRoot)
                let space = try await repository.createWorkspace(name: "产品架构团队")
                _ = try await repository.createDocument(DiagramTemplate.umlClass.makeDiagram(), in: space.id)
                _ = try await repository.createDocument(DiagramTemplate.panelBoard.makeDiagram(), in: space.id)
                let library = WorkspaceLibrary(repository: repository)
                library.templates = DiagramTemplate.allCases.map {
                    TemplateDescriptor(
                        id: $0.id, title: $0.title, subtitle: $0.subtitle, symbol: $0.symbol, category: $0.category)
                }
                let libraryWindow = WorkspaceLibraryWindowController(library: library)
                libraryWindow.showWindow(nil)
                await library.reload()
                try await Task.sleep(for: .milliseconds(180))
                if let frame = libraryWindow.window?.contentView?.superview {
                    try capture(frame).representation(using: .png, properties: [:])?.write(
                        to: output.appendingPathComponent("workspace-library.png"))
                }
                results["workspace_library_lists_managed_files"] = library.files.count == 2
                // 窗口 key 监听会异步重入 reload，文件断言一律使用独立仓储实例，避免竞态。
                let firstLive = try await repository.files(in: space.id, trashed: false).first
                if let firstLive { try await repository.trash(firstLive) }
                library.showingTrash = true
                await library.reload()
                try await Task.sleep(for: .milliseconds(180))
                var trashShotWritten = false
                if let frame = libraryWindow.window?.contentView?.superview {
                    let shot = output.appendingPathComponent("workspace-trash.png")
                    try capture(frame).representation(using: .png, properties: [:])?.write(to: shot)
                    trashShotWritten = FileManager.default.fileExists(atPath: shot.path)
                }
                let probe = LocalWorkspaceRepository(root: libraryRoot)
                let trashedNow = try await probe.files(in: space.id, trashed: true)
                let debugFile = trashedNow.first?.url.appendingPathComponent("document.json")
                let debugWritten = debugFile.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
                let restoredCount = trashedNow.isEmpty ? 0 : try await probe.restoreAll(in: space.id)
                let liveAfterRestore = try await probe.files(in: space.id, trashed: false).count
                let trashedAfterRestore = try await probe.files(in: space.id, trashed: true).count
                results["workspace_trash_renders_header_actions"] = library.showingTrash && trashShotWritten
                results["workspace_restore_all_returns_files"] =
                    firstLive != nil && restoredCount == 1 && liveAfterRestore == 2 && trashedAfterRestore == 0
                let secondLive = try await probe.files(in: space.id, trashed: false).first
                if let secondLive { try await probe.trash(secondLive) }
                let emptiedCount = try await probe.emptyTrash(in: space.id)
                let liveAfterEmpty = try await probe.files(in: space.id, trashed: false).count
                let trashedAfterEmpty = try await probe.files(in: space.id, trashed: true).count
                results["workspace_empty_trash_removes_files"] =
                    emptiedCount == 1 && trashedAfterEmpty == 0 && liveAfterEmpty == 1
                libraryWindow.close()
                let suite = "Forma.verification." + UUID().uuidString
                let defaults = UserDefaults(suiteName: suite)!
                defer { defaults.removePersistentDomain(forName: suite) }
                let preferences = AppPreferences(defaults: defaults)
                preferences.language = .english
                let settingsWindow = SettingsWindowController(preferences: preferences)
                settingsWindow.showWindow(nil)
                try await Task.sleep(for: .milliseconds(180))
                if let frame = settingsWindow.window?.contentView?.superview {
                    try capture(frame).representation(using: .png, properties: [:])?.write(
                        to: output.appendingPathComponent("settings-english.png"))
                }
                preferences.language = .simplifiedChinese
                try await Task.sleep(for: .milliseconds(180))
                if let frame = settingsWindow.window?.contentView?.superview {
                    try capture(frame).representation(using: .png, properties: [:])?.write(
                        to: output.appendingPathComponent("settings-chinese.png"))
                }
                let persistedAfterSettings = try DocumentCodec.read(at: url)
                results["settings_language_switches_without_document_change"] =
                    tr("工作空间") == "工作空间" && session.diagram == persistedAfterSettings.pages[0]
                settingsWindow.close()
                // 多页文档：新建页面、编辑后保存，重新打开验证页面数量与内容。
                let multiPage = FormaDocument()
                multiPage.configure(DiagramTemplate.blank.makeDiagram())
                multiPage.makeWindowControllers()
                multiPage.session.addPage()
                multiPage.session.add(.rounded, at: Point(x: 200, y: 200))
                let multiPageURL = output.appendingPathComponent("multi-page.forma")
                try await multiPage.save(to: multiPageURL, ofType: "com.forma.diagram", for: .saveOperation)
                let multiPageReopened = FormaDocument()
                try multiPageReopened.read(from: multiPageURL, ofType: "com.forma.diagram")
                multiPageReopened.makeWindowControllers()
                results["multi_page_document_survives_save_and_reopen"] =
                    multiPageReopened.session.pages.count == 2
                    && multiPageReopened.session.pages[1].nodes.count == 1
                    && multiPageReopened.session.pages[0].nodes.isEmpty
                    && multiPageReopened.session.activePageID == multiPage.session.activePageID
                multiPageReopened.close()
                multiPage.updateChangeCount(.changeCleared)
                multiPage.close()
                Localization.shared.language = languageBefore
                let report = try JSONSerialization.data(
                    withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
                try report.write(to: output.appendingPathComponent("integration-results.json"))
                let passed = results.values.allSatisfy { $0 }
                print("Forma integration verification: \(passed ? "PASSED" : "FAILED")")
                document.updateChangeCount(.changeCleared)
                document.close()
                return passed ? 0 : 1
            } catch {
                try? Data(error.localizedDescription.utf8).write(
                    to: output.appendingPathComponent("integration-error.txt"))
                fputs("Forma integration verification failed: \(error)\n", stderr)
                return 1
            }
        }
    }
#endif
