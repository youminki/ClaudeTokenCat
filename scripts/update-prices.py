#!/usr/bin/env python3 -I
"""Claude 모델 단가를 LiteLLM 가격 데이터에서 가져와 Sources/UsageCore/PricingData.swift를 만든다.

ccusage도 같은 데이터(model_prices_and_context_window.json, MIT)를 쓴다. 앱은 실행 중에 가격을 받지 않고,
새 모델이 나오면 이 스크립트를 다시 돌려 커밋한다.

    python3 -I scripts/update-prices.py            # 받아서 만들기
    python3 -I scripts/update-prices.py prices.json  # 받아 둔 파일로 만들기
"""
import json
import re
import sys
import urllib.request
from datetime import date
from pathlib import Path

SOURCE = "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"
OUT = Path(__file__).resolve().parent.parent / "Sources/UsageCore/PricingData.swift"
# Anthropic이 직접 내는 이름만 (Bedrock·Vertex 변형과 날짜 붙은 중복은 접두어 맞추기로 충분하다)
NAME = re.compile(r"^claude-[a-z0-9-]+$")
DATED = re.compile(r"-\d{8}$")


def load():
    if len(sys.argv) > 1:
        return json.loads(Path(sys.argv[1]).read_text())
    with urllib.request.urlopen(SOURCE, timeout=60) as response:
        return json.load(response)


def per_million(value):
    return round(value * 1_000_000, 6)


def main():
    data = load()
    rows = []
    for name, info in data.items():
        if not NAME.match(name) or DATED.search(name) or info.get("litellm_provider") != "anthropic":
            continue
        try:
            rates = [per_million(info[key]) for key in
                     ("input_cost_per_token", "output_cost_per_token",
                      "cache_creation_input_token_cost", "cache_read_input_token_cost")]
        except KeyError:
            continue
        rows.append((name, rates))
    if not rows:
        sys.exit("Claude 단가를 찾지 못했습니다. 데이터 형식이 바뀌었는지 확인하세요.")
    rows.sort()

    def number(x):
        return f"{x:g}"

    lines = [
        "// scripts/update-prices.py가 만든 파일이다. 손으로 고치지 말고 스크립트를 다시 돌린다.",
        f"// 출처: LiteLLM model_prices_and_context_window.json (MIT), {date.today().isoformat()}",
        "",
        "extension PricingTable {",
        "    /// 모델 이름별 단가 (USD / 1M tokens). 캐시 쓰기는 5분 TTL 단가.",
        "    static let generated: [(prefix: String, rates: Rates)] = [",
    ]
    width = max(len(name) for name, _ in rows) + 3
    for name, (inp, out, write, read) in rows:
        key = f'"{name}",'.ljust(width)
        lines.append(f"        ({key} Rates(input: {number(inp)}, output: {number(out)}, "
                     f"cacheWrite: {number(write)}, cacheRead: {number(read)})),")
    lines += ["    ]", "}", ""]
    OUT.write_text("\n".join(lines))
    print(f"{len(rows)}개 모델 → {OUT.relative_to(OUT.parent.parent.parent)}")


if __name__ == "__main__":
    main()
