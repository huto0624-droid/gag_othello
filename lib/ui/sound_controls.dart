import 'package:flutter/material.dart';

import '../services/app_state.dart';
import 'theme.dart';

/// BGM / SE の音量スライダーとミュート。タイトル画面とゲーム中の「おと」で同じものを使う
/// （同じ AppState を見ているので、どちらで動かしても値がそろう）。
class SoundControls extends StatelessWidget {
  const SoundControls({super.key, required this.app, this.samples = false});

  final AppState app;

  /// 「ためしぎき」ボタンを出す（タイトル画面用）
  final bool samples;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: app,
      builder: (BuildContext context, Widget? _) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _row(
              label: 'BGM',
              value: app.volBgm,
              onChanged: app.setBgmVolume,
              onEnd: app.commitVolumes,
            ),
            _row(
              label: 'SE',
              value: app.volSe,
              onChanged: app.setSeVolume,
              onEnd: () {
                app.commitVolumes();
                app.audio.sample('place');
              },
            ),
            const SizedBox(height: 4),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                if (samples) ...<Widget>[
                  Text('ためしぎき', style: bodyStyle(12.5)),
                  InkButton(label: 'コマ', small: true, onTap: () => app.audio.sample('place')),
                  InkButton(label: 'ストレス', small: true, onTap: () => app.audio.sample('stress')),
                  InkButton(label: '台パン', small: true, onTap: () => app.audio.sample('smash')),
                ],
                InkButton(label: app.muted ? '音 OFF' : '音 ON', small: true, onTap: app.toggleMute),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _row({
    required String label,
    required int value,
    required ValueChanged<int> onChanged,
    required VoidCallback onEnd,
  }) {
    return Row(
      children: <Widget>[
        SizedBox(width: 48, child: Text(label, style: displayStyle(15))),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: kGauge,
              inactiveTrackColor: kGaugeBg,
              thumbColor: kGauge,
              overlayColor: const Color(0x33FF2638),
              trackHeight: 8,
            ),
            child: Slider(
              value: value.toDouble(),
              min: 0,
              max: 100,
              divisions: 20,
              label: '$value',
              onChanged: (double v) => onChanged(v.round()),
              onChangeEnd: (double v) => onEnd(),
            ),
          ),
        ),
        SizedBox(
          width: 40,
          child: Text('$value', textAlign: TextAlign.right, style: bodyStyle(13.5, weight: FontWeight.w900)),
        ),
      ],
    );
  }
}

/// ゲーム中に開く「おと」ダイアログ。盤を見ながら調整できるよう、上寄せで背景は薄め。
Future<void> showSoundDialog(BuildContext context, AppState app) {
  return showDialog<void>(
    context: context,
    barrierColor: const Color(0x571C1233),
    builder: (BuildContext ctx) {
      return Dialog(
        alignment: Alignment.topCenter,
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.fromLTRB(16, 64, 16, 16),
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
                Text('おと', style: displayStyle(19)),
                const SizedBox(height: 6),
                SoundControls(app: app),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: InkButton(label: 'とじる', small: true, color: kHotB, onTap: () => Navigator.of(ctx).pop()),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
