/// `flutter3d convert` with bytes on either side: what a service that takes
/// an upload calls. No external program runs, and nothing is written
/// where the caller can see it.
library;

import 'dart:io';
import 'dart:typed_data';

import 'bundle.dart';
import 'command.dart';
import 'context.dart';
import 'output.dart';
import 'report.dart';

/// Which outputs a conversion hands back.
///
/// A `final class` with const instances rather than an `enum`, so a later
/// release can add one.
final class ConversionTarget {
  const ConversionTarget._(this.name, this._keeps);

  final String name;
  final bool Function(String path) _keeps;

  /// Every output: models, materials and their images, level documents.
  static const ConversionTarget everything = ConversionTarget._(
    'everything',
    _all,
  );

  /// `.f3d` and `.f3dsplat` alone.
  static const ConversionTarget models = ConversionTarget._('models', _isModel);

  /// `.fmat`, `.f3dmat` and the images they name. Only the split layout
  /// (`convertFiles(bundle: false)`) has them as files of their own; a
  /// bundle carries them inside its `.f3d`.
  static const ConversionTarget materials = ConversionTarget._(
    'materials',
    _isMaterial,
  );

  /// The level documents with their prefabs, and everything they name:
  /// the same files as [everything].
  static const ConversionTarget scenes = ConversionTarget._('scenes', _all);

  static const List<ConversionTarget> values = <ConversionTarget>[
    everything,
    models,
    materials,
    scenes,
  ];

  /// Whether an output at [path] is handed back.
  bool keeps(String path) => _keeps(path);

  static bool _all(String _) => true;

  static bool _isModel(String path) =>
      path.endsWith('.f3d') || path.endsWith('.f3dsplat');

  static bool _isMaterial(String path) =>
      path.endsWith('.fmat') ||
      path.endsWith('.f3dmat') ||
      path.startsWith('${OutputLayout.textures}/');

  @override
  String toString() => name;
}

/// What [convertFiles] made.
final class ConversionResult {
  const ConversionResult(this.files, this.reports);

  /// The outputs, by path relative to the output root (`chair.f3d`,
  /// `materials/wood.fmat`, `room.level.json`), in path order.
  final Map<String, Uint8List> files;

  /// One per input converted, as `flutter3d convert --json` prints them.
  final List<ConvertReport> reports;

  /// The exit code `flutter3d convert` would have given.
  int get exitCode => exitCodeFor(reports.map((ConvertReport r) => r.outcome));

  bool get isOk => exitCode == 0;
}

/// Converts [files] — one upload, or every file of an unpacked Unity, Godot
/// or USD bundle, by its path inside the bundle — and returns the outputs
/// [to] asks for, with the reports.
///
/// [entry] names the file to convert, by its key in [files]; null converts
/// every file a directory walk of `flutter3d convert` would. Every other
/// file is there to be found: the `.meta` files and models a Unity prefab
/// names, a Godot scene's `res://` paths (the bundle's root holds
/// `project.godot`, or is taken as `res://`), a USD layer's references and
/// textures.
///
/// **No external program runs.** FBX, `.blend` and a binary USD layer are
/// reported with [ConvertOutcome.missingTool] and the reason. Paths in
/// level documents start with [assetPrefix].
///
/// **One `.f3d` per input by default** ([bundle]): the model with its
/// lights and cameras, its materials, the `.f3dmat` programs, the level
/// documents as prefabs, and every other file a scene names carried whole
/// (see `F3dDocument.programs`, `prefabs` and `files`). [ConversionTarget]
/// then picks among bundles, `.f3dsplat` trees and nothing else. With
/// `bundle: false` the outputs are the sidecar layout of
/// `flutter3d convert --split`: `<name>.f3d`, `materials/*.fmat`,
/// `*.f3dmat`, `textures/*`, `models/*.f3d` and `<name>.level.json`.
///
/// **A document reads only the files that came with it.** A glTF buffer, an
/// OBJ material library, a USD reference or texture that climbs out of the
/// upload with `..` or names an absolute path is refused and reported, never
/// read.
///
/// Throws [ArgumentError] for a key that is absolute or climbs out with
/// `..`, and for an [entry] that is not a key.
Future<ConversionResult> convertFiles(
  Map<String, Uint8List> files, {
  required ConversionTarget to,
  String? entry,
  String assetPrefix = '',
  ModelSettings models = const ModelSettings(),
  bool materials = true,
  bool bundle = true,
}) async {
  for (final key in files.keys) {
    final parts = key.replaceAll(r'\', '/').split('/');
    if (key.startsWith('/') || key.contains(':') || parts.contains('..')) {
      throw ArgumentError.value(key, 'files', 'a path inside the bundle');
    }
  }
  if (entry != null && !files.containsKey(entry)) {
    throw ArgumentError.value(entry, 'entry', 'not one of the files');
  }
  // The readers resolve a prefab's model through `.meta` files and a
  // scene's `res://` paths on a directory tree, so the bundle is laid out
  // as one, privately, for the length of the call.
  final work = Directory.systemTemp.createTempSync('flutter3d_convert_');
  try {
    final input = Directory('${work.path}/in')..createSync();
    for (final MapEntry(:key, :value) in files.entries) {
      File('${input.path}/${key.replaceAll(r'\', '/')}')
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(value);
    }
    final inputs = entry != null
        ? <String>['${input.path}/$entry']
        : <String>[
            for (final key in (files.keys.toList()..sort()))
              if (isConvertibleFile('${input.path}/$key')) '${input.path}/$key',
          ];
    final plan = OutputPlan('${work.path}/out');
    final context = ConvertContext(
      plan: plan,
      assetPrefix: assetPrefix,
      models: models,
      writeMaterials: materials,
      externalTools: false,
      // The keys are checked above; this holds the references inside the
      // documents to the upload too.
      root: input.path,
    );
    final reports = await convertInputs(inputs, context);
    if (bundle) bundleOutputs(plan, reports);
    final prefix = '${input.path}/';
    return ConversionResult(
      <String, Uint8List>{
        for (final write in plan.files)
          if (to.keeps(write.path)) write.path: write.bytes,
      },
      <ConvertReport>[for (final report in reports) _rebased(report, prefix)],
    );
  } finally {
    work.deleteSync(recursive: true);
  }
}

/// [report] with the private directory [prefix] taken out of its input
/// and its lines, so they name files as the caller named them.
ConvertReport _rebased(ConvertReport report, String prefix) {
  String clean(String line) => line
      .replaceAll(prefix, '')
      .replaceAll(prefix.substring(0, prefix.length - 1), '.');
  final out = ConvertReport(clean(report.input), report.format)
    ..outcome = report.outcome
    ..error = report.error == null ? null : clean(report.error!);
  out.written.addAll(report.written);
  out.mapped.addAll(report.mapped.map(clean));
  out.dropped.addAll(report.dropped.map(clean));
  out.warnings.addAll(report.warnings.map(clean));
  return out;
}
