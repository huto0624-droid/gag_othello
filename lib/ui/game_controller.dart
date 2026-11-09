import 'dart:async';
import 'dart:math' as math;

import 'dart:ui' show Offset;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../core/engine.dart';
import '../core/models.dart';
import '../core/util.dart';
import '../services/app_state.dart';
import '../services/audio_service.dart';
import '../services/face_service.dart';
import 'disc_painter.dart';
import 'visuals.dart';

const String kDefaultMsg = '置けるマスは、少しまつとうっすら光ります。ゲージがMAXなら「台パン」を長押し＝盤の石をひっくり返して同数に！';

/// 手番が始まってから、置けるマスが光り出すまでの時間（ミリ秒）
const int kHintDelayMs = 3000;

/// 光が「うっすら」見えるまでのフェードイン時間（ミリ秒）
const int kHintFadeMs = 900;

int _dist(int a, int b) => math.max(((a >> 3) - (b >> 3)).abs(), ((a & 7) - (b & 7)).abs());

/// 対局の進行役。ロジック（[Game]）を動かし、演出（アニメーション・音・メッセージ）を順番に流す。
/// 画面（GameScreen）はこのクラスの状態を読んで描くだけ。
///
/// ブラウザ試作版の UI ブロック（doMove / animateMove / startHold / fireDaipan / scheduleCPU …）の移植。
class GameController extends ChangeNotifier {
  GameController({required this.vsync, required this.app}) {
    _newGame();
  }

  final TickerProvider vsync;
  final AppState app;

  AudioService get audio => app.audio;
  FaceStore get faces => app.faces;
  bool get isCpu => app.mode == GameMode.cpu;

  final math.Random _rng = math.Random();
  late Game g;

  /// 盤の64マスの見た目
  final List<CellVisual> cells = List<CellVisual>.generate(64, (int _) => CellVisual());

  /// アニメーションの途中経過で盤を再描画するための通知
  final ValueNotifier<int> boardTick = ValueNotifier<int>(0);

  final Set<AnimationController> _anims = <AnimationController>{};
  int _token = 0;
  bool _disposed = false;

  /// 演出中は操作を受け付けない（0 なら操作可）
  int lock = 0;
  HoldState? hold;
  final List<int> _coolUntil = <int>[0, 0];
  Timer? _cpuT;
  Timer? _cpuD;

  // ---- 表示用の状態（render() で更新）
  int lastIdx = -1;
  String message = kDefaultMsg;
  final List<bool> _prevMax = <bool>[false, false];
  List<Mood> moods = <Mood>[Mood.normal, Mood.normal];
  int lead = 0;
  bool heat = false;
  Set<int> hints = <int>{};

  /// 置けるマスを出してよい手番か（render() で決まる）
  bool _hintsWanted = false;

  /// 手番が始まってからの経過時間。置けるマスの光り方（[hintStrength]）に使う
  final Stopwatch _hintWatch = Stopwatch();

  /// 置けるマスの光の強さ（0 = 見えない、1 = はっきり）。最初の 3 秒は 0、そのあとフェードイン。
  /// 盤は毎フレーム描き直されるので、時間の経過はこの値を読むだけで反映される。
  double get hintStrength {
    if (!_hintsWanted) return 0;
    final ms = _hintWatch.elapsedMilliseconds;
    if (ms < kHintDelayMs) return 0;
    return clampD((ms - kHintDelayMs) / kHintFadeMs, 0, 1);
  }

  final List<PanelState> panels = <PanelState>[PanelState(), PanelState()];
  String turnText = '';
  int turnOwner = 1;
  bool turnIsHold = false;
  EndingInfo? ending;

  // ---- 演出
  final List<BannerSpec> banners = <BannerSpec>[];
  final List<StressFx?> stressFx = <StressFx?>[null, null];
  final List<int> nudgeIds = <int>[0, 0];
  ShakeKind shakeKind = ShakeKind.none;
  int shakeId = 0;
  int flashId = 0;
  int vignetteId = 0;
  bool vignetteBig = false;
  int burstId = 0;
  int _fxCounter = 0;

  // ------------------------------------------------------------------ 公開API

  /// 対局を始める（BGM 開始と CPU の手番予約）
  void begin() {
    audio.stopBgm();
    audio.startBgm(Bgm.game);
    _scheduleCpu();
  }

  /// 「もういちど」
  void restart() {
    _resetTransient();
    _newGame();
    begin();
    _notify();
  }

