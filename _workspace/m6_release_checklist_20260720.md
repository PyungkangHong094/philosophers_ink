# M6 출시 준비 — 검증 체크리스트 · 정책 가이드 · 스토어 초안 (2026-07-20)

검증자: qa-m6 · 기준: `docs/PHILOSOPHERS_INK_DESIGN.md` 12~14장 · `ink-qa-protocol`
환경: Flutter 3.44.6 / Dart 3.12.2, `env -u PUB_CACHE -u TMP -u TEMP` 접두.
대상: main 최신 (카운트다운·비커 벽·배수 물리 반영). **현행 빌드 기준** — shell-m6(광고·IAP)·
hints-m6(힌트) 산출물은 미통합 상태이며 후속 검증 대상.

## 요약

- **GDD 14장 체크리스트**: PASS 6 / 실기기필요 1 / 후속(미통합) 1 / 정책 별도.
- 실측: `flutter analyze` 클린(0 issues), `flutter test` **318개 전부 통과**(팀 보고 312 상회),
  iOS 디버그 빌드 성공, 인테스트 성능 벤치 예산 내.
- **출시 차단(P0/P1) 5건** — 아래 "출시 차단 항목" 참조. 전부 설정/정책 레이어(코드 로직 아님).
- 사람 실플레이 검증 전까지 **출시 보류 레벨 7개**: 011·043·047·048·050·054·065 (솔버 한계).

---

## 1. GDD 14장 출시 전 검증 체크리스트 (실측)

| # | 항목 | 판정 | 근거 |
|---|---|---|---|
| 1 | 코어 루프 완주(시작→플레이→클리어/재시작→결과) | **PASS** | `level_session_test`: "방출→낙하→착수 카운트→클리어" 통과. `widget_test`: InkApp 부팅→타이틀 도달. 세션 레벨에서 착수·클리어·실패(오염/타임아웃) 전 경로 커버. *전 화면 수동 완주는 실기기 항목(아래 3).* |
| 2 | 재시작 3회 연속 동일 동작(결정성) | **PASS** | `determinism_test`: "같은 시드·같은 입력 → 300틱 후 해시 3회 동일" + "reset 후 재현 해시 동일". `HeadlessSession`·`LevelSession`·`gimmicks_determinism` 각각 reset 3회 동일 해시. GDD 10.5 계약 충족. |
| 3 | 실기기 60fps(중가 Android 1 + 구형 iPhone 1) | **실기기 필요** | Android 툴체인 부재로 실기기 프로파일 미실행(STATUS 보류 항목). **대체 증거**: 순수 Dart 인테스트 벤치 — 기믹 5종 활성 틱 min **0.978ms**, 상전이 대량 min **1.063ms**(활성셀 1674~1836, 예산 3ms). iOS 디버그 빌드 성공(AOT 링크 정상). **기준 기기 미선정** — 사용자 조치 필요. |
| 4 | 터치 타겟 44px 이상 | **PASS** | `InkSpace.touchTarget=44` / `levelCell=56`(tokens.dart) 정의·사용 확인: 일시정지·재시작(play_screen 679), 잉크 팔레트(compact 50/full 92, 44+ 유지), 설정 토글, 레벨 셀 56. 경미 권고: settings 255·level_select 51의 하드코딩 `44`를 토큰 참조로. |
| 5 | 게임 로직 내 매직 넘버 0개 | **PASS** | `lib/sim`·`lib/gameplay` 밸런스 값 스캔: 별점 임계는 named const(`kThreeStarPercent=115`, `kTwoStarPercent=160`), 나머지 밸런스는 `constants.dart`·레벨 JSON. 잔여 리터럴 22건은 전부 debug_hud·level_player(에디터/디버그 전용 UI)의 폰트·패딩 레이아웃 상수 — 프로토콜 예외. |
| 6 | 음소거 토글 동작 | **PASS** | 설정 `sound` 토글 → `AudioService.configure(enabled:...)`. app.dart 116~120이 init·설정변경(addListener)마다 전달. `audio_service_test`: "음소거(enabled=false) 시 무예외". `progress_store_test`: "설정(볼륨·사운드·모션) 저장·복원". |
| 7 | 광고 빈도 제한·리워드 힌트 지급 | **후속(미통합)** | google_mobile_ads·in_app_purchase는 pubspec에 존재하나 `lib/meta`에 ads/iap 코드 미배선(shell-m6·hints-m6 진행 중). 현행 빌드에는 광고·힌트 로직 없음 → 통합 후 재검증. **크래시 리스크**: 통합 시 AdMob App ID 설정 필수(정책 §2.3). |
| 8 | 스토어 정책 체크리스트(12장) 전 항목 | **별도 (§2)** | 아래 정책 가이드 참조. 현 시점 미충족 3건(세로 고정·수출 규정·릴리스 서명). |

