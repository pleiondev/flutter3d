/// Questions about the source tree that decide whether a piece of work is done.
///
/// **The tree is the record, not a checkbox.** A row such as "the UV mode can be
/// switched into" is true when the mode is marked ready in the file that lists
/// them, and a page that waited for somebody to tick it would go green a day
/// late and stay green after a revert. Each probe is one such question, small
/// enough to be read as the sentence it stands for.
library;

import 'dart:io';

import 'model.dart';

/// Answers one question about the tree under [root].
typedef Probe = ProbeResult Function(Directory root);

String? _read(Directory root, String path) {
  final file = File('${root.path}/$path');
  return file.existsSync() ? file.readAsStringSync() : null;
}

/// True when [path] exists and matches [pattern].
Probe fileMatches(String path, RegExp pattern, {String what = ''}) {
  return (Directory root) {
    final text = _read(root, path);
    if (text == null) return ProbeResult(ok: false, detail: '$path is missing');
    return pattern.hasMatch(text)
        ? ProbeResult(ok: true, detail: what)
        : ProbeResult(
            ok: false,
            detail: what.isEmpty ? path : 'not yet: $what',
          );
  };
}

/// True when [path] exists.
Probe fileExists(String path) {
  return (Directory root) => File('${root.path}/$path').existsSync()
      ? ProbeResult(ok: true, detail: path)
      : ProbeResult(ok: false, detail: '$path is missing');
}

/// True when every one of [stems] is imported by some file under [directory]
/// other than its own.
///
/// This is the test for "written and connected to nothing": a screen with a
/// test and no importer is a screen nobody can reach, which is what four of
/// the modeller's were. The answer names the ones still unreached.
Probe importedFrom(String directory, List<String> stems) {
  return (Directory root) {
    final dir = Directory('${root.path}/$directory');
    if (!dir.existsSync()) {
      return ProbeResult(ok: false, detail: '$directory is missing');
    }
    final sources = <String, String>{
      for (final file in dir.listSync(recursive: true).whereType<File>())
        if (file.path.endsWith('.dart')) file.path: file.readAsStringSync(),
    };
    final missing = <String>[
      for (final stem in stems)
        if (!sources.entries.any(
          (entry) =>
              !entry.key.endsWith('/$stem.dart') &&
              (entry.value.contains("/$stem.dart'") ||
                  entry.value.contains("'$stem.dart'")),
        ))
          stem,
    ];
    return missing.isEmpty
        ? ProbeResult(ok: true, detail: 'all ${stems.length} are imported')
        : ProbeResult(
            ok: false,
            detail:
                '${stems.length - missing.length} of ${stems.length} '
                'imported; not yet: ${missing.join(', ')}',
          );
  };
}

/// All of [probes] at once, answered with the first thing that is missing.
Probe allOf(List<Probe> probes) {
  return (Directory root) {
    for (final probe in probes) {
      final result = probe(root);
      if (!result.ok) return result;
    }
    return const ProbeResult(ok: true);
  };
}

/// The probes the 0.7.0 checklist asks, by the id the checklist names them with.
Map<String, Probe> releaseProbes() => <String, Probe>{
  'uv-mode': (Directory root) {
    const path = 'apps/flutter3d_modeler/lib/src/ui/tools.dart';
    final text = _read(root, path);
    if (text == null) return ProbeResult(ok: false, detail: '$path is missing');
    final entry = RegExp(r"uv\(\s*'UV'[^)]*\)").firstMatch(text)?.group(0);
    if (entry == null) {
      return const ProbeResult(ok: false, detail: 'no UV mode');
    }
    return entry.contains('ready: false')
        ? const ProbeResult(ok: false, detail: 'UV is still marked not ready')
        : const ProbeResult(ok: true, detail: 'UV is marked ready');
  },
  'modeler-screens': importedFrom('apps/flutter3d_modeler/lib', <String>[
    'uv_screen',
    'lod_screen',
    'retopo_overlay',
    'frame_capture_panel',
    'simulation_cache_strip',
  ]),
  'lod-export': allOf(<Probe>[
    fileMatches(
      'packages/flutter3d_model_core/lib/src/project_document.dart',
      RegExp(r'withLods'),
      what: 'the converter writes levels of detail',
    ),
    fileMatches(
      'packages/flutter3d_model_core/lib/src/exporting.dart',
      RegExp(r'carriesLods'),
      what: 'an export says which formats carry them',
    ),
  ]),
  'edu-carried': fileExists(
    'packages/flutter3d/lib/src/engine/assets/load_model_asset.dart',
  ),
  'burst-source': fileMatches(
    'packages/flutter3d_particles/lib/src/particle_system.dart',
    RegExp(r'int burst\([^)]*source', dotAll: true),
    what: 'a burst can be given a source',
  ),
  'ground-collision': fileMatches(
    'packages/flutter3d_sim/lib/src/level/level_collision.dart',
    RegExp(r'_groundCollider'),
    what: 'a level adds its ground to the collision world',
  ),
  'texture-transform': fileMatches(
    'packages/flutter3d/lib/src/engine/assets/model_asset.dart',
    RegExp(r'sharedTextureTransform'),
    what: 'an atlas-packed model moves its coordinates',
  ),
  'project-format': fileMatches(
    'packages/flutter3d_model_core/lib/src/project_format.dart',
    RegExp(r"'modifiers'"),
    what: 'a project file keeps its modifier stack',
  ),
  'boundary-doc': fileExists('doc/boundary-0.7.0.md'),
  'architecture-doc': fileMatches(
    'ARCHITECTURE.md',
    RegExp(r'0\.7\.0 is the shelf'),
    what: 'section 16 describes 0.7.0',
  ),
  'modeler-version': fileMatches(
    'apps/flutter3d_modeler/pubspec.yaml',
    RegExp(r'^version:\s*0\.7\.0', multiLine: true),
    what: 'the modeller carries 0.7.0',
  ),
  'tutorial-deploy': fileMatches(
    'cloud/server/lib/src/config.dart',
    RegExp(r'learnDirectory'),
    what: 'the tutorial reaches the server it is served from',
  ),
  // --- The showcase ------------------------------------------------------
  'showcase-lod': allOf(<Probe>[
    fileMatches(
      'packages/flutter3d_model_core/lib/src/project_document.dart',
      RegExp(r'convertedTo\(base\.layout\)'),
      what: 'the levels a project exports keep the layout of their object',
    ),
    fileMatches(
      'packages/flutter3d_model_core/lib/src/lod_cache.dart',
      RegExp(r'convertedTo\(base\.layout\)'),
      what: 'the levels its screen shows keep it too',
    ),
  ]),
  'showcase-platform': allOf(<Probe>[
    fileExists('apps/flutter3d_showcase/pubspec.yaml'),
    fileMatches(
      'pubspec.yaml',
      RegExp(r'apps/flutter3d_showcase'),
      what: 'the app is in the workspace',
    ),
    fileMatches(
      'tool/structure/repository.dart',
      RegExp(r"'flutter3d_showcase'"),
      what: 'the structure rules know the app',
    ),
    fileMatches(
      'apps/flutter3d_showcase/macos/Runner/Info.plist',
      RegExp(r'FLTEnableFlutterGPU'),
      what: 'macOS asks for the GPU',
    ),
    fileExists('apps/flutter3d_showcase/lib/src/demo/demo.dart'),
  ]),
  'showcase-site': allOf(<Probe>[
    fileMatches(
      'site/tool/build.mjs',
      RegExp('showcase'),
      what: 'the site build knows the showcase',
    ),
    fileExists('site/tool/showcase.sh'),
  ]),
};
