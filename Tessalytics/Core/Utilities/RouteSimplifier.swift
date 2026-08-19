import Foundation

enum RouteSimplifier {
    static func simplify(_ points: [CoordinateDTO], tolerance: Double = 0.00008) -> [CoordinateDTO] {
        guard points.count > 2 else { return points }
        var keep = Array(repeating: false, count: points.count)
        keep[0] = true; keep[points.count - 1] = true
        simplify(points, first: 0, last: points.count - 1, squaredTolerance: tolerance * tolerance, keep: &keep)
        return points.enumerated().compactMap { keep[$0.offset] ? $0.element : nil }
    }

    private static func simplify(_ points: [CoordinateDTO], first: Int, last: Int, squaredTolerance: Double, keep: inout [Bool]) {
        guard !Task.isCancelled, last > first + 1 else { return }
        var maximum = squaredTolerance
        var index = 0
        for candidate in (first + 1)..<last {
            if Task.isCancelled { return }
            let distance = squaredSegmentDistance(points[candidate], points[first], points[last])
            if distance > maximum { maximum = distance; index = candidate }
        }
        guard index != 0 else { return }
        keep[index] = true
        simplify(points, first: first, last: index, squaredTolerance: squaredTolerance, keep: &keep)
        simplify(points, first: index, last: last, squaredTolerance: squaredTolerance, keep: &keep)
    }

    private static func squaredSegmentDistance(_ point: CoordinateDTO, _ start: CoordinateDTO, _ end: CoordinateDTO) -> Double {
        var x = start.longitude, y = start.latitude
        var dx = end.longitude - x, dy = end.latitude - y
        if dx != 0 || dy != 0 {
            let t = ((point.longitude - x) * dx + (point.latitude - y) * dy) / (dx * dx + dy * dy)
            if t > 1 { x = end.longitude; y = end.latitude }
            else if t > 0 { x += dx * t; y += dy * t }
        }
        dx = point.longitude - x; dy = point.latitude - y
        return dx * dx + dy * dy
    }
}
