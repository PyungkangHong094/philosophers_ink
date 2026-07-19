<p align="center">
  <img src="assets/icon/app_icon.png" alt="현자의 잉크" width="160">
</p>

<h1 align="center">현자의 잉크 (Philosopher's Ink)</h1>

<p align="center">
쏟아지는 원소를 마법 잉크 선 하나로 녹이고, 얼리고, 증발시켜 플라스크를 채우는<br>
<b>상전이 물리 퍼즐</b> — 연금술사의 대업(Magnum Opus) 77레벨
</p>

---

## 게임

- **장르**: 드로잉 + falling-sand 물리 퍼즐 (iOS / Android, Flutter, 세로 고정)
- **조작**: 손가락으로 선을 긋는다. 석필은 벽이 되고, 화염 룬은 녹이고, 서리 룬은 얼린다
- **핵심 시스템**: 물질 11종 · 3상(고체/액체/기체) 상전이 · 용암+물 반응 · 기믹 5종
  (변성 게이트 · 중력 반전 · 포탈 · 온도 존 · 재 방출구)
- **진행**: 연금술 대업 4챕터(니그레도→알베도→키트리니타스→루베도) × 77레벨,
  11레벨마다 7대 작업(OPERATIO) 종합시험
- **규칙**: 제한 시간 카운트다운, 개방형 비커(위 입구로만 수용·가득 차면 넘침),
  잉크를 아낄수록 별(★~★★★)이 오른다

## 실행

```bash
flutter pub get
flutter run                     # 연결된 기기/시뮬레이터
flutter run -t lib/main_dev.dart  # 개발용: 레벨 1 직행 하네스
flutter test                    # 테스트 (352개)
```

- Flutter 3.44+ / Dart 3.12+. 광고·IAP는 디버그/시뮬레이터에서 자동 스텁.

## 아키텍처

게임 엔진 없이 **순수 Dart 시뮬 코어 + CustomPainter 직접 렌더링**.

| 디렉토리 | 내용 |
|---|---|
| `lib/sim` `lib/core` `lib/render` | falling-sand 셀룰러 오토마타(160×320, 틱 ~1ms), 결정성 RNG, 둥근 잉크 방울 포인트 렌더 |
| `lib/gameplay` `lib/level` | 잉크 예산, 플라스크 판정, 별점, 레벨 JSON 로더/검증기/직렬화, 헤드리스 세션 |
| `lib/ui` `lib/meta` | 셸(트루 블랙+골드), 온보딩, HUD, 진행/해금 영속화 |
| `lib/audio` | flutter_soloud 절차 합성 SFX (변주·착수 피치 램프·상전이 반응음) |
| `lib/monetize` | 광고(전면·리워드 힌트)·IAP 추상화 + 스텁 |
| `assets/levels` | 레벨 JSON 77개 (힌트 스트로크 포함) |
| `tool/level_lab` | **레벨 랩** — 자동 솔버·치즈 프로브·힌트 베이크 파이프라인 |

### 레벨 랩 (Level Lab)

레벨 품질을 기계로 보증하는 파이프라인: **생성 → 솔버 검증 → 난이도 정량화 → 카빙 → 분포 감사**.

```bash
dart run tool/level_lab/solve.dart --level assets/levels/level_001.json   # 단일 솔브
dart run tool/level_lab/sweep.dart --all                                  # 전수 스윕
dart run tool/level_lab/bake_hints.dart                                   # 솔버 해 → 힌트 베이크
```

- 무노력 클리어(치즈) 자동 색출 — 45레벨 발견·봉쇄 이력
- 별점 임계를 솔버 실측 최소 잉크로 승격
- 힌트는 "실제로 클리어되는 해"만 베이크 (거짓말 방지 재생 검증)

## 문서 (SSOT)

| 문서 | 내용 |
|---|---|
| `docs/PHILOSOPHERS_INK_DESIGN.md` | 게임 디자인 문서 (GDD) — 단일 진실 원천 |
| `docs/PHILOSOPHERS_INK_LEVELS.md` | 77레벨 설계도 (난이도 모델·별점 공식·레벨별 명세) |
| `docs/LEVEL_LAB.md` | 레벨 랩 파이프라인 설계 |
| `_workspace/STATUS.md` | 개발 진행 원장 (마일스톤 M0~M6 이력) |
| `_workspace/m6_release_checklist_20260720.md` | 출시 체크리스트·스토어 정책 가이드·설명문 초안 |

## 상태

- **M0~M6 전 마일스톤 코드 계층 완료** — 테스트 352개, analyze 0, iOS/Android 빌드 확인
- 출시 잔여: 스토어 콘솔 작업(AdMob 실 ID · IAP 상품 등록 · 서명 키 · 개인정보 신고),
  실기기 프로파일, 고난도 7레벨 사람 검증

---

*설계 변경은 반드시 GDD에 먼저 반영한 뒤 구현한다.*
