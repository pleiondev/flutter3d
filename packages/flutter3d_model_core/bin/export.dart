// ignore_for_file: avoid_print — a command-line tool whose whole output is
// stdout and stderr; a logging framework would be the wrong tool.

/// `rel-13`: a modeller document, exported from a script.
///
///     dart run flutter3d_model_core:export model.f3dproj out.glb
///     dart run flutter3d_model_core:export model.f3dproj out.obj --name crate
///
/// **The same `planExport` the editor's own export sheet calls**, which is
/// the whole point: a template model built by a build script and one exported
/// by a person pressing a button are the same bytes, because they are the
/// same function. That function used to live in `apps/flutter3d_modeler`,
/// where nothing without a Flutter toolchain could reach it — and it never
/// needed one: its imports were `dart:convert`, `dart:typed_data` and two
/// packages of this repository's own. Moving it here is what makes this file
/// possible and is most of what `rel-13` asked for.
///
/// **A refusal is an exit code and a sentence**, not a stack trace. The
/// readiness checks a person sees in the export sheet run here too, so a
/// script that exports a mesh with a hole in it is told what is wrong in the
/// same words — and `--anyway` is the same override the sheet offers, for a
/// caller who has read the warning and means it.
///
/// **Determinism is the property this exists to be checked for.** The row's
/// own acceptance is `make_templates.py && git diff --exit-code`, which only
/// says anything if exporting the same document twice produces the same
/// bytes; `export_determinism_test.dart` holds that directly.
library;

import 'dart:io';

import 'package:flutter3d_model_core/flutter3d_model_core.dart';

/// What the file's own extension says the caller wants.
///
/// A switch rather than a `--format` flag, because the destination path
/// already carries the answer and two ways of saying it is one way to
/// disagree with yourself.
ExportFormat? _formatOf(String path) {
  final String name = path.toLowerCase();
  if (name.endsWith('.glb')) return ExportFormat.glb;
  if (name.endsWith('.obj')) return ExportFormat.obj;
  if (name.endsWith('.stl')) return ExportFormat.stl;
  if (name.endsWith('.f3d')) return ExportFormat.f3d;
  return null;
}

int main(List<String> arguments) {
  final positional = arguments.where((String a) => !a.startsWith('-')).toList();
  if (positional.length != 2) {
    stderr.writeln(
      'usage: dart run flutter3d_model_core:export <in.f3dproj> <out.glb>\n'
      '       --anyway   export past a readiness warning\n'
      '       --name X   the name inside the file, when it should not be the '
      'destination\'s own',
    );
    return 2;
  }

  final File source = File(positional[0]);
  if (!source.existsSync()) {
    stderr.writeln('there is no file at ${positional[0]}');
    return 1;
  }

  final String destination = positional[1];
  final ExportFormat? format = _formatOf(destination);
  if (format == null) {
    stderr.writeln(
      '$destination names no format this knows — .glb, .obj, .stl or .f3d',
    );
    return 2;
  }

  final ProjectRead read = readProject(source.readAsBytesSync());
  if (read is! ProjectOpened) {
    stderr.writeln('${positional[0]}: ${(read as ProjectRefused).because}');
    return 1;
  }
  final ModelProject project = read.project;

  final int nameAt = arguments.indexOf('--name');
  final String name = nameAt >= 0 && nameAt + 1 < arguments.length
      ? arguments[nameAt + 1]
      : destination.split(Platform.pathSeparator).last.split('.').first;

  final ExportResult result = planExport(
    project,
    format: format,
    name: name,
    force: arguments.contains('--anyway'),
  );

  switch (result) {
    case ExportWritten(:final files):
      for (final ExportFile file in files) {
        final File target = File(
          files.length == 1 ? destination : _beside(destination, file.name),
        );
        target.parent.createSync(recursive: true);
        target.writeAsBytesSync(file.bytes, flush: true);
        print('${target.path}: ${file.bytes.length} bytes');
      }
      return 0;
    case ExportRefused(:final because):
      stderr.writeln(because);
      return 1;
    case ExportBlocked(:final issues):
      stderr.writeln(
        'this document is not ready to export:\n'
        '  ${issues.map((ExportIssue i) => i.message).join('\n  ')}\n'
        'Fix them, or pass --anyway to export regardless.',
      );
      return 1;
  }
}

/// A companion file — a `.bin`, a texture, a `CREDITS.txt` — beside the one
/// the caller named, rather than wherever it would land on its own.
String _beside(String destination, String name) {
  final int cut = destination.lastIndexOf(Platform.pathSeparator);
  return cut < 0 ? name : '${destination.substring(0, cut + 1)}$name';
}
