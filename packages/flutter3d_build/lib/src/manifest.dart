/// `ap-04`: the default directory convention, and the optional manifest
/// that overrides it per file.
///
/// **Without a manifest, everything under `assets_src/` maps to
/// `flutter3d_generated/` with the same relative path** (extension
/// swapped to `.f3d`) — no configuration is the whole point, and an empty
/// `assets_src/` (or none at all) plans nothing rather than erroring.
///
/// **With `flutter3d_assets.yaml`**, a list of rules, each a glob and the
/// options it overrides — texture family, mips, how an OBJ without normals
/// gets them, or a flat exclusion. The last matching rule wins, so a broad
/// rule near the top and a narrower exception below it behave the way a
/// `.gitignore` override would.
///
/// **`classes:` beside `rules:`** (`N7`) writes one `.f3d` per device class
/// instead of one per source — `chair.phone.f3d`, `chair.web.f3d`,
/// `chair.desktop.f3d` — each cut to its class's `DeviceClassBudget`. A
/// manifest without it builds what it always built.
///
/// **`"**/*.obj"` matches a root-level `a.obj` too.** That is
/// `package:glob`'s rule since 2.2.0, where `**` at the start of a pattern
/// may match no directory at all; before it, the same pattern skipped every
/// source sitting directly under `assets_src/`, and a manifest for a project
/// with no subdirectories excluded nothing. A test holds the current rule,
/// so a later `glob` that changes it again fails there first.
library;

import 'dart:io';

import 'package:flutter3d_core/formats.dart';
import 'package:glob/glob.dart';
import 'package:yaml/yaml.dart';

import 'convert.dart';
import 'device_classes.dart';

/// Thrown by [AssetManifest.parse] — always names the line the problem is
/// on, because a manifest's own author is the one who reads this, not a
/// user of the finished game.
final class ManifestFormatException implements Exception {
  const ManifestFormatException(this.message, this.line);

  final String message;

  /// 1-indexed, the way an editor's own gutter counts.
  final int line;

  @override
  String toString() => 'flutter3d_assets.yaml:$line: $message';
}

/// What one glob in the manifest overrides for the files it matches.
final class AssetRule {
  AssetRule({
    required this.glob,
    this.textures,
    this.mips,
    this.objNormals,
    this.lods,
    this.impostor = false,
    this.exclude = false,
  });

  final Glob glob;
  final TextureFamily? textures;
  final bool? mips;
  final ObjNormals? objNormals;

  /// `C5`: the triangle ratios of the levels of detail a matched model gains
  /// — `lods: [0.5, 0.25, 0.1]`, the manifest's spelling of `convert
  /// --lods`. Null leaves the model's own levels, if it has any, alone.
  final List<double>? lods;

  /// `C4`: whether a matched model's chains end in a baked impostor —
  /// `impostor: true`, the manifest's spelling of `convert --impostor`.
  final bool impostor;
  final bool exclude;
}

const Set<String> _topLevelKeys = <String>{'rules', 'classes'};
const Set<String> _classKeys = <String>{
  'lods',
  'impostor',
  'impostorCell',
  'maxTextureSide',
  'lightDifference',
};
const Set<String> _ruleKeys = <String>{
  'glob',
  'textures',
  'mips',
  'objNormals',
  'lods',
  'impostor',
  'exclude',
};

/// A parsed `flutter3d_assets.yaml`, or the empty manifest a project without
/// one gets — the same object either way, so nothing downstream branches on
/// whether a file existed.
final class AssetManifest {
  const AssetManifest([
    this.rules = const <AssetRule>[],
    this.classes = const <DeviceClassBudget>[],
  ]);

  static const AssetManifest empty = AssetManifest();

  final List<AssetRule> rules;

  /// `N7`: the device classes a model is written for, one `.f3d` each —
  /// `classes: [phone, web, desktop]` for the presets, or a mapping from a
  /// class to the numbers it changes (`phone: {maxTextureSide: 512}`).
  /// Empty, the default, writes the single `.f3d` a project always had.
  final List<DeviceClassBudget> classes;

  /// Reads a project's manifest if it has one, or [empty] if it does not —
  /// the "no configuration" half of `ap-04`'s own acceptance.
  static AssetManifest readFrom(Directory projectRoot) {
    final file = File('${projectRoot.path}/flutter3d_assets.yaml');
    if (!file.existsSync()) return empty;
    return AssetManifest.parse(file.readAsStringSync());
  }

