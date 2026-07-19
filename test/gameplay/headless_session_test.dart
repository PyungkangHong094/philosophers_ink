import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:philosophers_ink/gameplay/headless_session.dart';
import 'package:philosophers_ink/level/loader.dart';
import 'package:philosophers_ink/level/level_model.dart';

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
      final level = _load('level_001.json');
      // 출고 레벨 예산은 콘텐츠라 계속 바뀐다 — 파일에서 동적으로 읽는다.
      final cap = level.inkBudget[InkType.chalk]!;
      final s = HeadlessSession(level)..reset();
      // 그리드 폭 전체를 가로지르는 거대한 스트로크 — 예산 상한에서 잘린다.
      final placed = s.applyStroke(InkType.chalk, 0, 300, 159, 300);
      expect(placed, s.inkUsed);
      expect(s.inkUsed, lessThanOrEqualTo(cap));
      expect(s.inkUsed, greaterThan(0));
    });

    test('숨김 잉크(예산 0)는 배치되지 않는다', () {
      final level = _load('level_001.json'); // heat/frost 예산 0.
      final s = HeadlessSession(level)..reset();
      expect(s.applyStroke(InkType.heat, 10, 10, 30, 10), 0);
      expect(s.applyStroke(InkType.frost, 10, 20, 30, 20), 0);
      expect(s.inkUsed, 0);
    });

    test('비커 벽이 스탬프된다 (LevelSession과 동일 물리 — 솔버 충실도)', () {
      final level = _load('level_001.json');
      final s = HeadlessSession(level);
      final f = level.flasks.first;
      final g = s.game.grid;
      final left = f.x;
      final right = f.x + f.w - 1;
      final bottom = f.y + f.h - 1;
      expect(g.get(left, f.y + 1), Material.wall.index, reason: '좌벽');
      expect(g.get(right, f.y + 1), Material.wall.index, reason: '우벽');
      expect(g.get(f.x + 1, bottom), Material.wall.index, reason: '바닥');
    });

    test('제한 시간 초과 시 timeout 실패 (LevelSession과 동일 계약)', () {
      final level = Level(
        meta: const LevelMeta(id: 1, name: 't', chapter: 1, difficulty: 1),
        background: 0xFF000000,
        emitters: [
          EmitterSpec(x: 5, y: 0, width: 3, material: Material.prima, rate: 1),
        ],
        flasks: const [FlaskSpec(x: 4, y: 3, w: 5, h: 8, goal: 100000)],
        inkBudget: const {InkType.chalk: 0},
        timeLimitSeconds: 1, // 60틱
      );
      final s = HeadlessSession(level);
      for (var t = 0; t < 70; t++) {
        s.tick();
      }
      expect(s.isFailed, isTrue);
      expect(s.isTimedOut, isTrue);
    });

    test('솔버 tickCap(≤3600)은 최소 제한(4800틱=80s)보다 작다 — 기존 해 무영향', () {
      final s = HeadlessSession(_load('level_001.json'));
      expect(s.timeLimitTicks, greaterThanOrEqualTo(80 * 60));
      expect(3600, lessThan(s.timeLimitTicks));
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
