# 현자의 잉크 — 출시 전 성능·버벅임(jank) 감사

- **일자:** 2026-07-20
- **담당:** performance-engineer
- **범위:** 순수 Dart 시뮬 벤치가 못 잡는 버벅임 원인을 코드 레벨에서 색출 (읽기+분석 전용, 코드 미수정)
- **대상 상태:** M0~M6 완료 (테스트 352, analyze 0), 시뮬 틱 0.87~1.35ms/3ms 예산 내 검증됨
- **방법:** 렌더/게임루프/오디오/셸/메모리 경로 코드 정독 + 할당 패턴 추적

---

## Executive Summary

| 등급 | 건수 | 핵심 |
|------|------|------|
| 🔴 P1 버벅임 유발 확실 | 1 | 렌더 핫패스(`WorldPointsPainter`)의 프레임당 힙 할당 |
| 🟠 P2 조건부 위험 | 2 | 플라스크 HUD 프레임당 Paint 할당(무조건 repaint), 앰비언트 오디오 2차 전체 스캔(기본 OFF) |
| 🟡 P3 개선 기회 | 3 | 초시계 60fps 리빌드, 디버그 전용 이미지 경로, 시뮬·메모리 청결 확인 |

**핵심 판정:** 그리드는 **160×320 = 51,200 셀**이고 플레이 화면은 `_frameTick`으로 매 프레임(60fps) 페인터를 repaint한다. 시뮬 틱은 예산 내지만 **페인트 경로**에서 프레임당 대량 할당이 발생한다 — 시뮬 틱 벤치 밖이라 검증되지 않았고, 이것이 P1이다. 시뮬 틱·오디오 합성 캐시·레벨 전환/dispose 경로는 할당 청결하며 77레벨 누적 성장 요인은 없다.

---

## 🔴 P1 — 버벅임 유발 확실

### P1-1. `WorldPointsPainter.paint` 프레임당 힙 할당 (GC 압력 → 주기적 버벅임)

**파일:줄** `lib/render/world_painter.dart:174-198` (특히 `:178`, `:185-187`, `:196`)

**패턴 (매 프레임, 60fps, UI 스레드):**
1. `:178` `List<List<double>?>.filled(kMaterialTable.length, null)` — 버킷 배열 신규 할당.
2. `:182-187` 활성 셀마다 growable `<double>[]` 버킷에 좌표 2개를 **박싱된 double**로 추가. Dart VM에서 `<double>[]`는 박싱 저장 → 활성 셀 N개당 2N개 박싱 객체 + 리스트 백킹 재할당(성장).
3. `:196` 물질별 `Float32List.fromList(b)` — 매 프레임 **전체 복사**로 신규 Float32List 생성.

**근거:** 방출구가 지속적으로 입자를 뿌리는 레벨에서 활성 셀은 수천~수만 규모. 활성 1만 셀 가정 시 프레임당 약 2만 박싱 double + Float32List 복사 → 60fps에서 초당 100만+ 할당. `CustomPainter.paint`는 UI 스레드에서 Picture(디스플레이 리스트)를 생성하므로, 이 할당 폭주가 UI 스레드 young-gen GC를 주기적으로 유발 → 수십~수백 ms 간격의 **버벅임 스파이크**. 순수 Dart 시뮬 틱 벤치(0.87~1.35ms)는 이 경로를 전혀 포함하지 않아 놓친다. (참고: 전 51,200 셀 순회 자체는 typed-array 읽기라 저렴 — 문제는 할당이다.)

**권장 수정 (1줄):** 물질별 재사용 `Float32List` 버퍼를 State가 소유(하이워터마크로만 성장)하고 제자리 채운 뒤 `Float32List.sublistView(buf, 0, n*2)`를 `drawRawPoints`에 넘겨 프레임당 할당을 0으로 만든다.

---

## 🟠 P2 — 조건부 위험

### P2-1. 플라스크 HUD 무조건 프레임당 repaint + Paint 할당

**파일:줄** `lib/ui/game/play_screen.dart:504-509` (`ValueListenableBuilder` on `_frameTick`) + `:942` (`shouldRepaint => true`) + Paint 생성 `:859-863, 897-912, 933`

**근거:** `_frameTick`이 매 프레임 증가 → CustomPaint가 매 프레임 새 `_FlaskHudPainter`로 리빌드되고 `shouldRepaint`가 무조건 true라 매 프레임 paint. paint 안에서 `wall`/`fill`/`line`/`dot` Paint를 플라스크마다 신규 생성. 플라스크 수가 적어(보통 1~4개) 절대 비용은 작지만, **무조건 프레임당 Paint 할당**이 P1 위에 얹혀 UI 스레드 할당 총량을 키운다. (채움 진행도가 실시간 변하므로 repaint 자체는 정당 — 문제는 Paint 재할당.)

**권장 수정 (1줄):** `wall` 등 정적 Paint를 static으로 승격하고(fill은 `..color` 변이로 재사용), repaint 트리거를 `_frameTick`이 아니라 플라스크 상태 변화 notifier로 좁힌다.

### P2-2. 앰비언트 오디오 2차 전체 그리드 스캔 (현재 기본 OFF)

**파일:줄** `lib/ui/game/play_screen.dart:297-302` → `_ambientDensities()` `:368-393` (스캔 루프 `:373`)

**근거:** 활성화 시 `_onFrame`이 12프레임마다(~5Hz) 51,200 셀을 **다시 전수 스캔**해 밀도 3종을 계산한다. 현재 `GrainPlay.ambientLayersDefaultEnabled = false` (`lib/audio/sound_tokens.dart:142`)라 **런타임 비용 0** — 실플레이 피드백("우웅")으로 기본 꺼둠. 위험은 조건부: 설정/향후 재활성 시 페인트 스캔과 별개로 UI 스레드에 5Hz 전체 스캔이 추가된다.

