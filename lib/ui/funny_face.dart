import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/face_service.dart';

/// 通常顔の写真に、「変顔っぽさ」を自動でつけて表示する。
///
/// 撮り直しは要らない。顔写真と、本人が合わせた「目の位置」だけを使う。
/// - ぎょろ目：目の位置に、白目と黒目を大きく重ねる（黒目は動く）
/// - ベロ：目の間隔から口の位置を見積もって、舌を出す
/// - ぷよぷよ：顔の中心がふくらんだり、へこんだりする（[animated] のとき）
///
/// 親から渡された大きさいっぱいに描く（丸く切り抜くのは親の ClipOval）。
class FunnyFace extends StatefulWidget {
  const FunnyFace({super.key, required this.asset, this.animated = true});

  final FaceAsset asset;

  /// false のときは動かさず、歪みもつけない（モザイクの小さなタイル用。軽い）
  final bool animated;

  @override
  State<FunnyFace> createState() => _FunnyFaceState();
}

class _FunnyFaceState extends State<FunnyFace> with SingleTickerProviderStateMixin {
  AnimationController? _c;

  @override
  void initState() {
    super.initState();
    if (widget.animated) {
      _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: CustomPaint(
        painter: _FunnyFacePainter(asset: widget.asset, phase: _c, warp: widget.animated),
      ),
    );
  }
}

class _FunnyFacePainter extends CustomPainter {
  _FunnyFacePainter({required this.asset, required this.phase, required this.warp}) : super(repaint: phase);

  final FaceAsset asset;

  /// 0〜1 をくり返す時計。null なら止めた絵
  final Animation<double>? phase;

  /// 顔をぷよぷよ歪ませるか
  final bool warp;

  static const int _grid = 16;
  static const Color _ink = Color(0xFF1C1233);

  /// 中心 (cx, cy)・半径 r の内側を、amp > 0 でふくらませ、amp < 0 でへこませる。
  /// 点 (x, y)（画像に対する 0〜1 の割合）が動く先を返す。r の外側は動かない。
  static Offset _bulge(double x, double y, double cx, double cy, double r, double amp) {
    final vx = x - cx;
    final vy = y - cy;
    final dist = math.sqrt(vx * vx + vy * vy);
    if (dist >= r || dist == 0) return Offset(x, y);
    final q = 1 - dist / r;
    final k = 1 + amp * q * q;
    return Offset(cx + vx * k, cy + vy * k);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    if (s <= 0) return;
    final t = phase?.value ?? 0.0;
    final img = asset.image;
    final e = asset.eyes;

    // 目の間隔 d（画像に対する割合）と、「下」向きの単位ベクトル（顔が傾いていても追従する）
    final ex = e[2] - e[0];
    final ey = e[3] - e[1];
    final d = math.max(0.05, math.sqrt(ex * ex + ey * ey));
    final ux = -ey / d;
    final uy = ex / d;
    final midX = (e[0] + e[2]) / 2;
    final midY = (e[1] + e[3]) / 2;

    // ぷよぷよの中心（鼻のあたり）と半径。画像のふちには届かないようにする
    final r = math.min(0.36, math.max(0.2, d * 1.3));
    final cx = (midX + ux * d * 0.45).clamp(r + 0.02, 1 - r - 0.02).toDouble();
    final cy = (midY + uy * d * 0.45).clamp(r + 0.02, 1 - r - 0.02).toDouble();
    final amp = warp ? 0.5 * math.sin(2 * math.pi * t) : 0.0;

    // ---- 顔写真
    if (warp) {
      final pos = <Offset>[];
      final tex = <Offset>[];
      for (var j = 0; j <= _grid; j++) {
        for (var i = 0; i <= _grid; i++) {
          final u = i / _grid;
          final v = j / _grid;
          final p = _bulge(u, v, cx, cy, r, amp);
          pos.add(Offset(p.dx * s, p.dy * s));
          tex.add(Offset(u * img.width, v * img.height));
        }
      }
      final idx = <int>[];
      for (var j = 0; j < _grid; j++) {
        for (var i = 0; i < _grid; i++) {
          final a0 = j * (_grid + 1) + i;
          final a1 = a0 + 1;
          final b0 = a0 + _grid + 1;
          final b1 = b0 + 1;
          idx
            ..add(a0)
            ..add(a1)
            ..add(b0)
            ..add(a1)
            ..add(b1)
            ..add(b0);
        }
      }
      final shader = ui.ImageShader(img, TileMode.clamp, TileMode.clamp, Matrix4.identity().storage);
      final verts = ui.Vertices(ui.VertexMode.triangles, pos, textureCoordinates: tex, indices: idx);
      canvas.drawVertices(
        verts,
        BlendMode.srcOver,
        Paint()
          ..shader = shader
          ..filterQuality = FilterQuality.medium,
      );
    } else {
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        Rect.fromLTWH(0, 0, s, s),
        Paint()..filterQuality = FilterQuality.medium,
      );
    }

