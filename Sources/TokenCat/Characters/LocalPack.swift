import Foundation

/// 저장소에 올리지 않는 개인용 러너 팩.
///
/// `Sources/TokenCat/LocalPack/`(.gitignore)에 `@objc(TokenCatLocalPack)` 클래스를 두고 이 프로토콜을 따르게 하면
/// 그 Mac에서 빌드한 앱에만 러너가 더해진다. 저작권이 있는 캐릭터를 공개 저장소에 싣지 않고 개인적으로
/// 쓰려는 경우를 위한 연결 고리라, 이 파일은 팩이 없어도 빌드된다.
/// 그림 파일은 `Assets/LocalPack/`(.gitignore)에 두면 번들에 함께 들어가 `Bundle.module`로 읽을 수 있다.
protocol LocalRunnerPack: AnyObject {
    static var runners: [PackRunner] { get }
}

/// 개인 팩의 러너 하나.
struct PackRunner {
    let id: String
    let name: String
    /// 무대에서 누르면 말풍선으로 하는 말. 여러 개면 돌아가며 쓴다.
    let lines: [String]
    let rig: CharacterRig

    var character: RunnerCharacter {
        RunnerCharacter(key: "pack.\(id)", name: name, sound: lines.randomElement() ?? name,
                        rig: LocalPack.fitted(self), assetPrefix: nil, fixedTheme: .natural)
    }
}

enum LocalPack {
    /// 팩 클래스를 이름으로 찾는다. 팩 파일이 없으면 빈 목록.
    static let runners: [PackRunner] = (NSClassFromString("TokenCatLocalPack") as? LocalRunnerPack.Type)?.runners ?? []

    private static var fittedRigs: [String: CharacterRig] = [:]

    /// 크기 맞춤은 장면 10개를 재므로 러너마다 한 번만 한다. 설정 목록은 다시 그릴 때마다 모든 러너를 읽는다.
    /// 메인 스레드에서만 쓴다.
    static func fitted(_ runner: PackRunner) -> CharacterRig {
        if let cached = fittedRigs[runner.id] { return cached }
        let fitted = FittedRig(runner.rig)
        fittedRigs[runner.id] = fitted
        return fitted
    }

    /// 저장 id는 내 러너(UUID)와 겹치지 않게 앞에 붙인다.
    static func storageID(_ runner: PackRunner) -> String { "pack:\(runner.id)" }

    static func runner(storageID: String?) -> PackRunner? {
        guard let storageID, storageID.hasPrefix("pack:") else { return nil }
        let id = storageID.dropFirst("pack:".count)
        return runners.first { $0.id == id }
    }
}
