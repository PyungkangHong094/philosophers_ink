/// 기믹·방출구 정적 시각 표식 오버레이 (GDD 6·8.1, 감사 Q1-1).
///
/// 문제: 포탈·변성 게이트·온도 존·방출구는 sim에서 순수 셀 인덱스 집합(비물질)이라 화면에
/// 전혀 그려지지 않아, 챕터 2–4 플레이어가 "물이 순간이동/얼음이 허공에서 녹음/물질이
/// 무에서 쏟아짐"을 읽지 못한다(플레이어빌리티 결함). 이 페인터는 [Level] 모델의 좌표만
/// 읽어 **정적으로 1회** 표식을 그린다 — sim 상태를 구독하지 않으므로 결정성·성능에 무영향이다
/// (RepaintBoundary로 분리, repaint 트리거 없음).
///
/// 스타일: GDD 8.1 "볼드한 단색 실루엣 + 명도 대비 20%+". 챕터 4색 배경(니그레도 암/알베도
/// 명/시트리니타스 골드/루베도 암적) 모두에서 식별되도록, 배경 명도에 맞춘 적응형 헤일로
/// (밝은 배경엔 어두운, 어두운 배경엔 밝은 외곽선)를 색 코어 아래 깔아 대비를 보장한다.
///
/// 기믹별 시각 정체성(단순 기하 — 에셋 제작 없음):
/// - 포탈: 이중 링. 같은 색 = 연결된 입·출구 페어(색으로 페어를 식별).
/// - 변성 게이트: 점선 존 + 결과 물질색 하강 화살표(from→to 흐름 암시).
/// - 온도 존: 반투명 필드(열=주홍/냉=청백) + 파동 해칭.
/// - 방출구: 레토르트 목 실루엣(하강 깔때기) + 낙하 드립. 재 방출구는 재색 반점 혼입.
/// 중력 반전은 존이 없는 버튼 기믹이라 여기서 그리지 않는다(HUD의 '중력' 버튼이 표식).
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../core/constants.dart';
import '../../level/level_model.dart';
import '../../render/world_painter.dart' show GridViewport;
import '../../sim/materials.dart' show propsOf;
import '../tokens.dart';

class GimmickOverlayPainter extends CustomPainter {
  final Level level;

  /// 배경 명도로 결정한 적응형 헤일로 색(대비 보장용 외곽선).
  final Color _halo;

  GimmickOverlayPainter(this.level) : _halo = _haloFor(level.background);

  /// 밝은 배경(명도>0.5) → 어두운 헤일로, 어두운 배경 → 밝은 헤일로.
  static Color _haloFor(int argb) {
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;
    final lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0;
    return lum > 0.5
        ? InkColor.black0.withValues(alpha: 0.72)
        : InkColor.parchment.withValues(alpha: 0.72);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final vp = GridViewport.fit(
        size, SimConstants.gridWidth, SimConstants.gridHeight);

    // 방출구(레토르트 목) — 물질이 흘러나오는 원천.
    for (final e in level.emitters) {
      _paintEmitter(canvas, vp, e);
    }

    // 기믹 — 포탈 페어는 등장 순서로 색을 순환 배정.
    var portalIndex = 0;
    for (final gim in level.gimmicks) {
      switch (gim.type) {
        case GimmickType.portal:
          _paintPortal(canvas, vp, gim, portalIndex++);
        case GimmickType.tempZone:
          _paintTempZone(canvas, vp, gim);
        case GimmickType.varianceGate:
          _paintGate(canvas, vp, gim);
        // gravity_flip: 존 없음(HUD 버튼이 표식). ash_emitter: 방출구 ash_ratio가 표현.
      }
    }
  }

  // ---- 좌표 헬퍼 ----

  Rect _rect(GridViewport vp, num x, num y, num w, num h) => Rect.fromLTWH(
      vp.offsetX + x * vp.scale,
      vp.offsetY + y * vp.scale,
      (w * vp.scale).toDouble(),
      (h * vp.scale).toDouble());

