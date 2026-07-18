# 딥 감사 — 커밋된 코드베이스 전체 (HEAD 9d1f149) — 2026-07-18

감사자: qa-m4 · 기준: HEAD `9d1f149`(격리 worktree, M5 미커밋 변경 미포함) · ink-qa-protocol.
범위: lib/ 46파일 6867줄 전수 정독 + 정적 스윕. 실행 검증: `flutter analyze`(격리 worktree) **No issues found**.
환경: `env -u PUB_CACHE -u TMP -u TEMP` 접두. **코드 수정 없음** — 소유 라우팅은 리더.

## 요약: P0 0 / P1 0 / P2 3 / P3 7

전반적으로 **매우 견고**하다. 계층 분리(sim/render/core 순수 Dart ↔ gameplay ↔ ui)가 일관되고,
경계면 계약(로더→검증기→빌더→sim)이 방어적이며, 매직 넘버·하드코딩 색이 단일 소스(constants/tokens)에
수렴한다. 결함은 전부 **비차단**이며 대부분 렌더/셸 생명주기의 방어 강화 항목이다.

핵심 3건: (1) WorldImageSource async dispose 레이스(예외+이미지 누수), (2) InkController 미dispose,
(3) 렌더 파이프라인 `_rgba` 단일 버퍼의 async 공유 잠재 경합.

---

## P2 — 실 결함 (수정 권장, 데이터/결정성 무해)

### [P2-1] WorldImageSource.update() async dispose 레이스 + 이미지 누수
- 파일: `lib/render/world_painter.dart:66-89` (update), `lib/ui/game/play_screen.dart:106` (호출), `:89-95` (dispose)
- 재현: 플레이 중 뒤로가기(Navigator.maybePop) → `_PlayScreenState.dispose()`가 `_imageSource.dispose()`
  호출. 직전 프레임의 `_imageSource.update(_rgba)`가 `await ImmutableBuffer.fromUint8List`/
  `getNextFrame` 지점에서 suspend 중이면, 재개 시 (a) `notifyListeners()`를 **이미 dispose된
  ChangeNotifier**에 호출 → FlutterError("used after disposed") 비동기 throw, (b) 새로 디코드한
  `frame.image`가 dispose된 소스에 매달려 **다시 dispose되지 않음 → ui.Image 누수**(~200KB/회),
  (c) `old?.dispose()`가 이미 dispose된 이미지에 재호출.
- 근거: ChangeNotifier 계약(dispose 후 notify 금지) + ui.Image 수명 관리(GDD 10.3 파이프라인).
- 권고: `bool _disposed` 플래그 추가. 각 await 뒤 `if (_disposed) { frame?.image.dispose(); return; }`
  가드, `notifyListeners()` 전 `if (_disposed) return`. dispose()에서 `_disposed=true`.
- 소유: sim-engineer (render/ 소유).

### [P2-2] InkController(ChangeNotifier) 미dispose — 리스너 누수
- 파일: `lib/gameplay/ink_controller.dart:19` (extends ChangeNotifier), `lib/gameplay/level_session.dart:30`
  (소유), `lib/ui/game/play_screen.dart:88-95` (dispose에 누락)
- 내용: play_screen.dispose()는 `_ticker/_imageSource/_outcome/_frameTick`은 dispose하나
  `_session.ink`(ChangeNotifier)는 dispose하지 않는다. LevelSession에도 dispose가 없다. 네이티브
  핸들은 없어 하드 누수는 아니나, ChangeNotifier 리스너 목록이 GC 전까지 남고 flutter 컨벤션 위반.
  레벨 재플레이가 반복되는 게임 특성상 인스턴스가 계속 쌓인다.
- 근거: ChangeNotifier 생명주기 컨벤션(소유자 dispose 책임).
- 권고: `LevelSession.dispose()`를 추가해 `ink.dispose()` 호출, play_screen.dispose()에서 세션 dispose.
  (WorldImageSource는 이미 올바르게 dispose 중 — 동일 패턴 적용.)
