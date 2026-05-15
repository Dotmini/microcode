//
//  SnowEffectView.swift
//  MicroCode
//
//  Created for MicroCode Dotmini.
//

import SwiftUI

struct SnowParticle: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var size: CGFloat
    var speed: CGFloat
    var opacity: Double
}

struct SnowEffectView: View {
    @State private var particles: [SnowParticle] = []
    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background is handled by the theme underlay, this is just overlay effects
                
                ForEach(particles) { particle in
                    Circle()
                        .fill(Color.white)
                        .frame(width: particle.size, height: particle.size)
                        .position(x: particle.x, y: particle.y)
                        .opacity(particle.opacity)
                }
            }
            .onAppear {
                // Initial burst
                createParticles(in: geometry.size, count: 50)
            }
            .onReceive(timer) { _ in
                updateParticles(in: geometry.size)
            }
        }
        .allowsHitTesting(false) // Let clicks pass through!
        .ignoresSafeArea()
    }
    
    private func createParticles(in size: CGSize, count: Int) {
        for _ in 0..<count {
            let particle = SnowParticle(
                x: CGFloat.random(in: 0...size.width),
                y: CGFloat.random(in: 0...size.height), // Initial can be anywhere
                size: CGFloat.random(in: 2...6),
                speed: CGFloat.random(in: 1...4), // Vertical speed
                opacity: Double.random(in: 0.3...0.8)
            )
            particles.append(particle)
        }
    }
    
    private func updateParticles(in size: CGSize) {
        // Add new particles occasionally
        if CGFloat.random(in: 0...1) > 0.7 {
            particles.append(SnowParticle(
                x: CGFloat.random(in: 0...size.width),
                y: -10, // Start slightly above
                size: CGFloat.random(in: 2...6),
                speed: CGFloat.random(in: 1...4),
                opacity: Double.random(in: 0.3...0.8)
            ))
        }
        
        // Update positions
        for i in particles.indices {
            particles[i].y += particles[i].speed
            particles[i].x += CGFloat.random(in: -1...1) // Slight wobble
        }
        
        // Remove particles that fell off screen
        particles.removeAll { $0.y > size.height + 10 }
    }
}
