---
name: ink-shell-design
description: 현자의 잉크 셸(아웃게임) 디자인 시스템 구현 규칙. 트루 블랙+골드 컬러 토큰, 한/영 이중 타이포, 잉크 플러드 전환 등 모션 토큰, 화면별(타이틀/챕터·레벨 선택/클리어/일시정지/설정) 스펙, 컴포넌트 스펙을 Flutter 상수로 정의. lib/ui, lib/meta 코드 작성·수정, 셸 화면·HUD·전환 애니메이션 작업 시 반드시 이 스킬을 사용할 것.
---

# 셸 디자인 시스템 구현 규칙

SSOT: `docs/PHILOSOPHERS_INK_DESIGN.md` 8.4장. 시각 참고 `docs/philosophers_ink_shell_mockup.html`
(충돌 시 GDD 우선). 디자인 언어 원전: `docs/design-references/lam.md` (람보르기니 — 어둠을 여백으로,
표면 명도 층위로 깊이 표현). bugatti.md/ferrari.md는 대안 레퍼런스 — 방향성 재검토 요청 시에만 읽는다.

## 핵심 철학 3원칙

1. **셸은 조용하게, 인게임은 화려하게** — 셸의 무채색이 레벨 진입 순간 챕터 단색을 터뜨린다.
2. **골드 희소성: 화면당 골드 요소 1~2개.** 골드 = 가치·현재·달성 (CTA, 현재 레벨, 획득 별)에만.
   잠김/비활성은 색이 아니라 명도(text-3)와 보더 유무로.
3. **전환은 의식(ritual)처럼** — 무게감 있는 duration + 강한 ease. 가볍고 빠른 팝 금지.

## 토큰 (`lib/ui/tokens.dart`에 이대로 상수화)

```dart
// 표면 — 그을린 웜 블랙
black0 #050505 / black1 #0A0A09 / black2 #131311 / black3 #1D1C19 / hairline #29271F
// 골드
gold #C9A227 / goldHi #E8C95A / goldDeep #8F7118
// 텍스트 — 순백 금지, 양피지
parchment #F2EDDF / text2 #9C968A / text3 #5E5A50
// 챕터 스와치 (셸에 허용되는 유일한 유채색)
nigredo #1D1418 / albedo #E9E5DB / citrinitas #D9A62E / rubedo #8E1F2F
// duration
fast 120ms / base 240ms / ritual 650ms
```

- 위젯 코드에 hex 직접 기입 금지 — tokens.dart 참조만.

## 타이포 (GDD 8.4.3)

- Display(라틴): Anton 계열 컨덴스드 헤비, 대문자 전용, 자간 +0.02~0.05em — 챕터명·레벨 번호·로고.
- 한글: Pretendard (Black~Regular), 대형은 자간 −1~−2%. 본문 15px / 캡션 12px / 아이브로우 11px(+0.25~0.35em).
- 숫자는 tabular figures (`FontFeature.tabularFigures()`).
- 폰트 에셋: `assets/fonts/` — 없으면 시스템 폴백으로 진행하되 TODO 보고.

## 모션 (GDD 8.4.5)

- **잉크 플러드** (시그니처): 레벨 셀 탭 좌표 기점 챕터색 원 확장 → 화면 삼킴 → 그대로 인게임 배경.
  650ms, easeInOutQuart. 복귀는 역방향. 셸→인게임의 유일한 유채색 순간.
- 별 스탬프: scale 1.6→1.0 오버슛 + 글로우, 250ms 스태거, 각각 햅틱 light impact.
- 타이틀 플라스크: 글로우 사인파 4s, 골드 입자 상승 6~8개 불규칙 딜레이.
- reduced motion 시: 플러드 즉시 컷, 호흡·펄스 정지, 스탬프는 페이드.

## 컴포넌트 (GDD 8.4.6)

| 컴포넌트 | 요점 |
|---|---|
| Primary CTA | 골드 필 + black0 텍스트(800), radius 2px, 프레스 goldDeep |
| Ghost | 투명 + 헤어라인 보더 + parchment, 프레스 black3 |
| 카드 | black2 + 헤어라인 + radius 2px, **그림자 금지** (깊이는 명도로만) |
| 레벨 셀 | 정방형 56px+, 클리어/현재(골드 보더+글로우)/잠금(text3) 3상태 |
| 게이지 | 트랙 hairline 1px, 필 gold, 값 tabular |

## 화면별 스펙

GDD 8.4.4 표를 그대로 따른다. 구현 순서 권장: 토큰 → 레벨 선택(플러드 진입점) → 클리어 → 타이틀 → 나머지.
작업(OPERATIO) 레벨 셀은 골드 링 표시 (LEVELS.md 1장 — 골드 희소성 원칙의 승인된 예외).

## 품질 바닥 (GDD 8.4.7 — QA 판정 기준이기도 함)

- 대비: 본문 AA 이상 (parchment on black0 ≈ 15:1). text3는 비활성 전용.
- 터치 타겟 44px+ (레벨 셀 56px). 세이프 에어리어 패딩 필수.
- reduced motion·햅틱 오프 설정 제공. 일시정지 오버레이는 블러 금지 (성능) — black0 90% 오버레이.
