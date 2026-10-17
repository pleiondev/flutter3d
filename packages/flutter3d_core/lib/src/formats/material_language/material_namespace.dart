/// A plugin's material in its plugin's namespace: the stage a `.f3dmat` it
/// ships compiles to, and the source renamed to it.
library;

import 'material_parser.dart';

/// The stage a material called [material] compiles to when a plugin of
/// [namespace] ships it: `<namespace>__<material>` for the bare name a
/// `.f3dmat` writes (`material Hair` in `acme_hair` is `acme_hair__Hair`),
/// and [material] as it is when it already names that namespace. Null for a
/// name in another namespace (`other__Ink`), which no plugin compiles.
///
/// **The namespace is the plugin's, never the source's to choose**, as every
/// other name a plugin registers is (`PluginManifest.nameProblem`). So a
/// plugin's `.f3dmat` writes `material Hair`, and the stage the build and
/// the run time compile, the lighting model names and a document stores
/// (`LightingModel.name`, `acme_hair.Hair`) all carry `acme_hair`. The `__`
/// is how a shader spells the dot (`LightingModel.shaderNameOf`).
String? materialStageIn(String namespace, String material) {
  final own = '${namespace}__';
  if (material.startsWith(own) && material.length > own.length) {
    return material;
  }
  if (material.contains('__')) return null;
  return '$own$material';
}

/// [source], a `.f3dmat`, with its first block — the material, the
/// full-screen stage or the compute kernel the file is — named [name], and
/// every other byte as it was written: what a build or a run time compiles,
/// and carries in the bundle's material section, once the stage is in its
/// plugin's namespace ([materialStageIn]), so whatever reads the source
/// back reads the stage's own name.
///
/// Throws a [MaterialSyntaxException] for a source with no first block to
/// rename, which [parseMaterial] refuses too.
String renameMaterialSource(String source, String name) {
  // Comments blanked to the same length, so an offset in them is one in
  // the source, and a `material` in a comment is not the block.
  final code = source
      .split('\n')
      .map((String line) {
        final comment = line.indexOf('//');
        return comment < 0
            ? line
            : line.substring(0, comment) + ' ' * (line.length - comment);
      })
      .join('\n');
  final header = RegExp(
    r'\b(?:material|fullscreen|compute)\s+([A-Za-z_][A-Za-z0-9_]*)',
  ).firstMatch(code);
  if (header == null) {
    throw const MaterialSyntaxException(
      'a .f3dmat starts with a "material", "fullscreen" or "compute" block, '
      'and this one has none',
      1,
      1,
    );
  }
  final at = header.start + header.group(0)!.lastIndexOf(header.group(1)!);
  return source.replaceRange(at, at + header.group(1)!.length, name);
}
