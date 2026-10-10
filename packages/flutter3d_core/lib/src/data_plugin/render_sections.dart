/// A data plugin's `materials` and `renderSteps`: the two sections of a
/// `.f3dplugin` document the renderer reads, through the plugin API's
/// `DataSectionRegistry`.
library;

import 'package:flutter3d_core/flutter3d_core.dart' show RendererSteps;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show
        DataSection,
        DataSectionContext,
        DocumentFormatException,
        PluginException,
        PluginHost,
        RenderAnchor;

import 'runtime_shaders.dart';

/// The sections this package reads from a data plugin: [materialsSection]
/// and [renderStepsSection], for an engine that draws.
///
/// ```dart
/// final sections = DataSections(<DataSection>[
///   ...renderDataSections,   // flutter3d_core
///   entityKindsSection,      // flutter3d_sim
///   effectsSection,          // flutter3d_particles
/// ]);
/// ```
const List<DataSection> renderDataSections = <DataSection>[
  materialsSection,
  renderStepsSection,
];

/// A data plugin's `materials`: the material language, compiled where the
/// backend compiles at run time ([RuntimeShaders]).
///
/// An entry is `{"source": "glow.f3dmat"}`, a file of the plugin's, or
/// `{"text": "material Glow { … }"}`, the material written in place. On an
/// engine that draws nothing the section is read and noted, not compiled;
/// on one that draws, the engine needs a [RuntimeShaders] among its
/// registries.
const DataSection materialsSection = _MaterialsSection();

/// A data plugin's `renderSteps`: a full-screen stage per backend at an
/// anchor, switched like the engine's own steps ([RuntimeRenderStep]).
///
/// The anchor is one of the engine's (`after bloom`, or as Dart spells it,
/// `afterBloom`), checked when the document is read, or one another plugin
/// added to the renderer, resolved and checked when this one is installed.
/// A step over the scene's light goes before tone mapping, one over the
/// finished picture (`"present": true`) after it. The engine needs a
/// [RuntimeShaders] and the renderer's [RendererSteps] among its registries.
const DataSection renderStepsSection = _RenderStepsSection();

/// A material in the material language, as a file of the plugin's or as
/// text written into the document.
final class DataMaterial {
  const DataMaterial({this.source, this.text})
    : assert(
        (source == null) != (text == null),
        'a material is a source path or text, not both',
      );

  /// The `.f3dmat` file, relative to the plugin's own directory.
  final String? source;

  /// The material written out in the document.
  final String? text;

  Map<String, Object?> toJson() => <String, Object?>{
    'source': ?source,
    'text': ?text,
  };
}

/// A render step a data plugin adds: a full-screen stage per backend at an
/// anchor. See [RuntimeRenderStep], which it becomes.
final class DataRenderStep {
  const DataRenderStep({
    required this.name,
    required this.anchor,
    required this.shaders,
    this.present = false,
    this.needs = const <String>[],
    this.after = const <String>[],
    this.before = const <String>[],
  });

  /// The name without the plugin's prefix.
  final String name;

  /// The anchor the step is placed at, by name: one of the engine's
  /// (`after bloom`), or one another plugin added to the renderer
  /// (`RendererSteps.addAnchor`). A name, not a [RenderAnchor], because a
  /// plugin's anchor is the renderer's, and the document is read before
  /// there is one; it is resolved with `RendererSteps.anchorNamed` when the
  /// plugin is installed.
  final String anchor;

  /// The stage's source file, by backend.
  final Map<String, String> shaders;
  final bool present;
  final List<String> needs;
  final List<String> after;
  final List<String> before;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'anchor': anchor,
    'shaders': shaders,
    if (present) 'present': true,
    if (needs.isNotEmpty) 'needs': needs,
    if (after.isNotEmpty) 'after': after,
    if (before.isNotEmpty) 'before': before,
  };
}

/// The entries of a section written as a list of objects.
List<Map<String, Object?>> _entries(Object? written, String key) =>
    switch (written) {
      null => const <Map<String, Object?>>[],
      final List<Object?> list when list.every((e) => e is Map) =>
        <Map<String, Object?>>[
          for (final entry in list) (entry! as Map).cast<String, Object?>(),
        ],
      _ => throw DocumentFormatException('"$key" is not a list of objects'),
    };

/// The materials as read, then with their texts: each with the name its
/// messages give it.
final class _Materials {
  const _Materials(this.materials, [this.texts = const <(String, String)>[]]);

