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

/// 그리드를 직접 순회해 **둥근 잉크 방울**로 그리는 페인터 (사용자 디렉션 2026-07-19).
///
/// 동적 물질(입자·액체·기체)은 원형 점 — "잉크 방울" 픽션 정합. 정적 잉크·벽
/// (staticSolid)은 각진 사각 유지 — 그은 선·지형의 명료함. 물질별 drawRawPoints
/// 단일 콜이라 이미지 디코드 경로(WorldImageSource)보다 프레임 비용이 낮다.
/// EMPTY는 그리지 않아 레벨 배경(Scaffold)이 비친다.
class WorldPointsPainter extends CustomPainter {
  final Uint8List cells;
  final int gridWidth;
  final int gridHeight;

  WorldPointsPainter({
    required this.cells,
    required this.gridWidth,
    required this.gridHeight,
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
    final buckets = List<List<double>?>.filled(kMaterialTable.length, null);
    for (var i = 0; i < cells.length; i++) {
      final id = cells[i];
      if (id == 0) continue; // EMPTY
      final b = buckets[id] ??= <double>[];
      final gx = i % gridWidth;
      final gy = i ~/ gridWidth;
      b
        ..add(vp.offsetX + (gx + 0.5) * s)
        ..add(vp.offsetY + (gy + 0.5) * s);
    }
    for (var id = 1; id < buckets.length; id++) {
      final b = buckets[id];
      if (b == null) continue;
      final isStatic = categoryOf(id) == MaterialCategory.staticSolid;
      final paint = (isStatic ? _square : _round)[id]
        ..strokeWidth = isStatic ? s : s * _roundOverlap;
      canvas.drawRawPoints(
          ui.PointMode.points, Float32List.fromList(b), paint);
    }
  }

  @override
  bool shouldRepaint(WorldPointsPainter old) =>
      old.cells != cells ||
      old.gridWidth != gridWidth ||
      old.gridHeight != gridHeight;
}
