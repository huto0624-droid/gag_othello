import 'package:flutter/foundation.dart';

/// 画面の下に赤い「エラー表示」を出すかどうか。
///
/// - 開発中（`flutter run`）：出す
/// - 公開用ビルド（`flutter build web --release`）：ふつうは出さない（遊んでいる人にエラー文を見せない）
/// - 公開版でも、ページのアドレスの最後に `?debug=1` を付けて開くと出る
///   （例：https://ユーザー名.github.io/リポジトリ名/?debug=1）。動かないときの原因を読むために使う
/// - ビルドのときに常に出したい場合：`flutter build web --release --dart-define=SHOW_ERRORS=true`
const bool _kShowErrorsInBuild = bool.fromEnvironment('SHOW_ERRORS', defaultValue: !kReleaseMode);

bool get kShowErrorBanner {
  if (_kShowErrorsInBuild) return true;
  try {
    return Uri.base.queryParameters['debug'] == '1';
  } catch (_) {
    return false;
  }
}

/// 画面の下に出す「エラー表示」の中身（null なら出さない）。
/// 何かが失敗したとき、原因をそのまま画面で読めるようにする。
/// 画面が進まない・固まったときに、このメッセージを教えてもらえれば原因を絞れる。
final ValueNotifier<String?> errorBanner = ValueNotifier<String?>(null);

void reportError(Object error) {
  final text = '$error';
  debugPrint('gag_othello error: $text');
  if (!kShowErrorBanner) return;
  errorBanner.value = text.length > 700 ? text.substring(0, 700) : text;
}
