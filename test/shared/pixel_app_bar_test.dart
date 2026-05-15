import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myminimax/shared/widgets/pixel_app_bar.dart';

void main() {
  group('PixelAppBar', () {
    Widget wrap(Widget child) => MaterialApp(
          home: Scaffold(body: child),
        );

    testWidgets('renders title text', (tester) async {
      await tester.pumpWidget(wrap(const PixelAppBar(title: 'Settings')));
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('renders empty title as SizedBox', (tester) async {
      await tester.pumpWidget(wrap(const PixelAppBar(title: '')));
      expect(find.byType(SizedBox), findsOneWidget);
    });

    testWidgets('renders action widgets', (tester) async {
      await tester.pumpWidget(wrap(PixelAppBar(
        title: 'Test',
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: () {}),
          IconButton(icon: const Icon(Icons.more_vert), onPressed: () {}),
        ],
      )));

      expect(find.byIcon(Icons.search), findsOneWidget);
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
    });

    testWidgets('renders custom leading widget', (tester) async {
      await tester.pumpWidget(wrap(const PixelAppBar(
        title: 'Test',
        leading: Icon(Icons.menu),
      )));

      expect(find.byIcon(Icons.menu), findsOneWidget);
    });

    testWidgets('preferredSize is 56 height', (tester) async {
      const appBar = PixelAppBar(title: 'Test');
      expect(appBar.preferredSize.height, 56);
    });
  });
}
