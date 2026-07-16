/// 잉크 선택 상태 + 예산을 묶는 게임플레이 컨트롤러 (GDD 4장).
///
/// [ChangeNotifier]로 HUD(debug_hud.dart)가 잔량·선택 변화를 구독한다.
/// 배치 자체는 sim(GameState 스트로크 API)이 하고, 이 컨트롤러는 "무슨 잉크로,
/// 예산이 되는가, 얼마를 차감할까"만 결정한다 — sim에 의존하지 않는다(소유권 경계).
///
/// 청구 모델은 **부분 배치 cap** 하나로 확정됐다(GDD 4.2, 팀 확정 2026-07-16):
/// 배치 전 [selectedRemaining]을 sim [extendStroke]의 maxCells 상한으로 넘겨
/// 잔량만큼만 칠하고, 반환된 실제 배치 수를 [chargePlaced]로 사후 차감한다.
/// 잔량이 소진되면 드래그 중 선이 그 지점에서 멈춘다.
library;

import 'package:flutter/foundation.dart';

import '../sim/materials.dart';
import 'ink.dart';
import 'ink_budget.dart';

class InkController extends ChangeNotifier {
  final InkBudget budget;

  InkType? _selected;

  /// 예산을 받아 첫 노출 잉크를 기본 선택한다. 노출 잉크가 없으면 선택 없음(null).
  InkController(this.budget) {
    _selected = _firstVisible();
  }

  InkType? _firstVisible() {
    final visible = budget.visibleInks;
    return visible.isEmpty ? null : visible.first;
  }

  /// 현재 선택된 잉크. 노출 잉크가 하나도 없으면 null.
  InkType? get selected => _selected;

  /// 선택된 잉크가 배치하는 물질 — sim 스트로크 API에 넘긴다. 선택 없으면 null.
  Material? get selectedMaterial => _selected?.material;

  /// HUD가 그릴 잉크 목록 (숨김 제외).
  List<InkType> get visibleInks => budget.visibleInks;

  /// 잉크 선택 변경. 숨김 잉크는 선택 불가. 실제 변경 시에만 notify.
  void select(InkType type) {
    if (budget.isHidden(type)) return;
    if (_selected == type) return;
    _selected = type;
    notifyListeners();
  }

  /// 지금 선택 잉크로 그릴 수 있는가 — 선택 있고 잔량>0. post-hoc 모델의 게이트.
  bool get canDraw {
    final s = _selected;
    return s != null && budget.remaining(s) > 0;
  }

  /// 선택 잉크의 잔량 — sim [extendStroke]의 maxCells 상한으로 넘겨 정확한
  /// (누수 없는) 세그먼트 배치를 만든다. 선택 없으면 0.
  int get selectedRemaining {
    final s = _selected;
    return s == null ? 0 : budget.remaining(s);
  }

  /// 배치 후 실제 배치 셀 수를 사후 차감(부분 배치 cap 모델). 실제 차감량 반환,
  /// 차감 시 notify. 선택 없으면 0.
  int chargePlaced(int placedCells) {
    final s = _selected;
    if (s == null) return 0;
    final charged = budget.chargeAvailable(s, placedCells);
    if (charged > 0) notifyListeners();
    return charged;
  }

  /// 재시작 안전: 예산 복원 + 선택을 첫 노출 잉크로 되돌림 (GDD 10.5).
  void reset() {
    budget.reset();
    _selected = _firstVisible();
    notifyListeners();
  }
}
