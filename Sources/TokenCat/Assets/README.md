# 스프라이트 에셋 폴더

빌드 없이 내 그림을 쓰려면 설정 → 러너 → 그림 불러오기(GIF 또는 PNG 여러 장)가 더 쉽습니다.

이 폴더에 `<러너>_<상태>_<번호>.png`를 넣고 다시 빌드(`swift build`)하면
코드로 그린 러너 대신 자동으로 사용됩니다. `<러너>`는 `cat`, `dog`, `rabbit`, `fox`,
`penguin`, `duck`, `dino`, `hedgehog`, `chick`, `frog`, `panda`, `turtle`, `snail`, `octopus`,
`whale`, `ghost`, `slime`, `robot`, `ufo`, `ninja`, `unicorn`, `dragon` 중 하나입니다.
PNG로 바꾼 러너는 장난(점프·하트 등) 동작을 하지 않습니다.

| 파일 (고양이 예) | 용도 | 크기 |
|---|---|---|
| `cat_run_0.png` ~ `cat_run_7.png` | 달리기 8프레임 (걷기/달리기/질주 공용) | 36×22pt (@1x) / 72×44px (@2x) |
| `cat_rainbow_0.png` ~ `cat_rainbow_7.png` | 전력 질주 전용 8프레임 (트레일 포함 권장, 없으면 run 재사용) | 동일 |
| `cat_sleep_0.png`, `cat_sleep_1.png` | 잠자기 2프레임 | 동일 |
| `cat_tired_0.png`, `cat_tired_1.png` | 지침 2프레임 (사용률 80%+) | 동일 |
| `cat_alert_0.png`, `cat_alert_1.png` | 경고 2프레임 (사용률 95%+) | 동일 |

- 한 상태의 프레임 중 하나라도 없으면 그 상태는 코드로 그린 러너로 돌아갑니다.
- 컬러 스프라이트는 라이트 메뉴바에서도 보이도록 외곽선을 넣어 주세요 (§F1).
- 원작 냥캣 이미지는 쓰지 않습니다. 직접 만든 에셋만 넣어 주세요 (§10 저작권 리스크).
- 설정의 러너 색상은 코드로 그린 러너에만 적용됩니다.
