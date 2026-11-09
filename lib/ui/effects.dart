import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'disc_painter.dart';
import 'theme.dart';
import 'visuals.dart';

const double _deg = math.pi / 180;

double _lerp(double a, double b, double t) => a + (b - a) * t;

// ---------------------------------------------------------------------------
// 画面中央の大きな文字（かど！ / ドーン！ / パス！ ...）
// ---------------------------------------------------------------------------

class BannerWidget extends StatefulWidget {
  const BannerWidget({super.key, required this.spec, required this.fontSize});

  final BannerSpec spec;
  final double fontSize;

  @override
  State<BannerWidget> createState() => _BannerWidgetState();
}

class _BannerWidgetState extends State<BannerWidget> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (widget.spec.seconds * 1000).round()),
    )..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Color get _fill {
    switch (widget.spec.style) {
      case BannerStyle.red:
        return kGauge;
      case BannerStyle.gold:
        return kHotB;
      case BannerStyle.paper:
        return kPaper;
    }
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: AnimatedBuilder(
          animation: _c,
          builder: (BuildContext context, Widget? child) {
            final t = _c.value;
            double scale;
            double opacity;
            double dy = 0;
            if (t < 0.18) {
              final p = Curves.easeOut.transform(t / 0.18);
              scale = _lerp(0.2, 1.15, p);
              opacity = math.min(1.0, p * 1.4);
            } else if (t < 0.30) {
              scale = _lerp(1.15, 1.0, (t - 0.18) / 0.12);
              opacity = 1;
            } else if (t < 0.80) {
              scale = 1;
              opacity = 1;
            } else {
              final p = (t - 0.8) / 0.2;
              scale = 1;
              opacity = 1 - p;
              dy = -0.2 * widget.fontSize * 1.2 * p;
            }
            return Opacity(
              opacity: opacity.clamp(0.0, 1.0).toDouble(),
              child: Transform.translate(
                offset: Offset(0, dy),
                child: Transform.rotate(
                  angle: -4 * _deg,
                  child: Transform.scale(scale: scale, child: child),
                ),
              ),
            );
          },
          child: OutlinedText(widget.spec.text, size: widget.fontSize, fill: _fill, stroke: widget.fontSize * 0.16),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 放射状の集中線（台パンの衝撃・ストレス大）
// ---------------------------------------------------------------------------

class RayBurst extends StatefulWidget {
  const RayBurst({
    super.key,
    required this.color,
    required this.extent,
    this.duty = 3.5,
    this.period = 11,
    this.stops = const <double>[0.20, 0.52, 0.71],
    this.ms = 600,
  });

  final Color color;

  /// 描く範囲の一辺（px）
  final double extent;

  /// 1本の線の角度 / 繰り返しの角度（度）
  final double duty;
  final double period;

  /// 中心側の透明の終わり / 最も濃い位置 / 外側の透明の始まり（半径に対する割合）
  final List<double> stops;
  final int ms;

  @override
  State<RayBurst> createState() => _RayBurstState();
}

class _RayBurstState extends State<RayBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: Duration(milliseconds: widget.ms))..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        width: widget.extent,
        height: widget.extent,
        child: CustomPaint(painter: _RayPainter(_c, widget.color, widget.duty, widget.period, widget.stops)),
      ),
    );
  }
}

class _RayPainter extends CustomPainter {
  _RayPainter(this.anim, this.color, this.duty, this.period, this.stops) : super(repaint: anim);

  final Animation<double> anim;
  final Color color;
  final double duty;
  final double period;
  final List<double> stops;

