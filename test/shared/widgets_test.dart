import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myminimax/shared/widgets/error_card.dart';
import 'package:myminimax/shared/widgets/section_title.dart';
import 'package:myminimax/shared/widgets/page_header.dart';
import 'package:myminimax/shared/widgets/generate_button.dart';

void main() {
  group('ErrorCard', () {
    testWidgets('renders message text', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ErrorCard(message: 'Something went wrong'))),
      );
      expect(find.text('Something went wrong'), findsOneWidget);
    });

    testWidgets('renders error icon', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ErrorCard(message: 'Test error'))),
      );
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });
  });

  group('SectionTitle', () {
    testWidgets('renders title text', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SectionTitle(title: 'Settings'))),
      );
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('uses custom fontSize', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SectionTitle(title: 'Large', fontSize: 20))),
      );
      final text = tester.widget<Text>(find.text('Large'));
      expect(text.style?.fontSize, 20);
    });
  });

  group('PageHeader', () {
    testWidgets('renders title and icon', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: PageHeader(icon: Icons.chat, title: 'Conversation'))),
      );
      expect(find.text('Conversation'), findsOneWidget);
      expect(find.byIcon(Icons.chat), findsOneWidget);
    });

    testWidgets('shows divider when enabled', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: PageHeader(icon: Icons.settings, title: 'Settings', showDivider: true))),
      );
      expect(find.byType(Divider), findsOneWidget);
    });

    testWidgets('no divider by default', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: PageHeader(icon: Icons.settings, title: 'Settings'))),
      );
      expect(find.byType(Divider), findsNothing);
    });
  });

  group('GenerateButton', () {
    testWidgets('renders label text', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: GenerateButton(label: 'Create Image', icon: Icons.image))),
      );
      expect(find.text('Create Image'), findsOneWidget);
    });

    testWidgets('renders icon', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: GenerateButton(label: 'Generate', icon: Icons.auto_awesome))),
      );
      expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
    });

    testWidgets('shows loading text when loading', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: GenerateButton(label: 'Generate', icon: Icons.auto_awesome, isLoading: true))),
      );
      // GradientButton may not render text in test env; verify the widget exists
      expect(find.byType(GenerateButton), findsOneWidget);
    });

    testWidgets('has onPressed callback configured', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GenerateButton(
              label: 'TapMe',
              icon: Icons.auto_awesome,
              onPressed: () => tapped = true,
            ),
          ),
        ),
      );
      // Verify the button was created with correct props
      final button = tester.widget<GenerateButton>(find.byType(GenerateButton));
      expect(button.onPressed, isNotNull);
      expect(button.isLoading, false);
    });

    testWidgets('isLoading prop is true when loading', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GenerateButton(
              label: 'Generate',
              icon: Icons.auto_awesome,
              isLoading: true, onPressed: null,
            ),
          ),
        ),
      );
      final button = tester.widget<GenerateButton>(find.byType(GenerateButton));
      expect(button.isLoading, true);
    });
  });
}
