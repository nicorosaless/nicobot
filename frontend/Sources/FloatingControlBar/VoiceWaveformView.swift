import SwiftUI

struct VoiceWaveformView: View {
    let mode: ActiveBarMode
    let micLevel: Float
    let speakingLevel: Float
    let isLocked: Bool
    var respondingStartTime: Date? = nil

    var body: some View {
        HStack(spacing: 12) {
            orbView
                .frame(width: 28, height: 28)

            waveformLine
                .frame(height: 28)
        }
        .padding(.horizontal, 14)
    }

    // MARK: - Dot orb (ring of 8 dots)

    private var orbView: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let orbitRadius: CGFloat = size.width / 2 - 3
                let n = 8

                switch mode {

                case .idle:
                    let dotR: CGFloat = 1.8
                    for i in 0..<n {
                        let angle = Double(i) / Double(n) * 2 * .pi - .pi / 2
                        let x = center.x + orbitRadius * CGFloat(cos(angle))
                        let y = center.y + orbitRadius * CGFloat(sin(angle))
                        ctx.fill(Path(ellipseIn: CGRect(x: x - dotR, y: y - dotR, width: dotR * 2, height: dotR * 2)),
                                 with: .color(.white.opacity(0.15)))
                    }

                case .listening:
                    let level = CGFloat(micLevel)
                    let rawPhase = (-t * 1.8).truncatingRemainder(dividingBy: 1.0)
                    let phase = rawPhase < 0 ? rawPhase + 1.0 : rawPhase
                    let baseDotR: CGFloat = 2.0
                    let dotR = baseDotR + level * 1.2

                    for i in 0..<n {
                        let angle = Double(i) / Double(n) * 2 * .pi - .pi / 2
                        let pulseOffset = orbitRadius + level * 2.0 * CGFloat(sin(Double(i) * 0.8 + t * 3.0))
                        let x = center.x + pulseOffset * CGFloat(cos(angle))
                        let y = center.y + pulseOffset * CGFloat(sin(angle))
                        let norm = Double(i) / Double(n)
                        let delta = (norm - phase + 1.0).truncatingRemainder(dividingBy: 1.0)
                        let opacity = delta < 0.4 ? 0.15 + (0.4 - delta) / 0.4 * 0.85 : 0.15

                        if opacity > 0.5 {
                            let gr = dotR * 2.2
                            ctx.fill(Path(ellipseIn: CGRect(x: x - gr, y: y - gr, width: gr * 2, height: gr * 2)),
                                     with: .color(.white.opacity(opacity * 0.15)))
                        }
                        ctx.fill(Path(ellipseIn: CGRect(x: x - dotR, y: y - dotR, width: dotR * 2, height: dotR * 2)),
                                 with: .color(.white.opacity(opacity)))
                    }

                case .processing:
                    let rotSpeed = 0.7
                    let rotPhase = (t * rotSpeed).truncatingRemainder(dividingBy: 1.0)
                    let breathe = 0.5 + 0.5 * sin(t * 1.6)

                    for i in 0..<n {
                        let angle = Double(i) / Double(n) * 2 * .pi - .pi / 2
                        let x = center.x + orbitRadius * CGFloat(cos(angle))
                        let y = center.y + orbitRadius * CGFloat(sin(angle))
                        let norm = Double(i) / Double(n)
                        let delta = (norm - rotPhase + 1.0).truncatingRemainder(dividingBy: 1.0)
                        let isActive = delta < 0.375 // 3 of 8 dots lit
                        let dotR: CGFloat = isActive ? 2.0 + CGFloat(breathe) * 0.5 : 1.5
                        let opacity = isActive ? 0.5 + breathe * 0.3 : 0.1

                        ctx.fill(Path(ellipseIn: CGRect(x: x - dotR, y: y - dotR, width: dotR * 2, height: dotR * 2)),
                                 with: .color(.white.opacity(opacity)))
                    }

                case .responding:
                    let elapsed = respondingStartTime.map { t - $0.timeIntervalSinceReferenceDate } ?? 100
                    let boost = max(1.0 - elapsed / 2.0, 0)

                    let faux = abs(sin(t * 3.0))
                    let phase = (t * 2.8).truncatingRemainder(dividingBy: 1.0)
                    let dotR: CGFloat = 2.4 + CGFloat(faux) * 0.3 + CGFloat(boost) * 1.0
                    let fadeWindow = 0.3

                    for i in 0..<n {
                        let angle = Double(i) / Double(n) * 2 * .pi - .pi / 2
                        let x = center.x + orbitRadius * CGFloat(cos(angle))
                        let y = center.y + orbitRadius * CGFloat(sin(angle))
                        let norm = Double(i) / Double(n)
                        let delta = (norm - phase + 1.0).truncatingRemainder(dividingBy: 1.0)
                        let base = delta < fadeWindow ? 0.2 + (fadeWindow - delta) / fadeWindow * 0.8 : 0.2
                        let opacity = min(base + boost * 0.6, 1.0)

                        if opacity > 0.45 {
                            let gr = dotR * 1.8
                            ctx.fill(Path(ellipseIn: CGRect(x: x - gr, y: y - gr, width: gr * 2, height: gr * 2)),
                                     with: .color(.white.opacity(opacity * 0.18)))
                        }
                        ctx.fill(Path(ellipseIn: CGRect(x: x - dotR, y: y - dotR, width: dotR * 2, height: dotR * 2)),
                                 with: .color(.white.opacity(opacity)))
                    }

                case .speaking:
                    let level = CGFloat(speakingLevel)
                    let pulse = 0.5 + 0.5 * sin(t * 2.5)
                    let combined = level * 0.7 + CGFloat(pulse) * 0.3
                    let dotR: CGFloat = 2.2 + combined * 1.0
                    let warmTint = Color(red: 1.0, green: 0.95, blue: 0.85)

                    for i in 0..<n {
                        let angle = Double(i) / Double(n) * 2 * .pi - .pi / 2
                        let x = center.x + orbitRadius * CGFloat(cos(angle))
                        let y = center.y + orbitRadius * CGFloat(sin(angle))
                        let wave = sin(Double(i) * 0.9 + t * 2.0)
                        let opacity = 0.3 + Double(combined) * 0.5 + wave * 0.15

                        if opacity > 0.5 {
                            let gr = dotR * 2.0
                            ctx.fill(Path(ellipseIn: CGRect(x: x - gr, y: y - gr, width: gr * 2, height: gr * 2)),
                                     with: .color(warmTint.opacity(opacity * 0.12)))
                        }
                        ctx.fill(Path(ellipseIn: CGRect(x: x - dotR, y: y - dotR, width: dotR * 2, height: dotR * 2)),
                                 with: .color(warmTint.opacity(min(opacity, 1.0))))
                    }

                case .done:
                    let breathe = 0.5 + 0.5 * sin(t * 0.9)
                    let dotR: CGFloat = 2.0 + CGFloat(breathe) * 0.3
                    let opacity = 0.38 + 0.18 * breathe
                    for i in 0..<n {
                        let angle = Double(i) / Double(n) * 2 * .pi - .pi / 2
                        let x = center.x + orbitRadius * CGFloat(cos(angle))
                        let y = center.y + orbitRadius * CGFloat(sin(angle))
                        ctx.fill(Path(ellipseIn: CGRect(x: x - dotR, y: y - dotR, width: dotR * 2, height: dotR * 2)),
                                 with: .color(.white.opacity(opacity)))
                    }
                }
            }
        }
    }

    // MARK: - Horizontal reactive waveform line

    private var waveformLine: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSinceReferenceDate

                switch mode {

                case .idle:
                    let rect = CGRect(x: 0, y: size.height / 2 - 1, width: size.width, height: 2)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 1),
                             with: .color(.white.opacity(0.2)))

                case .done:
                    let breathe = CGFloat(0.5 + 0.5 * sin(t * 0.9))
                    let h = 2.0 + breathe * 2.5
                    let opacity = 0.3 + Double(breathe) * 0.15
                    let rect = CGRect(x: 0, y: size.height / 2 - h / 2, width: size.width, height: h)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: h / 2),
                             with: .color(.white.opacity(opacity)))

                case .listening:
                    let level = CGFloat(micLevel)
                    let barCount = 36
                    let barW: CGFloat = 2.0
                    let totalGap = size.width - barW * CGFloat(barCount)
                    let gap = totalGap / CGFloat(barCount - 1)

                    for i in 0..<barCount {
                        let x = CGFloat(i) * (barW + gap)
                        let pos = Double(i) / Double(barCount)
                        let wave1 = sin(pos * .pi * 3.0 + t * 4.0)
                        let wave2 = sin(pos * .pi * 5.0 + t * 6.5) * 0.4
                        let wave3 = sin(pos * .pi * 2.0 + t * 3.0) * 0.25
                        let envelope = pow(sin(pos * .pi), 1.2)
                        let amplitude = (wave1 + wave2 + wave3) / 1.65 * 0.5 + 0.5
                        let h = 2.0 + amplitude * envelope * (4.0 + level * 22.0)
                        let opacity = min(0.3 + amplitude * 0.3 + Double(level) * 0.4, 1.0)

                        let barRect = CGRect(x: x, y: size.height / 2 - h / 2, width: barW, height: h)
                        ctx.fill(Path(roundedRect: barRect, cornerRadius: barW / 2),
                                 with: .color(.white.opacity(opacity)))
                    }

                case .processing:
                    let barCount = 36
                    let barW: CGFloat = 2.0
                    let totalGap = size.width - barW * CGFloat(barCount)
                    let gap = totalGap / CGFloat(barCount - 1)
                    let scanPos = 0.5 + 0.5 * sin(t * 1.6)

                    for i in 0..<barCount {
                        let x = CGFloat(i) * (barW + gap)
                        let pos = Double(i) / Double(barCount)
                        let dist = abs(pos - scanPos)
                        let pulse = max(0, 1.0 - dist * 5.0)
                        let gaussPulse = pulse * pulse
                        let h = 2.0 + CGFloat(gaussPulse) * 8.0
                        let opacity = 0.08 + gaussPulse * 0.45

                        let barRect = CGRect(x: x, y: size.height / 2 - h / 2, width: barW, height: h)
                        ctx.fill(Path(roundedRect: barRect, cornerRadius: barW / 2),
                                 with: .color(.white.opacity(opacity)))
                    }

                case .responding:
                    let elapsed = respondingStartTime.map { t - $0.timeIntervalSinceReferenceDate } ?? 100
                    let boost = max(1.0 - elapsed / 2.0, 0)
                    let barCount = 28
                    let barW: CGFloat = 2.0
                    let totalGap = size.width - barW * CGFloat(barCount)
                    let gap = totalGap / CGFloat(barCount - 1)

                    for i in 0..<barCount {
                        let x = CGFloat(i) * (barW + gap)
                        let pos = Double(i) / Double(barCount)
                        let wave = sin(pos * .pi * 4.0 + t * 5.0)
                        let wave2 = sin(pos * .pi * 7.0 + t * 3.5) * 0.3
                        let envelope = sin(pos * .pi)
                        let amplitude = (wave + wave2) * 0.5 + 0.5
                        let h = 2.0 + amplitude * envelope * (8.0 + CGFloat(boost) * 6.0)
                        let opacity = min(0.4 + amplitude * 0.35 + boost * 0.3, 1.0)

                        let barRect = CGRect(x: x, y: size.height / 2 - h / 2, width: barW, height: h)
                        ctx.fill(Path(roundedRect: barRect, cornerRadius: barW / 2),
                                 with: .color(.white.opacity(opacity)))
                    }

                case .speaking:
                    let level = CGFloat(speakingLevel)
                    let barCount = 36
                    let barW: CGFloat = 2.0
                    let totalGap = size.width - barW * CGFloat(barCount)
                    let gap = totalGap / CGFloat(barCount - 1)
                    let warmTint = Color(red: 1.0, green: 0.95, blue: 0.85)

                    for i in 0..<barCount {
                        let x = CGFloat(i) * (barW + gap)
                        let pos = Double(i) / Double(barCount)
                        let wave1 = sin(pos * .pi * 3.0 - t * 4.0)
                        let wave2 = sin(pos * .pi * 5.0 - t * 2.5) * 0.3
                        let envelope = pow(sin(pos * .pi), 1.2)
                        let amplitude = (wave1 + wave2) / 1.3 * 0.5 + 0.5
                        let h = 3.0 + amplitude * envelope * (5.0 + level * 18.0)
                        let opacity = min(0.3 + amplitude * 0.3 + Double(level) * 0.4, 1.0)

                        let barRect = CGRect(x: x, y: size.height / 2 - h / 2, width: barW, height: h)
                        ctx.fill(Path(roundedRect: barRect, cornerRadius: barW / 2),
                                 with: .color(warmTint.opacity(opacity)))
                    }
                }
            }
        }
    }
}

#if DEBUG
struct VoiceWaveformView_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 12) {
            ForEach([ActiveBarMode.listening, .processing, .speaking, .responding, .done], id: \.self) { m in
                VStack(spacing: 4) {
                    Text(String(describing: m))
                        .foregroundColor(.white)
                        .font(.system(size: 9))
                    VoiceWaveformView(mode: m, micLevel: 0.5, speakingLevel: 0.6, isLocked: false,
                                      respondingStartTime: m == .responding ? Date() : nil)
                        .frame(width: 180, height: 44)
                        .background(Color.white.opacity(0.07))
                        .clipShape(Capsule())
                }
            }
        }
        .padding()
        .background(Color.black)
        .frame(width: 1000, height: 110)
    }
}
#endif