  /// params의 중첩 rect({x,y,w,h}) → 그리드 Rect. 값이 없으면 null.
  Rect? _rectFromParams(GridViewport vp, Object? raw) {
    if (raw is! Map) return null;
    num? n(Object? v) => v is num ? v : null;
    final x = n(raw['x']);
    final y = n(raw['y']);
    final w = n(raw['w']);
    final h = n(raw['h']);
    if (x == null || y == null || w == null || h == null) return null;
    return _rect(vp, x, y, w, h);
  }

  /// 헤일로(외곽선) → 코어 2패스 스트로크. 배경 무관 대비 보장.
  void _strokeHalo(Canvas canvas, Path path, Color core, double width) {
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..strokeWidth = width + 2.0
        ..color = _halo,
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..strokeWidth = width
        ..color = core,
    );
  }

  /// src를 dash/gap 주기로 잘라 점선 Path 생성.
  Path _dashed(Path src, {double dash = 5, double gap = 4}) {
    final out = Path();
    for (final m in src.computeMetrics()) {
      var dist = 0.0;
      while (dist < m.length) {
        final next = math.min(dist + dash, m.length);
        out.addPath(m.extractPath(dist, next), Offset.zero);
        dist = next + gap;
      }
    }
    return out;
  }

  // ---- 방출구 ----

  /// 레토르트 목 실루엣: 방출 밴드에서 아래로 좁아지는 깔때기 + 드립.
  void _paintEmitter(Canvas canvas, GridViewport vp, EmitterSpec e) {
    final color = Color(propsOf(e.material.index).argb);
    // 밴드 상단 폭 = 방출 폭, 아래로 좁아지는 스포웃.
    final band = _rect(vp, e.x, e.y, e.width, 1);
    final neckH = math.max(band.width * 0.9, 10.0);
    final spoutHalf = math.max(band.width * 0.18, 2.0);
    final cx = band.center.dx;
    final top = band.top;
    final bottom = top + neckH;

    final funnel = Path()
      ..moveTo(band.left, top)
      ..lineTo(band.right, top)
      ..lineTo(cx + spoutHalf, bottom)
      ..lineTo(cx - spoutHalf, bottom)
      ..close();

    // 반투명 물질색 필드 + 헤일로 외곽선.
    canvas.drawPath(funnel, Paint()..color = color.withValues(alpha: 0.22));
    _strokeHalo(canvas, funnel, color, 2.0);

    // 재 방출구: 재색 반점 혼입(순수 오염 위험 암시).
    if (e.ashRatio > 0) {
      final ash = Color(propsOf(Material.ash.index).argb);
      final p = Paint()..color = ash;
      for (var i = 0; i < 4; i++) {
        final t = (i + 1) / 5.0;
        canvas.drawCircle(
            Offset(cx + (i.isEven ? -1 : 1) * spoutHalf * 0.5, top + neckH * t),
            math.max(vp.scale * 0.8, 1.4),
            p);
      }
    }

    // 드립 — 스포웃 아래 낙하 힌트 2점.
    final drip = Paint()..color = color.withValues(alpha: 0.85);
    for (var i = 0; i < 2; i++) {
      canvas.drawCircle(
          Offset(cx, bottom + neckH * (0.35 + i * 0.4)),
          math.max(vp.scale * 0.9, 1.6),
          drip);
    }
  }

  // ---- 포탈 ----

  void _paintPortal(
      Canvas canvas, GridViewport vp, GimmickSpec gim, int pairIndex) {
    final color = InkGimmick
        .portalPairs[pairIndex % InkGimmick.portalPairs.length];
    final entry = _rectFromParams(vp, gim.params[GimmickParamKey.entry]);
    final exit = _rectFromParams(vp, gim.params[GimmickParamKey.exit]);
    if (entry != null) _paintPortalRing(canvas, entry, color, filled: true);
    if (exit != null) _paintPortalRing(canvas, exit, color, filled: false);
  }

  /// 이중 링. 입구=중심 채움(빨려듦), 출구=중심 비움(뿜어냄). 색이 페어를 잇는다.
  void _paintPortalRing(Canvas canvas, Rect r, Color color,
      {required bool filled}) {
    final outer = Path()..addOval(r);
    final inner = Path()..addOval(r.deflate(math.max(r.shortestSide * 0.2, 2)));
    _strokeHalo(canvas, outer, color, 2.5);
    _strokeHalo(canvas, inner, color, 1.5);
    if (filled) {
      canvas.drawCircle(r.center, math.max(r.shortestSide * 0.12, 1.5),
          Paint()..color = color);
    }
  }

  // ---- 온도 존 ----

  void _paintTempZone(Canvas canvas, GridViewport vp, GimmickSpec gim) {
    final p = gim.params;
    final rect = _rectFromParams(vp, p) ??
        _rectMaybe(vp, p[GimmickParamKey.x], p[GimmickParamKey.y],
            p[GimmickParamKey.w], p[GimmickParamKey.h]);
    if (rect == null) return;
    final heat = p[GimmickParamKey.kind] != kTempZoneCool; // 기본 heat 취급
    final color = heat ? InkGimmick.heatZone : InkGimmick.coolZone;

    // 반투명 필드.
    canvas.drawRect(rect, Paint()..color = color.withValues(alpha: 0.12));
    // 점선 외곽 + 헤일로.
    final border = _dashed(Path()..addRect(rect));
    _strokeHalo(canvas, border, color, 1.5);

    // 파동 해칭 — 존 폭을 가로지르는 사인파 3줄(열=상승 물결감, 냉=예리한 지그재그 느낌).
    final rows = 3;
    for (var i = 1; i <= rows; i++) {
      final baseY = rect.top + rect.height * i / (rows + 1);
      final amp = math.min(rect.height / (rows + 2), 6.0);
      final wave = Path();
      const steps = 20;
      for (var s = 0; s <= steps; s++) {
        final t = s / steps;
        final x = rect.left + rect.width * t;
        final ph = t * math.pi * 4 + (heat ? 0 : math.pi / 2);
        final y = baseY + math.sin(ph) * amp * (heat ? 1.0 : 0.7);
        if (s == 0) {
          wave.moveTo(x, y);
        } else {
          wave.lineTo(x, y);
        }
      }
      _strokeHalo(canvas, wave, color, 1.5);
    }
  }

  Rect? _rectMaybe(GridViewport vp, Object? x, Object? y, Object? w, Object? h) {
    if (x is num && y is num && w is num && h is num) {
      return _rect(vp, x, y, w, h);
    }
    return null;
  }

  // ---- 변성 게이트 ----

  void _paintGate(Canvas canvas, GridViewport vp, GimmickSpec gim) {
    final p = gim.params;
    final rect = _rectMaybe(vp, p[GimmickParamKey.x], p[GimmickParamKey.y],
        p[GimmickParamKey.w], p[GimmickParamKey.h]);
    if (rect == null) return;

    // 결과 물질색(from→to의 to). 없으면 중립 헤일로만.
    final toName = p[GimmickParamKey.to];
    final toMat = toName is String ? materialFromName(toName) : null;
    final color =
        toMat != null ? Color(propsOf(toMat.index).argb) : InkColor.parchment;

    // 점선 존 외곽.
    final border = _dashed(Path()..addRect(rect));
    _strokeHalo(canvas, border, color, 1.5);

    // 중앙 하강 화살표(흐름 = 통과 시 to로 변성). 존 세로를 관통.
    final cx = rect.center.dx;
    final headW = math.min(rect.width * 0.32, 14.0);
    final topY = rect.top + rect.height * 0.15;
    final tipY = rect.bottom - rect.height * 0.15;
    final shaft = Path()
      ..moveTo(cx, topY)
      ..lineTo(cx, tipY);
    _strokeHalo(canvas, shaft, color, 2.0);
    final head = Path()
      ..moveTo(cx - headW / 2, tipY - headW * 0.7)
      ..lineTo(cx, tipY)
      ..lineTo(cx + headW / 2, tipY - headW * 0.7);
    _strokeHalo(canvas, head, color, 2.0);
  }

  @override
  bool shouldRepaint(GimmickOverlayPainter old) => old.level != level;
}
