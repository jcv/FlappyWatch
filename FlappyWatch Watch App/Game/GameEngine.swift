import SwiftUI
import WatchKit

enum GameState {
    case ready, playing, lost
}

@MainActor
final class GameEngine: ObservableObject {
    @Published var birdY: CGFloat = 0
    @Published var birdVelocityY: CGFloat = 0
    @Published var pipes: [Pipe] = []
    @Published var score: Int = 0 {
        didSet {
            if score > highScore {
                highScore = score
            }
        }
    }
    @Published var highScore: Int = UserDefaults.standard.integer(forKey: "highScore") {
        didSet {
            UserDefaults.standard.set(highScore, forKey: "highScore")
        }
    }
    @Published var state: GameState = .ready

    private(set) var screenSize: CGSize = .zero
    private var nextPipeId = 0
    private var distanceSinceLastPipe: CGFloat = 0
    private var spinAccumulator: Double = 0

    let birdRadius: CGFloat = 6
    let pipeWidth: CGFloat = 20
    var birdX: CGFloat { screenSize.width * 0.32 }

    private let gravity: CGFloat = 480           // pt/s^2
    private let flapImpulse: CGFloat = -170       // pt/s, set (not added) as bird's velocity on flap
    private let maxFallVelocity: CGFloat = 260
    private let baseSpeed: CGFloat = 62
    private let maxSpeed: CGFloat = 110
    private let speedRampPerPoint: CGFloat = 1.6
    private let pipeSpacing: CGFloat = 92         // horizontal distance between pipe centers
    private let baseGapHeight: CGFloat = 62
    private let minGapHeight: CGFloat = 46
    private let gapShrinkPerPoint: CGFloat = 0.35
    private let pipeMargin: CGFloat = 20
    // Crown units of accumulated |rotation| that fire one flap. Tuned by feel, not derived --
    // rebuild after changing if the flap cadence feels off against a real spin.
    private let flapSpinThreshold: Double = 5.0

    private var currentSpeed: CGFloat {
        min(baseSpeed + CGFloat(score) * speedRampPerPoint, maxSpeed)
    }

    private var currentGapHeight: CGFloat {
        max(baseGapHeight - CGFloat(score) * gapShrinkPerPoint, minGapHeight)
    }

    func configure(size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        screenSize = size
        resetRound()
        state = .ready
    }

    func start() {
        guard state == .ready || state == .lost else { return }
        resetRound()
        state = .playing
    }

    private func resetRound() {
        birdY = screenSize.height / 2
        birdVelocityY = 0
        pipes = []
        nextPipeId = 0
        distanceSinceLastPipe = 0
        spinAccumulator = 0
        score = 0
    }

    /// Crown rotation is read as a flap gesture, not a position: any spin (either direction)
    /// accumulates, and every time it crosses `flapSpinThreshold` the bird flaps once -- so
    /// spinning faster reads as flapping faster, same as tapping faster in the original game.
    func handleCrownDelta(_ delta: Double) {
        guard state == .playing else { return }
        spinAccumulator += abs(delta)
        while spinAccumulator >= flapSpinThreshold {
            spinAccumulator -= flapSpinThreshold
            flap()
        }
    }

    private func flap() {
        birdVelocityY = flapImpulse
        WKInterfaceDevice.current().play(.click)
    }

    func update(deltaTime: TimeInterval) {
        guard screenSize != .zero, state == .playing else { return }

        // Fixed substeps so a slow render frame still consumes real elapsed time instead of
        // visually slowing gameplay down, capped so catching up can't itself add unbounded work.
        let step: TimeInterval = 1.0 / 60.0
        let maxSubsteps = 4
        var remaining = min(deltaTime, 0.25)
        var stepsTaken = 0
        while remaining > 0, state == .playing {
            stepsTaken += 1
            let dt = CGFloat(stepsTaken >= maxSubsteps ? remaining : min(remaining, step))
            remaining -= Double(dt)
            stepBird(dt: dt)
            stepPipes(dt: dt)
        }
    }

    private func stepBird(dt: CGFloat) {
        birdVelocityY = min(birdVelocityY + gravity * dt, maxFallVelocity)
        birdY += birdVelocityY * dt

        if birdY - birdRadius <= 0 {
            birdY = birdRadius
            endGame()
        } else if birdY + birdRadius >= screenSize.height {
            birdY = screenSize.height - birdRadius
            endGame()
        }
    }

    private func stepPipes(dt: CGFloat) {
        guard state == .playing else { return }
        let speed = currentSpeed
        distanceSinceLastPipe += speed * dt

        for i in pipes.indices {
            pipes[i].x -= speed * dt
        }
        pipes.removeAll { $0.x + pipeWidth < 0 }

        if distanceSinceLastPipe >= pipeSpacing {
            distanceSinceLastPipe -= pipeSpacing
            spawnPipe()
        }

        let birdRect = CGRect(
            x: birdX - birdRadius,
            y: birdY - birdRadius,
            width: birdRadius * 2,
            height: birdRadius * 2
        )

        for i in pipes.indices {
            let pipe = pipes[i]
            if !pipe.scored, pipe.x + pipeWidth < birdX {
                pipes[i].scored = true
                score += 1
                WKInterfaceDevice.current().play(.directionUp)
            }

            guard pipe.x < birdX + birdRadius, pipe.x + pipeWidth > birdX - birdRadius else { continue }
            let gapTop = pipe.gapCenterY - pipe.gapHeight / 2
            let gapBottom = pipe.gapCenterY + pipe.gapHeight / 2
            if birdRect.minY < gapTop || birdRect.maxY > gapBottom {
                endGame()
                return
            }
        }
    }

    private func spawnPipe() {
        let gapHeight = currentGapHeight
        let minCenter = pipeMargin + gapHeight / 2
        let maxCenter = screenSize.height - pipeMargin - gapHeight / 2
        let center = maxCenter > minCenter ? CGFloat.random(in: minCenter...maxCenter) : screenSize.height / 2
        pipes.append(Pipe(id: nextPipeId, x: screenSize.width, gapCenterY: center, gapHeight: gapHeight))
        nextPipeId += 1
    }

    private func endGame() {
        guard state == .playing else { return }
        state = .lost
        WKInterfaceDevice.current().play(.failure)
    }
}
