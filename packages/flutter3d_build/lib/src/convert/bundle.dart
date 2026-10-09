/// One `.f3d` per input: the files a conversion planned beside each other —
/// the model, its materials, programs, textures, level documents and the
/// models a scene names — folded into the bundle sections of a single file.
///
/// **Why a bundle by default.** A converted asset used to arrive as a
/// directory of sidecars: `<name>.f3d`, `materials/*.fmat`, `*.f3dmat`,
/// `textures/*` and `<name>.level.json`, which have to be copied, versioned
/// and shipped together and break when one is left behind. `.f3d` carries all
/// of them now (see "The bundle" in `f3d_format.dart`), so one input is one
/// file. `flutter3d convert --split` and `convertFiles(bundle: false)` keep
/// the sidecar layout for a project that edits the materials as files.
///
/// **What goes where.**
///
/// * The input's own model (`<name>.f3d`) is the bundle's geometry, with its
///   lights and cameras. An input without one — a Unity or Godot scene, a
///   MaterialX library — makes a bundle with no geometry of its own.
/// * Every `.f3dmat` is a program, keyed by the material it declares.
/// * Every `<name>.level.json` is a prefab document, keyed by `<name>`.
/// * Every other file — the models a scene names, `.fmat` materials, textures
///   — is carried whole under the path it was planned at, which is the path a
///   level names after its asset prefix.
/// * For an input with its own model whose levels name no material by id,
///   the `.fmat` files and textures are left out: they repeat the model's own
///   material table and images, and the level's `materials` table that
///   pointed at them goes with them.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';

import 'output.dart';
import 'report.dart';

/// Folds every converted input's planned files in [plan] into one `.f3d`
/// each, rewriting [reports] to name the bundle.
///
/// A file two inputs planned is carried in both bundles. A file no
/// converted input wrote (a splat capture is its own format) stays as it
/// was planned.
void bundleOutputs(OutputPlan plan, List<ConvertReport> reports) {
  final planned = <String, PlannedWrite>{
    for (final write in plan.files) write.path: write,
  };
  final folded = <String>{};
  final bundles = <(String, Uint8List, ConvertReport)>[];

  for (final report in reports) {
    if (report.outcome != ConvertOutcome.converted) continue;
    final mine = <String>[
      for (final path in report.written)
        if (planned.containsKey(path) && _bundles(path)) path,
    ];
    if (mine.isEmpty) continue;

    final primary = mine
        .where((String p) => p.endsWith('.f3d') && !p.contains('/'))
        .firstOrNull;
    final levels = <String, Map<String, Object?>>{
      for (final path in mine)
        if (path.endsWith(OutputLayout.level))
          path.split('/').last.replaceFirst(OutputLayout.level, ''):
              switch (jsonDecode(utf8.decode(planned[path]!.bytes))) {
                final Map<String, Object?> document => document,
                _ => <String, Object?>{},
              },
    };
    final namesMaterials = levels.values.any(_namesMaterials);
    final dropSidecars = primary != null && !namesMaterials;

    final programs = <String, String>{
      for (final path in mine)
        if (path.endsWith('.f3dmat'))
          _programName(utf8.decode(planned[path]!.bytes), path): utf8.decode(
            planned[path]!.bytes,
          ),
    };
    final files = <String, Uint8List>{
      for (final path in mine)
        if (path != primary &&
            !path.endsWith(OutputLayout.level) &&
            !path.endsWith('.f3dmat') &&
            !(dropSidecars && _isSidecar(path)))
          path: planned[path]!.bytes,
    };
    final prefabs = <String, Map<String, Object?>>{
      for (final MapEntry(:key, :value) in levels.entries)
        key: dropSidecars
            ? (<String, Object?>{...value}..remove('materials'))
            : value,
    };

    final ModelDocument base = primary == null
        ? const PlainModelDocument()
        : F3dDocument.parse(planned[primary]!.bytes);
    final bytes = F3dWriter(
      base,
      programs: programs,
      prefabs: prefabs,
      files: files,
    ).write();
    final path = primary ?? '${safeFileName(stemOf(report.input))}.f3d';
    folded.addAll(mine);
    bundles.add((path, bytes, report));
    report.written
      ..removeWhere(mine.contains)
      ..insert(0, path);
    report.map(
      'bundle -> $path: ${primary == null ? 'no model of its own' : 'the model'}'
      '${base.lights.isEmpty ? '' : ', ${base.lights.length} lights'}'
      '${base.cameras.isEmpty ? '' : ', ${base.cameras.length} cameras'}'
      ', ${programs.length} programs, ${prefabs.length} prefabs, '
      '${files.length} files carried whole',
    );
  }

  folded.forEach(plan.remove);
  for (final (path, bytes, report) in bundles) {
    final at = plan.add(path, bytes, owner: report.input);
    if (at != path) {
      report.written[report.written.indexOf(path)] = at;
    }
  }
}

/// Whether a planned file goes into a bundle: everything a conversion
/// writes but a splat tree, which is a format of its own.
bool _bundles(String path) =>
    path.endsWith('.f3d') ||
    path.endsWith('.fmat') ||
    path.endsWith('.f3dmat') ||
    path.endsWith(OutputLayout.level) ||
    path.startsWith('${OutputLayout.textures}/');

/// A material file or a texture: what an input with its own model already
/// carries in the model's material table and images.
bool _isSidecar(String path) =>
    path.endsWith('.fmat') || path.startsWith('${OutputLayout.textures}/');

/// Whether a level names a material by id anywhere: its `materials` table
/// is then needed, and the `.fmat` files it points at with it.
bool _namesMaterials(Object? json) => switch (json) {
  final Map<String, Object?> map => map.entries.any(
    (MapEntry<String, Object?> e) =>
        (e.key == 'materials' && e.value is List) || _namesMaterials(e.value),
  ),
  final List<Object?> list => list.any(_namesMaterials),
  _ => false,
};

/// The material a `.f3dmat` declares, which is the name a material's
/// lighting model names it by; the file's stem when it declares none.
String _programName(String source, String path) =>
    RegExp(r'^\s*material\s+(\w+)', multiLine: true).firstMatch(source)?[1] ??
    stemOf(path);
