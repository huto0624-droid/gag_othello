import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// BGM の種類
enum Bgm {
  /// タイトル（メニュー）画面
  menu,

  /// 対局中
  game,

  /// ヒートアップ中（テンポアップ＋ギラついた音色）
  heat,
}

/// BGM と効果音を鳴らす。音声は `assets/audio/*.wav`（tool/render_audio.py で生成）。
///
/// 音量モデルはブラウザ試作版と同じ：スライダー 0〜100 → 0〜1 → 2乗（聴感に合わせる）。
/// WAV には試作版のバス音量（BGM 0.5 / SE 0.9 / マスター 0.9）が書き込み済みなので、
/// ここでは「スライダー値の2乗」をそのままプレイヤー音量にする。
///
/// 音まわりの失敗でゲームが止まらないよう、すべての呼び出しは例外を握りつぶす。
class AudioService {
  static const Map<Bgm, String> _bgmFiles = <Bgm, String>{
    Bgm.menu: 'audio/bgm_menu.wav',
    Bgm.game: 'audio/bgm_game.wav',
    Bgm.heat: 'audio/bgm_heat.wav',
  };

  static const int _sePoolSize = 6;

  AudioPlayer? _bgm;
  AudioPlayer? _hold;
  final List<AudioPlayer> _sePool = <AudioPlayer>[];
  int _seNext = 0;

  double _bgmVol = 1;
  double _curBgm = 1;
  double _seVol = 1;
  bool _muted = false;
  bool _ducked = false;
  bool _suspended = false;

  Bgm? _track;
  bool _playing = false;
  int _epoch = 0;

  Timer? _rampTimer;
  Timer? _duckTimer;

  bool get muted => _muted;
  Bgm? get track => _track;
  bool get isBgmPlaying => _playing;

  Future<void> init() async {
    try {
      // Android で SE を鳴らした瞬間に BGM が止まらないよう、オーディオフォーカスを取らない
      await AudioPlayer.global.setAudioContext(
        AudioContext(
          android: AudioContextAndroid(audioFocus: AndroidAudioFocus.none),
          iOS: AudioContextIOS(category: AVAudioSessionCategory.playback),
        ),
      );
    } catch (e) {
      debugPrint('audio: setAudioContext skipped ($e)');
    }
    try {
      final bgm = AudioPlayer();
      await bgm.setReleaseMode(ReleaseMode.loop);
      _bgm = bgm;
      final hold = AudioPlayer();
      await hold.setReleaseMode(ReleaseMode.stop);
      _hold = hold;
      for (var i = 0; i < _sePoolSize; i++) {
        final p = AudioPlayer();
        await p.setReleaseMode(ReleaseMode.stop);
        _sePool.add(p);
      }
    } catch (e) {
      debugPrint('audio: init failed ($e)');
    }
  }

  void dispose() {
    _rampTimer?.cancel();
    _duckTimer?.cancel();
    _bgm?.dispose();
    _hold?.dispose();
    for (final p in _sePool) {
      p.dispose();
    }
    _sePool.clear();
  }

  // ---------------------------------------------------------------- 音量

  double get _bgmTarget => (_muted || _ducked || _suspended) ? 0.0 : _bgmVol;

  /// スライダー値（0〜100）をセットする
  void setBgmSlider(int v) {
    final x = math.min(1.0, math.max(0.0, v / 100.0));
    _bgmVol = x * x;
    _applyBgmNow();
  }

  void setSeSlider(int v) {
    final x = math.min(1.0, math.max(0.0, v / 100.0));
    _seVol = x * x;
  }

  void setMuted(bool m) {
    _muted = m;
    if (m) {
      _fire(_hold?.stop());
    }
    _applyBgmNow();
  }

  void _setBgm(double v) {
    _curBgm = v;
    _fire(_bgm?.setVolume(v));
  }

  void _applyBgmNow() {
    _rampTimer?.cancel();
    _setBgm(_bgmTarget);
  }

  /// いまの音量から [to] まで [ms] かけて滑らかに変える
  void _ramp(double to, int ms) {
    _rampTimer?.cancel();
    final from = _curBgm;
    final steps = math.max(1, (ms / 30).ceil());
    var i = 0;
    _rampTimer = Timer.periodic(const Duration(milliseconds: 30), (Timer t) {
      i++;
      if (_muted || _suspended || _ducked) {
        _setBgm(0.0);
        t.cancel();
        return;
      }
      final v = from + (to - from) * (i / steps);
      _setBgm(math.min(1.0, math.max(0.0, v)));
      if (i >= steps) t.cancel();
    });
  }

