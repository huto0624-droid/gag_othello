import 'package:flutter_test/flutter_test.dart';

// `flutter create .` が既定の widget_test.dart（存在しない MyApp を参照する）を足さないための置き場。
// ロジックのテストは engine_test.dart にある。
void main() {
  test('placeholder', () {
    expect(1 + 1, 2);
  });
}
