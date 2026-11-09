import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/engine.dart';
import '../core/util.dart';
import 'disc_painter.dart';
import 'effects.dart';
import 'game_controller.dart';
import 'theme.dart';
import 'visuals.dart';

const double _deg = math.pi / 180;

/// プレイヤーパネル：アバター・名前・枚数・ストレスゲージ・台パンボタン。
/// ストレスを食らった瞬間の演出（揺れ・怒りマーク・赤フラッシュ・数字ポップ）もここで流す。
class PlayerPanel extends StatefulWidget {
  const PlayerPanel({super.key, required this.ctl, required this.p, required this.clock});

  final GameController ctl;
  final int p;
  final Animation<double> clock;

  @override
  State<PlayerPanel> createState() => _PlayerPanelState();
}

class _PlayerPanelState extends State<PlayerPanel> with TickerProviderStateMixin {
  static const int _hitMs = 1700;
  late final AnimationController _hit;
  late final AnimationController _nudge;
  StressFx? _fx;
  int _nudgeSeen = 0;

  @override
  void initState() {
    super.initState();
    _hit = AnimationController(vsync: this, duration: const Duration(milliseconds: _hitMs), value: 1.0);
    _nudge = AnimationController(vsync: this, duration: const Duration(milliseconds: 220), value: 1.0);
    _fx = widget.ctl.stressFx[widget.p - 1];
    _nudgeSeen = widget.ctl.nudgeIds[widget.p - 1];
  }

