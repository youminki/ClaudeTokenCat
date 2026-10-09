import Foundation

/// 메뉴바 러너 종류. 그림은 `CharacterRig`가 벡터로 그린다.
enum Runner: String, CaseIterable {
    case cat, dog, rabbit, fox, penguin, duck, dino, hedgehog
    case chick, frog, panda, turtle, snail, octopus, whale
    case ghost, slime, robot, ufo, ninja, unicorn, dragon
    case tiger, raccoon, bear, sheep, blackCat, goldenCat

    enum Group: String, CaseIterable {
        case animal = "동물"
        case fantasy = "판타지"
    }

    var group: Group {
        switch self {
        case .ghost, .slime, .robot, .ufo, .ninja, .unicorn, .dragon: return .fantasy
        default: return .animal
        }
    }

    static func runners(in group: Group) -> [Runner] {
        allCases.filter { $0.group == group }
    }

    var displayName: String {
        switch self {
        case .cat: return "고양이"
        case .dog: return "강아지"
        case .rabbit: return "토끼"
        case .fox: return "여우"
        case .penguin: return "펭귄"
        case .duck: return "오리"
        case .dino: return "공룡"
        case .hedgehog: return "고슴도치"
        case .chick: return "병아리"
        case .frog: return "개구리"
        case .panda: return "판다"
        case .turtle: return "거북이"
        case .snail: return "달팽이"
        case .octopus: return "문어"
        case .whale: return "고래"
        case .ghost: return "유령"
        case .slime: return "슬라임"
        case .robot: return "로봇"
        case .ufo: return "UFO"
        case .ninja: return "닌자"
        case .unicorn: return "유니콘"
        case .dragon: return "드래곤"
        case .tiger: return "호랑이"
        case .raccoon: return "너구리"
        case .bear: return "곰"
        case .sheep: return "양"
        case .blackCat: return "검은 고양이"
        case .goldenCat: return "황금 고양이"
        }
    }

    /// 팝오버에서 러너를 누르면 말풍선으로 내는 소리.
    var sound: String {
        switch self {
        case .cat: return "냥"
        case .dog: return "멍멍"
        case .rabbit: return "깡총"
        case .fox: return "캥"
        case .penguin: return "뒤뚱뒤뚱"
        case .duck: return "꽥"
        case .dino: return "크아앙"
        case .hedgehog: return "킁킁"
        case .chick: return "삐약"
        case .frog: return "개굴"
        case .panda: return "냠냠"
        case .turtle: return "엉금엉금"
        case .snail: return "느릿느릿"
        case .octopus: return "뽀글뽀글"
        case .whale: return "푸우"
        case .ghost: return "부우"
        case .slime: return "말랑"
        case .robot: return "삐빅"
        case .ufo: return "삐융"
        case .ninja: return "닌닌"
        case .unicorn: return "히힝"
        case .dragon: return "크르릉"
        case .tiger: return "어흥"
        case .raccoon: return "킁킁"
        case .bear: return "꿀꺽"
        case .sheep: return "메에"
        case .blackCat: return "야옹"
        case .goldenCat: return "반짝냥"
        }
    }

    /// 칸에 맞게 크기를 맞춘 그림. 계산은 러너마다 한 번만 한다.
    var rig: CharacterRig {
        if let cached = Self.fitted[self] { return cached }
        let fitted = FittedRig(baseRig)
        Self.fitted[self] = fitted
        return fitted
    }

    private static var fitted: [Runner: CharacterRig] = [:]

    private var baseRig: CharacterRig {
        switch self {
        case .cat: return Quadruped.cat
        case .dog: return Quadruped.dog
        case .rabbit: return Quadruped.rabbit
        case .fox: return Quadruped.fox
        case .panda: return Quadruped.panda
        case .unicorn: return Quadruped.unicorn
        case .hedgehog: return Quadruped.hedgehog
        case .chick: return Bird.chick
        case .duck: return Bird.duck
        case .penguin: return Bird.penguin
        case .dino: return Reptile.dino
        case .dragon: return Reptile.dragon
        case .frog: return Frog()
        case .turtle: return Turtle()
        case .snail: return Snail()
        case .octopus: return Octopus()
        case .whale: return Whale()
        case .ghost: return Ghost()
        case .slime: return Slime()
        case .robot: return Robot()
        case .ufo: return UFO()
        case .ninja: return Ninja()
        case .tiger: return Quadruped.tiger
        case .raccoon: return Quadruped.raccoon
        case .bear: return Quadruped.bear
        case .sheep: return Quadruped.sheep
        case .blackCat: return Quadruped.blackCat
        case .goldenCat: return Quadruped.goldenCat
        }
    }
}
