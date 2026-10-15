/// The modeller's readers read the engine's lighting models: a material set
/// to a plugin's model, one read back from a journal, and a `.fmat` linked
/// with one, each against the table it is handed.
///
///     dart test test/plugin_models_test.dart
///
/// Mutation: look the value up in `LightingModels.shipped` in `_fieldSet`,
/// and the first test refuses the plugin's model; drop `lightingModels:`
/// from `modelCommandFromJson`'s rebuilt command, and the second does.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';

const LightingModel _ink = LightingModel('Ink', 'acme_ink__Ink');

LightingModels _engine() => LightingModels()..register(_ink);

ModelHistory _painted() => ModelHistory(
  ModelProject(
    materials: <ProjectMaterial>[
      ProjectMaterial(surface: SurfaceMaterial(name: 'page')),
    ],
  ),
);

void main() {
  test(
    'a material is set to a plugin\'s model against the engine\'s table',
    () {
      final history = _painted();
      expect(
        history.run(
          SetMaterialField(
            index: 0,
            field: 'lightingModel',
            value: 'acme_ink.Ink',
            lightingModels: _engine(),
          ),
        ),
        isNull,
      );
      expect(
        history.project.materials.single.surface.lightingModel,
        same(_ink),
      );

      // Without the table, only the built-in models are names.
      expect(
        _painted().run(
          const SetMaterialField(
            index: 0,
            field: 'lightingModel',
            value: 'acme_ink.Ink',
          ),
        ),
        isNotNull,
      );
    },
  );

  test('a command read back is read against the table it is handed', () {
    final json = const SetMaterialField(
      index: 0,
      field: 'lightingModel',
      value: 'acme_ink.Ink',
    ).toJson();
    final read = modelCommandFromJson(json, lightingModels: _engine());
    final history = _painted();
    expect(history.run(read!), isNull);
    expect(history.project.materials.single.surface.lightingModel, same(_ink));
  });

  test('a .fmat linked with a plugin\'s model reads as it', () {
    final bytes = Uint8List.fromList(
      utf8.encode(
        '{"fmat": 1, "name": "page", "lightingModel": "acme_ink.Ink"}',
      ),
    );
    final history = _painted();
    expect(
      history.run(
        LinkMaterialFile(
          index: 0,
          path: 'page.fmat',
          bytes: bytes,
          lightingModels: _engine(),
        ),
      ),
      isNull,
    );
    // Without the plugin the file names, it is refused, naming it.
    expect(
      _painted().run(
        LinkMaterialFile(index: 0, path: 'page.fmat', bytes: bytes),
      ),
      contains('acme_ink'),
    );
  });
}
