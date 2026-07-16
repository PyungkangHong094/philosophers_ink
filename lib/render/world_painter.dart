import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

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

  WorldImageSource({required this.width, required this.height});

  ui.Image? get image => _image;

  /// [rgba]로 새 이미지를 만든다. 이전 변환이 진행 중이면 이번 프레임은 건너뛴다.
  Future<void> update(Uint8List rgba) async {
    if (_converting) return;
    _converting = true;
    try {
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
    _image?.dispose();
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
