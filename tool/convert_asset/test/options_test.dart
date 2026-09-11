/// `ConvertAssetOptions.parse` on its own — `fmt-14`'s own row.
///
///     dart test test/options_test.dart
library;

import 'package:convert_asset/convert_asset.dart';
import 'package:test/test.dart';

void main() {
  group('ConvertAssetOptions.parse', () {
    test('the input and format are read, name defaults from the input', () {
      final options = ConvertAssetOptions.parse(<String>['teapot.glb', '-f', 'f3d']);
      expect(options, isNotNull);
      expect(options!.input, 'teapot.glb');
      expect(options.format, 'f3d');
      expect(options.name, 'teapot');
    });

    test('a path with directories keeps only the file\'s own base name', () {
      final options = ConvertAssetOptions.parse(<String>[
        'models/rigged/teapot.glb',
        '-f',
        'obj',
      ]);
      expect(options!.name, 'teapot');
    });

    test('--output overrides the default name', () {
      final options = ConvertAssetOptions.parse(<String>[
        'teapot.glb',
        '-f',
        'obj',
        '-o',
        'renamed',
      ]);
      expect(options!.name, 'renamed');
    });

    test('--format is accepted as a long flag too', () {
      final options = ConvertAssetOptions.parse(<String>['teapot.glb', '--format', 'stl']);
      expect(options!.format, 'stl');
    });

    test('--textures keep is accepted; anything else is refused', () {
      expect(
        ConvertAssetOptions.parse(<String>['teapot.glb', '-f', 'obj', '--textures', 'keep']),
        isNotNull,
      );
      expect(
        ConvertAssetOptions.parse(<String>['teapot.glb', '-f', 'obj', '--textures', 'external']),
        isNull,
      );
    });

    test('a second bare argument does not replace the input already found', () {
      final options = ConvertAssetOptions.parse(<String>['teapot.glb', 'stray.txt', '-f', 'obj']);
      expect(options!.input, 'teapot.glb');
    });

    test('missing -f is refused', () {
      expect(ConvertAssetOptions.parse(<String>['teapot.glb']), isNull);
    });

    test('missing an input is refused', () {
      expect(ConvertAssetOptions.parse(<String>['-f', 'obj']), isNull);
    });

    test('a flag with nothing after it is refused rather than dropped', () {
      expect(ConvertAssetOptions.parse(<String>['teapot.glb', '-f']), isNull);
    });

    test('a dotfile with no other dot keeps its own leading dot', () {
      final options = ConvertAssetOptions.parse(<String>['.gitignore', '-f', 'obj']);
      expect(options!.name, '.gitignore');
    });
  });
}
