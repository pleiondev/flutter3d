/// A material naming a plugin's lighting model requires that plugin.
///
///     dart test test/formats/lighting_plugin_requires_test.dart
///
/// A `.fmat` lists the plugin in `requires`, a `.f3d` names the model in
/// the plugin's namespace in its `materialLighting` record, and a reader
/// without the plugin refuses either by the plugin's name. Drawn with the
/// scene's model instead, the material would be a different asset rather
/// than a poorer one.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:test/test.dart';

const LightingModel _ink = LightingModel('Ink', 'acme_ink__Ink');

LightingModels _withInk() => LightingModels()..register(_ink);

MaterialDocument _inked() => MaterialDocument(
  surface: SurfaceMaterial(name: 'ink'),
  lighting: _ink,
);

void main() {
  group('.fmat', () {
    test('lists the plugin of the model it names in requires', () {
      final written =
          jsonDecode(writeFmat(_inked(), lightingModels: _withInk()))
              as Map<String, Object?>;
      // Mutation: write the envelope with no requires, and a reader without
      // the plugin opens the material drawn with the scene's model.
      expect(written['requires'], <String>['acme_ink']);
      expect(written['lighting'], 'acme_ink.Ink');
    });

    test('a built-in model requires nothing', () {
      final written =
          jsonDecode(
                writeFmat(
                  MaterialDocument(
                    surface: SurfaceMaterial(name: 'plain'),
                    lighting: LightingModel.pbr,
                  ),
                ),
              )
              as Map<String, Object?>;
      expect(written['requires'], isEmpty);
    });

    test('reads as itself where the plugin is installed', () {
      final bytes = utf8.encode(
        writeFmat(_inked(), lightingModels: _withInk()),
      );
      expect(readFmat(bytes, lightingModels: _withInk()).lighting, same(_ink));
    });

    test('is refused by the plugin\'s name where it is not', () {
      final bytes = utf8.encode(
        writeFmat(_inked(), lightingModels: _withInk()),
      );
      expect(
        () => readFmat(bytes, name: 'ink.fmat'),
        throwsA(
          isA<FmatFormatException>().having(
            (FmatFormatException e) => e.message,
            'message',
            contains('acme_ink'),
          ),
        ),
      );
    });

    test('a file without requires that names the model is refused too', () {
      // Written before the writer listed the plugin: the word itself says
      // which plugin it needs.
      final bytes = utf8.encode(
        jsonEncode(<String, Object?>{'fmat': 1, 'lighting': 'acme_ink.Ink'}),
      );
      expect(() => readFmat(bytes), throwsA(isA<FmatFormatException>()));
    });
  });

  group('.f3d', () {
    Uint8List inkedBox() {
      final box = F3dDocument.parse(
        File('test/fixtures/v1/box.f3d').readAsBytesSync(),
      );
      return F3dWriter(
        PlainModelDocument(
          surfaces: box.surfaces,
          materials: <SurfaceMaterial>[
            SurfaceMaterial(name: 'ink', lightingModel: _ink),
          ],
          images: box.images,
          nodes: box.nodes,
        ),
      ).write();
    }

    test('names the plugin\'s model in its namespace', () {
      final document = F3dDocument.parse(
        inkedBox(),
        lightingModels: _withInk(),
      );
      expect(document.requires, <String>{'acme_ink'});
      expect(document.materials.single.lightingModel, same(_ink));
    });

    test('is refused by the plugin\'s name without it', () {
      // Mutation: drop the check in `F3dDocument.parse`, and the box opens
      // with the scene's model, nothing saying why it looks different.
      expect(
        () => F3dDocument.parse(inkedBox()),
        throwsA(
          isA<F3dFormatException>().having(
            (F3dFormatException e) => e.message,
            'message',
            contains('acme_ink'),
          ),
        ),
      );
    });

    test('the bundle fixture requires nothing', () {
      expect(
        F3dDocument.parse(
          File('test/fixtures/v2/bundle.f3d').readAsBytesSync(),
        ).requires,
        isEmpty,
      );
    });
  });
}
