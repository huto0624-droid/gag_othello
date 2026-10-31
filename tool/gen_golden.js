#!/usr/bin/env node
// ブラウザ試作版のエンジン（ENGINE ブロック）で決まった対局を再生し、
// 1手ごとの結果を test/golden/golden_games.json に書き出す。
// Dart 版のエンジンが同じ結果になるかを test/engine_test.dart が確かめる。
//
//   node tool/gen_golden.js [prototype/gag-othello.html] > test/golden/golden_games.json
//
// 台パンは乱数に依存し、JS と Dart で乱数列が違うため、ここには含めない
// （台パンの性質は engine_test.dart の性質テストで確かめる）。
const fs = require('fs');
const path = require('path');
const file = process.argv[2] || path.join(__dirname, '..', 'prototype', 'gag-othello.html');
const html = fs.readFileSync(file, 'utf8');
const m = html.match(/\/\* ===ENGINE-START=== \*\/([\s\S]*?)\/\* ===ENGINE-END=== \*\//);
if (!m) throw new Error('engine block not found');
const Engine = new Function(m[1] + '; return Engine;')();
const { Game, pickMove } = Engine;

function mulberry(a) {
  return function () {
    a |= 0; a = a + 0x6D2B79F5 | 0;
    let t = Math.imul(a ^ a >>> 15, 1 | a);
    t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t;
    return ((t ^ t >>> 14) >>> 0) / 4294967296;
  };
}

// 手の選び方：greedy=欲張り(ノイズ小) / noisy=ノイズ大 / random=完全ランダム
function choose(game, p, kind, rng) {
  const moves = Array.from(game.moves(p).keys());
  if (!moves.length) return -1;
  if (kind === 'random') return moves[(rng() * moves.length) | 0];
  if (kind === 'greedy') {
    let best = -1, bs = -1;
    game.moves(p).forEach((f, i) => { const s = f.length + rng() * 0.01; if (s > bs) { bs = s; best = i; } });
    return best;
  }
  return pickMove(game, p, rng);
}

const strategies = [['random', 'greedy'], ['greedy', 'random'], ['noisy', 'noisy'], ['greedy', 'greedy'], ['random', 'random']];
const games = [];
for (let g = 0; g < 30; g++) {
  const rng = mulberry(1000 + g * 7919);
  const [s1, s2] = strategies[g % strategies.length];
  const game = new Game(rng, { manualPass: true });
  const steps = [];
  let guard = 0;
  while (!game.over && guard++ < 200) {
    let res, action;
    if (game.pending) { action = -1; res = game.pass(); }
    else {
      const mv = choose(game, game.turn, game.turn === 1 ? s1 : s2, rng);
      if (mv < 0) throw new Error('no move but not pending');
      action = mv; res = game.play(mv);
    }
    if (!res) throw new Error('engine refused a chosen action');
    steps.push({
      a: action,
      flips: action >= 0 ? res.flips : [],
      gauge: res.gauge.map(e => [e.p, e.delta, e.reason]),
      passed: res.passed || 0,
      pending: res.pending || 0,
      heatStarted: !!res.heatStarted,
      over: !!res.over,
      corner: !!res.corner,
      turn: game.turn,
      g: game.gauge.slice(),
      streak: game.passStreak.slice(),
      hits: game.maxHits.slice(),
      counts: game.counts(),
      empties: game.empties(),
      board: Array.from(game.b).join(''),
      legal: (game.over || game.pending) ? [] : Array.from(game.moves(game.turn).keys()),
      canDaipan: [game.canDaipan(1), game.canDaipan(2)]
    });
  }
  games.push({ seed: 1000 + g * 7919, p1: s1, p2: s2, steps });
}
const stats = { games: games.length, steps: 0, corner: 0, bigflip: 0, pass: 0, late: 0, manualPass: 0, heat: 0 };
games.forEach(gm => gm.steps.forEach(s => {
  stats.steps++;
  if (s.a === -1) stats.manualPass++;
  if (s.heatStarted) stats.heat++;
  s.gauge.forEach(e => { stats[e[2]]++; });
}));
process.stderr.write('golden: ' + JSON.stringify(stats) + '\n');
process.stdout.write(JSON.stringify({ version: 1, games }) + '\n');
