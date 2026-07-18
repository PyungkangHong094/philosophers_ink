# M5 온보딩 리포트 (2026-07-18)

담당: shell-ui-engineer (shell-m4). 소유: `lib/ui`, `lib/meta`.
SSOT: GDD 7.2(튜토리얼 원칙 — 텍스트 최소화, 화면 내 1~2줄, 새 요소는 그것만으로 클리어되는
레벨에서 등장) + 8.4(셸 디자인) + `ink-shell-design`.

사용자 피드백(P1 UX): "처음에 뭘 해야 할지 모르겠다. 별 3개 받는 법도 모르겠다."

---

## 1. 구현 요약

| 안내 | 언제 | 어디 | 소멸 | 영속(1회성) |
|---|---|---|---|---|
| 목표 배너 | 레벨 진입 즉시 | 상단 1줄 | 3초 후 또는 첫 터치 | 아니오(매 레벨) |
| 첫 조작 가이드 | 미조작 3초 후(챕터 1) | 하단 중앙 1줄+아이콘 | 첫 스트로크/중력 사용 | 예 |
| 별점 설명 | 첫 클리어 | 클리어 화면 1줄+사용량 | — | 예(firstClear) |
| 별점 임계 | 일시정지 | 오버레이 상단 1줄 | — | 아니오(상시) |
| 게이지 힌트 | 첫 스트로크(튜토리얼) | 잉크병 잔량 숫자 강조 | 1.2초 | 예(gauge) |

- **문구 자동 생성**: 목표 배너는 `FlaskSpec`(개수/물질/상태/순수)에서 파생. 한글 목적격 조사(을/를)를
  받침 유무로 자동 부착. 물질 한글명은 셸 로컬라이즈 맵(sim은 영문 name만 보유).
- **골드 희소성**: 안내는 달성이 아니므로 무채. 예외 — 별점 임계·사용량 숫자는 골드(가치=별점).
- **reduced motion**: 첫 조작 가이드 아이콘 바브·게이지 펄스 정지. 배너 페이드만 유지(토큰 duration).
- **영속**: 1회성 안내는 `OnboardingState`(seen-key Set) → `ink.onboarding.v1` prefs. 재플레이 반복
  노출 금지. 설정 "안내 다시 보기 · 초기화"가 `reset()`으로 되돌림(스낵바 확인).

### 파일

신규: `lib/ui/onboarding/onboarding_text.dart`(순수 문구 생성), `.../onboarding_widgets.dart`
(GoalBanner·FirstOpGuide), `lib/meta/onboarding.dart`(OnboardingState).
수정: `play_screen`(타이머·가이드·게이지 배선), `clear_overlay`(별점 설명), `pause_overlay`(임계),
`ink_palette_bar`(잔량 강조 펄스, Stateful 전환), `settings_screen`(안내 다시 보기), `app`·`progress_store`
(onboarding 주입·영속), `level_select`(주입 전달).

---

## 2. 문구 목록 (사용자 톤 확인용)

**목표 배너 (조건별 자동 생성)**
- 개수만: `플라스크를 35만큼 채워라`
- 물질: `프리마를 플라스크에 35만큼 담아라`
- 상태: `물을 고체로 20만큼 담아라`
- 순수(❗): `재 없이 프리마를 플라스크에 35만큼 담아라`
- 다중 플라스크: `플라스크 2곳을 조건대로 채워라`
- (물질 한글명: 프리마·물·얼음·증기·재·용암·돌. 상태: 고체·액체·기체.)

**첫 조작 가이드**
- 스트로크(레벨 1~2): `화면에 선을 그어 길을 만들어라`
- 중력(중력 반전 레벨): `버튼으로 중력을 뒤집어라`

**별점**
- 첫 클리어 설명: `잉크를 아낄수록 별이 오른다`
- 첫 클리어 사용량: `사용 80 · ★★★ ≤ 60` (미검증 레벨은 `사용 80`)
- 일시정지 임계: `★★ ≤ 100 · ★★★ ≤ 60` (미검증 레벨은 숨김)

**설정**
- `안내 다시 보기` / `목표·조작·별점 안내를 처음처럼` / 버튼 `초기화` → 스낵바 `안내를 초기화했다`

> 톤 조정 요청 시 문구는 전부 `onboarding_text.dart`(생성)·`OnboardingCopy`(고정)·해당 위젯 한 곳에서
> 바꾸면 된다. 예: "담아라"→"모아라", "정제하라" 등 픽션 톤 강화 여지.

---

## 3. 저장 스키마 (추가)

`ink.onboarding.v1` — 본 적 있는 1회성 안내 키 리스트:
```json
["firstClear", "gauge", "stroke"]
```
키: `stroke`·`gravity`·`firstClear`·`gauge`. 설정 리셋 시 빈 리스트로.

---

## 4. 검증

- `dart analyze` (lib + test): **No issues found**.
- 신규 테스트:
  - `test/ui/onboarding_text_test.dart`: 목표 조건 4종 + 다중 + 조사(을/를) + 임계/사용량 3종.
  - `test/meta/onboarding_test.dart`: markSeenOnce 1회성·reset·onChanged·JSON 왕복 + prefs 영속 왕복.
  - `test/ui/onboarding_widget_test.dart`: 배너 노출/소멸(불투명도 0) + 첫 조작 가이드 + 일시정지 임계
    + 클리어 별점 설명/숨김 — **전부 크기 단언 포함**(getSize width/height > 0, 0×0 회귀 방지).
- 기존 셸 테스트(shell_smoke·play_lifecycle)는 `onboarding` 주입 + 온보딩 타이머 정리(dispose) 반영.
- 전체 `flutter test` 통과(러너 다수 팀 테스트 포함).

### 주의/이연

- 첫 조작 가이드는 `chapter == 1` 전용(GDD 7.2 튜토리얼 챕터). 중력 가이드는 `session.hasGravityFlip`로
  판정(레벨 JSON teaches/tags 콘텐츠는 미수정). 챕터 3~4 신규 요소 온보딩은 콘텐츠 확정 후 확장 여지.
- 목표 배너 다중 플라스크는 요약 1줄. 조건이 상이한 다중 플라스크의 상세 안내는 향후.
- `lib/main_dev.dart`(레벨 랩 팀 데브 하네스)가 InkServices/PlayScreen을 직접 구성해 API 변경으로
  깨져, `onboarding` 인자만 기계적으로 추가함(빌드 그린 유지). 소유 이관 시 확인 요망.