- 소유: gameplay-engineer(LevelSession) + shell-ui-engineer(play_screen 배선).

### [P2-3] 렌더 `_rgba` 단일 버퍼의 async 공유 잠재 경합
- 파일: `lib/ui/game/play_screen.dart:105-106`, `lib/render/world_painter.dart:66-70`
- 내용: 매 프레임 `_palette.writeRgba(..., _rgba)`로 **동일 버퍼**를 덮어쓴 뒤 `_imageSource.update(_rgba)`.
  update는 `_converting` 인플라이트 가드로 동시 변환은 1개로 제한하나, 변환이 `_rgba`를 비동기로 읽는
  동안 다음 프레임 writeRgba가 같은 버퍼를 변형할 수 있다. `ImmutableBuffer.fromUint8List`가 리스트를
  즉시 복사하면 무해하나, 지연 복사(플랫폼 스레드)면 화면 티어링 가능.
- 근거: GDD 10.3 "재사용 버퍼" 파이프라인의 동시성 계약 미명시.
- 예상 효과: 티어링은 시각적, 메모리 안전성 무해(단일 스레드 Dart). 인플라이트 가드로 노출은 제한적.
- 권고: 더블 버퍼(핑퐁 2개) 또는 update 진입 즉시 복사본 확보. 또는 fromUint8List 즉시복사 보장 확인 후
  현행 유지 결정. 확정 전까지 P2(잠재)로 표기.
- 소유: sim-engineer.

---

## P3 — 방어·폴리시·경미 최적화

### [P3-1] 물질 테이블 조회 무가드 (핫패스 크래시 방어)
- `lib/sim/materials.dart:196-199` `propsOf/categoryOf = kMaterialTable[id]`(11엔트리), `flask.dart:113`
  `Material.values[id]`. 그리드는 Uint8List(0~255)나 실제 기입 집합이 0~10으로 닫혀 있어 안전.
  다만 손상/예기치 못한 id면 시뮬 핫패스에서 RangeError. 방어적 assert 또는 클램프 권고(성능 영향 없음).

### [P3-2] _FlaskHudPainter 프레임당 TextPainter 할당 + shouldRepaint 상시 true
- `lib/ui/game/play_screen.dart:380-421`. 플라스크 수(1~3)만큼 매 프레임 TextPainter 생성·layout.
  GC 압력 경미. 라벨 문자열 변할 때만 재생성하도록 캐시 권고. 효과: 프레임당 소액 할당 제거.

### [P3-3] UI가 sim 내부 버퍼로 2계층 관통
- `lib/ui/game/play_screen.dart:105` `_session.game.grid.cells`(UI→세션→GameState→raw Uint8List).
  렌더 경로라 실무 무해하나 소유권 경계상 `session.writeRgba(rgba)` 같은 파사드 노출이 깔끔.

### [P3-4] 타이틀 _breath 컨트롤러가 커버된 라우트에서도 vsync 지속
- `lib/ui/screens/title_screen.dart:30-34` `..repeat()`. 챕터 선택 push 시 타이틀이 offstage여도
  AnimationController는 계속 틱(페인트는 안 됨). `deactivate`에서 stop, `activate`에서 repeat 권고.

### [P3-5] LayoutBuilder.builder 내 _viewSize 상태 변형
- `lib/ui/game/play_screen.dart:219` 빌드 단계 부수효과. setState 없어 무해하나 관례상 회피 대상.

### [P3-6] debug_hud.dart 사장 코드 추정
- `lib/gameplay/debug_hud.dart`(150줄) 프로덕션 미참조(doc 코멘트 + 자기 테스트만). play_screen이
  ink_palette_bar로 대체. 제거 또는 존치 사유 명기. (게이트 QA에도 기록.)

### [P3-7] prefs 손상 시 진행 조용히 초기화
- `lib/meta/progress_store.dart:30-37` jsonDecode 실패 → 빈 진행 폴백(별점 소실). 견고한 폴백이나
  덮어쓰기 전 손상 blob 백업(`ink.progress.v1.bak`) 두면 복구 여지. 출시 데이터 무결성 폴리시.