### 추가 확인(팀 리더 지정 항목)
- **진행 저장/복원**: **PASS** — `progress_store_test` "진행 기록 prefs 저장·재오픈 복원", "별점 최고치 갱신 영속(하락 없음)". 온보딩 노출 이력도 영속.
- **초기화 동작**: **부분** — 인레벨 재시작(GameState.reset)은 §1-2에서 PASS. 설정 화면에 "안내(온보딩) 초기화" 존재(settings_screen 68). **전체 진행 초기화(별점 wipe) 기능은 없음** — GDD 미요구 항목이라 기준미정의. 출시 필수 아님, 향후 정책 결정.

---

## 2. GDD 12장 정책 체크리스트 (실무 가이드)

각 항목 "무엇을 · 어느 콘솔 · 어디서" 단계로 기술. **★ = 현행 빌드에서 미충족(조치 필요)**.

### 2.1 타겟 연령 선언
- **Google Play**: Play Console → 앱 → 정책 → **앱 콘텐츠 → 타겟 연령 및 콘텐츠**. 물리 퍼즐·폭력 없음 →
  "만 13세 이상" 또는 전연령 선택. 아동 대상(13세 미만) 선택 시 Families 정책 강제(§2.4) — **광고 SDK
  구성이 Families 광고 요건을 만족해야 하므로, 광고 수익 모델과 상충하면 "13세 이상 + 아동 비대상"을 권장.**
- **App Store**: App Store Connect → 앱 → **연령 등급(Age Rating)** 설문. 전 항목 "없음/드물게 없음" →
  4+ 등급. "아동용 카테고리(Kids)" 는 선택하지 말 것(광고·계정 제약 증가).

### 2.2 콘텐츠 등급(IARC)
- **Google Play**: Play Console → **앱 콘텐츠 → 콘텐츠 등급** 설문 제출 → IARC 등급 자동 발급.
  퍼즐·비폭력·비도박 → 전 지역 최저 등급(ESRB Everyone / PEGI 3 예상). 광고 포함 체크 필수.
- **App Store**: §2.1 연령 등급 설문이 곧 콘텐츠 등급. 별도 제출 없음.

### 2.3 AdMob 콘텐츠 등급 + App ID ★
- **AdMob 콘솔**: apps.admob.com → 앱 등록(iOS·Android 각 1개) → **앱 설정 → 콘텐츠 등급을 "G(전체)"**
  로 설정(퍼즐 게임). 리워드/전면 광고 단위 생성.
- **★ App ID 미설정(크래시 차단)**: google_mobile_ads는 초기화 시 App ID를 요구한다. 통합 시 필수:
  - iOS: `ios/Runner/Info.plist`에 `GADApplicationIdentifier`(문자열) + `SKAdNetworkItems`(AdMob 제공 SKAdNetwork ID 목록) 추가.
  - Android: `android/app/src/main/AndroidManifest.xml` `<application>` 내 `<meta-data
    android:name="com.google.android.gms.ads.APPLICATION_ID" android:value="ca-app-pub-..."/>`.
  - **현행 빌드엔 둘 다 없음** → shell-m6 광고 통합과 함께 반드시 추가(누락 시 앱 시작 즉시 크래시).
