import AppKit
import Testing
import UniformTypeIdentifiers
@testable import Compositor

@MainActor
struct TextActionBoundaryTests {
    private func draft(_ content: String = "Pending") -> EditorSession {
        let session = EditorSession()
        session.createDocument(width: 320, height: 240, emptyLayer: true)
        session.beginText(at: CGPoint(x: 40, y: 50))
        session.textDraft?.style.content = content
        return session
    }

    @Test func layerAndSelectionCommandsCommitBeforeChangingTheDocument() throws {
        let session = draft()
        #expect(!session.canEditLayers && session.canRequestLayerEdit)
        session.addBlankLayer()
        #expect(session.textDraft == nil)
        #expect(session.document?.layers.count == 3)
        #expect(session.document?.layers.contains(where: { $0.liveText?.style.content == "Pending" }) == true)
        session.undo()
        #expect(session.activeLayer?.liveText?.style.content == "Pending")

        session.editActiveText()
        session.textDraft?.style.content = "Selected"
        session.selectAll()
        #expect(session.textDraft == nil)
        #expect(session.activeLayer?.liveText?.style.content == "Selected")
        #expect(session.selection != nil)
    }

    @Test func failedFinishRetainsDraftAndStopsLayerAction() {
        let session = draft()
        session.textDraft?.style.fontSize = .nan
        let before = session.document?.layers.count
        session.addBlankLayer()
        #expect(session.textDraft != nil)
        #expect(session.document?.layers.count == before)
        #expect(session.brushError != nil)
    }

    @Test func genuineBusyStateStillBlocksTheRequest() {
        let session = draft()
        let count = session.document?.layers.count
        session.isProjectBusy = true
        #expect(!session.canRequestLayerEdit)
        session.addBlankLayer()
        #expect(session.textDraft != nil)
        #expect(session.document?.layers.count == count)
        session.isProjectBusy = false
    }

    @Test func imageImportFinishesTextBeforeStartingDecode() async throws {
        let source = try ImageImportTests().fixture(.png)
        defer { try? FileManager.default.removeItem(at: source) }
        let session = draft("Keep this text")
        await session.importImages([source])
        #expect(session.textDraft == nil)
        #expect(session.document?.layers.contains(where: { $0.liveText?.style.content == "Keep this text" }) == true)
        #expect(session.document?.layers.contains(where: { $0.asset != nil && $0.liveText == nil }) == true)
    }

    @Test func finderAndDropImportsFinishTextBeforeRouting() async throws {
        let source = try ImageImportTests().fixture(.png)
        defer { try? FileManager.default.removeItem(at: source) }
        let workspace = ProjectWorkspace()
        let first = workspace.current
        first.session.createDocument(width: 320, height: 240, emptyLayer: true)
        first.session.beginText(at: CGPoint(x: 40, y: 50))
        first.session.textDraft?.style.content = "Before Finder"
        await workspace.receive([source])
        #expect(first.session.textDraft == nil)
        #expect(first.session.document?.layers.contains(where: { $0.liveText?.style.content == "Before Finder" }) == true)
        #expect(workspace.tabs.count == 2)

        workspace.select(first.id)
        first.session.editActiveText()
        first.session.textDraft?.style.content = "Before drop"
        let provider = NSItemProvider(item: source as NSURL, typeIdentifier: UTType.fileURL.identifier)
        await workspace.receiveProviders([provider], into: first.id)
        #expect(first.session.textDraft == nil)
        #expect(first.session.document?.layers.contains(where: { $0.liveText?.style.content == "Before drop" }) == true)
        #expect(first.session.document?.layers.contains(where: { $0.asset != nil && $0.liveText == nil && $0.name != "Layer 1" }) == true)
    }

    @Test func saveCapturesTheLatestTextDraft() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CompositorTextBoundary-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = draft("Saved draft")
        let url = root.appendingPathComponent("Text.comp")
        session.projectURL = url
        let controller = ProjectController(session: session)
        #expect(await controller.save())
        #expect(session.textDraft == nil)
        let loaded = try await ProjectStore.shared.load(from: url)
        #expect(loaded.manifest.layers.contains(where: { $0.text?.content == "Saved draft" }))
    }

    @Test func editingExistingTextThenFilteringKeepsTheEditedVersionInUndo() async throws {
        let session = draft("Original")
        #expect(session.finishText())
        session.editActiveText()
        session.textDraft?.style.content = "Edited before blur"
        session.beginFilter(.gaussianBlur)
        #expect(session.textDraft == nil)
        #expect(session.activeLayer?.liveText?.style.content == "Edited before blur")
        #expect(session.filterEdit?.original.image === session.activeLayer?.asset?.image)
        let filter = try #require(session.filterEdit)
        filter.settings.radius = 2
        await session.commitFilter()
        #expect(session.activeLayer?.liveText == nil)
        session.undo()
        #expect(session.activeLayer?.liveText?.style.content == "Edited before blur")
        session.undo()
        #expect(session.activeLayer?.liveText?.style.content == "Original")
    }

    @Test func filteringNewTextStartsFromItsCommittedPixels() async throws {
        let session = draft("New text before blur")
        session.beginFilter(.gaussianBlur)
        #expect(session.textDraft == nil)
        #expect(session.activeLayer?.liveText?.style.content == "New text before blur")
        #expect(session.filterEdit?.original.image === session.activeLayer?.asset?.image)
        let filter = try #require(session.filterEdit)
        filter.settings.radius = 2
        await session.commitFilter()
        #expect(session.activeLayer?.liveText == nil)
        session.undo()
        #expect(session.activeLayer?.liveText?.style.content == "New text before blur")
    }
}
