/// 레벨 랩 L1 — 복수 레벨 일괄 솔버 CLI (docs/LEVEL_LAB.md §2). Isolate 풀 병렬.
///
///   dart run tool/level_lab/sweep.dart --chapter 1
///   dart run tool/level_lab/sweep.dart --all --concurrency 8
///
/// 옵션: --seed N --rollouts N --refine N --tick-cap N --stall N --max-strokes N
///       --concurrency N --out DIR
///
/// 결과: DIR/level_NNN.json 개별 기록 + stdout 요약 표 + 게이트 줄(solvable X/Y).
// CLI 도구라 stdout 출력이 정상 — avoid_print 억제.
// ignore_for_file: avoid_print
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'src/cli_args.dart';
import 'src/level_io.dart';
import 'src/solver.dart';

/// isolate에 넘길 작업 (전부 원시값이라 전송 가능).
class _Task {
  final String path;
  final int seed;
  final int rollouts;
  final int refine;
  final int tickCap;
  final int stall;
  final int maxStrokes;
  final bool probe;

  /// 스윕 실행 시점 git HEAD SHA (프로비넌스 스탬프용, 없으면 null). 메인에서 1회 계산해 전달.
  final String? gitSha;
  const _Task(this.path, this.seed, this.rollouts, this.refine, this.tickCap,
      this.stall, this.maxStrokes, this.probe, this.gitSha);
}

Future<Map<String, dynamic>> _solveInIsolate(_Task t) => Isolate.run(() {
      final level = loadLevelFile(t.path);
      final cfg = SolverConfig(
        seed: t.seed,
        rolloutBudget: t.rollouts,
        refineBudget: t.refine,
        tickCap: t.tickCap,
        stallTicks: t.stall,
        maxStrokes: t.maxStrokes,
      );
      // solveLevel이 아카이브 기록 가드로 이미 위양성을 걸러 반환한다(verify_failed 포함).
      final json = solveLevel(level, cfg).toJson();
      if (t.probe) json['probes'] = runProbes(level, cfg);
      // 프로비넌스: 이 레벨 내용 해시로 소비 시점 stale 검출이 가능하게 한다.
      stampProvenance(json, t.path, gitSha: t.gitSha);
      return json;
    });

Future<void> main(List<String> argv) async {
  final args = CliArgs(argv);

  final List<String> paths;
  if (args.has('all')) {
    paths = allLevelPaths();
  } else if (args.has('chapter')) {
    paths = levelPathsForChapter(args.intOr('chapter', 1));
  } else {
    print('사용법: dart run tool/level_lab/sweep.dart (--all | --chapter N) [옵션]');
    return;
  }
  if (paths.isEmpty) {
    print('대상 레벨 없음.');
    return;
  }

  final base = const SolverConfig();
  final seed = args.intOr('seed', base.seed);
  final rollouts = args.intOr('rollouts', base.rolloutBudget);
  final refine = args.intOr('refine', base.refineBudget);
  final tickCap = args.intOr('tick-cap', base.tickCap);
  final stall = args.intOr('stall', base.stallTicks);
  final maxStrokes = args.intOr('max-strokes', base.maxStrokes);
  final outDir = args.str('out') ?? kDefaultOutDir;
  final concurrency = args.intOr('concurrency', Platform.numberOfProcessors)
      .clamp(1, paths.length);

  final probe = args.has('probe');
  final gitSha = currentGitSha(); // 스윕 1회당 한 번 — 프로비넌스 스탬프에 박는다.
  final tasks = [
    for (final p in paths)
      _Task(p, seed, rollouts, refine, tickCap, stall, maxStrokes, probe, gitSha)
  ];

  stderr.writeln('레벨 랩 sweep: ${paths.length}레벨 · '
      '동시성 $concurrency · seed $seed · rollouts $rollouts · tickCap $tickCap');

  final sw = Stopwatch()..start();
  final results = <Map<String, dynamic>>[];
  var next = 0;
  var done = 0;

  Future<void> worker() async {
    while (true) {
      final i = next++;
      if (i >= tasks.length) break;
      // 한 레벨이 던져도 스윕 전체가 죽지 않게 격리 (진행 로그 유지).
      Map<String, dynamic> r;
      try {
        r = await _solveInIsolate(tasks[i]);
      } catch (e) {
        r = {
          'level': -1,
          'name': tasks[i].path,
          'chapter': 0,
          'solvable': false,
          'min_ink': null,
          'effort': null,
          'rollouts': 0,
          'elapsed_ms': 0,
          'error': '$e',
        };
        stderr.writeln('  [ERR] ${tasks[i].path}: $e');
      }
      results.add(r);
      if ((r['level'] as int) > 0) writeResultJson(outDir, r['level'] as int, r);
      done++;
      stderr.writeln('  [$done/${tasks.length}] ${_line(r)}');
    }
  }

  await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);
  sw.stop();

  results.sort((a, b) => (a['level'] as int).compareTo(b['level'] as int));

  final solvable = results.where((r) => r['solvable'] == true).length;

  print('');
  print('레벨 | 상태     | min_ink | effort | rollouts | ms    | 이름');
  print('-----+----------+---------+--------+----------+-------+------');
  for (final r in results) {
    print(_tableRow(r));
  }
  // 기록 가드가 버린 위양성 집계 — 탐색-검증 불일치 신호.
  final verifyDropped = results.fold<int>(
      0, (a, r) => a + ((r['verify_failed'] as int?) ?? 0));
  final droppedLevels = results
      .where((r) => ((r['verify_failed'] as int?) ?? 0) > 0)
      .map((r) => 'L${r['level']}(${r['verify_failed']})')
      .join(', ');

  print('');
  print('게이트: solvable $solvable/${results.length} · '
      '총 ${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)}s · out=$outDir');
  print('기록 가드: 위양성 $verifyDropped개 제외'
      '${verifyDropped > 0 ? " ($droppedLevels)" : ""}');
  if (solvable < results.length) {
    final miss = results
        .where((r) => r['solvable'] != true)
        .map((r) => 'L${r['level']}')
        .join(', ');
    print('미발견(솔버 한계): $miss');
  }
}

String _line(Map<String, dynamic> r) {
  final s = r['solvable'] == true ? 'OK' : 'MISS';
  return 'L${r['level']} $s ink=${r['min_ink'] ?? "-"} '
      'effort=${r['effort'] ?? "-"} ${r['elapsed_ms']}ms';
}

String _tableRow(Map<String, dynamic> r) {
  final id = 'L${r['level'].toString().padLeft(3, "0")}';
  final st = (r['solvable'] == true ? 'SOLVABLE' : 'UNSOLVED').padRight(8);
  final ink = (r['min_ink']?.toString() ?? '-').padLeft(7);
  final eff = (r['effort']?.toString() ?? '-').padLeft(6);
  final ro = r['rollouts'].toString().padLeft(8);
  final ms = r['elapsed_ms'].toString().padLeft(5);
  return '$id | $st | $ink | $eff | $ro | $ms | ${r['name']}';
}
