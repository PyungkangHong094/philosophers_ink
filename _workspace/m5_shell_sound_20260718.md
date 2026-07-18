# M5 셸 사운드 + 폴리시 리포트 (2026-07-18)

담당: shell-ui-engineer (shell-m4). 소유: `lib/ui`, `lib/meta`, `lib/audio`(신설), `main.dart`.
SSOT: GDD 9(사운드 디자인) + 8.4(셸) + `ink-shell-design`/`game-audio` 스킬.

---

## 1. 사운드 시스템

오디오 에셋이 아직 없어 **flutter_soloud 파형 오실레이터로 1차 SFX를 코드 생성**한다(절차 합성).
BGM은 에셋 확보 시 후속(GDD 9.2 BGM 행 — M5+).

### 파일 (lib/audio 신설)

| 파일 | 역할 |
|---|---|
| `sound_tokens.dart` | 믹스 게인(dB→선형), 이벤트별 주파수·볼륨·길이, 변주 디튠, 그레인 파라미터 — 매직 수치 단일 소스 |
| `audio_service.dart` | `AudioService` 계약 + `SilentAudioService`(무음 폴백, 테스트 기본) |
| `soloud_audio_service.dart` | flutter_soloud 절차 합성 구현 |

### 아키텍처

- `AudioService` 인터페이스로 호출부(셸·인게임)와 엔진을 분리. 실제는 `SoLoudAudioService`,
  초기화 실패·미지원 플랫폼·헤드리스 테스트는 `SilentAudioService` 또는 내부 무음화로 폴백.
  **오디오는 절대 게임을 죽이지 않는다** — init/재생 실패를 전부 삼킨다.
- `InkServices.audio`로 트리에 주입. `_Bootstrap`이 `SoLoudAudioService`를 만들어 init 후
  `settings`를 구독해 음소거·볼륨을 `configure`로 반영. 테스트는 `InkApp(audioOverride:)`로 무음 주입.
- **lib/sim 무수정**: 상전이 이벤트 훅이 없어, 사운드는 이미 존재하는 경로로만 소비한다:
  - 플라스크 착수 → `LevelSession(onSettle:)` 콜백(기존 API) → `flaskFill(phase)` (상별 피치).
  - 앰비언트 밀도 → PlayScreen이 매 프레임 읽는 `grid.cells`를 동적 카테고리 카운트(읽기 전용).
  - 드로잉/UI → 셸이 소유한 입력 지점.

### 이벤트 목록 (구현·배선 완료)

| 이벤트 | 트리거 | 합성 | 비고 |
|---|---|---|---|
| `uiTap` | 타이틀 시작·챕터 카드·레벨 셀·잉크병 선택·볼륨 확정 | fSquare 880Hz 45ms | UI 카테고리 |
| `stroke` | 드로잉 획 배치(placed>0) | triangle 196Hz 32ms, 45ms 스로틀 | 드래그 스팸 방지 |
| `flaskFill` | `onSettle`(착수 카운트업 동기) | triangle, 상별 피치(고체 G5·액체 D5·기체 B4) | GDD 9.2 최우선 폴리시 |
| `clearStinger` | 일반 레벨 클리어 | triangle 상승 3음(C5·E5·G5) | |
| `operatioStinger` | 작업(11의 배수) 레벨 클리어 | fSquare 하강·풍성 4음(G4·C5·E5·G5) | GDD 7.1 전용 스팅어 |
| `fail` | 오염 실패 | fSaw 하강 2음(E4·C4) | |
| `setAmbientDensity` | 활성 셀 밀도(≈5Hz 샘플) | saw superwave 110Hz 루프, 볼륨 변조 | 물질 앰비언트(수직 적응형) |

- **믹스 계층(GDD 9.2)**: 이벤트 SFX 0dB > 그레인 −6dB > BGM −10dB. `gainFromDb`로 dB 표기.
- **변주**: 재생마다 ±14센트 랜덤 디튠으로 반복감 제거(GDD 9.2 "변주 3~5개").
- **음소거(GDD 9 필수)**: 설정 화면 사운드 토글 + 볼륨 슬라이더(활성 트랙만 골드), **일시정지
  오버레이의 소리 켜기/끄기**(인게임 접근). 볼륨 영속화.