  final List<DataMaterial> materials;
  final List<(String, String)> texts;
}

final class _MaterialsSection extends DataSection {
  const _MaterialsSection();

  @override
  String get name => 'materials';

  @override
  Object read(Object? written, DataSectionContext context) => _Materials(
    List<DataMaterial>.unmodifiable(<DataMaterial>[
      for (final entry in _entries(written, name))
        switch ((entry['source'], entry['text'])) {
          (final String source, null) => DataMaterial(source: source),
          (null, final String text) => DataMaterial(text: text),
          _ => throw const DocumentFormatException(
            'a material is a "source" file or its "text", one of the two',
          ),
        },
    ]),
  );

  @override
  Object? write(Object section) => <Object?>[
    for (final m in (section as _Materials).materials) m.toJson(),
  ];

  @override
  List<String> resources(Object section) => <String>[
    for (final m in (section as _Materials).materials) ?m.source,
  ];

  @override
  Object load(Object section, DataSectionContext context) {
    final materials = (section as _Materials).materials;
    return _Materials(
      materials,
      List<(String, String)>.unmodifiable(<(String, String)>[
        for (final material in materials)
          switch (material) {
            DataMaterial(:final String text) => (
              '${context.plugin} (inline)',
              text,
            ),
            DataMaterial(:final source) => (source!, context.textOf(source)),
          },
      ]),
    );
  }

  @override
  void install(PluginHost host, Object section, DataSectionContext context) {
    final texts = (section as _Materials).texts;
    if (texts.isEmpty) return;
    if (host.backend == null) {
      context.note('materials not loaded: this engine draws nothing');
      return;
    }
    final shaders = _shadersOf(host, context, 'materials');
    for (final (from, text) in texts) {
      shaders.addMaterial(text, from: from);
    }
  }
}

/// The render steps as read, then with their stages: each step's stage
/// source by backend, by step name.
final class _RenderSteps {
  const _RenderSteps(
    this.steps, [
    this.stages = const <String, Map<String, String>>{},
  ]);

  final List<DataRenderStep> steps;
  final Map<String, Map<String, String>> stages;
}

final class _RenderStepsSection extends DataSection {
  const _RenderStepsSection();

  @override
  String get name => 'renderSteps';

  @override
  Object read(Object? written, DataSectionContext context) => _RenderSteps(
    List<DataRenderStep>.unmodifiable(<DataRenderStep>[
      for (final entry in _entries(written, name)) _renderStep(entry),
    ]),
  );

  @override
  Object? write(Object section) => <Object?>[
    for (final s in (section as _RenderSteps).steps) s.toJson(),
  ];

  @override
  List<String> resources(Object section) => <String>[
    for (final s in (section as _RenderSteps).steps) ...s.shaders.values,
  ];

  @override
  Object load(Object section, DataSectionContext context) {
    final steps = (section as _RenderSteps).steps;
    return _RenderSteps(steps, <String, Map<String, String>>{
      for (final step in steps)
        step.name: <String, String>{
          for (final MapEntry(key: backend, value: path)
              in step.shaders.entries)
            RuntimeBackends.normalize(backend)!: context.textOf(path),
        },
    });
  }

  @override
  void install(PluginHost host, Object section, DataSectionContext context) {
    final _RenderSteps(:steps, :stages) = section as _RenderSteps;
    if (steps.isEmpty) return;
    if (host.backend == null) {
      context.note('render steps not loaded: this engine draws nothing');
      return;
    }
    final id = context.plugin;
    final shaders = _shadersOf(host, context, 'render steps');
    final renderer = host.maybeRegistry<RendererSteps>();
    if (renderer == null) {
      throw PluginException(
        'plugin "$id" brings render steps, and this engine has no '
        'RendererSteps to add them to; hand the renderer\'s renderSteps to '
        'the engine among its registries',
      );
    }
    for (final step in steps) {
      // Through the renderer, which knows the anchors other plugins added
      // as well as the engine's.
      final anchor = _anchorIn(renderer.anchors, step.anchor);
      if (anchor == null) {
        throw PluginException(
          'plugin "$id": render step "${step.name}" is placed at '
          '"${step.anchor}", which is not an anchor of this renderer; the '
          'anchors are ${renderer.anchors.map((a) => a.name).join(', ')}. A '
          'plugin\'s own anchor has to be added before this one is installed',
        );
      }
      if (!anchor.isEngine) {
        _checkSide(
          'render step "${step.name}"',
          anchor,
          present: step.present,
          refuse: PluginException.new,
        );
      }
      shaders.addRenderStep(
        RuntimeRenderStep(
          name: '$id.${step.name}',
          anchor: anchor,
          shaders: stages[step.name]!,
          present: step.present,
          needs: step.needs,
          after: step.after,
          before: step.before,
        ),
        renderer,
      );
    }
  }
}

