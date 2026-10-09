/// `flutter3d convert`: every input recognised by its extension and, where
/// that is not enough, by its first bytes, handed to its reader, and the
/// outputs written together once every input has been read.
library;

import 'dart:convert';
import 'dart:io';

import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';

import '../build_exceptions.dart';
import '../chunk_generate.dart' show defaultChunkThreshold, parseChunkThreshold;
import '../cli_contract.dart' show cliJson, convertUsage;
import '../convert.dart' show TextureFamily;
import '../lod_generate.dart' show parseLodRatios;
import 'bundle.dart';
import 'context.dart';
import 'godot_input.dart';
import 'materialx_input.dart';
import 'model_input.dart';
import 'output.dart';
import 'report.dart';
import 'unity_input.dart';
import 'usd_input.dart';

/// The parsed command line.
final class ConvertCommandSettings {
  const ConvertCommandSettings({
    required this.inputs,
    this.output = '.',
    this.dryRun = false,
    this.overwrite = false,
    this.assetPrefix,
    this.materials = true,
    this.reportPath,
    this.json = false,
    this.models = const ModelSettings(),
    this.split = false,
  });

  /// A copy with the given fields replaced. A `clear…` flag resets that
  /// nullable field to null, which passing null cannot say.
  ConvertCommandSettings copyWith({
    List<String>? inputs,
    String? output,
    bool? dryRun,
    bool? overwrite,
    String? assetPrefix,
    bool? materials,
    String? reportPath,
    bool? json,
    ModelSettings? models,
    bool? split,
    bool clearAssetPrefix = false,
    bool clearReportPath = false,
  }) => ConvertCommandSettings(
    inputs: inputs ?? this.inputs,
    output: output ?? this.output,
    dryRun: dryRun ?? this.dryRun,
    overwrite: overwrite ?? this.overwrite,
    assetPrefix: clearAssetPrefix ? null : (assetPrefix ?? this.assetPrefix),
    materials: materials ?? this.materials,
    reportPath: clearReportPath ? null : (reportPath ?? this.reportPath),
    json: json ?? this.json,
    models: models ?? this.models,
    split: split ?? this.split,
  );

  final List<String> inputs;
  final String output;
  final bool dryRun;
  final bool overwrite;
  final String? assetPrefix;
  final bool materials;
  final String? reportPath;
  final bool json;
  final ModelSettings models;

  /// Whether to keep the sidecar layout (`--split`): `.fmat`, `.f3dmat`,
  /// textures and level documents beside the `.f3d`, instead of one bundle
  /// per input.
  final bool split;

  /// Null for anything [convertUsage] should answer.
  static ConvertCommandSettings? parse(List<String> arguments) {
    final inputs = <String>[];
    var output = '.';
    var dryRun = false, overwrite = false, materials = true, json = false;
    var split = false;
    String? prefix, reportPath;
    var textures = TextureFamily.auto;
    var mips = true, impostor = false;
    var lods = const <double>[];
    int? chunks;
    for (var i = 0; i < arguments.length; i++) {
      final a = arguments[i];
      String? next() => i + 1 < arguments.length ? arguments[++i] : null;
      switch (a) {
        case '-o' || '--output':
          output =
              next() ??
              (throw const ConvertUsageException('-o needs a directory'));
        case '--dry-run':
          dryRun = true;
        case '--overwrite':
          overwrite = true;
        case '--asset-prefix':
          prefix =
              next() ??
              (throw const ConvertUsageException(
                '--asset-prefix needs a path',
              ));
        case '--no-materials':
          materials = false;
        case '--report':
          reportPath =
              next() ??
              (throw const ConvertUsageException('--report needs a file'));
        case '--json':
          json = true;
        case '--split':
          split = true;
        case '--textures':
          textures = TextureFamily.parse(
            next() ??
                (throw const ConvertUsageException(
                  '--textures names a family',
                )),
          );
        case '--no-mips':
          mips = false;
        case '--impostor':
          impostor = true;
        case '--chunks':
          chunks = defaultChunkThreshold;
        case _ when a.startsWith('--chunks='):
          chunks =
              parseChunkThreshold(a.substring(9)) ??
              (throw const ConvertUsageException(
                '--chunks= takes a triangle count',
              ));
        case '--lods':
          lods = parseLodRatios(
            next() ??
                (throw const ConvertUsageException('--lods takes ratios')),
          );
        case _ when a.startsWith('--lods='):
          lods = parseLodRatios(a.substring(7));
        case '-h' || '--help':
          return null;
        case _ when a.startsWith('-'):
          throw ConvertUsageException('unknown option $a');
        default:
          inputs.add(a);
      }
    }
    if (inputs.isEmpty) return null;
    return ConvertCommandSettings(
      inputs: inputs,
      output: output,
      dryRun: dryRun,
      overwrite: overwrite,
      assetPrefix: prefix,
      materials: materials,
      reportPath: reportPath,
      json: json,
      split: split,
      models: ModelSettings(
        textures: textures,
        mips: mips,
        lods: lods,
        impostor: impostor,
        chunks: chunks,
      ),
    );
  }
}

