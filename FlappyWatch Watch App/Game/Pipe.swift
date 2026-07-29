import CoreGraphics

struct Pipe: Identifiable {
    let id: Int
    var x: CGFloat
    let gapCenterY: CGFloat
    let gapHeight: CGFloat
    var scored: Bool = false
}
