#!/usr/bin/env python3
"""`flutter create .` で プラットフォーム用フォルダを作ったあとに、1回だけ実行する補助スクリプト。

  python3 tool/post_create.py

やること（すでに入っていれば何もしません。何度実行しても同じ結果になります。手作業でやっても同じです）
  - iOS : ios/Runner/Info.plist に 写真ライブラリ / カメラの使用目的の説明文を追加
  - Web : web/index.html  … タイトル・説明・言語(ja)・テーマ色を設定し、読み込み中の画面を追加
          web/manifest.json … アプリ名・説明・色を設定（ホーム画面に追加したときの名前）
"""
import html
import json
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))

APP_NAME = 'ギャグオセロ'
APP_DESC = '顔写真がコマになる、格差解消のパーティーオセロ。台パンで逆転、負けても笑える。'
THEME = '#FFE45C'

PLIST_ADD = (
    '\t<key>NSPhotoLibraryUsageDescription</key>\n'
    '\t<string>顔写真をコマにするために、写真ライブラリから画像を選びます。写真は端末の外には送られません。</string>\n'
    '\t<key>NSCameraUsageDescription</key>\n'
    '\t<string>顔写真をコマにするために、カメラで撮影します。写真は端末の外には送られません。</string>\n'
)

# 読み込み中の画面。Flutter の画面は後ろから重なってくるので、消し忘れても邪魔にならない
SPLASH_STYLE = '''  <style id="gag-splash-style">
    html, body { margin: 0; height: 100%; background: #FFE45C; }
    #gag-splash {
      position: fixed; inset: 0; display: flex; flex-direction: column;
      align-items: center; justify-content: center; gap: 14px;
      background-color: #FFE45C;
      background-image: radial-gradient(#FFD21F 3px, transparent 3.5px);
      background-size: 22px 22px; color: #1C1233;
      font-family: "Hiragino Sans", "Yu Gothic", "Noto Sans JP", sans-serif; font-weight: 900;
    }
    #gag-splash .t { font-size: 34px; letter-spacing: 2px; text-shadow: 3px 3px 0 #fff; }
    #gag-splash .s { font-size: 14px; font-weight: 700; }
    #gag-splash .b { width: 160px; height: 10px; border: 3px solid #1C1233; border-radius: 8px; background: #fff; overflow: hidden; }
    #gag-splash .b i { display: block; width: 40%; height: 100%; background: #FF2638; animation: gag-slide 1.1s ease-in-out infinite alternate; }
    @keyframes gag-slide { from { margin-left: 0; } to { margin-left: 60%; } }
  </style>
'''

SPLASH_BODY = '''  <div id="gag-splash"><div class="t">ギャグオセロ</div><div class="b"><i></i></div><div class="s">よみこみ中…</div></div>
  <script>
    (function () {
      function done() { var e = document.getElementById('gag-splash'); if (e && e.parentNode) e.parentNode.removeChild(e); }
      window.addEventListener('flutter-first-frame', done);
      document.addEventListener('flutter-first-frame', done);
    })();
  </script>
'''


def patch_plist(path):
    if not os.path.exists(path):
        print('skip  (見つかりません) %s' % path)
        return
    s = open(path, encoding='utf-8').read()
    if 'NSPhotoLibraryUsageDescription' in s:
        print('ok    (追加済み)     %s' % path)
        return
    i = s.rfind('</dict>')
    if i < 0:
        print('NG    (</dict> が見つかりません。手作業で追加してください) %s' % path)
        return
    open(path, 'w', encoding='utf-8').write(s[:i] + PLIST_ADD + s[i:])
    print('patch %s' % path)


def set_meta(s, key, value, attr='name'):
    """<meta name="key" content="..."> を value にする。なければ </head> の前に足す。"""
    tag = '<meta %s="%s" content="%s">' % (attr, key, html.escape(value, quote=True))
    pat = re.compile(r'<meta\s+%s="%s"[^>]*>' % (attr, re.escape(key)), re.IGNORECASE)
    if pat.search(s):
        return pat.sub(lambda m: tag, s, count=1)
    return s.replace('</head>', '  %s\n</head>' % tag, 1)


def patch_index(path):
    if not os.path.exists(path):
        print('skip  (見つかりません) %s' % path)
        return
    orig = open(path, encoding='utf-8').read()
    s = orig

    # 言語
    if re.search(r'<html[^>]*\blang=', s, re.IGNORECASE):
        s = re.sub(r'(<html[^>]*\blang=")[^"]*(")', lambda m: m.group(1) + 'ja' + m.group(2), s, count=1, flags=re.IGNORECASE)
    else:
        s = re.sub(r'<html(\s[^>]*)?>', lambda m: '<html lang="ja"%s>' % (m.group(1) or ''), s, count=1, flags=re.IGNORECASE)

    # タイトルと各種メタ情報
    s = re.sub(r'<title>.*?</title>', lambda m: '<title>%s</title>' % APP_NAME, s, count=1, flags=re.DOTALL | re.IGNORECASE)
    s = set_meta(s, 'description', APP_DESC)
    s = set_meta(s, 'apple-mobile-web-app-title', APP_NAME)
    s = set_meta(s, 'theme-color', THEME)
    s = set_meta(s, 'og:title', APP_NAME, attr='property')
    s = set_meta(s, 'og:description', APP_DESC, attr='property')

    # 読み込み中の画面
    if 'id="gag-splash-style"' not in s:
        s = s.replace('</head>', SPLASH_STYLE + '</head>', 1)
    if 'id="gag-splash"' not in s:
        m = re.search(r'<body[^>]*>', s, re.IGNORECASE)
        if m:
            s = s[:m.end()] + '\n' + SPLASH_BODY + s[m.end():]
        else:
            print('NG    (<body> が見つかりません。読み込み画面は付けませんでした) %s' % path)

    if s == orig:
        print('ok    (設定済み)     %s' % path)
    else:
        open(path, 'w', encoding='utf-8').write(s)
        print('patch %s' % path)


def patch_manifest(path):
    if not os.path.exists(path):
        print('skip  (見つかりません) %s' % path)
        return
    try:
        data = json.load(open(path, encoding='utf-8'))
    except ValueError as e:
        print('NG    (JSON として読めません: %s) %s' % (e, path))
        return
    want = {
        'name': APP_NAME,
        'short_name': APP_NAME,
        'description': APP_DESC,
        'lang': 'ja',
        'background_color': THEME,
        'theme_color': THEME,
    }
    if all(data.get(k) == v for k, v in want.items()):
        print('ok    (設定済み)     %s' % path)
        return
    data.update(want)
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=4)
        f.write('\n')
    print('patch %s' % path)


def main():
    patch_plist(os.path.join(ROOT, 'ios', 'Runner', 'Info.plist'))
    patch_index(os.path.join(ROOT, 'web', 'index.html'))
    patch_manifest(os.path.join(ROOT, 'web', 'manifest.json'))
    return 0


if __name__ == '__main__':
    sys.exit(main())
