import SwiftUI

/// Three steppers (green / yellow / red) for editing a `Timing` in 15-second
/// increments, showing each value as M:SS.
struct TimingEditor: View {
    @Binding var timing: Timing

    var body: some View {
        TimeStepperRow(label: "Green", color: .green, seconds: $timing.green)
        TimeStepperRow(label: "Yellow", color: .yellow, seconds: $timing.yellow)
        TimeStepperRow(label: "Red", color: .red, seconds: $timing.red)
    }
}

private struct TimeStepperRow: View {
    let label: String
    let color: Color
    @Binding var seconds: Int

    var body: some View {
        Stepper(value: $seconds, in: 0...3600, step: 15) {
            HStack(spacing: 8) {
                Circle().fill(color).frame(width: 10, height: 10)
                Text(label)
                Spacer()
                Text(seconds.asMMSS)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A compact, read-only summary of a timing: three coloured dots with times,
/// plus a "default" / "custom" badge.
struct TimingSummary: View {
    let timing: Timing
    let isCustom: Bool

    var body: some View {
        HStack(spacing: 12) {
            dot(.green, timing.green)
            dot(.yellow, timing.yellow)
            dot(.red, timing.red)
            Text(isCustom ? "custom" : "default")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(.quaternary, in: Capsule())
        }
        .font(.caption)
        .monospacedDigit()
    }

    private func dot(_ color: Color, _ seconds: Int) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(seconds.asMMSS)
        }
    }
}
