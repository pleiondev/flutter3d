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
/// **`"**/*.obj"` does not match a root-level `a.obj`** — `package:glob`'s
/// own rule for `**/`, proven by a test rather than assumed, because a
/// manifest for a project whose sources sit directly under `assets_src/`
/// with no subdirectory is exactly the case a "just write `**/*.ext`"
/// habit misses silently. `"**.obj"` (no slash) matches both.
library;

import 'dart:io';

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:glob/glob.dart';
import 'package:yaml/yaml.dart';

import 'convert.dart';

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
    this.exclude = false,
  });

  final Glob glob;
  final TextureFamily? textures;
  final bool? mips;
  final ObjNormals? objNormals;
  final bool exclude;
}

const Set<String> _topLevelKeys = <String>{'rules'};
const Set<String> _ruleKeys = <String>{
  'glob',
  'textures',
  'mips',
  'objNormals',
  'exclude',
};

/// A parsed `flutter3d_assets.yaml`, or the empty manifest a project without
/// one gets — the same object either way, so nothing downstream branches on
/// whether a file existed.
final class AssetManifest {
  const AssetManifest([this.rules = const <AssetRule>[]]);

  static const AssetManifest empty = AssetManifest();

  final List<AssetRule> rules;

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
          'unknown key "$name" — the only one this reads is "rules"',
          key.span.start.line + 1,
        );
      }
    }

    final rulesNode = document.nodes['rules'];
    if (rulesNode == null) return empty;
    if (rulesNode is! YamlList) {
      throw ManifestFormatException(
        '"rules" must be a list',
        rulesNode.span.start.line + 1,
      );
    }

    return AssetManifest(<AssetRule>[
      for (final ruleNode in rulesNode.nodes) _parseRule(ruleNode),
    ]);
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
      exclude: exclude,
    );
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
