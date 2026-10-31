#!/usr/bin/env python3
"""アプリに同梱する日本語フォント（Noto Sans CJK JP の Bold / Black）を作る。

ネットにつながらない環境や、Google Fonts を遮断するブラウザでも文字が出るよう、
フォントはアプリの中に入れてあります。ふつうは実行する必要はありません。作り直したいときだけ：

    pip install fonttools
    python3 tool/build_fonts.py --src /path/to/NotoSansCJK-Bold.ttc /path/to/NotoSansCJK-Black.ttc

- TTC から日本語（JP）の書体だけを取り出す
- 使う文字だけ残して軽くする：ASCII / かな / JIS X 0208（第1・第2水準の漢字、記号）/ ソースコード内の全文字
- ライセンスは SIL Open Font License 1.1（assets/fonts/OFL.txt）
"""
import argparse
import glob
import os
import re
import sys

from fontTools import subset
from fontTools.ttLib import TTCollection, TTFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))


def jis0208_chars():
    """JIS X 0208 の全文字（記号・かな・第1水準・第2水準の漢字）"""
    out = set()
    for hi in range(0xA1, 0xF5):
        for lo in range(0xA1, 0xFF):
            try:
                ch = bytes([hi, lo]).decode('euc_jp')
            except UnicodeDecodeError:
                continue
            if len(ch) == 1:
                out.add(ord(ch))
    return out


def source_chars():
    """lib/ と README のソースに出てくる全ての文字（画面に出す文言を取りこぼさないため）"""
    out = set()
    for f in glob.glob(os.path.join(ROOT, 'lib', '**', '*.dart'), recursive=True):
        out.update(ord(c) for c in open(f, encoding='utf-8').read())
    return out


def pick_jp(path):
    if path.lower().endswith('.ttc'):
        ttc = TTCollection(path, lazy=False)
        for f in ttc.fonts:
            fam = f['name'].getDebugName(1) or ''
            if fam.endswith(' JP') or ' JP ' in fam + ' ':
                return f
        raise SystemExit('JP の書体が見つかりません: ' + path)
    return TTFont(path)


def build(src, dst, unicodes):
    font = pick_jp(src)
    opts = subset.Options()
    opts.layout_features = ['kern', 'ccmp']
    opts.hinting = False
    opts.notdef_outline = True
    opts.glyph_names = False
    opts.name_IDs = ['*']
    opts.name_languages = ['*']
    opts.legacy_kern = False
    opts.drop_tables += ['DSIG']
    s = subset.Subsetter(opts)
    s.populate(unicodes=sorted(unicodes))
    s.subset(font)
    font.save(dst)
    print('%-28s %8.1f KB  (%d glyphs)' % (os.path.relpath(dst, ROOT), os.path.getsize(dst) / 1024.0, len(font.getGlyphOrder())))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--src', nargs=2, metavar=('BOLD', 'BLACK'), required=True)
    ap.add_argument('--out', default=os.path.join(ROOT, 'assets', 'fonts'))
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    uni = set(range(0x20, 0x7F)) | set(range(0xA0, 0x100)) | set(range(0x2010, 0x2030)) | set(range(0x3000, 0x3100)) \
        | set(range(0xFF00, 0xFFF0)) | jis0208_chars() | source_chars()
    uni.discard(0x0A)
    uni = {u for u in uni if u >= 0x20}
    print('文字数:', len(uni))
    build(a.src[0], os.path.join(a.out, 'GagGothic-Bold.otf'), uni)
    build(a.src[1], os.path.join(a.out, 'GagGothic-Black.otf'), uni)
    return 0


if __name__ == '__main__':
    sys.exit(main())