/// The engine's [RuntimeShaders], or a [PluginException] saying it has
/// none for the [what] the plugin brings.
RuntimeShaders _shadersOf(
  PluginHost host,
  DataSectionContext context,
  String what,
) =>
    host.maybeRegistry<RuntimeShaders>() ??
    (throw PluginException(
      'plugin "${context.plugin}" brings $what, and this engine has no '
      'RuntimeShaders to compile them; hand one to the engine among its '
      'registries',
    ));

DataRenderStep _renderStep(Map<String, Object?> entry) {
  String text(String key, String what) => switch (entry[key]) {
    final String value when value.isNotEmpty => value,
    _ => throw DocumentFormatException('$what names no "$key"'),
  };
  final name = text('name', 'a render step');
  final what = 'render step "$name"';
  final written = text('anchor', what);
  final present = switch (entry['present']) {
    null => false,
    final bool value => value,
    _ => throw DocumentFormatException('$what: "present" is not true or false'),
  };
  // An engine anchor is checked here; any other name is one a plugin adds
  // to the renderer, resolved and checked when this one is installed.
  final engine = _anchorIn(RenderAnchor.values, written);
  if (engine != null) {
    _checkSide(
      what,
      engine,
      present: present,
      refuse: DocumentFormatException.new,
    );
  }
  final shaders = switch (entry['shaders']) {
    final Map<Object?, Object?> map
        when map.isNotEmpty &&
            map.keys.every((k) => k is String) &&
            map.values.every((v) => v is String) =>
      Map<String, String>.unmodifiable(map.cast<String, String>()),
    _ => throw DocumentFormatException(
      '$what: "shaders" is not a map from a backend to a stage\'s file',
    ),
  };
  List<String> names(String key) => switch (entry[key]) {
    null => const <String>[],
    final List<Object?> list when list.every((e) => e is String) =>
      List<String>.unmodifiable(list.cast<String>()),
    _ => throw DocumentFormatException('$what: "$key" is not a list of names'),
  };
  return DataRenderStep(
    name: name,
    anchor: engine?.name ?? written,
    shaders: shaders,
    present: present,
    needs: names('needs'),
    after: names('after'),
    before: names('before'),
  );
}

/// The anchor of [anchors] called [written], by its name (`after bloom`) or
/// as Dart spells it (`afterBloom`), which is how a reader of the API will
/// write it; null when none is.
RenderAnchor? _anchorIn(List<RenderAnchor> anchors, String written) {
  final spaced = written.replaceAllMapped(
    RegExp('[A-Z]'),
    (Match m) => ' ${m[0]!.toLowerCase()}',
  );
  return anchors
      .where((RenderAnchor a) => a.name == written || a.name == spaced)
      .firstOrNull;
}

/// Refuses, through [refuse], a step on the wrong side of tone mapping. A
/// plugin's anchor is judged by the engine anchor it follows
/// ([RenderAnchor.engineAnchor]).
///
/// A stage over the scene's light reads `hdr_colour`, which tone mapping
/// turns into `frame`: one placed on the wrong side of it would read a
/// picture that is not there yet, or is not there any more.
void _checkSide(
  String what,
  RenderAnchor anchor, {
  required bool present,
  required Exception Function(String message) refuse,
}) {
  final at = RenderAnchor.values.indexOf(anchor.engineAnchor);
  final tonemap = RenderAnchor.values.indexOf(RenderAnchor.afterTonemap);
  if (present && at < tonemap) {
    throw refuse(
      '$what draws over the finished picture ("present": true) at '
      '"${anchor.name}", before tone mapping has made one; place it at '
      '"${RenderAnchor.afterTonemap.name}" or later',
    );
  }
  if (!present && at >= tonemap) {
    throw refuse(
      '$what draws over the scene\'s light at "${anchor.name}", after tone '
      'mapping has turned it into the picture; place it before '
      '"${RenderAnchor.afterTonemap.name}", or set "present": true',
    );
  }
}
