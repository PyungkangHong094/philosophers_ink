# QA: M2 gameplay sim-독립 모듈 (점진 1차) — 2026-07-16

검증자: game-qa / 대상: gameplay-engineer 소유 (lib/gameplay/{flask,star_rating}, lib/level/*)
범위: 플라스크 판정 · 별점 · 레벨 로더/검증기/직렬화/에디터. **sim↔gameplay 통합(착수 이벤트
전체 루프·방출구 확장·main 배선)은 이번 제외** — sim #10 진행 중, 랜딩 후 2차로(gameplay-engineer·
리더 합의). 판정 기준: GDD 5.1, LEVELS.md 4장, GDD 10.6, ink-qa-protocol.

## 요약: PASS 8 / FAIL 0 / 권고 1 / 기준미정의 0

**M2 gameplay 모듈 점진 게이트: GO (차단 결함 없음).**

| # | 항목 | 결과 |
|---|------|------|
| 1 | dart analyze (gameplay/level) 이슈 0 | PASS |
| 2 | flutter test (gameplay/level) 36/36 | PASS |
| 3 | 플라스크 판정 4종 ↔ GDD 5.1 | PASS |
| 4 | 별점 공식 ↔ LEVELS 4장 | PASS |
| 5 | 로더/검증기 명시적 에러 (조용한 스킵 금지) | PASS |
| 6 | 에디터 export→load 라운드트립 무손실 | PASS |
| 7 | 매직 넘버 (밸런스 = 상수/JSON) | PASS |
| 8 | 픽스처 3자 스키마 정합 (loader↔JSON↔model) | PASS |

## 상세

### [1] dart analyze — PASS
`dart analyze lib/gameplay lib/level test/gameplay test/level` → "No issues found!".
(전체 analyze는 sim #10 진행 중 game_state·emitter 미완성이라 대상 한정. sim 코어는 sim 소유 2차.)

### [2] flutter test 36/36 — PASS
`flutter test test/level test/gameplay/flask_test.dart test/gameplay/star_rating_test.dart` 전부 통과
(flask 9 + star 5 + loader 13 + serializer_roundtrip 3 + editor_document 5 + 기타 = 36).
gameplay-engineer 보고는 31개였으나 실측 36개 전부 통과(카운트 차이는 무해).
주: 현재 pubspec은 gameplay-engineer의 플러그인 임시제거 상태(진행 중)라 그대로 두고 그 위에서 실행.
**pubspec은 내가 건드리지 않았다** — gameplay-engineer가 마지막에 원복 예정(리더 지침대로 "진행 중"
처리, 결함 아님). 전체 `flutter test`는 sim #10 미완성으로 실패하므로 gameplay 3경로만 실행.

### [3] 플라스크 판정 4종 ↔ GDD 5.1 — PASS
GDD 5.1 표와 flask.dart 로직·테스트를 1:1 대조:
- **숫자만(무조건)**: 어떤 물질이든 카운트 + 소비. ✓
- **물질 지정**: 지정 물질만 카운트, 타 물질은 통과·소멸(grid.set empty). ✓
- **상태 지정**: 매칭 상만 카운트, **비매칭 상 셀은 소비 안 하고 남겨 전이 유도**(증기→응결→물).
  이 핵심 뉘앙스가 코드(flask.dart:119-123 `else if (s.state == null)`)와 테스트("증기는 그 자리에
  남아 응결 대기") 양쪽에 정확히 반영. ✓
- **순수(❗)**: ASH 1개라도 혼입 시 contaminated + 재 제거 + isFailed → 클리어 불가(재시작 유도). ✓
클리어 = 전 플라스크 goal 충족 && 실패 없음. reset이 카운트·오염 복원. 스캔 순서 고정(fi→y→x)이라
같은 그리드 → 같은 판정(결정성). 착수 이벤트(SettleEvent) 좌표·물질·상 포함.

### [4] 별점 공식 ↔ LEVELS 4장 — PASS
LEVELS 4장:85 "★★★ ≤ 최적해×1.15 / ★★ ≤ ×1.6 / ★ = 클리어" 부합.
- **부동소수 함정 회피**: 배율을 정수 퍼센트(kThreeStarPercent=115, kTwoStarPercent=160)로 두고
  `optimalTotal * 퍼센트 ~/ 100`. 100×1.15가 114.999로 내림되는 float 오류 원천 차단. ✓
- 경계값 테스트: ≤115=3성 / 116=2성 / ≤160=2성 / 161=1성. ✓
- **optimal null → ★만** (미검증 레벨). ✓ 명시 임계가 파생보다 우선. ✓

### [5] 로더/검증기 명시적 에러 — PASS (독립 재현 포함)
loader는 구조 파싱 위반을 모으고, 통과 시 validateLevel이 의미 위반을 **전부 모아** LevelException으로
던진다 — 조용한 스킵 없음. 기존 loader_test 9종(비-JSON/비객체/좌표밖/정적방출/미지물질/해금3종/
미지기믹/복수위반) 통과.
**독립 재현**(리더 약속): 별도 스크립트로 불량 픽스처 14종을 직접 작성·주입 → **전 케이스 명시적
거부, 조용한 스킵 0**. 특히:
- `goal 필드 누락` → 기본값 0으로 조용히 넘어가지 않고 "goal 양수" 에러로 표면화(P1 위험 원천 차단).
- `flasks가 배열 아님`, `optimal_ink 미지 키`, `ash_ratio>1`, `total 음수`, `heat 잉크 챕터2 지급(해금)`,
  `difficulty 범위밖`, `meta 통째 문자열`(5개 문제 동시) 등 전부 LevelException.
검증 후 스크립트 삭제(작업트리 잔여 0).

### [6] 에디터 라운드트립 무손실 — PASS
serializer levelToMap 키가 loader 파싱 키와 정확히 대응. 색은 알파 FF면 #RRGGBB, 아니면 #AARRGGBB로
쓰고 로더가 양쪽 다 읽어 왕복 보존. EditorDocument.fromLevel→build(검증)→exportJson→reloadExported이
무손실(테스트: level_001/021 왕복, 직렬화 결과 재검증 통과, fromLevel 원본 불변). build/exportJson도
검증 실패 시 명시적 LevelException(조용한 저장 금지).

### [7] 매직 넘버 — PASS
- 별점 배율: star_rating.dart에 kThreeStarPercent/kTwoStarPercent 명명 상수(주석 "매직 넘버 금지 —
  여기 한 곳"). `~/ 100`은 퍼센트 나눗셈 알고리즘 상수.
- 레벨 밸런스(예산·goal·optimal·좌표)는 전부 레벨 JSON 출처(loader). 하드코딩 밸런스 리터럴 0.
- validator의 chapter 1~4·difficulty 1~10은 스키마 경계 상수(에러 메시지 자기설명적). 해금 챕터 맵은
  named const(_materialUnlockChapter 등). 밸런스 튜닝값 아님.

### [8] 픽스처 3자 정합 — PASS
loader 파싱 필드 ↔ 실제 JSON(level_001/021) ↔ Level 모델 3자 일치. 로더 테스트가 두 픽스처 실제
로드·검증 통과 확인. 챕터별 해금도 정합: level_001(ch1 PRIMA 방출/chalk 예산/무조건 플라스크),
level_021(ch2 WATER 방출/상태 플라스크 solid/frost 예산/WALL 지형).

## 권고 (비차단)
1. validator.dart의 chapter 범위(1~4)·difficulty 범위(1~10) 인라인 리터럴은 스키마 경계라 무해하나,
   LEVELS 7장 스키마와 동기화 명확성을 위해 named const로 뽑을 수 있음(선택). 밸런스값 아니라 결함 아님.

## 기준미정의 / 보류 (sim #10 랜딩 후 2차 QA)
- **sim↔gameplay 경계면**: 착수 이벤트(SettleEvent) 순서 결정성을 **전체 sim 루프**와 함께 검증
  (리더 지시: 결정성 해시에 이벤트 로그 포함). 방출구 확장(EmitterSpec rate/total/ash_ratio → sim
  emitter 계약), main.dart 배선. 이번엔 FlaskSystem 단위 스캔 결정성(고정 순서)만 확인.
- **M2 게이트 최종**: GDD 14장 "코어 루프 시작→플레이→클리어/재시작→결과 완주" — 통합 빌드 필요.
- **성능·결정성 회귀**: M2 씬(플라스크 판정 패스 추가) A/B/C 벤치 + 상전이 씬 해시(0x21374561) —
  통합 후 재측정.
- test/sim/{emitter_test,phase_test}.dart는 sim #10 산출물 — sim 2차 QA 대상.

## 회귀 확인 (이전 리포트 대비)
- M1 gameplay(잉크 예산·컨트롤러)는 이번 변경 없음. flask/star/level은 신규 모듈 — 이 리포트가 기준선.
- InkType/Material enum·materials 테이블을 level_model이 재수출·역인덱싱(materialFromName)하는데
  M0 [7] 원리(enum index 안정)와 무모순. 물질명 매핑은 kMaterialTable name 단일 소스.

## 산출물
- 리포트: _workspace/qa_m2_gameplay_20260716.md
- 독립 검증: 불량 픽스처 14종 스크립트(임시, 검증 후 삭제).
