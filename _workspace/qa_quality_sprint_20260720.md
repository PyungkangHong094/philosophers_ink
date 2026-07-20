# QA: 퀄리티 스프린트 커밋 전 게이트 — 2026-07-20

작업 디렉토리: C:\Github\Philosopher Ink · 검증자: game-qa-2
환경: /c/flutter/bin (Dart SDK 3.12.2 stable, windows_x64), PUB_CACHE=/c/pub-cache

## 게이트 판정 (최종): **GO**

초판 NO-GO의 블로커 2건(테스트 스테일)은 리더 승인 하에 QA(game-qa-2)가 직접 갱신 완료.
재검증: `dart analyze lib/render lib/ui tool test` → **No issues found**, 관련 12개 스위트
`flutter test` → **86/86 PASS**. 앱 런타임 코드는 무변경(테스트만 갱신) — 코어 6개 검증 대상은
초판부터 전부 PASS였다.

### 블로커 해소 기록 (2026-07-20, QA 직접 수정 — 테스트 코드 QA 소유)
- **[P1-A 해소]** `test/ui/game_overlays_test.dart`: FailOverlay 호출에 `failure: LevelFailure.contamination` 추가 + **타임아웃 케이스 신규**(`failure: LevelFailure.timeout` → '시간 초과' 문구 단언, '오염' 부재 단언)로 Q1-2 사유별 분기 계약 고정. `LevelFailure` import 추가.
- **[P1-B 해소]** `test/ui/hud_test.dart`: 카운트업 단언을 카운트다운 계약으로 재작성 — 시작=제한시간(02:00), 시뮬 경과 시 감소(초 파싱 <120), 재시작 시 제한시간 복귀, ≤10초 warn 색(InkColor.warn) 단언 추가. formatClock 순수 테스트 추가. 결정성 위해 `timeLimitSeconds` 명시(120/8초).

## 요약: PASS 14 / FAIL 0 / 권고 5 / 맥필요 2

---

## FAIL (P1 — 커밋 차단)

### [P1-A] dart analyze 에러 1건 — FailOverlay 필수 인자 누락으로 기존 테스트 컴파일 불가
- 위치: `test/ui/game_overlays_test.dart:82`
- 재현: `dart analyze lib/render lib/ui tool test` → `error - The named parameter 'failure' is required, but there's no corresponding argument (missing_required_argument)`.
- 원인: Q1-2에서 `FailOverlay`에 `required LevelFailure failure`를 추가(clear_overlay.dart:236)했으나, 기존 위젯 테스트가 `FailOverlay(eyebrow:.., onRetry:.., onHome:..)`로 인자 없이 호출. 해당 테스트 파일 전체가 컴파일 실패 → analyze 정적 에러 0 게이트 위반.
- 근거: QA 프로토콜 "1. dart analyze — 정적 에러 0 확인". 소유: **shell-ui-2** (FailOverlay 계약 변경자). 수정: `failure: LevelFailure.timeout`(또는 contamination) 인자 추가.

### [P1-B] flutter test hud_test 2건 실패 — 인게임 HUD를 카운트업→카운트다운으로 바꿨으나 테스트 미갱신
- 위치: `test/ui/hud_test.dart` — `초시계가 00:00부터 표시되고 크기를 가진다`, `시간이 흐르면 증가하고, 재시작하면 00:00으로 리셋`
- 재현: `flutter test test/ui/hud_test.dart` → 2 failed.
- 원인: 이번 워킹트리 diff가 상단 HUD 시간 표시를 HEAD의 `formatElapsed(_session.game.tickCount)`(카운트업 초시계, 0에서 증가)에서 `formatClock(_countdownSeconds)`(remainingTicks 기반 카운트다운)로 교체(play_screen.dart:716-743). 테스트는 여전히 카운트업 의미(00:00 시작·증가·재시작 시 00:00 리셋)를 단언 → 실패. `makeEntry()`가 timeLimitSeconds=null이라 세션이 밴드 기본 제한시간으로 카운트다운 시작 → 첫 표시가 00:00이 아니고, 재시작도 00:00이 아닌 제한시간으로 리셋.
- 판정: **코드는 의도된 설계**(GDD 2장 제한시간 카운트다운)로 정당. 결함은 **스테일 테스트**. 테스트를 카운트다운 의미로 갱신해야 함(시작=제한시간 표시·시간 경과 시 감소·재시작 시 제한시간으로 복귀). `일시정지 중 정지`·팔레트 위치 테스트는 통과.
- 소유: 테스트 코드는 QA 소유이나 이번 게이트는 "보고만" 지시 → **shell-ui-2와 협의 후 QA가 갱신** 권장. 근거: QA 프로토콜 "2. flutter test — 회귀 확인".

---

## PASS (교차 검증·실행 증거)

