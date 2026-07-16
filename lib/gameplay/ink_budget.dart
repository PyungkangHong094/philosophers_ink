/// 잉크 예산 회계 (GDD 4.2). 순수 Dart — flutter 미의존, 단위 테스트 대상.
///
/// 예산 단위 = 래스터라이즈된 셀 수 (GDD 4.2 / 10.4). 레벨별로 잉크 종류당
/// 예산을 생성자로 주입한다 (M1 데모는 하드코딩 대신 주입, M2는 레벨 JSON).
///
/// 설계 계약:
///  - 차감은 **실제 배치된 셀 수**만큼. 스트로크가 이미 찬 셀을 건너뛰면 그만큼 덜 든다.
///  - **삭제 시 미반환** — 잉크를 되돌리는 API는 존재하지 않는다 (신중한 드로잉 유도).
///  - 초기 예산 0인 잉크는 "숨김" 상태 ([isHidden]) — UI가 병 자체를 숨기는 근거.
///  - [reset]은 잔량을 초기 예산으로 복원 (GameState.reset과 함께 재시작 안전).
library;

import 'ink.dart';

/// 잉크 종류별 잔량을 관리하는 예산 장부.
class InkBudget {
  /// 초기 예산 (레벨이 준 총량). 게이지 분모·숨김 판정의 기준. 불변.
  final Map<InkType, int> _initial;

  /// 현재 잔량. 차감으로만 줄고, 절대 늘지 않는다 (미반환).
  final Map<InkType, int> _remaining;

  /// 잉크 종류당 예산을 주입한다. 명시하지 않은 종류는 0(숨김)으로 둔다.
  /// 음수 예산은 허용하지 않는다 (0으로 클램프).
  InkBudget({int chalk = 0, int heat = 0, int frost = 0})
      : _initial = {
          InkType.chalk: chalk < 0 ? 0 : chalk,
          InkType.heat: heat < 0 ? 0 : heat,
          InkType.frost: frost < 0 ? 0 : frost,
        },
        _remaining = {
          InkType.chalk: chalk < 0 ? 0 : chalk,
          InkType.heat: heat < 0 ? 0 : heat,
          InkType.frost: frost < 0 ? 0 : frost,
        };

  /// 레벨 JSON `ink_budget` 맵({"chalk":N,...})에서 생성 (M2 로더용).
  factory InkBudget.fromMap(Map<String, dynamic> map) => InkBudget(
        chalk: (map['chalk'] as num?)?.toInt() ?? 0,
        heat: (map['heat'] as num?)?.toInt() ?? 0,
        frost: (map['frost'] as num?)?.toInt() ?? 0,
      );

  /// 이 잉크의 초기 예산(총량).
  int initial(InkType type) => _initial[type]!;

  /// 이 잉크의 현재 잔량.
  int remaining(InkType type) => _remaining[type]!;

  /// 초기 예산이 0 → 병을 숨긴다 (GDD 4.2, 튜토리얼 단순화).
  /// 잔량이 0이어도 초기 예산이 있었으면 숨기지 않는다(고갈은 [isDepleted]).
  bool isHidden(InkType type) => _initial[type]! == 0;

  /// 사용 가능했으나 잔량이 0으로 바닥난 상태 (숨김과 구분).
  bool isDepleted(InkType type) => !isHidden(type) && _remaining[type]! == 0;

  /// 게이지 채움 비율 0.0~1.0. 숨김(초기 0)이면 0.0.
  double fraction(InkType type) {
    final init = _initial[type]!;
    if (init == 0) return 0.0;
    return _remaining[type]! / init;
  }

  /// UI에 노출할 잉크 목록 — 초기 예산이 있는(숨김 아닌) 종류만, enum 순서.
  List<InkType> get visibleInks =>
      InkType.values.where((t) => !isHidden(t)).toList(growable: false);

  /// [cells]개를 청구할 여력이 있는가 (차감 없는 질의). 숨김 잉크는 항상 false.
  bool canAfford(InkType type, int cells) {
    if (cells <= 0) return true;
    if (isHidden(type)) return false;
    return cells <= _remaining[type]!;
  }

  /// 확정 청구 모델 — **부분 배치 cap** (GDD 4.2, 팀 확정 2026-07-16).
  /// 잔량 한도 내에서 최대한 차감하고 **실제 차감량**을 반환한다. 드래그 중
  /// 잔량이 소진되면 그 지점에서 선이 멈춘다(무반응 방지). 잔량은 음수가 되지
  /// 않고, [cells]<=0이면 0을 반환한다. 배치 후 실제 배치 셀 수를 사후 차감한다.
  int chargeAvailable(InkType type, int cells) {
    if (cells <= 0) return 0;
    final rem = _remaining[type]!;
    final charged = cells < rem ? cells : rem;
    _remaining[type] = rem - charged;
    return charged;
  }

  /// 잔량을 초기 예산으로 복원 (재시작 안전, GDD 10.5).
  void reset() {
    for (final type in InkType.values) {
      _remaining[type] = _initial[type]!;
    }
  }
}
