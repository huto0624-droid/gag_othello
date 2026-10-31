import 'package:flutter/foundation.dart';

/// 画面の下に赤い「エラー表示」を出すかどうか。
///
/// - 開発中（`flutter run`）：出す
/// - 公開用ビルド（`flutter build web --release`）：出さない（遊んでいる人にエラー文を見せない）
/// - 公開前にテスターに試してもらうときだけ出したい：
///     `flutter build web --release --dart-define=SHOW_ERRORS=true`
const bool kShowErrorBanner = bool.fromEnvironment('SHOW_ERRORS', defaultValue: !kReleaseMode);

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
