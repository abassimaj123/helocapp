import 'package:flutter/material.dart';
import 'package:calcwise_core/calcwise_core.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) => CalcwiseOnboarding(
        appKey: 'helocapp',
        onDone: () => Navigator.of(context).pushReplacementNamed('/home'),
        pages: const [
          OnboardingPage(
            icon: Icons.account_balance_rounded,
            title: 'Unlock Your\nHome Equity',
            subtitle:
                'See how much you can borrow and what it costs month by month.',
            pills: ['Credit Line', 'Draw Period', 'Repayment'],
            titleFr: 'Libérez votre\nvaleur nette',
            subtitleFr:
                'Découvrez combien vous pouvez emprunter et ce que cela coûte chaque mois.',
            pillsFr: ['Marge de crédit', 'Période de retrait', 'Remboursement'],
            titleEs: 'Libera el valor\nde tu hogar',
            subtitleEs:
                'Descubre cuánto puedes pedir prestado y lo que cuesta mes a mes.',
            pillsEs: ['Línea de crédito', 'Período de retiro', 'Reembolso'],
          ),
          OnboardingPage(
            icon: Icons.trending_up_rounded,
            title: 'Plan Your\nDraw Strategy',
            subtitle:
                'Model interest-only draws vs accelerated repayment — side by side.',
            pills: ['Interest Only', 'Early Payoff', 'Variable Rate'],
            titleFr: 'Planifiez votre\nstratégie de retrait',
            subtitleFr:
                'Modélisez les retraits en intérêts seulement vs remboursement accéléré.',
            pillsFr: [
              'Intérêts seulement',
              'Remboursement rapide',
              'Taux variable'
            ],
            titleEs: 'Planifica tu\nestrategia de retiro',
            subtitleEs:
                'Modela retiros de solo intereses vs pago acelerado — lado a lado.',
            pillsEs: ['Solo intereses', 'Pago anticipado', 'Tasa variable'],
          ),
          OnboardingPage(
            icon: Icons.history_rounded,
            title: 'Save & Compare\nStrategies',
            subtitle:
                'Your HELOC scenarios are saved automatically. Revisit and compare anytime.',
            pills: ['History', 'PDF Export', 'Share'],
            titleFr: 'Sauvegardez et\ncomparez vos stratégies',
            subtitleFr:
                'Vos scénarios HELOC sont sauvegardés. Retrouvez-les et comparez à tout moment.',
            pillsFr: ['Historique', 'Export PDF', 'Partager'],
            titleEs: 'Guarda y compara\nestrategias',
            subtitleEs:
                'Tus escenarios HELOC se guardan automáticamente. Compáralos cuando quieras.',
            pillsEs: ['Historial', 'Exportar PDF', 'Compartir'],
          ),
        ],
      );
}
