import 'dart:math' as math;
import 'dart:ui' show BlurStyle, MaskFilter;

import 'package:flutter/material.dart';

import 'disc_painter.dart';
import 'game_controller.dart';
import 'theme.dart';

/// 8x8 の盤。描画は CustomPaint 1枚で行い、タップはマス番号に変換して渡す。
/// 盤の外側には右下 5px のベタ影が出るので、[side] のうち 5px は影用に空けてある。
class BoardView extends StatelessWidget {
  const BoardView({
    super.key,
    required this.ctl,
    required this.clock,
    required this.side,
  });

  final GameController ctl;

  /// 経過秒の元になる時計（炎・涙のアニメ用）
  final Animation<double> clock;
  final double side;

  static const double _shadow = 5;
  static const double _pad = 10; // 枠4 + 余白6
  static const double _gap = 2;

  int _hit(Offset p) {
    final bs = side - _shadow;
    final cell = (bs - 2 * _pad - 7 * _gap) / 8;
    final x = p.dx - _pad;
    final y = p.dy - _pad;
    if (x < 0 || y < 0) return -1;
    final step = cell + _gap;
    final col = (x / step).floor();
    final row = (y / step).floor();
    if (col < 0 || col > 7 || row < 0 || row > 7) return -1;
    return row * 8 + col;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'オセロ盤',
      child: SizedBox(
        width: side,
        height: side,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (TapUpDetails d) {
            final i = _hit(d.localPosition);
            if (i >= 0) ctl.onCell(i);
          },
          child: CustomPaint(
            size: Size(side, side),
            painter: BoardPainter(ctl: ctl, clock: clock),
          ),
        ),
      ),
    );
  }
}

class BoardPainter extends CustomPainter {
  BoardPainter({required this.ctl, required this.clock})
      : super(repaint: Listenable.merge(<Listenable>[ctl.boardTick, ctl, clock]));

  final GameController ctl;
  final Animation<double> clock;

  @override
  void paint(Canvas canvas, Size size) {
    const double shadow = BoardView._shadow;
    const double pad = BoardView._pad;
    const double gap = BoardView._gap;
    final bs = size.width - shadow;
    final cell = (bs - 2 * pad - 7 * gap) / 8;
    final t = clock.value * SingleDiscPainter.clockSeconds;
    final ink = Paint()..color = kInk;

    // 盤の枠とベタ影
    final outer = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, bs, bs), const Radius.circular(14));
    canvas.drawRRect(outer.shift(const Offset(shadow, shadow)), ink);
    canvas.drawRRect(outer, ink);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(4, 4, bs - 8, bs - 8), const Radius.circular(10)),
      Paint()..color = kFeltD,
    );

    final turnColor = ownerColor(ctl.g.turn);
    final feltPaint = Paint()..color = kFelt;
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = kFeltD;
    // 置けるマスの光。最初の数秒は消えていて、そのあとうっすらフェードインする
    final hs = ctl.hintStrength;
    final lastLine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = kWhite;

    Rect rectOf(int i) => Rect.fromLTWH(pad + (i & 7) * (cell + gap), pad + (i >> 3) * (cell + gap), cell, cell);

    // マス・ヒント・最後の手の印
    for (var i = 0; i < 64; i++) {
      var rc = rectOf(i);
      final nope = ctl.cells[i].nope;
      if (nope > 0) {
        rc = rc.shift(Offset(math.sin(nope * math.pi * 4) * 3 * (1 - nope), 0));
      }
      canvas.drawRRect(RRect.fromRectAndRadius(rc, const Radius.circular(6)), feltPaint);
      canvas.drawRRect(RRect.fromRectAndRadius(rc.deflate(1), const Radius.circular(5)), edge);
      if (hs > 0 && ctl.hints.contains(i)) {
        // ぼんやりした光の輪（にじみ）と、うすい印
        final halo = Paint()
          ..color = turnColor.withAlpha((hs * 120).round())
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, cell * 0.14);
        canvas.drawCircle(rc.center, cell * 0.26, halo);
        canvas.drawCircle(rc.center, cell * 0.15, Paint()..color = turnColor.withAlpha((hs * 96).round()));
      }
      if (i == ctl.lastIdx && ctl.cells[i].owner != 0) {
        final ring = Rect.fromCircle(center: rc.center, radius: cell / 2 - 2);
        final a0 = t * 2 * math.pi / 7;
        const n = 18;
        for (var k = 0; k < n; k++) {
          canvas.drawArc(ring, a0 + k * 2 * math.pi / n, 2 * math.pi / n * 0.55, false, lastLine);
        }
      }
    }

    // コマ。飛んでいるものは手前に重ねる
    final looks = <int, DiscLook>{1: ctl.lookFor(1), 2: ctl.lookFor(2)};
    final r = cell * 0.43;
    for (var pass = 0; pass < 2; pass++) {
      for (var i = 0; i < 64; i++) {
        final cv = ctl.cells[i];
        if (cv.owner == 0 && cv.flip == 0) continue;
        final flying = cv.offset.dx != 0 || cv.offset.dy != 0;
        if ((pass == 0) == flying) continue;
        if (cv.opacity <= 0 || cv.scale <= 0) continue;
        final rc = rectOf(i);
        final center = rc.center + Offset(cv.offset.dx * bs, cv.offset.dy * bs);
        var sx = 1.0;
        var sy = 1.0;
        var shown = cv.owner;
        if (cv.flip > 0) {
          final a = cv.flip * math.pi;
          final pop = 1 + 0.1 * math.sin(a);
          sx = math.cos(a).abs() * pop;
          sy = pop;
          shown = cv.flip >= 0.5 ? cv.toOwner : cv.owner;
        }
        if (shown == 0) continue;
        canvas.save();
        canvas.translate(center.dx, center.dy);
        if (cv.rot != 0) canvas.rotate(cv.rot);
        canvas.scale(math.max(0.001, sx * cv.scale), sy * cv.scale);
        final fade = cv.opacity < 1;
        if (fade) {
          canvas.saveLayer(
            Rect.fromCircle(center: Offset.zero, radius: r * 1.6),
            Paint()..color = Color.fromARGB((cv.opacity * 255).round(), 255, 255, 255),
          );
        }
        paintDisc(canvas, Offset.zero, r, looks[shown]!, t, seed: i);
        if (fade) canvas.restore();
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant BoardPainter old) => old.ctl != ctl;
}