  factory AssetManifest.parse(String yamlText) {
    final YamlNode document;
    try {
      document = loadYamlNode(yamlText);
    } on YamlException catch (error) {
      throw ManifestFormatException(
        error.message,
        (error.span?.start.line ?? 0) + 1,
      );
    }

    if (document is YamlScalar && document.value == null) return empty;
    if (document is! YamlMap) {
      throw ManifestFormatException(
        'expected a mapping at the top level',
        document.span.start.line + 1,
      );
    }

    for (final key in document.nodes.keys) {
      final name = _textOf(key as YamlNode, 'a top-level key');
      if (!_topLevelKeys.contains(name)) {
        throw ManifestFormatException(
          'unknown key "$name" — the ones this reads are '
          '${_topLevelKeys.join(', ')}',
          key.span.start.line + 1,
        );
      }
    }

    final rulesNode = document.nodes['rules'];
    if (rulesNode != null && rulesNode is! YamlList) {
      throw ManifestFormatException(
        '"rules" must be a list',
        rulesNode.span.start.line + 1,
      );
    }
    final classesNode = document.nodes['classes'];
    if (rulesNode == null && classesNode == null) return empty;

    return AssetManifest(
      <AssetRule>[
        if (rulesNode is YamlList)
          for (final ruleNode in rulesNode.nodes) _parseRule(ruleNode),
      ],
      classesNode == null
          ? const <DeviceClassBudget>[]
          : _parseClasses(classesNode),
    );
  }

  /// `classes:` as a list of class names (their presets) or a mapping from
  /// a class name to the budget numbers it changes.
  static List<DeviceClassBudget> _parseClasses(YamlNode node) {
    DeviceClass classOf(YamlNode name) {
      final text = _textOf(name, 'a device class');
      return DeviceClass.parse(text) ??
          (throw ManifestFormatException(
            'unknown device class "$text" — expected one of '
            '${DeviceClass.values.join(', ')}',
            name.span.start.line + 1,
          ));
    }

    final budgets = switch (node) {
      final YamlList list => <DeviceClassBudget>[
        for (final entry in list.nodes)
          DeviceClassBudget.presetFor(classOf(entry)),
      ],
      final YamlMap map => <DeviceClassBudget>[
        for (final entry in map.nodes.entries)
          _parseBudget(
            DeviceClassBudget.presetFor(classOf(entry.key as YamlNode)),
            entry.value,
          ),
      ],
      _ => throw ManifestFormatException(
        '"classes" must be a list of classes or a mapping of them',
        node.span.start.line + 1,
      ),
    };
    final seen = <DeviceClass>{};
    for (final budget in budgets) {
      if (!seen.add(budget.deviceClass)) {
        throw ManifestFormatException(
          'device class "${budget.deviceClass}" is named twice',
          node.span.start.line + 1,
        );
      }
    }
    return budgets;
  }

  /// [preset] with the numbers [node] names replaced; an empty or null value
  /// keeps the preset whole.
  static DeviceClassBudget _parseBudget(
    DeviceClassBudget preset,
    YamlNode node,
  ) {
    if (node is YamlScalar && node.value == null) return preset;
    if (node is! YamlMap) {
      throw ManifestFormatException(
        'a device class takes a mapping of the numbers it changes',
        node.span.start.line + 1,
      );
    }
    for (final key in node.nodes.keys) {
      final name = _textOf(key as YamlNode, 'a device class key');
      if (!_classKeys.contains(name)) {
        throw ManifestFormatException(
          'unknown key "$name" in a device class — expected one of '
          '${_classKeys.join(', ')}',
          key.span.start.line + 1,
        );
      }
    }
    int? positive(String key) => switch (node.nodes[key]) {
      null => null,
      final YamlNode value => switch (value.value) {
        final int n when n > 0 => n,
        _ => throw ManifestFormatException(
          '$key must be a whole number above zero',
          value.span.start.line + 1,
        ),
      },
    };
    final lightDifference = switch (node.nodes['lightDifference']) {
      null => null,
      final YamlNode value => switch (value.value) {
        final num n when n >= 0 && n < 1 => n.toDouble(),
        _ => throw ManifestFormatException(
          'lightDifference must be a number from 0 up to 1',
          value.span.start.line + 1,
        ),
      },
    };
    return preset.copyWith(
      lods: switch (node.nodes['lods']) {
        null => null,
        final YamlNode value => _lodsOf(value),
      },
      impostor: switch (node.nodes['impostor']) {
        null => null,
        final YamlNode value => _boolOf(value, 'impostor'),
      },
      impostorCell: positive('impostorCell'),
      maxTextureSide: positive('maxTextureSide'),
      lightDifference: lightDifference,
    );
  }

