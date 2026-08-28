// Converts a model into the engine's `.f3d` container.
//
//   dart run tool/convert_asset.dart ../flutter3d_samples/assets/teapot.obj
//   dart run tool/convert_asset.dart ../flutter3d_samples/assets/Box.glb \
//     -o build/box.f3d
//
// A CLI in Dart, not an FFI helper. `ARCHITECTURE.md` §14 measured the decoders
// and concluded the format matters far more than the language: the same geometry
// is 360x slower to load as OBJ text than as a binary buffer, and no amount of
// native code closes that. This tool moves the parse off the device entirely,
// which is the only change of that size available.
//
// Ahead-of-time compilable, because that is how it will be used from a build
// step:
//
//   DART="$(dirname "$(command -v flutter)")/cache/dart-sdk/bin/dart"
//   $DART compile exe tool/convert_asset.dart -o build/convert_asset

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d/src/engine/assets/f3d/f3d.dart';
import 'package:flutter3d/src/engine/assets/gltf/gltf.dart';
import 'package:flutter3d/src/engine/assets/obj/obj.dart';
import 'package:flutter3d/src/engine/geometry/geometry.dart';

import 'convert_asset_options.dart';

Future<int> main(List<String> arguments) async {
  final options = ConvertAssetOptions.parse(arguments);
  if (options == null) {
    stderr.writeln(usage);
    return 2;
  }

  final input = File(options.input);
  if (!input.existsSync()) {
    stderr.writeln('No such file: ${options.input}');
    return 1;
  }

  final bytes = input.readAsBytesSync();
  final readClock = Stopwatch()..start();

  final ModelDocument document;
  try {
    document = await _decode(bytes, options.input);
  } on Object catch (error) {
    stderr.writeln('Could not decode ${options.input}: $error');
    return 1;
  }
  readClock.stop();

  final writeClock = Stopwatch()..start();
  final encoded = F3dWriter(document).write();
  writeClock.stop();

  final output = File(options.output);
  output.parent.createSync(recursive: true);
  output.writeAsBytesSync(encoded);

  // Re-read what was just written and check it against the source. A converter
  // that silently drops a surface produces a file that looks fine until someone
  // renders it, so the check belongs here rather than in a test that may not be
  // run against this particular asset.
  final roundTrip = F3dDocument.parse(encoded);
  final problems = _compare(document, roundTrip);
  if (problems.isNotEmpty) {
    stderr.writeln('Round trip disagrees with the source:');
    for (final problem in problems) {
      stderr.writeln('  $problem');
    }
    return 1;
  }

  stdout.writeln('${options.input} -> ${options.output}');
  stdout.writeln(
    '  ${document.surfaces.length} surfaces, ${document.vertexCount} vertices, '
    '${document.triangleCount} triangles, ${document.materials.length} '
    'materials, ${document.images.length} images, '
    '${document.animations.length} animations',
  );
  stdout.writeln(
    '  ${_bytes(bytes.length)} in, ${_bytes(encoded.length)} out '
    '(${(encoded.length / bytes.length).toStringAsFixed(2)}x)',
  );
  stdout.writeln(
    '  decoded in ${readClock.elapsedMicroseconds} us, '
    'encoded in ${writeClock.elapsedMicroseconds} us',
  );
  for (final warning in document.warnings) {
    stdout.writeln('  warning: $warning');
  }
  return 0;
}

Future<ModelDocument> _decode(Uint8List bytes, String path) {
  final resolve = fileUriResolverFor(path);
  final lower = path.toLowerCase();

  if (lower.endsWith('.obj')) {
    return ObjLoader(
      layout: VertexLayout.standard,
    ).load(bytes, resolveUri: resolve);
  }
  if (lower.endsWith('.gltf') || lower.endsWith('.glb')) {
    return GltfLoader(
      layout: VertexLayout.standard,
    ).load(bytes, resolveUri: resolve);
  }
  if (isF3dFile(bytes)) {
    throw const FormatException('That is already a .f3d file.');
  }
  throw FormatException('Unrecognised extension: $path');
}

/// Reads sibling files relative to the model, the way the decoders expect.
AssetUriResolver fileUriResolverFor(String modelPath) {
  final directory = File(modelPath).parent.path;
  return (uri) async {
    if (uri.startsWith('data:')) return decodeDataUri(uri);
    final file = File('$directory/${Uri.decodeComponent(uri)}');
    if (!file.existsSync()) {
      throw FileSystemException('Referenced file not found', file.path);
    }
    return file.readAsBytes();
  };
}

/// What the round trip must preserve.
///
/// Deliberately checks the vertex and index bytes rather than counts: the format
/// promises the loader hands back the *same* geometry, and a count comparison
/// would pass a file whose floats were mangled by an endianness slip.
List<String> _compare(ModelDocument source, ModelDocument reloaded) {
  final problems = <String>[];

  void check(bool condition, String message) {
    if (!condition) problems.add(message);
  }

  check(
    source.surfaces.length == reloaded.surfaces.length,
    'surfaces: ${source.surfaces.length} in, ${reloaded.surfaces.length} out',
  );
  check(
    source.materials.length == reloaded.materials.length,
    'materials: ${source.materials.length} in, ${reloaded.materials.length} out',
  );
  check(
    source.images.length == reloaded.images.length,
    'images: ${source.images.length} in, ${reloaded.images.length} out',
  );
  check(
    source.nodes.length == reloaded.nodes.length,
    'nodes: ${source.nodes.length} in, ${reloaded.nodes.length} out',
  );
  check(
    source.animations.length == reloaded.animations.length,
    'animations: ${source.animations.length} in, '
    '${reloaded.animations.length} out',
  );
  if (problems.isNotEmpty) return problems;

  for (var i = 0; i < source.surfaces.length; i++) {
    final a = source.surfaces[i].mesh;
    final b = reloaded.surfaces[i].mesh;

    if (a.layout.toString() != b.layout.toString()) {
      problems.add('surfaces[$i]: layout ${a.layout} became ${b.layout}');
      continue;
    }
    if (a.vertices.length != b.vertices.length ||
        a.indices.length != b.indices.length) {
      problems.add(
        'surfaces[$i]: ${a.vertexCount} vertices / ${a.indexCount} indices '
        'became ${b.vertexCount} / ${b.indexCount}',
      );
      continue;
    }
    for (var v = 0; v < a.vertices.length; v++) {
      if (a.vertices[v] != b.vertices[v]) {
        problems.add('surfaces[$i]: vertex float $v differs');
        break;
      }
    }
    for (var v = 0; v < a.indices.length; v++) {
      if (a.indices[v] != b.indices[v]) {
        problems.add('surfaces[$i]: index $v differs');
        break;
      }
    }
  }

  return problems;
}

String _bytes(int count) {
  if (count < 1024) return '$count B';
  if (count < 1024 * 1024) return '${(count / 1024).toStringAsFixed(1)} KB';
  return '${(count / (1024 * 1024)).toStringAsFixed(1)} MB';
}
