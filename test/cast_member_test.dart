import 'package:flutter_test/flutter_test.dart';
import 'package:ne_izlesem/models/cast_member.dart';

void main() {
  group('CastMember.fromJson', () {
    test('reads character straight off movie credits', () {
      final member = CastMember.fromJson({
        'id': 12,
        'name': 'Tilda Swinton',
        'profile_path': '/abc.jpg',
        'character': 'The Ancient One',
      });

      expect(member.id, 12);
      expect(member.name, 'Tilda Swinton');
      expect(member.character, 'The Ancient One');
      expect(member.profilePath, '/abc.jpg');
    });

    test('prefers the first role from TV aggregate_credits', () {
      final member = CastMember.fromJson({
        'id': 3,
        'name': 'Pedro Pascal',
        'roles': [
          {'character': 'Joel Miller'},
          {'character': 'Narrator'},
        ],
        // aggregate_credits ayrıca bir character alanı taşıyabilir; roles kazanır.
        'character': 'yok sayılmalı',
      });

      expect(member.character, 'Joel Miller');
    });

    test('falls back to the character field when roles is empty', () {
      final member = CastMember.fromJson({
        'id': 4,
        'name': 'Bella Ramsey',
        'roles': <dynamic>[],
        'character': 'Ellie',
      });

      expect(member.character, 'Ellie');
    });

    test('tolerates a missing character on both shapes', () {
      expect(CastMember.fromJson({'id': 5, 'name': 'X'}).character, '');
      expect(
        CastMember.fromJson({
          'id': 6,
          'name': 'Y',
          'roles': [<String, dynamic>{}],
        }).character,
        '',
      );
    });

    test('tolerates a missing name', () {
      expect(CastMember.fromJson({'id': 8}).name, '');
    });

    test('keeps profilePath null when TMDB sends none', () {
      final member = CastMember.fromJson({
        'id': 9,
        'name': 'Z',
        'profile_path': null,
        'character': 'Extra',
      });

      expect(member.profilePath, isNull);
    });
  });

  group('CastMember.profileUrl', () {
    test('builds a w185 TMDB url when a path exists', () {
      const member = CastMember(
        id: 1,
        name: 'A',
        profilePath: '/pic.jpg',
        character: 'C',
      );

      expect(member.profileUrl, 'https://image.tmdb.org/t/p/w185/pic.jpg');
    });

    test('is empty rather than a broken url when the path is null', () {
      const member = CastMember(id: 1, name: 'A', character: 'C');

      expect(member.profileUrl, '');
    });
  });
}
