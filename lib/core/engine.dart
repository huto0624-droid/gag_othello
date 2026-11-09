/// 純ロジック層。Flutter にも dart:ui にも依存しない（`dart test` でも動く）。
///
/// ブラウザ試作版（gag-othello.html の ENGINE ブロック）をそのまま移植したもの。
/// 盤は 64 要素の `List<int>`（0=空 / 1=1P / 2=2P）。インデックスは row*8+col。
library;

import 'dart:math' as math;

/// 調整用パラメータ（将来は Remote Config などに逃がす想定）
class Cfg {
  Cfg._();

  /// 台パンの長押し時間（ミリ秒）
  static const int holdMs = 900;

  /// 空きマスがこの数以下になると「ヒートアップ」（台パン封印・ゲージ停止）
  static const int sealEmpties = 6;
}

/// ストレスゲージの調整値（ガチモードは空き 6・ゲージは 1.3 倍の版）。
/// ボット同士のシミュレーションで「1ゲームあたり台パン約 2.3 回」になるよう合わせてある。
class GaugeCfg {
  GaugeCfg._();

  static const int max = 100;

  /// 角を取られた
  static const int corner = 52;

  /// 1手でこの枚数以上返された
  static const int bigFlipMin = 5;
  static const int bigFlip = 20;

  /// 自分がパス
  static const int pass = 33;

  /// 連続パス
  static const int passStreak = 46;

  /// この手数以降、枚数で負けている側に手番ごとに少しずつ加算する。
  /// 加算量 = 相手との差 ÷ behindStep（切り上げ）。1回あたり behindMax が上限。
  static const int behindFromMove = 6;
  static const int behindStep = 4;
  static const int behindMax = 5;
}

/// ゲージが増えた理由
enum StressReason { corner, bigflip, pass, late }

/// 1回のゲージ増加
class GaugeEvent {
  const GaugeEvent(this.p, this.delta, this.reason);

  final int p;
  final int delta;
  final StressReason reason;
}

/// 手の種類
enum ResultKind { move, pass, daipan }

/// `Game.play / pass / daipan` の結果。UI はこれを見て演出を組み立てる。
class TurnResult {
  TurnResult(this.kind, this.p);

  final ResultKind kind;

  /// 手を打った（パスした・台パンした）側
  final int p;

  /// 打った場所（move のみ）
  int idx = -1;

  /// 裏返った場所（move のみ）
  List<int> flips = const <int>[];
  final List<GaugeEvent> gauge = <GaugeEvent>[];

  /// 自動パスになった側（0=なし）
  int passed = 0;

  /// 手動パスの待ちになった側（0=なし）
  int pending = 0;
  bool heatStarted = false;
  bool over = false;
  bool corner = false;

  // daipan のみ
  List<int> before = const <int>[];
  List<int> after = const <int>[];
  int tier = 0;
  int tries = 0;
}

const List<List<int>> _dirs = <List<int>>[
  <int>[-1, -1],
  <int>[-1, 0],
  <int>[-1, 1],
  <int>[0, -1],
  <int>[0, 1],
  <int>[1, -1],
  <int>[1, 0],
  <int>[1, 1],
];

const Set<int> _xSquares = <int>{9, 14, 49, 54};

bool isCorner(int i) => i == 0 || i == 7 || i == 56 || i == 63;

List<int> initialBoard() {
  final b = List<int>.filled(64, 0);
  b[27] = 2;
  b[28] = 1;
  b[35] = 1;
  b[36] = 2;
  return b;
}

/// idx に p が打ったとき裏返る石の一覧（打てなければ空）
List<int> flipsFor(List<int> b, int idx, int p) {
  if (b[idx] != 0) return <int>[];
  final r0 = idx >> 3;
  final c0 = idx & 7;
  final o = 3 - p;
  final out = <int>[];
  for (final d in _dirs) {
    var r = r0 + d[0];
    var c = c0 + d[1];
    final line = <int>[];
    while (r >= 0 && r < 8 && c >= 0 && c < 8 && b[r * 8 + c] == o) {
      line.add(r * 8 + c);
      r += d[0];
      c += d[1];
    }
    if (line.isNotEmpty && r >= 0 && r < 8 && c >= 0 && c < 8 && b[r * 8 + c] == p) {
      out.addAll(line);
    }
  }
  return out;
}

/// p が打てる場所 → 裏返る石。挿入順（盤の左上から）で並ぶ。
Map<int, List<int>> legalMoves(List<int> b, int p) {
  final m = <int, List<int>>{};
  for (var i = 0; i < 64; i++) {
    if (b[i] == 0) {
      final f = flipsFor(b, i, p);
      if (f.isNotEmpty) m[i] = f;
    }
  }
  return m;
}

