/// いま動いているのがどの版か分かるように、タイトル画面の下に出す印。公開し直したのに古いままのときの確認用。
const String kBuildLabel = '2026-11-09 b';

/// あそびかた
enum GameMode {
  /// ひとりで：2P側はコンピュータ
  cpu,

  /// ふたりで：向かい合わせ・同じ画面
  twoPlayer,
}

/// 保存用の文字列 <-> GameMode
extension GameModeCodec on GameMode {
  String get code => this == GameMode.cpu ? 'cpu' : '2p';

  static GameMode fromCode(String? s) => s == '2p' ? GameMode.twoPlayer : GameMode.cpu;
}

/// 顔写真の種類
class FaceKind {
  FaceKind._();

  /// 顔（目の位置あわせあり。炎が出る。勝ったときは画面いっぱいに出る）
  static const String normal = 'normal';

  static const List<String> all = <String>[normal];
}

/// ゲージ増加の理由 → 画面に出す文言
String stressLabel(String reasonName) {
  switch (reasonName) {
    case 'corner':
      return '角を取られた！';
    case 'bigflip':
      return 'ごっそり返された！';
    case 'pass':
      return 'パスさせられた…';
    default:
      return 'じわじわ劣勢…';
  }
}
