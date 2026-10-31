#!/usr/bin/env python3
"""ギャグオセロの BGM / 効果音を WAV で書き出す。

ブラウザ試作版（Web Audio API で毎回合成していた音）と同じ設計を、
Flutter の audioplayers で鳴らせるよう WAV にしておくためのスクリプト。

    python3 tool/render_audio.py            # assets/audio/ に書き出す
    python3 tool/render_audio.py --check    # 書き出さず、長さと音量だけ確認する

必要: Python 3.9+, numpy, scipy   (pip install numpy scipy)

- 44.1kHz / モノラル / 16bit
- 矩形波・のこぎり波・三角波は倍音を足し合わせて作る（折り返しノイズが出ない帯域制限波）
- 音量の包絡は試作版と同じ「指数カーブで立ち上がり→指数カーブで減衰」
- バス音量は書き込み済み：BGM 0.5 x マスター 0.9 = 0.45 / SE 0.9 x マスター 0.9 = 0.81
  （アプリ側のスライダーは 値^2 をそのままプレイヤー音量にかけるだけ）
- BGM は1周ぶんの長さに収め、はみ出した音の余韻は曲頭に折り返して重ねる（ループの継ぎ目が出ない）
"""
import argparse
import math
import os
import sys

import numpy as np
from scipy.io import wavfile
from scipy.signal import lfilter, sosfilt, butter

SR = 44100
NYQ = SR / 2.0
BGM_BUS = 0.5 * 0.9
SE_BUS = 0.9 * 0.9
PEAK_LIMIT = 0.98

RNG = np.random.default_rng(20240607)


def m2f(n):
    return 440.0 * 2.0 ** ((n - 69) / 12.0)


# --------------------------------------------------------------------------- 音の部品


