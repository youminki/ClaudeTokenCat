import Testing
@testable import SearchCore

/// Petdex 목록에 실제로 있는 이름들 (slug, 이름).
private let pets: [(slug: String, name: String)] = [
    ("naruto", "Naruto"), ("totoro", "Totoro"), ("capvolt", "Pikachu\u{200C}"), ("doraemon", "Doraemon"),
    ("crayon-shin-chan", "Crayon Shin-chan"), ("kuromi", "Kuromi"), ("cinnamoroll", "Cinnamoroll"),
    ("chopper", "Chopper"), ("luffy-gear-5", "Luffy Gear 5"), ("ruby", "Ruby"), ("snoopy", "Snoopy"),
    ("tanjiro", "Tanjiro"), ("gojo-satoru", "Gojo Satoru"), ("rilakkuma", "Rilakkuma"), ("black-cat", "Black Cat"),
    ("mangeureojin-gom", "망그러진곰"), ("homelander", "Homelander"),
]

private func find(_ query: String) -> [String] {
    HangulSearch.search(query, in: pets) { HangulSearch.Target($0.slug, $0.name) }.map(\.slug)
}

@Suite struct HangulSearchTests {
    @Test func romanizesForLoanwords() {
        #expect(HangulSearch.romanize("나루토") == "naruto")
        #expect(HangulSearch.romanize("피카츄") == "pikachu")
        #expect(HangulSearch.romanize("고죠") == "gojo")
        #expect(HangulSearch.romanize("스누피") == "snupi")
    }

    @Test func findsJapaneseNamesBySound() {
        #expect(find("나루토") == ["naruto"])
        #expect(find("토토로") == ["totoro"])
        #expect(find("피카츄") == ["capvolt"])   // 이름 끝에 보이지 않는 글자가 붙어 있다
        #expect(find("도라에몽") == ["doraemon"])
        #expect(find("쿠로미") == ["kuromi"])
        #expect(find("시나모롤") == ["cinnamoroll"])
        #expect(find("리락쿠마") == ["rilakkuma"])
        #expect(find("고죠").contains("gojo-satoru"))
    }

    @Test func findsByAliasWhereSoundDiffers() {
        #expect(find("짱구") == ["crayon-shin-chan"])
        #expect(find("쵸파") == ["chopper"])
        #expect(find("고양이") == ["black-cat"])
        #expect(find("스누피") == ["snoopy"])
    }

    @Test func aliasHitsRankAboveLooseSoundHits() {
        // 루피는 소리로 Ruby에도 닿지만, 사전에 있는 Luffy가 먼저 나와야 한다
        #expect(find("루피").first == "luffy-gear-5")
    }

    @Test func aliasesMatchWholeWordsOnly() {
        let noisy: [(slug: String, name: String)] = [("alder-catalog-foot", "Alder Catalog Foot"),
                                                       ("edogawa-conan", "Edogawa Conan"), ("tennis-kitty", "TennisKitty")]
        let found = { (q: String) in HangulSearch.search(q, in: noisy) { HangulSearch.Target($0.slug, $0.name) }.map(\.slug) }
        #expect(found("고양이") == ["tennis-kitty"])   // catalog의 cat은 아니고, camelCase의 Kitty는 맞다
        #expect(found("강아지").isEmpty)
        #expect(find("고양이 검은") == ["black-cat"])
    }

    @Test func soundMatchesStartAtWordBoundary() {
        let list: [(slug: String, name: String)] = [("rudolf-steiner", "Rudolf Steiner"), ("naruto", "Naruto")]
        #expect(HangulSearch.search("나루토", in: list) { HangulSearch.Target($0.slug, $0.name) }.map(\.slug) == ["naruto"])
    }

    @Test func keepsExistingBehaviour() {
        #expect(find("망그러진") == ["mangeureojin-gom"])
        #expect(find("home") == ["homelander"])
        #expect(find("").count == pets.count)
        #expect(find("없는이름입니다").isEmpty)
    }

    @Test func shortHangulDoesNotMatchBySoundAlone() {
        // 두 글자 소리는 엉뚱한 것이 많이 걸려 사전에 없으면 소리로는 찾지 않는다
        #expect(find("호무").isEmpty)
    }
}
