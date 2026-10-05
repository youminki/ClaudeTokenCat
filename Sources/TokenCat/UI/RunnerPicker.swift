import SwiftUI
import UsageCore

/// 러너 고르기. 각 러너를 실제 스프라이트로 보여 주고, 고른 러너는 달리는 모습으로 움직인다.
struct RunnerPicker: View {
    @Binding var selection: Runner
    let theme: SpriteTheme
    @Environment(\.colorScheme) private var colorScheme

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Runner.allCases, id: \.self) { runner in
                Button { selection = runner } label: { tile(runner) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(runner.displayName)
                    .accessibilityAddTraits(runner == selection ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }

    private func tile(_ runner: Runner) -> some View {
        let selected = runner == selection
        let frames = Self.frames(runner: runner, theme: theme, dark: colorScheme == .dark)
        return VStack(spacing: 4) {
            Group {
                if selected {
                    TimelineView(.periodic(from: .now, by: Self.frameInterval)) { context in
                        sprite(frames[Self.frameIndex(at: context.date, count: frames.count)])
                    }
                } else {
                    sprite(frames[0])
                }
            }
            .frame(width: 54, height: 33)
            Text(runner.displayName)
                .font(.system(size: 11, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? .primary : .secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(selected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5))
        .contentShape(Rectangle())
    }

    private static let frameInterval = CatState.running.frameInterval

    private static func frameIndex(at date: Date, count: Int) -> Int {
        Int(date.timeIntervalSinceReferenceDate / frameInterval) % count
    }

    private func sprite(_ image: NSImage) -> some View {
        Image(nsImage: image).resizable().interpolation(.none)
    }

    /// labelColor가 창 테마에 맞게 칠해지도록 테마별로 한 번씩 래스터라이즈해 둔다.
    private static var cache: [String: [NSImage]] = [:]

    private static func frames(runner: Runner, theme: SpriteTheme, dark: Bool) -> [NSImage] {
        let key = "\(runner.rawValue)|\(theme.rawValue)|\(dark)"
        if let cached = cache[key] { return cached }
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let frames = SpriteFrames.frames(for: .normal(.running), runner: runner, theme: theme).map {
            SpriteRasterizer.rasterize($0, size: SpriteFrames.spriteSize, appearance: appearance)
        }
        cache[key] = frames
        return frames
    }
}
