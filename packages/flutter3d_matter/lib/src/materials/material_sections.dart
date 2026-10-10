import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show DataSection, DataSectionContext, PluginException, PluginHost;

import 'material_catalog.dart';
import 'material_json.dart';
import 'physical_material.dart';

/// What a data plugin's document names in its `requires` when it brings
/// substances: [physicalMaterialsSection] or [materialPairsSection].
///
/// **Substances are a requirement, not a version.** A build that does not
/// read these sections refuses the document, rather than installing the
/// plugin without the substances its levels name, and every other document
/// still opens there.
const String physicalMaterialsRequirement = 'f3d.physicalMaterials';

/// A data plugin's `physicalMaterials`: substances, each a
/// [PhysicalMaterial]'s fields with its id `<plugin id>.<name>`, installed
/// into the engine's [MaterialCatalog] so a level, a world's medium or a
/// collider can name them.
///
/// Registered by the application in the engine's `DataSectionRegistry`,
/// beside [materialPairsSection].
const DataSection physicalMaterialsSection = _PhysicalMaterialsSection();

/// A data plugin's `materialPairs`: how one of its substances meets another
/// material ([MaterialPair]), installed into the engine's [MaterialCatalog].
const DataSection materialPairsSection = _MaterialPairsSection();

List<Map<String, Object?>> _entries(Object? written, String name) =>
    switch (written) {
      null => const <Map<String, Object?>>[],
      final List<Object?> list when list.every((e) => e is Map) =>
        <Map<String, Object?>>[
          for (final entry in list) (entry! as Map).cast<String, Object?>(),
        ],
      _ => throw MaterialFormatException('"$name" is not a list of objects'),
    };

MaterialCatalog _catalogue(PluginHost host, DataSectionContext context) =>
    host.maybeRegistry<MaterialCatalog>() ??
    (throw PluginException(
      'plugin "${context.plugin}" brings physical materials, and this engine '
      'has no MaterialCatalog to add them to; an EngineLoop installs one '
      'unless it was handed another',
    ));

final class _PhysicalMaterialsSection extends DataSection {
  const _PhysicalMaterialsSection();

  @override
  String get name => 'physicalMaterials';

  @override
  String get requirement => physicalMaterialsRequirement;

  /// Each entry read and held to its plugin: an id in the plugin's
  /// namespace, a source for every group, and numbers in SI that
  /// [PhysicalMaterial.problems] finds plausible, so a density written in
  /// g/cm³ or a temperature in °C refuses the plugin when it is read, not a
  /// level later.
  @override
  Object read(Object? written, DataSectionContext context) {
    final plugin = context.plugin;
    return List<PhysicalMaterial>.unmodifiable(<PhysicalMaterial>[
      for (final entry in _entries(written, name))
        _checked(PhysicalMaterial.fromJson(entry), plugin),
    ]);
  }

  static PhysicalMaterial _checked(PhysicalMaterial material, String plugin) {
    if (!material.id.startsWith('$plugin.')) {
      throw MaterialFormatException(
        'physical material "${material.id}": a plugin\'s material ids start '
        'with its own id, "$plugin.<name>"',
      );
    }
    final problems = material.problems();
    if (problems.isNotEmpty) {
      throw MaterialFormatException(
        'physical material "${material.id}" is not plausible in SI units: '
        '${problems.join('; ')}',
      );
    }
    return material;
  }

  @override
  Object? write(Object section) => <Object?>[
    for (final material in section as List<PhysicalMaterial>) material.toBody(),
  ];

  /// Through the plugin's own view of the catalogue, so switching the
  /// plugin off takes them out. A substance whose id another plugin already
  /// took refuses the install with a `MaterialRegistrationException`.
  @override
  void install(PluginHost host, Object section, DataSectionContext context) {
    final materials = section as List<PhysicalMaterial>;
    if (materials.isEmpty) return;
    final catalogue = _catalogue(host, context);
    for (final material in materials) {
      catalogue.add(material);
    }
  }
}

final class _MaterialPairsSection extends DataSection {
  const _MaterialPairsSection();

  @override
  String get name => 'materialPairs';

  @override
  String get requirement => physicalMaterialsRequirement;

  /// Each entry ([MaterialPair.fromJson]): `first` and `second` by id, one
  /// of them the plugin's own, the numbers it measured and its `source`,
  /// plausible as [MaterialPair.problems] judges.
  @override
  Object read(Object? written, DataSectionContext context) {
    final plugin = context.plugin;
    return List<MaterialPair>.unmodifiable(<MaterialPair>[
      for (final entry in _entries(written, name))
        _checked(MaterialPair.fromJson(entry), plugin),
    ]);
  }

  static MaterialPair _checked(MaterialPair pair, String plugin) {
    final what = 'the material pair of "${pair.first}" and "${pair.second}"';
    if (!pair.first.startsWith('$plugin.') &&
        !pair.second.startsWith('$plugin.')) {
      throw MaterialFormatException(
        '$what: a plugin\'s pair has one of its own materials in it, '
        '"$plugin.<name>"',
      );
    }
    final problems = pair.problems();
    if (problems.isNotEmpty) {
      throw MaterialFormatException('$what: ${problems.join('; ')}');
    }
    return pair;
  }

  @override
  Object? write(Object section) => <Object?>[
    for (final pair in section as List<MaterialPair>) pair.toJson(),
  ];

  @override
  void install(PluginHost host, Object section, DataSectionContext context) {
    final pairs = section as List<MaterialPair>;
    if (pairs.isEmpty) return;
    final catalogue = _catalogue(host, context);
    for (final pair in pairs) {
      catalogue.addPair(pair);
    }
  }
}
