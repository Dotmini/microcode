//
//  InteractiveImagePreviewView.swift
//  MicroCode
//
//  Rich Image Viewer with Pan, Zoom, Metadata, and Region Selection Commenting
//  Copyright © 2026 Dotmini Company Limited. All rights reserved.
//

import SwiftUI
import AppKit

struct ImageInspectRegion: Identifiable, Equatable {
    var id = UUID()
    var rect: CGRect
    var note: String = ""
}

struct InteractiveImagePreviewView: View {
    let url: URL
    
    @State private var image: NSImage?
    @State private var imageSize: CGSize = .zero
    @State private var fileSizeString: String = ""
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    
    // Multi-region selection state in image canvas coordinates
    @State private var dragStart: CGPoint? = nil
    @State private var currentDrag: CGPoint? = nil
    @State private var activeDraftRect: CGRect? = nil
    @State private var selectedRegions: [ImageInspectRegion] = []
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
                                            if let r = activeDraftRect, r.width > 15 && r.height > 15 {
                                                selectedRegions.append(ImageInspectRegion(rect: r))
                                                activeDraftRect = nil
                                                isShowingCommentPopover = true
                                            } else {
                                                activeDraftRect = nil
                                            }
                                        }
                                )
                            
                            // Active Dragging Marquee Box
                            if let draft = activeDraftRect {
                                Rectangle()
                                    .stroke(Color.primary, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                                    .background(Color.primary.opacity(0.08))
                                    .frame(width: draft.width, height: draft.height)
                                    .position(x: draft.midX, y: draft.midY)
                            }
                            
                            // Pinned Multi-Region Selection Overlay Boxes
                            ForEach(Array(selectedRegions.enumerated()), id: \.element.id) { idx, region in
                                ZStack(alignment: .topLeading) {
                                    Rectangle()
                                        .stroke(Color.primary, lineWidth: 1.5)
                                        .background(Color.primary.opacity(0.1))
                                        .frame(width: region.rect.width, height: region.rect.height)
                                    
                                    HStack(spacing: 4) {
                                        Text("#\(idx + 1)")
                                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                        Text("\(Int(region.rect.width))×\(Int(region.rect.height))")
                                            .font(.system(size: 8.5, design: .monospaced))
                                            .foregroundColor(.secondary)
                                        Button {
                                            selectedRegions.removeAll { $0.id == region.id }
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundColor(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color(nsColor: .windowBackgroundColor))
                                    .foregroundColor(.primary)
                                    .cornerRadius(3)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 3)
                                            .stroke(Color.primary.opacity(0.28), lineWidth: 1)
                                    )
                                    .offset(x: 0, y: -22)
                                }
                                .position(x: region.rect.midX, y: region.rect.midY)
                            }
                            
                            // Multi-Region Inspect Control Card
                            if !selectedRegions.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "viewfinder")
                                            .font(.system(size: 10, weight: .semibold))
                                        Text("SELECTED REGIONS (\(selectedRegions.count))")
                                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                        Spacer()
                                        Text("Drag on image to add more spots")
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                        Button {
                                            selectedRegions.removeAll()
                                            commentText = ""
                                        } label: {
                                            Text("Clear")
                                                .font(.system(size: 9, weight: .medium))
                                                .foregroundColor(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    
                                    ForEach(Array(selectedRegions.enumerated()), id: \.element.id) { idx, region in
                                        HStack(spacing: 5) {
                                            Text("#\(idx + 1)")
                                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                                .frame(width: 22, alignment: .leading)
                                            TextField(
                                                "คำสั่งเฉพาะจุด #\(idx + 1)...",
                                                text: Binding(
                                                    get: { idx < selectedRegions.count ? selectedRegions[idx].note : "" },
                                                    set: { val in
                                                        if idx < selectedRegions.count {
                                                            selectedRegions[idx].note = val
                                                        }
                                                    }
                                                )
                                            )
                                            .textFieldStyle(.plain)
                                            .font(.system(size: 10))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(Color.primary.opacity(0.05))
                                            .cornerRadius(4)
                                        }
                                    }
                                    
                                    HStack(spacing: 5) {
                                        TextField("คำสั่งรวมสำหรับทุกจุดที่เลือก…", text: $commentText)
                                            .textFieldStyle(.plain)
                                            .font(.system(size: 10.5))
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 4.5)
                                            .background(Color.primary.opacity(0.06))
                                            .cornerRadius(4)
                                            .onSubmit {
                                                sendRegionsToAgent()
                                            }
                                        
                                        Button {
                                            sendRegionsToAgent()
                                        } label: {
                                            HStack(spacing: 4) {
                                                Image(systemName: "arrow.up.circle.fill")
                                                    .font(.system(size: 9.5))
                                                Text("Send (\(selectedRegions.count))")
                                                    .font(.system(size: 10, weight: .semibold))
                                            }
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 5)
                                            .background(Color.primary)
                                            .foregroundColor(Color(nsColor: .windowBackgroundColor))
                                            .cornerRadius(4)
                                        }
                                        .buttonStyle(.plain)
                                        .help("Send all selected image regions to AI Agent")
                                    }
                                }
                                .padding(8)
                                .frame(width: min(max(260, geo.size.width - 24), 360))
                                .background(Color(nsColor: .windowBackgroundColor).opacity(0.97))
                                .cornerRadius(7)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7)
                                        .stroke(Color.primary.opacity(0.22), lineWidth: 1)
                                )
                                .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 4)
                                .position(x: geo.size.width / 2, y: max(70, geo.size.height - 80))
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
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MicroCodeFileSaved"))) { note in
            guard PreviewHotReloadEngine.shared.isAutoHotReloadEnabled else { return }
            if let savedPath = note.userInfo?["path"] as? String,
               URL(fileURLWithPath: savedPath).standardizedFileURL.path == url.standardizedFileURL.path {
                loadImage()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MicroCodeWorkspaceFileDidChange"))) { note in
            guard PreviewHotReloadEngine.shared.isAutoHotReloadEnabled else { return }
            if let changedPath = note.userInfo?["path"] as? String,
               URL(fileURLWithPath: changedPath).standardizedFileURL.path == url.standardizedFileURL.path {
                loadImage()
            }
        }
    }
    
    private func updateSelection(start: CGPoint, current: CGPoint) {
        let x = min(start.x, current.x)
        let y = min(start.y, current.y)
        let width = abs(current.x - start.x)
        let height = abs(current.y - start.y)
        activeDraftRect = CGRect(x: x, y: y, width: width, height: height)
    }
    
    private func sendRegionsToAgent() {
        guard !selectedRegions.isEmpty else { return }
        let fileName = url.lastPathComponent
        let globalComment = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines: [String] = [
            "[Multi-Region Image Inspect (\(selectedRegions.count) Region\(selectedRegions.count == 1 ? "" : "s")) in `\(fileName)`]"
        ]
        for (idx, r) in selectedRegions.enumerated() {
            let note = r.note.trimmingCharacters(in: .whitespacesAndNewlines)
            let coords = "[\(Int(r.rect.minX)), \(Int(r.rect.minY)), \(Int(r.rect.width))×\(Int(r.rect.height))]"
            if note.isEmpty {
                lines.append("- Region #\(idx + 1) \(coords)")
            } else {
                lines.append("- Region #\(idx + 1) \(coords): \(note)")
            }
        }
        if !globalComment.isEmpty {
            lines.append("Overall Instruction: \(globalComment)")
        } else if !selectedRegions.contains(where: { !$0.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            lines.append("Overall Instruction: Please inspect and update the selected regions.")
        }
        PreviewDockService.shared.sendRegionCommentToAgent(comment: lines.joined(separator: "\n"))
        commentText = ""
        selectedRegions.removeAll()
        activeDraftRect = nil
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