  /// 人間の手番か（2人プレイでは常に true）
  bool get isHumanTurn => !isCpu || g.turn == 1;

  /// 手動パスの待ち表示を出す側（0=出さない。CPU は自動でパスする）
  int get passPlayer => (!g.over && lock == 0 && g.pending != 0 && !(isCpu && g.pending == 2)) ? g.pending : 0;

  String get passSub {
    final p = g.pending;
    if (p == 0 || heat) return '';
    final amt = g.passStreak[p - 1] + 1 >= 2 ? GaugeCfg.passStreak : GaugeCfg.pass;
    return 'ストレス +$amt';
  }

  DiscLook lookFor(int owner, {Mood? mood, bool rage = false, bool brows = false}) {
    final f = faces.get(owner, FaceKind.normal);
    return DiscLook(
      owner: owner,
      face: f.image,
      eyes: f.eyes,
      mood: mood ?? moods[owner - 1],
      hot: lead == owner || lead == 0,
      rage: rage,
      brows: brows,
    );
  }

  void removeBanner(int id) {
    banners.removeWhere((BannerSpec b) => b.id == id);
    _notify();
  }

  void onCell(int i) {
    if (_disposed || g.over || lock > 0 || hold != null || !isHumanTurn) return;
    if (!g.moves(g.turn).containsKey(i)) {
      _nope(i);
      return;
    }
    _doMove(i);
  }

  Future<void> doPass() async {
    if (_disposed || g.over || g.pending == 0 || lock > 0 || hold != null) return;
    final token = _token;
    lock++;
    _notify();
    final res = g.pass();
    if (res == null) {
      lock--;
      _refresh();
      return;
    }
    await _animatePass(res);
    if (token != _token) return;
    lock--;
    _afterAction(res);
  }

  /// 台パンボタンを押した（長押し開始）
  void startHold(int p, {bool auto = false}) {
    if (_disposed || hold != null || lock > 0 || g.over) return;
    if (!auto && isCpu && p == 2) return; // CPU の台パンは CPU だけが押せる
    if (!g.canDaipan(p)) {
      if (!auto) {
        nudgeIds[p - 1]++;
        _notify();
      }
      return;
    }
    if (DateTime.now().millisecondsSinceEpoch < _coolUntil[p - 1]) return;
    _cpuT?.cancel();
    final timer = Timer(const Duration(milliseconds: Cfg.holdMs), () => _fireDaipan(p));
    hold = HoldState(p, auto, timer);
    audio.holdStart();
    _refresh();
  }

  /// 指を離した。長押しが足りなければ思いとどまる
  void cancelHold(int p) {
    final h = hold;
    if (h == null || h.auto || h.p != p) return;
    h.timer.cancel();
    hold = null;
    _coolUntil[p - 1] = DateTime.now().millisecondsSinceEpoch + 900;
    audio.holdStop();
    audio.duck(false);
    message = '${app.nameOf(p)} は思いとどまった。';
    _refresh();
    _scheduleCpu();
  }

  /// 画面を離れる／バックグラウンドへ行くときなど、長押しだけ止める
  void abortHold() {
    final h = hold;
    if (h == null) return;
    h.timer.cancel();
    hold = null;
    audio.holdStop();
    audio.duck(false);
    _refresh();
    _scheduleCpu();
  }