- **사전 고지(심사 주의)**: App Store 심사 노트에 "리워드 광고로 힌트 제공, 광고 SDK: Google AdMob" 명시.

### 2.4 Google Play Families 정책
- 타겟 연령을 "13세 이상 + 아동 비대상"(§2.1 권장)으로 선언하면 Families 정책 **비적용** → 표준 광고 가능.
- 만약 전연령/아동 대상을 택하면: Play Console → **Families → 정책 준수**, 광고 SDK를 Google
  "Families 자체 인증 광고 SDK" 목록으로 제한(AdMob은 Families 모드 지원 — `tagForChildDirectedTreatment`
  설정 필요). **권장: 아동 비대상으로 단순화.**

### 2.5 계정 없는 구조 → App Store 5.1.1(v) 회피
- **현재 구조 적합**: 진행·설정은 `shared_preferences`(로컬 온디바이스)만 사용, 로그인·계정 생성 없음.
  IAP(광고 제거)는 계정 불요 — Apple 5.1.1(v)"핵심 기능에 무관한 계정 요구 금지"에 저촉되지 않음.
- **주의**: 향후 클라우드 세이브·리더보드 추가 시 "선택적 로그인"으로만. 현 범위 유지 시 조치 불요.

### 2.6 수출 규정(암호화 신고) ★
- **★ Info.plist 미설정**: `ios/Runner/Info.plist`에 `ITSAppUsesNonExemptEncryption` 키 없음 →
  App Store Connect 빌드 업로드 시마다 암호화 사용 여부를 수동으로 물음.
  - 이 게임은 표준 HTTPS(광고 SDK) 외 자체 암호화 없음 → **`ITSAppUsesNonExemptEncryption`=`false`** 추가 권장
    (심사 자동화·업로드 반복 질문 제거).
- **Google Play**: 미국 수출 관리 규정 자기 분류 — 표준 암호화만 사용이므로 별도 신고 불요(대시보드 고지만 확인).

### 2.7 개인정보 처리방침 / 데이터 안전
- **★ 광고 통합 시 필수**: AdMob은 광고 식별자(IDFA/AAID)를 수집 → 양 스토어 모두 개인정보 처리방침 URL 요구.
  - Play Console → **앱 콘텐츠 → 데이터 보안** 양식: "광고/기기 식별자 수집 — 예"로 신고.
  - App Store Connect → **앱 개인정보 보호** → "데이터 사용 — 타사 광고" 신고 + `NSUserTrackingUsageDescription`
    (ATT 프롬프트 문구) 추가 검토(AdMob 개인화 광고 사용 시).
- 계정·수집이 없는 현행(광고 미통합) 상태에선 "데이터 미수집"이나, **광고 통합 즉시 위 신고로 갱신** 필요.

---

## 3. 스토어 준비물 초안

**GDD 13장 리스크 준수**: 원작(sugar, sugar) 및 유사 클론 언급 절대 금지. 차별화 축(상전이·잉크·연금술)만 강조.

### 3.1 앱 이름 / 부제
- 한국어: **현자의 잉크** — 부제 "상전이 물리 퍼즐"
- English: **Philosopher's Ink** — subtitle "Phase-Shift Physics Puzzle"
- ⚠ 현행 Android 런처 라벨이 `philosophers_ink`(원시 패키지명) → **"현자의 잉크"/"Philosopher's Ink"로
  교체 필요**(AndroidManifest `android:label`). iOS는 `CFBundleDisplayName`="Philosophers Ink"(아포스트로피 없음, 정정 권장).

