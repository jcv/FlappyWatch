import SwiftUI

struct ContentView: View {
    @StateObject private var engine = GameEngine()
    @State private var crownValue: Double = 0
    @State private var lastCrownValue: Double = 0
    @State private var lastUpdate: Date?
    @FocusState private var isCrownFocused: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack {
                TimelineView(.animation) { timeline in
                    Canvas { context, size in
                        draw(context: context, size: size)
                    }
                    .onChange(of: timeline.date) { _, newDate in
                        tick(newDate)
                    }
                }
                .focusable(true)
                .focused($isCrownFocused)
                .digitalCrownRotation(
                    $crownValue,
                    from: -100_000,
                    through: 100_000,
                    by: 1,
                    sensitivity: .high,
                    isContinuous: true,
                    isHapticFeedbackEnabled: false
                )
                .onAppear {
                    engine.configure(size: geo.size)
                    isCrownFocused = true
                }
                .onChange(of: geo.size) { _, newSize in
                    guard engine.screenSize == .zero, newSize.width > 0, newSize.height > 0 else { return }
                    engine.configure(size: newSize)
                    isCrownFocused = true
                }

                if engine.state != .playing {
                    stateOverlay
                }
            }
        }
        .ignoresSafeArea()
    }

    private func tick(_ date: Date) {
        // Crown delta is tracked every frame regardless of game state so a spin mid-overlay
        // doesn't get read as one giant flap the instant play resumes.
        let delta = crownValue - lastCrownValue
        lastCrownValue = crownValue
        engine.handleCrownDelta(delta)

        guard engine.state == .playing else {
            lastUpdate = nil
            return
        }
        defer { lastUpdate = date }
        guard let last = lastUpdate else { return }
        engine.update(deltaTime: date.timeIntervalSince(last))
    }

    private func draw(context: GraphicsContext, size: CGSize) {
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .color(Color(red: 0.53, green: 0.81, blue: 0.92))
        )

        for pipe in engine.pipes {
            drawPipe(pipe, context: context, size: size)
        }

        drawBird(context: context)

        if engine.state == .playing {
            context.draw(
                Text("\(engine.score)").font(.system(size: 20, weight: .heavy, design: .rounded)).foregroundColor(.white),
                at: CGPoint(x: size.width / 2, y: 4),
                anchor: .top
            )
        }
    }

    private func drawPipe(_ pipe: Pipe, context: GraphicsContext, size: CGSize) {
        let gapTop = pipe.gapCenterY - pipe.gapHeight / 2
        let gapBottom = pipe.gapCenterY + pipe.gapHeight / 2
        let color = Color(red: 0.3, green: 0.75, blue: 0.35)

        let topRect = CGRect(x: pipe.x, y: 0, width: engine.pipeWidth, height: max(gapTop, 0))
        let bottomRect = CGRect(x: pipe.x, y: gapBottom, width: engine.pipeWidth, height: max(size.height - gapBottom, 0))
        context.fill(Path(roundedRect: topRect, cornerRadius: 2), with: .color(color))
        context.fill(Path(roundedRect: bottomRect, cornerRadius: 2), with: .color(color))
    }

    private func drawBird(context: GraphicsContext) {
        // Tilts nose-up on a fresh flap, nose-down as it dives -- pure cosmetic feedback,
        // has no effect on the hitbox (which stays a plain circle).
        let rotation = min(max(Double(engine.birdVelocityY) * 0.15, -30), 75)
        let rect = CGRect(x: -engine.birdRadius, y: -engine.birdRadius, width: engine.birdRadius * 2, height: engine.birdRadius * 2)

        context.drawLayer { layer in
            layer.translateBy(x: engine.birdX, y: engine.birdY)
            layer.rotate(by: .degrees(rotation))
            layer.fill(Path(ellipseIn: rect), with: .color(.yellow))
            layer.fill(
                Path(ellipseIn: CGRect(x: rect.maxX - 4.5, y: rect.minY + 1, width: 3, height: 3)),
                with: .color(.black)
            )

            var beak = Path()
            beak.move(to: CGPoint(x: rect.maxX - 1, y: -1.5))
            beak.addLine(to: CGPoint(x: rect.maxX + 4, y: 0))
            beak.addLine(to: CGPoint(x: rect.maxX - 1, y: 1.5))
            beak.closeSubpath()
            layer.fill(beak, with: .color(.orange))
        }
    }

    @ViewBuilder
    private var stateOverlay: some View {
        VStack(spacing: 6) {
            switch engine.state {
            case .ready:
                Text("FlappyWatch").font(.headline)
                Text("Spin the Crown to flap").font(.caption2).multilineTextAlignment(.center)
                if engine.highScore > 0 {
                    Text("Best: \(engine.highScore)").font(.caption2)
                }
            case .lost:
                Text("Game Over").font(.headline)
                Text("Score: \(engine.score)").font(.caption2)
                Text("Best: \(engine.highScore)").font(.caption2)
            case .playing:
                EmptyView()
            }
            Button(engine.state == .ready ? "Start" : "Play Again") {
                engine.start()
            }
            .font(.caption2)
        }
        .multilineTextAlignment(.center)
        .padding()
        .background(.black.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding()
    }
}

#Preview {
    ContentView()
}
