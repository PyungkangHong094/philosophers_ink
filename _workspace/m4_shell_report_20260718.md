# M4 셸 UI 1차 구축 리포트 (2026-07-18)

담당: shell-ui-engineer (shell-m4). 소유 범위: `lib/ui/`, `lib/meta/`, `lib/main.dart` 엔트리.
SSOT: GDD 8.4 셸 디자인 시스템 + `ink-shell-design` 스킬. 시각 참고: `docs/philosophers_ink_shell_mockup.html`.

---

## 1. 화면 구조 (내비게이션)

```
InkApp (MaterialApp)
 └ _Bootstrap            # prefs + 레벨 카탈로그 비동기 로드, 스플래시
    └ InkServices        # settings/progress/catalog 를 트리에 주입 (InheritedWidget)
       └ TitleScreen                     # 골드 플라스크 호흡 + 로고, 탭 → 챕터 선택
          └ ChapterSelectScreen          # 세로 카드 4장(스파인·별·해금), 우상단 설정
             └ LevelSelectScreen         # 5열 셀 그리드, 셀 탭 → [잉크 플러드] → 인게임
                └ PlayScreen             # 정식 인게임 (HUD·클리어·실패·일시정지)
             └ SettingsScreen            # 토글 3종 + (디버그) 에디터 진입
```

- **셸→인게임 전환**: `inkFloodRoute` — 탭 좌표 기점 원형 확장(650ms, easeInOutQuart), 원 밖은
  투명이라 아래 블랙 셸이 비쳐 색이 번지는 인상. pop 시 역방향 수축. reduced motion 시 즉시 컷.
  플러드 색 = 레벨의 실제 배경색(`level.background`) — GDD "그대로 인게임 배경이 됨"의 충실 구현.
- **다음 레벨**: 클리어 오버레이의 [다음 레벨]은 같은 챕터 내 다음 레벨로 `pushReplacement`(중앙 기점
  플러드). 챕터 경계 넘김은 제공하지 않고 나가기로 레벨 선택 복귀(해금 규칙 존중).

### 파일 목록 (신규)

| 파일 | 역할 |
|---|---|
| `lib/ui/tokens.dart` | 컬러·타이포(`InkText`)·모션·간격 토큰. hex/매직 수치 단일 소스 |
| `lib/ui/widgets.dart` | 공용 컴포넌트: `InkCTA`·`InkGhostButton`·`InkEyebrow`·`StarRow`·`InkGauge`·`InkCard` |
| `lib/ui/ink_flood.dart` | 시그니처 잉크 플러드 전환 라우트 |
| `lib/ui/settings_controller.dart` | reduced motion·햅틱·사운드(M5 훅) 상태 + 햅틱 게이트 |
| `lib/ui/app.dart` | 앱 루트 + 부트스트랩 + `InkServices` 프로바이더 |
| `lib/ui/screens/title_screen.dart` | 타이틀 (골드 플라스크 CustomPaint) |
| `lib/ui/screens/chapter_select_screen.dart` | 챕터 선택 |
| `lib/ui/screens/level_select_screen.dart` | 레벨 선택 (플러드 진입점) |
| `lib/ui/screens/settings_screen.dart` | 설정 |
| `lib/ui/game/play_screen.dart` | 인게임 오케스트레이터 + 상단 HUD + 플라스크 페인터 |
| `lib/ui/game/ink_palette_bar.dart` | 하단 잉크 팔레트 바 (debug_hud 대체) |
| `lib/ui/game/clear_overlay.dart` | 클리어(별 스탬프)·실패 오버레이 |
| `lib/ui/game/pause_overlay.dart` | 일시정지 오버레이 |
| `lib/meta/chapters.dart` | 4챕터 정적 테이블(라틴/한글/범위/스와치) |
| `lib/meta/level_catalog.dart` | assets/levels 스캔·파싱, 존재 레벨만 노출 |
| `lib/meta/progress.dart` | 별점·클리어 기록 + 해금 규칙 + 직렬화 |
| `lib/meta/progress_store.dart` | shared_preferences 영속화 브리지 |