  /// BGM を一瞬止める／戻す（台パンの溜めや衝撃で SE を際立たせる）
  void duck(bool on) {
    _ducked = on;
    if (on) {
      _applyBgmNow();
    } else {
      _ramp(_bgmVol, 300);
    }
  }

  // ---------------------------------------------------------------- BGM

  Future<void> startBgm(Bgm t) async {
    final bgm = _bgm;
    if (bgm == null) return;
    if (_track == t && _playing) return;
    final epoch = ++_epoch;
    try {
      await bgm.stop();
      if (epoch != _epoch) return;
      _rampTimer?.cancel();
      _ducked = false;
      final fadeIn = t == Bgm.menu;
      final startVol = fadeIn ? 0.0 : _bgmTarget;
      _curBgm = startVol;
      await bgm.play(AssetSource(_bgmFiles[t]!), volume: startVol);
      if (epoch != _epoch) return;
      _track = t;
      _playing = true;
      if (fadeIn) _ramp(_bgmVol, 800);
    } catch (e) {
      // Web では最初のタップ前に鳴らせないことがある。次の操作で再挑戦される。
      debugPrint('audio: bgm start failed ($e)');
      if (epoch == _epoch) {
        _track = null;
        _playing = false;
      }
    }
  }

  void stopBgm() {
    _epoch++;
    _playing = false;
    _track = null;
    _rampTimer?.cancel();
    _fire(_bgm?.stop());
    holdStop();
  }

  /// タイトル画面用。まだ鳴っていなければ鳴らす（Web の自動再生対策で、タップのたびに呼んでよい）
  void ensureMenuBgm() {
    if (_track == Bgm.menu && _playing) return;
    startBgm(Bgm.menu);
  }

  /// 空きマス4以下のヒートアップ：BGM をテンポアップ版に切り替える
  void setHeat(bool heat) {
    if (heat) {
      if (_track == Bgm.game) startBgm(Bgm.heat);
    } else if (_track == Bgm.heat) {
      startBgm(Bgm.game);
    }
  }

  /// アプリがバックグラウンドへ行った／戻った
  void setSuspended(bool s) {
    _suspended = s;
    if (s) {
      _fire(_bgm?.pause());
      _fire(_hold?.stop());
    } else if (_playing) {
      _fire(_bgm?.resume());
      _applyBgmNow();
    }
  }

  // ---------------------------------------------------------------- SE

  void _playSe(String name) {
    if (_muted || _suspended || _sePool.isEmpty) return;
    final p = _sePool[_seNext];
    _seNext = (_seNext + 1) % _sePool.length;
    _fire(p.play(AssetSource('audio/se_$name.wav'), volume: math.min(1.0, _seVol)));
  }

  void place() => _playSe('place');

  /// [k] は何枚目か（音程が少しずつ変わる）
  void flip(int k) => _playSe('flip${k % 6}');

  void ding() => _playSe('ding');

  void pass() => _playSe('pass');

  void siren() => _playSe('siren');

  /// ストレスを食らった音。lv2=ピキッ＋ブブー、lv3=ピキーン＋不協和音のガーン
  void stress(int lv) {
    _playSe(lv >= 3 ? 'stress3' : 'stress2');
    if (lv >= 3) {
      duck(true);
      _duckTimer?.cancel();
      _duckTimer = Timer(const Duration(milliseconds: 650), () => duck(false));
    }
  }

  /// 台パンの長押し開始。ゴゴゴ…と音が上がり、BGM は一瞬止まる
  void holdStart() {
    duck(true);
    if (_muted || _suspended) return;
    final h = _hold;
    if (h == null) return;
    _fire(h.stop().then((_) => h.play(AssetSource('audio/se_hold.wav'), volume: math.min(1.0, _seVol))));
  }

  void holdStop() {
    _fire(_hold?.stop());
  }

  /// 台パン！
  void smash() {
    holdStop();
    _playSe('smash');
    duck(true);
    _duckTimer?.cancel();
    _duckTimer = Timer(const Duration(milliseconds: 750), () => duck(false));
  }

  void land() => _playSe('land');

  void win() => _playSe('win');

  void funny() => _playSe('funny');

  /// 音量調整中の「ためしぎき」
  void sample(String kind) {
    if (kind == 'stress') {
      stress(3);
    } else if (kind == 'smash') {
      smash();
    } else {
      place();
      Timer(const Duration(milliseconds: 110), () => flip(1));
      Timer(const Duration(milliseconds: 170), () => flip(3));
      Timer(const Duration(milliseconds: 300), ding);
    }
  }

  void _fire(Future<void>? f) {
    if (f == null) return;
    f.catchError((Object e) {
      debugPrint('audio: $e');
    });
  }
}
