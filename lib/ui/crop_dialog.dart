import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/util.dart';
import '../services/face_service.dart';
import 'theme.dart';

/// 写真の切り抜き。丸の中に顔を入れ、通常顔では両目に赤い印を合わせる（そこに炎が出る）。
/// OK を押すと 256x256 の PNG にして [FaceAsset] を返す。やめるなら null。
Future<FaceAsset?> showCropDialog(
  BuildContext context, {
  required ui.Image image,
  required String kind,
  required String title,
}) {
  return showDialog<FaceAsset>(
    context: context,
    barrierDismissible: false,
    barrierColor: const Color(0xB81C1233),
    builder: (BuildContext ctx) => _CropDialog(image: image, kind: kind, title: title),
  );
}

class _CropDialog extends StatefulWidget {
  const _CropDialog({required this.image, required this.kind, required this.title});

  final ui.Image image;
  final String kind;
  final String title;

  @override
  State<_CropDialog> createState() => _CropDialogState();
}

class _CropDialogState extends State<_CropDialog> {
  double _zoom = 1;
  double _ox = 0;
  double _oy = 0;
  List<double> _eyes = <double>[0.34, 0.44, 0.66, 0.44];
  int _drag = -2; // -2=なし / -1=画像を動かす / 0,1=目の印
  double _side = 300;
  bool _busy = false;

  bool get _isNormal => widget.kind == FaceKind.normal;

  /// 画像を置く矩形（丸の枠 [side] x [side] に対して、はみ出さないよう位置を補正する）
  Rect _geom(double side) {
    final iw = widget.image.width.toDouble();
    final ih = widget.image.height.toDouble();
    final s = math.max(side / iw, side / ih) * _zoom;
    final w = iw * s;
    final h = ih * s;
    final mx = (w - side) / 2;
    final my = (h - side) / 2;
    _ox = clampD(_ox, -mx, mx);
    _oy = clampD(_oy, -my, my);
    return Rect.fromLTWH(side / 2 - w / 2 + _ox, side / 2 - h / 2 + _oy, w, h);
  }

  void _onPanStart(DragStartDetails d) {
    _drag = -1;
    if (_isNormal) {
      for (var k = 0; k < 2; k++) {
        final ex = _eyes[k * 2] * _side;
        final ey = _eyes[k * 2 + 1] * _side;
        if ((d.localPosition - Offset(ex, ey)).distance < 26) _drag = k;
      }
    }
  }

  void _onPanUpdate(DragUpdateDetails d) {
    setState(() {
      if (_drag >= 0) {
        _eyes[_drag * 2] = clampD(d.localPosition.dx / _side, 0.05, 0.95);
        _eyes[_drag * 2 + 1] = clampD(d.localPosition.dy / _side, 0.05, 0.95);
      } else if (_drag == -1) {
        _ox += d.delta.dx;
        _oy += d.delta.dy;
      }
    });
  }

  Future<void> _ok() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      const double out = 256;
      final k = out / _side;
      final gm = _geom(_side);
      final rec = ui.PictureRecorder();
      final c = Canvas(rec, Rect.fromLTWH(0, 0, out, out));
      c.drawRect(Rect.fromLTWH(0, 0, out, out), Paint()..color = kWhite);
      c.drawImageRect(
        widget.image,
        Rect.fromLTWH(0, 0, widget.image.width.toDouble(), widget.image.height.toDouble()),
        Rect.fromLTWH(gm.left * k, gm.top * k, gm.width * k, gm.height * k),
        Paint()..filterQuality = FilterQuality.high,
      );
      final pic = rec.endRecording();
      final img = await pic.toImage(256, 256);
      pic.dispose();
      final png = await encodePng(img);
      final eyes = _isNormal
          ? _eyes.map<double>((double v) => (v * 1000).roundToDouble() / 1000).toList()
          : FaceStore.defaultEyes;
      if (!mounted) return;
      Navigator.of(context).pop(FaceAsset(image: img, eyes: eyes, png: png, custom: true));
    } catch (e) {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hint = _isNormal
        ? '丸の中に顔を入れて、赤い印を両目に合わせてください。印は動かせます。ここに炎が出ます。'
        : '丸の中に顔を入れてください。ドラッグで位置、スライダーで大きさを変えられます。';
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
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints box) {
              final side = math.min(300.0, box.maxWidth - 6);
              _side = side;
              final gm = _geom(side);
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(widget.title, style: displayStyle(18)),
                  const SizedBox(height: 6),
                  Text(hint, style: bodyStyle(12.5)),
                  const SizedBox(height: 10),
                  Center(
                    child: Container(
                      width: side + 6,
                      height: side + 6,
                      decoration: BoxDecoration(
                        color: kWhite,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: kInk, width: 3),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanStart: _onPanStart,
                          onPanUpdate: _onPanUpdate,
                          onPanEnd: (DragEndDetails d) => _drag = -2,
                          child: CustomPaint(
                            size: Size(side, side),
                            painter: _CropPainter(
                              image: widget.image,
                              dest: gm,
                              eyes: _isNormal ? _eyes : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      Text('ズーム', style: bodyStyle(13)),
                      Expanded(
                        child: SliderTheme(
                          data: SliderThemeData(
                            activeTrackColor: kGauge,
                            inactiveTrackColor: kGaugeBg,
                            thumbColor: kGauge,
                            trackHeight: 8,
                          ),
                          child: Slider(
                            value: _zoom,
                            min: 1,
                            max: 3,
                            onChanged: (double v) => setState(() => _zoom = v),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      InkButton(label: 'やめる', small: true, onTap: _busy ? null : () => Navigator.of(context).pop()),
                      const SizedBox(width: 10),
                      InkButton(label: 'これでOK', small: true, color: kHotB, onTap: _busy ? null : _ok),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  const _CropPainter({required this.image, required this.dest, required this.eyes});

  final ui.Image image;
  final Rect dest;

  /// 通常顔のときだけ [左目x, 左目y, 右目x, 右目y]（0〜1）
  final List<double>? eyes;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    canvas.drawRect(Offset.zero & size, Paint()..color = kWhite);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      dest,
      Paint()..filterQuality = FilterQuality.medium,
    );
    // 丸の外を暗くする
    final mask = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addOval(Rect.fromCircle(center: Offset(s / 2, s / 2), radius: s / 2 - 2));
    canvas.drawPath(mask, Paint()..color = const Color(0x9E1C1233));
    canvas.drawCircle(
      Offset(s / 2, s / 2),
      s / 2 - 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = kWhite,
    );
    final e = eyes;
    if (e != null) {
      final line = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = kHotA;
      final cross = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = kHotA;
      for (var k = 0; k < 2; k++) {
        final c = Offset(e[k * 2] * s, e[k * 2 + 1] * s);
        canvas.drawCircle(c, 13, Paint()..color = kHotA.withAlpha(72));
        canvas.drawCircle(c, 13, line);
        canvas.drawLine(c.translate(-19, 0), c.translate(19, 0), cross);
        canvas.drawLine(c.translate(0, -19), c.translate(0, 19), cross);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CropPainter old) => true;
}
