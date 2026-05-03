//
//  FestiveOverlayView.swift
//  CodeTunner
//
//  Created for MicroCode Dotmini.
//

import SwiftUI

struct FestiveParticle: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var size: CGFloat
    var color: Color
    var vx: CGFloat
    var vy: CGFloat
    var opacity: Double
    var life: Double
}

struct FestiveBallon: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var size: CGFloat
    var color: Color
    var speed: CGFloat
    var wobble: CGFloat
    var phase: Double
}

struct FestiveOverlayView: View {
    @EnvironmentObject var appState: AppState
    
    @State private var particles: [FestiveParticle] = []
    @State private var balloons: [FestiveBallon] = []
    @State private var hearts: [FestiveParticle] = []
    
    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    var isFestive: Bool {
        let name = appState.appTheme.rawValue
        return name.contains("happyNew") || name.contains("christmas")
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if isFestive {
                    // Balloons (Floating up)
                    ForEach(balloons) { balloon in
                        VStack(spacing: 0) {
                            Circle()
                                .fill(balloon.color)
                                .frame(width: balloon.size, height: balloon.size * 1.2)
                            Rectangle()
                                .fill(Color.white.opacity(0.3))
                                .frame(width: 1, height: 20)
                        }
                        .position(x: balloon.x + sin(balloon.phase) * balloon.wobble, y: balloon.y)
                        .opacity(0.6)
                    }
                    
                    // Fireworks
                    ForEach(particles) { p in
                        Circle()
                            .fill(p.color)
                            .frame(width: p.size, height: p.size)
                            .position(x: p.x, y: p.y)
                            .opacity(p.opacity)
                    }
                    
                    // Hearts
                    ForEach(hearts) { h in
                        Image(systemName: "heart.fill")
                            .foregroundColor(h.color)
                            .font(.system(size: h.size))
                            .position(x: h.x, y: h.y)
                            .opacity(h.opacity)
                    }
                }
            }
            .onAppear {
                if isFestive {
                    setupFestive(in: geometry.size)
                }
            }
            .onReceive(timer) { _ in
                if isFestive {
                    updateFestive(in: geometry.size)
                } else if !particles.isEmpty || !balloons.isEmpty {
                    particles.removeAll()
                    balloons.removeAll()
                    hearts.removeAll()
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
    
    private func setupFestive(in size: CGSize) {
        guard size.width > 0 && size.height > 0 else { return }
        // Initial balloons
        for _ in 0..<10 {
            spawnBalloon(in: size)
        }
    }
    
    private func spawnBalloon(in size: CGSize) {
        guard size.width > 0 else { return }
        let colors: [Color] = [.red, .blue, .yellow, .pink, .purple, .orange, .green]
        balloons.append(FestiveBallon(
            x: CGFloat.random(in: 0...size.width),
            y: size.height + 50,
            size: CGFloat.random(in: 20...40),
            color: colors.randomElement() ?? .red,
            speed: CGFloat.random(in: 1...3),
            wobble: CGFloat.random(in: 5...15),
            phase: Double.random(in: 0...Double.pi * 2)
        ))
    }
    
    private func spawnFirework(at point: CGPoint) {
        let colors: [Color] = [.yellow, .orange, .red, .white, .cyan, .pink]
        let baseColor = colors.randomElement() ?? .yellow
        let count = 40
        
        for _ in 0..<count {
            let angle = Double.random(in: 0...Double.pi * 2)
            let speed = CGFloat.random(in: 1...6)
            particles.append(FestiveParticle(
                x: point.x,
                y: point.y,
                size: CGFloat.random(in: 2...4),
                color: baseColor,
                vx: cos(angle) * speed,
                vy: sin(angle) * speed,
                opacity: 1.0,
                life: 1.0
            ))
        }
    }
    
    private func spawnHeart(in size: CGSize) {
        guard size.width > 0 && size.height > 0 else { return }
        hearts.append(FestiveParticle(
            x: CGFloat.random(in: 0...size.width),
            y: CGFloat.random(in: 0...size.height),
            size: CGFloat.random(in: 10...20),
            color: Color.pink.opacity(0.6),
            vx: 0,
            vy: CGFloat.random(in: -2...(-0.5)),
            opacity: 0.8,
            life: 1.0
        ))
    }
    
    private func updateFestive(in size: CGSize) {
        guard size.width > 50 && size.height > 50 else { return }
        
        // 1. Update Fireworks
        particles = particles.compactMap { p in
            var updated = p
            updated.x += updated.vx
            updated.y += updated.vy
            updated.vy += 0.1 // Gravity
            updated.life -= 0.02
            updated.opacity = updated.life
            return updated.life > 0 ? updated : nil
        }
        
        // Random firework
        if particles.count < 100 && Double.random(in: 0...1) > 0.96 {
            let x = CGFloat.random(in: 50...max(51, size.width - 50))
            let y = CGFloat.random(in: 50...max(51, size.height / 2))
            spawnFirework(at: CGPoint(x: x, y: y))
        }
        
        // 2. Update Balloons
        balloons = balloons.compactMap { b in
            var updated = b
            updated.y -= updated.speed
            updated.phase += 0.05
            return updated.y > -100 ? updated : nil
        }
        
        if balloons.count < 15 && Double.random(in: 0...1) > 0.94 {
            spawnBalloon(in: size)
        }
        
        // 3. Update Hearts
        hearts = hearts.compactMap { h in
            var updated = h
            updated.y += updated.vy
            updated.life -= 0.015
            updated.opacity = updated.life
            return updated.life > 0 ? updated : nil
        }
        
        if hearts.count < 10 && Double.random(in: 0...1) > 0.97 {
            spawnHeart(in: size)
        }
    }
}
