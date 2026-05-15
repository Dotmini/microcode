//
//  DeviceFrameView.swift
//  MicroCode
//
//  Created by SPU AI CLUB
//  Copyright © 2024 AIPRENEUR. All rights reserved.
//

import SwiftUI

struct DeviceFrameView<Content: View>: View {
    let device: DeviceFrame
    let isLandscape: Bool
    let isDarkMode: Bool
    let scale: CGFloat
    let content: Content
    
    // Derived from DeviceModel in PreviewView, but adapted for the simpler DeviceFrame struct
    // We might need to enhance DeviceFrame to include these capabilities or map them
    
    init(device: DeviceFrame, isLandscape: Bool = false, isDarkMode: Bool = false, scale: CGFloat = 1.0, @ViewBuilder content: () -> Content) {
        self.device = device
        self.isLandscape = isLandscape
        self.isDarkMode = isDarkMode
        self.scale = scale
        self.content = content()
    }
    
    var body: some View {
        let width = isLandscape ? device.height : device.width
        let height = isLandscape ? device.width : device.height
        
        ZStack {
            // Device Body
            RoundedRectangle(cornerRadius: device.cornerRadius + 8)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.25), Color(white: 0.15), Color(white: 0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: width + 20, height: height + 20)
                .shadow(color: .black.opacity(0.5), radius: 30, y: 15)
            
            // Inner bezel
            RoundedRectangle(cornerRadius: device.cornerRadius + 4)
                .fill(Color.black)
                .frame(width: width + 10, height: height + 10)
            
            // Screen Area
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: device.cornerRadius)
                    .fill(isDarkMode ? Color.black : Color.white)
                
                // Content
                content
                
                // Overlays (Dynamic Island / Status Bar)
                // Note: Simplified for generic DeviceFrame. 
                // In a real app we check device capabilities.
                if device.name.contains("iPhone") && (device.name.contains("15") || device.name.contains("14 Pro")) {
                    dynamicIslandView
                }
                
                statusBarView
                
                if device.name.contains("iPhone") && !device.name.contains("SE") {
                    homeIndicatorView
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: device.cornerRadius))
            
            // Side Buttons
            sideButtons(width: width, height: height)
        }
        .scaleEffect(scale)
        .frame(width: (width + 40) * scale, height: (height + 40) * scale)
    }
    
    // MARK: - Subviews
    
    private var dynamicIslandView: some View {
        VStack {
            Capsule()
                .fill(Color.black)
                .frame(width: 126, height: 37)
                .padding(.top, isLandscape ? 8 : 12)
            Spacer()
        }
    }
    
    private var statusBarView: some View {
        let textColor = isDarkMode ? Color.white : Color.black
        let hasIsland = device.name.contains("iPhone") && (device.name.contains("15") || device.name.contains("14 Pro"))
        
        return VStack {
            HStack {
                Text("9:41")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(textColor)
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: "cellularbars")
                    Image(systemName: "wifi")
                    Image(systemName: "battery.100")
                }
                .font(.system(size: 12))
                .foregroundColor(textColor)
            }
            .padding(.horizontal, hasIsland ? 32 : 20)
            .padding(.top, hasIsland ? 55 : 12)
            Spacer()
        }
    }
    
    private var homeIndicatorView: some View {
        VStack {
            Spacer()
            Capsule()
                .fill(isDarkMode ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                .frame(width: 134, height: 5)
                .padding(.bottom, 8)
        }
    }
    
    private func sideButtons(width: CGFloat, height: CGFloat) -> some View {
        // Simplified buttons logic
        ZStack {
            // Power button (right)
            HStack {
                Spacer()
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(white: 0.3))
                    .frame(width: 3, height: 45)
                    .offset(x: width / 2 + 12, y: -height * 0.15)
            }
            
            // Volume buttons (left)
            HStack {
                VStack(spacing: 15) {
                    RoundedRectangle(cornerRadius: 2).fill(Color(white: 0.3)).frame(width: 3, height: 25)
                    RoundedRectangle(cornerRadius: 2).fill(Color(white: 0.3)).frame(width: 3, height: 45)
                    RoundedRectangle(cornerRadius: 2).fill(Color(white: 0.3)).frame(width: 3, height: 45)
                }
                .offset(x: -(width / 2 + 12), y: -height * 0.12)
                Spacer()
            }
        }
    }
}
