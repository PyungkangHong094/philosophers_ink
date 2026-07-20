/// 레벨 랩 L1 — 단일 레벨 스트로크 탐색 솔버 CLI (docs/LEVEL_LAB.md §2).
///
///   dart run tool/level_lab/solve.dart --level assets/levels/level_001.json
///
/// 옵션: --seed N --rollouts N --refine N --tick-cap N --stall N --max-strokes N
///       --out DIR (결과 JSON 기록) --quiet
///       --probe no-flip | --probe no-ink=chalk|heat|frost  (제약 프로브 단발)
///       --probes  (해당 레벨의 프로브 묶음 실행·출력)
// CLI 도구라 stdout 출력이 정상 — avoid_print 억제.
// ignore_for_file: avoid_print
library;

import 'dart:convert';

import 'src/candidate.dart';
import 'src/cli_args.dart';
import 'src/level_io.dart';
import 'src/solver.dart';

void main(List<String> argv) {
  final args = CliArgs(argv);
  final levelPath = args.str('level');
  if (levelPath == null) {
    print('사용법: dart run tool/level_lab/solve.dart --level <path> [옵션]');
    return;
  }

  final base = const SolverConfig();
  var cfg = base.copyWith(
    seed: args.intOr('seed', base.seed),
    rolloutBudget: args.intOr('rollouts', base.rolloutBudget),
    refineBudget: args.intOr('refine', base.refineBudget),
    tickCap: args.intOr('tick-cap', base.tickCap),
    stallTicks: args.intOr('stall', base.stallTicks),
    maxStrokes: args.intOr('max-strokes', base.maxStrokes),
  );

  final level = loadLevelFile(levelPath);

  // 프로브 묶음 모드: no-flip + no-ink 전종을 돌려 필수성 리포트.
  if (args.has('probes')) {
    final probes = runProbes(level, cfg);
    print('L${level.meta.id.toString().padLeft(3, "0")} 프로브: ${jsonEncode(probes)}');
    return;
  }

  // 단발 제약 프로브.
  String? probeLabel;
  final probe = args.str('probe');
  if (probe == 'no-flip') {
    cfg = cfg.copyWith(allowGravity: false);
    probeLabel = 'no-flip';
  } else if (probe != null && probe.startsWith('no-ink=')) {
    final t = inkFromKey(probe.substring('no-ink='.length));
    if (t != null) {
      cfg = cfg.copyWith(zeroedInks: {t});
      probeLabel = 'no-ink:${inkKey(t)}';
    }
  }

  final result = solveLevel(level, cfg);

  print('${_summaryLine(result)}${probeLabel == null ? "" : "  [probe=$probeLabel]"}');
  if (!args.has('quiet') && result.solutions.isNotEmpty) {
    final best = result.solutions.first;
    print('  최소 해: ${best.candidate} (ink=${best.ink}, ticks=${best.ticks})');
  }

  final json = result.toJson();
  if (probeLabel != null) json['probe'] = probeLabel;

  if (args.has('out')) {
    final outDir = args.str('out') ?? kDefaultOutDir;
    // 프로비넌스 스탬프 — 소비자(bake_hints)가 stale 아카이브를 거부할 근거.
    stampProvenance(json, levelPath, gitSha: currentGitSha());
    writeResultJson(outDir, result.levelId, json);
    print('  → $outDir/level_${result.levelId.toString().padLeft(3, "0")}.json');
  } else if (args.has('json')) {
    print(const JsonEncoder.withIndent('  ').convert(json));
  }
}

String _summaryLine(SolveResult r) {
  final status = r.solvable ? 'SOLVABLE' : 'UNSOLVED(솔버 한계)';
  final ink = r.minInk == null ? '-' : '${r.minInk}';
  final eff = r.effort == null ? '-' : '${r.effort}';
  return 'L${r.levelId.toString().padLeft(3, "0")} [$status] '
      'min_ink=$ink effort=$eff rollouts=${r.rollouts} '
      '${r.elapsedMs}ms  ${r.name}';
}
