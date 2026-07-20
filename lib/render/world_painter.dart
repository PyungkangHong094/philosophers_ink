import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../sim/materials.dart';

/// 논리 그리드 ↔ 화면 좌표 변환. 정수배 스케일 + 센터링 (GDD 8.2·10.3).
///
/// 페인터와 입력 매핑이 **같은** 뷰포트를 써야 그은 자리에 정확히 셀이 찍힌다.
class GridViewport {
  final int scale; // 셀 1개 = scale 화면 픽셀 (정수)
  final double offsetX;
  final double offsetY;
  final int gridWidth;
  final int gridHeight;

  const GridViewport({
    required this.scale,
    required this.offsetX,
    required this.offsetY,
    required this.gridWidth,
    required this.gridHeight,
  });

  /// 캔버스 크기에 그리드를 정수배로 맞춘다. 비정수 스케일 금지(도트 미학).
  factory GridViewport.fit(Size size, int gridWidth, int gridHeight) {
    final sx = size.width ~/ gridWidth;
    final sy = size.height ~/ gridHeight;
    var scale = sx < sy ? sx : sy;
    if (scale < 1) scale = 1;
    final drawW = gridWidth * scale;
    final drawH = gridHeight * scale;
    return GridViewport(
      scale: scale,
      offsetX: (size.width - drawW) / 2,
      offsetY: (size.height - drawH) / 2,
      gridWidth: gridWidth,
      gridHeight: gridHeight,
    );
  }

  /// 화면 로컬 좌표 → 그리드 셀. 그리드 밖이면 null.
  (int, int)? toGrid(Offset local) {
    final gx = ((local.dx - offsetX) / scale).floor();
    final gy = ((local.dy - offsetY) / scale).floor();
    if (gx < 0 || gx >= gridWidth || gy < 0 || gy >= gridHeight) return null;
    return (gx, gy);
  }
}

/// RGBA 버퍼 → ui.Image 비동기 변환 (GDD 10.3 파이프라인).
///
/// ImmutableBuffer + ImageDescriptor.raw 경로는 비동기이므로, 프레임마다
/// 이미지를 새로 만들되 변환이 밀리지 않도록 in-flight 가드를 둔다.
/// 최신 이미지는 [image]에 보관되고 CustomPainter가 그것을 그린다.
class WorldImageSource extends ChangeNotifier {
  final int width;
  final int height;
  ui.Image? _image;
  bool _converting = false;
  bool _disposed = false;

  WorldImageSource({required this.width, required this.height});

  ui.Image? get image => _image;

  /// [rgba]로 새 이미지를 만든다. 이전 변환이 진행 중이면 이번 프레임은 건너뛴다.
  ///
  /// 변환은 여러 await를 거치는 비동기라, 그 사이 [dispose]가 끼어들 수 있다(플레이 중
  /// 이탈). 재개 시 이미 dispose된 상태면 방금 디코드한 이미지를 버리고 조용히 종료한다 —
  /// dispose된 ChangeNotifier에 notify(계약 위반 throw)하거나 이미지를 누수시키지 않는다.
  Future<void> update(Uint8List rgba) async {
    if (_disposed || _converting) return;
    _converting = true;
    try {
      // fromUint8List는 바이트를 **즉시(동기) 복사**하므로(엔진 계약), 이 await 이후
      // 호출자가 rgba 버퍼를 재사용해도 안전하다 — 단일 버퍼 티어링 없음.
      final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
      final descriptor = ui.ImageDescriptor.raw(
        buffer,
        width: width,
        height: height,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
      final codec = await descriptor.instantiateCodec();
      final frame = await codec.getNextFrame();
      buffer.dispose();
      descriptor.dispose();
      codec.dispose();
      // await 중 dispose가 끼어들었으면: 디코드한 이미지를 해제하고 종료(누수·notify 방지).
      if (_disposed) {
        frame.image.dispose();
        return;
      }
      final old = _image;
      _image = frame.image;
      old?.dispose();
      notifyListeners();
    } finally {
      _converting = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _image?.dispose();
    _image = null;
    super.dispose();
  }
}

/// 최신 월드 이미지를 정수배로 그린다. FilterQuality.none (도트 미학).
class WorldPainter extends CustomPainter {
  final WorldImageSource source;

  WorldPainter(this.source) : super(repaint: source);

  static final Paint _paint = Paint()..filterQuality = FilterQuality.none;

  @override
  void paint(Canvas canvas, Size size) {
    final image = source.image;
    if (image == null) return;
    final vp = GridViewport.fit(size, image.width, image.height);
    final drawW = (image.width * vp.scale).toDouble();
    final drawH = (image.height * vp.scale).toDouble();
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(vp.offsetX, vp.offsetY, drawW, drawH),
      _paint,
    );
  }

  @override
  bool shouldRepaint(WorldPainter oldDelegate) => oldDelegate.source != source;
}

/// [WorldPointsPainter]가 프레임마다 재사용하는 물질별 점 좌표 버퍼 (감사 P1-1).
///
/// 페인터 밖(플레이 화면 State)이 소유해 프레임 간 유지된다. 매 페인트에서 제자리로
/// 채우고 [view]로 [Canvas.drawRawPoints]에 넘겨 **페인트당 힙 할당 0**을 달성한다.
/// 버퍼는 하이워터마크로만 성장하고 축소하지 않는다(재할당 churn 제거).
class WorldPointBuffers {
  static final Float32List _emptyF32 = Float32List(0);

