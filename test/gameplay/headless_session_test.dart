import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:philosophers_ink/gameplay/headless_session.dart';
import 'package:philosophers_ink/level/loader.dart';
import 'package:philosophers_ink/level/level_model.dart';
import 'package:philosophers_ink/sim/materials.dart';

Level _load(String name) =>
    loadLevelFromJson(File('assets/levels/$name').readAsStringSync(), source: name);

void main() {
  group('HeadlessSession', () {
    test('reset 3회 연속 동일 그리드 해시 (재시작 안전, GDD 10.5)', () {
      final level = _load('level_001.json');
      final s = HeadlessSession(level);
      final hashes = <int>[];
      for (var run = 0; run < 3; run++) {
        s.reset();
        s.applyStroke(InkType.chalk, 40, 120, 84, 220);
        for (var t = 0; t < 200; t++) {
          s.tick();
        }
        hashes.add(s.game.grid.hash());
      }
      expect(hashes[0], hashes[1]);
      expect(hashes[1], hashes[2]);
    });

    test('applyStroke는 예산을 초과 차감하지 않는다 (부분 배치 cap)', () {
      final level = _load('level_001.json'); // chalk 예산 250.
      final s = HeadlessSession(level)..reset();
      // 그리드 폭 전체를 가로지르는 거대한 스트로크 — 예산 상한에서 잘린다.
      final placed = s.applyStroke(InkType.chalk, 0, 300, 159, 300);
      expect(placed, s.inkUsed);
      expect(s.inkUsed, lessThanOrEqualTo(250));
      expect(s.inkUsed, greaterThan(0));
    });

    test('숨김 잉크(예산 0)는 배치되지 않는다', () {
      final level = _load('level_001.json'); // heat/frost 예산 0.
      final s = HeadlessSession(level)..reset();
      expect(s.applyStroke(InkType.heat, 10, 10, 30, 10), 0);
      expect(s.applyStroke(InkType.frost, 10, 20, 30, 20), 0);
      expect(s.inkUsed, 0);
    });

    test('중력 반전은 기믹 있는 레벨에서만 동작', () {
      final noGrav = HeadlessSession(_load('level_001.json'))..reset();
      noGrav.toggleGravity();
      expect(noGrav.gravityInverted, isFalse, reason: '기믹 없으면 무시');

      final grav = HeadlessSession(_load('level_008.json'))..reset();
      grav.toggleGravity();
      expect(grav.gravityInverted, isTrue);
      grav.reset();
      expect(grav.gravityInverted, isFalse, reason: 'reset이 기본으로 되돌림');
    });
  });
}
