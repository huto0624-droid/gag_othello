import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/util.dart';
import '../services/app_state.dart';
import 'board_view.dart';
import 'disc_painter.dart';
import 'effects.dart';
import 'ending_overlay.dart';
import 'game_controller.dart';
import 'player_panel.dart';
import 'sound_controls.dart';
import 'theme.dart';
import 'visuals.dart';

/// 対局画面。上=2P（CPU）、下=1P。2人プレイのときは2P側のパネルが逆さまになる（向かい合わせ）。
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.app});

  final AppState app;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  late final GameController ctl;
  late final AnimationController _clock;
  late final AnimationController _shake;
  int _shakeSeen = 0;

  @override
  void initState() {
    super.initState();
    _clock = AnimationController(vsync: this, duration: const Duration(seconds: 3600))..repeat();
    _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 800), value: 1.0);
    ctl = GameController(vsync: this, app: widget.app);
    ctl.addListener(_onCtl);
    WidgetsBinding.instance.addObserver(this);
    ctl.begin();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ctl.removeListener(_onCtl);
    ctl.dispose();
    _clock.dispose();
    _shake.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) ctl.abortHold();
  }

  void _onCtl() {
    if (!mounted) return;
    if (ctl.shakeId != _shakeSeen) {
      _shakeSeen = ctl.shakeId;
      _shake.duration = Duration(milliseconds: ctl.shakeKind == ShakeKind.large ? 800 : 550);
      _shake.forward(from: 0.0);
    }
    setState(() {});
  }

  Future<void> _confirmLeave() async {
    final yes = await showDialog<bool>(
      context: context,
      barrierColor: const Color(0xB81C1233),
      builder: (BuildContext ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: InkBox(
              radius: 18,
              shadow: 5,
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text('タイトルにもどる？', style: displayStyle(19)),
                  const SizedBox(height: 8),
                  Text('いまの対局は、ここでおわります。', style: bodyStyle(13)),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      InkButton(label: 'つづける', small: true, onTap: () => Navigator.of(ctx).pop(false)),
                      const SizedBox(width: 10),
                      InkButton(label: 'もどる', small: true, color: kHotB, onTap: () => Navigator.of(ctx).pop(true)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (yes == true && mounted) Navigator.of(context).pop();
  }

  // ------------------------------------------------------------------ 画面

  @override
  Widget build(BuildContext context) {
    final hold = ctl.hold;
    return Scaffold(
      backgroundColor: kBg,
      body: Stack(
        children: <Widget>[
          const DotBackground(),
          SafeArea(
            child: AnimatedBuilder(
              animation: Listenable.merge(<Listenable>[_shake, _clock]),
              builder: (BuildContext context, Widget? child) {
                final o = _shakeOffset();
                return Transform.translate(
                  offset: Offset(o.dx, o.dy),
                  child: Transform.rotate(angle: o.dz, child: child),
                );
              },
              child: LayoutBuilder(builder: _buildStage),
            ),
          ),
          if (hold != null)
            HoldOverlay(who: '${widget.app.nameOf(hold.p)} が机を叩こうとしている…', clock: _clock),
          PulseOverlay(
            id: ctl.vignetteId,
            ms: ctl.vignetteBig ? 1100 : 800,
            opacityAt: _vignetteOpacity,
            child: const VignetteBox(edge: Color(0xD9FF2638)),
          ),
          PulseOverlay(
            id: ctl.flashId,
            ms: 450,
            opacityAt: (double t) => 0.95 * (1 - t),
            child: const SizedBox.expand(child: ColoredBox(color: kWhite)),
          ),
          if (ctl.ending != null)
            EndingOverlay(
              info: ctl.ending!,
              app: widget.app,
              onAgain: ctl.restart,
              onTitle: () => Navigator.of(context).pop(),
            ),
        ],
      ),
    );
  }

  double _vignetteOpacity(double t) {
    if (ctl.vignetteBig) {
      return t < 0.3 ? 1 - 0.45 * (t / 0.3) : 0.55 * (1 - (t - 0.3) / 0.7);
    }
    return 0.55 * (1 - t);
  }

  /// (dx, dy, 回転rad)
  _Shake _shakeOffset() {
    var dx = 0.0;
    var dy = 0.0;
    var rot = 0.0;
    final t = _clock.value * SingleDiscPainter.clockSeconds;
    if (ctl.hold != null) {
      dx += math.sin(t * 2 * math.pi / 0.09) * 2;
      dy += math.cos(t * 2 * math.pi / 0.07) * 1.5;
    }
    if (_shake.value < 1) {
      final big = ctl.shakeKind == ShakeKind.large;
      final k = _shake.value;
      final amp = big ? 13.0 : 7.0;
      final decay = 1 - k;
      dx += math.sin(k * 2 * math.pi * 4) * amp * decay;
      dy += math.cos(k * 2 * math.pi * 4 + 1) * amp * 0.8 * decay;
      rot = math.sin(k * 2 * math.pi * 3) * (big ? 0.012 : 0.006) * decay;
    }
    return _Shake(dx, dy, rot);
  }

  Widget _buildStage(BuildContext context, BoxConstraints box) {
    final contentW = math.min(box.maxWidth, 560.0) - 32;
    // 縦方向の余裕から盤の大きさを決める（上下バー・パネル2枚・メッセージ分を引く）
    const fixedH = 54.0 + 2 * 92.0 + 2 * 12.0 + 10.0 + 48.0 + 24.0;
    final side = clampD(math.min(contentW, box.maxHeight - fixedH), 220, 520);
    final two = widget.app.mode == GameMode.twoPlayer;

    final panel2 = PlayerPanel(ctl: ctl, p: 2, clock: _clock);
    final panel1 = PlayerPanel(ctl: ctl, p: 1, clock: _clock);

    return Center(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _topBar(),
                const SizedBox(height: 10),
                two ? Transform.rotate(angle: math.pi, child: panel2) : panel2,
                const SizedBox(height: 12),
                Center(child: _board(side)),
                const SizedBox(height: 12),
                panel1,
                const SizedBox(height: 10),
                SizedBox(
                  height: 48,
                  child: Text(
                    ctl.message,
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: bodyStyle(13.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    final dotColor = ctl.turnIsHold ? kGauge : ownerColor(ctl.turnOwner);
    return Row(
      children: <Widget>[
        InkButton(label: 'タイトルへ', small: true, onTap: _confirmLeave),
        const SizedBox(width: 10),
        Expanded(
          child: Semantics(
            liveRegion: true,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: kPaper,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: kInk, width: 3),
                boxShadow: const <BoxShadow>[BoxShadow(color: kInk, offset: Offset(3, 3), blurRadius: 0)],
              ),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: kInk, width: 3),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(ctl.turnText, maxLines: 1, overflow: TextOverflow.ellipsis, style: displayStyle(14.5)),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        AnimatedBuilder(
          animation: widget.app,
          builder: (BuildContext context, Widget? _) {
            return InkButton(
              label: widget.app.muted ? 'おと OFF' : 'おと',
              small: true,
              onTap: () => showSoundDialog(context, widget.app),
            );
          },
        ),
      ],
    );
  }

  Widget _board(double side) {
    final fs = clampD(side * 0.095, 28.8, 52.8);
    final burstExtent = side * 1.36;
    final passP = ctl.passPlayer;
    return SizedBox(
      width: side,
      height: side,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          BoardView(ctl: ctl, clock: _clock, side: side),
          if (ctl.burstId > 0)
            Positioned(
              left: -(burstExtent - side) / 2,
              top: -(burstExtent - side) / 2,
              child: RayBurst(key: ValueKey<int>(ctl.burstId), color: kInk, extent: burstExtent),
            ),
          if (passP != 0) Positioned.fill(child: _passOverlay(passP)),
          for (final b in ctl.banners) Positioned.fill(child: BannerWidget(key: ValueKey<int>(b.id), spec: b, fontSize: fs)),
        ],
      ),
    );
  }

  /// 打てる場所がないとき、人間は自分で「パス」を押さないと進めない（押すとストレスがたまる）
  Widget _passOverlay(int p) {
    final turnAround = widget.app.mode == GameMode.twoPlayer && p == 2;
    final look = ctl.lookFor(p, mood: Mood.panic);
    return Container(
      margin: const EdgeInsets.only(right: 5, bottom: 5),
      decoration: BoxDecoration(color: const Color(0xA81C1233), borderRadius: BorderRadius.circular(14)),
      child: Center(
        child: Transform.rotate(
          angle: turnAround ? math.pi : 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(
                width: 88,
                height: 88,
                child: CustomPaint(painter: SingleDiscPainter(look: look, clock: _clock, seed: p)),
              ),
              OutlinedText('打てるマスが ない…', size: 20, fill: kPaper, stroke: 5, shadow: false),
              const SizedBox(height: 6),
              InkButton(label: 'パス', big: true, color: const Color(0xFF5B5384), textColor: kWhite, onTap: ctl.doPass),
              const SizedBox(height: 4),
              Text(ctl.passSub, style: bodyStyle(13, color: kHotB, weight: FontWeight.w900)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Shake {
  const _Shake(this.dx, this.dy, this.dz);

  final double dx;
  final double dy;
  final double dz;
}
