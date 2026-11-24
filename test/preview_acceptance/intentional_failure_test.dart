import 'package:flutter_test/flutter_test.dart';

// Disposable: proves a failing check blocks the PR preview deploy. Never merge.
void main() {
  test('intentional failure for preview acceptance', () {
    expect(1, 2);
  });
}
