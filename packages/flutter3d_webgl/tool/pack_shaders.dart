/// Packs a loadable shader bundle: one file every backend reads its own
/// section of, for `GraphicsDevice.loadShaders`.
///
///     dart run tool/pack_shaders.dart \
///       --manifest <package>/shaders/effects.shaderbundle.json \
///       --impeller <package>/build/effects.shaderbundle \
///       --name effects \
///       --out <package>/assets/shaders/effects.f3dshaders
///
/// Options:
///
///   --manifest PATH   the bundle manifest impellerc reads (required). Its
///                     `file` entries resolve against the package root, which
///                     is the manifest directory's parent unless --package
///                     says otherwise — the same rule `build_shaders.sh` uses.
///   --package DIR     the package root (default: derived from --manifest).
///   --include DIR     an extra `#include <…>` root; repeatable. The package's
///                     own `shaders/` and `flutter3d_shaders`' are always
///                     searched, in that order, so an application's shader
///                     writes `#include <lib/color.glsl>` like the engine's.
///   --impeller FILE   impellerc's output for the same manifest. Optional:
///                     without it the bundle has no `impeller` section, and
///                     the Impeller backend refuses it by name.
///   --name NAME       what the bundle is called; what a refusal names
///                     (default: the manifest's stem).
///   --sdk TOKEN       the Dart SDK the impeller section was compiled with
///                     (default: this process's). Run the packer with the
///                     same SDK that ran impellerc and the default is right.
///   --out PATH        where to write the bundle (required).
///
/// Why this lives here: the WebGL section is the only one that has to be
/// *made* — the engine's GLSL translated to GLSL ES 3.00, the same
/// translation `generate_shaders.dart` does for the engine's own table — and
/// the translator is this package's. The Impeller section arrives compiled
/// and is copied in as it is; the software backend needs none.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_hardware/src/shader_bundle.dart';
import 'package:flutter3d_webgl/src/glsl_translate.dart';
import 'package:flutter3d_webgl/src/webgl_bundle_section.dart';

import 'source_package.dart';

void main(List<String> args) {
  final options = _Options.parse(args);

  final manifestFile = File(options.manifest);
  if (!manifestFile.existsSync()) _fail('no manifest at ${options.manifest}');
  final manifest =
      jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;

  // Every GLSL file under every include root, keyed the way an `#include`
  // names it. The package's own shaders first, then the engine's, then
  // whatever else was asked for: the first root to hold a path wins, which
  // is impellerc's rule as well.
  final String engine;
  try {
    engine =
        '${packageRoot('flutter3d_shaders', from: options.package)}'
        '/shaders';
  } on StateError catch (error) {
    _fail(error.message);
  }
  final roots = <String>[
    '${options.package}/shaders',
    engine,
    ...options.includes,
  ];
  final sources = <String, String>{};
  for (final root in roots) {
    final directory = Directory(root);
    if (!directory.existsSync()) _fail('include root not found: $root');
    for (final file in directory.listSync(recursive: true).whereType<File>()) {
      final path = file.path;
      if (!path.endsWith('.glsl') &&
          !path.endsWith('.frag') &&
          !path.endsWith('.vert')) {
        continue;
      }
      sources.putIfAbsent(
        path.substring(root.length + 1),
        () => file.readAsStringSync(),
      );
    }
  }

  final vertex = <String, String>{};
  final fragment = <String, String>{};
  final stages = <ShaderBundleStage>[];
  manifest.forEach((name, spec) {
    final entry = spec as Map<String, dynamic>;
    final file = entry['file'] as String;
    final source = File('${options.package}/$file');
    if (!source.existsSync()) {
      _fail('$name names $file, which is not under ${options.package}');
    }
    final isFragment = entry['type'] == 'fragment';
    // Translated from its own text, with includes resolved against the roots
    // above — `from` is only a name for the error message.
    final translated = translateGlsl(
      source.readAsStringSync(),
      sources,
      from: file,
      fragment: isFragment,
    );
    (isFragment ? fragment : vertex)[name] = translated;
    stages.add(ShaderBundleStage(name, fragment: isFragment));
  });

  final sections = <String, ByteData>{
    ShaderBundle.webglSection: encodeWebGlSection(
      vertex: vertex,
      fragment: fragment,
    ),
  };
  if (options.impeller case final String path) {
    final file = File(path);
    if (!file.existsSync()) _fail('no impellerc output at $path');
    sections[ShaderBundle.impellerSection] = file
        .readAsBytesSync()
        .buffer
        .asByteData();
  }

  final bundle = ShaderBundle(
    name: options.name,
    sdk: options.impeller == null ? '' : options.sdk,
    stages: stages,
    sections: sections,
  );
  final bytes = bundle.encode();
  final out = File(options.out)..parent.createSync(recursive: true);
  out.writeAsBytesSync(
    bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
  );
  stdout.writeln(
    'wrote ${options.out}: ${stages.length} stage'
    '${stages.length == 1 ? '' : 's'}, sections '
    '${sections.keys.join(', ')}, sdk "${bundle.sdk}", '
    '${bytes.lengthInBytes} bytes',
  );
}

final class _Options {
  const _Options({
    required this.manifest,
    required this.package,
    required this.includes,
    required this.impeller,
    required this.name,
    required this.sdk,
    required this.out,
  });

  final String manifest;
  final String package;
  final List<String> includes;
  final String? impeller;
  final String name;
  final String sdk;
  final String out;

  static _Options parse(List<String> args) {
    String? manifest;
    String? package;
    String? impeller;
    String? name;
    String? sdk;
    String? out;
    final includes = <String>[];
    for (var i = 0; i < args.length; i++) {
      String value() {
        if (i + 1 >= args.length) _fail('${args[i]} needs a value');
        return args[++i];
      }

      switch (args[i]) {
        case '--manifest':
          manifest = value();
        case '--package':
          package = value();
        case '--include':
          includes.add(value());
        case '--impeller':
          impeller = value();
        case '--name':
          name = value();
        case '--sdk':
          sdk = value();
        case '--out':
          out = value();
        case '--help' || '-h':
          stdout.writeln(_usage);
          exit(0);
        default:
          _fail('unknown argument: ${args[i]}\n\n$_usage');
      }
    }
    if (manifest == null || out == null) _fail(_usage);
    final absoluteManifest = File(manifest).absolute.path;
    final root = package ?? Directory(absoluteManifest).parent.parent.path;
    final stem = absoluteManifest
        .split('/')
        .last
        .replaceFirst(RegExp(r'\.shaderbundle\.json$'), '');
    return _Options(
      manifest: absoluteManifest,
      package: Directory(root).absolute.path.replaceAll(RegExp(r'/$'), ''),
      includes: includes,
      impeller: impeller,
      name: name ?? stem,
      sdk: sdk ?? Platform.version.split(' ').first,
      out: out,
    );
  }
}

const String _usage = '''
usage: dart run tool/pack_shaders.dart --manifest PATH --out PATH
         [--package DIR] [--include DIR]... [--impeller FILE]
         [--name NAME] [--sdk TOKEN]

Packs a loadable shader bundle for GraphicsDevice.loadShaders: the manifest's
stages translated to GLSL ES for WebGL, impellerc's output copied in for
Impeller, and a header naming the bundle and the SDK it was compiled on.
''';

Never _fail(String message) {
  stderr.writeln('pack_shaders: $message');
  exit(2);
}
