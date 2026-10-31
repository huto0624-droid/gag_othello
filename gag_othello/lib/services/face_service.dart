import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../core/models.dart';

const ui.Color _ink = ui.Color(0xFF1C1233);

/// 顔写真 1枚ぶん。[eyes] は画像内の割合 [左目x, 左目y, 右目x, 右目y]（0〜1）。
class FaceAsset {
  const FaceAsset({
    required this.image,
    required this.eyes,
    this.png,
    this.custom = false,
  });

  final ui.Image image;
  final List<double> eyes;

  /// 保存用の PNG（初期顔は null）
  final Uint8List? png;

  /// ユーザーが選んだ写真かどうか
  final bool custom;
}

/// PNG/JPEG などのバイト列を ui.Image にする
Future<ui.Image> decodeImageBytes(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
}

Future<Uint8List> encodePng(ui.Image image) async {
  final bd = await image.toByteData(format: ui.ImageByteFormat.png);
  if (bd == null) throw StateError('PNG encode failed');
  return bd.buffer.asUint8List();
}

ui.Paint _fill(ui.Color c) => ui.Paint()..color = c;

ui.Paint _stroke(ui.Color c, double w) => ui.Paint()
  ..color = c
  ..style = ui.PaintingStyle.stroke
  ..strokeWidth = w
  ..strokeJoin = ui.StrokeJoin.round
  ..strokeCap = ui.StrokeCap.round;

ui.Rect _oval(double cx, double cy, double rx, double ry) =>
    ui.Rect.fromCenter(center: ui.Offset(cx, cy), width: rx * 2, height: ry * 2);

/// 写真がなくても遊べるよう、コードで描く初期顔（256x256）。
/// [p] は 1 か 2、[kind] は FaceKind.normal / FaceKind.funny。
Future<ui.Image> drawDefaultFace(int p, String kind) async {
  const double s = 256;
  final rec = ui.PictureRecorder();
  final g = ui.Canvas(rec, ui.Rect.fromLTWH(0, 0, s, s));
  final bool one = p == 1;
  final bg = one ? const ui.Color(0xFFFFD9A8) : const ui.Color(0xFFC9EFFF);
  final skin = one ? const ui.Color(0xFFFFD2A6) : const ui.Color(0xFFFFE0CC);
  final hair = one ? const ui.Color(0xFF4A2A14) : const ui.Color(0xFF6B3FA0);
  final cheek = one ? const ui.Color(0x8CFF786E) : const ui.Color(0x8CFF78A0);
  final bool fun = kind == FaceKind.funny;

  g.drawRect(ui.Rect.fromLTWH(0, 0, s, s), _fill(bg));

  // 顔
  final face = _oval(128, 142, 88, 96);
  g.drawOval(face, _fill(skin));
  g.drawOval(face, _stroke(_ink, 6));

  // 髪
  final hp = ui.Path();
  if (one) {
    hp.moveTo(40, 100);
    hp.lineTo(34, 52);
    hp.lineTo(66, 76);
    hp.lineTo(78, 28);
    hp.lineTo(104, 66);
    hp.lineTo(128, 18);
    hp.lineTo(152, 66);
    hp.lineTo(178, 28);
    hp.lineTo(190, 76);
    hp.lineTo(222, 52);
    hp.lineTo(216, 100);
    hp.quadraticBezierTo(128, 70, 40, 100);
  } else {
    hp.moveTo(36, 112);
    hp.quadraticBezierTo(30, 30, 128, 24);
    hp.quadraticBezierTo(226, 30, 220, 112);
    hp.quadraticBezierTo(190, 70, 150, 78);
    hp.quadraticBezierTo(100, 92, 36, 112);
  }
  hp.close();
  g.drawPath(hp, _fill(hair));
  g.drawPath(hp, _stroke(_ink, 6));

  // ほっぺ
  g.drawOval(_oval(58, 158, fun ? 24 : 17, fun ? 20 : 12), _fill(cheek));
  g.drawOval(_oval(198, 158, fun ? 24 : 17, fun ? 20 : 12), _fill(cheek));

  // 目
  const exs = <double>[87, 169];
  const double ey = 113;
  for (var k = 0; k < 2; k++) {
    final x = exs[k];
    final white = _oval(x, ey, fun ? 25 : 21, fun ? 29 : 25);
    g.drawOval(white, _fill(const ui.Color(0xFFFFFFFF)));
    g.drawOval(white, _stroke(_ink, 5));
    if (fun) {
      g.drawCircle(ui.Offset(x + (k == 1 ? -11 : 11), ey - 6), 10, _fill(_ink));
      g.drawCircle(ui.Offset(x + (k == 1 ? -8 : 14), ey - 10), 3.5, _fill(const ui.Color(0xFFFFFFFF)));
    } else {
      g.drawCircle(ui.Offset(x, ey + 3), 10, _fill(_ink));
      g.drawCircle(ui.Offset(x + 4, ey - 2), 3.5, _fill(const ui.Color(0xFFFFFFFF)));
    }
  }

  // まゆ・口
  final line6 = _stroke(_ink, 6);
  if (fun) {
    g.drawLine(const ui.Offset(62, 84), const ui.Offset(108, 92), line6);
    g.drawLine(const ui.Offset(150, 84), const ui.Offset(194, 70), line6);
    g.drawOval(_oval(128, 180, 32, 22), _fill(_ink));
    final tongue = _oval(128, 198, 19, 17);
    g.drawOval(tongue, _fill(const ui.Color(0xFFFF6F91)));
    g.drawOval(tongue, _stroke(_ink, 4));
    g.drawLine(const ui.Offset(128, 190), const ui.Offset(128, 206), _stroke(_ink, 4));
  } else {
    g.drawLine(const ui.Offset(64, 92), const ui.Offset(108, 90), line6);
    g.drawLine(const ui.Offset(148, 90), const ui.Offset(192, 92), line6);
    g.drawArc(
      ui.Rect.fromCircle(center: const ui.Offset(128, 170), radius: 26),
      0.15 * 3.141592653589793,
      0.70 * 3.141592653589793,
      false,
      line6,
    );
  }

  final pic = rec.endRecording();
  final img = await pic.toImage(256, 256);
  pic.dispose();
  return img;
}

