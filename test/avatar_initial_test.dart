import 'package:flutter_test/flutter_test.dart';
import 'package:ne_izlesem/utils/avatar_initial.dart';

void main() {
  group('avatarInitial', () {
    test('primary adın ilk harfini büyütür', () {
      expect(avatarInitial('mehmet'), 'M');
    });

    test('boş primary için fallback (username) kullanılır', () {
      // display_name "" olarak gelebildiği için asıl regresyon senaryosu bu.
      expect(avatarInitial('', 'ahmet'), 'A');
    });

    test('whitespace-only primary boş sayılır, fallback kullanılır', () {
      expect(avatarInitial('   ', 'ahmet'), 'A');
    });

    test('null primary için fallback kullanılır', () {
      expect(avatarInitial(null, 'zeynep'), 'Z');
    });

    test('primary ve fallback boşsa çökmeden "?" döner', () {
      expect(avatarInitial('', ''), '?');
      expect(avatarInitial(null, null), '?');
      expect(avatarInitial('  '), '?');
    });
  });
}
