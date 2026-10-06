import SwiftUI
import UniformTypeIdentifiers
import UsageCore

/// 러너 고르기. 각 러너를 컬러로 보여 주고, 고른 러너와 마우스를 올린 러너는 실시간으로 달린다.
/// 맨 아래 '내 러너'는 사용자가 불러온 GIF·PNG로 만든 러너다.
struct RunnerPicker: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var store = CustomRunnerStore.shared
    @StateObject private var hover = HoveredRunner()
    @StateObject private var importState = ImportState()

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Runner.Group.allCases, id: \.self) { group in
                groupTitle(group.rawValue)
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Runner.runners(in: group), id: \.self) { runner in
                        let selected = settings.customRunnerID == nil && settings.runner == runner
                        Button { settings.select(runner) } label: {
                            tile(runner.character, key: runner.rawValue, selected: selected)
                        }
                        .buttonStyle(.plain)
                        .onHover { hover.update(runner.rawValue, $0) }
                        .accessibilityLabel(runner.displayName)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
            if !LocalPack.runners.isEmpty {
                groupTitle("개인 팩")
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(LocalPack.runners, id: \.id) { pack in
                        let id = LocalPack.storageID(pack)
                        let selected = settings.customRunnerID == id
                        Button { settings.select(pack) } label: {
                            tile(pack.character, key: id, selected: selected)
                        }
                        .buttonStyle(.plain)
                        .onHover { hover.update(id, $0) }
                        .accessibilityLabel(pack.name)
                    }
                }
            }
            groupTitle("내 러너")
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(store.runners) { custom in
                    let selected = settings.customRunnerID == custom.id
                    Button { settings.select(custom) } label: {
                        tile(custom.character, key: custom.id, selected: selected)
                    }
                    .buttonStyle(.plain)
                    .onHover { hover.update(custom.id, $0) }
                    .contextMenu { customMenu(custom) }
                    .help("오른쪽 클릭: 이름 바꾸기, 실루엣, 삭제")
                }
                Button(action: importRunner) { addTile }
                    .buttonStyle(.plain)
                    .help("GIF나 PNG(여러 장이면 파일 이름 순서가 프레임 순서)로 러너 만들기")
            }
            if let message = importState.message {
                Text(message).font(.caption).foregroundStyle(importState.isError ? .orange : .secondary)
            }
            Text("직접 만들었거나 쓸 권리가 있는 그림만 넣어 주세요. 불러온 그림은 이 Mac에만 저장되고 어디로도 보내지 않습니다.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    private func groupTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 2)
    }

    private func tile(_ character: RunnerCharacter, key: String, selected: Bool) -> some View {
        let live = selected || hover.key == key
        return VStack(spacing: 3) {
            Group {
                if live {
                    TimelineView(.animation) { context in
                        CharacterCanvas(character: character, theme: settings.spriteTheme, date: context.date,
                                        activity: selected ? .run : .walk)
                    }
                } else {
                    CharacterCanvas(character: character, theme: settings.spriteTheme, date: nil, activity: .stand)
                }
            }
            .frame(height: 40)
            Text(character.name)
                .font(.system(size: 11, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? .primary : .secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.primary.opacity(selected ? 0.08 : (live ? 0.05 : 0.025))))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(selected ? Color.accentColor.opacity(0.9) : Color.primary.opacity(0.06), lineWidth: 1))
        .contentShape(Rectangle())
    }

    private var addTile: some View {
        VStack(spacing: 3) {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(height: 40)
            Text("그림 불러오기").font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func customMenu(_ custom: CustomRunner) -> some View {
        Button("이름 바꾸기…") { rename(custom) }
        Button(custom.silhouette ? "원본 색으로 보기" : "메뉴바 색에 맞춰 실루엣으로 보기") {
            var updated = custom
            updated.silhouette.toggle()
            store.update(updated)
        }
        Divider()
        Button("삭제") {
            if settings.customRunnerID == custom.id { settings.customRunnerID = nil }
            store.delete(custom)
        }
    }

    private func importRunner() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.gif, .png, .jpeg, .heic, .webP, .image]
        panel.allowsMultipleSelection = true
        panel.message = "움직이는 GIF 하나, 또는 프레임 PNG 여러 장을 고르세요"
        panel.prompt = "불러오기"
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        importState.show("그림을 불러오는 중…", error: false)
        store.importImages(from: panel.urls) { [settings, importState] result in
            switch result {
            case .success(let custom):
                settings.select(custom)
                importState.show("'\(custom.name)' 러너를 만들었습니다 (\(custom.frameCount)프레임).", error: false)
            case .failure(let error):
                importState.show(error.localizedDescription, error: true)
            }
        }
    }

    private func rename(_ custom: CustomRunner) {
        let alert = NSAlert()
        alert.messageText = "러너 이름"
        let field = NSTextField(string: custom.name)
        field.frame = NSRect(x: 0, y: 0, width: 220, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "바꾸기")
        alert.addButton(withTitle: "취소")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        var updated = custom
        updated.name = String(name.prefix(12))
        store.update(updated)
    }
}

/// 러너 한 마리를 컬러로 그리는 캔버스. `date`가 있으면 그 시각의 동작을, 없으면 정지 자세를 그린다.
struct CharacterCanvas: View {
    let character: RunnerCharacter
    let theme: SpriteTheme
    let date: Date?
    var activity: CharacterPose.Activity = .run

    var body: some View {
        Canvas { context, size in
            let seconds = date?.timeIntervalSinceReferenceDate ?? 0
            let cycle: Double = activity == .run ? 0.72 : (activity == .walk ? 1.25 : 2.4)
            let phase = CGFloat(seconds.truncatingRemainder(dividingBy: cycle * 100) / cycle)
            let frame = MotionFrame(pose: CharacterPose(activity: activity, phase: phase))
            context.withCGContext { cg in
                CharacterCanvas.draw(cg, size: size, rig: character.rig, frame: frame,
                                     theme: character.theme(theme), themePhase: CGFloat(seconds / 6))
            }
        }
    }

    /// 설계 좌표를 `size`에 맞게 키워 컬러로 그린다.
    static func draw(_ cg: CGContext, size: CGSize, rig: CharacterRig, frame: MotionFrame, theme: SpriteTheme,
                     themePhase: CGFloat, alarm: Bool = false) {
        let scale = min(size.width / Stage.size.width, size.height / Stage.size.height)
        cg.translateBy(x: (size.width - Stage.size.width * scale) / 2,
                       y: (size.height - Stage.size.height * scale) / 2)
        cg.scaleBy(x: scale, y: scale)
        var look = CharacterLook(rich: true, palette: theme.richPalette(rig.palette, phase: themePhase),
                                 tint: .white, outline: max(0.32, 1.1 / scale))
        look.alarm = alarm
        let scene = CharacterScene(rig: rig, pose: frame.pose, transform: frame.transform)
        scene.draw(in: cg, look: look)
        for effect in frame.effects {
            effect.draw(in: cg, around: scene.placedBounds, tint: .white)
        }
    }
}

/// 마우스가 올라간 러너. `@State`를 못 쓰는 이유는 CalibrationForm 참고.
final class HoveredRunner: ObservableObject {
    @Published var key: String?

    func update(_ key: String, _ inside: Bool) {
        if inside { self.key = key } else if self.key == key { self.key = nil }
    }
}

final class ImportState: ObservableObject {
    @Published var message: String?
    @Published var isError = false

    func show(_ message: String, error: Bool) {
        self.message = message
        isError = error
    }
}