  static AssetRule _parseRule(YamlNode node) {
    if (node is! YamlMap) {
      throw ManifestFormatException(
        'each rule must be a mapping with at least "glob"',
        node.span.start.line + 1,
      );
    }

    Glob? glob;
    TextureFamily? textures;
    bool? mips;
    ObjNormals? objNormals;
    List<double>? lods;
    var impostor = false;
    var exclude = false;

    for (final entry in node.nodes.entries) {
      final keyNode = entry.key as YamlNode;
      final key = _textOf(keyNode, 'a rule key');
      final valueNode = entry.value;
      if (!_ruleKeys.contains(key)) {
        throw ManifestFormatException(
          'unknown key "$key" in a rule — expected one of '
          '${_ruleKeys.join(', ')}',
          keyNode.span.start.line + 1,
        );
      }
      switch (key) {
        case 'glob':
          final pattern = _textOf(valueNode, 'glob');
          try {
            glob = Glob(pattern);
          } on FormatException catch (error) {
            throw ManifestFormatException(
              'bad glob "$pattern": ${error.message}',
              valueNode.span.start.line + 1,
            );
          }
        case 'textures':
          final text = _textOf(valueNode, 'textures');
          final family = TextureFamily.parse(text);
          if (family == null) {
            throw ManifestFormatException(
              'unknown texture family "$text" — expected one of '
              '${TextureFamily.values.join(', ')}',
              valueNode.span.start.line + 1,
            );
          }
          textures = family;
        case 'mips':
          mips = _boolOf(valueNode, 'mips');
        case 'objNormals':
          final text = _textOf(valueNode, 'objNormals');
          objNormals = ObjNormals.values
              .where((normals) => normals.name == text)
              .firstOrNull;
          if (objNormals == null) {
            throw ManifestFormatException(
              'unknown objNormals "$text" — expected one of '
              '${ObjNormals.values.map((n) => n.name).join(', ')}',
              valueNode.span.start.line + 1,
            );
          }
        case 'lods':
          lods = _lodsOf(valueNode);
        case 'impostor':
          impostor = _boolOf(valueNode, 'impostor');
        case 'exclude':
          exclude = _boolOf(valueNode, 'exclude');
      }
    }

    if (glob == null) {
      throw ManifestFormatException(
        'a rule needs "glob"',
        node.span.start.line + 1,
      );
    }
    return AssetRule(
      glob: glob,
      textures: textures,
      mips: mips,
      objNormals: objNormals,
      lods: lods,
      impostor: impostor,
      exclude: exclude,
    );
  }

  /// A list of ratios, each strictly between zero and one — the same rule
  /// `convert --lods` holds, and refused on the line that broke it.
  static List<double> _lodsOf(YamlNode node) {
    if (node is! YamlList || node.nodes.isEmpty) {
      throw ManifestFormatException(
        'lods must be a list of ratios, e.g. [0.5, 0.25, 0.1]',
        node.span.start.line + 1,
      );
    }
    return <double>[
      for (final entry in node.nodes)
        switch (entry.value) {
          final num ratio when ratio > 0 && ratio < 1 => ratio.toDouble(),
          _ => throw ManifestFormatException(
            'a lods ratio must be a number strictly between 0 and 1',
            entry.span.start.line + 1,
          ),
        },
    ];
  }

  static String _textOf(YamlNode node, String what) {
    final value = node.value;
    if (value is String) return value;
    throw ManifestFormatException(
      '$what must be text',
      node.span.start.line + 1,
    );
  }

  static bool _boolOf(YamlNode node, String what) {
    final value = node.value;
    if (value is bool) return value;
    throw ManifestFormatException(
      '$what must be true or false',
      node.span.start.line + 1,
    );
  }

  /// The rule that applies to [relativePath], or null when nothing does.
  ///
  /// **The last matching rule wins**, not the first: a broad rule near the
  /// top of the file and a narrower exception below it read the way a
  /// person writes them — general case first, its exceptions after.
  AssetRule? ruleFor(String relativePath) {
    AssetRule? matched;
    for (final rule in rules) {
      if (rule.glob.matches(relativePath)) matched = rule;
    }
    return matched;
  }
}
