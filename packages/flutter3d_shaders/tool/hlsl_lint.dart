/// Every engine stage through the road a Direct3D 12 backend would take:
/// GLSL, glslang to SPIR-V, naga to HLSL, and DXC where it is installed.
///
///     dart run tool/hlsl_lint.dart                 # naga's half, DXC if found
///     dart run tool/hlsl_lint.dart --require-dxc   # CI: no DXC is a failure
///     dart run tool/hlsl_lint.dart --out build/hlsl --dxc /path/to/dxc
///
/// **A lint, not a backend.** Nothing in the engine reads HLSL yet, and no
/// bundle carries a `d3d12` section. What this holds is that the day one
/// does, the engine's own stages are already text the strictest HLSL
/// compiler accepts: a construct naga cannot write as HLSL, or one DXC
/// refuses (a register class past its limit, an implicit conversion, a
/// sampler state used as a value), fails here by stage name rather than on
/// a Windows machine at first draw.
///
/// The render stages go through the same preparation and the same
/// glslang flags the WebGPU table is generated with (`prepareStage`,
/// `compileStage`), so what is linted is what ships; the compute stages are
/// read from `flutter3d.compute.json` and compiled as
/// `generate_compute_shaders.dart` compiles them.
///
/// **DXC is optional on a developer's machine.** Without it the naga half
/// still runs, which is the half that has caught every translation problem
/// so far, and the summary says DXC was skipped. CI installs DXC and passes
/// `--require-dxc`, so a skip there is a failure.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_hardware/flutter3d_hardware.dart'
    show ShaderStageKind;
import 'package:flutter3d_shaders/compile.dart';

/// One stage on its way through the lint.
final class _Stage {
  _Stage(this.name, this.kind, this.glsl);

  final String name;
  final ShaderStageKind kind;
  final String glsl;
}

/// DXC's profile for [kind], at shader model 6.0, the oldest DXC writes
/// and the floor every Direct3D 12 driver with DXIL accepts.
String _profile(ShaderStageKind kind) => switch (kind) {
  ShaderStageKind.vertex => 'vs_6_0',
  ShaderStageKind.fragment => 'ps_6_0',
  ShaderStageKind.compute => 'cs_6_0',
  _ => throw UnsupportedError('no DXC profile for a ${kind.name} stage'),
};

/// Whether [hlsl] has the entry point DXC is told to compile. naga keeps
/// SPIR-V's `main` for a stage compiled from GLSL and moves the body to
/// `main_1`; checked rather than assumed, so a naga that renames it fails
/// here by stage rather than as DXC's "missing entry point".
final RegExp _main = RegExp(r'^\w+ main\(', multiLine: true);

/// [executable] when it runs, or null.
String? _found(String executable) {
  try {
    final probe = Process.runSync(executable, <String>['--version']);
    return probe.exitCode == 0 || '${probe.stdout}${probe.stderr}'.isNotEmpty
        ? executable
        : null;
  } on ProcessException {
    return null;
  }
}

Never _fail(String message) {
  stderr.writeln(message);
  exit(1);
}

void main(List<String> args) {
  var requireDxc = false;
  String? out;
  String? dxcPath;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--require-dxc':
        requireDxc = true;
      case '--out':
        out = args[++i];
      case '--dxc':
        dxcPath = args[++i];
      default:
        _fail('unknown argument ${args[i]}; see the header of this file');
    }
  }

  final ShaderSet shaders;
  try {
    shaders = loadShaders();
  } on StateError catch (error) {
    _fail(error.message);
  }

  final stages = <_Stage>[..._renderStages(shaders), ..._computeStages()];
  final directory = out == null
      ? Directory.systemTemp.createTempSync('flutter3d_hlsl_')
      : (Directory(out)..createSync(recursive: true));
  final dxc = dxcPath ?? _found('dxc');
  if (dxc == null && requireDxc) {
    _fail('--require-dxc, and no dxc on PATH: install DXC or pass --dxc');
  }

  final failures = <String>[];
  var compiled = 0;
  for (final stage in stages) {
    final String hlsl;
    try {
      hlsl = compileStage(
        stage.glsl,
        name: stage.name,
        kind: stage.kind,
        target: ShaderTarget.hlsl,
      ).text!;
    } on WgslCompileException catch (error) {
      failures.add('${stage.name}: ${error.message}');
      continue;
    }
    final file = File('${directory.path}/${stage.name}.hlsl')
      ..writeAsStringSync(hlsl);
    if (!_main.hasMatch(hlsl)) {
      failures.add('${stage.name}: naga wrote no `main` into ${file.path}');
      continue;
    }
    if (dxc == null) continue;
    final result = Process.runSync(dxc, <String>[
      '-nologo',
      '-T',
      _profile(stage.kind),
      '-E',
      'main',
      '-Fo',
      '${file.path}.dxil',
      file.path,
    ]);
    if (result.exitCode != 0) {
      failures.add(
        '${stage.name}: DXC refused ${file.path}:\n'
        '${result.stdout}${result.stderr}',
      );
      continue;
    }
    compiled++;
  }

  final translated = stages.length - failures.length;
  stdout.writeln(
    'hlsl lint: ${stages.length} stages, $translated through naga to HLSL'
    '${dxc == null ? ', DXC skipped (not on PATH)' : ', $compiled through DXC'}'
    ', written to ${directory.path}',
  );
  if (failures.isNotEmpty) {
    _fail('hlsl lint failed:\n  ${failures.join('\n  ')}');
  }
}

/// The manifest's render stages, prepared as the WebGPU table prepares
/// them: includes resolved, varyings numbered across the manifest, samplers
/// split.
List<_Stage> _renderStages(ShaderSet shaders) {
  try {
    final resolved = <String, String>{
      for (final entry in shaders.stages.values)
        entry.file: resolveIncludes(
          shaders.sources[entry.file]!,
          shaders.sources,
          from: entry.file,
        ),
    };
    final locations = assignVaryingLocations(<Set<String>>[
      for (final entry in shaders.stages.values)
        scanVaryings(
          resolved[entry.file]!,
          from: entry.file,
          fragment: entry.fragment,
        ),
    ]);
    return <_Stage>[
      for (final MapEntry(key: name, value: entry) in shaders.stages.entries)
        _Stage(
          name,
          entry.fragment ? ShaderStageKind.fragment : ShaderStageKind.vertex,
          prepareStage(
            resolved[entry.file]!,
            from: entry.file,
            fragment: entry.fragment,
            varyingLocations: locations,
          ).glsl,
        ),
    ];
  } on GlslTranslateException catch (error) {
    _fail(error.message);
  } on WgslPrepareException catch (error) {
    _fail(error.message);
  }
}

/// The compute manifest's stages, includes resolved, as
/// `flutter3d_webgpu/tool/generate_compute_shaders.dart` reads them.
List<_Stage> _computeStages() {
  final root = '${packageRoot('flutter3d_shaders')}/shaders';
  final manifest =
      jsonDecode(File('$root/flutter3d.compute.json').readAsStringSync())
          as Map<String, Object?>;
  final sources = <String, String>{
    for (final file
        in Directory(root)
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.glsl') || f.path.endsWith('.comp')))
      file.path.substring(root.length + 1): file.readAsStringSync(),
  };
  return <_Stage>[
    for (final MapEntry(key: name, value: raw) in manifest.entries)
      _Stage(
        name,
        ShaderStageKind.compute,
        resolveIncludes(
          sources[((raw! as Map<String, Object?>)['file']! as String)
              .replaceFirst('shaders/', '')]!,
          sources,
          from: name,
        ),
      ),
  ];
}