### P1 렌더 (world_painter.dart + world_point_buffers_test)
- **페인트 경로 힙 할당**: `WorldPointBuffers`가 State 소유(play_screen.dart:132)로 프레임 간 유지. `rebuild()`는 `_count`/`_cursor`를 fillRange로 리셋(할당 0)하고, `_buf[id]`는 하이워터마크 초과 시에만 성장(정상상태 0 할당). 대량 per-particle 버킷 할당 제거 확인. (단 `view()`는 물질당 sublistView 뷰 객체 1개 할당 — 권고 R1 참조.)
- **렌더→sim 변이 없음**: `rebuild`는 `cells`(sim 그리드)를 읽기만 하고 자기 버퍼에만 기록. 결정성 무영향 확인.
- **신규 테스트 4개 단언 타당**: 셀 중심 좌표 (gx+0.5)*s·(gy+0.5)*s 계산 정확(수기 검산 일치), 재사용 스테일 없음, EMPTY 제외, 하이워터마크 후 축소(view 길이=count*2). **flutter test 통과(4/4)** — 이 PC에서 dart:ui 타깃 실행 가능 확인.

### Q1 셸 묶음
- **기믹 오버레이 ↔ 레벨 스키마 정합**: `GimmickOverlayPainter`의 파라미터 키가 `level_model.dart`의 `GimmickParamKey`와 3자 일치 — 포탈 `entry`/`exit`(중첩 rect), 온도존 `kind` vs `kTempZoneCool`, 게이트 `to`+`x/y/w/h`. 포탈 페어는 등장 순서로 `InkGimmick.portalPairs` 순환(같은 색=연결 페어). 좌표계: 물질 렌더(`WorldPointsPainter`)·기믹·힌트·플라스크 모두 `GridViewport.fit(size, SimConstants.gridWidth/Height)` 동일 뷰포트 사용 → 그은 자리·표식 자리 일치.
- **레이어 순서**: 기믹(RepaintBoundary)→물질(매 프레임)→플라스크HUD(RepaintBoundary)→완성펄스(RepaintBoundary)→힌트고스트→상단 HUD. 애니메이션 레이어(물질)만 매 프레임 repaint, 정적 레이어는 RepaintBoundary로 격리. 타당.
- **카운트다운 경로**: `remainingTicks/tickRateHz`.ceil()로 초 변환, 표시 초 변화 시에만 `_countdownSeconds` 갱신(1Hz), ≤10초 `InkColor.warn`(골드 아님). 타임아웃 시 `_Outcome(failed, failure: _session.failureReason)`→`FailOverlay`가 `LevelFailure.timeout` 문구 분기(clear_overlay.dart:249) 확인.
- **햅틱**: 착수 70ms 스로틀(play_screen.dart:206), `settings.hapticX`가 `_haptics` 게이트(settings_controller.dart:56-67), 완성 펄스는 `_reduced`면 펄스 생략·햅틱만(play_screen.dart:417). reduced motion 분기 존재.
- **HUD repaint 폴드**: `_flaskSignatureNow()`가 flask별 count·isFailed만 폴드 — 플라스크 렌더의 가변 입력(채움·오염)과 정확히 일치(goal/state/pure/material은 스펙 불변이라 제외 타당). 매 프레임 무조건 repaint 제거.
- **Paint static 재사용 오염 없음**: `_fillPaint`/`_waterLinePaint`/`_dotPaint`는 draw 직전 `..color` 지정, `_wallPaint`는 gold·strokeWidth 불변. 색 변이 후 미복원 스테일 없음(모든 가변 색은 사용 직전 세팅). UI 스레드 단일 실행이라 인스턴스 공유 안전.

### 힌트 베이크 (11레벨 + bake_hints.dart)
- git diff가 `hint_stroke` 필드에만 국한(012·013·014·015·017·019·025·034·051·064·074) — 다른 포맷 무변경 확인.
- **거짓말 안 하는 힌트 보증**: 베이크 전 아카이브 원본 해 전체(스트로크+중력탭)를 fresh HeadlessSession에 `kVerifyRolloutConfig`로 재생, 클리어 실패 시 null 유지. 단일 토큰 안전 치환(정확히 1개 매치일 때만), 쓰기 후 왕복 재검증.
- **L034 영길이 점 스트로크**: `hint_stroke: heat (66,230)->(66,230)` = 최장 스트로크가 점(heat 룬 배치형 해). `_HintGhostPainter`가 Path.moveTo/lineTo 동일점 → StrokeCap.round로 degenerate segment를 점(dot)으로 렌더 → 안전(비가시·크래시 아님). (Impeller 시각 확인은 맥필요 M1.)
- **flutter test 통과**: hint_stroke_test·hint_bake_test(챕터1 정직성 10건 + 재시작 3회 동일 틱 결정성) 전부 green.

### 별점 재저작 (067/068/069)
- 방향 정합: `star_rating.dart:60` `inkUsed<=three→3성`이라 three가 더 엄격(작은 값). 067(78/63)·068(95/83)·069(87/76) 모두 three<two 만족. 예산 총합(600/400/600) 대비 임계값 타당 범위.
- 로더 통과: `loader.dart:264-265`가 `two_star`/`three_star` 키 파싱, JSON 3개 utf-8 유효. loader_test·star_rating_test green.
- (3성 도달 가능성=솔버 해 잉크≤three 확인은 맥필요 M2 — level-designer-2 도메인.)

