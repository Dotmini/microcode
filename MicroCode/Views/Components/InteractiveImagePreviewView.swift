//
//  InteractiveImagePreviewView.swift
//  MicroCode
//
//  Rich Image Viewer with Pan, Zoom, Metadata, and Region Selection Commenting
//  Copyright © 2026 AIPRENEUR. All rights reserved.
//

import SwiftUI
import AppKit

struct InteractiveImagePreviewView: View {
    let url: URL
    
    @State private var image: NSImage?
    @State private var imageSize: CGSize = .zero
    @State private var fileSizeString: String = ""
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    
    // Selection state in image coordinates
    @State private var dragStart: CGPoint? = nil
    @State private var currentDrag: CGPoint? = nil
    @State private var selectedRect: CGRect? = nil
    @State private var commentText: String = ""
    @State private var isShowingCommentPopover: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Sub-header Bar (Matching Modern IDE Workspace)
            HStack(spacing: 8) {
                // File Size Pill
                HStack(spacing: 5) {
                    Image(systemName: "photo")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    if !fileSizeString.isEmpty {
                        Text(fileSizeString)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(4)
                
                Spacer()
                
                // Zoom Controls
                HStack(spacing: 2) {
                    Button(action: { scale = max(0.1, scale - 0.2) }) {
                        Image(systemName: "minus.magnifyingglass")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .padding(4)
                    
                    Text("\(Int(scale * 100))%")
                        .font(.system(size: 9, design: .monospaced))
                        .frame(width: 36)
                    
                    Button(action: { scale = min(6.0, scale + 0.2) }) {
                        Image(systemName: "plus.magnifyingglass")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .padding(4)
                    
                    Button(action: { scale = 1.0; offset = .zero }) {
                        Text("Fit")
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 4)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(4)
                
                // Menu actions
                Menu {
                    Button("Copy Image") {
                        if let img = image {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.writeObjects([img])
                        }
                    }
                    Button("Copy File Path") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url.path, forType: .string)
                    }
                    Divider()
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    Button("Open in Default App") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .padding(4)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 18)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
            
            Divider()
            
            // Main Image Canvas
            GeometryReader { geo in
                ZStack {
                    Color(nsColor: .textBackgroundColor).opacity(0.85)
                    
                    if let img = image {
                        ZStack(alignment: .topLeading) {
                            Image(nsImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .scaleEffect(scale)
                                .offset(offset)
                                .gesture(
                                    DragGesture(minimumDistance: 2)
                                        .onChanged { value in
                                            if NSEvent.modifierFlags.contains(.option) {
                                                offset = CGSize(
                                                    width: offset.width + value.translation.width * 0.1,
                                                    height: offset.height + value.translation.height * 0.1
                                                )
                                            } else {
                                                if dragStart == nil {
                                                    dragStart = value.startLocation
                                                }
                                                currentDrag = value.location
                                                updateSelection(start: value.startLocation, current: value.location)
                                            }
                                        }
                                        .onEnded { _ in
                                            dragStart = nil
                                            currentDrag = nil
                                            if let r = selectedRect, r.width > 15 && r.height > 15 {
                                                isShowingCommentPopover = true
                                            } else {
                                                selectedRect = nil
                                            }
                                        }
                                )
                            
                            // Region Selection Overlay Box
                            if let rect = selectedRect {
                                ZStack(alignment: .topTrailing) {
                                    Rectangle()
                                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                                        .background(Color.accentColor.opacity(0.12))
                                        .frame(width: rect.width, height: rect.height)
                                        .position(x: rect.midX, y: rect.midY)
                                    
                                    // Region Tag & Comment Trigger
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "bubble.left.fill")
                                                .font(.system(size: 8))
                                            Text("Comment")
                                                .font(.system(size: 9, weight: .semibold))
                                            Spacer(minLength: 4)
                                            Button {
                                                selectedRect = nil
                                                commentText = ""
                                            } label: {
                                                Image(systemName: "xmark")
                                                    .font(.system(size: 8, weight: .bold))
                                                    .foregroundColor(.white.opacity(0.8))
                                            }
                                            .buttonStyle(.plain)
                                            .help("Dismiss selection")
                                        }
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.black.opacity(0.75))
                                        .foregroundColor(.white)
                                        .cornerRadius(3)
                                        
                                        // Quick Send to Agent Box
                                        HStack(spacing: 4) {
                                            TextField("Note to agent…", text: $commentText)
                                                .textFieldStyle(.plain)
                                                .font(.system(size: 10))
                                                .frame(width: 140)
                                                .padding(4)
                                                .background(Color(nsColor: .windowBackgroundColor))
                                                .cornerRadius(4)
                                                .onSubmit {
                                                    sendRegionToAgent(rect: rect)
                                                }
                                            
                                            Button {
                                                sendRegionToAgent(rect: rect)
                                            } label: {
                                                Image(systemName: "paperplane.fill")
                                                    .font(.system(size: 9))
                                                    .foregroundColor(.white)
                                                    .padding(5)
                                                    .background(Color.accentColor)
                                                    .cornerRadius(4)
                                            }
                                            .buttonStyle(.plain)
                                            .help("Send region instruction to AI Agent")
                                        }
                                        .padding(4)
                                        .background(.ultraThinMaterial)
                                        .cornerRadius(6)
                                        .shadow(radius: 4)
                                    }
                                    .position(x: min(max(rect.midX, 90), geo.size.width - 90), y: max(rect.minY - 30, 40))
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Loading image...")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .onAppear {
            loadImage()
        }
        .onChange(of: url) { _ in
            loadImage()
        }
    }
    
    private func updateSelection(start: CGPoint, current: CGPoint) {
        let x = min(start.x, current.x)
        let y = min(start.y, current.y)
        let width = abs(current.x - start.x)
        let height = abs(current.y - start.y)
        selectedRect = CGRect(x: x, y: y, width: width, height: height)
    }
    
    private func sendRegionToAgent(rect: CGRect) {
        let fileName = url.lastPathComponent
        let comment = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt: String
        if comment.isEmpty {
            prompt = "Regarding region [\(Int(rect.minX)), \(Int(rect.minY)), \(Int(rect.width))×\(Int(rect.height))] in `\(fileName)`: Please inspect and advise."
        } else {
            prompt = "Regarding region [\(Int(rect.minX)), \(Int(rect.minY)), \(Int(rect.width))×\(Int(rect.height))] in `\(fileName)`: \(comment)"
        }
        
        PreviewDockService.shared.sendRegionCommentToAgent(comment: prompt)
        commentText = ""
        selectedRect = nil
    }
    
    private func loadImage() {
        DispatchQueue.global(qos: .userInitiated).async {
            if let img = NSImage(contentsOf: url) {
                let size = img.size
                var sizeText = ""
                if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                   let bytes = attrs[.size] as? Int64 {
                    sizeText = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
                }
                
                DispatchQueue.main.async {
                    self.image = img
                    self.imageSize = size
                    self.fileSizeString = sizeText
                }
            }
        }
    }
}
