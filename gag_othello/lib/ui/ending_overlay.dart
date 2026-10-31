import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/util.dart';
import '../services/app_state.dart';
import 'theme.dart';
import 'visuals.dart';

const double _deg = math.pi / 180;

/// 終局：勝った側の変顔が画面いっぱいにモザイク状に降りそそぐ。
/// 引き分けのときは、ふたりの変顔が交互に並ぶ。
class EndingOverlay extends StatefulWidget {
  const EndingOverlay({
    super.key,
    required this.info,
    required this.app,
    required this.onAgain,
    required this.onTitle,
  });

  final EndingInfo info;
  final AppState app;
  final VoidCallback onAgain;
  final VoidCallback onTitle;

  @override
  State<EndingOverlay> createState() => _EndingOverlayState();
}

class _EndingOverlayState extends State<EndingOverlay> with TickerProviderStateMixin {
  static const double _total = 3.6; // 秒
  late final AnimationController _c;
  late final AnimationController _wig;
  late final List<double> _delays;
  late final List<double> _angles;

  @override
  void initState() {
    super.initState();
    final rng = math.Random();
    _delays = List<double>.generate(500, (int _) => rng.nextDouble() * 1.3);
    _angles = List<double>.generate(500, (int _) => (rng.nextDouble() * 36 - 18) * _deg);
    _c = AnimationController(vsync: this, duration: Duration(milliseconds: (_total * 1000).round()))..forward();
    _wig = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
    Future<void>.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) widget.app.audio.funny();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    _wig.dispose();
    super.dispose();
  }

  /// 0〜1 の区間 [from,to]（秒）での進み具合
  double _seg(double from, double to) => clampD((_c.value * _total - from) / (to - from), 0, 1);

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final app = widget.app;
    final faces = app.faces;
    return SizedBox.expand(
      child: ColoredBox(
        color: kInk,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints box) {
            final w = box.maxWidth;
            final h = box.maxHeight;
            final cols = clampInt((w / 92).round(), 4, 12);
            final tile = w / cols;
            final rows = (h / tile).ceil() + 1;
            final count = math.min(cols * rows, _delays.length);

            Widget faceDisc(int o, double size, {double ring = 12}) {
              return Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: kInk, width: 6),
                  boxShadow: <BoxShadow>[
                    const BoxShadow(color: Color(0x73000000), offset: Offset(10, 14), spreadRadius: 16),
                    BoxShadow(color: kInk, spreadRadius: ring + 4),
                    BoxShadow(color: ownerColor(o), spreadRadius: ring),
                  ],
                ),
                child: ClipOval(child: RawImage(image: faces.get(o, FaceKind.funny).image, fit: BoxFit.cover)),
              );
            }

            final mosaic = AnimatedBuilder(
              animation: _c,
              builder: (BuildContext context, Widget? _) {
                final tiles = <Widget>[];
                for (var i = 0; i < count; i++) {
                  final o = info.win != 0 ? info.win : (i % 2 == 1 ? 2 : 1);
                  final local = clampD((_c.value * _total - _delays[i]) / 0.5, 0, 1);
                  if (local <= 0) continue;
                  final s = Curves.easeOutBack.transform(local);
                  tiles.add(
                    Positioned(
                      left: (i % cols) * tile,
                      top: (i ~/ cols) * tile,
                      width: tile,
                      height: tile,
                      child: Opacity(
                        opacity: clampD(local * 2, 0, 1),
                        child: Transform.rotate(
                          angle: _angles[i],
                          child: Transform.scale(
                            scale: s,
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: ownerColor(o),
                                border: Border.all(color: kInk, width: 3),
                              ),
                              padding: const EdgeInsets.all(6),
                              child: ClipOval(
                                child: RawImage(image: faces.get(o, FaceKind.funny).image, fit: BoxFit.cover),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }
                return Stack(children: tiles);
              },
            );

            final win = info.win;
            final loser = win == 0 ? 0 : 3 - win;
            final head = win != 0 ? 'WINNER!!' : 'DRAW!!';
            final big = math.max(info.n1, info.n2);
            final small = math.min(info.n1, info.n2);
            final capTitle = win != 0
                ? '${app.nameOf(win)} の勝ち！ $big 対 $small'
                : '引き分け！ ${info.n1} 対 ${info.n2}';
            final capBody = win != 0
                ? 'おめでとう。そして、この変顔が全画面です。${app.nameOf(loser)} は笑っていいよ。'
                : 'ふたりとも仲よく変顔の刑です。';

            final giantSize = math.min(w * 0.6, math.min(h * 0.36, 400.0));
            final duoSize = math.min(w * 0.4, math.min(h * 0.26, 260.0));

            final center = AnimatedBuilder(
              animation: Listenable.merge(<Listenable>[_c, _wig]),
              builder: (BuildContext context, Widget? _) {
                // WINNER!! がドンと出る
                final pw = Curves.easeOutBack.transform(_seg(1.9, 2.9));
                final wigK = _seg(3.0, 3.1) > 0 ? (_wig.value * 2 - 1) : 0.0;
                final headFs = clampD(w * 0.16, 44, 93);
                // 変顔が上から落ちてくる
                final pg = Curves.easeOutBack.transform(_seg(1.5, 2.4));
                final pc = _seg(2.4, 3.0);
                final pb = _seg(2.7, 3.3);
                final dropY = -(1 - pg) * h * 1.1;

                final giant = win != 0
                    ? faceDisc(win, giantSize)
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[faceDisc(1, duoSize, ring: 10), const SizedBox(width: 6), faceDisc(2, duoSize, ring: 10)],
                      );
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: h),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.max,
                        children: <Widget>[
                          Opacity(
                            opacity: clampD(pw * 2, 0, 1),
                            child: Transform.rotate(
                              angle: (-14 + 10 * pw) * _deg + wigK * 3.5 * _deg,
                              child: Transform.scale(
                                scale: (2.6 - 1.6 * pw) * (1 + 0.03 * wigK),
                                child: OutlinedText(head, size: headFs, fill: kHotB, stroke: headFs * 0.14),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Opacity(
                            opacity: pg > 0 ? 1 : 0,
                            child: Transform.translate(
                              offset: Offset(0, dropY),
                              child: Transform.rotate(angle: -(1 - pg) * 40 * _deg, child: giant),
                            ),
                          ),
                          const SizedBox(height: 22),
                          Opacity(
                            opacity: pc,
                            child: Transform.translate(
                              offset: Offset(0, (1 - pc) * 20),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(maxWidth: math.min(w * 0.92, 460)),
                                child: InkBox(
                                  radius: 14,
                                  shadow: 4,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(capTitle, style: displayStyle(17.5)),
                                      const SizedBox(height: 3),
                                      Text(capBody, style: bodyStyle(13.5)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Opacity(
                            opacity: pb,
                            child: Transform.translate(
                              offset: Offset(0, (1 - pb) * 20),
                              child: Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                alignment: WrapAlignment.center,
                                children: <Widget>[
                                  InkButton(label: 'もういちど', color: kHotB, onTap: pb > 0.9 ? widget.onAgain : null),
                                  InkButton(label: 'せっていへ', onTap: pb > 0.9 ? widget.onTitle : null),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );

            return Semantics(
              container: true,
              label: '結果',
              child: Stack(children: <Widget>[Positioned.fill(child: mosaic), Positioned.fill(child: center)]),
            );
          },
        ),
      ),
    );
  }
}