  @override
  void didUpdateWidget(covariant PlayerPanel old) {
    super.didUpdateWidget(old);
    final fx = widget.ctl.stressFx[widget.p - 1];
    if (fx != null && (_fx == null || fx.id != _fx!.id)) {
      _fx = fx;
      _hit.forward(from: 0.0);
    }
    final n = widget.ctl.nudgeIds[widget.p - 1];
    if (n != _nudgeSeen) {
      _nudgeSeen = n;
      _nudge.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _hit.dispose();
    _nudge.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctl = widget.ctl;
    final p = widget.p;
    final ps = ctl.panels[p - 1];
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[_hit, _nudge]),
      builder: (BuildContext context, Widget? _) {
        final fx = _fx;
        final hitting = fx != null && fx.level >= 2 && _hit.value < 1;
        // 揺れ：lv2=0.75秒 / lv3=0.95秒
        var dx = 0.0;
        var dy = 0.0;
        var sc = 1.0;
        var flash = 0.0;
        if (hitting && fx != null) {
          final big = fx.level == 3;
          final dur = big ? 950.0 : 750.0;
          final t2 = clampD(_hit.value * _hitMs / dur, 0, 1);
          final amp = big ? 14.0 : 8.0;
          final decay = 1 - t2;
          dx = math.sin(t2 * 2 * math.pi * 3) * amp * decay;
          dy = math.cos(t2 * 2 * math.pi * 3) * amp * 0.35 * decay;
          sc = 1 + (big ? 0.06 : 0.035) * decay;
          flash = 0.6 * (1 - clampD(_hit.value * _hitMs / 900, 0, 1));
        }
        if (_nudge.value < 1) {
          dx += math.sin(_nudge.value * 2 * math.pi * 2) * 5 * (1 - _nudge.value);
        }
        return Transform.translate(
          offset: Offset(dx, dy),
          child: Transform.scale(
            scale: sc,
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                InkBox(
                  color: ps.active ? kPaper2 : kPaper,
                  outline: ps.active ? ownerColor(p) : null,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      _avatar(ps, hitting),
                      const SizedBox(width: 12),
                      Expanded(child: _middle(ps)),
                      const SizedBox(width: 12),
                      _DaipanButton(ctl: ctl, p: p, clock: widget.clock),
                    ],
                  ),
                ),
                if (flash > 0.01)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Color.fromARGB((flash * 255).round(), 255, 38, 56),
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                if (fx != null && fx.level >= 2 && _hit.value < 1) _spop(fx),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _avatar(PanelState ps, bool hitting) {
    final ctl = widget.ctl;
    final p = widget.p;
    final fx = _fx;
    final look = ctl.lookFor(p, mood: ps.mood, rage: ps.rage || hitting);
    final burst = hitting && fx != null && fx.level == 3 && _hit.value * _hitMs < 800;

    // 怒りマーク：ストレスがたまっている間は脈打ち、食らった瞬間はポンと弾ける
    double veinScale = 0;
    double veinAngle = 0;
    double veinOpacity = 0;
    if (_hit.value < 1 && fx != null && fx.level >= 2) {
      final t = _hit.value;
      if (t < 0.15) {
        final k = t / 0.15;
        veinScale = 0.2 + 1.7 * k;
        veinAngle = (-30 + 38 * k) * _deg;
        veinOpacity = k;
      } else if (t < 0.35) {
        final k = (t - 0.15) / 0.2;
        veinScale = 1.9 - 0.55 * k;
        veinAngle = (8 - 12 * k) * _deg;
        veinOpacity = 1;
      } else if (t < 0.85) {
        veinScale = 1.35 + 0.05 * ((t - 0.35) / 0.5);
        veinAngle = -4 * _deg * (1 - (t - 0.35) / 0.5);
        veinOpacity = 1;
      } else {
        veinScale = 1.4;
        veinOpacity = 1 - (t - 0.85) / 0.15;
      }
    } else if (ps.tense) {
      final tt = widget.clock.value * SingleDiscPainter.clockSeconds;
      final k = (math.sin(tt * 2 * math.pi / 1.0) * 0.5 + 0.5);
      veinScale = 0.9 + 0.28 * k;
      veinAngle = (-8 + 14 * k) * _deg;
      veinOpacity = 1;
    }

    return SizedBox(
      width: 64,
      height: 64,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          if (burst)
            Positioned(
              left: -48,
              top: -48,
              child: RayBurst(
                key: ValueKey<int>(fx!.id),
                color: kGauge,
                extent: 160,
                duty: 4,
                period: 12,
                stops: const <double>[0.20, 0.38, 0.68],
                ms: 700,
              ),
            ),
          Positioned.fill(
            child: Semantics(
              label: '${ps.name} の顔',
              child: CustomPaint(painter: SingleDiscPainter(look: look, clock: widget.clock, seed: p)),
            ),
          ),
          if (veinOpacity > 0.01)
            Positioned(
              right: -12,
              top: -12,
              child: Opacity(
                opacity: clampD(veinOpacity, 0, 1),
                child: Transform.rotate(
                  angle: veinAngle,
                  child: Transform.scale(
                    scale: veinScale,
                    child: const SizedBox(width: 36, height: 36, child: CustomPaint(painter: _VeinPainter())),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _middle(PanelState ps) {
    final fx = _fx;
    final sealedOrMax = ps.sealed || ps.max;
    // lv1 の小さなポップ（ゲージの上に「+10 角を取られた！」）
    Widget? gpop;
    if (fx != null && _hit.value < 1) {
      final t = clampD(_hit.value * _hitMs / 1400, 0, 1);
      if (t < 1) {
        double o;
        double dy;
        double s;
        if (t < 0.15) {
          o = t / 0.15;
          dy = 8 * (1 - t / 0.15);
          s = 0.6 + 0.5 * (t / 0.15);
        } else if (t < 0.8) {
          o = 1;
          dy = 0;
          s = 1.1 - 0.1 * clampD((t - 0.15) / 0.1, 0, 1);
        } else {
          final k = (t - 0.8) / 0.2;
          o = 1 - k;
          dy = -8 * k;
          s = 1;
        }
        gpop = Positioned(
          right: 0,
          top: -22,
          child: Opacity(
            opacity: clampD(o, 0, 1),
            child: Transform.translate(
              offset: Offset(0, dy),
              child: Transform.scale(
                scale: s,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: kPaper,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: kInk, width: 2),
                  ),
                  child: Text('+${fx.total} ${fx.label}', style: displayStyle(12, color: kGauge)),
                ),
              ),
            ),
          ),
        );
      }
    }
    // ゲージの「バンッ」と伸びる動き
    var bump = 1.0;
    if (fx != null && _hit.value * _hitMs < 700) {
      final k = _hit.value * _hitMs / 700;
      if (k < 0.14) {
        bump = 1 + 1.1 * (k / 0.14);
      } else if (k < 0.4) {
        bump = 2.1 - 0.55 * ((k - 0.14) / 0.26);
      } else {
        bump = 1.55 - 0.55 * ((k - 0.4) / 0.6);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Flexible(
              child: Text(ps.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: displayStyle(16)),
            ),
            const SizedBox(width: 8),
            Text('${ps.count}', style: displayStyle(22)),
            Text('枚', style: bodyStyle(13)),
          ],
        ),
        const SizedBox(height: 4),
        Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Transform.scale(
              scaleY: bump,
              child: _Gauge(value: ps.gauge, sealed: ps.sealed),
            ),
            if (gpop != null) gpop,
          ],
        ),
        const SizedBox(height: 2),
        Text(
          ps.note,
          maxLines: ps.sealed ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          style: bodyStyle(11.5, color: sealedOrMax ? kGauge : kInk, weight: sealedOrMax ? FontWeight.w900 : FontWeight.w700),
        ),
      ],
    );
  }

  Widget _spop(StressFx fx) {
    final big = fx.level == 3;
    final dur = big ? 1700.0 : 1500.0;
    final t = clampD(_hit.value * _hitMs / dur, 0, 1);
    double o;
    double dy;
    double s;
    if (t < 0.14) {
      final k = t / 0.14;
      o = k;
      dy = 0.2 * (1 - k) + 0.0;
      s = 0.2 + 1.1 * k;
    } else if (t < 0.26) {
      o = 1;
      dy = 0;
      s = 1.3 - 0.3 * ((t - 0.14) / 0.12);
    } else if (t < 0.78) {
      o = 1;
      dy = -0.06 * ((t - 0.26) / 0.52);
      s = 1;
    } else {
      final k = (t - 0.78) / 0.22;
      o = 1 - k;
      dy = -0.06 - 0.39 * k;
      s = 1;
    }
    return Positioned.fill(
      child: IgnorePointer(
        child: Opacity(
          opacity: clampD(o, 0, 1),
          child: FractionalTranslation(
            translation: Offset(0, dy),
            child: Center(
              child: Transform.rotate(
                angle: -5 * _deg,
                child: Transform.scale(
                  scale: s,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      OutlinedText('ストレス +${fx.total}', size: big ? 34 : 24, fill: kGauge, stroke: big ? 6 : 5),
                      OutlinedText(fx.label, size: 14, fill: kPaper, stroke: 5, body: true, shadow: false),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ストレスゲージ（赤固定）。ヒートアップ中はグレーになって止まる。
class _Gauge extends StatelessWidget {
  const _Gauge({required this.value, required this.sealed});

  final int value;
  final bool sealed;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 16,
      decoration: BoxDecoration(
        color: sealed ? const Color(0xFFD9D4E6) : kGaugeBg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: kInk, width: 3),
      ),
      clipBehavior: Clip.antiAlias,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: value / GaugeCfg.max),
        duration: const Duration(milliseconds: 500),
        curve: const Cubic(0.3, 1.3, 0.5, 1.0),
        builder: (BuildContext context, double v, Widget? _) {
          return Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: clampD(v, 0, 1),
              heightFactor: 1,
              child: ColoredBox(color: sealed ? const Color(0xFF8D859F) : kGauge),
            ),
          );
        },
      ),
    );
  }
}

/// 怒りマーク（#）。ストレスがたまると顔の横に出る
class _VeinPainter extends CustomPainter {
  const _VeinPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 32;
    canvas.scale(k, k);
    final path = Path()
      ..moveTo(5, 13)
      ..quadraticBezierTo(13, 13, 13, 5)
      ..moveTo(19, 5)
      ..quadraticBezierTo(19, 13, 27, 13)
      ..moveTo(5, 19)
      ..quadraticBezierTo(13, 19, 13, 27)
      ..moveTo(19, 27)
      ..quadraticBezierTo(19, 19, 27, 19);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 8
        ..color = kInk,
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 4
        ..color = kGauge,
    );
  }

  @override
  bool shouldRepaint(covariant _VeinPainter old) => false;
}

/// 台パンボタン（盤の石をひっくり返す技）。長押し（0.9秒）で発動。ゲージが足りない／ヒートアップ中は押せない。
class _DaipanButton extends StatelessWidget {
  const _DaipanButton({required this.ctl, required this.p, required this.clock});