`lib/main.dart`는 디버그 셸(GameScreen/에셋 순회)에서 `InkApp` 부팅으로 교체. 기존 인앱 에디터는
설정 화면 내 `kDebugMode` 가드 히든 진입으로 유지.

---

## 2. 디자인 토큰 체계

- **컬러(`InkColor`)**: 표면 5단(black0~hairline), 골드 3종(gold/goldHi/goldDeep), 텍스트 3단
  (parchment/text2/text3), 챕터 스와치 4색(nigredo/albedo/citrinitas/rubedo), scrim90. GDD 8.4.2 그대로.
- **타이포(`InkText`)**: displayXL/L/M(라틴 대문자), headingKo/titleKo(한글 음수 자간), body/caption/
  eyebrow/cta. 숫자는 `FontFeature.tabularFigures()`.
  - ⚠️ **타입명 주의**: 타이포 토큰 클래스는 `InkText`. GDD/스킬 표기는 `InkType`였으나 sim의
    잉크 enum `InkType`과 충돌하여 `InkText`로 명명(의도적 상이점, 아래 4절).
- **모션(`InkMotion`)**: fast 120 / base 240 / ritual 650 / starStagger 250, flood=easeInOutQuart,
  stamp=easeOutBack.
- **간격(`InkSpace`)**: 4/8/16/24/40/64 + radius 2(샤프) + levelCell 56 + touchTarget 44.
- 하드코딩 hex/수치 없음 — `dart analyze` 클린으로 확인. 인게임 캔버스 배경색만 레벨 JSON에서 온다(의도).

---

## 3. 메타 저장 스키마

`shared_preferences` 문자열 키 2개(JSON 직렬화):

- `ink.progress.v1`:
  ```json
  { "version": 1, "records": { "1": {"cleared": true, "stars": 3}, "2": {"cleared": true, "stars": 2} } }
  ```
  - 별점은 **최고치 유지**(하락 없음), 클리어 플래그는 한 번 켜지면 유지. 변경 시에만 저장.
- `ink.settings.v1`:
  ```json
  { "reducedMotion": false, "haptics": true, "sound": true }
  ```

**해금 규칙 (GDD 7.1)**:
- 챕터 1(콘텐츠 존재 최소 챕터)은 항상 해금. 챕터 c(>1)는 하위 챕터의 **존재하는 모든 레벨** 클리어 시 해금.
- 챕터 내부 선형 해금: 첫 레벨은 챕터 해금 시 열리고, 이후 레벨은 직전(존재) 레벨 클리어 시 열림.
- 콘텐츠가 듬성듬성해도(파일 일부만 존재) 안전. `assets/levels/`를 매니페스트 스캔 → 파싱 성공한 것만
  노출하고 실패는 `loadErrors`에 기록(조용한 스킵 금지). 매니페스트 로드 자체 실패 시 빈 카탈로그 폴백.

---

## 4. GDD 스펙과 의도적으로 다른 부분

1. **타이포 토큰 클래스명 `InkText`** (GDD/스킬은 `InkType`). sim/materials의 잉크 enum `InkType`과
   전역 충돌하므로 개명. 값·역할·스케일은 스펙 동일.
2. **플러드 색 = 레벨 배경색**(GDD 문구는 "챕터색"). 챕터 스와치 대신 인게임 실제 배경색으로 번지게 해
   "그대로 인게임 배경이 됨"을 충실히 구현. 알베도(은백) 등은 스와치와 배경이 근사해 체감 차 미미.
3. **레벨 선택 정원 셀**: 챕터 정원(11/22칸)만큼 셀을 그리되 파일 없는 슬롯은 "absent"(text3, 비활성)로
   표시. 미저작 슬롯을 감추지 않고 정원을 드러내는 선택(진행 위치 인지).

---

## 5. 골드 희소성 검산 (화면당 1~2개 원칙)

