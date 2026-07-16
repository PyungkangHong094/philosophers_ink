# 개발 진행 원장 (STATUS)

오케스트레이터(`philosopher-ink-dev`)가 매 마일스톤 완료 시 갱신한다.

## 현재 상태

- 마일스톤: **M1 완료 — 게이트 GO** (통합 QA PASS 7 / FAIL 0, `_workspace/qa_m1_integration_20260716.md`)
- 마지막 갱신: 2026-07-16

## 완료 이력

| 날짜 | 항목 | 비고 |
|---|---|---|
| 2026-07-16 | 하네스 구축 (에이전트 5 + 스킬 6) | 초기 구성 |
| 2026-07-16 | 설계 문서 docs/ 통합 | GDD·LEVELS·목업·디자인 레퍼런스 4종 |
| 2026-07-16 | **M0 시뮬 스파이크** — sim 코어(그리드·물질·입자규칙·RNG)+렌더 파이프라인+석필 드로잉+데모 씬, 테스트 18/18 | 틱 0.27~0.49ms(예산 3ms), 결정성 3회 동일. QA GO |
| 2026-07-16 | **M1 상전이** — WATER/ICE/STEAM 3상, 화염·서리 룬 확률 전이, 잉크 3종 예산(부분 cap, 미반환, 예산0 숨김), HUD 배선. 테스트 62개 | 액체 최악 0.94~1.35ms(예산 3ms), cap 모델 GDD 4.2 명문화. 통합 QA GO |

## 보류 항목

- Android 실기기 60fps 프로파일 — 툴체인 부재 (설치 후 재계측). 순수 Dart 벤치로 대체 검증됨.
- 개발자 모드 미설정 — 네이티브 플러그인 심링크로 flutter test 우회 필요 (사용자 조치 대기)

## 팀 규약 (QA 권고 반영)

- 플러그인 워크어라운드 원복은 3파일 전부: `git checkout -- pubspec.yaml pubspec.lock windows/flutter/generated_plugins.cmake` (pub get은 cmake를 못 되돌림)
- 튜닝 파라미터(constants.dart): pHeat/pCold=0.12, liquidDispersion=4, gasDispersion=3, iceSlipChance=0.45 — M1 체감 튜닝 대상

## 다음 단계

- M2 게임화: 플라스크·승리조건·별점 + 레벨 로더/검증기 + 인앱 에디터(디버그) (팀 모드: gameplay 주도 + sim + qa)