---

## 축별 총평 (양호 항목 명시)

**1. 에러 위험 — 양호.**
- 이동 패스(`rules._tryMove/_slide`) 전량 inBounds 가드. 게이트/포탈/온도존의 직접 인덱스 접근
  (`grid.cells[idx]`, `_moveStamp[e]`)은 **검증기가 rect 전 필드를 그리드 경계로 검사**(validator
  `_checkRect`/`_checkRectField`, 포탈 입출구 셀 수 1:1)하고 로더가 항상 검증기를 통과시키므로 안전.
  빌더 gridWidth == 검증기 SimConstants.gridWidth로 인덱스 일관.
- JSON 파싱(`loader.dart`) 전면 방어: 타입 위반 수집 후 명시 예외, 조용한 스킵 0. 색·힌트·잉크맵
  전부 fallback+예외. 에디터도 `_doc.build()`(검증 throw) 후에만 LevelPlayer 진입 — 미검증 Level→sim
  경로 없음.
- async: `app.dart._boot`가 `mounted` 가드 + try/catch, 빈 카탈로그 폴백. 유일한 async-gap 결함은
  P2-1(WorldImageSource).
- dispose: title/clear/play/level_player 컨트롤러 dispose 정상. 유일 누락 P2-2(InkController).

**2. 성능 — 양호.**
- `palette.writeRgba` LUT 방식, 프레임당 신규 할당 0(재사용 버퍼). 51200셀 × 4B 단순 복사.
- `GameLoop` accumulator + maxFrameAccumSeconds(0.25) 클램프로 스파이럴 방지. 첫 프레임 dt 가드.
- `WorldPainter.shouldRepaint`는 source 동일성 비교 + `repaint: source`(Listenable) 구동 — 정석.
- sim 틱 실측(게이트 QA) 0.98ms/예산 3ms. 그리드 순회 핫패스는 단일 배열 선형 스캔.
- 경미 항목만: P3-2(TextPainter), P3-4(offstage 컨트롤러).

**3. 아키텍처 — 우수.**
- 순수 Dart 경계 준수: materials/grid/rules/game_state/game_loop/emitter/rasterize/flask/ink_budget/
  star_rating/loader/validator/gimmick_builder에 flutter import 0. render/palette는 dart:typed_data만.
- gimmick_builder가 "검증된 입력 가정 + sim 공개 타입만 조립" 소유권 경계 명시 준수. 순환 의존 없음.
- 매직 넘버: 밸런스 전량 `SimConstants`, 셸 수치·색 전량 `tokens.dart`(하드코딩 hex 0 — 게이트 QA 확인),
  별점 배율 `star_rating` 상수, 검증 범위 `validator` 상수. 단일 소스 원칙 일관.
- 경미: P3-3(2계층 관통), debug_hud 사장(P3-6).
- 테스트: 27파일 180케이스. sim/gameplay/meta 두터움(결정성·회귀·경계). 얇은 곳: 셸 위젯은 스모크만,
  ProgressStore prefs 왕복 통합 테스트 부재(게이트 백로그), P2-1 dispose 레이스 회귀 테스트 부재.

**4. 보안/출시 — 양호.**
- 디버그 코드 전량 `kDebugMode`/`debugPrint` 가드(release 스트립). 에디터 진입 kDebugMode 게이트.
  stray print() 0. 네트워크·시크릿·외부 입력 주입면 없음.
- prefs 무결성: loadProgress/loadSettings/GameProgress.fromJson 모두 손상 입력 방어(빈 상태 폴백).
  개선 여지 P3-7(손상 백업).

---

## 회귀·정합 확인
- 격리 worktree(9d1f149) `flutter analyze` 클린 재확인 — M5 미커밋 변경과 무관하게 HEAD 자체가 클린.
- 게이트 QA(qa_m4_gate_20260718) 결과와 정합: 레벨 33 해금·토큰·빌드 GO 유지. 본 딥 감사는 그 위에
  코드 레벨 생명주기/경합/방어 항목을 추가 발굴(전부 비차단).