### 3.2 앱 설명문 — 한국어
> **쏟아지는 원소를 잉크 선 하나로 다스리세요.**
>
> 연금술사의 잉크는 물리 법칙을 그립니다. 석필로 벽을 세우고, 서리 룬으로 물을 얼려 다리를 놓고,
> 화염 룬으로 얼음을 녹여 증기를 피워 올리세요. 흐르고, 얼고, 끓어오르는 원소의 연쇄를 지켜보는 것이
> 이 퍼즐의 핵심입니다.
>
> · 고체·액체·기체 3상 상전이를 이용하는 falling-sand 물리 퍼즐
> · 석필·서리·화염 세 가지 잉크로 원소를 변환
> · 니그레도부터 루베도까지, 연금술 4대 작업을 관통하는 77개 레벨
> · 중력 반전, 포탈, 변성 게이트, 온도 존 — 조합으로 깊어지는 퍼즐 설계
> · 최소한의 잉크로 별 3개에 도전하는 재도전 설계
>
> 조용한 서재에서 시작해, 레벨마다 터지는 색의 향연. 손끝의 잉크 한 줄이 만드는 물리를 경험하세요.

### 3.3 앱 설명문 — English
> **Command falling elements with a single stroke of ink.**
>
> An alchemist's ink draws the laws of physics. Raise walls with chalk, freeze water into bridges with frost
> runes, melt ice and coax rising steam with flame runes. The heart of the puzzle is watching elements flow,
> freeze, and boil in cascading reactions.
>
> · A falling-sand physics puzzle built on solid / liquid / gas phase transitions
> · Three inks — chalk, frost, flame — to transform the elements
> · 77 levels tracing the four alchemical operations, from Nigredo to Rubedo
> · Gravity reversal, portals, transmutation gates, temperature zones — puzzles that deepen through combination
> · Chase three stars by solving with the least ink

### 3.4 키워드 (ASO)
- 한국어: 물리 퍼즐, 상전이, 연금술, 잉크, 드로잉 퍼즐, 낙하 모래, 두뇌 퍼즐, 얼음, 증기, 힐링 퍼즐
- English: physics puzzle, phase transition, alchemy, ink, drawing puzzle, falling sand, brain teaser, sandbox physics, relaxing puzzle, logic
- (원작·경쟁 타이틀명은 키워드에서도 제외 — 상표 리스크)

### 3.5 스크린샷 촬영 목록 (화면·레벨 지정)
세로 프레임. 각 컷 상단에 라틴 대형 카피(GDD 8.4.4 스토어 에셋 규칙).

| # | 화면 | 지정 레벨/상태 | 카피(예시) | 의도 |
|---|---|---|---|---|
| 1 | 인게임 플레이 | L017(서리 룬 첫 등장) — 물이 얼어 쌓이는 순간 | "FREEZE TO BUILD" | 시그니처 창발(얼려 짓기) |
| 2 | 인게임 플레이 | L034~040 챕터3(화염 룬·증기 상승) | "MELT. BOIL. RISE." | 상전이 사이클 |
| 3 | 클리어 화면 | 별 3개 스탬프 + 잉크 게이지 | "MASTER THE FLOW" | 별점 재도전 |
| 4 | 레벨 선택 | 챕터2 알베도(은백) 그리드 | "77 TRIALS" | 볼륨·진행 |
| 5 | 인게임 플레이 | 챕터4 루베도(진홍) — 용암+물 반응 | "TRANSMUTE" | 후반 스펙터클 |
| 6 | 타이틀 | 골드 플라스크 라인아트 | "PHILOSOPHER'S INK" | 브랜드 |

- 촬영은 **디버그 오버레이 OFF, 온보딩 문구 노출 상태** 1컷 포함 권장.
- App Store: 6.5"·6.9" 필수 사이즈. Play: 폰 최소 2컷 + 피처 그래픽(1024×500) 별도.