    final line = math.max(1.5, s * 0.012);

    // ---- 口とベロ（口は目の間隔の 0.95 倍だけ下）
    final pm = _bulge(midX + ux * d * 0.95, midY + uy * d * 0.95, cx, cy, r, amp);
    final tw = d * 0.52 * s; // ベロの幅
    // 長さ（ハァハァ動く）。丸い枠からはみ出して切れないよう、下向きに残っている長さで頭打ちにする
    final px = pm.dx - 0.5;
    final py = pm.dy - 0.5;
    final along = px * ux + py * uy; // 口の位置を「下」へ射影
    final disc = along * along - (px * px + py * py) + 0.48 * 0.48;
    final room = (disc > 0 ? -along + math.sqrt(disc) : 0.0) * s;
    final tl = math.max(tw, math.min(room, d * (0.72 + 0.1 * math.sin(2 * math.pi * t * 2)) * s));
    canvas.save();
    canvas.translate(pm.dx * s, pm.dy * s);
    canvas.rotate(math.atan2(uy, ux) - math.pi / 2);
    // 大きく開けた口
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: tw * 1.35, height: tw * 0.6),
      Paint()..color = const Color(0xE61C1233),
    );
    final tongue = RRect.fromRectAndCorners(
      Rect.fromLTWH(-tw / 2, -tw * 0.05, tw, tl),
      topLeft: Radius.circular(tw * 0.1),
      topRight: Radius.circular(tw * 0.1),
      bottomLeft: Radius.circular(tw / 2),
      bottomRight: Radius.circular(tw / 2),
    );
    canvas.drawRRect(tongue, Paint()..color = const Color(0xFFFF6F91));
    canvas.drawRRect(
      tongue,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = line
        ..strokeJoin = StrokeJoin.round
        ..color = _ink,
    );
    canvas.drawLine(
      Offset(0, tw * 0.2),
      Offset(0, tl * 0.6),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = line * 0.7
        ..strokeCap = StrokeCap.round
        ..color = _ink,
    );
    canvas.restore();

    // ---- ぎょろ目（本人が合わせた目の位置に重ねる）
    final re = d * 0.42 * s;
    for (var k = 0; k < 2; k++) {
      final p = _bulge(e[k * 2], e[k * 2 + 1], cx, cy, r, amp);
      final c = Offset(p.dx * s, p.dy * s);
      canvas.drawCircle(c, re, Paint()..color = const Color(0xFFFFFFFF));
      canvas.drawCircle(
        c,
        re,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = line * 1.2
          ..color = _ink,
      );
      // 黒目：動くときはぐるぐる、止めた絵のときは寄り目
      final Offset off;
      if (phase != null) {
        final th = 2 * math.pi * (t * 2) + (k == 0 ? 0.0 : 1.9);
        off = Offset(math.cos(th), math.sin(th)) * (re * 0.34);
      } else {
        off = Offset(k == 0 ? 0.34 : -0.34, 0.12) * re;
      }
      canvas.drawCircle(c + off, re * 0.46, Paint()..color = _ink);
      canvas.drawCircle(c + off + Offset(-re * 0.14, -re * 0.16), re * 0.14, Paint()..color = const Color(0xFFFFFFFF));
    }
  }

  @override
  bool shouldRepaint(covariant _FunnyFacePainter old) =>
      old.asset != asset || old.phase != phase || old.warp != warp;
}