### ⚠️ sim 훅 요청 (gameplay/sim 소유 — team-lead 경유)

GDD 9.2의 **이벤트 SFX "결빙 crackle·증발 puff"**와 **파티클 그레인(낙하·퇴적 지속음)**은
상전이/입자 이동 순간 이벤트가 필요하다. 현재 lib/sim은 그런 콜백을 노출하지 않는다. 1차에서는
`grid.cells` 밀도로 **물질 앰비언트**만 근사했고(움직임·전이 구분 없음), 결빙/증발 개별 SFX는
미배선이다. `AudioService.flaskFill` 외에 sim→gameplay 전이 이벤트(예: `onPhaseChange(material,
kind, x, y)`) 훅이 있으면 crackle/puff와 진짜 파티클 그레인을 붙일 수 있다 — sim-engineer 협의 요청.

---

## 2. 폴리시

- **클리어 골드 파티클**: 별 스탬프 착지 순간 그 위치에서 골드 입자 7개가 솟아 페이드
  (`_StarParticles`, `clear_overlay.dart`). reduced motion 시 생략.
- **잉크 플러드 마감**: 확장 원 앞머리에 **플러드색(레벨 배경색)을 밝게 당긴 잉크 메니스커스 링**
  (소프트 글로우). 골드가 아닌 플러드색 자체 변주라 GDD "유일한 유채색" 순수성 유지. reduced motion 시 생략.
