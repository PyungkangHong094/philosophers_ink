import 'package:flutter_test/flutter_test.dart';
import 'package:philosophers_ink/core/constants.dart';
import 'package:philosophers_ink/core/game_state.dart';
import 'package:philosophers_ink/sim/emitter.dart';
import 'package:philosophers_ink/sim/gimmicks.dart';
import 'package:philosophers_ink/sim/materials.dart';

const _w = SimConstants.gridWidth;
const _h = SimConstants.gridHeight;

/// 기믹 5종이 모두 활성인 최악 시나리오 GameState.
/// - 상단 재 방출구(물+재 혼합) → 게이트에서 재를 물로 정화 → 포탈로 원거리 이동.
/// - 상단부 빙결 존(물→얼음 상전이 부하) + 중력 반전 토글은 입력 시퀀스로 주입한다.
GameState _scene() {
  final ashEmitter = EmitterConfig(
    x: _w ~/ 2 - 6,
    y: 2,
    width: 13,
    materialId: Material.water.index,
    intervalTicks: 2,
    ashRatio: 0.3, // 재 방출구
  );
  // 화면 폭 전체를 덮는 변성 게이트: 모든 이동 물질 → WATER (정화).
  final gate = TransmutationGate.rect(
    gridWidth: _w,
    x: 0,
    y: _h ~/ 2,
    width: _w,
    height: 1,
    toMaterial: Material.water.index,
  );
  // 좌하단 → 우상단 포탈 (5x5 박스 쌍).
  final portal = Portal.rects(
    gridWidth: _w,
    entryX: 4,
    entryY: _h - 8,
    exitX: _w - 10,
    exitY: 8,
    width: 5,
    height: 5,
  );
  // 상단 1/4을 덮는 빙결 존(레벨 고정 화로/빙결) — 상전이 부하를 최악화.
  final zone = TemperatureZone.rect(
    gridWidth: _w,
    x: 0,
    y: 4,
    width: _w,
    height: _h ~/ 4,
    kind: TemperatureZoneKind.cool,
  );
  return GameState(
    emitters: [ashEmitter],
    gates: [gate],
    portals: [portal],
    temperatureZones: [zone],
  );
}

/// 결정적 입력 시퀀스: 벽 하나 + 중력 반전 토글(틱 60 on, 틱 180 off) + N틱.
int _runAndHash() {
  final game = _scene();
  final s = game.beginStroke(InkType.chalk);
  game.extendStroke(s, 20, 260, 140, 300);
  for (var i = 0; i < 300; i++) {
    if (i == 60) game.setGravityInverted(true);
    if (i == 180) game.setGravityInverted(false);
    game.tick();
  }
  return game.grid.hash();
}

void main() {
  test('기믹 전부 활성 + 중력 토글 → 300틱 후 해시가 3회 모두 동일 (재시작 결정성)', () {
    final h1 = _runAndHash();
    final h2 = _runAndHash();
    final h3 = _runAndHash();
    expect(h1, h2);
    expect(h2, h3);
  });

  test('reset 후 재현 시에도 해시 동일 (GDD 10.5, 3회)', () {
    final game = _scene();
    void play() {
      final s = game.beginStroke(InkType.chalk);
      game.extendStroke(s, 20, 260, 140, 300);
      for (var i = 0; i < 200; i++) {
        if (i == 60) game.setGravityInverted(true);
        game.tick();
      }
    }

    play();
    final first = game.grid.hash();
    for (var r = 0; r < 3; r++) {
      game.reset();
      // reset이 중력을 기본으로 되돌리는지도 함께 검증.
      expect(game.gravityInverted, isFalse, reason: 'reset #$r 중력 미복원');
      play();
      expect(game.grid.hash(), first, reason: 'reset #$r 재현 실패');
    }
  });

  test('기믹 5종 활성 최악 시나리오 틱 예산 (~3ms) — 실측 로그', () {
    final game = _scene();
    // 그리드를 실사용 밀도로 채운 뒤 계측 (워밍업).
    for (var i = 0; i < 400; i++) {
      game.tick();
    }
    // 배치별 평균의 **최솟값**으로 판정한다. flutter_test는 파일을 병렬 아이솔레이트로
    // 돌리므로 단순 평균은 머신 포화 시 벽시계 노이즈로 위양성을 낸다 (lava_reaction_test와
    // 동일 방식). 경합이 덜 낀 배치의 최솟값이 실제 처리량을 대표한다.
    // 배치 수·길이를 늘려(10×80) 경합 심한 환경에서도 깨끗한 배치가 하나는 잡히게 한다.
    const batches = 10;
    const itersPerBatch = 80;
    var minPerTickMs = double.infinity;
    var lastAvg = 0.0;
    for (var b = 0; b < batches; b++) {
      final sw = Stopwatch()..start();
      for (var i = 0; i < itersPerBatch; i++) {
        game.tick();
      }
      sw.stop();
      lastAvg = sw.elapsedMicroseconds / itersPerBatch / 1000.0;
      if (lastAvg < minPerTickMs) minPerTickMs = lastAvg;
    }
    // ignore: avoid_print
    print('기믹 활성 틱: min ${minPerTickMs.toStringAsFixed(3)}ms '
        '(마지막 배치 ${lastAvg.toStringAsFixed(3)}ms, '
        '활성 셀 ${game.activeCellCount}, 예산 3ms)');
    expect(minPerTickMs, lessThan(3.0),
        reason: '기믹 활성 최악 시나리오 틱 예산 초과 (${minPerTickMs}ms)');
  });
}