### 솔버 가드 (solver.dart·sweep.dart·solve.dart·level_io.dart·rollout.dart + archive_guard_test)
- **verify-on-write 전 경로 커버**: 기록 가드(`verifySolutions`)가 `solveLevel` 내부 초크포인트에 삽입(solver.dart:332). solve.dart(:61)·sweep.dart(isolate) 양쪽 모두 solveLevel 경유 → **우회 불가**. `minInk`/`solvable`도 검증 통과 해에서 파생(정직화).
- **stale 거부**: bake_hints가 프로비넌스 `level_hash`(FNV-1a 16진 16자)를 현재 레벨 내용 해시와 대조, 불일치 시 `null(stale)`. mtime 대신 내용 해시 사용(mtime 신뢰불가 포렌식 대응). 프로비넌스는 sweep·solve 양쪽에서 `stampProvenance`로 스탬프.
- **kVerifyRolloutConfig 공유**: 스윕 기록 가드와 bake 검증이 동일 롤아웃 설정(tickCap 3600·stall 3600·forbidInFlask=false) 공유 → "스윕이 남긴 해==베이크가 받는 해".
- **flutter test 통과**: archive_guard_test 5건(L016 위양성 탈락·진짜해 유지·want 조기종료·contentHash 결정성·프로비넌스 스탬프) green. SDK 3.12.2가 `?gitSha` 널어웨어 요소 지원 확인.

### 결정성 리스크 스캔 (item 6)
- git status: 변경은 전부 lib/render·lib/ui·tool·test·assets. **lib/sim·lib/gameplay·lib/core 변경 0건** 확인.
- 렌더(WorldPointsPainter·GimmickOverlayPainter)·햅틱(settings)·HUD 폴드 모두 sim 그리드/플라스크 상태를 **읽기 전용**. 시뮬 변이 코드 없음.
- pubspec 3파일 무변경 확인.

---

## 권고 (문서 근거 없는 개선 제안 — 게이트 무관)

- **R1 (렌더 주석 정확성)**: `WorldPointBuffers.view()`는 물질당 `Float32List.sublistView` 뷰 객체 1개를 할당(데이터 복사는 없음). 프레임당 할당은 0이 아니라 "비어있지 않은 물질 수(≤~12, 입자 수 무관)"가 상한. 코드 주석의 "페인트당 힙 할당 0"은 "물질 수로 상한(입자 무관)"이 정확. GC 압력은 무시할 수준이라 성능 결함 아님. 소유: sim-engineer.
- **R2 (mouth:down 플라스크 렌더 — 선재 결함)**: `_FlaskHudPainter`가 `FlaskSpec.mouth`를 읽지 않고 항상 상단 개방 U 비커로 그린다. mouth:down(천장부착 ∩) 레벨 7개(008·009·011·029·064·072·077)에서 시각이 물리와 불일치. **HEAD에도 동일**(이번 스프린트 회귀 아님) → 후속 폴리시 백로그. 소유: shell-ui-2.
- **R3 (골드 검산)**: 인게임 활성 플레이 시 골드 요소 = 플라스크 비커 외곽선 N개(_wallPaint=gold, 다중 플라스크면 2~3) + 팔레트 선택 + 완성 펄스(승인). 셸 "1~2" 규칙은 셸 화면 대상이고 tokens.dart가 인게임 예외를 명시하나, 목표 플라스크 골드는 선재 사항이니 의도 확인 권고. 소유: shell-ui-2.
- **R4 (하드코딩 색 — 선재)**: `lib/ui/ink_flood.dart:35` `const Color(0xFFFFFFFF)`가 tokens.dart 외 유일 하드코딩(플러드 하이라이트 lerp 대상). 이번 diff 무관하나 토큰화 권고. 소유: shell-ui-2.
- **R5 (ch2-4 힌트 정직성 테스트 부재)**: hint_bake_test는 챕터1(001-010)만 커버. 이번 베이크된 ch2-4 힌트는 bake 도구 self-verify(verify-on-bake)로만 보증. 회귀 방지용 ch234 정직성 테스트 추가 권고. 소유: QA.

## 맥에서 돌려야 할 검증 목록 (이 PC 한계)
- **M1**: L034 영길이 힌트 점이 Impeller(iOS/Android 기본)에서 dot로 실제 렌더되는지 디바이스 시각 확인. Skia에선 정상. (degenerate round-cap은 Impeller에서 과거 비렌더 이력 있음.)
- **M2**: 067/068/069 3성 임계(≤63/83/76 잉크) 실제 도달 가능성 — 솔버 최소해 잉크와 대조(level-designer-2). 로더·방향·형은 이 PC에서 PASS.
- **참고**: 이 PC에서 flutter test는 dart:ui 타깃 포함 정상 실행됨(전멸 아님). 전체 스위트 회귀는 맥에서 1회 풀런 권장(game_overlays·hud_test 수정 후).

## 회귀 확인 (이전 리포트 대비)
- `_workspace/`에 이전 `qa_*.md` 없음(신규). `perf_audit_20260720.md`·`quality_audit_20260720.md`·`solver_forensics_20260720.md`는 스프린트 감사 산출물 — 본 게이트는 그 수정들의 커밋 전 검증.
