// usage: node tool/sim.js prototype/gag-othello.html   （試作版 JS エンジンでのボット同士の検証）
const fs = require('fs');
const html = fs.readFileSync(process.argv[2], 'utf8');
const m = html.match(/\/\* ===ENGINE-START=== \*\/([\s\S]*?)\/\* ===ENGINE-END=== \*\//);
if (!m) throw new Error('engine block not found');
const Engine = new Function(m[1] + '; return Engine;')();
const { CFG, Game, daipanShuffle, hasMove, pickMove, IS_CORNER } = Engine;

// 再現できる乱数
function mulberry(a) { return function () { a |= 0; a = a + 0x6D2B79F5 | 0; let t = Math.imul(a ^ a >>> 15, 1 | a); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; }; }

/* ---------- Test A: 台パン再配置の性質 ---------- */
function testShuffle(N) {
  const rng = mulberry(12345);
  const st = { n: 0, tier: [0, 0, 0, 0, 0], bad: 0, cornerOcc: 0, cornerToSlam: 0, tiersByEmpties: {}, maxTries: 0, sumTries: 0, diffHist: {} };
  const fails = [];
  for (let g = 0; g < N; g++) {
    const game = new Game(rng);
    const stopAt = 4 + ((rng() * 56) | 0);          // 4〜59手目で止める → 空き 約 5〜60
    for (let k = 0; k < stopAt && !game.over; k++) {
      const mv = pickMove(game, game.turn, rng); if (mv < 0) break; game.play(mv);
    }
    if (game.over) continue;
    const e = game.empties();
    if (e < 5) continue;
    for (const slammer of [1, 2]) {
      const before = game.b.slice();
      const total = 64 - e, target = Math.ceil(total / 2);
      const r = daipanShuffle(game.b, slammer, game.turn, rng);
      st.n++; st.tier[r.tier]++; st.sumTries += r.tries; st.maxTries = Math.max(st.maxTries, r.tries);
      const b = r.board;
      let c1 = 0, c2 = 0, ok = true;
      for (let i = 0; i < 64; i++) {
        if ((before[i] === 0) !== (b[i] === 0)) ok = false;       // 占有マスは動かさない
        if (b[i] === 1) c1++; else if (b[i] === 2) c2++;
      }
      const cs = slammer === 1 ? c1 : c2, co = slammer === 1 ? c2 : c1;
      if (r.tier < 4) {
        if (cs !== target || co !== total - target) ok = false;   // 同数（端数は台パン側）
        const d = cs - co; st.diffHist[d] = (st.diffHist[d] || 0) + 1;
      }
      if (r.tier === 1 && !(hasMove(b, game.turn) && hasMove(b, 3 - game.turn))) ok = false;
      if (r.tier === 2 && !hasMove(b, game.turn)) ok = false;
      [0, 7, 56, 63].forEach(c => { if (before[c]) { st.cornerOcc++; if (b[c] === slammer) st.cornerToSlam++; } });
      const bucket = e <= 10 ? '5-10' : e <= 20 ? '11-20' : e <= 40 ? '21-40' : '41-60';
      st.tiersByEmpties[bucket] = st.tiersByEmpties[bucket] || [0, 0, 0, 0, 0]; st.tiersByEmpties[bucket][r.tier]++;
      if (!ok) { st.bad++; if (fails.length < 3) fails.push({ e, slammer, tier: r.tier, c1, c2 }); }
    }
  }
  return { st, fails };
}

/* ---------- Test B: ゲージ調整（ボットの対局） ---------- */
function playBotGame(rng, noise) {
  const game = new Game(rng);
  let guard = 0, log = { corner: 0, bigflip: 0, pass: 0, late: 0 };
  while (!game.over && guard++ < 500) {
    // 台パン判断：MAX かつ 4枚以上負けている、ときどき
    for (const p of [1, 2]) {
      const c = game.counts();
      if (game.canDaipan(p) && c[p - 1] <= c[2 - p] - 4 && rng() < 0.5) game.daipan(p);
    }
    if (game.over) break;
    const mv = pickMove(game, game.turn, rng); if (mv < 0) break;
    const res = game.play(mv);
    res.gauge.forEach(g => { log[g.reason]++; });
  }
  return { game, log };
}
function testGauge(N) {
  const rng = mulberry(777);
  let total = 0, zero = 0, hist = {}, hits = 0, wasted = 0, pass = 0, moves = 0, logSum = { corner: 0, bigflip: 0, pass: 0, late: 0 };
  let diffAfter = 0;
  for (let g = 0; g < N; g++) {
    const { game, log } = playBotGame(rng);
    const d = game.daipans[0] + game.daipans[1];
    total += d; if (!d) zero++; hist[d] = (hist[d] || 0) + 1;
    hits += game.maxHits[0] + game.maxHits[1];
    wasted += Math.max(0, game.maxHits[0] - game.daipans[0]) + Math.max(0, game.maxHits[1] - game.daipans[1]);
    moves += game.moveNo;
    for (const k in log) logSum[k] += log[k];
  }
  return { avgDaipan: total / N, zeroRate: zero / N, hist, avgMaxHits: hits / N, avgWastedMax: wasted / N, avgMoves: moves / N, gaugeEventsPerGame: Object.fromEntries(Object.entries(logSum).map(([k, v]) => [k, +(v / N).toFixed(2)])) };
}

console.log('== Test A: shuffle (8000 games sampled) ==');
const A = testShuffle(8000);
console.log(JSON.stringify({ samples: A.st.n, tier: A.st.tier, violations: A.st.bad, avgTries: +(A.st.sumTries / A.st.n).toFixed(2), maxTries: A.st.maxTries, cornerToSlammerRate: +(A.st.cornerToSlam / A.st.cornerOcc).toFixed(3), occupiedCornerSamples: A.st.cornerOcc, diffHist: A.st.diffHist, tiersByEmpties: A.st.tiersByEmpties }, null, 1));
if (A.fails.length) console.log('FAILS', JSON.stringify(A.fails));

console.log('== Test B: gauge tuning (4000 bot games) ==');
console.log(JSON.stringify(testGauge(4000), null, 1));
console.log('CFG.gauge', JSON.stringify(CFG.gauge));
