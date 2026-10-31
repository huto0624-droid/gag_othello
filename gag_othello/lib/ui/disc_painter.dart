import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/util.dart';
import 'theme.dart';
import 'visuals.dart';

/// コマ1枚の見た目の指定
class DiscLook {
  const DiscLook({
    required this.owner,
    required this.face,
    required this.eyes,
    this.mood = Mood.normal,
    this.hot = true,
    this.rage = false,
    this.brows = false,
  });

  final int owner;
  final ui.Image face;

  /// [左目x, 左目y, 右目x, 右目y]（顔画像内の割合 0〜1）
  final List<double> eyes;
  final Mood mood;

  /// 炎の色：true=赤い炎（優勢・互角） / false=青白い炎（劣勢）
  final bool hot;

  /// キレ顔：縁が赤くなり、眉が吊り上がって震える
  final bool rage;

  /// 怒り眉だけ出す（ストレスを食らった瞬間）
  final bool brows;
}

const double _deg = math.pi / 180;

/// コマ（顔）を描く。盤・アバター・パス画面で共通。
/// [center] は円の中心、[r] は縁の外側の半径、[t] は経過秒（炎のゆらぎ・涙の落下用）、
/// [seed] はコマごとにアニメの位相をずらす値。
void paintDisc(Canvas canvas, Offset center, double r, DiscLook look, double t, {int seed = 0}) {
  final lw = math.max(1.5, r * 0.09);
  Offset c = center;
  if (look.rage) {
    c = c + Offset(math.sin(t * 27 + seed) * r * 0.04, math.cos(t * 21 + seed) * r * 0.035);
  }
  final ring = look.rage ? kGauge : ownerColor(look.owner);
  final inkFill = Paint()..color = kInk;
  canvas.drawCircle(c + Offset(0, r * 0.12), r + lw, inkFill); // ベタ影
  canvas.drawCircle(c, r + lw, inkFill);
  canvas.drawCircle(c, r, Paint()..color = ring);

  // ---- 顔写真
  final fr = r * 0.82;
  canvas.save();
  canvas.translate(c.dx, c.dy);
  double fs = 1;
  double ang = 0;
  Offset fo = Offset.zero;
  if (look.mood == Mood.smug) {
    fs = 1.05;
    ang = -4 * _deg;
  } else if (look.mood == Mood.panic) {
    fs = 0.93;
    fo = Offset(math.sin(t * 18 + seed) * r * 0.03, math.cos(t * 14 + seed) * r * 0.03);
  }
  canvas.translate(fo.dx, fo.dy);
  canvas.rotate(ang);
  canvas.scale(fs, fs);
  final faceRect = Rect.fromCircle(center: Offset.zero, radius: fr);
  canvas.save();
  canvas.clipPath(Path()..addOval(faceRect));
  canvas.drawRect(faceRect, Paint()..color = kWhite);
  final img = look.face;
  canvas.drawImageRect(
    img,
    Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
    faceRect,
    Paint()..filterQuality = FilterQuality.medium,
  );
  canvas.restore();
  canvas.drawCircle(
    Offset.zero,
    fr,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = lw
      ..color = kInk,
  );
  canvas.restore();

  // ---- 表情の重ね物（円の箱に対する % で位置を決める）
  final box = 2 * r;
  Offset pt(double xPct, double yPct) => Offset(c.dx - r + xPct / 100 * box, c.dy - r + yPct / 100 * box);
  final e1x = 9 + look.eyes[0] * 82;
  final e1y = 9 + look.eyes[1] * 82;
  final e2x = 9 + look.eyes[2] * 82;
  final e2y = 9 + look.eyes[3] * 82;

  if (look.mood == Mood.smug) {
    _glasses(canvas, pt((e1x + e2x) / 2, (e1y + e2y) / 2), ((e2x - e1x) + 24) / 100 * box, 0.21 * box, lw);
  }
  if (look.mood == Mood.panic) {
    final tw = 0.07 * box;
    final th = 0.11 * box;
    for (var k = 0; k < 2; k++) {
      final ph = ((t / 1.1) + k * 0.45 + seed * 0.07) % 1.0;
      final alpha = ph < 0.25 ? ph / 0.25 : 1 - (ph - 0.25) / 0.75;
      final base = pt(k == 0 ? e1x : e2x, (k == 0 ? e1y : e2y) + 7);
      final s = 0.6 + 0.4 * ph;
      _drop(canvas, Offset(base.dx, base.dy + th / 2 + ph * 1.6 * th), tw * s, th * s, 0x8FE3FF, alpha, lw * 0.7, 0.0);
    }
    final sw = 0.09 * box;
    final sh = 0.14 * box;
    final bob = (math.sin(t * 2 * math.pi / 1.2 + seed) * 0.5 + 0.5) * 0.10 * sh;
    final sp = pt(84.5, 16);
    _drop(canvas, Offset(sp.dx, sp.dy + bob), sw, sh, 0xB6ECFF, 1.0, lw, 18 * _deg);
  }
  if (look.rage || look.brows) {
    _brow(canvas, pt(e1x, e1y - 15), 0.26 * box, 0.07 * box, 22 * _deg);
    _brow(canvas, pt(e2x, e2y - 15), 0.26 * box, 0.07 * box, -22 * _deg);
  }
  if (look.mood == Mood.fire) {
    final w = 0.27 * box;
    final h = 0.36 * box;
    final a = look.hot ? kHotA : kColdA;
    final b = look.hot ? kHotB : kWhite;
    for (var k = 0; k < 2; k++) {
      final e = pt(k == 0 ? e1x : e2x, k == 0 ? e1y : e2y);
      // CSS: translate(-50%, -64%) → 箱の下端中央が目の少し下
      final bottom = Offset(e.dx, e.dy + 0.36 * h);
      final off = k == 1 ? 0.5 : 0.0;
      _flame(canvas, bottom, w, h, a, b, (t / 0.42 + off + seed * 0.13) % 1.0, (t / 0.33 + off * 1.3 + seed * 0.11) % 1.0);
    }
  }
}

