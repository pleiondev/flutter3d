/// `ap-03`: `dart run flutter3d_build:convert` — the same converter
/// `packages/flutter3d/tool/convert_asset.dart` was, moved here so a build
/// hook (`ap-05`) and a project that only has the published `flutter3d`
/// package can both reach it, plus what that tool never had: a directory on
/// the input side, and the texture/mip options `ap-09`'s row promises —
/// accepted and validated now, wired to an actual encoder once `ap-07`
/// exists.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_core/geometry.dart';

import 'texture_encode.dart';

/// The compression family a texture should target — `ap-09`'s own row.
///
/// A `final class` with const instances, not an `enum`: `ap-09` already
/// names a fifth candidate (`ASTC`) the plan defers rather than rules out,
/// so this is a set a later track adds to, the same shape
/// `tool/structure.dart`'s "an enum in a published package is machinery or
/// is not an enum" rule asks for anything that is not a closed loop's own
/// step.
final class TextureFamily {
  const TextureFamily._(this.name);

  final String name;

  static const TextureFamily auto = TextureFamily._('auto');
  static const TextureFamily bc = TextureFamily._('bc');
  static const TextureFamily etc2 = TextureFamily._('etc2');
  static const TextureFamily none = TextureFamily._('none');

  static const List<TextureFamily> values = <TextureFamily>[
    auto,
    bc,
    etc2,
    none,
  ];

  static TextureFamily? parse(String text) {
    for (final family in values) {
      if (family.name == text) return family;
    }
    return null;
  }

  @override
  String toString() => name;
}

const String usage = '''
Usage: dart run flutter3d_build:convert <model-or-directory> [options]

Converts a glTF, GLB, OBJ or STL model into the engine's .f3d container. A
directory converts every recognised model file under it, recursively.

Options:
  -o, --output <path>       Where to write the result. For a single input
                             file: the output file (default: input with its
                             extension replaced by .f3d). For a directory
                             input: the output directory, mirroring the
                             input's own relative paths (default: alongside
                             each source file).
  --textures <family>       auto | bc | etc2 | none (default: auto). Chooses
                             which compressed texture family a converted
                             image targets. `bc` picks BC1 for an opaque
                             image and BC3 for one with alpha; `etc2` refuses
                             (and leaves the source image as it arrived)
                             an image with alpha, since the EAC alpha block
                             is not encoded yet. `auto` is unresolved until
                             ap-09 picks a family per target device rather
                             than per conversion — it behaves like `none`.
  --no-mips                 Skip generating a mip chain for textures.
                             Accepted, but there is no mip generator wired
                             in here yet (ap-08 exists in flutter3d_formats;
                             this converter does not call it).
  -h, --help                Show this text.
''';

final class ConvertOptions {
  const ConvertOptions({
    required this.input,
    this.output,
    this.textures = TextureFamily.auto,
    this.mips = true,
  });

  final String input;
  final String? output;
  final TextureFamily textures;
  final bool mips;

  /// Parses [arguments], or returns null for anything [usage] should answer
  /// — an unknown flag, a missing value, more than one positional argument.
  static ConvertOptions? parse(List<String> arguments) {
    String? input;
    String? output;
    var textures = TextureFamily.auto;
    var mips = true;

    for (var i = 0; i < arguments.length; i++) {
      final argument = arguments[i];
      switch (argument) {
        case '-o' || '--output':
          if (i + 1 >= arguments.length) return null;
          output = arguments[++i];
        case '--textures':
          if (i + 1 >= arguments.length) return null;
          final family = TextureFamily.parse(arguments[++i]);
          if (family == null) return null;
          textures = family;
        case '--no-mips':
          mips = false;
        case '-h' || '--help':
          return null;
        case _ when argument.startsWith('-'):
          return null;
        case _ when input == null:
          input = argument;
        default:
          return null;
      }
    }

    if (input == null) return null;
    return ConvertOptions(
      input: input,
      output: output,
      textures: textures,
      mips: mips,
    );
  }
}

/// The extensions [convertOne] reads without being handed a decoder: every
/// suffix `flutter3d_formats` has a built-in reader for, except `.f3d`, which
/// is what this writes.
///
/// **Read off [builtInModelExtensions] rather than listed here again.** It was
/// a second list once, and a format added to the decoders would have been one
/// `dart run flutter3d_build:convert` silently walked past.
final Set<String> recognisedExtensions = <String>{
  for (final String suffix in builtInModelExtensions.keys)
    if (suffix != '.f3d') suffix,
};

