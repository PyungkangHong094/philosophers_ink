---
name: ink-gameplay-systems
description: 현자의 잉크 게임플레이 계층 구현 규칙. 잉크 예산·팔레트, 플라스크 승리 조건(개수/물질/상태/순수), 별점 공식, 기믹 5종(변성 게이트/중력 반전/포탈/온도 존/재 방출구), 레벨 JSON 스키마·로더·검증기를 정의. lib/gameplay, lib/level 코드 작성·수정, 승리 조건·별점·기믹·레벨 로딩 작업 시 반드시 이 스킬을 사용할 것.
---

# 게임플레이 시스템 구현 규칙

SSOT: `docs/PHILOSOPHERS_INK_DESIGN.md` 4·5·6장, `docs/PHILOSOPHERS_INK_LEVELS.md` 7장(스키마).

## 잉크 시스템 (GDD 4장)

- 잉크 3종: 석필(WALL) / 화염 룬(HEAT_LINE) / 서리 룬(COLD_LINE). 예산 단위 = 래스터라이즈 셀 수.
- 레벨별 잉크 종류당 예산. 예산 0인 잉크는 UI에서 병 자체를 숨긴다.
- 선 삭제는 스트로크 단위, **잉크 미반환** (신중한 드로잉 유도가 설계 의도).

## 플라스크 판정 (GDD 5.1)

판정은 "착수 순간"에 한다 (셀이 플라스크 영역에 안착할 때):

| 조건 | 판정 |
|---|---|
| 무조건 | 어떤 물질이든 카운트 |
| 물질 지정 | 해당 물질만 카운트, 타 물질은 통과·소멸 |
| 상태 지정 | 착수 시점의 상(고/액/기)이 일치해야 카운트 |
| 순수(❗) | ASH 1개 혼입 즉시 실패 상태 → 재시작 유도 |

- 착수 카운트업은 사운드·UI와 동기화되는 이벤트를 발행한다 (원작 만족감의 핵심, GDD 9.2).

## 별점 (LEVELS.md 4장 공식이 GDD 5.3보다 구체 — 이것을 쓴다)

- ★★★ = 사용량 ≤ 최적해 × 1.15 / ★★ = ≤ 최적해 × 1.6 / ★ = 클리어.
- 최적해 잉크는 레벨 JSON `meta.optimal_ink`에서 읽는다. null이면 별점은 ★만 부여 (미검증 레벨).

## 기믹 5종 (GDD 6장)

| 기믹 | 구현 요점 |
|---|---|
| 변성 게이트 | 통과 셀의 물질 ID 치환 (from→to 페어는 레벨 JSON) |
| 중력 반전 | 전역 플래그 — sim의 이동 규칙 미러링 API 호출 |
| 포탈 | 페어 박스 간 셀 텔레포트, 진입 방향 보존 |
| 온도 존 | 고정 영역이 화염/서리 선과 동일한 확률 전이 적용 |
| 재 방출구 | 방출구 옵션 (mixture에 ASH 비율 지정) |

- 기믹은 sim 공개 API로만 구현 — sim 내부 규칙 수정 금지 (소유권: sim-engineer).

## 레벨 JSON 스키마

`assets/levels/level_NNN.json`. GDD 10.6 + LEVELS.md 7장 통합:

```jsonc
{
  "meta": { "id": 36, "name": "증기 엘리베이터", "chapter": 3, "difficulty": 5,
            "teaches": [], "tags": [], "optimal_ink": {"chalk":84,"heat":30,"frost":22},
            "solutions_verified": 2, "hint_stroke": null },
  "background": "#D9A62E",
  "emitters":  [{ "x":0,"y":0,"material":"WATER","rate":0,"total":null,"ash_ratio":0 }],
  "flasks":    [{ "x":0,"y":0,"w":0,"h":0,"goal":100,"material":null,"state":null,"pure":false }],
  "terrain":   [],
  "gimmicks":  [],
  "ink_budget": { "chalk":0,"heat":0,"frost":0 },
  "star_thresholds": null
}
```

- `total: null` = 무한 방출. `star_thresholds`는 optimal_ink에서 공식으로 파생하므로 보통 null.
- 로더(`level/loader.dart`)는 검증기(`level/validator.dart`)를 반드시 통과시킨다:
  스키마 필수 필드, 물질 ID 유효성, 챕터 해금 정합성(레벨 챕터보다 늦게 해금되는 요소 사용 금지),
  플라스크·방출구 좌표가 그리드 내부인지. 실패 시 조용히 스킵 금지 — 명시적 에러.

## 게임 상태

- `GameState.reset()`: 그리드·잉크·플라스크 카운트·RNG 시드 완전 초기화.
  테스트: 재시작 3회 연속 동일 동작 (그리드 해시 비교).
- 진행도 저장(클리어·별)은 `meta/progress.dart` 소유(shell-ui-engineer)와의 경계 —
  gameplay는 결과 이벤트만 발행하고 저장은 하지 않는다.