/// The formats an input may be, with their readers.
typedef _Reader = Future<void> Function(String, ConvertContext, ConvertReport);

/// What [path] is: a format name and its reader, or null.
(String, _Reader)? detectFormat(String path) {
  final extension = extensionOf(path);
  final byName = switch (extension) {
    '.prefab' => ('unity-prefab', convertUnityInput),
    '.unity' => ('unity-scene', convertUnityInput),
    '.mat' => ('unity-material', convertUnityInput),
    '.tscn' => ('godot-scene', convertGodotInput),
    '.tres' => ('godot-resource', convertGodotInput),
    '.mtlx' => ('materialx', convertMaterialXInput),
    _ when usdExtensions.contains(extension) => ('usd', convertUsdInput),
    _ when modelExtensions.contains(extension) => (
      modelFormatName(path),
      convertModelInput,
    ),
    _ => null,
  };
  if (byName != null) return byName;
  return _sniff(path);
}

(String, _Reader)? _sniff(String path) {
  final file = File(path);
  if (!file.existsSync()) return null;
  final handle = file.openSync();
  final List<int> head;
  try {
    head = handle.readSync(512);
  } finally {
    handle.closeSync();
  }
  final text = latin1.decode(head, allowInvalid: true);
  if (text.startsWith('glTF')) return ('gltf', convertModelInput);
  if (text.startsWith('#usda') || text.startsWith('PXR-USDC')) {
    return ('usd', convertUsdInput);
  }
  if (text.contains('<materialx')) return ('materialx', convertMaterialXInput);
  if (text.startsWith('%YAML') && text.contains('!u!')) {
    return ('unity', convertUnityInput);
  }
  if (text.startsWith('[gd_scene')) return ('godot-scene', convertGodotInput);
  if (text.startsWith('[gd_resource')) {
    return ('godot-resource', convertGodotInput);
  }
  return null;
}

/// The files [inputs] name: each file as given, each directory's
/// recognised files, each glob's matches — sorted within each, so a run
/// reads them in the same order every time.
List<String> expandInputs(List<String> inputs, List<String> problems) {
  final out = <String>[];
  final seen = <String>{};
  void add(String path) {
    if (seen.add(File(path).absolute.path)) out.add(path);
  }

  for (final input in inputs) {
    final type = FileSystemEntity.typeSync(input);
    if (type == FileSystemEntityType.file) {
      add(input);
    } else if (type == FileSystemEntityType.directory) {
      final found = <String>[
        for (final entity in Directory(input).listSync(recursive: true))
          if (entity is File && _walkable(entity.path)) entity.path,
      ]..sort();
      if (found.isEmpty) {
        problems.add('$input: no file in it is one this converts');
      }
      found.forEach(add);
    } else if (input.contains(RegExp(r'[*?[{]'))) {
      final found = <String>[
        for (final entity in Glob(input).listSync())
          if (entity is File) entity.path,
      ]..sort();
      if (found.isEmpty) problems.add('$input: matches nothing');
      found.forEach(add);
    } else {
      problems.add('$input: no such file or directory');
    }
  }
  return out;
}

/// Whether a directory walk picks [path] up. A Unity material, a Godot
/// resource or a PLY only when it is what it says: a `.mat` that is YAML,
/// a `.tres` that is a material; the rest by extension.
bool _walkable(String path) {
  final extension = extensionOf(path);
  if (extension == '.meta' || extension == '.import') return false;
  if (extension == '.tres') {
    final head = File(path).openSync();
    try {
      final text = latin1.decode(head.readSync(256), allowInvalid: true);
      return text.contains('Material');
    } finally {
      head.closeSync();
    }
  }
  return detectFormat(path) != null;
}

