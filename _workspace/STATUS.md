# 개발 진행 원장 (STATUS)

오케스트레이터(`philosopher-ink-dev`)가 매 마일스톤 완료 시 갱신한다.

## 현재 상태

- 마일스톤: **M4 완료 — 게이트 GO** (P0·P1 결함 0, `_workspace/qa_m4_gate_20260718.md`)
- 마지막 갱신: 2026-07-18
- 환경: 2026-07-18부로 윈도우 PC → 맥 이전 (Flutter 3.44.6, 테스트 전체 통과 확인)

## 완료 이력

| 날짜 | 항목 | 비고 |
|---|---|---|
| 2026-07-16 | 하네스 구축 (에이전트 5 + 스킬 6) | 초기 구성 |
| 2026-07-16 | 설계 문서 docs/ 통합 | GDD·LEVELS·목업·디자인 레퍼런스 4종 |
| 2026-07-16 | **M0 시뮬 스파이크** — sim 코어(그리드·물질·입자규칙·RNG)+렌더 파이프라인+석필 드로잉+데모 씬, 테스트 18/18 | 틱 0.27~0.49ms(예산 3ms), 결정성 3회 동일. QA GO |
| 2026-07-16 | **M1 상전이** — WATER/ICE/STEAM 3상, 화염·서리 룬 확률 전이, 잉크 3종 예산(부분 cap, 미반환, 예산0 숨김), HUD 배선. 테스트 61개 (tryCharge 제거 후 재검증 GO) | 액체 최악 0.94~1.35ms(예산 3ms), cap 모델 GDD 4.2 명문화. 통합 QA GO + 재검증 애드덤 |

| 2026-07-16 | **M2 게임화** — 플라스크 판정 4종(착수 소비)·별점·LevelSession, 레벨 JSON 로더/검증기/직렬화(왕복 무손실), 인앱 에디터(디버그), 코어 루프 완주. 테스트 115개 | 통합 결정성(이벤트 로그 포함 해시 3회 동일), 통합 틱 0.26ms. 게이트 QA GO |
| 2026-07-18 | 맥 이전 + 패키지 선별 — 윈도우 env 제거, animations 추가 (`package_curation_20260718.md`) | 광고·IAP는 M6 시점 설치 |
| 2026-07-18 | **M4 콘텐츠 1** — 챕터 1–2 레벨 33개(001~033, 팬아웃 3인, 해금 위반 0·설계표 D값 전수 일치) + 셸 1차(GDD 8.4 토큰, 화면 5종, 잉크 플러드 전환, 정식 HUD, 메타 영속화, main.dart=InkApp, 에디터 kDebugMode 가드). loader_test 스모크 루프 전환. 테스트 180개 | iOS 디버그 빌드 성공(141.8s). macOS 대상 미구성(no-op). 게이트 QA GO (`qa_m4_gate_20260718.md`) |
| 2026-07-18 | **M3 기믹** — 5종 완성: 변성 게이트·중력 반전(Rules.gravitySign 미러링)·포탈·재/순수(ashRatio)·온도 존(로드맵 4종 + GDD 6장 정합 위해 온도 존 추가). 레벨 JSON 기믹 스키마·로더·검증기·gimmick_builder → GameState 주입, 중력 토글 gravityLog 결정성 계약. 테스트 161개 | 기믹 5종 활성 최악 틱 0.87~0.99ms(예산 3ms), 결정성 3회 동일. 게이트 QA GO + P2 2건 반영 (`qa_m3_gate_20260718.md`) |

## 백로그

- optimal_ink 전량 설계 추정치 — 플레이테스트 실측 후 승격 + star_thresholds 재산정 (33레벨 공통)
- 손 플레이테스트(클리어 가능성 실증) — 인간 태스크
- 별점 누적 보너스 레벨 해금(GDD 7.1) 미구현 → M5+
- qa-m4 P2: 작업 레벨 ◈ 표시 정책 / L16 teaches=[] / ProgressStore prefs 왕복 통합 테스트 / debug_hud 사장 코드 정리 / 클리어 골드 3요소
- 에디터 파일쓰기 path_provider 바인딩 + 기믹 저작 UI
- macOS 데스크톱 대상 미구성 (`flutter create --platforms=macos` 필요 시)

## 보류 항목

- Android 실기기 60fps 프로파일 — 툴체인 부재 (설치 후 재계측). 순수 Dart 벤치로 대체 검증됨.
- 개발자 모드 미설정 — 네이티브 플러그인 심링크로 flutter test 우회 필요 (사용자 조치 대기)

## 팀 규약 (QA 권고 반영)

- 플러그인 워크어라운드 원복은 3파일 전부: `git checkout -- pubspec.yaml pubspec.lock windows/flutter/generated_plugins.cmake` (pub get은 cmake를 못 되돌림)
- 튜닝 파라미터(constants.dart): pHeat/pCold=0.12, liquidDispersion=4, gasDispersion=3, iceSlipChance=0.45 — M1 체감 튜닝 대상

## 다음 단계

- M5 콘텐츠 2: LAVA·STONE·용암+물 반응(sim — 물질 테이블만 존재, 규칙 미구현) + 사운드(flutter_soloud) + 챕터 3–4 레벨 44개 + 폴리시
