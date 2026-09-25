/// `ap-03`: `dart run flutter3d_build:convert` — the same converter
/// `packages/flutter3d/tool/convert_asset.dart` was, moved here so a build
/// hook (`ap-05`) and a project that only has the published `flutter3d`
/// package can both reach it, plus what that tool never had: a directory on
/// the input side, and the texture/mip options `ap-09`'s row promises —
/// accepted and validated now, wired to an actual encoder once `ap-07`
/// exists.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_core/geometry.dart';

import 'device_classes.dart';
import 'impostor_bake.dart';
import 'lod_generate.dart';
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

  /// One cooked texture for every device family — `gfx-83n`. Not a GPU
  /// format: a 4×4 block intermediate the load turns into BC, ASTC, ETC2 or
  /// RGBA8 against what the device reports sampling.
  static const TextureFamily universal = TextureFamily._('universal');

  static const List<TextureFamily> values = <TextureFamily>[
    auto,
    bc,
    etc2,
    universal,
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
Gaussian splat capture (.ply or .spz) becomes a .f3dsplat instead: a tree of
merged levels of detail, paged so a viewer loads only what it draws. A
directory converts every recognised file under it, recursively.

Options:
  -o, --output <path>       Where to write the result. For a single input
                             file: the output file (default: input with its
                             extension replaced by .f3d). For a directory
                             input: the output directory, mirroring the
                             input's own relative paths (default: alongside
                             each source file).
  --textures <family>       auto | bc | etc2 | universal | none (default:
                             auto). Chooses which compressed texture family a
                             converted image targets. `bc` picks BC1 for an
                             opaque image and BC3 for one with alpha; `etc2`
                             refuses (and leaves the source image as it
                             arrived) an image with alpha, since the EAC alpha
                             block is not encoded yet. `universal` writes a
                             4x4 block intermediate that is not a GPU format:
                             the load turns it into BC, ASTC, ETC2 or RGBA8
                             against what the device samples, so one cooked
                             file serves every device family at twenty bytes
                             a block. `auto` behaves like `none` here: the
                             machine converting a texture is not the one that
                             loads it, so only a build hook, which is told its
                             target, resolves it. Name a family, or
                             `universal` for a file every device can load.
  --no-mips                 Skip the mip chain and keep the base level alone.
                             Every compressed image otherwise carries one,
                             down to the last level that is whole 4x4 blocks.
  --lods <ratios>           Comma-separated triangle ratios, each strictly
                             between 0 and 1 (e.g. 0.5,0.25,0.1). Every node
                             that draws something gains one simplified level
                             per ratio, cut from its full mesh and switched
                             in by screen size. Also --lods=<ratios>.
  --impostor                Bake an octahedral impostor for every node that
                             draws something: 8x8 views of its colour and its
                             normals, drawn by the software rasteriser into
                             two atlases, as the level its chain ends in.
  --classes <names>         Comma-separated device classes: phone, web,
                             desktop. Writes one file per class beside the
                             output (model.phone.f3d, model.web.f3d, ...)
                             instead of model.f3d, each cut to its class's
                             budget: its own level-of-detail chain, impostor
                             and largest texture side. Where a class names
                             no chain (desktop), --lods and --impostor apply.
  -h, --help                Show this text.