- **챕터 3(금 #D9A62E)·4(진홍 #8E1F2F)**: `kChapters` 스와치·라틴명 이미 정의됨. 레벨 34~77이
  병렬 저작 중이며 `LevelCatalog.discover`가 파일 등장 시 자동 그룹핑함을 테스트로 확인
  (`chapters_palette_test`). 현재 assets에는 챕터 1·2(33개)만 존재.

---

## 2b. 딥 감사(deep_audit_20260718) 인계 처리 — UI 계층

team-lead 인계분(내 소유 lib/ui 범위)을 함께 처리했다.

- **[P2-2] 세션 자원 미해제**: `PlayScreen.dispose()`에서 `_session.dispose()` 호출 배선
  (gameplay-engineer가 추가한 `LevelSession.dispose()` → `ink.dispose()`). 순서: 티커 정지 →
  세션 dispose → 이미지 소스 → notifier들. 이제 InkController(ChangeNotifier) 리스너 누수 없음.
- **[P3-2] FlaskHudPainter 프레임당 TextPainter 할당**: `_FlaskLabelCache`(State 소유·dispose)로
  라벨 문자열이 바뀔 때만 TextPainter 재생성·재레이아웃. 프레임당 신규 할당 제거. 감사가 render
  소유로 적었으나 실제 UI 계층이라 내가 처리.
- **[P3-4] 타이틀 호흡 컨트롤러 offstage 지속**: `deactivate`에서 `stop`, `activate`에서 `repeat`.
  다른 라우트가 위를 덮는 경우는 Flutter의 TickerMode가 이미 vsync를 뮤트하므로, 이 가드는
  명시적 트리 분리(pop/이동)를 다룬다.
- **[P3-6] debug_hud 사장 추정**: 3절 참조 — 사장 아님(에디터 스택), gameplay 소유라 미수정.
- (참고) [P2-1] WorldImageSource async dispose 레이스는 `lib/render/world_painter.dart` 소유 —
  render/sim 담당. play_screen은 기존대로 `_imageSource.dispose()`만 호출.

---

## 3. qa-m4 P2 정리

- **ProgressStore 영속 왕복 통합 테스트**: `test/meta/progress_store_test.dart` 추가 —
  진행 기록·별점 최고치·설정(볼륨·사운드·모션) 저장/복원 4케이스.
- **debug_hud 사장 코드**: **사장 아님.** `debug_hud.dart`(InkHud)·`level_player.dart`(LevelPlayer)는
  `editor_screen`의 테스트 플레이 스택으로 여전히 살아있다(editor → LevelPlayer → InkHud).
  play_screen/ink_palette_bar의 grep 매치는 doc 코멘트 오탐. 두 파일은 **lib/gameplay 소유**라
  내가 수정하지 않았다 — 권고: gameplay-engineer가 debug_hud 헤더의 "M2 이후 대체" 문구를
  "에디터 테스트 플레이 전용"으로 갱신. (team-lead에 별도 보고.)
- **작업 레벨 ◈ 표기**: 확정대로 "레벨 셀 골드 링 유지 + 이름 접두 없음". 현행 `_LevelCell`가
  이미 골드 링만, 접두 없음 — 변경 불필요. 인게임 아이브로우도 "LV n"만.
- **L16 teaches=[]**: 콘텐츠 소유 — 손대지 않음.

---

## 4. 보너스 레벨 해금 (GDD 7.1) — 설계 문서 공백

GDD 7.1은 "별점 누적으로 챕터당 보너스 레벨 2~3개 해금"을 언급하나, **레벨 콘텐츠 SSOT인
`PHILOSOPHERS_INK_LEVELS.md`에 보너스 레벨의 정의가 전혀 없다**(보너스/bonus 검색 0건, 5장
작업 레벨표·6장 설계표 모두 1~77 본편만). 문서 우선 원칙에 따라 **구현하지 않고 공백으로 보고**한다.

필요 결정(team-lead/level-designer):
- 보너스 레벨의 위치(슬롯), 해금 임계(챕터별 누적 별 몇 개), 콘텐츠 정의를 LEVELS.md에 먼저 명시.
- 확정 후 `GameProgress`에 보너스 해금 판정 + 레벨 선택 UI 보너스 슬롯을 추가하면 된다(해금 로직은
  기존 `isChapterUnlocked`/별점 집계 재사용 가능).

---

## 5. 검증

- `dart analyze` (내 소유 lib/audio·ui·meta + 내 테스트): **No issues found**.
- 전체 `flutter test`: **206 통과 / 0 실패**. (M4의 loader_test 충돌은 소유자가 해소함.)
- 신규 테스트(누계 +11):
  - `test/audio/audio_service_test.dart` (3): 무음 폴백·미초기화 안전 무음·음소거 무예외.
  - `test/meta/progress_store_test.dart` (4): 진행·별점 최고치·설정 영속 왕복·기본값.
  - `test/meta/chapters_palette_test.dart` (4): 챕터 3·4 스와치·11배수 경계·OPERATIO·카탈로그 그룹핑.
- 기존 셸 테스트(shell_smoke·widget)는 `SilentAudioService` 주입으로 갱신 — 회귀 없음.

### 미해결/이관

- (cross-team) `test/render/world_image_source_test.dart`에 lint 2건(unnecessary_type_check /
  unnecessary_import) — 렌더팀 미추적 파일, 내 소유 아님. team-lead 보고.
- (sim 훅) 결빙 crackle·증발 puff·진짜 파티클 그레인 → sim 전이 이벤트 훅 필요(위 1절).
- (문서 공백) 보너스 레벨 정의(4절).
- macOS 데스크톱 미스캐폴딩으로 `flutter build macos` 불가(M4와 동일). **iOS 시뮬레이터 디버그
  빌드 성공** (`✓ Built build/ios/iphonesimulator/Runner.app`, 227.8s) — flutter_soloud 네이티브
  플러그인 통합·앱 어셈블 검증됨. widget_test가 InkApp 부팅(무음 주입)을 추가로 커버.

---

## 6. M5+ 이연

- BGM(챕터별 앰비언트 루프 + 클리어 덕킹) — 에셋 확보 후.
- 결빙/증발 이벤트 SFX·파티클 그레인 실배선 — sim 훅 확보 후.
- 착수음 카운트업 미세 동기·룬 애니메이션(GDD M5 표) — sim/폴리시 협업.
- 오디오 에셋 번들 시 30MB 예산 관리(GDD 9.2).
