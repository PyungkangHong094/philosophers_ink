import 'package:flutter_test/flutter_test.dart';
import 'package:philosophers_ink/core/game_state.dart';
import 'package:philosophers_ink/sim/materials.dart';

// gameplay-engineer 잉크 예산이 의존하는 스트로크 API 계약 검증.
void main() {
  test('extendStroke는 새로 칠한 셀 수를 반환한다 (차감 근거)', () {
    final game = GameState();
    final id = game.beginStroke(InkType.chalk);
    final placed = game.extendStroke(id, 5, 5, 5, 5); // 단일 점, 두께 2 → 4셀
    expect(placed, 4);
    expect(game.strokeCellCount(id), 4);
  });

  test('previewStrokeCells는 그리드를 바꾸지 않고 배치 예정 셀 수를 센다', () {
    final game = GameState();
    final id = game.beginStroke(InkType.frost);
    final preview = game.previewStrokeCells(5, 5, 5, 5);
    final placed = game.extendStroke(id, 5, 5, 5, 5);
    expect(preview, 4);
    expect(placed, preview, reason: '프리뷰 == 실제 배치');
  });

  test('maxCells는 배치를 상한에서 멈춘다 (예산 부족 부분배치 방지)', () {
    final game = GameState();
    final id = game.beginStroke(InkType.chalk);
    // 긴 세그먼트지만 3셀까지만 배치.
    final placed = game.extendStroke(id, 0, 0, 40, 0, maxCells: 3);
    expect(placed, 3);
    expect(game.strokeCellCount(id), 3);
  });

  test('maxCells 0이면 아무것도 배치하지 않는다', () {
    final game = GameState();
    final id = game.beginStroke(InkType.chalk);
    expect(game.extendStroke(id, 0, 0, 40, 0, maxCells: 0), 0);
    expect(game.strokeCellCount(id), 0);
  });

  test('잉크 종류대로 물질을 배치한다', () {
    final game = GameState();
    final chalk = game.beginStroke(InkType.chalk);
    game.extendStroke(chalk, 2, 2, 2, 2);
    expect(game.grid.get(2, 2), Material.wall.index);
    expect(game.inkOfStroke(chalk), InkType.chalk);

    final heat = game.beginStroke(InkType.heat);
    game.extendStroke(heat, 20, 2, 20, 2);
    expect(game.grid.get(20, 2), Material.heatLine.index);

    final frost = game.beginStroke(InkType.frost);
    game.extendStroke(frost, 40, 2, 40, 2);
    expect(game.grid.get(40, 2), Material.coldLine.index);
  });

  test('deleteStroke는 배치 셀을 EMPTY로 복원하고 삭제 수를 반환 (잉크 미반환)', () {
    final game = GameState();
    final id = game.beginStroke(InkType.chalk);
    final placed = game.extendStroke(id, 5, 5, 5, 5);
    final removed = game.deleteStroke(id);
    expect(removed, placed);
    expect(game.grid.get(5, 5), Material.empty.index);
    expect(game.strokeCellCount(id), 0, reason: '삭제 후 스트로크 없음');
  });
}
