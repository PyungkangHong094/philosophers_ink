---
name: ink-sim-core
description: 현자의 잉크 falling-sand 시뮬레이션 코어 구현 규칙. 그리드/물질 테이블/이동·전이 규칙/결정성 RNG/렌더링 파이프라인(Uint8List→ImageDescriptor.raw)/드로잉 래스터라이즈/성능 예산을 정의. lib/sim, lib/render, lib/core 코드를 작성·수정하거나, 물질·상전이·성능 관련 작업을 할 때 반드시 이 스킬을 사용할 것. "시뮬", "물리", "CA", "입자", "렌더링", "60fps" 언급 시 트리거.
---

# 시뮬 코어 구현 규칙

SSOT: `docs/PHILOSOPHERS_INK_DESIGN.md` 3장(원소)·4.1장(잉크 선)·10장(기술). 이 스킬은 그 운영 규칙이다.

## 그리드 표현

- 논리 그리드 세로형 ≈160×320 (기기 비율 따라 세로 가변). `Uint8List` 1개, 셀당 물질 ID 1바이트.
- 물질 ID enum 순서는 GDD 3.1 테이블 순서 고정: EMPTY=0, WALL, HEAT_LINE, COLD_LINE, PRIMA, ICE, WATER, STEAM, ASH, LAVA, STONE.
- 물질 속성(카테고리, 가열/냉각 전이 대상, 팔레트 색)은 `sim/materials.dart`의 중앙 테이블 하나로.
  switch문 산개 금지 — 물질 추가 시 테이블 한 곳만 고치면 되는 구조가 목표.

## 틱과 이동 규칙 (GDD 3.3)

- 60Hz 고정 틱, accumulator로 렌더 프레임과 분리.
- 카테고리별 이동: 입자(아래→아래대각), 액체(아래→아래대각→수평 dispersion), 기체(액체의 상하 미러), 정적(불동).
- 좌우 스캔 방향은 프레임마다 교차 (편향 제거). 중력 반전은 규칙 자체를 미러링.
- 이동 처리 시 "이번 틱에 이미 움직인 셀" 중복 이동 방지 필요 — dirty 플래그 또는 스캔 방향 규약으로 해결.

## 상전이와 반응

- 화염/서리 선: 인접 4방향 셀을 매 틱 확률 p로 ±1단계 전이. p는 `core/constants.dart`.
- 상전이 사슬: ICE→WATER→STEAM (가열), STEAM→WATER→ICE (냉각). PRIMA·ASH·STONE 불변.
- 반응은 단 하나: LAVA+WATER 접촉 → STONE+STEAM (두 셀 각각 변환). 다른 반응 추가 금지 (스코프 통제).

## 결정성 (GDD 10.2)

- 시드 고정 RNG 단일 인스턴스 (`core/rng.dart`). 이유: 재시작 동일성, 리플레이·힌트 검증의 기반.
- `math.Random()` 신규 생성, `DateTime.now()` 기반 로직 금지.
- 검증: 같은 레벨·같은 입력 → N틱 후 그리드 해시 동일. 이를 단위 테스트로 고정한다.

## 렌더링 파이프라인 (GDD 10.3)

```
Uint8List(물질ID) → 팔레트 룩업 → RGBA 버퍼 → ui.ImmutableBuffer + ImageDescriptor.raw
→ drawImageRect (FilterQuality.none, 정수배 확대)
```

- 팔레트는 `render/palette.dart` — 챕터별 배경색 위에서 물질 간 명도 차 20% 이상 (GDD 8.2).
- 셀=화면 픽셀 정수배 유지. 비정수 스케일 금지 (도트 미학 붕괴).

## 드로잉 입력 (GDD 10.4)

- 터치 스트로크 → 브레젠험 래스터라이즈, 선 두께 2셀. 잉크 차감 = 래스터라이즈된 셀 수.
- 스트로크 ID 유지 (탭 삭제 단위). 삭제 시 해당 셀 EMPTY 복원, 잉크 미반환.

## 성능 예산 (GDD 10.3)

| 구간 | 예산 |
|---|---|
| 시뮬 틱 | ~3ms |
| RGBA 버퍼 변환 | ~1ms |
| 페인트 | ~2ms |

- 최적화는 실측 후에만. Stopwatch 계측 코드를 디버그 빌드에 유지한다.
- 예산 초과 시 대응 순서: 그리드 축소(128×256) → Isolate 이전 (GDD 13장). 선제적 Isolate 금지.

## 코드 배치

```
lib/core/   game_loop.dart, constants.dart, rng.dart, game_state.dart
lib/sim/    grid.dart, materials.dart, rules.dart
lib/render/ world_painter.dart, palette.dart
```

- `lib/sim/`은 순수 Dart (flutter import 금지). 테스트는 `test/sim/`.
- 모든 밸런스 값은 `constants.dart` — 게임 로직 내 매직 넘버 0개가 출시 기준(GDD 14장).
