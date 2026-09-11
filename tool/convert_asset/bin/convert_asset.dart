/// Reads glTF, OBJ, STL or `.f3d`; writes any of the other three; prints
/// what came out — `fmt-14`'s own row.
///
///     dart run tool/convert_asset/bin/convert_asset.dart <input> -f <format>
///
/// [format] is one of `glb`, `obj`, `stl`, `f3d`. The output is written
/// beside the input, under its own base name. Every write goes through
/// `flutter3d_formats`'s own `ExportReport` — write, read back, compare —
/// and this prints what it found: a warning is the writer's own, ahead of
/// time; a difference is what the round trip actually turned up.
///
/// **`--textures external` is not built.** The row names it beside `keep`;
/// every writer here always embeds its own images (`GltfWriter`'s own doc
/// comment: "always produces one self-contained file"), and none has a
/// second mode that writes them as sibling files. `--textures keep` is
/// the only value this tool accepts — anything else is refused by name
/// rather than silently treated as the same thing.
///
/// Argument parsing (`ConvertAssetOptions`) and the report's own text
/// (`writeReport`) both live in `lib/`, testable without spawning this
/// process — see `test/options_test.dart` and `test/report_printer_test.dart`.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:convert_asset/convert_asset.dart';
import 'package:flutter3d_formats/flutter3d_formats.dart';

Future<void> main(List<String> arguments) async {
  final options = ConvertAssetOptions.parse(arguments);
  if (options == null) {
    stderr.writeln(usage);
    exitCode = 64; // EX_USAGE
    return;
  }

  final inputFile = File(options.input);
  if (!inputFile.existsSync()) {
    stderr.writeln('no such file: ${options.input}');
    exitCode = 66; // EX_NOINPUT
    return;
  }

  final ModelDocument document;
  try {
    document = await decodeModelBytes(
      ModelLoadRequest(source: _CliAssetSource(inputFile.path)),
      await inputFile.readAsBytes(),
      _CliAssetSource(inputFile.path).resolveUri,
    );
  } catch (error) {
    stderr.writeln('could not read "${options.input}": $error');
    exitCode = 65; // EX_DATAERR
    return;
  }

  final ExportReport report;
  switch (options.format) {
    case 'glb':
      report = await exportToGlb(document, name: options.name);
    case 'obj':
      report = await exportToObj(document, name: options.name);
    case 'stl':
      report = await exportToStl(document, name: options.name);
    case 'f3d':
      report = exportToF3d(document, name: options.name);
    default:
      stderr.writeln('unknown format "${options.format}"; see:\n$usage');
      exitCode = 64;
      return;
  }

  final outputDir = inputFile.parent.path;
  for (final entry in report.files.entries) {
    await File('$outputDir/${entry.key}').writeAsBytes(entry.value);
  }

  writeReport(report, stdout);

  // A difference is the one thing here that means the write is actually
  // wrong; a warning on its own is the writer working as documented.
  if (report.differences.isNotEmpty) exitCode = 1;
}

/// Reads a model and its siblings straight off disk — this tool's own
/// minimal [AssetSource]. `flutter3d_formats` ships none: it needs no
/// Flutter SDK, and `dart:io` is exactly the boundary that would cost it
/// one. The real file-backed source, `FileAssetSource`, lives in
/// `flutter3d` instead, which this tool has no reason to depend on for
/// one class.
final class _CliAssetSource extends AssetSource {
  _CliAssetSource(this.path);

  final String path;

  @override
  String get key => path;

  @override
  Future<Uint8List> read() => File(path).readAsBytes();

  @override
  AssetUriResolver get resolveUri => (AssetRequest request) async {
    final relative = safeRelativeAssetPath(request.uri);
    final dir = File(path).parent.path;
    return File('$dir/$relative').readAsBytes();
  };
}
