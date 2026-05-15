//
//  UniversalPreviewView.swift
//  MicroCode
//
//  Created by SPU AI CLUB
//  Copyright © 2024 AIPRENEUR. All rights reserved.
//

import SwiftUI

struct UniversalPreviewView: View {
    @ObservedObject var previewService = PreviewService.shared
    @State private var zoomLevel: CGFloat = 0.4
    
    // Default set of devices to preview
    let targetDevices: [DeviceFrame] = [
        DeviceFrame.allDevices.first { $0.name == "iPhone SE" },
        DeviceFrame.allDevices.first { $0.name == "iPhone 15 Pro" },
        DeviceFrame.allDevices.first { $0.name == "iPad Pro 11" }
    ].compactMap { $0 }
    
    var body: some View {
        VStack(spacing: 0) {
            // Sub-toolbar for Universal Mode
            HStack {
                Text("Universal Mode")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Zoom Control
                HStack(spacing: 8) {
                    Image(systemName: "minus.magnifyingglass")
                    Slider(value: $zoomLevel, in: 0.2...0.8)
                        .frame(width: 100)
                    Image(systemName: "plus.magnifyingglass")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding(8)
            .background(Color(white: 0.1))
            .padding(.bottom, 1) // Separator
            
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 40) {
                    ForEach(targetDevices) { device in
                        VStack(spacing: 16) {
                            if let image = previewService.universalPreviewImages[device.id] {
                                // Rendered Image in Frame
                                DeviceFrameView(device: device, scale: zoomLevel) {
                                    Image(nsImage: image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                }
                            } else if previewService.isPreviewLoading {
                                // Loading
                                DeviceFrameView(device: device, scale: zoomLevel) {
                                    ZStack {
                                        Color.black
                                        ProgressView()
                                            .scaleEffect(2)
                                    }
                                }
                            } else {
                                // Placeholder / Ready state
                                DeviceFrameView(device: device, scale: zoomLevel) {
                                    ZStack {
                                        Color(white: 0.9)
                                        VStack {
                                            Image(systemName: "play.fill")
                                                .font(.largeTitle)
                                                .foregroundColor(.gray)
                                            Text("Waiting...")
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                        }
                                    }
                                }
                            }
                            
                            // Label
                            Text(device.name)
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                                .padding(4)
                                .background(Color.black.opacity(0.3))
                                .cornerRadius(4)
                        }
                    }
                }
                .padding(40)
            }
        }
        .background(GridBackground())
    }
}
