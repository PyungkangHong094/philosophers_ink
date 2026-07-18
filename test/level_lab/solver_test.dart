import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:philosophers_ink/level/loader.dart';
import 'package:philosophers_ink/level/level_model.dart';

import '../../tool/level_lab/src/solver.dart';

Level _load(String name) =>
    loadLevelFromJson(File('assets/levels/$name').readAsStringSync(), source: name);

void main() {
  group('스트로크 탐색 솔버', () {
    test('레벨 001 자동 해 발견', () {
      final level = _load('level_001.json');
      final res = solveLevel(
        level,
        // 콘텐츠 갱신에 견고하도록 여유 예산 — 치즈 봉쇄 후 001은 effort ~39.
        const SolverConfig(
          rolloutBudget: 150,
          refineBudget: 0,
          tickCap: 2400,
          stallTicks: 300,
          collectTarget: 4,
        ),
      );
      expect(res.solvable, isTrue);
      expect(res.minInk, isNotNull);
      expect(res.effort, isNotNull);
      expect(res.solutions, isNotEmpty);
    });

    test('시드 고정 → 재실행 완전 동일 (결정성)', () {
      final level = _load('level_008.json'); // 즉시 클리어 → 빠름.
      const cfg = SolverConfig(
        seed: 20260718,
        rolloutBudget: 12,
        refineBudget: 8,
        tickCap: 400,
        stallTicks: 200,
      );
      final a = solveLevel(level, cfg);
      final b = solveLevel(level, cfg);
      expect(a.solvable, b.solvable);
      expect(a.minInk, b.minInk);
      expect(a.effort, b.effort);
      expect(a.rollouts, b.rollouts);
      expect(
        a.solutions.map((s) => '${s.candidate}|${s.ink}').toList(),
        b.solutions.map((s) => '${s.candidate}|${s.ink}').toList(),
        reason: '같은 시드 → 같은 해 아카이브',
      );
    });

    test('no-flip 제약 프로브는 결정적으로 실행된다', () {
      final level = _load('level_008.json'); // 중력 기믹 레벨.
      const c = SolverConfig(
        rolloutBudget: 6,
        refineBudget: 0,
        tickCap: 400,
        stallTicks: 200,
        allowGravity: false,
      );
      final a = solveLevel(level, c);
      final b = solveLevel(level, c);
      expect(a.solvable, b.solvable);
      expect(a.minInk, b.minInk);
    });

    test('no-ink(chalk 0) 제약은 스트로크 없이 탐색한다', () {
      final level = _load('level_008.json');
      const c = SolverConfig(
        rolloutBudget: 6,
        refineBudget: 0,
        tickCap: 400,
        stallTicks: 200,
        zeroedInks: {InkType.chalk},
      );
      final r = solveLevel(level, c);
      // chalk 예산 0 → 후보 스트로크 없음 → solvable이면 잉크 0(빈 후보) 해여야 한다.
      if (r.solvable) expect(r.minInk, 0);
    });

    test('다른 시드 → 탐색 경로가 달라질 수 있다 (결정성 무결성 확인용)', () {
      final level = _load('level_002.json');
      const base = SolverConfig(
        rolloutBudget: 40,
        refineBudget: 0,
        tickCap: 900,
        stallTicks: 300,
        collectTarget: 3,
      );
      final a = solveLevel(level, base);
      final b = solveLevel(level, base.copyWith(seed: base.seed + 1));
      // 둘 다 결정적이어야 한다(자기 자신과 동일).
      final a2 = solveLevel(level, base);
      expect(a.rollouts, a2.rollouts);
      expect(a.minInk, a2.minInk);
      // 시드가 다르면 최소한 실행이 독립적으로 완료된다(해 존재 여부와 무관).
      expect(b.rollouts, greaterThan(0));
    });
  });
}
