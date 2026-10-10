/// Varying locations for a loadable bundle, held against the engine's own.
///
/// **A loaded stage is paired with a stage it was not compiled beside.** A
/// bundle's fragment stage runs against the engine's vertex stages, WebGPU
/// does not link, and the two modules are joined by `@location` alone — so a
/// varying's number has to be the number the engine already committed to
/// `flutter3d_webgpu`'s `lib/engine_shaders.dart`. Numbering a bundle on its
/// own would give `v_normal` whatever index its own family handed out, the
/// pipeline would still build, and the fragment stage would read normals out
/// of some other varying's slot.
///
/// Written for `flutter3d_webgpu/tool/pack_wgsl_section.dart` and moved here
/// when `flutter3d_build` needed the same answer for a project's materials
/// (P8): two copies of this rule would be two rules, and the one that drifted
/// would draw wrongly rather than fail.
library;

import 'glsl_to_wgsl.dart';
import 'glsl_translate.dart';
import 'source_package.dart';

/// One stage of a bundle, with its `#include`s already expanded.
typedef BundleStageSource = ({String file, bool fragment, String resolved});

/// A location per varying name, agreeing with [engine]'s.
///
/// Computed over both manifests, then held against the engine's alone. Throws
/// [WgslPrepareException] when the bundle would move one of the engine's
/// varyings: the failure is a refusal to pack rather than a section that
/// would compile and read the wrong slot.
Map<String, int> bundleVaryingLocations(
  ShaderSet engine,
  Iterable<BundleStageSource> stages,
) {
  final theirs = <Set<String>>[
    for (final entry in engine.stages.values)
      scanVaryings(
        _resolveEngine(engine, entry.file),
        from: entry.file,
        fragment: entry.fragment,
      ),
  ];
  final ours = <Set<String>>[
    for (final stage in stages)
      scanVaryings(stage.resolved, from: stage.file, fragment: stage.fragment),
  ];

  final engineOnly = assignVaryingLocations(theirs);
  final together = assignVaryingLocations(<Set<String>>[...theirs, ...ours]);

  for (final entry in engineOnly.entries) {
    if (together[entry.key] == entry.value) continue;
    throw WgslPrepareException(
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

String _resolveEngine(ShaderSet engine, String file) {
  try {
    return resolveIncludes(engine.sources[file]!, engine.sources, from: file);
  } on GlslTranslateException catch (error) {
    throw WgslPrepareException('the engine\'s $file: ${error.message}');
  }
}
