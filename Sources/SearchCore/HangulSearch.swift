import Foundation

/// 한글 검색어로 영어·로마자 이름을 찾는다. Petdex 펫 이름은 대부분 영어나 일본어 로마자라
/// 글자를 그대로 비교하면 한글로는 거의 걸리지 않는다. 두 길로 찾는다.
/// 1. 별칭 사전: 짱구 → shinchan, 고양이 → cat처럼 소리로는 닿지 않는 이름.
/// 2. 소리 맞추기: 나루토 → naruto, 피카츄 → pikachu처럼 일본 이름을 한글로 적은 것. 한글을 로마자로 읽고,
///    로마자 표기마다 다르게 적는 소리(ch·j, l·r, 된소리·예사소리, 긴 소리)를 같은 열쇠로 묶어 비교한다.
public enum HangulSearch {

    public static func containsHangul(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) }
    }

    // MARK: 로마자로 읽기

    private static let initials = ["g", "kk", "n", "d", "tt", "r", "m", "b", "pp", "s", "ss", "", "j", "jj", "ch",
                                   "k", "t", "p", "h"]
    private static let medials = ["a", "ae", "ya", "yae", "eo", "e", "yeo", "ye", "o", "wa", "wae", "oe", "yo", "u",
                                  "wo", "we", "wi", "yu", "eu", "ui", "i"]
    private static let finals = ["", "k", "k", "k", "n", "n", "n", "t", "l", "k", "m", "l", "l", "l", "p", "l", "m",
                                 "p", "p", "t", "t", "ng", "t", "t", "k", "t", "p", "t"]

    /// 외래어 표기에 맞춘 로마자. 받침 없는 '으'는 자음만 남기고(스누피 → snupi),
    /// ㅈ·ㅊ 뒤 'y'는 뺀다(피카츄 → pikachu, 고죠 → gojo).
    public static func romanize(_ text: String) -> String {
        var out = ""
        for scalar in text.unicodeScalars {
            guard (0xAC00...0xD7A3).contains(scalar.value) else {
                out += String(scalar).lowercased()
                continue
            }
            let index = Int(scalar.value - 0xAC00)
            let initial = index / 588, medial = (index % 588) / 28, final = index % 28
            var vowel = medials[medial]
            if medial == 18, final == 0, initial != 11 { vowel = "" }        // 스 → s, 크 → k
            if [12, 13, 14].contains(initial), vowel.hasPrefix("y") { vowel.removeFirst() }   // 쵸 → cho
            out += initials[initial] + vowel + finals[final]
        }
        return out
    }

    // MARK: 소리 열쇠

    /// 표기가 달라도 소리가 비슷하면 같은 열쇠가 나오게 줄인다. 영어·로마자 이름과 한글을 읽은 로마자에 똑같이 쓴다.
    public static func phoneticKey(_ text: String) -> String {
        let words = text.lowercased().split { !$0.isLetter }
        return words.map { word -> String in
            var s = String(word).filter { $0.isASCII && $0.isLetter }
            if s.hasSuffix("er") { s = String(s.dropLast(2)) + "a" }       // chopper ≈ 쵸파
            for (from, to) in [("ng", "n"), ("ci", "si"), ("ce", "se"), ("cy", "si"), ("tch", "ch"),
                               ("oo", "u"), ("ou", "o"), ("eo", "o"), ("eu", "u"), ("ae", "e"), ("oe", "e"),
                               ("ch", "j"), ("sh", "s"), ("ts", "s"), ("ph", "f"), ("z", "j"), ("c", "k"), ("q", "k"),
                               ("x", "ks"), ("y", "i"), ("w", "u"), ("l", "r"), ("g", "k"), ("d", "t"), ("b", "p"),
                               ("v", "p"), ("f", "p"), ("h", "")] {
                s = s.replacingOccurrences(of: from, with: to)
            }
            // 겹친 글자는 하나로 (rilakkuma ≈ 리락쿠마)
            var collapsed = ""
            for ch in s where ch != collapsed.last { collapsed.append(ch) }
            return collapsed
        }.joined()
    }

    // MARK: 찾기

    /// 한 항목의 비교용 글. 보이지 않는 글자(U+200C 같은 서식 문자)는 지운다. 남기면 앞 글자와 한 글자로 묶여
    /// "Pikachu\u{200C}"에서 "pikachu"를 찾지 못한다.
    public struct Target {
        /// 원래 글 (소문자).
        public let text: String
        /// 낱말들. camelCase도 나눈다 (TennisKitty → tennis, kitty).
        public let tokens: [String]
        /// 낱말을 띄어 쓴 글. 여러 낱말 별칭(no face)을 찾을 때 쓴다.
        let spaced: String
        /// 낱말마다 시작하는 소리 열쇠 (i번째 낱말부터 끝까지 이어 붙인 것).
        let keySuffixes: [String]

        public init(_ parts: String...) {
            let scalars = parts.joined(separator: " ").unicodeScalars.filter { $0.properties.generalCategory != .format }
            var split = String.UnicodeScalarView()
            var previous: Unicode.Scalar?
            for scalar in scalars {
                if let previous, previous.properties.isLowercase, scalar.properties.isUppercase { split.append(" ") }
                split.append(scalar)
                previous = scalar
            }
            text = String(String.UnicodeScalarView(scalars)).lowercased()
            tokens = String(split).lowercased()
                .split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
            spaced = " " + tokens.joined(separator: " ") + " "
            let keys = tokens.map { phoneticKey($0) }
            keySuffixes = keys.indices.map { keys[$0...].joined() }
        }
    }

    /// 검색어 한 단어. 별칭과 소리 열쇠는 한 번만 만든다.
    struct Word {
        let text: String
        let aliases: [[String]]
        let key: String?

        init(_ raw: String) {
            text = raw.lowercased()
            guard containsHangul(text) else {
                aliases = []
                key = nil
                return
            }
            aliases = (KoreanAliases.terms[text] ?? []).map { $0.split { !$0.isLetter && !$0.isNumber }.map(String.init) }
            // 소리 맞추기는 짧으면 엉뚱한 것이 많이 걸려 열쇠가 5자 이상일 때만 (아냐 → ania는 사전으로만)
            let key = phoneticKey(romanize(text))
            self.key = key.count >= 5 ? key : nil
        }

        /// 0이면 안 맞는다. 클수록 위에 둔다.
        func score(in target: Target) -> Int {
            if target.text.contains(text) {
                return target.tokens.contains { $0.hasPrefix(text) } ? 5 : 4
            }
            for alias in aliases {
                if alias.count == 1, let term = alias.first {
                    // 낱말 단위로만: cat이 catalog에, dog이 edogawa에 걸리지 않게. 긴 이름은 앞부분이 같아도 된다
                    if target.tokens.contains(where: { $0 == term || (term.count >= 5 && $0.hasPrefix(term)) }) { return 4 }
                } else if !alias.isEmpty, target.spaced.contains(" " + alias.joined(separator: " ") + " ") {
                    return 4
                }
            }
            // 소리는 낱말 처음부터 맞아야 한다 (stei|ner rudolf가 naruto로 읽히지 않게). 뒤 낱말로 이어지는 것은 된다 (shin chan)
            if let key, let index = target.keySuffixes.firstIndex(where: { $0.hasPrefix(key) }) { return index == 0 ? 2 : 1 }
            return 0
        }
    }

    /// 모든 단어가 맞는 항목만, 점수 높은 순서로 (같으면 원래 순서).
    public static func search<T>(_ query: String, in items: [T], target: (T) -> Target) -> [T] {
        let words = query.split(separator: " ").map { Word(String($0)) }
        guard !words.isEmpty else { return items }
        var scored: [(offset: Int, score: Int, item: T)] = []
        for (offset, item) in items.enumerated() {
            let t = target(item)
            var total = 0
            for word in words {
                let s = word.score(in: t)
                if s == 0 { total = 0; break }
                total += s
            }
            if total > 0 { scored.append((offset, total, item)) }
        }
        return scored.sorted { $0.score != $1.score ? $0.score > $1.score : $0.offset < $1.offset }.map(\.item)
    }
}
