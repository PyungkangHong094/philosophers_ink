# QA: M1 통합 (2차, sim↔gameplay 경계면) — 2026-07-16

검증자: game-qa / 대상: M1-A(sim 상전이, sim-engineer) + M1-B(잉크 배선, gameplay-engineer) 통합
착수 조건: gameplay #7 완료 통지 수신 + pubspec clean(HEAD) 확인 후.
판정 기준: GDD 3.3·4.1·4.2(부분 배치 cap 확정 2026-07-16)·10.2·10.5, ink-qa-protocol,
성능 baseline = sim-engineer 선실측(A 1.219 / B 1.076 / C 1.178 ms/tick).

## 요약: PASS 7 / FAIL 0 / 권고 2 / 기준미정의 0

**M1 통합 게이트: GO (차단 결함 없음). 1차 기준미정의(청구 모델)·권고1(GDD 인용) 모두 해소.**

| # | 항목 | 결과 |
|---|------|------|
| 1 | dart analyze 이슈 0 | PASS |
| 2 | flutter test 전체 62/62 | PASS |
| 3 | 상전이 결정성 독립 재현 | PASS |
| 4 | 성능 A/B/C 회귀 (예산 3ms) | PASS |
| 5 | 경계면 sim↔gameplay — **cap 모델** 배선 | PASS |
| 6 | 삭제 미반환 / 예산0 숨김 / reset 통합 | PASS |
| 7 | 액체·기체 규칙 (신규 sim 테스트) | PASS |

## 상세

### [1] dart analyze — PASS
전체 → "No issues found!".

### [2] flutter test 62/62 — PASS
플러그인 워크어라운드(네이티브 3종 임시 제거 + TMP/TEMP=C:\flutter-tmp) 후 전체 통과
(gameplay 29 + sim determinism/rules/rasterize/transitions/liquid_gas + smoke + widget). 실패·에러 0.
**P0 게이트 충족**: pubspec.yaml/lock/generated_plugins.cmake 전부 HEAD 복구 확인
(git status 빈 상태), 검증용 임시 스크립트 삭제.

### [3] 상전이 결정성 독립 재현 — PASS
기존 테스트 비의존 독립 씬(WATER 방출 + 화염선 + 서리선 + 석필벽, 전이 패스 + 이동 패스 모두 활성)
600틱:
- fresh 3회 해시 = 0x21374561 (완전 동일), 빈 그리드와 상이(전이 실제 발생 확인).
- reset() 3회 후 재현 = 0x21374561 (fresh와 일치). GDD 10.5 재시작 결정성 충족.
근거: 상전이 패스가 전이 불가 물질에서 RNG를 소비하지 않는 규율(rules.dart `_radiateCell`)이
그리드 상태에만 의존해 결정적. reset()이 grid·rng seed·rules(_tick/_scanLeftToRight/_moveStamp)를
완전 초기화.

### [4] 성능 A/B/C 회귀 — PASS (dart run JIT, 51200셀, 300틱 평균, 예산 3ms)
| 시나리오 | 내 실측 | sim-eng baseline | 판정 |
|---|---|---|---|
| [A] 체커보드 WATER (액체 최악) | 0.942 ms/tick | 1.219 | OK, 자릿수 일치 |
| [B] 체커보드 STEAM (기체) | 0.732 ms/tick | 1.076 | OK, 자릿수 일치 |
| [C] 화염룬+대량 WATER (전이+이동) | 1.354 ms/tick | 1.178 | OK, 자릿수 일치 |
전부 예산 3ms 이내(최대 [C] 1.354ms = 예산의 45%, ~2.2배 여유). A/B는 내 값이 baseline보다
낮고 C는 약간 높은데(내 [C] 씬이 화염선 밀도·물 충전량이 더 큼) 셋 다 ~0.7–1.4ms 동일 자릿수라
"자릿수 일치" 기준 부합. M0 최악(밀집 PRIMA) 0.436ms → M1 액체/기체 ~1ms대 상승은 상전이 패스 +
수평 확산(dispersion) 추가분으로 설명되는 정상 회귀.

