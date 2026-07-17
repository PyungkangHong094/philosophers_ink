# 현자의 잉크 (Philosopher's Ink)

Flutter 상전이 물리 퍼즐 게임. 설계 SSOT: `docs/PHILOSOPHERS_INK_DESIGN.md` + `docs/PHILOSOPHERS_INK_LEVELS.md`.
설계 변경은 문서에 먼저 반영한 뒤 구현한다.

## 빌드 환경 (이 PC — macOS)

- 2026-07-18 윈도우 PC → 맥으로 이전 완료. Flutter SDK: `~/develop/flutter` (3.44.6 stable).
- 구 윈도우용 env 오버라이드(`PUB_CACHE=C:\pub-cache` 등)는 `.claude/settings.json`에서 제거됨 — 다시 넣지 말 것 (맥에서 pub 경로가 깨져 native assets 빌드 실패).
- Xcode 26.1 / Android SDK 36 설치됨 — iOS·Android·macOS·웹 타깃 모두 가능.

## 하네스: Philosopher Ink 게임 개발

**목표:** GDD 기반 77레벨 상전이 퍼즐 게임을 마일스톤(M0~M6) 단위로 구현·검증·출시 준비.

**트리거:** 이 게임의 구현·수정·확장·QA·레벨 제작·마일스톤 진행 요청 시 `philosopher-ink-dev`
스킬을 사용하라. 단순 질문·문서 열람은 직접 응답 가능.

**변경 이력:**
| 날짜 | 변경 내용 | 대상 | 사유 |
|------|----------|------|------|
| 2026-07-16 | 초기 구성 (에이전트 5종 + 스킬 5종 + 오케스트레이터) | 전체 | - |