''';

final class ConvertOptions {
  const ConvertOptions({
    required this.input,
    this.output,
    this.textures = TextureFamily.auto,
    this.mips = true,
    this.lods = const <double>[],
    this.impostor = false,
    this.classes = const <DeviceClass>[],
  });

  final String input;
  final String? output;
  final TextureFamily textures;
  final bool mips;

  /// The triangle ratios `--lods` asked for, or empty for none — see
  /// [generateLods].
  final List<double> lods;

  /// Whether `--impostor` asked for a baked card at the end of each chain —
  /// see [bakeImpostors].
  final bool impostor;

  /// The device classes `--classes` asked for (`N7`), or empty for the
  /// single file a conversion always wrote.
  final List<DeviceClass> classes;

  /// Parses [arguments], or returns null for anything [usage] should answer
  /// — an unknown flag, a missing value, more than one positional argument.
  static ConvertOptions? parse(List<String> arguments) {
    String? input;
    String? output;
    var textures = TextureFamily.auto;
    var mips = true;
    var lods = const <double>[];
    var impostor = false;
    var classes = const <DeviceClass>[];

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
        case '--impostor':
          impostor = true;
        case '--classes':
          if (i + 1 >= arguments.length) return null;
          classes = parseDeviceClasses(arguments[++i]) ?? const <DeviceClass>[];
          if (classes.isEmpty) return null;
        case '--lods':
          if (i + 1 >= arguments.length) return null;
          lods = parseLodRatios(arguments[++i]) ?? const <double>[];
          if (lods.isEmpty) return null;
        case _ when argument.startsWith('--lods='):
          lods =
              parseLodRatios(argument.substring('--lods='.length)) ??
              const <double>[];
          if (lods.isEmpty) return null;
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
      lods: lods,
      impostor: impostor,
      classes: classes,
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
      'note: --textures auto accepted, but only a build hook knows the '
      'target it converts for — textures pass through unencoded until a run '
      'names bc, etc2 or universal explicitly',
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
    if (_isSplat(source)) {
      final ok = await convertSplat(
        source,
        destination,
        stdoutSink,
        stderrSink,
      );
      if (!ok) failures++;
      continue;
    }
    // One file per device class when `--classes` names any (`N7`), each with
    // its class's budget over what the command line asked for; the single
    // file otherwise, exactly as before.
    final budgets = options.classes.isEmpty
        ? const <DeviceClassBudget?>[null]
        : <DeviceClassBudget?>[
            for (final c in options.classes) DeviceClassBudget.presetFor(c),
          ];
    for (final budget in budgets) {
      final ok = await convertOne(
        source,
        budget == null
            ? destination
            : deviceClassDestination(destination, budget.deviceClass),
        stdoutSink,
        stderrSink,
        textures: options.textures,
        mips: options.mips,
        lods: budget?.lods ?? options.lods,
        impostor: budget?.impostor ?? options.impostor,
        impostorCell: budget?.impostorCell ?? 64,
        maxTextureSide: budget?.textures.maxSide,
        decoders: decoders,
      );
      if (!ok) failures++;
    }
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
      if (entity is File &&
          (_recognised(entity.path, decoders) ||
              _looksLikeSplatCapture(entity.path)))
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
  final suffix = _outputSuffix(path);
  final dot = relative.lastIndexOf('.');
  return dot < 0 ? '$relative$suffix' : '${relative.substring(0, dot)}$suffix';
}

/// The suffixes read as a splat capture rather than a model: a binary PLY
/// of fitted Gaussians, or its compressed SPZ form.
const Set<String> splatExtensions = <String>{'.ply', '.spz'};

bool _isSplat(String path) => splatExtensions.contains(_extensionOf(path));

/// Whether a file found by a directory walk is a capture: any `.spz`, and a
/// `.ply` only when its header names the fitted colour `f_dc_0`. A mesh or
/// point cloud saved as PLY is left alone there, as it was before splats
/// were converted at all; named on its own it is still tried and refused.
bool _looksLikeSplatCapture(String path) {
  if (!_isSplat(path)) return false;
  if (_extensionOf(path) != '.ply') return true;
  final file = File(path).openSync();
  try {
    final head = latin1.decode(file.readSync(4096));
    final end = head.indexOf('end_header');
    return head.substring(0, end < 0 ? head.length : end).contains('f_dc_0');
  } finally {
    file.closeSync();
  }
}

/// `.f3dsplat` for a splat capture, `.f3d` for everything else.
String _outputSuffix(String path) =>
    _isSplat(path) ? kSplatOctreeExtension : '.f3d';

String _extensionOf(String path) {
  final dot = path.lastIndexOf('.');
  final slash = path.lastIndexOf('/');
  return dot > slash ? path.substring(dot).toLowerCase() : '';
}

String _defaultOutput(String input) {
  final dot = input.lastIndexOf('.');
  final slash = input.lastIndexOf('/');
  final suffix = _outputSuffix(input);
  if (dot > slash) return '${input.substring(0, dot)}$suffix';
  return '$input$suffix';
}

/// Converts one splat capture — a `.ply` or `.spz` — into the paged tree of
/// levels of detail `SplatLod` draws from (`.f3dsplat`), and writes what
/// happened to [out]/[err]. Returns whether it succeeded.
///
/// The cloud keeps the axes its source file stores: a PLY as written, an SPZ
/// in its right, up, back. The written tree is read back and its leaves
/// counted against the source, the same double-check [convertOne] makes: a
/// tree that silently lost a box of splats draws a hole nobody would trace
/// to the converter.
Future<bool> convertSplat(
  String inputPath,
  String outputPath,
  IOSink out,
  IOSink err, {
  int leafCapacity = 512,
  int grid = 8,
}) async {
  final input = File(inputPath);
  if (!input.existsSync()) {
    err.writeln('No such file: $inputPath');
    return false;
  }
  final bytes = input.readAsBytesSync();
  final clock = Stopwatch()..start();
  final SplatCloud cloud;
  try {
    cloud = _extensionOf(inputPath) == '.spz'
        ? parseSplatSpz(bytes, keepHigherBands: false)
        : parseSplatPly(bytes);
  } on Object catch (error) {
    err.writeln('Could not read $inputPath as a splat capture: $error');
    return false;
  }
  final tree = buildSplatOctree(cloud, leafCapacity: leafCapacity, grid: grid);
  final encoded = encodeSplatOctree(tree);
  clock.stop();

  final output = File(outputPath);
  output.parent.createSync(recursive: true);
  output.writeAsBytesSync(encoded);

  final back = parseSplatOctree(encoded);
  if (back.leafSplatCount != cloud.count) {
    err.writeln(
      'Round trip disagrees with the source ($inputPath): '
      '${cloud.count} splats in, ${back.leafSplatCount} in the tree',
    );
    return false;
  }

  out
    ..writeln('$inputPath -> $outputPath')
    ..writeln(
      '  ${cloud.count} splats, ${tree.nodes.length} nodes, root of '
      '${tree.nodes.first.splatCount}',
    )
    ..writeln(
      '  ${_bytes(bytes.length)} in, ${_bytes(encoded.length)} out, built in '
      '${clock.elapsedMilliseconds} ms',
    );
  return true;
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
  bool mips = true,
  List<double> lods = const <double>[],
  bool impostor = false,
  int impostorCell = 64,
  int? maxTextureSide,
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

  // The mesh levels first: a level is one more surface sharing its base's
  // material, so it rides on whatever the images become, and the impostor
  // below goes after the coarsest of them.
  document = generateLods(
    document,
    lods,
    report: (level) => out.writeln('  $level'),
  );

  // A device class's texture budget (`N7`): the source's images are fitted
  // before anything reads them, so the impostor is baked from what that class
  // will draw up close, and before they are compressed, so the chain is cut
  // from the smaller image. The atlases the bake adds are not fitted: their
  // size is the class's impostor cell, a budget of its own.
  if (maxTextureSide != null) {
    document = fitDocumentTextures(
      document,
      maxTextureSide,
      report: (message) => out.writeln('  texture: $message'),
    );
  }

  // Before the textures: the bake reads the source's own images, and a
  // block-compressed one is not something it can decode. The atlases it adds
  // are then compressed with the rest.
  if (impostor) {
    document = await bakeImpostors(
      document,
      cell: impostorCell,
      report: (message) => out.writeln('  impostor: $message'),
    );
  }

  document = await encodeDocumentTextures(
    document,
    textures,
    mips: mips,
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