/// `dart run flutter3d_build:convert`'s own `main`, factored out so
/// `packages/flutter3d/bin/convert.dart` can be the thin wrapper `ap-03`
/// asks for and a test can drive this without a second process.
///
/// [decoders] are an application's own readers, asked before the built-in
/// ones exactly as `decodeModel` asks them, and a directory walk picks up any
/// file one of them claims by name.
Future<int> runConvert(
  List<String> arguments, {
  IOSink? out,
  IOSink? err,
  List<ModelDecoder> decoders = const <ModelDecoder>[],
}) async {
  final stdoutSink = out ?? stdout;
  final stderrSink = err ?? stderr;

  final options = ConvertOptions.parse(arguments);
  if (options == null) {
    stderrSink.writeln(usage);
    return 2;
  }

  if (options.textures == TextureFamily.auto) {
    stdoutSink.writeln(
      'note: --textures auto accepted, but choosing a family per target '
      'device is ap-09 — textures pass through unencoded until a run names '
      'bc or etc2 explicitly',
    );
  }
  if (!options.mips) {
    stdoutSink.writeln(
      'note: --no-mips accepted, no mip generator yet (ap-08) — nothing '
      'generates one regardless',
    );
  }

  final inputEntity = FileSystemEntity.typeSync(options.input);
  if (inputEntity == FileSystemEntityType.notFound) {
    stderrSink.writeln('No such file or directory: ${options.input}');
    return 1;
  }

  final jobs = inputEntity == FileSystemEntityType.directory
      ? _planDirectory(options.input, options.output, decoders)
      : <(String, String)>[
          (options.input, options.output ?? _defaultOutput(options.input)),
        ];

  var failures = 0;
  for (final (source, destination) in jobs) {
    final ok = await convertOne(
      source,
      destination,
      stdoutSink,
      stderrSink,
      textures: options.textures,
      decoders: decoders,
    );
    if (!ok) failures++;
  }
  return failures == 0 ? 0 : 1;
}

/// Whether [path] is a model this converter reads: a built-in suffix other
/// than `.f3d`, or a file one of [decoders] claims by name.
bool _recognised(String path, List<ModelDecoder> decoders) {
  if (recognisedExtensions.contains(_extensionOf(path))) return true;
  final name = path.substring(path.lastIndexOf('/') + 1).toLowerCase();
  final nothing = Uint8List(0);
  return decoders.any((ModelDecoder decoder) => decoder.handles(name, nothing));
}

List<(String, String)> _planDirectory(
  String directory,
  String? outputRoot,
  List<ModelDecoder> decoders,
) {
  final root = Directory(directory);
  return <(String, String)>[
    for (final entity in root.listSync(recursive: true))
      if (entity is File && _recognised(entity.path, decoders))
        (
          entity.path,
          outputRoot == null
              ? _defaultOutput(entity.path)
              : '$outputRoot/${_relativeF3d(root.path, entity.path)}',
        ),
  ];
}

String _relativeF3d(String root, String path) {
  final relative = path.startsWith('$root/')
      ? path.substring(root.length + 1)
      : path;
  final dot = relative.lastIndexOf('.');
  return dot < 0 ? '$relative.f3d' : '${relative.substring(0, dot)}.f3d';
}

String _extensionOf(String path) {
  final dot = path.lastIndexOf('.');
  final slash = path.lastIndexOf('/');
  return dot > slash ? path.substring(dot).toLowerCase() : '';
}

String _defaultOutput(String input) {
  final dot = input.lastIndexOf('.');
  final slash = input.lastIndexOf('/');
  if (dot > slash) return '${input.substring(0, dot)}.f3d';
  return '$input.f3d';
}

