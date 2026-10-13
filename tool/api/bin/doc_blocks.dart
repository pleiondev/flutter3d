/// Analyzes every Dart block of the documentation against today's API.
///
/// ```
/// cd tool/api
/// dart run api_snapshot:doc_blocks [--only <path text>] [--keep]
/// ```
///
/// The pages are `site/content/**`, the root README and each package's
/// README and API.md. Each block is read with the imports it shows, the
/// ones an earlier block of its page showed, and the main libraries of the
/// packages its page lists under `dependencies:` (on a page that lists
/// none, of the packages that page is about). A block that is not meant to
/// compile opens with ` ```dart fragment `.
///
/// Exits 1 naming each page and line where a name resolves wrong, so a
/// rename that left its old spelling on the site fails CI. Run by
/// `tool/ci.sh` after `pub get`, beside the API snapshots: it needs the
/// workspace resolved, and analyzing four hundred blocks takes about a
/// minute, which is too long for `tool/structure.dart`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:api_snapshot/api_snapshot.dart';
import 'package:api_snapshot/doc_blocks.dart';

/// The genre a site section is about, whose kit its pages are read with.
const Map<String, List<String>> _sectionKits = <String, List<String>>{
  'education': <String>['flutter3d_education'],
  'platformer': <String>['flutter3d_game_platformer'],
  'racing': <String>['flutter3d_game_racing'],
  'shooter': <String>['flutter3d_game_shooter'],
  'strategy': <String>['flutter3d_game_strategy'],
};

/// What a page that names no dependencies is read with.
const List<String> _siteDefault = <String>[
  'flutter3d',
  'flutter3d_app',
  'flutter3d_game',
  'flutter3d_audio',
  'flutter3d_particles',
];

/// What every block may use without showing it: the core libraries and
/// Flutter's widgets, which a snippet takes for granted.
const List<String> _always = <String>[
  "import 'dart:async';",
  "import 'dart:io';",
  "import 'dart:math';",
  "import 'dart:typed_data';",
  // vector_math's `Matrix4` is the engine's; Flutter's is vector_math_64's.
  "import 'package:flutter/widgets.dart' hide Matrix4;",
  "import 'package:vector_math/vector_math.dart';",
];