| 화면 | 골드 요소 | 개수 | 판정 |
|---|---|---|---|
| 타이틀 | 플라스크 라인아트(+글로우) | 1 | OK |
| 챕터 선택 | 획득 별 아이콘/카운트, 현재 챕터 골드 보더 | 2 | OK (GDD 명시) |
| 레벨 선택 | 현재 셀 골드 보더+글로우, 획득 별, 작업(OPERATIO) 골드 링 | 2 + 승인 예외 | OK (링은 LEVELS 1장 승인 예외) |
| 클리어 | 별 스탬프(골드), 잉크 게이지 필(골드), CTA [다음 레벨](골드 필) | 3* | 주의 |
| 일시정지 | 없음(전부 고스트/무채) | 0 | OK |
| 설정 | 토글 ON 상태만 골드 | 상태 의존 | OK |
| 인게임 | 플라스크 윤곽(골드), 선택 잉크병 골드 보더 | 2 | OK |

\* **클리어 화면 골드 3요소는 GDD 8.4.4가 명시적으로 나열한 구성**(별·게이지 필·CTA)이라 스펙 준수로
   판단. 다만 "화면당 1~2개" 일반 원칙보다 많으므로 M5 폴리시에서 게이지 필을 무채+골드 값 텍스트로
   낮추는 안을 QA와 검토 권장.

---

## 6. 품질 바닥 (GDD 8.4.7) 대응

- 터치 타겟: 레벨 셀 56px(`InkSpace.levelCell`), 버튼/아이콘 44px(`touchTarget`), 잉크병 56px.
- 세이프 에어리어: 전 화면 `SafeArea` / 인게임은 `MediaQuery.paddingOf` 반영.
- reduced motion: 설정 토글 || `MediaQuery.disableAnimations`. 플러드 즉시 컷, 타이틀 호흡·펄스 정지,
  별 스탬프 페이드. 햅틱은 설정 게이트(`SettingsController.hapticLight/Selection`).
- 일시정지 오버레이: black0 90% scrim(블러 금지 — 성능).
- 대비: parchment/gold on black0 (AA↑). 비활성은 색이 아니라 text3 명도로.
- 전 위젯 `Semantics`(button/selected/toggled/label) 부여.

---

## 7. 검증 결과

- `dart analyze` (lib+test): **No issues found**.
- 신규 테스트 21개 전부 통과:
  - `test/meta/progress_test.dart` (11): 별점 최고치·클리어 유지·notify·onChanged·집계·직렬화 왕복·해금 4종.
  - `test/meta/level_catalog_test.dart` (4): id 정렬·byId·그룹핑·populatedChapters·빈 카탈로그.
  - `test/ui/shell_smoke_test.dart` (5): 타이틀·챕터·레벨·설정 토글·인게임 HUD 스모크.
  - `test/widget_test.dart` (1): InkApp 부팅 → 타이틀 도달(기존 M2 RESET 테스트 대체).
- 전체 `flutter test`: 179 통과 / **1 실패** — 아래.

### 미해결 이슈 (내 소유 밖)

- **`test/level/loader_test.dart:68` 실패**: `level_001.json`의 `ink_budget.chalk`를 100으로 단언하나,
  level-designer가 파일을 250으로 갱신하여 드리프트. loader_test(gameplay-engineer 소유) 또는
  level_001.json(level-designer 소유) 정합화 필요. shell 코드와 무관. team-lead에 보고 완료.

---

## 8. M5 폴리시로 이연

- 폰트 에셋 미탑재(`assets/fonts/` 없음) → 시스템 폴백. `InkText.displayFamily/textFamily = null`에
  TODO. M5에서 Anton/Pretendard 번들 + family 지정.
- 사운드: `SettingsController.sound` 토글·훅만 존재. flutter_soloud 배선은 M5(sim-engineer 협의).
- 잉크 플러드 폴리시(입자·룬 문양), 별 스탬프 글로우 정교화, 타이틀 파티클 물리 개선.
- 클리어 골드 3요소 → 1~2요소 절감 검토(5절).
- 챕터당 보너스 레벨 2~3개 해금(GDD 7.1) 미구현 — M5+.
- 인게임 캔버스 핸드오프 타이밍(플러드↔sim 첫 프레임) sim-engineer와 정밀 협의(M5).
