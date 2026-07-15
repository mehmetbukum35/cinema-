import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ne_izlesem/widgets/responsive_layout.dart';

import 'helpers/widget_test_helpers.dart';
import 'support/responsive_test_matrix.dart';

void main() {
  responsiveTestWidgets(
    'AdaptiveLabelValueRow handles long localized text',
    (testCase) => pumpApp(
      Scaffold(
        body: Center(
          child: SizedBox(
            width: 280,
            child: AdaptiveLabelValueRow(
              label: const Text('Kişisel Beğeni Uyumu'),
              value: const Text(
                'Kişisel uyum henüz hesaplanmadı ve daha sonra güncellenecek',
                textAlign: TextAlign.end,
              ),
            ),
          ),
        ),
      ),
      locale: testCase.locale,
      mediaQueryData: testCase.mediaQueryData,
    ),
  );

  responsiveTestWidgets(
    'ResponsiveAlertDialog scrolls long content safely',
    (testCase) => pumpApp(
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => ResponsiveAlertDialog(
                  title: const Text('Uzun içerik testi'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(
                      12,
                      (index) => Text(
                        'Dar ekranlarda taşmaması gereken uzun açıklama ${index + 1}',
                      ),
                    ),
                  ),
                ),
              ),
              child: const Text('Aç'),
            ),
          ),
        ),
      ),
      locale: testCase.locale,
      mediaQueryData: testCase.mediaQueryData,
    ),
    verify: (tester, testCase) async {
      await tester.tap(find.text('Aç'));
      await tester.pumpAndSettle();
      expect(find.text('Uzun içerik testi'), findsOneWidget);
    },
  );
}
