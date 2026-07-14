import 'package:flutter_test/flutter_test.dart';
import 'package:ne_izlesem/utils/username_helper.dart';

void main() {
  group('validateUsername', () {
    test('accepts valid usernames', () {
      expect(validateUsername('mehmet21'), isNull);
      expect(validateUsername('user_name'), isNull);
    });

    test('rejects empty and invalid formats', () {
      expect(validateUsername(''), 'please_enter_a_username');
      expect(validateUsername('ab'), 'username_invalid_format');
      expect(validateUsername('bad-name'), 'username_invalid_format');
    });
  });

  group('needsUsername', () {
    test('returns true when username missing', () {
      expect(needsUsername({'id': 1}), isTrue);
      expect(needsUsername({'id': 1, 'username': ''}), isTrue);
    });

    test('returns false when username set', () {
      expect(needsUsername({'id': 1, 'username': 'mehmet'}), isFalse);
    });
  });
}
