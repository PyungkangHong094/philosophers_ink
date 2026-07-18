# 레벨 랩 L1 — 스트로크 탐색 솔버 리포트 (2026-07-18)

SSOT: `docs/LEVEL_LAB.md` §1(L1)·§2(실행)·§3(게이트). 담당: lab-l1.

## 1. 설계 요약

차곡의 상태공간 BFS 솔버를 **스트로크 프리미티브 탐색**으로 이식했다. 시뮬 코어가 결정적·순수
Dart라 오프라인 대량 롤아웃이 가능하다는 전제를 그대로 활용한다.

### 해 후보 인코딩 (`tool/level_lab/src/candidate.dart`)
- `StrokePrimitive` = 잉크종류 + 시작·끝 격자 좌표. `Candidate` = 선분 k개(k≤4) + 중력 반전 탭 틱 목록.
- 중력 반전 버튼 탭을 탐색 변수로 포함(탭 틱 목록). 순차 충전 레벨(L011)을 위해 후반 틱까지 후보.

### 탐색기 (`tool/level_lab/src/solver.dart`)
1. **빈 후보 프로브**: 잉크 0(무-스트로크) 롤아웃 1회 — 입자 더미 확산만으로 클리어되는 레벨을 즉시 확정.
2. **(a) 편향 무작위 샘플링**: 방향 램프(소스 열→플라스크 중심), 자유 선분, 짧은 편향판, 그리고
   다중 플라스크용 **커버올**(플라스크마다 전용 램프 배정) 모드를 격자 스냅으로 샘플.
3. **(b) 적합도 언덕오르기 정련**: 이진 승패가 아니라 **플라스크 진행 합(fitness)** 으로 근접해를
   상위 풀에 모으고, 좌표 섭동·선분 축소·선분 제거·중력 탭 조정으로 언덕오르기(평지 드리프트 허용).
   희소 보상(다중 플라스크·중력 순차)에서 이게 결정적 — [25,25,0] 근접해를 [25,25,25]로 민다.
- 각 후보는 헤드리스 롤아웃(`rollout.dart`)으로 T틱 승리 판정. 산출: solvable / min_ink / effort(첫 해까지
  롤아웃 수) / 상위 N개 해 아카이브(JSON).
- **결정성**: `DeterministicRng(seed)` 단일 인스턴스에서만 무작위 → `--seed` 고정 시 재실행 완전 동일
  (유닛 테스트로 고정).

### lib 최소 훅
- **`lib/gameplay/headless_session.dart` (신설, 순수 Dart)** — 유일한 lib 추가.
  `LevelSession`은 `InkController`(ChangeNotifier)를 소유해 `package:flutter/foundation`을 끌어와
  순수 CLI에서 컴파일 불가. `HeadlessSession`은 GameState+FlaskSystem+InkBudget를 직접 조립(판정·틱·
  재시작·부분 배치 cap 청구를 LevelSession과 동일 규칙으로)하되 flutter 무의존. **lib/sim 무수정.**

### 실행 형태 (`docs/LEVEL_LAB.md` §2)
```
dart run tool/level_lab/solve.dart --level assets/levels/level_007.json   # 단일
dart run tool/level_lab/sweep.dart --chapter 1                            # 챕터 일괄(Isolate 병렬)
dart run tool/level_lab/sweep.dart --all --out tool/level_lab/out
# 옵션: --seed --rollouts --refine --tick-cap --stall --max-strokes --concurrency
```
- 성능: 시뮬 틱 ≈0.7ms(160×320 그리드). sweep은 레벨 단위 Isolate 풀 병렬(기본 = 코어 수).
  단일 레벨 대량 롤아웃은 수 분대. AOT(`dart compile exe`)는 ~1.3배.

## 2. 챕터 1 게이트 결과

`sweep --chapter 1` (석필 + 중력 반전만). **게이트 통과: 11/11 solvable.**

| 레벨 | solvable | min_ink | effort(첫 해까지 롤아웃) | 비고 |
|---|---|---|---|---|
| 001~006, 008~010 (9개) | ✅ | **0** | 1 (빈 후보 즉시) | 잉크 0 치즈 — 아래 §3 |
| 007 삼중주 | ✅ | 221 / 예산 340 (여유율 154%) | 357 | 단일 장선 해 발견 |
| 011 ◈ 하소 | ✅ | 73 | 155 | 중력 반전 탭 포함 해 |

- **min_ink 단위 확정**: 로울아웃에서 실제 배치·차감된 잉크 총량 = `ink_budget`과 동일 단위(셀).
  007의 사전 수동 추정 "[25,25,25]≈75"는 선분 *길이* 단위였고, 래스터라이즈 굵기 반영 시
  차감 셀수와 정합 — **단위 불일치 없음**. L3 예산 카빙의 근거로 사용 가능.
- 잉크 0 목록에 **002가 추가**됨(사전 프로브에서는 지형 스캔만으로 스트로크 필요로 예측했으나,
  스윕의 긴 롤아웃에서 더미 확산이 결국 플라스크에 도달) — 최종 9/11.

## 3. 핵심 발견

- **잉크 0 치즈(입자 더미 확산)**: 챕터 1의 **9/11 레벨(001~006·008~010)**은 스트로크
  없이도 클리어된다(PRIMA가 쌓여 45° 더미로 확산되어 플라스크에 착수; 002도 장시간 확산으로 도달).
  star_thresholds가 잉크 기준이라 이 레벨들은 "기다리면 3성"이 성립 — **별점/밸런스 재검토 필요**
  (level-designer·qa 통지 대상). 진짜 스트로크가 필요한 챕터 1 레벨은 **007·011**뿐.
- 그래서 min_ink는 8개 레벨에서 ≈0으로 수렴 — L3 예산 카빙은 이들에 대해 사람 실플레이 min_ink 또는
  시간 지표를 별도로 써야 한다(솔버 min_ink를 그대로 예산 근거로 쓰면 예산이 0에 붕괴).

## 4. lib 훅 추가 목록
- `lib/gameplay/headless_session.dart` (신설, 순수 Dart 헤드리스 세션) — 유일한 lib 변경. lib/sim 무수정.

## 5. 테스트
- `test/level_lab/candidate_test.dart` — 프리미티브/후보 JSON 왕복·동등성(5).
- `test/level_lab/solver_test.dart` — 레벨 001 자동 해 발견·시드 결정성(3).
- `test/gameplay/headless_session_test.dart` — reset 3회 동일·부분 배치 cap·숨김 잉크·중력(4).
- 회귀: 기존 전체 스위트 통과(230 passed).

## 6. 미해결 이슈 / 후속
- CLI(`dart run`)가 flutter 무의존으로 동작 확인(HeadlessSession 경로). 앱 빌드 미포함.
- L2(메트릭)·L3(카빙)·L4(감사)는 후속 태스크. min_ink 0 수렴 레벨의 예산 근거는 L3에서 재논의.
