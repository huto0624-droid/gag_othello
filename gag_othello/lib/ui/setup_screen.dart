import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/models.dart';
import '../services/app_state.dart';
import '../services/audio_service.dart';
import '../services/error_report.dart';
import '../services/face_service.dart';
import 'crop_dialog.dart';
import 'game_screen.dart';
import 'sound_controls.dart';
import 'theme.dart';

/// タイトル（設定）画面：あそびかた・名前・顔写真・おと・ルール。
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.app});

  final AppState app;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final ImagePicker _picker = ImagePicker();
  late final List<TextEditingController> _names;
  String _note = '写真はこの端末の中だけで使われ、外には送られません。写真がなくても、そのまま遊べます。';

  AppState get app => widget.app;

  @override
  void initState() {
    super.initState();
    _names = <TextEditingController>[
      TextEditingController(text: app.names[0]),
      TextEditingController(text: app.names[1]),
    ];
    app.audio.ensureMenuBgm();
  }

  @override
  void dispose() {
    for (final c in _names) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _start() async {
    try {
      FocusScope.of(context).unfocus();
      for (var i = 0; i < 2; i++) {
        final t = _names[i].text.trim();
        app.setName(i + 1, t.isEmpty ? 'プレイヤー${i + 1}' : t);
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (BuildContext _) => GameScreen(app: app)),
      );
    } catch (e) {
      reportError('対局を始められませんでした: $e');
      return;
    }
    // 対局から戻ったらメニューBGMへ
    if (mounted) app.audio.startBgm(Bgm.menu);
  }

  Future<void> _pickFace(int p, String kind) async {
    final src = await _chooseSource();
    if (src == null || !mounted) return;
    try {
      final x = await _picker.pickImage(source: src, maxWidth: 1280, maxHeight: 1280, imageQuality: 92);
      if (x == null || !mounted) return;
      final bytes = await x.readAsBytes();
      final img = await decodeImageBytes(bytes);
      if (!mounted) return;
      final label = kind == FaceKind.normal ? '通常顔' : '変顔';
      final asset = await showCropDialog(context, image: img, kind: kind, title: '${p}P の$labelを調整');
      if (asset != null) {
        await app.saveFace(p, kind, asset);
        if (mounted) setState(() => _note = '写真を保存しました。');
      }
    } catch (e) {
      debugPrint('pick face failed: $e');
      if (mounted) setState(() => _note = '画像を読み込めませんでした。別の写真をためしてください。');
    }
  }

  Future<ImageSource?> _chooseSource() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: InkBox(
              radius: 18,
              shadow: 5,
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text('写真をえらぶ', style: displayStyle(18)),
                  const SizedBox(height: 10),
                  InkButton(label: 'ライブラリからえらぶ', expand: true, onTap: () => Navigator.of(ctx).pop(ImageSource.gallery)),
                  const SizedBox(height: 10),
                  InkButton(label: 'カメラでとる', expand: true, onTap: () => Navigator.of(ctx).pop(ImageSource.camera)),
                  const SizedBox(height: 10),
                  InkButton(label: 'やめる', small: true, onTap: () => Navigator.of(ctx).pop()),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------------ 画面

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: Listener(
        // Web ではタップするまで音を出せないので、操作のたびにメニューBGMを確認する
        onPointerDown: (PointerDownEvent e) => app.audio.ensureMenuBgm(),
        behavior: HitTestBehavior.translucent,
        child: Stack(
          children: <Widget>[
            const DotBackground(),
            SafeArea(
              child: Column(
                children: <Widget>[
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 560),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                            child: AnimatedBuilder(
                              animation: Listenable.merge(<Listenable>[app, app.faces]),
                              builder: (BuildContext context, Widget? _) => _content(context),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // 「はじめる」は画面の下に固定（スクロールしなくても押せる）
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: InkButton(
                        label: 'はじめる',
                        big: true,
                        expand: true,
                        color: kFeltD,
                        textColor: kWhite,
                        onTap: _start,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final logo = math.min(74.0, math.max(43.0, w * 0.14));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // ---- ロゴ
        Center(
          child: Transform.rotate(
            angle: -2 * math.pi / 180,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              decoration: BoxDecoration(color: kInk, borderRadius: BorderRadius.circular(6)),
              child: Text('Me vs You', style: displayStyle(14, color: kHotB)),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Transform.rotate(
          angle: -3 * math.pi / 180,
          child: Wrap(
            alignment: WrapAlignment.center,
            children: <Widget>[
              OutlinedText('ギャグ', size: logo, fill: kP1, stroke: logo * 0.14),
              OutlinedText('オセロ', size: logo, fill: kPaper, stroke: logo * 0.14),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '実力差はいらない。負けても笑える。勝つと顔面モザイクで恥をかく、パーティー向けオセロ。',
          textAlign: TextAlign.center,
          style: bodyStyle(14.5, height: 1.5),
        ),
        const SizedBox(height: 14),

        // ---- あそびかた
        Row(
          children: <Widget>[
            Expanded(child: _segment(GameMode.cpu, 'ひとりで', 'コンピュータと対戦')),
            const SizedBox(width: 10),
            Expanded(child: _segment(GameMode.twoPlayer, 'ふたりで', '向かい合わせ・同じ画面')),
          ],
        ),
        const SizedBox(height: 14),

        // ---- プレイヤー
        _playerCard(1),
        const SizedBox(height: 14),
        _playerCard(2),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(_note, style: bodyStyle(12.5)),
        ),
        const SizedBox(height: 10),

        // ---- おと
        InkBox(
          radius: 14,
          shadow: 3,
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text('おと', style: displayStyle(16)),
              const SizedBox(height: 4),
              SoundControls(app: app, samples: true),
              if (kIsWeb && !app.audio.isBgmPlaying)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('画面にさわると、メニューBGMが流れます。', style: bodyStyle(12)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ---- ルール
        InkBox(
          radius: 14,
          shadow: 3,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 8),
              childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              title: Text('ルールを見る', style: displayStyle(15)),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final t in _rules)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('・', style: bodyStyle(13.5)),
                        Expanded(child: Text(t, style: bodyStyle(13.5, height: 1.45))),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static const List<String> _rules = <String>[
    'ふつうのオセロです。光っているマスに自分の顔を置きます。',
    '赤いストレスゲージは、角を取られる・一気に5枚以上返される・パスになる・劣勢が続くと、たまります。たまるほど顔がイライラしてきます。',
    '打てる場所がないときは「パス」ボタンを押します。押すとストレスがたまります。',
    'ゲージがMAXになったら「台パン」ボタンを長押し。相手の番でも使えます。コマが宙を舞い、石数が同数になります（端数は台パンした側）。',
    'ただし角は完全ランダム。1/2で相手のものになるので、勝っているときの台パンは損です。',
    '空きマスが4つ以下になるとヒートアップ。目が燃え、机が熱すぎて台パンは封印されます。',
    '終局後は、勝った側の変顔が画面いっぱいに。負けた側は笑ってOK。',
  ];

  Widget _segment(GameMode m, String title, String sub) {
    final on = app.mode == m;
    return Semantics(
      button: true,
      selected: on,
      label: '$title $sub',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => app.setMode(m),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: on ? kInk : kPaper,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kInk, width: 3),
            boxShadow: const <BoxShadow>[BoxShadow(color: kInk, offset: Offset(3, 3), blurRadius: 0)],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: displayStyle(16.5, color: on ? kPaper : kInk)),
              Text(sub, style: bodyStyle(11.5, color: on ? kPaper : kInk)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _playerCard(int p) {
    final color = ownerColor(p);
    return InkBox(
      radius: 18,
      shadow: 4,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: kInk, width: 3),
                ),
                child: Text('${p}P', style: displayStyle(16)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _names[p - 1],
                  maxLength: 10,
                  style: bodyStyle(16, weight: FontWeight.w900),
                  decoration: InputDecoration(
                    counterText: '',
                    isDense: true,
                    filled: true,
                    fillColor: kWhite,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: kInk, width: 3),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: kInk, width: 3),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: kP2, width: 3),
                    ),
                  ),
                  onChanged: (String v) => app.setName(p, v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _slot(p, FaceKind.normal),
          const SizedBox(height: 8),
          _slot(p, FaceKind.funny),
        ],
      ),
    );
  }

  Widget _slot(int p, String kind) {
    final color = ownerColor(p);
    final f = app.faces.get(p, kind);
    final custom = app.faces.isCustom(p, kind);
    final title = kind == FaceKind.normal ? '通常顔' : '変顔';
    final sub = kind == FaceKind.normal ? '目の位置あわせあり（炎が出ます）' : '勝ったとき画面いっぱいに出ます';
    return Row(
      children: <Widget>[
        Container(
          width: 76,
          height: 76,
          margin: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: kInk, width: 3),
            boxShadow: <BoxShadow>[
              const BoxShadow(color: kInk, spreadRadius: 7),
              BoxShadow(color: color, spreadRadius: 4),
            ],
          ),
          child: ClipOval(child: RawImage(image: f.image, fit: BoxFit.cover)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: displayStyle(15)),
              Text(sub, style: bodyStyle(11.5)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 10,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  InkButton(label: '写真をえらぶ', small: true, onTap: () => _pickFace(p, kind)),
                  if (custom)
                    GestureDetector(
                      onTap: () => app.resetFace(p, kind),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          'もどす',
                          style: bodyStyle(12.5).copyWith(decoration: TextDecoration.underline),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
