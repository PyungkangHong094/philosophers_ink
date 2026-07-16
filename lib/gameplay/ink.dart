/// 잉크 3종의 게임플레이 확장 (GDD 4.1). 순수 Dart — flutter 미의존.
///
/// [InkType] 자체와 잉크→물질 매핑([materialForInk])은 sim/materials.dart가
/// 소유하는 공유 계약이다(sim-engineer). 여기서는 재정의하지 않고 재수출하며,
/// 예산 키·라벨 등 게임플레이 계층에만 필요한 부가 정보만 확장으로 얹는다.
library;

import '../sim/materials.dart';

export '../sim/materials.dart' show InkType, materialForInk;

extension InkTypeX on InkType {
  /// 이 잉크가 그리드에 배치하는 물질 (sim 계약 [materialForInk] 위임).
  Material get material => materialForInk(this);

  /// 레벨 JSON 예산 키 (GDD 10.6 / LEVELS.md 7장).
  String get budgetKey => switch (this) {
        InkType.chalk => 'chalk',
        InkType.heat => 'heat',
        InkType.frost => 'frost',
      };

  /// 디버그 HUD 라벨 (M1 데모용, 폴리시 전).
  String get debugLabel => switch (this) {
        InkType.chalk => '석필',
        InkType.heat => '화염',
        InkType.frost => '서리',
      };
}

/// 예산 키 → InkType 역매핑 (로더가 사용, M2). 알 수 없는 키면 null.
InkType? inkTypeFromKey(String key) => switch (key) {
      'chalk' => InkType.chalk,
      'heat' => InkType.heat,
      'frost' => InkType.frost,
      _ => null,
    };