### [5] 경계면 sim↔gameplay — **부분 배치 cap 모델** — PASS (리더 확정 기준)
main.dart `_chargedExtend` 배선을 sim·gameplay 양쪽 코드 동시 대조:
```
budget = _ink.selectedRemaining            // 선택 잉크 잔량
placed = _game.extendStroke(.., maxCells: budget)   // maxCells 상한까지만 배치, 실제 배치 수 반환
_ink.chargePlaced(placed)                  // 실제 배치 수를 cap 차감
```
- **차감 = 실제 배치 셀 수**: extendStroke는 EMPTY 셀만 칠하고 painted를 반환, maxCells=잔량에서
  break하므로 painted ≤ 잔량. chargePlaced→chargeAvailable = min(painted, 잔량) = painted(정확).
  이중 cap이지만 painted ≤ 잔량이라 실차감 = painted, **누수·초과차감 없음**. GDD 4.2 "차감 =
  래스터라이즈 셀 수" + "부분 배치(잔량 cap)" 확정 기준 부합.
- **배선이 cap 경로**: main은 chargePlaced(사후 cap)만 사용, tryCharge(all-or-nothing)·
  previewStrokeCells는 미사용. 리더 확정(부분 배치 cap)과 일치 → 1차 기준미정의 해소, PASS.
- 잔량 0 게이트: `selectedRemaining<=0`이면 미배치, `canDraw`(잔량>0) 사전 확인 이중 방어.

### [6] 삭제 미반환 / 예산0 숨김 / reset 통합 — PASS
- 삭제 미반환: `_onTapUp`→`deleteStrokeAt`→`deleteStroke`(EMPTY 복원)은 예산에 손대지 않음.
  InkBudget에 반환 API 부재. GDD 4.2 부합.
- 예산 0 병 숨김: InkHud가 `controller.visibleInks`(숨김 제외)로 렌더. 데모는 3종 다 노출.
- reset 통합: `_reset()`이 `_game.reset()` + `_loop.reset()` + `_ink.reset()` 동시 호출 →
  그리드·틱·예산·선택 전부 복원. dispose에 `_ink.dispose()` 연결.

### [7] 액체·기체 규칙 — PASS
신규 test/sim/liquid_gas_test.dart(액체 확산·웅덩이 고임·기체 상승·얼음 안식각) +
transitions_test.dart(화염/서리 가열·냉각 체인, 불활성 불변, 전이 결정성) 전부 통과([2]에 포함).
독립 씬([3])에서도 액체 낙하·전이·기체 상승이 결정적으로 재현됨. 규칙 구조(rules.dart)는 1차 대기 중
정적 검토 완료 — move-stamp 중복이동 방지, 고정 스캔+단일 RNG로 결정성 설계 정합.

## 권고 (비차단)
1. **미사용 all-or-nothing 경로**: 청구 모델이 부분 배치 cap으로 확정되며 InkBudget.tryCharge /
   InkController.tryCharge / GameState.previewStrokeCells가 프로덕션 배선에서 미사용이 됐다.
   ink_budget_test/ink_controller_test는 여전히 이들을 단위 검증 중(프리미티브로서 정상). 향후 데드
   코드 정리 시 제거하거나 "확정 모델 아님, 프리미티브 보존" 주석을 명시할지 gameplay-engineer 판단.
   현시점 결함 아님. 소유: gameplay-engineer.
2. **QA 프로세스 주의(코드 결함 아님)**: 플러그인 임시제거 워크어라운드는 pub get 시
   windows/flutter/generated_plugins.cmake의 FFI 목록(flutter_soloud/jni)을 제거하며, 개발자 모드
   미설정 상태의 복구 pub get은 이를 되돌리지 못한다. 워크어라운드 사용 후 pubspec/lock뿐 아니라
   `git checkout -- windows/flutter/generated_plugins.cmake`까지 원복해야 트리가 완전 clean이 된다.
   이번 검증에서 확인·원복 완료. (양 엔지니어 워크어라운드 시 동일 주의 필요.)

## 회귀 확인 (이전 리포트 대비)
- **1차 리포트(qa_m1_ink_20260716.md) 기준미정의 해소**: 청구 모델이 부분 배치 cap으로 확정,
  GDD 4.2:109 "예산 부족 시: 부분 배치(잔량 cap)" 명문화 확인. 경계면 [5]에서 배선이 cap 경로임을
  검증 → PASS 전환.
