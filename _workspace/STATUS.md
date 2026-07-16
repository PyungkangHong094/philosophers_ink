# 개발 진행 원장 (STATUS)

오케스트레이터(`philosopher-ink-dev`)가 매 마일스톤 완료 시 갱신한다.

## 현재 상태

- 마일스톤: **M2 완료 — 게이트 GO** (게이트 QA PASS 9 / FAIL 0, `_workspace/qa_m2_gate_20260716.md`)
- 마지막 갱신: 2026-07-16

## 완료 이력

| 날짜 | 항목 | 비고 |
|---|---|---|
| 2026-07-16 | 하네스 구축 (에이전트 5 + 스킬 6) | 초기 구성 |
| 2026-07-16 | 설계 문서 docs/ 통합 | GDD·LEVELS·목업·디자인 레퍼런스 4종 |
| 2026-07-16 | **M0 시뮬 스파이크** — sim 코어(그리드·물질·입자규칙·RNG)+렌더 파이프라인+석필 드로잉+데모 씬, 테스트 18/18 | 틱 0.27~0.49ms(예산 3ms), 결정성 3회 동일. QA GO |
| 2026-07-16 | **M1 상전이** — WATER/ICE/STEAM 3상, 화염·서리 룬 확률 전이, 잉크 3종 예산(부분 cap, 미반환, 예산0 숨김), HUD 배선. 테스트 61개 (tryCharge 제거 후 재검증 GO) | 액체 최악 0.94~1.35ms(예산 3ms), cap 모델 GDD 4.2 명문화. 통합 QA GO + 재검증 애드덤 |

| 2026-07-16 | **M2 게임화** — 플라스크 판정 4종(착수 소비)·별점·LevelSession, 레벨 JSON 로더/검증기/직렬화(왕복 무손실), 인앱 에디터(디버그), 코어 루프 완주. 테스트 115개 | 통합 결정성(이벤트 로그 포함 해시 3회 동일), 통합 틱 0.26ms. 게이트 QA GO |

## 백로그

- 에디터 파일쓰기 path_provider 바인딩 (현재 주입형 sink + 클립보드/콘솔 — 개발자 모드 활성화 후)
- level_player/debug_hud 디버그 UI 하드코딩 색 → M4 셸 디자인 시스템으로 대체

## 보류 항목

- Android 실기기 60fps 프로파일 — 툴체인 부재 (설치 후 재계측). 순수 Dart 벤치로 대체 검증됨.
- 개발자 모드 미설정 — 네이티브 플러그인 심링크로 flutter test 우회 필요 (사용자 조치 대기)

## 팀 규약 (QA 권고 반영)

- 플러그인 워크어라운드 원복은 3파일 전부: `git checkout -- pubspec.yaml pubspec.lock windows/flutter/generated_plugins.cmake` (pub get은 cmake를 못 되돌림)
- 튜닝 파라미터(constants.dart): pHeat/pCold=0.12, liquidDispersion=4, gasDispersion=3, iceSlipChance=0.45 — M1 체감 튜닝 대상

## 다음 단계

- M3 기믹: 변성 게이트·중력 반전·포탈·재/순수(재 방출구는 ashRatio로 선반영됨) 4종 (팀 모드: gameplay + sim + qa)