  final List<Float32List> _buf; // 물질 id별 (x,y 쌍 연속) 좌표
  final Int32List _count; // 이번 프레임 물질별 점 개수
  final Int32List _cursor; // 채우기 커서(플로트 인덱스)

  WorldPointBuffers() : this._(kMaterialTable.length);

  WorldPointBuffers._(int n)
      : _buf = List<Float32List>.filled(n, _emptyF32, growable: false),
        _count = Int32List(n),
        _cursor = Int32List(n);

  /// 그리드를 순회해 물질별 점 좌표를 제자리 채운다. 할당은 버퍼가 하이워터마크를
  /// 넘을 때만(성장) 발생하고, 정상 상태에선 0이다. 이후 [count]/[view]로 그린다.
  void rebuild(Uint8List cells, int gridWidth, int gridHeight, GridViewport vp) {
    final n = _count.length;
    _count.fillRange(0, n, 0);
    // 1패스: 물질별 개수 집계.
    for (var i = 0; i < cells.length; i++) {
      final id = cells[i];
      if (id != 0) _count[id]++;
    }
    // 용량 확보 — 하이워터마크(모자랄 때만 성장).
    for (var id = 1; id < n; id++) {
      final need = _count[id] * 2;
      if (_buf[id].length < need) _buf[id] = Float32List(need);
    }
    // 2패스: 제자리 채움. 행별 y·중첩 인덱스로 나눗셈/나머지 없이 순회.
    _cursor.fillRange(0, n, 0);
    final ox = vp.offsetX;
    final oy = vp.offsetY;
    final s = vp.scale.toDouble();
    var i = 0;
    for (var gy = 0; gy < gridHeight; gy++) {
      final rowY = oy + (gy + 0.5) * s;
      for (var gx = 0; gx < gridWidth; gx++, i++) {
        final id = cells[i];
        if (id == 0) continue;
        final buf = _buf[id];
        var c = _cursor[id];
        buf[c++] = ox + (gx + 0.5) * s;
        buf[c++] = rowY;
        _cursor[id] = c;
      }
    }
  }

  /// 물질 id의 이번 프레임 점 개수.
  int count(int id) => _count[id];

  /// 물질 id의 채워진 좌표만 보는 뷰(복사 없음) — drawRawPoints 입력.
  Float32List view(int id) =>
      Float32List.sublistView(_buf[id], 0, _count[id] * 2);
}

/// 그리드를 직접 순회해 **둥근 잉크 방울**로 그리는 페인터 (사용자 디렉션 2026-07-19).
///
/// 동적 물질(입자·액체·기체)은 원형 점 — "잉크 방울" 픽션 정합. 정적 잉크·벽
/// (staticSolid)은 각진 사각 유지 — 그은 선·지형의 명료함. 물질별 drawRawPoints
/// 단일 콜이라 이미지 디코드 경로(WorldImageSource)보다 프레임 비용이 낮다.
/// EMPTY는 그리지 않아 레벨 배경(Scaffold)이 비친다.
///
/// 좌표 버퍼는 [WorldPointBuffers](State 소유)를 재사용해 페인트당 할당이 없다(감사 P1-1).
class WorldPointsPainter extends CustomPainter {
  final Uint8List cells;
  final int gridWidth;
  final int gridHeight;
  final WorldPointBuffers buffers;

  WorldPointsPainter({
    required this.cells,
    required this.gridWidth,
    required this.gridHeight,
    required this.buffers,
    required Listenable repaint,
  }) : super(repaint: repaint);

  /// 원형 점이 이웃과 살짝 겹치게 하는 지름 배율 — 웅덩이·더미가 갈라져 보이지 않게.
  static const double _roundOverlap = 1.25;

  static final List<Paint> _round = _buildPaints(StrokeCap.round);
  static final List<Paint> _square = _buildPaints(StrokeCap.square);

  static List<Paint> _buildPaints(StrokeCap cap) => [
        for (final p in kMaterialTable)
          Paint()
            ..color = Color(0xFF000000 | (p.argb & 0x00FFFFFF))
              .withAlpha((p.argb >> 24) & 0xFF)
            ..strokeCap = cap
            ..style = PaintingStyle.stroke,
      ];

  @override
  void paint(Canvas canvas, Size size) {
    final vp = GridViewport.fit(size, gridWidth, gridHeight);
    final s = vp.scale.toDouble();
    buffers.rebuild(cells, gridWidth, gridHeight, vp);
    for (var id = 1; id < kMaterialTable.length; id++) {
      if (buffers.count(id) == 0) continue;
      final isStatic = categoryOf(id) == MaterialCategory.staticSolid;
      final paint = (isStatic ? _square : _round)[id]
        ..strokeWidth = isStatic ? s : s * _roundOverlap;
      canvas.drawRawPoints(ui.PointMode.points, buffers.view(id), paint);
    }
  }

  @override
  bool shouldRepaint(WorldPointsPainter old) =>
      old.cells != cells ||
      old.gridWidth != gridWidth ||
      old.gridHeight != gridHeight ||
      old.buffers != buffers;
}
