import UIKit

final class WatchMapView: UIView {
    override func draw(_ rect: CGRect) {
        let land = UIColor(red: 0.87, green: 0.94, blue: 0.91, alpha: 1)
        land.setFill()
        UIBezierPath(rect: rect).fill()

        let road = UIColor.white
        road.setStroke()
        let path = UIBezierPath()
        path.lineWidth = 22
        path.move(to: CGPoint(x: -20, y: rect.height * 0.74))
        path.addCurve(
            to: CGPoint(x: rect.width + 20, y: rect.height * 0.48),
            controlPoint1: CGPoint(x: rect.width * 0.25, y: rect.height * 0.62),
            controlPoint2: CGPoint(x: rect.width * 0.65, y: rect.height * 0.82)
        )
        path.stroke()

        let water = UIColor(red: 0.68, green: 0.84, blue: 0.88, alpha: 0.55)
        water.setFill()
        UIBezierPath(
            roundedRect: CGRect(x: rect.width * 0.62, y: rect.height * 0.12, width: rect.width * 0.42, height: rect.height * 0.2),
            cornerRadius: 60
        ).fill()
    }
}