bool hasMove(List<int> b, int p) {
  for (var i = 0; i < 64; i++) {
    if (b[i] == 0 && flipsFor(b, i, p).isNotEmpty) return true;
  }
  return false;
}

/// 台パン後の盤面の再配置の結果
class ShuffleResult {
  const ShuffleResult(this.board, this.tier, this.tries);

  final List<int> board;

  /// 1: 両者に合法手あり / 2: 手番側のみ / 3: 条件なし / 4: 不発（盤面そのまま）
  final int tier;
  final int tries;
}

/// 台パン後の盤面の再配置。
///
/// 1. 占有済みの角は 1/2 で台パン側 / 相手側（完全ランダム）
/// 2. 残りの石は、全体が同数になるよう色を再配分（端数は台パン側）
/// 3. 手番側に合法手があり、できれば相手側にもある盤面を採用
///
/// 見つからなければ段階的に条件をゆるめる（tier 1→2→3）。tier 4 は不発。
ShuffleResult daipanShuffle(
  List<int> board,
  int slammer,
  int turn,
  math.Random rng, {
  int maxTries = 3000,
}) {
  final other = 3 - slammer;
  final corners = <int>[];
  final nonc = <int>[];
  for (var i = 0; i < 64; i++) {
    if (board[i] != 0) {
      if (isCorner(i)) {
        corners.add(i);
      } else {
        nonc.add(i);
      }
    }
  }
  final total = corners.length + nonc.length;
  final slamTarget = (total + 1) ~/ 2; // 端数は台パン側
  final pool = List<int>.of(nonc);
  List<int>? best2;
  List<int>? best3;
  var tries = 0;
  while (tries < maxTries) {
    tries++;
    final nb = List<int>.of(board);
    var cs = 0;
    for (final c in corners) {
      final own = rng.nextDouble() < 0.5 ? slammer : other;
      nb[c] = own;
      if (own == slammer) cs++;
    }
    final need = slamTarget - cs;
    if (need < 0 || need > nonc.length) continue; // 角の結果が極端 → 角を振り直す
    for (var i = pool.length - 1; i > 0; i--) {
      final j = (rng.nextDouble() * (i + 1)).floor();
      final t = pool[i];
      pool[i] = pool[j];
      pool[j] = t;
    }
    for (var i = 0; i < pool.length; i++) {
      nb[pool[i]] = i < need ? slammer : other;
    }
    final a = hasMove(nb, turn);
    if (a && hasMove(nb, 3 - turn)) return ShuffleResult(nb, 1, tries);
    if (a) {
      best2 ??= nb;
    } else {
      best3 ??= nb;
    }
  }
  if (best2 != null) return ShuffleResult(best2, 2, tries);
  if (best3 != null) return ShuffleResult(best3, 3, tries);
  return ShuffleResult(List<int>.of(board), 4, tries);
}

/// 1局ぶんの状態と進行。
class Game {
  /// [manualPass] が true のとき、打てる場所がない側は「パスを押すまで待つ」（pending）。
  /// false なら自動でパスする（シミュレーション用）。
  Game({math.Random? rng, this.manualPass = false}) : rng = rng ?? math.Random() {
    reset();
  }

  final math.Random rng;
  final bool manualPass;

  late List<int> b;
  int turn = 1;
  List<int> gauge = <int>[0, 0];
  List<int> passStreak = <int>[0, 0];
  List<int> daipans = <int>[0, 0];
  List<int> maxHits = <int>[0, 0];
  int moveNo = 0;
  bool over = false;
  bool heat = false;

  /// 手動パス待ちの側（0=なし）
  int pending = 0;

  void reset() {
    b = initialBoard();
    turn = 1;
    gauge = <int>[0, 0];
    passStreak = <int>[0, 0];
    daipans = <int>[0, 0];
    maxHits = <int>[0, 0];
    moveNo = 0;
    over = false;
    heat = false;
    pending = 0;
  }

  /// [1Pの枚数, 2Pの枚数]
  List<int> counts() {
    var a = 0;
    var c = 0;
    for (var i = 0; i < 64; i++) {
      if (b[i] == 1) {
        a++;
      } else if (b[i] == 2) {
        c++;
      }
    }
    return <int>[a, c];
  }

  int empties() {
    var n = 0;
    for (var i = 0; i < 64; i++) {
      if (b[i] == 0) n++;
    }
    return n;
  }

  bool get isHeat => empties() <= Cfg.sealEmpties;

  Map<int, List<int>> moves([int? p]) => legalMoves(b, p ?? turn);