/// 4つの顔（1P/2P × 通常/変顔）を持つ。ユーザーの写真があればそれ、なければ初期顔。
class FaceStore extends ChangeNotifier {
  final Map<String, FaceAsset> _defaults = <String, FaceAsset>{};
  final Map<String, FaceAsset> _custom = <String, FaceAsset>{};

  /// 初期顔の目の位置（通常顔）
  static const List<double> defaultEyes = <double>[87 / 256, 113 / 256, 169 / 256, 113 / 256];

  static String keyOf(int p, String kind) => '$p-$kind';

  bool _ready = false;
  bool get ready => _ready;

  Future<void> init() async {
    for (final p in <int>[1, 2]) {
      for (final kind in FaceKind.all) {
        final img = await drawDefaultFace(p, kind);
        _defaults[keyOf(p, kind)] = FaceAsset(image: img, eyes: defaultEyes);
      }
    }
    _ready = true;
    notifyListeners();
  }

  FaceAsset get(int p, String kind) {
    final k = keyOf(p, kind);
    return _custom[k] ?? _defaults[k]!;
  }

  bool isCustom(int p, String kind) => _custom.containsKey(keyOf(p, kind));

  /// 保存済みの写真を読み込んだときなど、通知なしで入れる
  void putCustomSilently(int p, String kind, FaceAsset asset) {
    _custom[keyOf(p, kind)] = asset;
  }

  void setCustom(int p, String kind, FaceAsset asset) {
    _custom[keyOf(p, kind)] = asset;
    notifyListeners();
  }

  void resetCustom(int p, String kind) {
    _custom.remove(keyOf(p, kind));
    notifyListeners();
  }
}