void _glasses(Canvas canvas, Offset center, double w, double h, double lw) {
  final top = center.dy - h / 2;
  final lensW = w * 0.45;
  final left = Rect.fromLTWH(center.dx - w / 2, top, lensW, h);
  final right = Rect.fromLTWH(center.dx + w / 2 - lensW, top, lensW, h);
  final bridge = Paint()
    ..color = kInk
    ..strokeWidth = math.max(1.5, lw)
    ..strokeCap = StrokeCap.round;
  canvas.drawLine(Offset(left.right, center.dy - h * 0.12), Offset(right.left, center.dy - h * 0.12), bridge);
  for (final r in <Rect>[left, right]) {
    final rr = RRect.fromRectAndCorners(
      r,
      topLeft: Radius.circular(h * 0.25),
      topRight: Radius.circular(h * 0.25),
      bottomLeft: Radius.circular(h * 0.55),
      bottomRight: Radius.circular(h * 0.55),
    );
    canvas.drawRRect(rr, Paint()..color = const Color(0xFF0B0818));
    canvas.save();
    canvas.clipRRect(rr);
    final leg = (r.width + r.height) * 0.28;
    final hi = Path()
      ..moveTo(r.left, r.top)
      ..lineTo(r.left + leg, r.top)
      ..lineTo(r.left, r.top + leg)
      ..close();
    canvas.drawPath(hi, Paint()..color = const Color(0xFF5B5384));
    canvas.restore();
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, lw * 0.9)
        ..color = kInk,
    );
  }
}

/// しずく型（涙・汗）
void _drop(Canvas canvas, Offset c, double w, double h, int fillRgb, double alpha, double lw, double rotation) {
  final a = clampInt((alpha * 255).round(), 0, 255);
  if (a <= 0) return;
  canvas.save();
  canvas.translate(c.dx, c.dy);
  canvas.rotate(rotation);
  final path = Path()
    ..moveTo(0, -h / 2)
    ..cubicTo(w * 0.15, -h * 0.2, w / 2, h * 0.05, w / 2, h * 0.2)
    ..arcToPoint(Offset(-w / 2, h * 0.2), radius: Radius.circular(w / 2), clockwise: true)
    ..cubicTo(-w / 2, h * 0.05, -w * 0.15, -h * 0.2, 0, -h / 2)
    ..close();
  canvas.drawPath(path, Paint()..color = Color(0xFF000000 | fillRgb).withAlpha(a));
  canvas.drawPath(
    path,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = lw
      ..color = kInk.withAlpha(a),
  );
  canvas.restore();
}

