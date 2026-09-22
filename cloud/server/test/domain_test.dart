import 'package:flutter3d_models/src/domain/access.dart';
import 'package:flutter3d_models/src/domain/model.dart';
import 'package:flutter3d_models/src/domain/user.dart';
import 'package:flutter3d_models/src/mail/letters.dart';
import 'package:flutter3d_models/src/pages/format.dart';
import 'package:test/test.dart';

User _user(int id, {bool verified = true}) => User(
  id: id,
  email: 'u$id@example.com',
  handle: 'u$id',
  displayName: 'User $id',
  createdAt: DateTime.utc(2026),
  emailVerifiedAt: verified ? DateTime.utc(2026) : null,
);

ModelRecord _model({
  required int owner,
  Visibility visibility = Visibility.private,
}) => ModelRecord(
  id: 1,
  ownerId: owner,
  slug: 'chair',
  title: 'Chair',
  description: '',
  visibility: visibility,
  sourceFormat: 'glb',
  triangleCount: 12,
  sizeBytes: 100,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  hasPreview: false,
);

void main() {
  group('access', () {
    test('a private model is its owner\'s alone', () {
      final model = _model(owner: 1);
      expect(canView(model, _user(1)), isTrue);
      expect(canView(model, _user(2)), isFalse);
      expect(canView(model, null), isFalse);
    });

    test(
      'a public model is anybody\'s to see and still only its owner\'s to change',
      () {
        final model = _model(owner: 1, visibility: Visibility.public);
        expect(canView(model, null), isTrue);
        expect(canView(model, _user(2)), isTrue);
        expect(canEdit(model, _user(2)), isFalse);
        expect(canEdit(model, null), isFalse);
        expect(canEdit(model, _user(1)), isTrue);
      },
    );

    test('uploading waits for a confirmed address', () {
      expect(canUpload(_user(1)), isTrue);
      expect(canUpload(_user(1, verified: false)), isFalse);
      expect(canUpload(null), isFalse);
    });
  });

  group('model', () {
    test('slugify makes a readable path segment', () {
      expect(slugify('Old Oak Chair (v2)'), 'old-oak-chair-v2');
      expect(slugify('  ***  '), 'model');
      expect(slugify('Стул'), 'model');
      expect(slugify('a' * 100), hasLength(60));
    });

    test('the path carries the id, so equal titles do not collide', () {
      expect(_model(owner: 1).path, '/m/1-chair');
    });

    test('formatBytes picks the unit a person expects', () {
      expect(formatBytes(812), '812 B');
      expect(formatBytes(4300), '4.2 KB');
      expect(formatBytes(19500000), '18.6 MB');
    });

    test('a licence is found by its SPDX id, and an unknown one is none', () {
      expect(Licence.of('CC-BY-4.0'), Licence.ccBy);
      expect(Licence.of('MIT'), Licence.mit);
      expect(Licence.of('GPL-3.0'), isNull);
      expect(Licence.of(null), isNull);
      expect(Licence.cc0.requiresAttribution, isFalse);
      expect(Licence.mit.requiresAttribution, isTrue);
    });

    test(
      'a category is found by its column value, and an unknown one is none',
      () {
        expect(Category.of('characters'), Category.characters);
        expect(Category.of('bogus'), isNull);
        expect(Category.of(null), isNull);
      },
    );
  });

  group('format', () {
    test('groups digits in threes', () {
      expect(groupDigits(0), '0');
      expect(groupDigits(999), '999');
      expect(groupDigits(1000), '1,000');
      expect(groupDigits(1234567), '1,234,567');
      expect(groupDigits(-12345), '-12,345');
    });

    test('dates are ISO and in UTC', () {
      expect(isoDate(DateTime.utc(2026, 9, 1, 23, 30)), '2026-09-01');
    });

    test('plurals', () {
      expect(plural(1, 'model'), '1 model');
      expect(plural(2400, 'triangle'), '2,400 triangles');
    });
  });

  group('letters', () {
    test('a name cannot put markup into the letter', () {
      final letter = verificationLetter(
        to: 'ann@example.com',
        name: '<script>alert(1)</script>',
        link: Uri.parse('https://models.pleion.dev/verify?token=abc'),
      );
      expect(letter.html, isNot(contains('<script>')));
      expect(letter.html, contains('&lt;script&gt;'));
    });

    test('both forms carry the link', () {
      final link = Uri.parse('https://models.pleion.dev/reset?token=abc');
      final letter = resetLetter(
        to: 'ann@example.com',
        name: 'Ann',
        link: link,
      );
      expect(letter.text, contains('$link'));
      expect(letter.html, contains('$link'));
      expect(letter.subject, isNotEmpty);
    });
  });
}
