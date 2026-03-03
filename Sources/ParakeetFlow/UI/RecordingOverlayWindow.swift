import AppKit
import SwiftUI

@MainActor
final class RecordingOverlayController {
    private var panel: NSPanel?

    private static let panelSize = NSSize(width: 240, height: 80)

    func show(colors: [Color]) {
        guard panel == nil else { return }

        let hostingView = NSHostingView(rootView: RecordingIndicatorView(barColors: colors))
        hostingView.sizingOptions = []
        hostingView.frame = NSRect(origin: .zero, size: Self.panelSize)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.contentView = hostingView

        // Bottom center of screen
        if let screen = NSScreen.main {
            let x = screen.frame.midX - Self.panelSize.width / 2
            let y = screen.visibleFrame.minY + 24
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.orderFrontRegardless()
        self.panel = panel
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }
}

// MARK: - Siri-style waveform

private struct RecordingIndicatorView: View {
    let barColors: [Color]
    private static let barCount = 5
    @State private var phases: [Bool]

    init(barColors: [Color]) {
        self.barColors = barColors
        _phases = State(initialValue: Array(repeating: false, count: Self.barCount))
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<Self.barCount, id: \.self) { i in
                WaveBar(isAnimating: phases[i], index: i, color: barColors[i])
            }
        }
        .frame(width: 240, height: 80)
        .onAppear {
            for i in 0..<Self.barCount {
                let delay = Double(i) * 0.12
                withAnimation(
                    .easeInOut(duration: 0.5 + Double(i) * 0.08)
                    .repeatForever(autoreverses: true)
                    .delay(delay)
                ) {
                    phases[i] = true
                }
            }
        }
    }
}

private struct WaveBar: View {
    let isAnimating: Bool
    let index: Int
    let color: Color

    private var minHeight: CGFloat {
        [10, 14, 12, 14, 10][index]
    }

    private var maxHeight: CGFloat {
        [34, 54, 68, 54, 34][index]
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(color)
            .frame(width: 10, height: isAnimating ? maxHeight : minHeight)
    }
}
