import 'package:flutter_test/flutter_test.dart';
import 'package:ne_izlesem/l10n/en.dart';
import 'package:ne_izlesem/l10n/tr.dart';

void main() {
  test('l10n keys parity between TR and EN maps', () {
    final trKeys = kTrStrings.keys.toSet();
    final enKeys = kEnStrings.keys.toSet();

    final missingInEn = trKeys.difference(enKeys);
    final missingInTr = enKeys.difference(trKeys);

    expect(
      missingInEn,
      isEmpty,
      reason: 'Keys present in TR but missing in EN: $missingInEn',
    );
    expect(
      missingInTr,
      isEmpty,
      reason: 'Keys present in EN but missing in TR: $missingInTr',
    );
  });
}
