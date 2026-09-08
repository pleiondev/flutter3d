/// Writes the `webgpu` section of somebody else's shader bundle.
///
///     dart run tool/pack_wgsl_section.dart \
///       --manifest <package>/shaders/effects.shaderbundle.json \
///       --out <package>/build/effects.webgpu.json
///
/// Options:
///
///   --manifest PATH   the bundle manifest, the same one impellerc reads and
///                     the same one `flutter3d_webgl/tool/pack_shaders.dart`
///                     reads (required). Its `file` entries resolve against the
///                     package root.
///   --package DIR     the package root (default: the manifest directory's
///                     parent, which is the rule the other packer uses).
///   --include DIR     an extra `#include <…>` root; repeatable. The package's
///                     own `shaders/` and `flutter3d_shaders`' are always
///                     searched, in that order.
///   --out PATH        where to write the section (required).
///
/// ## Why this is a program of its own, in this package
///
/// A bundle is one file with a section per backend, and `pack_shaders.dart` in
/// `flutter3d_webgl` is what assembles it. It could have grown a third section
/// the way it grew the first two — except that everything the WGSL section is
/// made of lives here: the translator in `lib/src/glsl_to_wgsl.dart`, the two
/// external compilers in `lib/src/wgsl_compiler.dart`, and the shape of the
/// document in `lib/src/wgsl_section.dart`. Reaching for those from
/// the WebGL package's build script would make one backend's tooling depend on
/// another backend's library, which is the coupling four separate backends
/// exist to avoid — and `flutter3d_webgl` does not depend on this package, so
/// it would not even resolve.
///
/// So the section arrives at `pack_shaders.dart` already made, exactly the way
/// impellerc's does: it is copied in under `--webgpu FILE` and that packer
/// never learns what is in it. The one section it still *makes* is its own,
/// which is what its header already says.
///
/// `flutter3d/example/tool/build_shaders.sh` is the worked example of the three
/// steps in order, and there is nothing in it a second application would do
/// differently.
///
/// ## Varyings are numbered against the engine's manifest, not this bundle's
///
/// **A loaded stage is paired with a stage it was not compiled beside.** The
/// example's `ExampleStripes` is a fragment shader and the renderer runs it
/// against the engine's own vertex stages; WebGPU does not link, so the two
/// modules are joined by `@location` alone and a varying's number has to be the
/// number the engine already committed to `lib/engine_shaders.dart`. Numbering
/// this bundle's stages on their own would give `v_normal` whatever index its
/// own family happened to hand out, the pipeline would still build, and the
/// fragment stage would read the vertex stage's normals out of some other
/// varying's slot.
///
/// So the numbering is computed over the engine's manifest *and* this bundle's
/// stages together, and then checked: if any name the engine declares came out
/// at a different location than the engine's own manifest alone gives it, this
/// refuses to write anything. That happens when a bundle introduces a varying
/// into a family — see `assignVaryingLocations`, which numbers a family from
/// zero — and the honest answer there is that the bundle cannot be paired with
/// the engine's stages at all, rather than a section that draws wrongly.
///
/// ## When glslang and naga are not installed
///
/// This exits **3** and writes nothing, saying which program is missing. Three
/// rather than two because the caller has to tell "this machine has no shader
/// compilers" from "this shader does not compile": the first is an ordinary
/// state of a checked-out repository — the CI that is green today installs
/// neither — and a bundle that refuses to build on it would make a backend's
/// tooling a requirement for everybody else's build. The second is a mistake in
/// a shader and has to stop the build. `build_shaders.sh` maps 3 to a line on
/// stderr and a bundle with two sections instead of three.
library;

import 'dart:convert';
import 'dart:io';