  void _addGauge(TurnResult res, int p, int delta, StressReason reason) {
    if (isHeat) return; // ヒートアップ中はゲージ停止
    final g = gauge[p - 1];
    final n = math.min(GaugeCfg.max, g + delta);
    if (n == g) return;
    gauge[p - 1] = n;
    res.gauge.add(GaugeEvent(p, n - g, reason));
    if (n >= GaugeCfg.max) maxHits[p - 1]++;
  }

  /// 現在の手番が idx に打つ。打てなければ null。
  TurnResult? play(int idx) {
    final p = turn;
    if (over) return null;
    final flips = flipsFor(b, idx, p);
    if (flips.isEmpty) return null;
    final res = TurnResult(ResultKind.move, p);
    res.idx = idx;
    res.flips = flips;
    b[idx] = p;
    for (final f in flips) {
      b[f] = p;
    }
    moveNo++;
    passStreak[p - 1] = 0;
    final o = 3 - p;
    turn = o;
    if (isCorner(idx)) {
      res.corner = true;
      _addGauge(res, o, GaugeCfg.corner, StressReason.corner);
    }
    if (flips.length >= GaugeCfg.bigFlipMin) {
      _addGauge(res, o, GaugeCfg.bigFlip, StressReason.bigflip);
    }
    _resolve(res);
    if (!over && pending == 0) _late(res);
    _finish(res);
    return res;
  }

  /// 手番側に打てる場所がないとき：manualPass なら「パスを押すまで待つ」(pending)、
  /// でなければ自動でパス。両者とも打てなければ終局。
  void _resolve(TurnResult res) {
    pending = 0;
    if (empties() == 0) {
      over = true;
      return;
    }
    final t = turn;
    if (hasMove(b, t)) return;
    if (hasMove(b, 3 - t)) {
      if (manualPass) {
        pending = t;
        res.pending = t;
        return;
      }
      _doPass(res, t);
    } else {
      over = true;
    }
  }

  void _doPass(TurnResult res, int t) {
    res.passed = t;
    passStreak[t - 1]++;
    _addGauge(
      res,
      t,
      passStreak[t - 1] >= 2 ? GaugeCfg.passStreak : GaugeCfg.pass,
      StressReason.pass,
    );
    turn = 3 - t;
  }

  /// 手動パス待ちの側がパスする。待ちでなければ null。
  TurnResult? pass() {
    final t = pending;
    if (t == 0 || over) return null;
    final res = TurnResult(ResultKind.pass, t);
    _doPass(res, t);
    _resolve(res);
    if (!over) _late(res);
    _finish(res);
    return res;
  }

  /// 枚数で負けている側に、手番ごとに少しずつストレスを足す
  void _late(TurnResult res) {
    if (moveNo < GaugeCfg.behindFromMove) return;
    final c = counts();
    final t = turn;
    final d = c[2 - t] - c[t - 1]; // 相手より何枚少ないか
    if (d <= 0) return;
    final v = (d + GaugeCfg.behindStep - 1) ~/ GaugeCfg.behindStep; // 切り上げ
    _addGauge(res, t, math.min(GaugeCfg.behindMax, v), StressReason.late);
  }

  void _finish(TurnResult res) {
    res.over = over;
    if (!heat && isHeat) {
      heat = true;
      res.heatStarted = true;
    }
  }

  bool canDaipan(int p) => !over && !isHeat && gauge[p - 1] >= GaugeCfg.max;

  /// p が台パンする（相手の手番でも可）。できなければ null。
  TurnResult? daipan(int p) {
    if (!canDaipan(p)) return null;
    final before = List<int>.of(b);
    final r = daipanShuffle(b, p, turn, rng);
    final res = TurnResult(ResultKind.daipan, p);
    res.before = before;
    res.after = r.board;
    res.tier = r.tier;
    res.tries = r.tries;
    b = r.board;
    gauge[p - 1] = 0;
    daipans[p - 1]++;
    _resolve(res);
    _finish(res);
    return res;
  }
}

/// コンピュータの手。強すぎないよう「欲張り＋ノイズ」。打てなければ -1。
int pickMove(Game game, int p, math.Random rng) {
  var best = -1;
  var bs = -1e9;
  game.moves(p).forEach((int i, List<int> f) {
    final r = i >> 3;
    final c = i & 7;
    var s = f.length.toDouble();
    if (isCorner(i)) {
      s += 6;
    } else if (_xSquares.contains(i)) {
      s -= 3;
    } else if (r == 0 || r == 7 || c == 0 || c == 7) {
      s += 1.5;
    }
    s += rng.nextDouble() * 4;
    if (s > bs) {
      bs = s;
      best = i;
    }
  });
  return best;
}
