import 'package:flutter_test/flutter_test.dart';
import 'package:myminimax/app/theme.dart';

void main() {
  test('PixelTheme colors are available', () {
    expect(PixelTheme.primary, isNotNull);
    expect(PixelTheme.background, isNotNull);
    expect(PixelTheme.primaryText, isNotNull);
  });
}
