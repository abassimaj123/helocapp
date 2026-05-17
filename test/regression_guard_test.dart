import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:heloc_app/core/heloc_engine.dart';

void main() {
  group('Format — affichage', () {
    test('Formatage currency USD', () {
      final fmt = NumberFormat.currency(locale: 'en_US', symbol: r'$');
      expect(fmt.format(50000), r'$50,000.00');
    });

    test('LTV formaté en pourcentage', () {
      final fmt = NumberFormat('#,##0.0');
      expect(fmt.format(75.5), '75.5');
    });
  });

  group('Widget — éléments UI de base', () {
    testWidgets('Card équité disponible affiche montant', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Card(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Text('Available Equity'),
                  Text(r'$150,000.00',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.text('Available Equity'), findsOneWidget);
      expect(find.text(r'$150,000.00'), findsOneWidget);
    });

    testWidgets('Champ taux HELOC accepte valeur', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TextField(
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: 'HELOC Rate (%)'),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), '8.5');
      expect(find.text('8.5'), findsOneWidget);
    });
  });

  group('Regression guard — HelocEngine', () {
    test('RG-1: équité disponible = valeur × 85% - hypothèque', () {
      // Maison 500k, hypothèque 200k → 500k × 85% - 200k = 225k
      final available = HelocEngine.availableEquity(500000, 200000);
      expect(available, closeTo(225000, 5000));
    });

    test('RG-2: LTV = solde / valeur × 100', () {
      expect(HelocEngine.ltv(200000, 500000), closeTo(40.0, 0.1));
      expect(HelocEngine.ltv(400000, 500000), closeTo(80.0, 0.1));
    });

    test('RG-3: paiement intérêt seulement 50k @ 8.5%', () {
      final payment = HelocEngine.interestOnlyPayment(50000, 8.5);
      expect(payment, closeTo(354.17, 1.0));
    });

    test('RG-4: paiement amorti 50k @ 8.5% / 10 ans', () {
      final payment = HelocEngine.amortizedPayment(50000, 8.5, 10);
      expect(payment, closeTo(619.0, 10.0));
    });

    test('RG-5: capacité max emprunt respecte LTV 85% (défaut)', () {
      final max = HelocEngine.maxBorrowCapacity(500000, 200000);
      // Max = 500k × 85% - 200k = 225k
      expect(max, closeTo(225000, 1000));
    });
  });
}