def _wave(kind, ph, f):
    """位相 ph[rad]、瞬間周波数 f[Hz] の帯域制限波形（最大振幅 約1）"""
    if kind == 'sine':
        return np.sin(ph)
    fmin = max(1.0, float(np.min(f)))
    kmax = int((NYQ * 0.98) / fmin)
    out = np.zeros_like(ph)
    if kind == 'sawtooth':
        for k in range(1, kmax + 1):
            m = (k * f) < NYQ * 0.98
            sgn = 1.0 if k % 2 == 1 else -1.0
            out += np.where(m, sgn * np.sin(k * ph) / k, 0.0)
        return out * (2.0 / math.pi)
    if kind == 'square':
        for k in range(1, kmax + 1, 2):
            m = (k * f) < NYQ * 0.98
            out += np.where(m, np.sin(k * ph) / k, 0.0)
        return out * (4.0 / math.pi)
    if kind == 'triangle':
        for k in range(1, kmax + 1, 2):
            m = (k * f) < NYQ * 0.98
            sgn = 1.0 if ((k - 1) // 2) % 2 == 0 else -1.0
            out += np.where(m, sgn * np.sin(k * ph) / (k * k), 0.0)
        return out * (8.0 / (math.pi ** 2))
    raise ValueError(kind)


def _env(n, d, v):
    """0.0001 から v まで 10ms で指数的に立ち上がり、d 秒で 0.0001 まで指数的に減衰"""
    t = np.arange(n) / SR
    att = min(0.01, d * 0.5)
    lo = 0.0001
    e = np.empty(n)
    a = t < att
    e[a] = lo * (v / lo) ** (t[a] / att)
    e[~a] = v * (lo / v) ** ((t[~a] - att) / max(1e-6, d - att))
    return e


def osc(kind, f0, f1, d, v):
    """f0 から f1（None なら固定）へ指数スイープする発振器 1音ぶんのサンプル列"""
    n = max(1, int(round(d * SR)))
    t = (np.arange(n) + 0.5) / SR
    if f1:
        f = f0 * (f1 / f0) ** (t / d)
    else:
        f = np.full(n, float(f0))
    ph = 2.0 * math.pi * np.cumsum(f) / SR
    return _wave(kind, ph, f) * _env(n, d, v)


def noise(d, v, c0, c1):
    """ホワイトノイズ → カットオフが c0 から c1 へ下がるローパス → 指数減衰"""
    n = max(1, int(round(d * SR)))
    x = RNG.uniform(-1.0, 1.0, n)
    y = np.empty(n)
    block = 32
    zi = np.zeros(2)
    q = 0.7071
    for s in range(0, n, block):
        e = min(n, s + block)
        tt = (s + (e - s) / 2.0) / SR
        fc = c0 * (c1 / c0) ** (tt / d)
        fc = min(fc, SR * 0.45)
        w0 = 2.0 * math.pi * fc / SR
        al = math.sin(w0) / (2.0 * q)
        cs = math.cos(w0)
        a0 = 1.0 + al
        b = np.array([(1 - cs) / 2, 1 - cs, (1 - cs) / 2]) / a0
        a = np.array([1.0, -2.0 * cs / a0, (1.0 - al) / a0])
        yy, zi = lfilter(b, a, x[s:e], zi=zi)
        y[s:e] = yy
    t = np.arange(n) / SR
    g = v * (0.0001 / v) ** (t / d)
    return y * g


class Mix:
    """時刻つきで音を重ねていくバッファ。loop=True なら、はみ出しを曲頭へ折り返す"""

    def __init__(self, seconds, loop=False):
        self.n = int(round(seconds * SR))
        self.buf = np.zeros(self.n)
        self.loop = loop

    def add(self, t, x):
        i = int(round(t * SR))
        if self.loop:
            idx = (np.arange(len(x)) + i) % self.n
            np.add.at(self.buf, idx, x)
        else:
            if i >= self.n:
                return
            e = min(self.n, i + len(x))
            self.buf[i:e] += x[: e - i]

    def osc(self, t, kind, f0, f1, d, v):
        self.add(t, osc(kind, f0, f1, d, v))

    def noise(self, t, d, v, c0, c1):
        self.add(t, noise(d, v, c0, c1))


# --------------------------------------------------------------------------- BGM

# ゲーム中（8分音符グリッド）
G_ROOT = [36, 33, 29, 31]
G_LEAD = [
    [72, 0, 76, 79, 0, 76, 72, 0],
    [69, 0, 72, 76, 0, 72, 69, 0],
    [65, 0, 69, 72, 0, 69, 65, 0],
    [67, 0, 71, 74, 0, 71, 67, 74],
]

# メニュー（D major・I-V-vi-IV を2周・16分音符グリッド・128BPM）
M_TEMPO = 128
M_ROOT = [50, 45, 47, 43, 50, 45, 47, 43]
M_CHORD = [[62, 66, 69], [61, 64, 69], [62, 66, 71], [62, 67, 71]]
M_BASS = [0, 3, 6, 8, 11, 14]
M_LEAD = [
    [74, 0, 0, 78, 0, 0, 76, 0, 74, 0, 0, 71, 0, 0, 69, 0],
    [73, 0, 0, 76, 0, 0, 73, 0, 69, 0, 0, 73, 0, 0, 76, 0],
    [71, 0, 0, 74, 0, 0, 78, 0, 76, 0, 74, 0, 71, 0, 0, 0],
    [71, 0, 74, 0, 79, 0, 0, 74, 71, 0, 0, 67, 0, 0, 71, 74],
    [78, 0, 78, 81, 0, 78, 76, 0, 74, 0, 76, 78, 0, 0, 81, 0],
    [76, 0, 76, 73, 0, 76, 73, 0, 69, 0, 73, 76, 0, 0, 81, 0],
    [78, 0, 74, 78, 0, 81, 78, 0, 76, 74, 71, 74, 0, 0, 0, 0],
    [79, 0, 76, 74, 0, 71, 74, 0, 76, 0, 74, 71, 0, 0, 69, 73],
]


def render_game(tempo, heat):
    spb = 60.0 / tempo / 2.0
    steps = 32
    m = Mix(steps * spb, loop=True)
    for step in range(steps):
        bar = (step >> 3) & 3
        s = step & 7
        t = step * spb
        n = G_LEAD[bar][s]
        if s % 2 == 0:
            m.osc(t, 'triangle', m2f(G_ROOT[bar] + (12 if s == 4 else 0)), None, spb * 1.6, 0.22)
        if n:
            m.osc(t, 'square', m2f(n), None, spb * 0.9, 0.05)
        if heat and n:
            m.osc(t, 'sawtooth', m2f(n + 12), None, spb * 0.5, 0.035)
        if s % 2 == 1:
            m.noise(t, 0.04, 0.09 if heat else 0.05, 9000, 6000)
        if s % 4 == 0 or (heat and s % 4 == 2):
            m.osc(t, 'sine', 120, 45, 0.12, 0.3)
    return m.buf


def render_menu():
    spb = 60.0 / M_TEMPO / 4.0
    steps = 128
    m = Mix(steps * spb, loop=True)
    for step in range(steps):
        bar = (step >> 4) & 7
        s = step & 15
        t = step * spb
        n = M_LEAD[bar][s]
        if n:
            m.osc(t, 'square', m2f(n), None, spb * 1.7, 0.05)
            m.osc(t, 'triangle', m2f(n + 12), None, spb * 1.2, 0.03)
        if s in M_BASS:
            m.osc(t, 'triangle', m2f(M_ROOT[bar]), None, spb * 1.8, 0.26)
        if s % 4 == 2:
            for c in M_CHORD[bar & 3]:
                m.osc(t, 'square', m2f(c), None, spb * 1.2, 0.022)
        if s % 4 == 0:
            m.osc(t, 'sine', 150, 42, 0.14, 0.34)
        if s == 4 or s == 12:
            m.noise(t, 0.12, 0.16, 7000, 1800)
            m.osc(t, 'triangle', 220, 120, 0.08, 0.1)
        if s % 2 == 1:
            m.noise(t, 0.03, 0.045, 9000, 6000)
    return m.buf


# --------------------------------------------------------------------------- SE


def se_mix(seconds):
    return Mix(seconds + 0.05, loop=False)


def se_place():
    m = se_mix(0.09)
    m.osc(0, 'sine', 560, 300, 0.09, 0.5)
    return m.buf


def se_flip(k):
    m = se_mix(0.06)
    m.osc(0, 'triangle', 620 + (k % 6) * 60, None, 0.06, 0.25)
    return m.buf


def se_ding():
    m = se_mix(0.45)
    m.osc(0, 'sine', 880, None, 0.25, 0.4)
    m.osc(0.1, 'sine', 1320, None, 0.35, 0.4)
    return m.buf


def se_pass():
    m = se_mix(0.4)
    m.osc(0, 'triangle', 420, 190, 0.4, 0.5)
    return m.buf


def se_siren():
    m = se_mix(4 * 0.13 + 0.12)
    for i in range(4):
        m.osc(i * 0.13, 'square', 660 if i % 2 else 440, None, 0.12, 0.18)
    return m.buf


def se_stress2():
    m = se_mix(0.32)
    m.osc(0, 'sine', 1500, 3000, 0.09, 0.3)
    m.osc(0.04, 'sawtooth', 310, 190, 0.28, 0.28)
    m.osc(0.04, 'sawtooth', 295, 180, 0.28, 0.2)
    m.noise(0, 0.2, 0.35, 2500, 200)
    return m.buf


def se_stress3():
    m = se_mix(0.85)
    m.osc(0, 'sine', 1500, 3000, 0.09, 0.3)
    m.osc(0.05, 'sawtooth', 233, 120, 0.8, 0.38)
    m.osc(0.05, 'sawtooth', 247, 125, 0.8, 0.32)
    m.osc(0.05, 'square', 98, 40, 0.5, 0.35)
    m.noise(0, 0.6, 0.7, 5000, 140)
    m.osc(0.14, 'sine', 2400, 3400, 0.12, 0.22)
    return m.buf


def se_hold(d=0.9):
    """台パン長押し：ゴゴゴ…と低い音が昇り、キーンという高音が重なる。900ms で最大"""
    n = int(round(d * SR))
    t = (np.arange(n) + 0.5) / SR
    f = 40.0 * (150.0 / 40.0) ** (t / d)
    ph = 2.0 * math.pi * np.cumsum(f) / SR
    saw = _wave('sawtooth', ph, f)
    sos = butter(2, 420.0 / NYQ, btype='low', output='sos')
    saw = sosfilt(sos, saw)
    g1 = 0.0001 * (0.55 / 0.0001) ** (t / d)
    f2 = 300.0 * (1800.0 / 300.0) ** (t / d)
    ph2 = 2.0 * math.pi * np.cumsum(f2) / SR
    g2 = 0.0001 * (0.16 / 0.0001) ** (t / d)
    return saw * g1 + np.sin(ph2) * g2


def se_smash():
    m = se_mix(0.8)
    m.noise(0, 0.8, 1.0, 4000, 110)
    m.osc(0, 'sine', 150, 32, 0.7, 1.0)
    m.osc(0, 'square', 95, 38, 0.25, 0.35)
    return m.buf


def se_land():
    m = se_mix(5 * 0.05 + 0.07)
    freqs = np.random.default_rng(7).uniform(300, 800, 6)
    for i in range(6):
        m.osc(i * 0.05, 'triangle', float(freqs[i]), None, 0.07, 0.25)
    return m.buf


def se_win():
    m = se_mix(1.2)
    for i, n in enumerate([72, 76, 79, 84, 79, 84]):
        m.osc(i * 0.13, 'square', m2f(n), None, 0.28, 0.22)
    m.osc(0, 'sawtooth', m2f(48), None, 1.2, 0.2)
    return m.buf


def se_funny():
    m = se_mix(1.65)
    m.osc(0.6, 'sine', 1400, 280, 0.6, 0.35)
    m.osc(1.3, 'sine', 300, 1100, 0.35, 0.3)
    return m.buf


# --------------------------------------------------------------------------- 書き出し

BGM_FILES = [
    ('bgm_menu', lambda: render_menu()),
    ('bgm_game', lambda: render_game(112, False)),
    ('bgm_heat', lambda: render_game(168, True)),
]

SE_FILES = [
    ('se_place', se_place),
    ('se_ding', se_ding),
    ('se_pass', se_pass),
    ('se_siren', se_siren),
    ('se_stress2', se_stress2),
    ('se_stress3', se_stress3),
    ('se_hold', se_hold),
    ('se_smash', se_smash),
    ('se_land', se_land),
    ('se_win', se_win),
    ('se_funny', se_funny),
] + [('se_flip%d' % k, (lambda kk=k: se_flip(kk))) for k in range(6)]


def finish(x, bus, loop):
    """バス音量を掛け、ピークが大きすぎれば全体を下げ、SE は終端を 5ms でなめらかに閉じる"""
    y = x * bus
    if not loop:
        k = int(0.005 * SR)
        if len(y) > k:
            y[-k:] *= np.linspace(1.0, 0.0, k)
    peak = float(np.max(np.abs(y))) if len(y) else 0.0
    scale = 1.0
    if peak > PEAK_LIMIT:
        scale = PEAK_LIMIT / peak
        y = y * scale
    return y, peak, scale


def to_int16(y):
    return np.clip(np.round(y * 32767.0), -32768, 32767).astype(np.int16)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', default=os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'assets', 'audio'))
    ap.add_argument('--check', action='store_true', help='書き出さずに確認だけする')
    args = ap.parse_args()
    out = os.path.abspath(args.out)
    if not args.check:
        os.makedirs(out, exist_ok=True)

    print('%-12s %8s %8s %8s %6s' % ('file', 'sec', 'peak', 'rms', 'scale'))
    jobs = [(n, f, BGM_BUS, True) for n, f in BGM_FILES] + [(n, f, SE_BUS, False) for n, f in SE_FILES]
    for name, fn, bus, loop in jobs:
        x = fn()
        y, peak, scale = finish(np.asarray(x, dtype=np.float64), bus, loop)
        rms = float(np.sqrt(np.mean(y * y)))
        print('%-12s %8.3f %8.3f %8.3f %6.2f' % (name, len(y) / SR, peak, rms, scale))
        if not args.check:
            wavfile.write(os.path.join(out, name + '.wav'), SR, to_int16(y))
    if not args.check:
        print('-> %s' % out)


if __name__ == '__main__':
    sys.exit(main())
