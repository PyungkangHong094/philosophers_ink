/// 플라스크 승리 조건 판정 (GDD 5.1). 순수 Dart — flutter 미의존.
///
/// 판정은 **착수 순간**: `game.tick()` 직후 [FlaskSystem.update]를 고정 스텝으로 돌려
/// 각 플라스크 영역을 스캔한다. 매칭 셀은 카운트+소비하고, 상태 플라스크의 비매칭 상
/// 셀은 그 자리에 남겨 전이(예: 증기→응결→물)를 유도한다.
///
/// 결정성: flasks·셀 스캔 순서가 고정이라 같은 그리드 → 같은 판정.
library;

import '../sim/grid.dart';
import '../sim/materials.dart';
import '../level/level_model.dart';

/// 착수 이벤트 — 한 셀이 조건에 맞게 카운트된 순간 (M5 카운트업 사운드/UI 동기용).
class SettleEvent {
  final int flaskIndex;
  final int x;
  final int y;
  final Material material;

  /// 착수 시점의 상.
  final FlaskState? phase;

  const SettleEvent({
    required this.flaskIndex,
    required this.x,
    required this.y,
    required this.material,
    required this.phase,
  });
}

/// 플라스크 1개의 런타임 상태 (스펙 + 카운트 + 오염).
class Flask {
  final FlaskSpec spec;
  int count = 0;

  /// 순수(❗) 위반 — ASH 혼입 (GDD 5.1). 회복 불가, 재시작 유도.
  bool contaminated = false;

  Flask(this.spec);

  bool get isComplete => count >= spec.goal;

  /// 순수 오염으로 실패한 상태.
  bool get isFailed => contaminated;

  /// 0.0~1.0 진행도 (UI 게이지용).
  double get progress =>
      spec.goal <= 0 ? 1.0 : (count / spec.goal).clamp(0.0, 1.0);

  void reset() {
    count = 0;
    contaminated = false;
  }
}

/// 여러 플라스크의 판정을 묶는 시스템. 레벨 클리어/실패를 종합한다.
class FlaskSystem {
  final List<Flask> flasks;

  /// 카운트된 착수마다 호출 (없어도 됨).
  void Function(SettleEvent event)? onSettle;

  FlaskSystem(List<FlaskSpec> specs, {this.onSettle})
      : flasks = specs.map(Flask.new).toList(growable: false);

  /// 순수 오염이 하나라도 있으면 실패 (GDD 5.1 → 재시작 유도).
  bool get isFailed => flasks.any((f) => f.isFailed);

  /// 레벨 클리어 = 모든 플라스크 목표 충족 && 실패 없음.
  bool get isCleared =>
      !isFailed && flasks.every((f) => f.isComplete);

  void reset() {
    for (final f in flasks) {
      f.reset();
    }
  }

  /// 틱 후 판정. 각 플라스크 영역을 스캔해 조건 평가 → 매칭 소비 + 카운트.
  /// 그리드 변경(소비)은 [grid.set]으로 EMPTY 처리한다.
  void update(Grid grid) {
    for (var fi = 0; fi < flasks.length; fi++) {
      _updateFlask(fi, flasks[fi], grid);
    }
  }

  void _updateFlask(int fi, Flask flask, Grid grid) {
    final s = flask.spec;
    final empty = Material.empty.index;
    // 넘침 규칙 (GDD 5.1, 2026-07-19): 목표를 채운 플라스크는 더 이상 소비하지 않는다.
    // 이후 도달하는 물질은 일반 sim 물리로 그 자리에 쌓여 넘친다("다 찼다"가 물리로 읽힘).
    // 순수 오염 판정도 목표 달성 전까지만 유효(채운 뒤 넘치는 ASH는 무해)하므로,
    // 완료된 플라스크는 이 판정 패스를 통째로 건너뛴다.
    if (flask.isComplete) return;
    for (var yy = s.y; yy < s.y + s.h; yy++) {
      for (var xx = s.x; xx < s.x + s.w; xx++) {
        if (!grid.inBounds(xx, yy)) continue;
        final id = grid.get(xx, yy);
        if (id == empty) continue;

        // 정적 잉크(석필 WALL·화염/서리 룬 선)·벽은 플라스크 내용물이 아니다 (GDD 5.1 판정
        // 각주). "어떤 물질이든"은 방출·낙하한 동적 물질(입자/액체/기체)을 뜻한다 —
        // 플라스크 영역에 직접 그은 잉크를 내용물로 세던 익스플로잇을 차단한다. 소비하지
        // 않고 그대로 남긴다(그린 선 유지). LAVA→STONE 등 동적 반응 산출물은 입자라 카운트 유지.
        if (categoryOf(id) == MaterialCategory.staticSolid) continue;

        // 순수 위반: ASH 혼입 → 오염 + 재 제거 (카운트 안 함). 목표 달성 전만 유효(위 조기 반환).
        if (s.pure && id == Material.ash.index) {
          flask.contaminated = true;
          grid.set(xx, yy, empty);
          continue;
        }

        final cat = categoryOf(id);
        if (_matches(s, id, cat)) {
          // 여기 진입 시 count < goal 이 보장된다(목표 도달 즉시 아래에서 반환).
          flask.count++;
          // 물질 테이블 조회 전 셀 ID 범위 가드 (디버그 조기 노출, 릴리즈 비용 0).
          assert(id >= 0 && id < Material.values.length,
              '물질 ID $id가 범위 밖 (0~${Material.values.length - 1})');
          onSettle?.call(SettleEvent(
            flaskIndex: fi,
            x: xx,
            y: yy,
            material: Material.values[id],
            phase: flaskStateForCategory(cat),
          ));
          grid.set(xx, yy, empty); // 카운트한 셀만 소비
          // 목표 도달 → 이 패스의 나머지 셀은 소비하지 않고 넘치게 둔다 (넘침 규칙).
          if (flask.isComplete) return;
        } else if (s.state == null) {
          // 무조건/물질 플라스크의 비매칭 → 통과·소멸 (GDD 5.1).
          grid.set(xx, yy, empty);
        }
        // 상태 플라스크의 비매칭 상 셀은 남긴다 — 그 자리에서 전이해 카운트되도록.
      }
    }
  }

  /// 이 셀이 플라스크 조건을 만족하는가. material·state 둘 다 지정되면 AND.
  bool _matches(FlaskSpec s, int id, MaterialCategory cat) {
    if (s.material != null && id != s.material!.index) return false;
    if (s.state != null && flaskStateForCategory(cat) != s.state) return false;
    return true;
  }
}
