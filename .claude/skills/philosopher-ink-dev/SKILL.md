---
name: philosopher-ink-dev
description: 현자의 잉크(Philosopher's Ink) Flutter 게임 개발 오케스트레이터. 마일스톤(M0 시뮬 스파이크 ~ M6 출시 준비) 실행, 기능 구현, 레벨 제작, 셸 UI 구축, QA를 에이전트 팀으로 조율한다. "게임 만들어/개발 진행/M0 시작/다음 마일스톤/레벨 만들어/화면 구현/버그 수정/다시 실행/재실행/이어서/보완/업데이트" 등 이 게임의 구현·수정·확장 요청 전부에 반드시 이 스킬을 사용할 것. 단순 질문·문서 열람은 직접 응답 가능.
---

# 현자의 잉크 개발 오케스트레이터

프로젝트 SSOT: `docs/PHILOSOPHERS_INK_DESIGN.md` (GDD) + `docs/PHILOSOPHERS_INK_LEVELS.md`.
설계 변경은 문서에 먼저 반영 후 구현한다 (GDD 서문의 원칙).

## 팀 구성

| 에이전트 | 소유 영역 | 전용 스킬 |
|---|---|---|
| sim-engineer | lib/sim, render, core | ink-sim-core |
| gameplay-engineer | lib/gameplay, level | ink-gameplay-systems |
| shell-ui-engineer | lib/ui, meta | ink-shell-design |
| level-designer | assets/levels | ink-level-authoring |
| game-qa | test, _workspace/qa | ink-qa-protocol |

- 모든 Agent 호출에 `model: "opus"` 명시. 에이전트 프롬프트에 "전용 스킬을 먼저 로드하라"를 포함한다.
- 소유권 경계: 타 에이전트 영역의 코드는 수정 요청 메시지로 해결, 직접 수정 금지.

## Phase 0: 컨텍스트 확인 (매 실행 시작 시)

1. `lib/` 존재 여부·`_workspace/` 확인 → 실행 모드 결정:
   - lib 미존재 → **초기 실행** (M0부터)
   - 존재 + 부분 수정 요청 → **부분 재실행** (해당 소유 에이전트만 호출)
   - 존재 + 새 마일스톤 요청 → **증분 실행** (아래 마일스톤 로드맵의 다음 단계)
2. `_workspace/STATUS.md`에서 마지막 완료 지점을 읽는다 (없으면 생성).
3. git 저장소가 아니면 `git init` 후 시작 (마일스톤 단위 커밋 권장).

## 마일스톤 로드맵 (GDD 11장) — 실행 모드 하이브리드

| 단계 | 내용 | 실행 모드 | 투입 에이전트 |
|---|---|---|---|
| M0 | 시뮬 스파이크: PRIMA 낙하 + 석필 드로잉 60fps. **go/no-go 게이트** | 서브 (단독) | sim-engineer → game-qa |
| M1 | 상전이: WATER 3상 + 화염·서리 + 잉크 예산 | 팀 | sim + gameplay + qa |
| M2 | 게임화: 플라스크·별점·레벨 로더·인앱 에디터 | 팀 | gameplay + sim + qa |
| M3 | 기믹 4종 + 재/순수 | 팀 | gameplay + sim + qa |
| M4 | 콘텐츠 1: 챕터 1–2 (33레벨) + 셸 1차 | 하이브리드: 레벨은 팬아웃 서브, 셸은 팀 | level-designer(팬아웃) + shell-ui + qa |
| M5 | 콘텐츠 2: 사운드 + 챕터 3–4 + 폴리시 | 하이브리드 | 전원 |
| M6 | 출시 준비: 광고·IAP·스토어 에셋 | 팀 | shell-ui + qa |

- **core loop first (GDD 11장)**: M2까지 폴리시 금지. 셸 UI 본격 투입은 M4부터
  (그 전 임시 UI는 최소한의 디버그 셸).
- M0은 게이트다: game-qa의 성능 실측 PASS 없이 M1 진행 금지. 미달 시 GDD 13장 대응
  (그리드 축소 → Isolate) 후 재측정.
- 각 마일스톤 완료 시: qa 검증 → `_workspace/STATUS.md` 갱신 → git 커밋 → 사용자 보고.

## 데이터 전달 프로토콜

- **태스크 기반** (조율): TaskCreate로 마일스톤 내 작업 분해, 의존관계 설정.
- **파일 기반** (산출물): 코드는 소유 디렉토리에, 중간 리포트는 `_workspace/`에
  `{phase}_{agent}_{artifact}.md` 규칙. `_workspace/STATUS.md`가 마일스톤 진행 원장.
- **메시지 기반** (실시간): API 계약 변경·결함 통지는 SendMessage.

## 점진적 QA 규칙

모듈 완성 직후 game-qa를 호출한다 — 마일스톤 말미 일괄 QA 금지.
qa의 P0 결함은 다른 작업을 멈추고 우선 해소한다.

## 에러 핸들링

- 에이전트 작업 실패: 1회 재시도(실패 컨텍스트 전달), 재실패 시 리더가 원인 분석 후
  작업을 쪼개거나 사용자에게 보고. 결과 없이 다음 단계로 넘어가지 않는다 (코드는 의존적이므로).
- 설계 문서 충돌: GDD > LEVELS.md > 목업. 충돌 발견 시 문서 수정 제안을 사용자에게 보고.
- 빌드 깨짐 상태로 팀 작업 종료 금지 — `dart analyze` 클린이 각 Phase 종료 조건.

## 후속 작업 매핑

| 요청 유형 | 처리 |
|---|---|
| "레벨 N 수정/밸런스" | level-designer 단독 (ink-level-authoring의 튜닝 순서) |
| "화면/디자인 수정" | shell-ui-engineer 단독 |
| "버그" | game-qa 재현 → 소유 에이전트 수정 → qa 회귀 확인 |
| "성능" | sim-engineer 실측 → 대응 |
| "다음 마일스톤/이어서" | Phase 0 → 로드맵 다음 단계 |

## 테스트 시나리오

1. **정상 흐름 (M0)**: 사용자 "M0 시작해줘" → Phase 0 (초기 실행 판정) → sim-engineer가
   ink-sim-core 로드 후 grid/materials/rules/painter 구현 + PRIMA 낙하 데모 → game-qa가
   결정성 테스트 + 성능 계측 → PASS → STATUS.md 갱신 → 커밋 → "M0 완료, go" 보고.
2. **에러 흐름 (M0 성능 미달)**: qa가 시뮬 5ms 실측 FAIL 보고 → 리더가 M1 진행 차단 →
   sim-engineer에게 그리드 128×256 축소 지시 → 재측정 PASS → 진행. 재실패 시 Isolate 이전
   검토를 사용자에게 보고 (go/no-go는 사용자 결정).
3. **부분 재실행**: 사용자 "레벨 17 너무 어려워" → Phase 0 (부분 재실행 판정) →
   level-designer 단독, 튜닝 순서(여유율 먼저) 적용 → 로더 검증 → 보고.
