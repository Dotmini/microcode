//
//  InteractivePDFPreviewView.swift
//  MicroCode
//
//  Interactive PDF Reader with Page Navigation, Zoom, and Continuous Scroll
//  Copyright © 2026 Dotmini Company Limited. All rights reserved.
//

import SwiftUI
import PDFKit
import AppKit

struct InteractivePDFPreviewView: View {
    let url: URL
    
    @State private var pdfDocument: PDFDocument?
    @State private var pageCount: Int = 0
    @State private var currentPageIndex: Int = 1
    @State private var isContinuous: Bool = true
    @State private var zoomScale: CGFloat = 1.0
    
    var body: some View {
        VStack(spacing: 0) {
            // Sub-header Bar
            HStack(spacing: 8) {
                // Page Info Badge
                HStack(spacing: 6) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    if pageCount > 0 {
                        Text("\(pageCount) pages")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                    } else {
                        Text("PDF")
                            .font(.system(size: 10, weight: .bold))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(4)
                
                // Display Mode Toggle
                Button {
                    isContinuous.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isContinuous ? "scroll" : "book.closed")
                            .font(.system(size: 10))
                        Text(isContinuous ? "Continuous" : "Single Page")
                            .font(.system(size: 10))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                // Open in External App
                Button("Open in Preview") {
                    NSWorkspace.shared.open(url)
                }
                .font(.system(size: 10))
                .buttonStyle(.bordered)
                
                // Actions Menu
                Menu {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    Button("Copy File Path") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url.path, forType: .string)
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
            
            // PDF Canvas
            PDFKitContainerView(url: url, isContinuous: isContinuous)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            loadPDF()
        }
        .onChange(of: url) { _ in
            loadPDF()
        }
    }
    
    private func loadPDF() {
        if let doc = PDFDocument(url: url) {
            self.pdfDocument = doc
            self.pageCount = doc.pageCount
        }
    }
}

// MARK: - PDFKit Representable Container
struct PDFKitContainerView: NSViewRepresentable {
    let url: URL
    let isContinuous: Bool
    
    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = isContinuous ? .singlePageContinuous : .singlePage
        pdfView.displayDirection = .vertical
        if let doc = PDFDocument(url: url) {
            pdfView.document = doc
        }
        return pdfView
    }
    
    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document?.documentURL != url {
            if let doc = PDFDocument(url: url) {
                nsView.document = doc
            }
        }
        nsView.displayMode = isContinuous ? .singlePageContinuous : .singlePage
    }
}