  final GameController ctl;
  final int p;
  final Animation<double> clock;

  @override
  Widget build(BuildContext context) {
    final ps = ctl.panels[p - 1];
    final holding = ctl.hold != null && ctl.hold!.p == p;
    final cpuSide = ctl.isCpu && p == 2;
    final sealed = ps.sealed;

    Color bg = const Color(0xFFE8E3F2);
    Color fg = const Color(0xFF6B6480);
    if (sealed) {
      bg = const Color(0xFFC9C3D9);
    } else if (ps.max) {
      bg = kGauge;
      fg = kWhite;
    }
    if (holding) fg = kWhite;

    Widget face = Container(
      width: 88,
      height: 64,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kInk, width: 3),
        boxShadow: sealed
            ? const <BoxShadow>[]
            : const <BoxShadow>[BoxShadow(color: kInk, offset: Offset(3, 3), blurRadius: 0)],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          // 長押しの進み具合（暗い赤が左から満ちる）
          Positioned.fill(
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(end: holding ? 1.0 : 0.0),
              duration: Duration(milliseconds: holding ? Cfg.holdMs : 120),
              curve: Curves.linear,
              builder: (BuildContext context, double v, Widget? _) {
                return Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: clampD(v, 0, 1),
                    heightFactor: 1,
                    child: const ColoredBox(color: Color(0xFF7A0010)),
                  ),
                );
              },
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('台パン', style: displayStyle(18, color: fg, height: 1.1)),
              Text(ps.btnSub, textAlign: TextAlign.center, style: bodyStyle(10.5, color: fg, height: 1.2)),
            ],
          ),
          if (sealed) const Positioned.fill(child: _Chain()),
        ],
      ),
    );

    if (ps.max && !holding && !sealed) {
      face = AnimatedBuilder(
        animation: clock,
        builder: (BuildContext context, Widget? child) {
          final tt = clock.value * SingleDiscPainter.clockSeconds;
          final k = math.sin(tt * 2 * math.pi / 0.8) * 0.5 + 0.5;
          return Transform.rotate(angle: -1.5 * _deg * k, child: Transform.scale(scale: 1 + 0.07 * k, child: child));
        },
        child: face,
      );
    }

    return IgnorePointer(
      ignoring: cpuSide, // CPU の台パンボタンは人間が押せない
      child: Semantics(
        button: true,
        enabled: ps.btnReady,
        label: cpuSide ? 'CPUの台パン（操作できません）' : '${p}Pの台パン。長押しで、盤の石をひっくり返して同数にする',
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (PointerDownEvent e) => ctl.startHold(p),
          onPointerUp: (PointerUpEvent e) => ctl.cancelHold(p),
          onPointerCancel: (PointerCancelEvent e) => ctl.cancelHold(p),
          child: face,
        ),
      ),
    );
  }
}

