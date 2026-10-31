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

  /// 通常顔（目の位置あわせあり。炎が出る）
  static const String normal = 'normal';

  /// 変顔（勝ったとき画面いっぱいに出る）
  static const String funny = 'funny';

  static const List<String> all = <String>[normal, funny];
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
