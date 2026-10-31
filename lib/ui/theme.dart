import 'package:flutter/material.dart';

/// 黄色い網点の紙面に、太い墨線のカードと緑のフェルト盤を貼ったマンガ調。
/// ゲージは赤固定、勝敗の色はコマの縁（橙 / 空色）で見分ける。
const Color kBg = Color(0xFFFFE45C);
const Color kDot = Color(0xFFFFD21F);
const Color kInk = Color(0xFF1C1233);
const Color kPaper = Color(0xFFFFFAF0);
const Color kPaper2 = Color(0xFFFFF0C9);
const Color kFelt = Color(0xFF1F9D68);
const Color kFeltD = Color(0xFF14744D);
const Color kP1 = Color(0xFFFF7A1A);
const Color kP2 = Color(0xFF27B4EE);
const Color kGauge = Color(0xFFFF2638);
const Color kGaugeBg = Color(0xFFFFD5D9);
const Color kHotA = Color(0xFFFF3A1E);
const Color kHotB = Color(0xFFFFD93B);
const Color kColdA = Color(0xFF6FD3FF);
const Color kWhite = Color(0xFFFFFFFF);

Color ownerColor(int p) => p == 1 ? kP1 : kP2;

/// アプリに同梱した日本語フォント（Noto Sans CJK JP の Bold / Black。pubspec.yaml の fonts を参照）。
/// ネットにつながらなくても、ブラウザが Google Fonts を遮断していても文字が出る。
const String kFontFamily = 'GagGothic';

/// 見出し用。いちばん太い（Black）字で、マンガの文字っぽく使う。
/// [color] に null を渡すと色なし（OutlinedText 用）。
TextStyle displayStyle(double size, {Color? color = kInk, double? height}) {
  return TextStyle(
    fontFamily: kFontFamily,
    fontSize: size,
    color: color,
    fontWeight: FontWeight.w900,
    height: height,
  );
}

/// 本文用（Bold。強調は w900）
TextStyle bodyStyle(
  double size, {
  Color? color = kInk,
  FontWeight weight = FontWeight.w700,
  double? height,
}) {
  return TextStyle(
    fontFamily: kFontFamily,
    fontSize: size,
    color: color,
    fontWeight: weight,
    height: height,
  );
}

/// 太い墨線で囲んだ文字（マンガの効果音風）
class OutlinedText extends StatelessWidget {
  const OutlinedText(
    this.text, {
    super.key,
    required this.size,
    required this.fill,
    this.stroke = 6,
    this.body = false,
    this.shadow = true,
    this.align = TextAlign.center,
  });

  final String text;
  final double size;
  final Color fill;
  final double stroke;
  final bool body;
  final bool shadow;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    final base = body ? bodyStyle(size, color: null, weight: FontWeight.w900) : displayStyle(size, color: null);
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeJoin = StrokeJoin.round
      ..color = kInk;
    final children = <Widget>[];
    if (shadow) {
      children.add(
        Transform.translate(
          offset: Offset(size * 0.06, size * 0.08),
          child: Text(text, textAlign: align, style: base.copyWith(foreground: strokePaint)),
        ),
      );
    }
    children.add(Text(text, textAlign: align, style: base.copyWith(foreground: strokePaint)));
    children.add(Text(text, textAlign: align, style: base.copyWith(color: fill)));
    return Stack(alignment: Alignment.center, children: children);
  }
}

/// 墨線の枠＋ベタ影のカード
class InkBox extends StatelessWidget {
  const InkBox({
    super.key,
    required this.child,
    this.color = kPaper,
    this.radius = 16,
    this.padding = const EdgeInsets.all(10),
    this.shadow = 3,
    this.borderWidth = 3,
    this.outline,
  });

  final Widget child;
  final Color color;
  final double radius;
  final EdgeInsetsGeometry padding;
  final double shadow;
  final double borderWidth;

  /// 外側に重ねる太い縁（手番のハイライト）
  final Color? outline;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: kInk, width: borderWidth),
        boxShadow: <BoxShadow>[
          BoxShadow(color: kInk, offset: Offset(shadow, shadow), blurRadius: 0),
        ],
      ),
      child: child,
    );
    if (outline == null) return box;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius + 4),
        border: Border.all(color: outline!, width: 4),
      ),
      padding: const EdgeInsets.all(1),
      child: box,
    );
  }
}

/// 丸ボタン（押すとへこむ）
class InkButton extends StatefulWidget {
  const InkButton({
    super.key,
    required this.label,
    required this.onTap,
    this.small = false,
    this.big = false,
    this.color = kPaper,
    this.textColor = kInk,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool small;
  final bool big;
  final Color color;
  final Color textColor;
  final bool expand;

  @override
  State<InkButton> createState() => _InkButtonState();
}

class _InkButtonState extends State<InkButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final double fs = widget.big ? 24 : (widget.small ? 13 : 16);
    final EdgeInsets pad = widget.big
        ? const EdgeInsets.symmetric(horizontal: 28, vertical: 12)
        : (widget.small
            ? const EdgeInsets.symmetric(horizontal: 14, vertical: 6)
            : const EdgeInsets.symmetric(horizontal: 18, vertical: 9));
    final enabled = widget.onTap != null;
    final label = Text(
      widget.label,
      textAlign: TextAlign.center,
      style: displayStyle(fs, color: enabled ? widget.textColor : const Color(0xFF8D859F)),
    );
    final btn = Transform.translate(
      offset: _down ? const Offset(2, 2) : Offset.zero,
      child: Container(
        width: widget.expand ? double.infinity : null,
        padding: pad,
        alignment: widget.expand ? Alignment.center : null,
        decoration: BoxDecoration(
          color: enabled ? widget.color : const Color(0xFFE8E3F2),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: kInk, width: 3),
          boxShadow: <BoxShadow>[
            BoxShadow(color: kInk, offset: _down ? const Offset(1, 1) : const Offset(3, 3), blurRadius: 0),
          ],
        ),
        child: label,
      ),
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTap: widget.onTap,
        child: btn,
      ),
    );
  }
}

/// 黄色い網点の背景
class DotBackground extends StatelessWidget {
  const DotBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return const RepaintBoundary(
      child: SizedBox.expand(child: CustomPaint(painter: _DotPainter())),
    );
  }
}

class _DotPainter extends CustomPainter {
  const _DotPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = kBg);
    final p = Paint()..color = kDot;
    for (double y = 8; y < size.height; y += 16) {
      for (double x = 8; x < size.width; x += 16) {
        canvas.drawCircle(Offset(x, y), 2.3, p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
