import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:philosophers_ink/render/world_painter.dart';
import 'package:philosophers_ink/sim/materials.dart';

// P1-1: 재사용 좌표 버퍼가 이전 버킷 방식과 동일한 점을 제자리로 채우는지 검증.
void main() {
  test('물질별 점을 셀 중심 좌표로 제자리 채운다', () {
    const w = 4, h = 4;
    final cells = Uint8List(w * h);
    cells[0 * w + 1] = Material.wall.index; // (gx1, gy0)
    cells[3 * w + 2] = Material.water.index; // (gx2, gy3)
    final vp = GridViewport.fit(const Size(4, 4), w, h); // scale 1, offset 0

    final buffers = WorldPointBuffers();
    buffers.rebuild(cells, w, h, vp);

    expect(buffers.count(Material.wall.index), 1);
    expect(buffers.count(Material.water.index), 1);
    expect(buffers.count(Material.prima.index), 0);

    final wall = buffers.view(Material.wall.index);
    expect(wall.length, 2);
    expect(wall[0], 1.5); // (1+0.5)*1
    expect(wall[1], 0.5);

    final water = buffers.view(Material.water.index);
    expect(water[0], 2.5);
    expect(water[1], 3.5);
  });

  test('재사용: 두 번째 rebuild가 이전 결과에 오염되지 않는다', () {
    const w = 4, h = 4;
    final vp = GridViewport.fit(const Size(4, 4), w, h);
    final buffers = WorldPointBuffers();

    final a = Uint8List(w * h)
      ..[0] = Material.water.index
      ..[1] = Material.water.index
      ..[2] = Material.water.index;
    buffers.rebuild(a, w, h, vp);
    expect(buffers.count(Material.water.index), 3);

    // 더 적은 점으로 재빌드 — 카운트·뷰가 스테일 없이 1만.
    final b = Uint8List(w * h)..[5] = Material.water.index; // (gx1, gy1)
    buffers.rebuild(b, w, h, vp);
    expect(buffers.count(Material.water.index), 1);
    final v = buffers.view(Material.water.index);
    expect(v.length, 2);
    expect(v[0], 1.5);
    expect(v[1], 1.5);
  });

  test('EMPTY(0)는 점을 만들지 않는다', () {
    const w = 3, h = 3;
    final vp = GridViewport.fit(const Size(3, 3), w, h);
    final buffers = WorldPointBuffers();
    buffers.rebuild(Uint8List(w * h), w, h, vp);
    for (var id = 0; id < kMaterialTable.length; id++) {
      expect(buffers.count(id), 0);
    }
  });

  test('하이워터마크: 더 큰 재빌드 후 작은 재빌드가 정확', () {
    const w = 8, h = 8;
    final vp = GridViewport.fit(const Size(8, 8), w, h);
    final buffers = WorldPointBuffers();

    // 큰 프레임: water 20개.
    final big = Uint8List(w * h);
    for (var i = 0; i < 20; i++) {
      big[i] = Material.water.index;
    }
    buffers.rebuild(big, w, h, vp);
    expect(buffers.count(Material.water.index), 20);
    expect(buffers.view(Material.water.index).length, 40);

    // 작은 프레임: water 2개 — view는 정확히 2점(4 float)만.
    final small = Uint8List(w * h)
      ..[0] = Material.water.index
      ..[9] = Material.water.index;
    buffers.rebuild(small, w, h, vp);
    expect(buffers.count(Material.water.index), 2);
    expect(buffers.view(Material.water.index).length, 4);
  });
}
