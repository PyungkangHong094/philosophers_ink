# M3 게임플레이 기믹 배선 보고 (gameplay → team-lead / level-designer)

작성: gameplay-m3 / 2026-07-18
범위: `lib/level/`, `lib/gameplay/` (기믹 스키마·로더·검증·배선). sim(`lib/sim`,`lib/core`)은 sim-m3 소유 — 미수정.
sim 계약: `_workspace/m3_sim_api_20260718.md` (게이트·포탈·중력·ASH) + GameState `temperatureZones` 배선(온도 존).

---

## 1. 무엇이 되었나

- **기믹 5종 전부** 레벨 JSON → sim 인스턴스로 배선 완료. 온도 존 포함(sim-m3가 GameState에
  `temperatureZones` 파라미터를 추가해줘 M3 범위에 들어옴).
- 레벨 JSON 기믹 스키마 확정 + 로더 파싱 + 검증기(좌표·물질 enum·해금·포탈 무결성) 확장.
- 중력 반전은 게임플레이 입력 이벤트로 처리하고 **입력 로그**에 (틱, 값)을 기록 — 결정성 계약 준수.
- 재 방출구는 기존 `emitter.ash_ratio` 그대로 사용(중복 구현 없음). 순수(❗) 플라스크 판정과 조합됨.
- 직렬화 왕복 무손실 유지(제네릭 `GimmickSpec {type, params}` 저장 → 에디터 무수정).
- 테스트: 전 130(계약 기준) → **현재 160 전부 통과**. 신규 25(게임플레이/레벨) + sim-m3 온도 존 테스트.
  `dart analyze` 클린.

## 2. 기믹 JSON 스키마 (저작 가이드 — level-designer M4용)

기믹은 `gimmicks` 배열에 `{ "type": ..., "params": {...} }` 형태로 넣는다. 좌표계는 그리드
160×320, row-major. 잘못된 필드는 로더가 **명시적 검증 에러**로 거부한다(조용한 스킵 없음).

### 2.1 변성 게이트 `variance_gate` (챕터 2+)
존을 통과하는 물질을 다른 물질로 변환. 채널 폭 전체를 덮는 **1셀 두께 가로 띠**로 두면
수직 이동이 건너뛰지 못해 확실히 변환된다(sim 계약 팁).
```jsonc
{ "type": "variance_gate",
  "params": { "x": 0, "y": 160, "w": 160, "h": 1,
              "to": "WATER",      // 필수: 변환 결과(이동 물질만)
              "from": "PRIMA" } } // 선택: 생략 시 존 안 모든 이동 물질이 대상
```

### 2.2 중력 반전 버튼 `gravity_flip` (챕터 1+)
존/좌표 없음. **존재만으로** 게임플레이가 중력 반전 버튼을 노출한다. 전역 토글.
```jsonc
{ "type": "gravity_flip", "params": {} }
```

### 2.3 포탈 `portal` (챕터 2+)
입구 박스 → 출구 박스 일방향 순간이동. 입·출구 **셀 수(w×h)가 같아야** 한다(1:1 매핑).
양방향은 방향을 뒤집은 포탈을 하나 더 둔다.
```jsonc
{ "type": "portal",
  "params": { "entry": { "x": 4,   "y": 290, "w": 5, "h": 5 },
              "exit":  { "x": 150, "y": 8,   "w": 5, "h": 5 } } }
```

### 2.4 온도 존 `temp_zone` (챕터 2+)
레벨 고정 화로/빙결 지대. 룬 없이 존 셀을 매 틱 ±1단계 상전이.
```jsonc
{ "type": "temp_zone",
  "params": { "x": 0, "y": 4, "w": 160, "h": 20,
              "kind": "cool",         // "heat" | "cool"
              "probability": null } } // 선택: 0~1, null이면 룬 기본 강도(pHeat/pCold)
```

