import SwiftUI

/// The bottom of the session screen: a live compass of your own steps, how far you are from the anchor, and Stop.
/// It reads the motion tracker directly, so it moves on every step and turns as you turn.
struct WalkOutCard: View {
    @Environment(AppModel.self) private var model
    let session: Session

    var body: some View {
        let tracker = model.motion
        let distance = tracker.position.distance
        let radius = session.config.radiusMeters
        let earlier = tracker.trail.count > 4 ? tracker.trail[tracker.trail.count - 5].distance : distance
        let status: WalkOut.Status = session.away ? .out : WalkOut.status(distance: distance, earlier: earlier, radius: radius)

        VStack(spacing: 14) {
            HStack(spacing: 16) {
                WalkOutCompass(position: tracker.position, heading: tracker.heading, trail: tracker.trail,
                               radius: radius, isOut: status == .out)
                    .frame(width: 132, height: 132)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title(status))
                        .font(.caption.weight(.bold))
                        .tracking(0.4)
                        .foregroundStyle(color(status))
                        .contentTransition(.opacity)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(Int(distance.rounded(.down)))")
                            .font(.system(size: 44, weight: .bold).monospacedDigit())
                            .tracking(-1.5)
                            .contentTransition(.numericText(value: distance.rounded(.down)))
                        Text("of \(Int(radius)) m")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(Palette.secondary)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    Text(hint(status, distance: distance, radius: radius))
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.snappy(duration: 0.25), value: Int(distance.rounded(.down)))
                .animation(.smooth(duration: 0.3), value: status)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(Int(distance)) of \(Int(radius)) meters from your anchor. \(hint(status, distance: distance, radius: radius))")
            stopButton(status: status, distance: distance, radius: radius)
        }
        .foregroundStyle(Palette.ink)
        .padding(16)
        .glassPanel(cornerRadius: 34)
        // A light tick for every meter your steps add, a firm one when you cross out of the circle.
        .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: Int(distance.rounded(.down)))
        .sensoryFeedback(.success, trigger: status == .out)
    }

    @ViewBuilder
    private func stopButton(status: WalkOut.Status, distance: Double, radius: Double) -> some View {
        if status == .out {
            Button(action: model.stop) {
                Label("End Session", systemImage: "stop.fill")
            }
            .buttonStyle(ProminentButtonStyle(color: Palette.ink))
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
        } else {
            let left = WalkOut.metersToGo(distance: distance, radius: radius)
            Label("Walk \(max(1, left)) m to unlock Stop", systemImage: "lock.fill")
                .font(.system(size: 17, weight: .semibold).monospacedDigit())
                .foregroundStyle(Palette.ink.opacity(0.8))
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(.white.opacity(0.7), in: Capsule())
                .contentTransition(.numericText(value: Double(left)))
                .animation(.snappy(duration: 0.25), value: left)
                .accessibilityLabel("Stop is locked. Walk \(max(1, left)) meters to unlock it.")
        }
    }

    private func title(_ status: WalkOut.Status) -> String {
        switch status {
        case .atAnchor: "AT YOUR ANCHOR"
        case .walkingOut: "WALKING OUT"
        case .walkingBack: "WALKING BACK IN"
        case .out: "STOP IS UNLOCKED"
        }
    }

    private func color(_ status: WalkOut.Status) -> Color {
        switch status {
        case .atAnchor, .walkingOut: Palette.blue
        case .walkingBack: Color(red: 0.76, green: 0.37, blue: 0)
        case .out: Palette.away
        }
    }

    private func hint(_ status: WalkOut.Status, distance: Double, radius: Double) -> String {
        switch status {
        case .atAnchor: "Walk any way. Every step counts."
        case .walkingOut: "\(WalkOut.metersToGo(distance: distance, radius: radius)) m more. Keep going."
        case .walkingBack: "That leads back in. Follow the green arrow."
        case .out: "You're out of the circle. Your phone is free."
        }
    }
}

