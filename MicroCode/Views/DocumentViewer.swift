//
//  DocumentViewer.swift
//  MicroCode
//
//  A versatile document viewer for PDF and Image files with PiP support.
//  Copyright © 2025 SPU AI CLUB. All rights reserved.
//

import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import AppKit

// MARK: - PiP Window Manager (Native NSWindow)
class PiPWindowManager {
    static let shared = PiPWindowManager()
    
    private var pipWindow: NSWindow?
    private var onCloseCallback: (() -> Void)?
    
    private init() {}
    
    func show(documentURL: URL?, onClose: @escaping () -> Void) {
        // Close existing window if any
        close()
        
        self.onCloseCallback = onClose
        
        // Create the window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 520),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window.title = documentURL?.lastPathComponent ?? "Document"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.delegate = WindowCloseDelegate(onClose: { [weak self] in
            self?.onCloseCallback?()
            self?.pipWindow = nil
        })
        
        // Create SwiftUI content
        let contentView = PiPWindowContent(documentURL: documentURL, onClose: { [weak self] in
            self?.close()
        })
        
        window.contentView = NSHostingView(rootView: contentView)
        
        // Position at top-right of screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowFrame = window.frame
            let x = screenFrame.maxX - windowFrame.width - 50
            let y = screenFrame.maxY - windowFrame.height - 50
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        window.makeKeyAndOrderFront(nil)
        self.pipWindow = window
    }
    
    func close() {
        pipWindow?.close()
        pipWindow = nil
    }
}

// MARK: - Window Close Delegate
private class WindowCloseDelegate: NSObject, NSWindowDelegate {
    let onClose: () -> Void
    
    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }
    
    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

// MARK: - PiP Window Content
struct PiPWindowContent: View {
    let documentURL: URL?
    let onClose: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar with Dock button
            HStack {
                Text(documentURL?.lastPathComponent ?? "Document")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                Spacer()
                
                // Dock button - return to side panel
                Button(action: { onClose() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "rectangle.lefthalf.inset.filled")
                        Text("Dock")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .help("Return to side panel mode")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Content
            if let url = documentURL {
                if url.pathExtension.lowercased() == "pdf" {
                    PDFKitRepresentedView(url: url)
                } else {
                    DocumentImagePreviewView(url: url)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No Document")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 300, minHeight: 400)
    }
}


struct DocumentViewer: View {
    @Binding var documentURL: URL?
    @Binding var isPiPActive: Bool
    
    @State private var isHovering = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header / Toolbar
            HStack {
                Text(documentURL?.lastPathComponent ?? "Document Viewer")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                if documentURL != nil {
                    Button(action: { closeDocument() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Close Document")
                    
                    Divider()
                        .frame(height: 16)
                }
                
                Button(action: { selectDocument() }) {
                    Image(systemName: "folder.fill")
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .help("Open Document (PDF/Image)")
                
                Button(action: { isPiPActive.toggle() }) {
                    Image(systemName: isPiPActive ? "rectangle.on.rectangle.angled.fill" : "rectangle.on.rectangle")
                        .foregroundColor(isPiPActive ? .orange : .secondary)
                }
                .buttonStyle(.plain)
                .help(isPiPActive ? "Dock Window" : "Float Window")
            }
            .padding(10)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Content
            ZStack {
                if let url = documentURL {
                    if isPDF(url) {
                        PDFKitRepresentedView(url: url)
                    } else if isImage(url) {
                        ImagePreviewView(url: url)
                    } else {
                        Text("Unsupported file format")
                            .foregroundColor(.secondary)
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary.opacity(0.5))
                        
                        Text("No Document Selected")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Button("Open File...") {
                            selectDocument()
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 200, idealWidth: 350, maxWidth: .infinity, maxHeight: .infinity)
        .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))
        .onDrop(of: [.pdf, .image], isTargeted: $isHovering) { providers in
            loadDroppedFile(from: providers)
        }
    }
    
    private func selectDocument() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf, .image, .png, .jpeg, .tiff]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                self.documentURL = url
            }
        }
    }
    
    private func closeDocument() {
        self.documentURL = nil
    }
    
    private func isPDF(_ url: URL) -> Bool {
        return url.pathExtension.lowercased() == "pdf"
    }
    
    private func isImage(_ url: URL) -> Bool {
        let imageExtensions = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "heic"]
        return imageExtensions.contains(url.pathExtension.lowercased())
    }
    
    private func loadDroppedFile(from providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        
        provider.loadItem(forTypeIdentifier: UTType.item.identifier, options: nil) { (item, error) in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else {
                // Try to get URL directly
                if let url = item as? URL {
                    DispatchQueue.main.async {
                        self.documentURL = url
                    }
                }
                return
            }
            // If needed, handle data-based drops, but file URL drops are standard for Finder
        }
        return true
    }
}

// MARK: - PDF Support
struct PDFKitRepresentedView: NSViewRepresentable {
    let url: URL
    
    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = PDFDocument(url: url)
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        return pdfView
    }
    
    func updateNSView(_ pdfView: PDFView, context: Context) {
        if pdfView.document?.documentURL != url {
            pdfView.document = PDFDocument(url: url)
        }
    }
}

// MARK: - Image Support
struct DocumentImagePreviewView: View {
    let url: URL
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical]) {
                if let nsImage = NSImage(contentsOf: url) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
                } else {
                    Text("Could not load image")
                        .foregroundColor(.red)
                }
            }
        }
    }
}

// MARK: - PiP Document Window (Proper Floating Panel)
struct PiPDocumentWindow: View {
    @Binding var documentURL: URL?
    @Binding var isPiPActive: Bool
    
    @State private var position = CGSize.zero
    @State private var dragOffset = CGSize.zero
    @State private var isDragging = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Drag Handle Bar - This is the only draggable area
            HStack {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(documentURL?.lastPathComponent ?? "Document")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                Spacer()
                
                Button(action: { isPiPActive = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.95))
            
            Divider()
            
            // Document Content
            DocumentViewer(documentURL: $documentURL, isPiPActive: $isPiPActive)
                .frame(height: 450)
        }
        .frame(width: 380)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow))
        .cornerRadius(12)
        .shadow(color: .black.opacity(isDragging ? 0.4 : 0.25), radius: isDragging ? 30 : 15, x: 0, y: isDragging ? 15 : 8)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .offset(x: position.width + dragOffset.width, y: position.height + dragOffset.height)
        .gesture(
            DragGesture()
                .onChanged { value in
                    isDragging = true
                    dragOffset = value.translation
                }
                .onEnded { value in
                    isDragging = false
                    position.width += value.translation.width
                    position.height += value.translation.height
                    dragOffset = .zero
                }
        )
        .padding(20)
        .animation(.interactiveSpring(), value: isDragging)
    }
}

// MARK: - Legacy Draggable Viewer (Deprecated)
struct DraggableDocumentViewer: View {
    @Binding var documentURL: URL?
    @Binding var isPiPActive: Bool
    
    var body: some View {
        PiPDocumentWindow(documentURL: $documentURL, isPiPActive: $isPiPActive)
    }
}
