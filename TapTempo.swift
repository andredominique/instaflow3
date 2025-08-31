import SwiftUI
import Combine
import AppKit

// MARK: - Tap Tempo Engine

final class TapTempoEngine: ObservableObject {
    @Published var bpm: Double? = nil
    @Published var tapCount: Int = 0

    private var timestamps: [TimeInterval] = []
    private let maxTapsConsidered = 8
    private let resetTimeout: TimeInterval = 2.0

    func reset() {
        timestamps.removeAll()
        bpm = nil
        tapCount = 0
    }

    func registerTap(now: TimeInterval = Date().timeIntervalSince1970) {
        if let last = timestamps.last, (now - last) > resetTimeout {
            timestamps.removeAll()
        }
        timestamps.append(now)
        tapCount = timestamps.count

        guard timestamps.count >= 2 else {
            bpm = nil
            return
        }

        if timestamps.count > maxTapsConsidered {
            timestamps.removeFirst(timestamps.count - maxTapsConsidered)
            tapCount = timestamps.count
        }

        let intervals = zip(timestamps.dropFirst(), timestamps).map { $0 - $1 }
        guard !intervals.isEmpty else { return }

        let median = Self.median(intervals)
        let filtered = intervals.filter { $0 <= median * 1.8 }
        let avg = filtered.reduce(0, +) / Double(filtered.count)
        let computedBPM = 60.0 / max(0.0001, avg)

        // Allow very fast tempos so SPI can go to 0.10s (needs up to ~600 BPM for 1 beat/image)
        if computedBPM.isFinite, computedBPM > 20, computedBPM <= 600 {
            // Round to nearest multiple of 2 BPM (keeps your original preference)
            bpm = (computedBPM / 2).rounded() * 2
        }
    }

    private static func median(_ arr: [Double]) -> Double {
        guard !arr.isEmpty else { return 0 }
        let sorted = arr.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2
        } else {
            return sorted[mid]
        }
    }
}

// MARK: - Tap Tempo Control (UI)

struct TapTempoControl: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var engine = TapTempoEngine()

    /// Render as a section (embed without GroupBox)
    var embedded: Bool = false

    /// Hide the "Tap Tempo" header line; default false
    var hideHeader: Bool = false

    /// Show a Reset button; default true
    var showReset: Bool = true

    // Default to 1 beat per image
    @State private var beatsPerImage: Int = 1

    // Optional: accept Spacebar when app is focused
    @State private var localKeyMonitor: Any?

    private var suggestedSecondsPerImage: Double? {
        guard let bpm = engine.bpm, bpm > 0 else { return nil }
        return (Double(beatsPerImage) * 60.0) / bpm
    }

    var body: some View {
        let section = VStack(alignment: .leading, spacing: 12) {
            // Header (optional; hidden in FinalPreviewView)
            if !hideHeader {
                HStack {
                    Text("Tap Tempo").font(.body)
                    Spacer()
                    if showReset {
                        Button("Reset") { engine.reset() }
                            .keyboardShortcut("r", modifiers: [.command])
                    }
                }
            }

            // Tap area
            Button { handleTap() } label: {
                VStack(spacing: 6) {
                    if let bpm = engine.bpm {
                        Text("\(bpm, specifier: "%.0f") BPM")
                            .font(.title2.monospacedDigit())
                    } else {
                        Text("Tap to set tempo")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    Text("Global hotkey: Control + Option + Space  •  Space works when the app is focused")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 90)
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.thinMaterial))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(engine.bpm == nil ? Color(nsColor: .quaternaryLabelColor) : Color.blue.opacity(0.25), lineWidth: 1)
            )

            // Timing rows
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("Seconds per image")
                        .frame(width: 140, alignment: .leading)
                        .font(.body)
                    // Lower min to 0.1 and finer steps
                    Slider(value: $model.project.reelSecondsPerImage, in: 0.1...10.0, step: 0.05)
                        .frame(width: 180)
                        .onChange(of: model.project.reelSecondsPerImage) { _, _ in
                            model.project.aspect = .story9x16
                        }
                    Text("\(model.project.reelSecondsPerImage, specifier: "%.2f")s")
                        .frame(width: 64, alignment: .trailing)
                        .font(.body)
                        .monospaced()
                    Spacer()
                }

                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Text("Beats per image:")
                            .font(.body)
                        Picker("", selection: $beatsPerImage) {
                            ForEach([1, 2, 3, 4, 6, 8], id: \.self) { v in
                                Text("\(v)").tag(v)
                            }
                        }
                        .frame(width: 90)
                    }

                    Spacer()

                    if let bpm = engine.bpm, let secs = suggestedSecondsPerImage {
                        Text("Auto: \(secs, specifier: "%.2f")s per image  •  \(bpm, specifier: "%.0f") BPM × \(beatsPerImage)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Tip: Aim for 4–6 taps for a stable reading.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tapTempoGlobalTap)) { _ in handleTap() }
        .onAppear {
            localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { ev in
                if ev.keyCode == 49 && !ev.modifierFlags.contains(.command) {
                    handleTap()
                    return nil
                }
                return ev
            }
        }
        .onDisappear {
            if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
            localKeyMonitor = nil
        }

        if embedded { section } else { GroupBox { section } }
    }

    private func handleTap() {
        engine.registerTap()
        if let secs = suggestedSecondsPerImage {
            // Clamp to new range (0.1–10.0). Frame snapping is applied in FinalPreviewView.onChange.
            model.project.reelSecondsPerImage = min(10.0, max(0.1, secs))
            model.project.aspect = .story9x16
        }
    }
}
