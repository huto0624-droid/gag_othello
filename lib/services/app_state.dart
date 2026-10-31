import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/models.dart';
import 'audio_service.dart';
import 'face_service.dart';

double _unit(num x) => x < 0 ? 0.0 : (x > 1 ? 1.0 : x.toDouble());

/// アプリ全体の設定（あそびかた・名前・音量・顔写真）と、音・顔のサービスをまとめて持つ。
/// 設定は端末内の SharedPreferences にだけ保存され、外部には送られない。
class AppState extends ChangeNotifier {
  AppState({required this.audio, required this.faces});

  final AudioService audio;
  final FaceStore faces;

  static const String _kSettings = 'gag-othello.settings.v1';
  static String _kFace(int p, String kind) => 'gag-othello.face.v1.$p.$kind';

  SharedPreferences? _prefs;

  GameMode mode = GameMode.cpu;
  final List<String> names = <String>['プレイヤー1', 'プレイヤー2'];
  int volBgm = 100;
  int volSe = 100;
  bool muted = false;

  Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      _loadSettings();
      await _loadFaces();
    } catch (e) {
      debugPrint('app_state: load failed ($e)');
    }
    audio.setBgmSlider(volBgm);
    audio.setSeSlider(volSe);
    notifyListeners();
  }

  void _loadSettings() {
    final raw = _prefs?.getString(_kSettings);
    if (raw == null) return;
    try {
      final d = jsonDecode(raw);
      if (d is! Map<String, dynamic>) return;
      mode = GameModeCodec.fromCode(d['mode'] as String?);
      final n = d['names'];
      if (n is List) {
        for (var i = 0; i < 2 && i < n.length; i++) {
          final s = n[i];
          if (s is String && s.trim().isNotEmpty) {
            names[i] = s.length > 10 ? s.substring(0, 10) : s;
          }
        }
      }
      final v = d['vol'];
      if (v is Map) {
        final b = v['bgm'];
        final s = v['se'];
        if (b is num && b >= 0 && b <= 100) volBgm = b.round();
        if (s is num && s >= 0 && s <= 100) volSe = s.round();
      }
    } catch (e) {
      debugPrint('app_state: bad settings ($e)');
    }
  }

  Future<void> _loadFaces() async {
    for (final p in <int>[1, 2]) {
      for (final kind in FaceKind.all) {
        final raw = _prefs?.getString(_kFace(p, kind));
        if (raw == null) continue;
        try {
          final d = jsonDecode(raw) as Map<String, dynamic>;
          final png = base64Decode(d['png'] as String);
          final img = await decodeImageBytes(png);
          List<double> eyes = FaceStore.defaultEyes;
          final e = d['eyes'];
          if (e is List && e.length == 4) {
            eyes = e.map<double>((dynamic x) => _unit(x as num)).toList();
          }
          faces.putCustomSilently(p, kind, FaceAsset(image: img, eyes: eyes, png: png, custom: true));
        } catch (e) {
          debugPrint('app_state: bad face $p-$kind ($e)');
        }
      }
    }
  }

  void _saveSettings() {
    final m = <String, dynamic>{
      'mode': mode.code,
      'names': names,
      'vol': <String, int>{'bgm': volBgm, 'se': volSe},
    };
    _prefs?.setString(_kSettings, jsonEncode(m));
  }

  // ---------------------------------------------------------------- 操作

  String nameOf(int p) {
    final n = names[p - 1];
    if (mode == GameMode.cpu && p == 2 && n == 'プレイヤー2') return 'CPU';
    return n.isEmpty ? '${p}P' : n;
  }

  void setMode(GameMode m) {
    if (mode == m) return;
    mode = m;
    _saveSettings();
    notifyListeners();
  }

  void setName(int p, String v) {
    names[p - 1] = v.length > 10 ? v.substring(0, 10) : v;
    _saveSettings();
  }

  /// スライダー操作中（毎フレーム）。保存は commitVolumes で
  void setBgmVolume(int v) {
    volBgm = v;
    audio.setBgmSlider(v);
    notifyListeners();
  }

  void setSeVolume(int v) {
    volSe = v;
    audio.setSeSlider(v);
    notifyListeners();
  }

  void commitVolumes() => _saveSettings();

  void toggleMute() {
    muted = !muted;
    audio.setMuted(muted);
    notifyListeners();
  }

  /// 切り抜いた顔写真を保存
  Future<void> saveFace(int p, String kind, FaceAsset asset) async {
    faces.setCustom(p, kind, asset);
    final png = asset.png;
    if (png == null) return;
    final m = <String, dynamic>{
      'png': base64Encode(png),
      if (kind == FaceKind.normal) 'eyes': asset.eyes,
    };
    try {
      await _prefs?.setString(_kFace(p, kind), jsonEncode(m));
    } catch (e) {
      debugPrint('app_state: save face failed ($e)');
    }
  }

  Future<void> resetFace(int p, String kind) async {
    faces.resetCustom(p, kind);
    try {
      await _prefs?.remove(_kFace(p, kind));
    } catch (e) {
      debugPrint('app_state: reset face failed ($e)');
    }
  }
}