- **1차 권고1(GDD 인용 불일치) 해소**: ink_budget.dart:75·ink_controller.dart 주석이
  'GDD 4.2 "전부 아니면 전무"'(존재하지 않던 인용) → "부분 배치 cap (GDD 4.2, 팀 확정 2026-07-16)"로
  갱신됨. 잘못된 인용 잔존 0.
- **M0 게이트(qa_m0) 회귀**: 결정성·성능 원리 유지. 물질 테이블 확장(WATER 3상·룬선·ICE) 후에도
  팔레트 LUT는 enum index 기반이라 회귀 안전(M0 [7] 원리). 성능은 M1 규칙 추가로 0.436→~1ms대
  상승하나 예산 내([4]). M0 기준선 해시(0x2115a458)는 PRIMA 방출 씬 전용이라 이번 WATER 씬
  기준선(0x21374561)과 별개 — 각 씬 독립 추적.

## 재검증 애드덤 (코드 드리프트 대응, 2026-07-16 후속)

2차 QA 최초 보고 직후 gameplay-engineer가 리더 확정을 반영해 **all-or-nothing 경로(tryCharge)를
코드에서 제거**(내 권고1 수용)하고 sim 스트로크 계약 테스트(stroke_api_test.dart)를 추가했다.
최초 GO는 tryCharge가 남아있던 62테스트 상태 기준이었으므로, 변경된 현재 코드로 게이트를 재실행:

- **정적 확인**: `grep tryCharge` → lib/·test/ 전부 0건(완전 제거). ink_budget.dart는 cap 프리미티브
  `chargeAvailable` + 부작용 없는 질의 `canAfford`만 남음. ink_controller.dart는 `chargePlaced`(cap) +
  `selectedRemaining` + `canDraw`만 남음. 주석 모두 "부분 배치 cap(팀 확정 2026-07-16)"로 정합.
- **dart analyze**: 이슈 0 재확인.
- **flutter test**: 61/61 통과(tryCharge 단위테스트 제거로 62→61, 신규 stroke_api_test 6개 포함).
  P0 게이트 재충족(pubspec 2형제 + generated_plugins.cmake 복구, git status clean).
- **경계면 계약(행동 기준, 리더 뉘앙스 반영)**: stroke_api_test.dart가 `extendStroke 반환=새로 칠한
  셀 수`, `maxCells 상한에서 배치 정지`, `maxCells=0 미배치`, `deleteStroke 미반환`을 직접 고정.
  main `_chargedExtend`는 selectedRemaining<=0이면 미배치 → **드래그 중 잔량 소진 시 선이 그 지점에서
  멈추고, 잔량>0인 동안 계속 그려짐** = cap 모델 행동 기준 충족. all-or-nothing 경로가 아예 사라져
  구현이 확정 모델 하나로 수렴함. PASS.
- **결정성·성능**: sim 코어(game_state·rules·materials·constants) 무변경 → 최초 측정
  (해시 0x21374561, A/B/C 0.942/0.732/1.354ms) 그대로 유효. 재측정 불필요.

**재검증 결론: 현재 코드(61테스트, cap 단일 모델)로도 M1 게이트 GO 유지.** 최초 권고1(데드코드)도
gameplay 측에서 해소됨.

### 신규 권고 (재검증 발견)
3. **잔존 구 문구(sim 소유)**: game_state.dart:141 `previewStrokeCells` 주석이
   "all-or-nothing 예산 사전검사용 (GDD 4.2)"로 남아있다. GDD 4.2는 이제 부분 배치 cap이므로 이
   문구는 스테일. gameplay-engineer의 권고1 grep은 "전부 아니면 전무"만 봐서 이 "all-or-nothing"
   표현을 놓쳤다. previewStrokeCells 자체는 sim이 제공하는 유효 API(stroke_api_test가 검증)이나 main
   미사용이며, 주석의 GDD 인용만 cap 기준으로 수정 권고. 소유: sim-engineer. 비차단.

## 산출물
- 리포트: _workspace/qa_m1_integration_20260716.md (본문 + 재검증 애드덤)
- 벤치 방식: 독립 dart 스크립트(임시, 검증 후 삭제) — 결정성 씬 + A/B/C 시나리오 직접 구성.