Future<void> main(List<String> args) async {
  final root = repositoryRootFrom(Directory.current);
  final packages = repositoryPackages(root);
  bool hasMain(String p) =>
      packages[p] != null &&
      File('${packages[p]!.path}/lib/$p.dart').existsSync();
  List<String> importsOf(Iterable<String> names) => <String>[
    for (final p in names)
      if (hasMain(p)) "import 'package:$p/$p.dart';",
  ];

  // `--only <text>`: the pages whose path contains it, to check a few
  // pages while correcting them.
  final wanted = <String>[
    for (var i = 0; i + 1 < args.length; i++)
      if (args[i] == '--only') args[i + 1],
  ];
  bool only(File f) => wanted.isEmpty || wanted.any(f.path.contains);
  final pages =
      <File>[
          ...Directory('${root.path}/site/content')
              .listSync(recursive: true)
              .whereType<File>()
              .where((File f) => f.path.endsWith('.md')),
          File('${root.path}/README.md'),
          for (final dir in packages.values) ...<File>[
            File('${dir.path}/README.md'),
            File('${dir.path}/API.md'),
          ],
        ].where((File f) => f.existsSync() && only(f)).toList()
        ..sort((File a, File b) => a.path.compareTo(b.path));

  final scratch = Directory.systemTemp.createTempSync('doc_blocks_');
  final files = <String, DocSnippet>{};
  final pageTypes = <String, Set<String>>{};
  var fragments = 0;
  for (final page in pages) {
    final doc = page.path.substring(root.path.length + 1);
    final text = page.readAsStringSync();
    final listed = declaredDependencies(text);
    final package = RegExp(r'^packages/(\w+)/').firstMatch(doc)?.group(1);
    final section = RegExp(r'^site/content/(\w+)/').firstMatch(doc)?.group(1);
    final fallback = importsOf(
      listed.any(hasMain)
          ? listed
          : package != null
          ? <String>[
              package,
              // The packages its own pubspec depends on: what its API is
              // written over, and what its README's reader has with it.
              ...declaredDependencies(
                '```yaml\n${File('${packages[package]!.path}/pubspec.yaml').readAsStringSync()}```\n',
              ),
              'flutter3d',
              'flutter3d_app',
              'flutter3d_game',
            ]
          : <String>[..._siteDefault, ...?_sectionKits[section]],
    );
    final blocks = docBlocksOf(text, fallback: fallback);
    pageTypes[doc] = typesDeclaredIn(blocks);
    for (final block in blocks) {
      if (block.fragment) {
        fragments++;
        continue;
      }
      final withAlways = DocBlock(
        line: block.line,
        source: block.source,
        imports: <String>[
          ...block.imports,
          for (final a in _always)
            if (!block.imports.contains(a)) a,
        ],
        fragment: false,
      );
      final snippet = snippetFor(withAlways);
      final path =
          '${scratch.path}/lib/b${files.length.toString().padLeft(4, '0')}.dart';
      File(path)
        ..createSync(recursive: true)
        ..writeAsStringSync(snippet.source);
      files[path] = (block: withAlways, doc: doc, offset: snippet.offset);
    }
  }

  _writePackageConfig(root, scratch);
  File(
    '${scratch.path}/analysis_options.yaml',
  ).writeAsStringSync('analyzer:\n  errors:\n    todo: ignore\n');
  final analyzed = await Process.run(Platform.resolvedExecutable, <String>[
    'analyze',
    '--format=machine',
    scratch.path,
  ]);
  final machine = '${analyzed.stdout}\n${analyzed.stderr}';
  // A path the analyzer printed resolved through a symbolic link (macOS's
  // /var is /private/var) is the same file.
  final byReal = <String, DocSnippet>{
    for (final MapEntry(key: path, value: snippet) in files.entries) ...{
      path: snippet,
      File(path).resolveSymbolicLinksSync(): snippet,
    },
  };
  final found =
      findingsIn(
        machine,
        byReal,
        apiFunctions: _apiFunctions(root, packages),
        pageTypes: pageTypes,
      )..sort(
        (DocFinding a, DocFinding b) =>
            '${a.doc}:${a.line.toString().padLeft(5)}'.compareTo(
              '${b.doc}:${b.line.toString().padLeft(5)}',
            ),
      );
  if (!args.contains('--keep')) scratch.deleteSync(recursive: true);

  for (final finding in found) {
    stdout.writeln(finding);
  }
  stdout.writeln(
    '${files.length} blocks analyzed in ${pages.length} pages, '
    '$fragments marked as fragments, ${found.length} '
    '${found.length == 1 ? 'name resolves' : 'names resolve'} wrong',
  );
  if (found.isNotEmpty) exitCode = 1;
}

/// The workspace's package config, its relative roots made absolute, so the
/// scratch directory resolves every package the repository resolves.
void _writePackageConfig(Directory root, Directory scratch) {
  final source = File('${root.path}/.dart_tool/package_config.json');
  final config = jsonDecode(source.readAsStringSync()) as Map<String, Object?>;
  final base = Uri.directory('${root.path}/.dart_tool/');
  for (final entry
      in (config['packages']! as List<Object?>).cast<Map<String, Object?>>()) {
    entry['rootUri'] = base.resolve(entry['rootUri']! as String).toString();
  }
  File('${scratch.path}/.dart_tool/package_config.json')
    ..createSync(recursive: true)
    ..writeAsStringSync(jsonEncode(config));
}

/// Every lowercase top-level name a published snapshot declares: a
/// function, a getter or a constant of the API.
Set<String> _apiFunctions(Directory root, Map<String, Directory> packages) {
  final out = <String>{};
  for (final MapEntry(key: name, value: dir) in packages.entries) {
    final api = File('${dir.path}/${snapshotPathOf(name)}');
    if (!api.existsSync()) continue;
    for (final line in api.readAsLinesSync()) {
      if (line.isEmpty || line.startsWith(' ') || line.startsWith('#')) {
        continue;
      }
      if (RegExp(r'^(library|export) ').hasMatch(line)) continue;
      // A type's header names no function.
      if (RegExp(
        r'^(?:@\S+\s+)*(?:[a-z]+\s+)*(?:class|enum|mixin|typedef|extension)\s',
      ).hasMatch(line)) {
        continue;
      }
      var bare = line;
      while (bare.contains('<')) {
        final next = bare.replaceAll(RegExp(r'<[^<>]*>'), '');
        if (next == bare) break;
        bare = next;
      }
      final m = RegExp(
        r'(?<![\w$])([a-z_$][\w$]*)\s*(?:\(| =|$)',
      ).firstMatch(bare);
      if (m != null) out.add(m.group(1)!);
    }
  }
  return out;
}