/// Heading-up radar: the way you face is always up, the anchor sits in the middle, the dashed ring is your lock
/// radius, your steps leave a fading trail, and a green arrow points straight out of the circle. The world layer
/// turns with the gyroscope (25 times a second, eased between readings) and your dot glides to each new step.
struct WalkOutCompass: View {
    let position: DeadReckoning
    let heading: Double
    let trail: [DeadReckoning]
    let radius: Double
    let isOut: Bool

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let half = side / 2
            let pxPerMeter = half / max(radius * 1.35, 10)
            let you = point(position, pxPerMeter: pxPerMeter, limit: half - 9)
            let ringDiameter = radius * pxPerMeter * 2
            let accent = isOut ? Palette.away : Palette.blue

            ZStack {
                Circle().fill(Color.white)
                ZStack {
                    Ticks().stroke(Palette.ink.opacity(0.22), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                    Circle()
                        .fill(accent.opacity(0.06))
                        .frame(width: ringDiameter, height: ringDiameter)
                    Circle()
                        .strokeBorder(accent.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        .frame(width: ringDiameter, height: ringDiameter)
                    TrailShape(points: trail.map { point($0, pxPerMeter: pxPerMeter, limit: half - 9) })
                        .stroke(Color(red: 0.2, green: 0.63, blue: 1).opacity(0.55),
                                style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    Circle()
                        .fill(accent)
                        .frame(width: 22, height: 22)
                        .overlay(AnchorMark(size: 13))
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    if !isOut, position.distance >= WalkOut.atAnchorMeters {
                        OutArrow()
                            .fill(Color(red: 0.2, green: 0.78, blue: 0.35))
                            .frame(width: 12, height: 17)
                            .offset(y: -19)
                            .frame(width: 60, height: 60)
                            .rotationEffect(.radians(WalkOut.outwardAngle(position)))
                            .offset(x: you.x, y: you.y)
                            .transition(.opacity)
                    }
                    Circle()
                        .fill(Color(red: 0.2, green: 0.63, blue: 1))
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .background(Circle().fill(Color(red: 0.2, green: 0.63, blue: 1).opacity(0.22)).frame(width: 26, height: 26))
                        .offset(x: you.x, y: you.y)
                }
                .frame(width: side, height: side)
                .rotationEffect(.radians(-heading))
                .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.92), value: heading)
                .animation(.spring(response: 0.32, dampingFraction: 0.86), value: position)

                // Fixed on the glass, not turning: the "ahead" marker at the top of the rim.
                VStack(spacing: 2) {
                    Triangle().fill(Palette.ink).frame(width: 10, height: 7)
                    Text("AHEAD")
                        .font(.system(size: 8, weight: .heavy))
                        .tracking(0.6)
                        .foregroundStyle(Palette.ink.opacity(0.7))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color.white, in: Capsule())
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 2)
            }
            .frame(width: side, height: side)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 1))
            .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    /// A step position in screen points from the center, north up, held inside the dial.
    private func point(_ p: DeadReckoning, pxPerMeter: Double, limit: Double) -> CGPoint {
        let x = p.east * pxPerMeter, y = -p.north * pxPerMeter
        let length = (x * x + y * y).squareRoot()
        guard length > limit, length > 0 else { return CGPoint(x: x, y: y) }
        return CGPoint(x: x / length * limit, y: y / length * limit)
    }
}

/// Short ticks every 30° around the rim, longer ones at the quarters.
private struct Ticks: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY), r = min(rect.width, rect.height) / 2
        for i in 0..<12 {
            let a = Double(i) * .pi / 6
            let inner = r - (i % 3 == 0 ? 9 : 5)
            path.move(to: CGPoint(x: c.x + sin(a) * (r - 2), y: c.y - cos(a) * (r - 2)))
            path.addLine(to: CGPoint(x: c.x + sin(a) * inner, y: c.y - cos(a) * inner))
        }
        return path
    }
}

/// Your recent steps as one smooth line, in points relative to the dial's center.
private struct TrailShape: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: c.x + first.x, y: c.y + first.y))
        for p in points.dropFirst() { path.addLine(to: CGPoint(x: c.x + p.x, y: c.y + p.y)) }
        return path
    }
}

/// An arrow pointing up: the way out.
private struct OutArrow: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + h * 0.45))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.66, y: rect.minY + h * 0.45))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.66, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.34, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.34, y: rect.minY + h * 0.45))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + h * 0.45))
        path.closeSubpath()
        return path
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
