import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:calcwise_core/calcwise_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Minimal host — no Firebase, no AdMob, no IAP.
Widget _host(Widget child) => MaterialApp(
      theme: ThemeData.light().copyWith(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00695C)),
        extensions: [CalcwiseTheme.light(primary: const Color(0xFF00695C))],
      ),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ResultTile', () {
    testWidgets('renders label and value', (tester) async {
      await tester.pumpWidget(_host(
        const ResultTile(label: 'Available Credit', value: r'$80,000'),
      ));
      await tester.pump();
      expect(find.text('Available Credit'), findsOneWidget);
      expect(find.text(r'$80,000'), findsOneWidget);
    });

    testWidgets('highlighted tile renders without error', (tester) async {
      await tester.pumpWidget(_host(
        const ResultTile(
          label: 'Interest-Only Payment',
          value: r'$367',
          isHighlight: true,
        ),
      ));
      await tester.pump();
      expect(find.text('Interest-Only Payment'), findsOneWidget);
      expect(find.text(r'$367'), findsOneWidget);
    });

    testWidgets('renders HELOC breakdown tiles', (tester) async {
      await tester.pumpWidget(_host(
        const Column(
          children: [
            ResultTile(label: 'Credit Limit', value: r'$120,000'),
            ResultTile(label: 'Current Balance', value: r'$40,000'),
            ResultTile(label: 'Available Credit', value: r'$80,000'),
            ResultTile(label: 'Prime Rate', value: '8.50%'),
          ],
        ),
      ));
      await tester.pump();
      expect(find.text('Credit Limit'), findsOneWidget);
      expect(find.text('Current Balance'), findsOneWidget);
      expect(find.text('Available Credit'), findsOneWidget);
      expect(find.text('Prime Rate'), findsOneWidget);
    });
  });

  group('CalcwiseHeroCard', () {
    testWidgets('renders label and value', (tester) async {
      await tester.pumpWidget(_host(
        const CalcwiseHeroCard(
          label: 'Monthly Payment',
          value: r'$367',
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('MONTHLY PAYMENT'), findsOneWidget);
      expect(find.text(r'$367'), findsOneWidget);
    });

    testWidgets('renders secondary text', (tester) async {
      await tester.pumpWidget(_host(
        const CalcwiseHeroCard(
          label: 'Monthly Payment',
          value: r'$367',
          secondary: 'Interest-only draw period',
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Interest-only draw period'), findsOneWidget);
    });

    testWidgets('renders stats row', (tester) async {
      await tester.pumpWidget(_host(
        const CalcwiseHeroCard(
          label: 'Monthly Payment',
          value: r'$367',
          stats: [
            (label: 'APR', value: '9.25%'),
            (label: 'Draw Period', value: '10 yrs'),
          ],
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('APR'), findsOneWidget);
      expect(find.text('DRAW PERIOD'), findsOneWidget);
    });

    testWidgets('renders badge', (tester) async {
      await tester.pumpWidget(_host(
        const CalcwiseHeroCard(
          label: 'Monthly Payment',
          value: r'$367',
          badges: [CalcwiseHeroBadge(label: 'Variable Rate')],
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Variable Rate'), findsOneWidget);
    });
  });

  group('SectionCard', () {
    testWidgets('renders title and children', (tester) async {
      await tester.pumpWidget(_host(
        const SectionCard(
          title: 'Draw Period',
          children: [
            ResultTile(label: 'Duration', value: '10 years'),
            ResultTile(label: 'Interest-Only Payment', value: r'$367'),
          ],
        ),
      ));
      await tester.pump();
      expect(find.text('Draw Period'), findsOneWidget);
      expect(find.text('Duration'), findsOneWidget);
      expect(find.text('Interest-Only Payment'), findsOneWidget);
    });

    testWidgets('renders repayment section', (tester) async {
      await tester.pumpWidget(_host(
        const SectionCard(
          title: 'Repayment Period',
          children: [
            ResultTile(label: 'Duration', value: '20 years'),
            ResultTile(label: 'Monthly Payment', value: r'$822'),
          ],
        ),
      ));
      await tester.pump();
      expect(find.text('Repayment Period'), findsOneWidget);
    });
  });

  group('CalcwiseEmptyState', () {
    testWidgets('renders icon and title', (tester) async {
      await tester.pumpWidget(_host(
        const CalcwiseEmptyState(
          icon: Icons.account_balance_rounded,
          title: 'No HELOC history',
        ),
      ));
      await tester.pump();
      expect(find.byIcon(Icons.account_balance_rounded), findsOneWidget);
      expect(find.text('No HELOC history'), findsOneWidget);
    });

    testWidgets('action button fires callback', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(_host(
        CalcwiseEmptyState(
          icon: Icons.calculate_rounded,
          title: 'No calculations',
          actionLabel: 'Calculate HELOC',
          onAction: () => tapped = true,
        ),
      ));
      await tester.pump();
      await tester.tap(find.text('Calculate HELOC'));
      expect(tapped, isTrue);
    });

    testWidgets('renders body text when provided', (tester) async {
      await tester.pumpWidget(_host(
        const CalcwiseEmptyState(
          icon: Icons.account_balance_rounded,
          title: 'No data',
          body: 'Enter your home equity details above.',
        ),
      ));
      await tester.pump();
      expect(find.text('Enter your home equity details above.'), findsOneWidget);
    });

    testWidgets('renders without action when not provided', (tester) async {
      await tester.pumpWidget(_host(
        const CalcwiseEmptyState(
          icon: Icons.account_balance_rounded,
          title: 'No data',
        ),
      ));
      await tester.pump();
      expect(find.byType(ElevatedButton), findsNothing);
    });
  });
}
