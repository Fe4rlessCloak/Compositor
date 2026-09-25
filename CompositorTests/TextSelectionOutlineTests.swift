import AppKit
import Testing
@testable import Compositor

@MainActor
struct TextSelectionOutlineTests {
    private func editor(zoom: CGFloat, rotation: CGFloat = 0, flipX: Bool = false, flipY: Bool = false)
        throws -> (EditorSession, CanvasView, InlineTextEditor, NSWindow) {
        let session = EditorSession()
        session.createDocument(width: 800, height: 600, emptyLayer: true)
        session.selectTool(.type)
        let view = CanvasView(session: session)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        session.viewport.resize(to: view.bounds.size, backingScale: 1, documentSize: CGSize(width: 800, height: 600))
        session.zoom(to: zoom)
        session.beginText(at: CGPoint(x: 350, y: 280))
        session.textDraft?.style.content = "Outline\nSelection"
        session.textDraft?.style.fontSize = 48
        var transform = LayerTransform(origin: CGPoint(x: 338, y: 200), size: CGSize(width: 260, height: 100))
        transform.rotation = rotation
        transform.flipX = flipX
        transform.flipY = flipY
        session.textDraft?.transform = transform
        view.synchronizeDisplay()
        let editor = try #require(view.inlineTextEditor)
        editor.textView.setSelectedRange(NSRange(location: 0, length: "Outline\nSelection".utf16.count))
        editor.textView.needsDisplay = true
        window.displayIfNeeded()
        return (session, view, editor, window)
    }

    private func bitmap(of view: NSView) throws -> NSBitmapImageRep {
        view.needsDisplay = true
        view.displayIfNeeded()
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    @Test(arguments: [1.0, 3.0] as [CGFloat])
    func selectionOutlineRendersAtDifferentCanvasZooms(zoom: CGFloat) throws {
        let (_, view, editor, _) = try editor(zoom: zoom)
        let selected = try bitmap(of: editor.textView)
        #expect(editor.textView.selectedRange() == NSRange(location: 0, length: "Outline\nSelection".utf16.count))
        let layout = try #require(editor.textView.layoutManager)
        let container = try #require(editor.textView.textContainer)
        layout.ensureLayout(for: container)
        let glyphs = layout.glyphRange(forCharacterRange: editor.textView.selectedRange(), actualCharacterRange: nil)
        #expect(glyphs.length > 0)
        #expect(!layout.boundingRect(forGlyphRange: glyphs, in: container).isEmpty)
        #expect(editor.textView.selectedTextAttributes[.backgroundColor] == nil)
        let pixels = try #require(selected.bitmapData)
        let alpha = stride(from: 3, to: selected.bytesPerRow * selected.pixelsHigh, by: 4)
            .reduce(into: 0) { count, offset in if pixels[offset] > 0 { count += 1 } }
        #expect(alpha > 0, "the selected text should have a visible outline at zoom \(zoom)")
        let directory = URL(fileURLWithPath: "/private/tmp/compositor-text-selection-outline", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("zoom-\(zoom)x.png")
        try #require(try bitmap(of: view).representation(using: .png, properties: [:])).write(to: file)
    }

    @Test func rotatedFlippedSelectionRemainsAlignedAndWritesPreviewArtifact() throws {
        let (session, view, editor, _) = try editor(zoom: 2.5, rotation: 31, flipX: true, flipY: true)
        session.changeTextStyle { $0.fontSize = 56; $0.red = 0.8; $0.green = 0.1; $0.blue = 0.2 }
        view.synchronizeDisplay()
        #expect(editor.textView.selectedRange() == NSRange(location: 0, length: "Outline\nSelection".utf16.count))
        let selected = try bitmap(of: editor.textView)
        editor.textView.setSelectedRange(NSRange(location: 0, length: 0))
        let unselected = try bitmap(of: editor.textView)
        #expect(selected.tiffRepresentation != unselected.tiffRepresentation)

        // Keep one canvas-level visual artifact for review, including its rotated/flipped editor box.
        editor.textView.setSelectedRange(NSRange(location: 0, length: "Outline\nSelection".utf16.count))
        view.synchronizeDisplay()
        let canvas = try bitmap(of: view)
        let directory = URL(fileURLWithPath: "/private/tmp/compositor-text-selection-outline", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("rotated-flipped-zoom-2.5x.png")
        try #require(canvas.representation(using: .png, properties: [:])).write(to: file)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }
}