### 2.5 재 방출구 (기믹 아님 — 방출구 옵션)
ASH는 **방출구의 `ash_ratio`(0~1)**로 낸다. 별도 기믹 엔트리가 아니다.
`ash_emitter` type은 선택적 마커 태그로만 인식하며 배선은 하지 않는다(챕터 3+).
```jsonc
"emitters": [ { "x": 74, "y": 2, "width": 13, "material": "WATER",
                "rate": 2, "total": null, "ash_ratio": 0.3 } ]
```

## 3. 배선 구조

```
level_NNN.json
  → loadLevelFromJson (loader.dart)      // 구조 파싱 + validateLevel 강제
      → GimmickSpec {type, params}[]     // 제네릭 저장 (왕복 무손실)
  → LevelSession (gameplay)
      → buildGimmicks(specs, gridWidth)  // gimmick_builder.dart
          → GimmickBundle { gates, portals, zones, hasGravityFlip }
      → GameState(gates:, portals:, temperatureZones:)   // sim 계약 배선점
```

- `buildGimmicks`는 검증된 파라미터만 받는다고 가정(로더가 항상 검증 통과시킴).
- 중력 반전: `LevelSession.setGravityInverted(bool)` / `toggleGravity()` — `hasGravityFlip`인
  레벨에서만 동작하고, 실제 변경 시 `gravityLog`에 `GravityToggle(tick, inverted)` 기록.
  `reset()`이 로그를 비우고 sim이 중력을 기본(아래)으로 되돌림 → 재시작 결정성.
- 디버그: `LevelPlayer`에 `hasGravityFlip`일 때만 'GRAV' 버튼 노출(폴리시는 M4+ 셸).

## 4. 검증 규칙 (validator.dart)

| type | 규칙 |
|---|---|
| 공통 | 알 수 없는 type 거부. 해금 챕터: gravity_flip 1, temp_zone/portal/variance_gate 2, ash_emitter 3 |
| variance_gate | x,y,w,h 정수·존 그리드 내부·w,h≥1. `to` 필수+이동 물질+해금. `from` 선택+해금 |
| portal | entry·exit rect 객체 필수·그리드 내부·w,h≥1. entry 셀 수 == exit 셀 수 |
| temp_zone | 존 그리드 내부. `kind` ∈ {heat,cool}. `probability` 있으면 0~1 |
| gravity_flip / ash_emitter | 마커(파라미터 검증 없음) |

물질 enum·해금 정합은 기존 방출구/플라스크와 같은 규칙(`_checkMaterialUnlock`) 재사용.

## 5. level-designer(M4) 참고 사항

- 기믹 저작 시 위 스키마·검증표를 따를 것. 위반은 로더가 전부 모아 에러로 던진다.
- **곱셈 원칙(GDD 6)**: 새 기믹 교육 레벨 직후 기존 기믹·상·잉크와 곱한 레벨을 배치.
- `assets/levels/`에는 아직 기믹 사용 레벨을 추가하지 않았다(레벨 콘텐츠는 level-designer 소유).
  테스트 픽스처는 `test/level/gimmick_loader_test.dart`의 `gimmickLevelMap()`(챕터3 5종 예시) 참고.
- 에디터 UI는 기믹 추가 버튼을 아직 제공하지 않는다(범위 밖). JSON 직접 저작 또는 왕복만 보장됨.

## 6. 파일 목록

- 신규: `lib/level/gimmick_builder.dart`, `test/level/gimmick_loader_test.dart`,
  `test/gameplay/gimmick_wiring_test.dart`
- 수정: `lib/level/level_model.dart`(GimmickType·GimmickParamKey 상수),
  `lib/level/validator.dart`(기믹 파라미터 검증), `lib/gameplay/level_session.dart`(배선·중력 로그),
  `lib/gameplay/level_player.dart`(디버그 GRAV 버튼)

## 7. 미해결 / 인계

- 없음(온도 존 포함 5종 전부 배선·검증·테스트 완료). 에디터 기믹 저작 UI는 명시적 범위 밖.
- sim-m3에 계약 문서 8절(온도 존 미포함 표기) 갱신 요청함 — 실제 GameState는 이미 배선됨.