// The include resolver, and only the include resolver — the reason
// `tool/generate_shaders.dart` gives, and the same dev dependency.
//
// ignore: implementation_imports
import 'package:flutter3d_webgl/src/glsl_translate.dart';
import 'package:flutter3d_webgpu/src/glsl_to_wgsl.dart';
import 'package:flutter3d_webgpu/src/source_package.dart';
import 'package:flutter3d_webgpu/src/wgsl_compiler.dart';
import 'package:flutter3d_webgpu/src/wgsl_section.dart';

void main(List<String> args) {
  final options = _Options.parse(args);

  if (_missingProgram() case final String missing) {
    stderr.writeln(
      'pack_wgsl_section: $missing is not on PATH, so this bundle gets no '
      '"webgpu" section. glslangValidator comes with the Vulkan SDK or '
      '`brew install glslang`; naga comes from `cargo install naga-cli`.',
    );
    exit(3);
  }

  final manifestFile = File(options.manifest);
  if (!manifestFile.existsSync()) _fail('no manifest at ${options.manifest}');
  final manifest =
      jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;

  // The engine's own shaders, read the way `generate_shaders.dart` reads them,
  // because the numbering below has to be the numbering that generated
  // `lib/engine_shaders.dart`.
  final ShaderSet engine;
  try {
    engine = loadShaders();
  } on StateError catch (error) {
    _fail(error.message);
  }

  // This bundle's own sources, keyed the way an `#include` names them. The
  // package's `shaders/` first, then the engine's, then whatever `--include`
  // asked for: the first root to hold a path wins, which is impellerc's rule
  // and `pack_shaders.dart`'s. Kept apart from the engine's map on purpose —
  // an application is free to have a `lib/color.glsl` of its own, and the
  // engine's stages must still be resolved against the engine's.
  final roots = <String>[
    '${options.package}/shaders',
    '${_shaderPackage(options.package)}/shaders',
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

  final entries = <String, _Entry>{};
  manifest.forEach((name, spec) {
    final entry = spec as Map<String, dynamic>;
    final file = entry['file'] as String;
    final source = File('${options.package}/$file');
    if (!source.existsSync()) {
      _fail('$name names $file, which is not under ${options.package}');
    }
    final String resolved;
    try {
      resolved = resolveIncludes(
        source.readAsStringSync(),
        sources,
        from: file,
      );
    } on GlslTranslateError catch (error) {
      _fail('$name: ${error.message}');
    }
    entries[name] = (
      file: file,
      fragment: entry['type'] == 'fragment',
      resolved: resolved,
    );
  });

  final locations = _varyingLocations(engine, entries);

  final vertex = <String, PackedStage>{};
  final fragment = <String, PackedStage>{};
  entries.forEach((name, entry) {
    final PreparedStage prepared;
    final CompiledStage compiled;
    try {
      prepared = prepareStage(
        entry.resolved,
        from: entry.file,
        fragment: entry.fragment,
        varyingLocations: locations,
      );
      compiled = compileStage(
        prepared.glsl,
        name: name,
        fragment: entry.fragment,
      );
      checkStd140Offsets(name, prepared, compiled.offsets);
    } on WgslPrepareError catch (error) {
      _fail('$name: ${error.message}');
    } on WgslCompileError catch (error) {
      _fail('$name: ${error.message}');
    } on WgslSectionError catch (error) {
      _fail(error.message);
    }
    (entry.fragment ? fragment : vertex)[name] = (
      wgsl: compiled.wgsl,
      prepared: prepared,
    );
  });

  final document = wgslSectionDocument(vertex: vertex, fragment: fragment);
  final out = File(options.out)..parent.createSync(recursive: true);
  out.writeAsStringSync(document);
  stdout.writeln(
    'wrote ${options.out}: ${vertex.length} vertex, ${fragment.length} '
    'fragment, section version $kSectionVersion, ${document.length} bytes',
  );
}

/// One manifest entry, with its `#include`s already expanded.
typedef _Entry = ({String file, bool fragment, String resolved});

/// A location per varying name, agreeing with the engine's committed table.
///
/// See the header: computed over both manifests, then held against the engine's
/// alone. The failure is a refusal to pack rather than a section that would
/// compile and read the wrong slot.
Map<String, int> _varyingLocations(ShaderSet engine, Map<String, _Entry> mine) {
  final theirs = <Set<String>>[];
  for (final entry in engine.stages.values) {
    final String resolved;
    try {
      resolved = resolveIncludes(
        engine.sources[entry.file]!,
        engine.sources,
        from: entry.file,
      );
    } on GlslTranslateError catch (error) {
      _fail('the engine\'s ${entry.file}: ${error.message}');
    }
    theirs.add(
      scanVaryings(resolved, from: entry.file, fragment: entry.fragment),
    );
  }
  final ours = <Set<String>>[
    for (final entry in mine.values)
      scanVaryings(entry.resolved, from: entry.file, fragment: entry.fragment),
  ];

  final Map<String, int> engineOnly;
  final Map<String, int> together;
  try {
    engineOnly = assignVaryingLocations(theirs);
    together = assignVaryingLocations(<Set<String>>[...theirs, ...ours]);
  } on WgslPrepareError catch (error) {
    _fail(error.message);
  }

  for (final entry in engineOnly.entries) {
    if (together[entry.key] == entry.value) continue;
    _fail(
      'this bundle moves the engine\'s varying "${entry.key}" from location '
      '${entry.value} to ${together[entry.key]}. A stage packed here is paired '
      'with a stage the engine already compiled, and WebGPU joins the two by '
      'location alone, so the numbering cannot be renegotiated by a bundle. '
      'A varying declared beside the engine\'s in one stage joins their '
      'family and renumbers it — give it a name of its own, or declare it in '
      'a stage that shares nothing with the engine\'s.',
    );
  }
  return together;
}

/// `flutter3d_shaders`' root, or a failure naming what to run.
String _shaderPackage(String from) {
  try {
    return packageRoot('flutter3d_shaders');
  } on StateError catch (error) {
    _fail('${error.message} (packing $from)');
  }
}

/// The first of the two programs that is not installed, or null.
///
/// Probed before anything is read, so the "no compilers here" exit costs a
/// process each rather than a manifest walk — and so the message names the
/// program rather than the stage that happened to be compiled first.
String? _missingProgram() {
  for (final program in <String>[kGlslang, kNaga]) {
    try {
      Process.runSync(program, <String>['--version']);
    } on ProcessException {
      return program;
    }
  }
  return null;
}

final class _Options {
  const _Options({
    required this.manifest,
    required this.package,
    required this.includes,
    required this.out,
  });

  final String manifest;
  final String package;
  final List<String> includes;
  final String out;

  static _Options parse(List<String> args) {
    String? manifest;
    String? package;
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
          // Normalised the way the package root is, for the reason
          // `pack_shaders.dart` gives: the keys an `#include` is matched by are
          // cut at the root's length, and a trailing slash would take the first
          // character of every one with it.
          includes.add(value().replaceAll(RegExp(r'/$'), ''));
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
    return _Options(
      manifest: absoluteManifest,
      package: Directory(root).absolute.path.replaceAll(RegExp(r'/$'), ''),
      includes: includes,
      out: out,
    );
  }
}

const String _usage = '''
usage: dart run tool/pack_wgsl_section.dart --manifest PATH --out PATH
         [--package DIR] [--include DIR]...

Writes the "webgpu" section of a loadable shader bundle: the manifest's stages
prepared, compiled through glslangValidator and naga, and encoded beside the
reflection a GPUShaderModule cannot be asked for. Hand the result to
flutter3d_webgl/tool/pack_shaders.dart under --webgpu.

Exits 3, having written nothing, when glslangValidator or naga is not on PATH.
''';

Never _fail(String message) {
  stderr.writeln('pack_wgsl_section: $message');
  exit(2);
}