/// 台パン封印中の鎖と南京錠（斜めの縞＋黄色い錠）
class _Chain extends StatelessWidget {
  const _Chain();

  @override
  Widget build(BuildContext context) => const CustomPaint(painter: _ChainPainter());
}

class _ChainPainter extends CustomPainter {
  const _ChainPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final a = Paint()..color = const Color(0xF28F96AA);
    final b = Paint()..color = const Color(0xF250566C);
    canvas.drawRect(Offset.zero & size, a);
    // 斜めの縞
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-45 * _deg);
    final span = size.width + size.height;
    for (double x = -span; x < span; x += 14) {
      canvas.drawRect(Rect.fromLTWH(x + 7, -span, 7, span * 2), b);
    }
    canvas.restore();
    // 南京錠
    final c = size.center(Offset.zero);
    final body = RRect.fromRectAndRadius(Rect.fromCenter(center: c.translate(0, 3), width: 26, height: 19), const Radius.circular(4));
    canvas.drawRRect(body, Paint()..color = kHotB);
    canvas.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = kInk,
    );
    final shackle = Path()
      ..moveTo(c.dx - 5, c.dy - 6.5)
      ..lineTo(c.dx - 5, c.dy - 12)
      ..arcToPoint(Offset(c.dx + 5, c.dy - 12), radius: const Radius.circular(5), clockwise: true)
      ..lineTo(c.dx + 5, c.dy - 6.5);
    canvas.drawPath(
      shackle,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = kInk,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ChainPainter old) => false;
}