/// Converts one recognised model file, and writes what happened to [out]/
/// [err]. Returns whether it succeeded.
///
/// Public rather than a private helper of [runConvert]: `ap-05`'s hook
/// converts one planned file at a time too, against its own cache decision
/// rather than against every argument on a command line, and calls this
/// directly instead of going through argument parsing it has no arguments
/// for.
Future<bool> convertOne(
  String inputPath,
  String outputPath,
  IOSink out,
  IOSink err, {
  TextureFamily textures = TextureFamily.auto,
  List<ModelDecoder> decoders = const <ModelDecoder>[],
}) async {
  final input = File(inputPath);
  if (!input.existsSync()) {
    err.writeln('No such file: $inputPath');
    return false;
  }

  final bytes = input.readAsBytesSync();
  final readClock = Stopwatch()..start();

  ModelDocument document;
  try {
    document = await _decode(bytes, inputPath, decoders);
  } on Object catch (error) {
    err.writeln('Could not decode $inputPath: $error');
    return false;
  }
  readClock.stop();

  document = await encodeDocumentTextures(
    document,
    textures,
    report: (message) => out.writeln('  texture: $message'),
  );

  final writeClock = Stopwatch()..start();
  final encoded = F3dWriter(document).write();
  writeClock.stop();

  final output = File(outputPath);
  output.parent.createSync(recursive: true);
  output.writeAsBytesSync(encoded);

  // Re-read what was just written and check it against the source — the
  // same double-check `convert_asset.dart` always made, moved rather than
  // relaxed: a converter that silently drops a surface produces a file that
  // looks fine until somebody renders it.
  final roundTrip = F3dDocument.parse(encoded);
  final problems = compareModelDocuments(document, roundTrip);
  if (problems.isNotEmpty) {
    err.writeln('Round trip disagrees with the source ($inputPath):');
    for (final problem in problems) {
      err.writeln('  $problem');
    }
    return false;
  }

  out.writeln('$inputPath -> $outputPath');
  out.writeln(
    '  ${document.surfaces.length} surfaces, ${document.vertexCount} '
    'vertices, ${document.triangleCount} triangles, '
    '${document.materials.length} materials, ${document.images.length} '
    'images, ${document.animations.length} animations',
  );
  out.writeln(
    '  ${_bytes(bytes.length)} in, ${_bytes(encoded.length)} out '
    '(${(encoded.length / bytes.length).toStringAsFixed(2)}x)',
  );
  out.writeln(
    '  decoded in ${readClock.elapsedMicroseconds} us, '
    'encoded in ${writeClock.elapsedMicroseconds} us',
  );
  for (final warning in document.warnings) {
    out.writeln('  warning: $warning');
  }
  return true;
}

/// [bytes] decoded the way `decodeModel` decodes them — [decoders] first,
/// then the built-in reader for the suffix — rather than through a `switch`
/// of this file's own that an application's decoder could never reach.
Future<ModelDocument> _decode(
  Uint8List bytes,
  String path,
  List<ModelDecoder> decoders,
) {
  if (!_recognised(path, decoders)) {
    if (isF3dFile(bytes)) {
      throw const FormatException('That is already a .f3d file.');
    }
    throw FormatException('Unrecognised extension: $path');
  }
  return decodeModelBytes(
    ModelLoadRequest(
      source: _PathSource(path),
      layout: VertexLayout.standard,
      decoders: decoders,
    ),
    bytes,
    fileUriResolverFor(path),
  );
}

/// A model named by its path, for the request [_decode] builds. Nothing reads
/// through it — [convertOne] has the bytes already — but a decoder is chosen
/// by the file name a source carries.
final class _PathSource extends AssetSource {
  const _PathSource(this.path);

  final String path;

  @override
  String get key => 'file:$path';

  @override
  Future<Uint8List> read() => File(path).readAsBytes();

  @override
  AssetUriResolver get resolveUri => fileUriResolverFor(path);
}

/// Reads sibling files relative to the model, the way the decoders expect.
AssetUriResolver fileUriResolverFor(String modelPath) {
  final directory = File(modelPath).parent.path;
  return (request) async {
    final uri = request.uri;
    if (uri.startsWith('data:')) return decodeDataUri(uri);
    final file = File('$directory/${Uri.decodeComponent(uri)}');
    if (!file.existsSync()) {
      throw FileSystemException('Referenced file not found', file.path);
    }
    return file.readAsBytes();
  };
}

String _bytes(int count) {
  if (count < 1024) return '$count B';
  if (count < 1024 * 1024) return '${(count / 1024).toStringAsFixed(1)} KB';
  return '${(count / (1024 * 1024)).toStringAsFixed(1)} MB';
}