**권장 수정 (1줄):** 활성화하려면 이 밀도 스캔을 시뮬 틱 또는 P1의 페인트 스캔에 합쳐 단일 패스로 처리한다(별도 전수 스캔 금지).

---

## 🟡 P3 — 개선 기회

### P3-1. 초시계 60fps 리빌드

**파일:줄** `lib/ui/game/play_screen.dart:583-604`

`ValueListenableBuilder<int>(_frameTick)`가 Container+BoxDecoration+Border+Text를 매 프레임(60/s) 리빌드하지만, `formatElapsed(tickCount)`는 초당 1회만 값이 바뀐다. 무해하지만 60배 낭비 리빌드.

**권장 수정:** 초 단위(1Hz) 파생 notifier 또는 포맷된 문자열 `ValueListenable`로 라벨 변경 시에만 리빌드.

### P3-2. 디버그 전용 이미지 디코드 경로 (출시 무관)

**파일:줄** `lib/render/world_painter.dart:57-139` (`WorldImageSource`/`WorldPainter`)

이 경로는 프레임당 `ImmutableBuffer`+`ImageDescriptor`+`codec`+`ui.Image` 생성/해제(감사 범위 #1이 우려한 지점 그대로)지만, 사용처는 **디버그 `lib/gameplay/level_player.dart:47,65,183`뿐**이다. 출시 셸 `PlayScreen`은 `WorldPointsPainter`를 쓴다. dispose 가드는 정확함(`:73-103`, in-flight/`_disposed` 처리 견고).

**권장 수정:** 릴리스 빌드에서 `level_player` 제외 확인만(디버그 플레이어). 셸 경로엔 영향 없음.

### P3-3. ✅ 청결 확인 (수정 불필요, 근거 포함)

- **시뮬 틱 할당 청결:** `_moveStamp` Int32List는 크기 변화 시에만 재할당(`lib/sim/rules.dart:72-74`), `grid.cells`는 안정 Uint8List(`lib/sim/grid.dart:15`), 이동/반응/게이트/포탈 패스에 프레임당 배열 생성 없음. → 틱이 예산 내인 이유와 정합.
- **게임 루프 청결:** accumulator를 `maxFrameAccumSeconds`(0.25s)로 클램프(`lib/core/game_loop.dart:43-45`) → 죽음의 나선 방지. 백그라운드 전환 시 `didChangeAppLifecycleState`가 시뮬 정지 + `stopAll`(`play_screen.dart:273-281`).
- **메모리·레벨 전환 청결:** "다음 레벨"은 `pushReplacement`(`lib/ui/screens/level_select_screen.dart:166`)라 77레벨 연속 플레이에도 PlayScreen 스택 누적 없음. `dispose`에서 ticker→session(InkController)→notifier 순 해제(`play_screen.dart:257-270`, `lib/gameplay/level_session.dart:173-175`). 그리드는 51,200바이트 Uint8List로 무시 가능.
- **오디오 청결:** 앱 단일 서비스, 파형/그레인은 `init()`에서 1회 로드 후 재생만 재사용(`lib/audio/soloud_audio_service.dart:47-81`) — SFX마다 재합성 없음. stroke/flask/phase 스로틀 존재(`:181-198, 243-248`). 원샷 자동 종료라 핸들 누수 요인 없음. 볼륨 램프는 `fadeVolume`+`scheduleStop`으로 자기정리(`:126-129`).
- **UI 리빌드 범위 청결:** `InkPaletteBar`는 `InkController`(ChangeNotifier) 구독 — select/charge/reset 시에만 notify(`lib/gameplay/ink_controller.dart:44-79`), 프레임당 리빌드 아님. 타이틀 호흡 애니메이션은 `deactivate`에서 정지·`activate`에서 재개(`lib/ui/screens/title_screen.dart:44-54`)라 타 화면에서 안 돎.

---

## 범위 7 — 도구 실행 기준선 (부분 실패, 원인 명시)

- **`flutter analyze` 이 PC 기준선 확보 실패.** export는 지시문대로 사용(`PATH=/c/flutter/bin`, `TMP/TEMP='C:\flutter-tmp'`, `PUB_CACHE=/c/pub-cache`). 실패 원인은 env가 아니라 Windows 심링크 권한:
  ```
  Building with plugins requires symlink support.
  Please enable Developer Mode in your system settings.
  ```
  `analyze`가 `pub get`을 트리거했고 그 단계에서 막혔다. 이는 알려진 환경 제약(kap-flutter-env)이며 실기기 프로파일과 함께 **Mac/기기 몫**이다.
- **부수효과 원복 완료:** `pub get`이 건드린 pubspec 계열 파일을 `git checkout --`로 원복, `git status` clean 확인.
- **P1 확진 제안(Mac/기기):** DevTools Timeline에서 방출구 밀집 레벨 플레이 중 UI 스레드 프레임 시간과 GC 이벤트 상관 확인. `WorldPointsPainter.paint` 구간이 프레임 예산(16.6ms)을 잠식하는지, GC 직후 프레임 드롭이 보이는지가 P1 확진 신호.

---

## 총평

출시 전 처리 1순위는 **P1-1 (렌더 페인터 프레임당 할당)** 단 1건 — 순수 Dart 벤치가 통과한 이유(페인트 경로 밖)와 정확히 맞물린다. P2 2건은 P1 수정과 함께 정리하면 좋고(특히 P2-1은 같은 파일), 나머지 경로는 청결하다. 억지 지적 없음.