  @override
  void dispose() {
    _disposed = true;
    _token++;
    _cpuT?.cancel();
    _cpuD?.cancel();
    hold?.timer.cancel();
    audio.holdStop();
    for (final c in _anims.toList()) {
      c.dispose();
    }
    _anims.clear();
    boardTick.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ 内部：状態

  void _newGame() {
    g = Game(rng: _rng, manualPass: true);
    for (var i = 0; i < 64; i++) {
      cells[i].reset(g.b[i]);
    }
    lock = 0;
    hold = null;
    lastIdx = -1;
    message = kDefaultMsg;
    ending = null;
    _prevMax[0] = false;
    _prevMax[1] = false;
    _coolUntil[0] = 0;
    _coolUntil[1] = 0;
    render();
  }

  void _resetTransient() {
    _token++;
    lock = 0;
    hold?.timer.cancel();
    hold = null;
    _cpuT?.cancel();
    _cpuD?.cancel();
    audio.holdStop();
    for (final c in _anims.toList()) {
      c.dispose();
    }
    _anims.clear();
    banners.clear();
    stressFx[0] = null;
    stressFx[1] = null;
    shakeKind = ShakeKind.none;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _bump() {
    if (!_disposed) boardTick.value++;
  }

  void _refresh() {
    render();
    _notify();
  }

  Mood _moodOf(int p, int n1, int n2, bool heat) {
    if (heat) return Mood.fire;
    final tot = n1 + n2;
    if (tot < 12) return Mood.normal;
    final sh = (p == 1 ? n1 : n2) / tot;
    return sh >= 0.6 ? Mood.smug : (sh <= 0.4 ? Mood.panic : Mood.normal);
  }

  /// ロジックの現在の状態を表示用の値に写す（通知はしない）
  void render() {
    final c = g.counts();
    final n1 = c[0];
    final n2 = c[1];
    heat = g.isHeat;
    lead = n1 > n2 ? 1 : (n2 > n1 ? 2 : 0);
    moods = <Mood>[_moodOf(1, n1, n2, heat), _moodOf(2, n1, n2, heat)];
    for (var i = 0; i < 64; i++) {
      final cv = cells[i];
      cv.owner = g.b[i];
      cv.toOwner = g.b[i];
      cv.flip = 0;
    }
    final showHints = !g.over && lock == 0 && hold == null && isHumanTurn && g.pending == 0;
    // 人間の手番になった（または手番が変わった）ところから時間を数え直す
    if (showHints && !_hintsWanted) {
      _hintWatch
        ..reset()
        ..start();
    } else if (!showHints && _hintsWanted) {
      _hintWatch
        ..stop()
        ..reset();
    }
    _hintsWanted = showHints;
    hints = showHints ? g.moves(g.turn).keys.toSet() : <int>{};

    for (var p = 1; p <= 2; p++) {
      final ps = panels[p - 1];
      final gg = g.gauge[p - 1];
      final max = gg >= GaugeCfg.max && !heat;
      ps.name = app.nameOf(p);
      ps.count = p == 1 ? n1 : n2;
      ps.gauge = gg;
      ps.max = max;
      ps.sealed = heat;
      ps.active = !g.over && g.turn == p;
      ps.tense = gg >= 60 && !heat;
      ps.rage = gg >= 70 && !heat;
      ps.mood = moods[p - 1];
      if (heat) {
        ps.note = '机がヒートアップして叩けない。';
      } else if (max) {
        ps.note = 'ストレスMAX！';
      } else if (gg >= 60) {
        ps.note = 'イライラ… $gg/${GaugeCfg.max}';
      } else {
        ps.note = 'ストレス $gg/${GaugeCfg.max}';
      }
      final cpuSide = isCpu && p == 2;
      if (heat) {
        ps.btnSub = '封印中';
      } else if (cpuSide) {
        ps.btnSub = max ? 'キレそう！' : 'ためてる';
      } else {
        ps.btnSub = max ? 'ひっくり返す！\n長押し' : 'ゲージ不足';
      }
      ps.btnReady = max && !cpuSide;
      if (max && !_prevMax[p - 1]) audio.ding();
      _prevMax[p - 1] = max;
    }

    if (g.over) {
      turnText = 'ゲームセット';
    } else if (hold != null) {
      turnText = '台パンのかまえ！（石をひっくり返す）';
      turnIsHold = true;
    } else if (g.pending != 0 && lock == 0) {
      turnText = 'パスを押そう…';
      turnOwner = g.pending;
    } else {
      turnText = '${app.nameOf(g.turn)} の番';
      turnOwner = g.turn;
    }
    if (hold == null) turnIsHold = false;
    _bump();
  }

  // ------------------------------------------------------------------ 内部：演出の道具

  Future<void> _sleep(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

  double _rand(double a, double b) => a + _rng.nextDouble() * (b - a);

  /// [ms] ミリ秒かけて 0→1 を流し、各フレームで [cb] を呼ぶ。終わったら完了する。
  Future<void> _tween(int ms, void Function(double t) cb, {Curve curve = Curves.linear}) {
    final c = AnimationController(vsync: vsync, duration: Duration(milliseconds: ms));
    _anims.add(c);
    final done = Completer<void>();
    c.addListener(() {
      if (_disposed) return;
      cb(curve.transform(c.value));
      _bump();
    });
    c.addStatusListener((AnimationStatus s) {
      if (s == AnimationStatus.completed) {
        _anims.remove(c);
        scheduleMicrotask(c.dispose);
        if (!done.isCompleted) done.complete();
      }
    });
    c.forward();
    return done.future;
  }

  void _banner(String text, BannerStyle style, double seconds) {
    final id = ++_fxCounter;
    banners.add(BannerSpec(id, text, style, seconds));
    Timer(Duration(milliseconds: (seconds * 1000).round() + 150), () {
      if (_disposed) return;
      removeBanner(id);
    });
    _notify();
  }

  void _shake(ShakeKind k) {
    shakeKind = k;
    shakeId++;
  }

  void _nope(int i) {
    _tween(250, (double t) {
      cells[i].nope = t;
    }).then((_) {
      cells[i].nope = 0;
      _bump();
    });
  }

  // ------------------------------------------------------------------ 内部：ストレス演出

  void _stressFromGauge(List<GaugeEvent> list) {
    final tot = <int, int>{};
    final rs = <int, List<StressReason>>{};
    for (final e in list) {
      tot[e.p] = (tot[e.p] ?? 0) + e.delta;
      (rs[e.p] ??= <StressReason>[]).add(e.reason);
    }
    for (final p in tot.keys) {
      _stressHit(p, tot[p]!, rs[p]!);
    }
  }

  /// ストレスを食らった演出。合計の増加量で3段階
  /// （小：ゲージだけ / 中：揺れ＋怒りマーク / 大：画面フラッシュ＋爆発）
  void _stressHit(int p, int total, List<StressReason> reasons) {
    final lv = total >= 25 ? 3 : (total >= 10 ? 2 : 1);
    panels[p - 1].gauge = g.gauge[p - 1];
    final main = reasons.where((StressReason r) => r != StressReason.late).toList();
    final shown = main.isNotEmpty ? main : reasons;
    stressFx[p - 1] = StressFx(++_fxCounter, lv, total, stressLabel(shown.first.name));
    if (lv >= 2) {
      vignetteBig = lv == 3;
      vignetteId++;
    }
    if (lv == 3) _shake(ShakeKind.medium);
    _notify();
    if (lv >= 2) audio.stress(lv);
  }

  // ------------------------------------------------------------------ 内部：手番の進行

  Future<void> _doMove(int i) async {
    final token = _token;
    lock++;
    final res = g.play(i);
    if (res == null) {
      lock--;
      return;
    }
    await _animateMove(res);
    if (token != _token) return;
    lock--;
    _afterAction(res);
  }

  Future<void> _animateMove(TurnResult res) async {
    final token = _token;
    hints = <int>{};
    lastIdx = res.idx;
    final cv = cells[res.idx];
    cv.reset(res.p);
    cv.scale = 0.2;
    cv.opacity = 0;
    _notify();
    audio.place();
    _tween(220, (double t) {
      cv.scale = t < 0.7 ? 0.2 + 0.95 * (t / 0.7) : 1.15 - 0.15 * ((t - 0.7) / 0.3);
      cv.opacity = math.min(1.0, t / 0.7);
    }, curve: Curves.easeOut);
    await _sleep(140);
    if (token != _token) return;

    // 近いものから順にひっくり返す
    final order = List<int>.of(res.flips);
    order.sort((int a, int b) => _dist(a, res.idx).compareTo(_dist(b, res.idx)));
    final n = order.length;
    for (var k = 0; k < n; k++) {
      final c = cells[order[k]];
      c.owner = 3 - res.p;
      c.toOwner = res.p;
      c.flip = 0;
      final kk = k;
      Timer(Duration(milliseconds: k * 55), () => audio.flip(kk));
    }
    final total = 55 * (n - 1) + 290;
    await _tween(total, (double t) {
      final ms = t * total;
      for (var k = 0; k < n; k++) {
        final c = cells[order[k]];
        final x = ms - k * 55;
        if (x <= 0) {
          c.flip = 0;
        } else if (x < 130) {
          c.flip = Curves.easeIn.transform(x / 130) * 0.5;
        } else if (x < 290) {
          c.flip = 0.5 + Curves.easeOut.transform((x - 130) / 160) * 0.5;
        } else {
          c.owner = res.p;
          c.toOwner = res.p;
          c.flip = 0;
        }
      }
    });
    if (token != _token) return;
    for (final i in order) {
      cells[i].owner = res.p;
      cells[i].toOwner = res.p;
      cells[i].flip = 0;
    }
    _bump();

    _stressFromGauge(res.gauge);
    if (res.corner) {
      _banner('かど！', BannerStyle.gold, 0.9);
      message = '${app.nameOf(res.p)} が角を取った。${app.nameOf(3 - res.p)} のストレスが爆上がり。';
      _notify();
      await _sleep(450);
      if (token != _token) return;
    }
    if (res.heatStarted) {
      audio.siren();
      audio.setHeat(true);
      _banner('ヒートアップ！', BannerStyle.red, 1.8);
      message = '空きマス残り${Cfg.sealEmpties}。目が燃えて、机が熱すぎて台パンできない。';
      _notify();
      await _sleep(900);
    }
  }

  Future<void> _animatePass(TurnResult res) async {
    audio.pass();
    _banner('パス！', BannerStyle.paper, 1.1);
    _stressFromGauge(res.gauge);
    final tail = res.gauge.any((GaugeEvent e) => e.reason == StressReason.pass) ? 'ストレスがたまる。' : '';
    message = '${app.nameOf(res.p)} はパス。$tail';
    _notify();
    await _sleep(800);
  }

  void _afterAction(TurnResult res) {
    render();
    if (res.over) {
      _notify();
      _runEnding();
      return;
    }
    if (g.pending != 0 && !(isCpu && g.pending == 2)) {
      message = '${app.nameOf(g.pending)} は打てる場所がない…。「パス」を押そう。';
    }
    _notify();
    _scheduleCpu();
    _maybeCpuDaipan();
  }

  // ------------------------------------------------------------------ 内部：台パン

  Future<void> _fireDaipan(int p) async {
    final token = _token;
    hold = null;
    lock++;
    final res = g.daipan(p);
    if (res == null) {
      lock--;
      audio.holdStop();
      audio.duck(false);
      _refresh();
      return;
    }
    _notify();
    await _animateDaipan(res);
    if (token != _token) return;
    lock--;
    _afterAction(res);
  }

  Future<void> _animateDaipan(TurnResult res) async {
    final token = _token;
    audio.smash();
    flashId++;
    _shake(ShakeKind.large);
    burstId++;
    _banner('ドーン！', BannerStyle.red, 1.4);
    hints = <int>{};
    lastIdx = -1;
    _notify();

    final flyTo = List<Offset>.filled(64, Offset.zero);
    final flyRot = List<double>.filled(64, 0);
    final flyScale = List<double>.filled(64, 1);
    final flyDur = List<double>.filled(64, 550);
    for (var i = 0; i < 64; i++) {
      if (cells[i].owner == 0) continue;
      flyTo[i] = Offset(_rand(-0.55, 0.55), -_rand(0.2, 0.75));
      flyRot[i] = _rand(-720, 720) * math.pi / 180;
      flyScale[i] = _rand(1.1, 1.5);
      flyDur[i] = _rand(480, 620);
    }
    const flyCurve = Cubic(0.2, 0.8, 0.3, 1.0);
    await _tween(680, (double t) {
      final ms = t * 680;
      for (var i = 0; i < 64; i++) {
        final cv = cells[i];
        if (cv.owner == 0) continue;
        final f = flyCurve.transform(clampD(ms / flyDur[i], 0, 1));
        cv.offset = Offset(flyTo[i].dx * f, flyTo[i].dy * f);
        cv.rot = flyRot[i] * f;
        cv.scale = 1 + (flyScale[i] - 1) * f;
      }
    });
    if (token != _token) return;

    // 宙に浮いている間に盤面を差し替え、ばらばらと降ってくる
    render();
    _notify();
    Timer(const Duration(milliseconds: 450), audio.land);
    final delay = List<double>.filled(64, 0);
    final dur = List<double>.filled(64, 600);
    for (var i = 0; i < 64; i++) {
      delay[i] = _rand(0, 160);
      dur[i] = _rand(520, 760);
    }
    await _tween(920, (double t) {
      final ms = t * 920;
      for (var i = 0; i < 64; i++) {
        final cv = cells[i];
        if (cv.owner == 0) continue;
        final x = clampD((ms - delay[i]) / dur[i], 0, 1);
        final k = 1 - Curves.easeOutBack.transform(x);
        cv.offset = Offset(flyTo[i].dx * k, flyTo[i].dy * k);
        cv.rot = flyRot[i] * k;
        cv.scale = 1 + (flyScale[i] - 1) * k;
      }
    });
    if (token != _token) return;
    for (final cv in cells) {
      cv.offset = Offset.zero;
      cv.rot = 0;
      cv.scale = 1;
    }
    _bump();
    await _sleep(80);

    var n1 = 0;
    var n2 = 0;
    for (final v in res.after) {
      if (v == 1) {
        n1++;
      } else if (v == 2) {
        n2++;
      }
    }
    final who = app.nameOf(res.p);
    if (res.tier == 4) {
      message = '$who の台パン…は不発。机が丈夫すぎた。';
    } else {
      final tail = n1 != n2 ? '（端数は台パンした側）' : ' の同数';
      message = '$who が台パンで石をひっくり返した！ 石は $n1 対 $n2$tail。角は運しだい。';
    }
    _notify();
  }

  // ------------------------------------------------------------------ 内部：CPU

  void _scheduleCpu() {
    _cpuT?.cancel();
    if (!isCpu || _disposed || g.over) return;
    if (g.pending == 2) {
      _cpuT = Timer(const Duration(milliseconds: 1000), _cpuPass); // CPU は自動でパス
      return;
    }
    if (g.turn != 2 || g.pending != 0) return;
    _cpuT = Timer(Duration(milliseconds: 650 + _rng.nextInt(450)), _cpuStep);
  }

  void _cpuPass() {
    if (_disposed || g.over || g.pending != 2) return;
    if (lock > 0 || hold != null) {
      _cpuT = Timer(const Duration(milliseconds: 350), _cpuPass);
      return;
    }
    doPass();
  }

  void _cpuStep() {
    if (_disposed || g.over || g.turn != 2 || g.pending != 0) return;
    if (lock > 0 || hold != null) {
      _cpuT = Timer(const Duration(milliseconds: 350), _cpuStep);
      return;
    }
    final i = pickMove(g, 2, _rng);
    if (i >= 0) _doMove(i);
  }

  /// CPU は劣勢のとき、ときどき台パンする
  void _maybeCpuDaipan() {
    if (!isCpu || _disposed || g.over || lock > 0 || hold != null || !g.canDaipan(2)) return;
    final c = g.counts();
    if (c[1] > c[0] - 3 || _rng.nextDouble() > 0.55) return;
    _cpuD?.cancel();
    _cpuD = Timer(Duration(milliseconds: 500 + _rng.nextInt(900)), () {
      if (!_disposed && lock == 0 && hold == null && g.canDaipan(2)) startHold(2, auto: true);
    });
  }

  // ------------------------------------------------------------------ 内部：終局

  Future<void> _runEnding() async {
    final token = _token;
    lock++;
    audio.stopBgm();
    final c = g.counts();
    final n1 = c[0];
    final n2 = c[1];
    final win = n1 > n2 ? 1 : (n2 > n1 ? 2 : 0);
    render();
    _banner('ゲームセット！', BannerStyle.gold, 1.6);
    message = '$n1 対 $n2。';
    _notify();
    await _sleep(1300);
    if (token != _token) return;
    audio.win();
    if (win != 0) {
      // 勝った側の色に、盤全体が染まる
      final futures = <Future<void>>[];
      for (var i = 0; i < 64; i++) {
        final cv = cells[i];
        if (cv.owner != 0 && cv.owner != win) {
          futures.add(_flipOne(i, win, _rng.nextInt(450)));
        } else if (cv.owner == 0) {
          futures.add(_popNew(i, win, 200 + _rng.nextInt(600)));
        }
      }
      await Future.wait(futures);
      await _sleep(700);
    } else {
      await _sleep(900);
    }
    if (token != _token) return;
    ending = EndingInfo(win, n1, n2);
    _notify();
  }

  Future<void> _flipOne(int i, int newOwner, int delayMs) async {
    final token = _token;
    await _sleep(delayMs);
    if (token != _token) return;
    final cv = cells[i];
    cv.toOwner = newOwner;
    cv.flip = 0;
    audio.flip(i);
    await _tween(290, (double t) {
      final x = t * 290;
      cv.flip = x < 130 ? Curves.easeIn.transform(x / 130) * 0.5 : 0.5 + Curves.easeOut.transform((x - 130) / 160) * 0.5;
    });
    cv.owner = newOwner;
    cv.toOwner = newOwner;
    cv.flip = 0;
    _bump();
  }

  Future<void> _popNew(int i, int owner, int delayMs) async {
    final token = _token;
    final cv = cells[i];
    cv.reset(owner);
    cv.opacity = 0;
    cv.scale = 0;
    await _sleep(delayMs);
    if (token != _token) return;
    await _tween(300, (double t) {
      cv.scale = t < 0.7 ? 1.2 * (t / 0.7) : 1.2 - 0.2 * ((t - 0.7) / 0.3);
      cv.opacity = math.min(1.0, t / 0.7);
    }, curve: Curves.easeOut);
    cv.scale = 1;
    cv.opacity = 1;
    _bump();
  }
}
