import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class ResponsiveTestCase {
  final String name;
  final Size size;
  final Locale locale;
  final double textScale;

  const ResponsiveTestCase({
    required this.name,
    required this.size,
    required this.locale,
    required this.textScale,
  });

  MediaQueryData get mediaQueryData => MediaQueryData(
    size: size,
    textScaler: TextScaler.linear(textScale),
    disableAnimations: true,
  );
}

const responsiveTestCases = <ResponsiveTestCase>[
  ResponsiveTestCase(
    name: 'compact-tr',
    size: Size(320, 568),
    locale: Locale('tr', 'TR'),
    textScale: 1,
  ),
  ResponsiveTestCase(
    name: 'compact-large-text-tr',
    size: Size(360, 640),
    locale: Locale('tr', 'TR'),
    textScale: 1.3,
  ),
  ResponsiveTestCase(
    name: 'phone-large-text-en',
    size: Size(393, 852),
    locale: Locale('en', 'US'),
    textScale: 1.3,
  ),
  ResponsiveTestCase(
    name: 'tablet-accessibility-tr',
    size: Size(600, 960),
    locale: Locale('tr', 'TR'),
    textScale: 2,
  ),
];

typedef ResponsiveWidgetBuilder = Widget Function(ResponsiveTestCase testCase);
typedef ResponsiveVerify =
    Future<void> Function(WidgetTester tester, ResponsiveTestCase testCase);

void expectNoResponsiveLayoutException(
  WidgetTester tester, {
  required String stage,
}) {
  final exception = tester.takeException();
  expect(
    exception,
    isNull,
    reason: 'Responsive layout failed at $stage: $exception',
  );
}

/// Aynı widget senaryosunu dar telefon, büyük yazı ve tablet profillerinde
/// çalıştırır. RenderFlex/viewport gibi Flutter yerleşim hataları otomatik
/// olarak [takeException] üzerinden testi başarısız yapar.
void responsiveTestWidgets(
  String description,
  ResponsiveWidgetBuilder builder, {
  ResponsiveVerify? verify,
  List<ResponsiveTestCase> cases = responsiveTestCases,
}) {
  for (final testCase in cases) {
    testWidgets('$description [${testCase.name}]', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = testCase.size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(builder(testCase));
      await tester.pump();
      await verify?.call(tester, testCase);

      final exception = tester.takeException();
      final details = exception is FlutterError
          ? exception.toStringDeep()
          : exception?.toString();
      expect(
        exception,
        isNull,
        reason: 'Responsive layout failed for ${testCase.name}: $details',
      );
    });
  }
}