void _brow(Canvas canvas, Offset c, double w, double h, double rotation) {
  canvas.save();
  canvas.translate(c.dx, c.dy);
  canvas.rotate(rotation);
  canvas.drawRRect(
    RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: w, height: h), Radius.circular(h * 0.5)),
    Paint()..color = kInk,
  );
  canvas.restore();
}

const List<List<double>> _flameShape = <List<double>>[
  <double>[0.50, 0.00],
  <double>[0.68, 0.26],
  <double>[0.90, 0.50],
  <double>[0.90, 0.76],
  <double>[0.72, 0.96],
  <double>[0.50, 1.00],
  <double>[0.28, 0.96],
  <double>[0.10, 0.76],
  <double>[0.10, 0.50],
  <double>[0.32, 0.28],
];

// ゆらぎのキーフレーム [sx, sy, skewDeg]
const List<List<double>> _flick = <List<double>>[
  <double>[1.0, 1.0, 0.0],
  <double>[0.90, 1.16, -7.0],
  <double>[1.07, 0.93, 5.0],
  <double>[0.95, 1.12, -3.0],
  <double>[1.0, 1.0, 0.0],
];

List<double> _flickAt(double phase) {
  final x = phase * 4;
  final i = math.min(3, x.floor());
  final f = x - i;
  final a = _flick[i];
  final b = _flick[i + 1];
  return <double>[a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f];
}

Path _flamePath(double left, double top, double w, double h) {
  final p = Path();
  for (var i = 0; i < _flameShape.length; i++) {
    final x = left + _flameShape[i][0] * w;
    final y = top + _flameShape[i][1] * h;
    if (i == 0) {
      p.moveTo(x, y);
    } else {
      p.lineTo(x, y);
    }
  }
  p.close();
  return p;
}

/// 炎の目。[bottom] は炎の下端中央（ゆらぎの支点）
void _flame(Canvas canvas, Offset bottom, double w, double h, Color outer, Color inner, double po, double pin) {
  final fo = _flickAt(po);
  canvas.save();
  canvas.translate(bottom.dx, bottom.dy);
  final m = Matrix4.identity();
  m.setEntry(0, 1, math.tan(fo[2] * _deg));
  canvas.transform(m.storage);
  canvas.scale(fo[0], fo[1]);
  canvas.drawPath(_flamePath(-w / 2, -h, w, h), Paint()..color = outer);
  canvas.restore();

  final fi = _flickAt(pin);
  canvas.save();
  canvas.translate(bottom.dx, bottom.dy);
  final m2 = Matrix4.identity();
  m2.setEntry(0, 1, math.tan(fi[2] * _deg));
  canvas.transform(m2.storage);
  canvas.scale(fi[0], fi[1]);
  // 内側の炎：外側の箱の 左右20% / 上34% を除いた範囲
  canvas.drawPath(_flamePath(-w / 2 + 0.2 * w, -h + 0.34 * h, 0.6 * w, 0.66 * h), Paint()..color = inner);
  canvas.restore();
}

/// アバターなど、コマ1枚だけを描く CustomPaint 用
class SingleDiscPainter extends CustomPainter {
  SingleDiscPainter({required this.look, required this.clock, this.seed = 0}) : super(repaint: clock);

  final DiscLook look;
  final Animation<double> clock;
  final int seed;

  /// 時計 AnimationController の長さ（秒）。経過秒 = value * clockSeconds
  static const double clockSeconds = 3600;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2 - 4;
    paintDisc(canvas, size.center(Offset.zero), r, look, clock.value * clockSeconds, seed: seed);
  }

  @override
  bool shouldRepaint(covariant SingleDiscPainter old) => old.look != look || old.seed != seed;
}
