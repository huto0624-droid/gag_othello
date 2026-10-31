import 'dart:async';
import 'dart:ui' as ui;

/// コマ（顔）の表情
enum Mood {
  normal,

  /// 優勢：サングラスのドヤ顔
  smug,

  /// 劣勢：涙と汗の焦り顔
  panic,

  /// ヒートアップ：目が炎
  fire,
}

/// バナー文字の色
enum BannerStyle { paper, red, gold }

/// 画面全体の揺れ
enum ShakeKind { none, medium, large }

/// 盤の1マスぶんの見た目（アニメーション用の途中状態を含む）
class CellVisual {
  /// 表示中のオーナー（0=空）
  int owner = 0;

  /// ひっくり返り中の裏側のオーナー
  int toOwner = 0;

  /// 0=なし / 0〜0.5=表が横を向く / 0.5〜1=裏が正面に戻る
  double flip = 0;
  double scale = 1;
  double opacity = 1;

  /// 回転（ラジアン）
  double rot = 0;

  /// 台パンで飛ぶときのずれ（盤の幅に対する割合）
  ui.Offset offset = ui.Offset.zero;

  /// 置けないマスを押したときの横揺れ（0〜1）
  double nope = 0;

  void reset(int o) {
    owner = o;
    toOwner = o;
    flip = 0;
    scale = 1;
    opacity = 1;
    rot = 0;
    offset = ui.Offset.zero;
  }
}

/// 画面中央に出る大きな文字（かど！ / ドーン！ など）
class BannerSpec {
  const BannerSpec(this.id, this.text, this.style, this.seconds);

  final int id;
  final String text;
  final BannerStyle style;
  final double seconds;
}

/// ストレスを食らった演出1回ぶん。level 1=ゲージだけ / 2=揺れ＋怒りマーク / 3=画面フラッシュ＋爆発
class StressFx {
  const StressFx(this.id, this.level, this.total, this.label);

  final int id;
  final int level;
  final int total;
  final String label;
}

/// 台パンの長押し中の状態
class HoldState {
  HoldState(this.p, this.auto, this.timer);

  final int p;

  /// CPU が自動で押している
  final bool auto;
  final Timer timer;
}

/// プレイヤーパネルの表示内容（描画用の写し）
class PanelState {
  String name = '';
  int count = 2;
  int gauge = 0;
  bool max = false;
  bool sealed = false;
  bool active = false;
  bool tense = false;
  bool rage = false;
  Mood mood = Mood.normal;
  String note = '';
  String btnSub = '';

  /// 台パンボタンが押せる状態か
  bool btnReady = false;
}

/// 終局の結果
class EndingInfo {
  const EndingInfo(this.win, this.n1, this.n2);

  /// 0=引き分け
  final int win;
  final int n1;
  final int n2;
}
