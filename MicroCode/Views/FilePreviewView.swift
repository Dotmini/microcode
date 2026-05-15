//
//  FilePreviewView.swift
//  MicroCode
//
//  Preview for PDF, Images, and other file formats
//

import SwiftUI
import PDFKit
import QuickLookUI

// MARK: - File Preview View
struct FilePreviewView: View {
    let fileURL: URL
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: iconForFile)
                    .foregroundColor(.accentColor)
                Text(fileURL.lastPathComponent)
                    .font(.headline)
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Content
            previewContent
        }
        .frame(minWidth: 600, minHeight: 500)
    }
    
    @ViewBuilder
    private var previewContent: some View {
        let ext = fileURL.pathExtension.lowercased()
        
        switch ext {
        case "pdf":
            PDFPreviewView(url: fileURL)
        case "png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "heic":
            ImagePreviewView(url: fileURL)
        case "svg":
            SVGPreviewView(url: fileURL)
        default:
            QuickLookPreviewView(url: fileURL)
        }
    }
    
    private var iconForFile: String {
        let ext = fileURL.pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.fill"
        case "png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "heic": return "photo.fill"
        case "svg": return "square.on.circle"
        default: return "doc.text.fill"
        }
    }
}

// MARK: - PDF Preview
struct PDFPreviewView: NSViewRepresentable {
    let url: URL
    
    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        if let document = PDFDocument(url: url) {
            pdfView.document = document
        }
        return pdfView
    }
    
    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document?.documentURL != url {
            if let document = PDFDocument(url: url) {
                nsView.document = document
            }
        }
    }
}

// MARK: - Image Preview
struct ImagePreviewView: View {
    let url: URL
    @State private var image: NSImage?
    @State private var scale: CGFloat = 1.0
    
    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            if let img = image {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Loading image...")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 8) {
                Button(action: { scale = max(0.1, scale - 0.25) }) {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.bordered)
                
                Text("\(Int(scale * 100))%")
                    .font(.caption)
                    .frame(width: 50)
                
                Button(action: { scale = min(5.0, scale + 0.25) }) {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.bordered)
                
                Button(action: { scale = 1.0 }) {
                    Text("Fit")
                }
                .buttonStyle(.bordered)
            }
            .padding(8)
            .background(.ultraThinMaterial)
            .cornerRadius(8)
            .padding()
        }
        .onAppear {
            loadImage()
        }
    }
    
    private func loadImage() {
        DispatchQueue.global(qos: .userInitiated).async {
            if let img = NSImage(contentsOf: url) {
                DispatchQueue.main.async {
                    self.image = img
                }
            }
        }
    }
}

// MARK: - SVG Preview
struct SVGPreviewView: View {
    let url: URL
    @State private var svgContent: String = ""
    
    var body: some View {
        ScrollView {
            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Unable to load SVG")
                    .foregroundColor(.secondary)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

// MARK: - QuickLook Preview (Fallback)
struct QuickLookPreviewView: NSViewRepresentable {
    let url: URL
    
    func makeNSView(context: Context) -> QLPreviewView {
        let previewView = QLPreviewView()
        previewView.previewItem = url as QLPreviewItem
        return previewView
    }
    
    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        nsView.previewItem = url as QLPreviewItem
    }
}

// MARK: - Preview Provider