/// The asset prefix a run uses: [given], or the output directory as typed
/// when it is relative, or nothing.
String assetPrefixFor(String output, String? given) {
  final raw = given ?? (output.startsWith('/') ? '' : output);
  var clean = raw.replaceAll(r'\', '/');
  while (clean.startsWith('./')) {
    clean = clean.substring(2);
  }
  while (clean.endsWith('/')) {
    clean = clean.substring(0, clean.length - 1);
  }
  return clean == '.' ? '' : clean;
}

/// Reads each of [inputs] into [context]'s plan, and returns a report per
/// input. An input that fails takes the files it planned with it, unless
/// an earlier input wrote them too.
Future<List<ConvertReport>> convertInputs(
  List<String> inputs,
  ConvertContext context,
) async {
  final reports = <ConvertReport>[];
  for (final input in inputs) {
    final format = detectFormat(input);
    if (format == null) {
      reports.add(
        ConvertReport(input, 'unknown')
          ..fail('not a format this converts (see flutter3d convert --help)'),
      );
      continue;
    }
    final (name, reader) = format;
    final report = ConvertReport(input, name);
    try {
      await reader(input, context, report);
    } on Object catch (error) {
      report.fail('$error');
    }
    if (report.outcome != ConvertOutcome.converted) {
      final keep = <String>{for (final r in reports) ...r.written};
      context.forget(context.plan.removeOwner(input, keep: keep));
      report.written.clear();
    }
    reports.add(report);
  }
  return reports;
}

/// Whether a directory walk would pick [path] up.
bool isConvertibleFile(String path) => _walkable(path);

/// `flutter3d convert`'s `main`. Returns the exit code.
Future<int> runConvertCommand(
  List<String> arguments, {
  IOSink? out,
  IOSink? err,
}) async {
  final stdoutSink = out ?? stdout;
  final stderrSink = err ?? stderr;
  final ConvertCommandSettings? options;
  try {
    options = ConvertCommandSettings.parse(arguments);
  } on ConvertUsageException catch (error) {
    stderrSink.writeln('${error.message}\n\n$convertUsage');
    return 2;
  }
  if (options == null) {
    (arguments.contains('-h') || arguments.contains('--help')
            ? stdoutSink
            : stderrSink)
        .writeln(convertUsage);
    return arguments.contains('-h') || arguments.contains('--help') ? 0 : 2;
  }

  final problems = <String>[];
  final inputs = expandInputs(options.inputs, problems);
  final reports = <ConvertReport>[
    for (final problem in problems)
      ConvertReport(problem.split(':').first, 'unknown')
        ..fail(problem.substring(problem.indexOf(':') + 2)),
  ];
  final plan = OutputPlan(options.output);
  final context = ConvertContext(
    plan: plan,
    assetPrefix: assetPrefixFor(options.output, options.assetPrefix),
    models: options.models,
    writeMaterials: options.materials,
  );

  reports.addAll(await convertInputs(inputs, context));
  if (!options.split) bundleOutputs(plan, reports);

  // Nothing is written when anything would be replaced without
  // --overwrite: a half-written run is worse than none.
  final collisions = options.overwrite ? const <String>[] : plan.collisions();
  if (collisions.isNotEmpty) {
    final owners = <String, String>{
      for (final write in plan.files) write.path: write.owner,
    };
    for (final report in reports) {
      final mine = collisions
          .where((String path) => owners[path] == report.input)
          .toList();
      if (mine.isEmpty) continue;
      report.fail(
        'would replace ${mine.join(', ')} under ${options.output}; pass '
        '--overwrite to replace them',
        as: ConvertOutcome.wouldOverwrite,
      );
    }
  }

  final changed = options.dryRun || collisions.isNotEmpty
      ? const <String>[]
      : plan.commit();

  if (options.json) {
    stdoutSink.writeln(
      const JsonEncoder.withIndent('  ').convert(
        cliJson('convert', <String, Object?>{
          'output': options.output,
          'dryRun': options.dryRun,
          'reports': <Object?>[for (final r in reports) r.toJson()],
        }),
      ),
    );
  } else {
    for (final report in reports) {
      stdoutSink.writeln(report.describe());
    }
    final planned = plan.files.length;
    stdoutSink.writeln(
      options.dryRun
          ? 'dry run: $planned files would be written under ${options.output}'
          : (collisions.isNotEmpty
                ? 'nothing written: ${collisions.length} files would be replaced'
                : '${changed.length} files written under ${options.output}'
                      '${planned - changed.length > 0 ? ', ${planned - changed.length} already up to date' : ''}'),
    );
  }
  if (options.reportPath case final String path) {
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(convertReportDocument(reports))}\n',
      );
  }
  return exitCodeFor(reports.map((ConvertReport r) => r.outcome));
}
