import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:philosophers_ink/level/loader.dart';
import 'package:philosophers_ink/level/level_model.dart';

import '../../tool/level_lab/src/candidate.dart';
import '../../tool/level_lab/src/level_io.dart';
import '../../tool/level_lab/src/solver.dart';

/// 아카이브 기록 가드 + 프로비넌스 스탬프 회귀 (2026-07-20 위양성 포렌식 대응).
///
/// L016 픽스처는 포렌식에서 실측한 두 후보를 쓴다:
///  - (91,68)->(15,62) : 09:14 스테일 아카이브의 위양성 — 현재 물리에서 클리어 안 됨.
///  - (93,67)->(17,62) : 현재 솔버가 찾은 진짜 해 — fresh 세션에서 CLEAR.
/// 가드는 전자를 버리고 후자만 남겨야 한다.
Level _load(String name) => loadLevelFromJson(
    File('assets/levels/$name').readAsStringSync(),
    source: name);

FoundSolution _sol(int x0, int y0, int x1, int y1, int ink) => FoundSolution(
    Candidate([StrokePrimitive(InkType.chalk, x0, y0, x1, y1)]), ink, 0);

void main() {
  group('verifySolutions — 아카이브 기록 가드', () {
    test('위양성은 버리고 진짜 해만 남긴다 (L016)', () {
      final level = _load('level_016.json');
      final fake = _sol(91, 68, 15, 62, 162); // 스테일 위양성
      final good = _sol(93, 67, 17, 62, 161); // 진짜 해
      // 잉크 오름차순 입력(good=161, fake=162)을 흉내 — want 넉넉히.
      final v = verifySolutions(level, [good, fake], 5);
      expect(v.kept.length, 1, reason: '진짜 해 1개만 통과');
      expect(v.kept.first.candidate.strokes.first.x0, 93,
          reason: '남은 것은 진짜 해');
      expect(v.dropped, 1, reason: '위양성 1개 탈락');
    });

    test('want 도달 시 조기 종료 — 이후 후보는 검증하지 않는다', () {
      final level = _load('level_016.json');
      final good = _sol(93, 67, 17, 62, 161);
      final fake = _sol(91, 68, 15, 62, 162);
      final v = verifySolutions(level, [good, fake], 1); // 1개만 원함
      expect(v.kept.length, 1);
      expect(v.dropped, 0, reason: 'good 확보 후 fake는 검증 전에 조기 종료');
    });
  });

  group('contentHash / stampProvenance — 프로비넌스 스탬프', () {
    test('내용 해시는 결정적이고 내용이 다르면 달라진다', () {
      expect(contentHash('abc'), contentHash('abc'));
      expect(contentHash('abc'), isNot(contentHash('abd')));
      expect(contentHash('abc').length, 16);
    });

    test('스탬프가 현재 레벨 내용 해시·git_sha를 박는다', () {
      const path = 'assets/levels/level_016.json';
      final json = <String, dynamic>{};
      stampProvenance(json, path, gitSha: 'deadbeef');
      final prov = json['provenance'] as Map;
      expect(prov['level_hash'], levelContentHash(path));
      expect((prov['level_hash'] as String).length, 16);
      expect(prov['git_sha'], 'deadbeef');
      expect(prov['swept_at'], isNotNull);
    });

    test('git_sha가 null이면 키를 생략한다', () {
      final json = <String, dynamic>{};
      stampProvenance(json, 'assets/levels/level_016.json');
      expect((json['provenance'] as Map).containsKey('git_sha'), isFalse);
    });
  });
}
