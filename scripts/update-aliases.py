#!/usr/bin/env python3 -I
"""Petdex 펫 이름의 한국어 공식 이름을 Wikidata(CC0)에서 찾아 Sources/SearchCore/GeneratedAliases.swift를 만든다.

Petdex 이름(영어)과 영어 이름이 같은 '가상의 인물'(Q95074와 그 하위 분류)만 고르고, 그 항목의 한국어 이름을
한글 검색어로 쓴다. 손으로 고른 별칭(KoreanAliases.swift)과 함께 쓰며, 앱은 실행 중에 Wikidata에 접속하지 않는다.

    python3 -I scripts/update-aliases.py                     # Wikidata에서 받아 만들기
    python3 -I scripts/update-aliases.py --save raw.json     # 받은 그대로도 저장
    python3 -I scripts/update-aliases.py --load raw.json     # 저장한 것으로 다시 만들기 (Wikidata 조회는 오래 걸린다)
"""
import json
import re
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

MANIFEST = "https://petdex.dev/api/manifest"
SPARQL = "https://query.wikidata.org/sparql"
AGENT = "RunTime-alias-builder/1.0 (https://github.com/youminki/RunTime)"
OUT = Path(__file__).resolve().parent.parent / "Sources/SearchCore/GeneratedAliases.swift"
BATCH = 120
HANGUL_WORD = re.compile(r"[가-힣]{2,}")
# 동음이의를 가르는 괄호 속 말 ("블레이드 (만화)"의 만화)은 이름이 아니라 버린다
PARENTHESES = re.compile(r"\s*[(\[（].*?[)\]）]")


def fetch(url, data=None):
    request = urllib.request.Request(url, data=data, headers={"User-Agent": AGENT, "Accept": "application/json"})
    with urllib.request.urlopen(request, timeout=120) as response:
        return json.load(response)


def candidates(manifest):
    """펫 이름 전체와 앞 한두 낱말 (Luffy Gear 5 → Luffy Gear 5, Luffy, Luffy Gear)."""
    names = set()
    for pet in manifest["pets"]:
        words = re.sub(r"[^A-Za-z0-9 .'-]", " ", pet.get("displayName", "")).split()
        for n in (len(words), 1, 2):
            name = " ".join(words[:n]).strip(" .-'")
            if len(name) >= 3 and re.search("[A-Za-z]", name):
                names.add(name)
    return sorted(names)


def korean_names(names):
    found = {}
    for start in range(0, len(names), BATCH):
        chunk = names[start:start + BATCH]
        values = " ".join(json.dumps(n) + "@en" for n in chunk)
        query = f"""SELECT ?en ?ko WHERE {{
          VALUES ?en {{ {values} }}
          ?item rdfs:label ?en .
          ?item wdt:P31/wdt:P279* wd:Q95074 .
          ?item rdfs:label ?ko . FILTER(LANG(?ko) = "ko")
        }}"""
        body = urllib.parse.urlencode({"query": query, "format": "json"}).encode()
        for attempt in range(3):
            try:
                rows = fetch(SPARQL, body)["results"]["bindings"]
                break
            except Exception as error:   # 시간 초과·잠깐 막힘은 쉬었다가 다시
                print(f"  다시 시도 ({error})", file=sys.stderr)
                time.sleep(5 * (attempt + 1))
        else:
            rows = []
        for row in rows:
            found.setdefault(row["ko"]["value"], set()).add(row["en"]["value"].lower())
        print(f"{min(start + BATCH, len(names))}/{len(names)} → {len(found)}개", file=sys.stderr)
        time.sleep(1)
    return found


def aliases(found):
    """한국어 이름 전체(띄어쓰기 없이)와 그 안의 한글 낱말을 검색어로 쓴다 (몽키 D. 루피 → 몽키D.루피, 몽키, 루피)."""
    table = {}
    for korean, english in found.items():
        korean = PARENTHESES.sub("", korean).strip()
        keys = {re.sub(r"\s+", "", korean)} | set(HANGUL_WORD.findall(korean))
        for key in keys:
            if HANGUL_WORD.search(key):
                table.setdefault(key, set()).update(english)
    return table


def main():
    args = sys.argv[1:]
    if "--load" in args:
        found = {k: set(v) for k, v in json.loads(Path(args[args.index("--load") + 1]).read_text()).items()}
    else:
        found = korean_names(candidates(fetch(MANIFEST)))
    if "--save" in args:
        Path(args[args.index("--save") + 1]).write_text(
            json.dumps({k: sorted(v) for k, v in found.items()}, ensure_ascii=False, indent=0))
    table = aliases(found)
    lines = [
        "// scripts/update-aliases.py가 만든 파일이다. 손으로 고치지 말고 스크립트를 다시 돌린다.",
        "// 출처: Wikidata (CC0) 가상의 인물 항목의 한국어 이름",
        "",
        "extension KoreanAliases {",
        "    static let generated: [String: [String]] = [",
    ]
    for key in sorted(table):
        values = ", ".join(json.dumps(v, ensure_ascii=False) for v in sorted(table[key]))
        lines.append(f"        {json.dumps(key, ensure_ascii=False)}: [{values}],")
    lines += ["    ]", "}", ""]
    OUT.write_text("\n".join(lines))
    print(f"{len(table)}개 한글 검색어 → {OUT.name}")


if __name__ == "__main__":
    main()
