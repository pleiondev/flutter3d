/// A data plugin's substances: the `physicalMaterials` and `materialPairs`
/// sections, read, held to SI and the plugin's namespace, and installed into
/// the engine's `MaterialCatalog`.
///
///     dart test test/data_plugin_materials_test.dart
///
/// Each test names the mutation that would defeat it.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_matter/flutter3d_matter.dart'
    show
        MaterialCatalog,
        MaterialRegistrationException,
        Materials,
        materialPairsSection,
        physicalMaterialsRequirement,
        physicalMaterialsSection;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show DataSection, Flutter3dPlugin;
import 'package:flutter3d_plugin_runtime/flutter3d_plugin_runtime.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

/// Plum jam, as a plugin called [plugin] declares it.
Map<String, Object?> _jam({
  String id = 'orchard.plumJam',
  double density = 1300.0,
  String? source = 'Orchard lab notes, 2026',
}) => <String, Object?>{
  'id': id,
  'name': 'plum jam',
  'phase': 'liquid',
  'mechanical': <String, Object?>{'density': density, 'source': ?source},
  'fluid': <String, Object?>{'viscosity': 30.0, 'source': ?source},
};

String _document({
  String plugin = 'orchard',
  List<Object?> materials = const <Object?>[],
  List<Object?> pairs = const <Object?>[],
}) => jsonEncode(<String, Object?>{
  'format': 'f3d.plugin',
  'version': 2,
  'requires': <String>[physicalMaterialsRequirement],
  'manifest': <String, Object?>{'id': plugin, 'apiVersion': '1.0'},
  'physicalMaterials': materials,
  'materialPairs': pairs,
});

/// The sections the matter registers, which read a plugin's substances.
final DataSections _sections = DataSections(<DataSection>[
  physicalMaterialsSection,
  materialPairsSection,
]);

final MemoryPluginSource _nothing = MemoryPluginSource(
  const <String, Uint8List>{},
);

void main() {
  test(
    'its substances are in the engine while it is on, and only then',
    () async {
      // Mutation: add them to the catalogue itself rather than the plugin's
      // view of it. They install, and stay when the plugin is switched off.
      final plugin = await DataPluginLoader(sections: _sections).load(
        _document(
          materials: <Object?>[_jam()],
          pairs: <Object?>[
            <String, Object?>{
              'first': 'orchard.plumJam',
              'second': 'f3d.glass',
              'contactAngle': 0.6,
              'source': 'Orchard lab notes, 2026',
            },
          ],
        ),
        _nothing,
      );
      final loop = EngineLoop(
        input: InputState(),
        plugins: <Flutter3dPlugin>[plugin],
      );
      expect(loop.materials.require('orchard.plumJam').density, 1300.0);
      expect(
        loop.materials.pairOf('f3d.glass', 'orchard.plumJam')!.contactAngle,
        0.6,
      );
      // The engine's own are there beside it.
      expect(loop.materials.byId('f3d.water'), same(Materials.water));

      loop.plugins.disable('orchard');
      loop.runSteps(1);
      expect(loop.materials.byId('orchard.plumJam'), isNull);
      expect(loop.materials.pairOf('f3d.glass', 'orchard.plumJam'), isNull);

      loop.plugins.enable('orchard');
      loop.runSteps(1);
      expect(loop.materials.byId('orchard.plumJam'), isNotNull);
    },
  );

  test('a document with substances says so in requires, and reads back', () {
    // Mutation: write the envelope without `requires`. A build that does
    // not know the section would install the plugin without its substances.
    final document = DataPluginDocument.parse(
      _document(materials: <Object?>[_jam()]),
      sections: _sections,
    );
    final written = document.toJson();
    expect(written['requires'], <String>[physicalMaterialsRequirement]);
    final again = DataPluginDocument.fromJson(
      jsonDecode(jsonEncode(written)) as Map<String, Object?>,
      sections: _sections,
    );
    expect(
      (again.sections['physicalMaterials']!.section as List<Object?>).length,
      1,
    );
    // Without the matter's sections, the document is refused for what it
    // requires rather than read without its substances.
    expect(
      () => DataPluginDocument.fromJson(
        jsonDecode(jsonEncode(written)) as Map<String, Object?>,
      ),
      throwsA(isA<DataPluginFormatException>()),
    );
  });

  test('a density in g/cm³ is refused when the document is read', () {
    // Mutation: skip `problems()` in the matter's section. The plugin then
    // reads, and the slip is found by a level a long way later.
    expect(
      () => DataPluginDocument.parse(
        sections: _sections,
        _document(materials: <Object?>[_jam(density: 1.3e-4)]),
      ),
      throwsA(
        isA<DataPluginFormatException>().having(
          (DataPluginFormatException e) => e.message,
          'message',
          contains('not plausible'),
        ),
      ),
    );
  });

  test('a group with no source is refused', () {
    expect(
      () => DataPluginDocument.parse(
        sections: _sections,
        _document(materials: <Object?>[_jam(source: null)]),
      ),
      throwsA(
        isA<DataPluginFormatException>().having(
          (DataPluginFormatException e) => e.message,
          'message',
          contains('source'),
        ),
      ),
    );
  });

  test("an id outside the plugin's namespace is refused", () {
    // Mutation: drop the namespace check. A plugin could then shadow — or,
    // registered first, take — an id the engine or another plugin owns.
    expect(
      () => DataPluginDocument.parse(
        sections: _sections,
        _document(materials: <Object?>[_jam(id: 'f3d.plumJam')]),
      ),
      throwsA(isA<DataPluginFormatException>()),
    );
  });

  test('an id another plugin already took refuses the install', () async {
    // Mutation: let the catalogue overwrite an id. The second plugin's jam
    // would quietly replace the first's under every level that names it.
    final first = await DataPluginLoader(
      sections: _sections,
    ).load(_document(materials: <Object?>[_jam()]), _nothing);
    final catalogue = MaterialCatalog.builtIn();
    final loop = EngineLoop(
      input: InputState(),
      materials: catalogue,
      plugins: <Flutter3dPlugin>[first],
    );
    expect(loop.materials, same(catalogue));
    // The same id, added by the application: the plugin's stands, and the
    // second is refused with the plugin that holds it named.
    expect(
      () => catalogue.add(Materials.water),
      throwsA(isA<MaterialRegistrationException>()),
    );
    final again = await DataPluginLoader(
      sections: _sections,
    ).load(_document(materials: <Object?>[_jam()]), _nothing);
    expect(
      () => EngineLoop(
        input: InputState(),
        materials: catalogue,
        plugins: <Flutter3dPlugin>[again],
      ),
      throwsA(
        isA<MaterialRegistrationException>().having(
          (MaterialRegistrationException e) => e.message,
          'message',
          allOf(contains('already registered'), contains('orchard')),
        ),
      ),
    );
  });
}