  @override
  void paint(Canvas canvas, Size size) {
    final t = anim.value;
    final a = t < 0.25 ? 0.9 * (t / 0.25) : 0.9 * (1 - (t - 0.25) / 0.75);
    if (a <= 0) return;
    final radius = size.width / 2;
    final peak = color.withAlpha((a * 255).round());
    final clear = color.withAlpha(0);
    final shader = ui.Gradient.radial(
      Offset.zero,
      radius,
      <Color>[clear, clear, peak, clear, clear],
      <double>[0.0, stops[0], stops[1], stops[2], 1.0],
    );
    final paint = Paint()..shader = shader;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(14 * _deg * t);
    final sc = 0.3 + 1.05 * t;
    canvas.scale(sc, sc);
    final n = (360 / period).floor();
    final rect = Rect.fromCircle(center: Offset.zero, radius: radius);
    for (var k = 0; k < n; k++) {
      canvas.drawArc(rect, k * period * _deg, duty * _deg, true, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RayPainter old) => false;
}

// ---------------------------------------------------------------------------
// 画面の四隅を染めるビネット（楕円のグラデーション）
// ---------------------------------------------------------------------------

class VignetteBox extends StatelessWidget {
  const VignetteBox({super.key, required this.edge, this.inner = 0.3});

  /// 外側の色
  final Color edge;

  /// 中心から何割まで透明か
  final double inner;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(child: SizedBox.expand(child: CustomPaint(painter: _VignettePainter(edge, inner))));
  }
}

class _VignettePainter extends CustomPainter {
  const _VignettePainter(this.edge, this.inner);

  final Color edge;
  final double inner;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final c = size.center(Offset.zero);
    final rx = size.width / 2 * 1.4142;
    final m = Matrix4.identity();
    m.translate(c.dx, c.dy);
    m.scale(1.0, size.height / size.width);
    m.translate(-c.dx, -c.dy);
    final shader = ui.Gradient.radial(
      c,
      rx,
      <Color>[edge.withAlpha(0), edge.withAlpha(0), edge],
      <double>[0.0, inner, 1.0],
      TileMode.clamp,
      m.storage,
    );
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant _VignettePainter old) => old.edge != edge || old.inner != inner;
}

// ---------------------------------------------------------------------------
// [id] が変わるたびに1回だけ流れる、フェードアウトする重ね物（画面フラッシュなど）
// ---------------------------------------------------------------------------

class PulseOverlay extends StatefulWidget {
  const PulseOverlay({
    super.key,
    required this.id,
    required this.ms,
    required this.opacityAt,
    required this.child,
  });

  final int id;
  final int ms;

  /// 経過 0〜1 に対する不透明度
  final double Function(double t) opacityAt;
  final Widget child;

  @override
  State<PulseOverlay> createState() => _PulseOverlayState();
}

class _PulseOverlayState extends State<PulseOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: Duration(milliseconds: widget.ms), value: 1.0);
  }

  @override
  void didUpdateWidget(covariant PulseOverlay old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id) {
      _c.duration = Duration(milliseconds: widget.ms);
      _c.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (BuildContext context, Widget? child) {
          final o = widget.opacityAt(_c.value);
          if (o <= 0.003) return const SizedBox.shrink();
          return Opacity(opacity: o > 1 ? 1.0 : o, child: child);
        },
        child: widget.child,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 台パンの長押し中：ゴゴゴゴゴ…
// ---------------------------------------------------------------------------

class HoldOverlay extends StatelessWidget {
  const HoldOverlay({super.key, required this.who, required this.clock});

  final String who;
  final Animation<double> clock;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints box) {
          final fs = math.min(64.0, math.max(35.0, box.maxWidth * 0.12));
          return AnimatedBuilder(
            animation: clock,
            builder: (BuildContext context, Widget? _) {
              final t = clock.value * SingleDiscPainter.clockSeconds;
              final pulse = 0.55 + 0.45 * (math.sin(t * 2 * math.pi / 0.8) * 0.5 + 0.5);
              final jx = math.sin(t * 2 * math.pi / 0.11) * 2;
              final jy = math.cos(t * 2 * math.pi / 0.13) * 1.5;
              return Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: Opacity(opacity: pulse, child: const VignetteBox(edge: Color(0x99960018))),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: box.maxHeight * 0.14,
                    child: Center(
                      child: Transform.translate(
                        offset: Offset(jx, jy),
                        child: OutlinedText('ゴゴゴゴゴ…', size: fs, fill: kGauge, stroke: fs * 0.16),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: box.maxHeight * 0.14 + fs * 1.5,
                    child: Center(
                      child: InkBox(
                        radius: 999,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                        child: Text(who, style: bodyStyle(14)),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: box.maxHeight * 0.14 + fs * 1.5 + 40,
                    child: Center(
                      child: OutlinedText('もうすぐ 石をひっくり返す！', size: 20, fill: kPaper, stroke: 5, body: true, shadow: false),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