### 3.6 심사 주의점
- **광고 SDK 사전 고지**: 심사 노트에 "Google AdMob 리워드 광고(힌트)·전면 광고(레벨 간) 사용, IAP: 광고 제거 단품" 명기.
- **원작 언급 0**: 설명·스크린샷·프로모 영상 어디에도 레퍼런스 타이틀명 금지(GDD 13).
- **IAP 메타데이터**: "광고 제거"는 비소모성(non-consumable). App Store Connect·Play Console에 상품 등록 + 심사용 설명 필요(shell-m6 IAP 통합 후).
- **개인정보 처리방침 URL**: 광고 통합 시 필수(§2.7) — 제출 전 호스팅 URL 준비.

---

## 출시 차단 항목 (P0/P1)

전부 설정/정책 레이어. 게임 로직·테스트는 결함 없음(analyze 0 / test 318 통과).
**2026-07-20 갱신: shell-m6가 4건 조치 완료 → qa-m6 회귀 재검 통과(실파일 확인). 잔여 2건.**

1. **[P1 · 해결됨✓]** 세로 고정 — `lib/main.dart` `setPreferredOrientations([portraitUp, portraitDown])` 확인.
   iOS Info.plist `UISupportedInterfaceOrientations`=Portrait 단독(가로 제거), AndroidManifest `screenOrientation="portrait"` 확인.
2. **[P1 · 미해결]** 릴리스 서명 미구성 — `android/app/build.gradle.kts` release가 debug 키 사용(TODO).
   Play 업로드 차단. 조치: 업로드 키스토어 생성·서명 구성. **소유: 사용자(키 관리) — 코드 밖 항목.**
3. **[P1 · 해결됨✓]** 수출 규정 — Info.plist `ITSAppUsesNonExemptEncryption`=`false` 확인.
4. **[P1 · 해결됨✓]** AdMob App ID — iOS `GADApplicationIdentifier`+`SKAdNetworkItems`, Android `APPLICATION_ID`
   meta-data 배선 확인. **⚠ 잔여 프리런칭 조치**: 현재 값이 Google 공개 **테스트** App ID
   (`ca-app-pub-3940256099942544~...`) — 스토어 제출 전 **실제 프로덕션 App ID·광고 단위 ID로 교체 필수**
   (테스트 ID 채로 출시하면 정책 위반·수익 0). **소유: shell-m6 / 사용자(AdMob 콘솔).**
5. **[P2 · 해결됨✓]** 런처 라벨 — Android `android:label`="현자의 잉크", iOS `CFBundleDisplayName`="Philosopher's Ink" 확인.

### 잔여 프리런칭 조치 요약 (코드 밖 / 사용자 소유)
- 릴리스 업로드 키스토어 서명(#2 위).
- AdMob 테스트 ID → 프로덕션 ID 교체(#4 위).
- 개인정보 처리방침 URL 호스팅 + Play 데이터 안전/App Store 앱 개인정보 신고(광고 IDFA/AAID 수집, §2.7).
- ATT(`NSUserTrackingUsageDescription`) — 개인화 광고 활성화 시 추가(현재 이연).
- 실기기 60fps 프로파일 + 기준 기기 선정.
- 출시 보류 레벨 7개 사람 실플레이 검증.

### 사람 실플레이 검증 전 출시 보류 레벨 (7개)
**011 · 043 · 047 · 048 · 050 · 054 · 065** — 솔버 한계로 자동 클리어 가능성 미검증(치즈 봉쇄는 실측 확정).
직접 플레이로만 해 존재 확인 가능. **소유: 사용자(인간 태스크).** 근거: `level_lab_audit_20260718.md`,
메모리 `pile-spread-zero-ink-cheese`(2026-07-19 갱신).

### 기준 미정의 / 실기기 필요 (판정 보류)
- 실기기 60fps 프로파일·기준 기기 선정(중가 Android 1 + 구형 iPhone 1) — 사용자 실기기 필요.
- 전체 진행 초기화(별점 wipe) 기능 — GDD 미요구, 출시 필수 아님. 정책 결정 대기.
