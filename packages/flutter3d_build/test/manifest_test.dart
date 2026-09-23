import 'dart:io';

import 'package:flutter3d_build/flutter3d_build.dart';
import 'package:flutter3d_core/formats.dart';
import 'package:test/test.dart';

void main() {
  group('AssetManifest.parse', () {
    test('an empty file is the empty manifest', () {
      expect(AssetManifest.parse('').rules, isEmpty);
    });

    test('an explicit, empty "rules" list is the empty manifest', () {
      expect(AssetManifest.parse('rules: []').rules, isEmpty);
    });

    test('one rule with just a glob parses, and matches by that glob', () {
      final manifest = AssetManifest.parse('''
rules:
  - glob: "characters/**"
''');
      expect(manifest.rules, hasLength(1));
      expect(manifest.ruleFor('characters/hero.glb'), isNotNull);
      expect(manifest.ruleFor('props/chair.glb'), isNull);
    });

    test('textures, mips, objNormals and exclude all parse', () {
      final manifest = AssetManifest.parse('''
rules:
  - glob: "**/*.obj"
    textures: etc2
    mips: false
    objNormals: flat
    exclude: false
''');
      final rule = manifest.ruleFor('props/a.obj')!;
      expect(rule.textures, TextureFamily.etc2);
      expect(rule.mips, isFalse);
      expect(rule.objNormals, ObjNormals.flat);
      expect(rule.exclude, isFalse);
    });

    test('"**/*.obj" matches a root-level file as well as a nested one, '
        'package:glob\'s rule since 2.2.0, held here so a later glob that '
        'changes it again fails in this test and not in somebody\'s '
        'manifest', () {
      final manifest = AssetManifest.parse('''
rules:
  - glob: "**/*.obj"
    exclude: true
''');
      expect(manifest.ruleFor('a.obj'), isNotNull);
      expect(manifest.ruleFor('props/a.obj'), isNotNull);
    });

    test('the last matching rule wins over an earlier, broader one', () {
      final manifest = AssetManifest.parse('''
rules:
  - glob: "**/*.glb"
    textures: bc
  - glob: "ui/**"
    exclude: true
''');
      expect(manifest.ruleFor('ui/icon.glb')!.exclude, isTrue);
      expect(
        manifest.ruleFor('characters/hero.glb')!.textures,
        TextureFamily.bc,
      );
    });

    test('an unknown top-level key names its own line', () {
      expect(
        () => AssetManifest.parse('rules: []\ntypo: 1\n'),
        throwsA(
          isA<ManifestFormatException>()
              .having((e) => e.line, 'line', 2)
              .having((e) => e.message, 'message', contains('typo')),
        ),
      );
    });

    test('an unknown key inside a rule names its own line', () {
      expect(
        () => AssetManifest.parse('''
rules:
  - glob: "*.glb"
    compresion: bc
'''),
        throwsA(
          isA<ManifestFormatException>()
              .having((e) => e.line, 'line', 3)
              .having((e) => e.message, 'message', contains('compresion')),
        ),
      );
    });

    test('a bad glob names its own line, not the top of the file', () {
      expect(
        () => AssetManifest.parse('''
rules:
  - glob: "hero.glb"
  - glob: "["
'''),
        throwsA(
          isA<ManifestFormatException>().having((e) => e.line, 'line', 3),
        ),
      );
    });

    test('an unknown texture family names the line and the allowed values', () {
      expect(
        () => AssetManifest.parse('''
rules:
  - glob: "*.glb"
    textures: astc
'''),
        throwsA(
          isA<ManifestFormatException>()
              .having((e) => e.line, 'line', 3)
              .having((e) => e.message, 'message', contains('auto')),
        ),
      );
    });

    test('a rule with no glob names its own line', () {
      expect(
        () => AssetManifest.parse('''
rules:
  - textures: bc
'''),
        throwsA(
          isA<ManifestFormatException>().having((e) => e.line, 'line', 2),
        ),
      );
    });

    test('"rules" as a scalar rather than a list names its own line', () {
      expect(
        () => AssetManifest.parse('rules: yes'),
        throwsA(
          isA<ManifestFormatException>().having((e) => e.line, 'line', 1),
        ),
      );
    });

    test('genuinely broken YAML syntax still names a line', () {
      expect(
        () => AssetManifest.parse('rules: [\n'),
        throwsA(isA<ManifestFormatException>()),
      );
    });
  });

  group('AssetManifest.readFrom', () {
    test('a project with no manifest file gets the empty manifest', () {
      final manifest = AssetManifest.readFrom(
        Directory.systemTemp.createTempSync('f3d_no_manifest_'),
      );
      expect(manifest.rules, isEmpty);
    });
  });
}
