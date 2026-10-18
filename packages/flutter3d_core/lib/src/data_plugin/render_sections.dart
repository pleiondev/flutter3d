/// A data plugin's `materials`, `renderSteps`, `bindings`, `pipeline`,
/// `lightTypes`, `vertexLayouts` and `lodTables`: the sections of a
/// `.f3dplugin` document the renderer reads, through the plugin API's
/// `DataSectionRegistry`.
library;

import 'package:flutter3d_core/flutter3d_core.dart'
    show
        LightPackContext,
        LightTypeHook,
        LightTypes,
        LodContext,
        LodPolicy,
        RenderHooks,
        RendererSteps;
import 'package:flutter3d_core/formats.dart' show PipelineDocument;
import 'package:flutter3d_core/geometry.dart'
    show VertexAttribute, VertexLayout;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show
        DataSection,
        DataSectionContext,
        DataSectionInstall,
        DataSectionLoad,
        DataSectionRead,
        DocumentFormatException,
        FormatSpec,
        LightType,
        PluginException,
        PluginHost,
        RenderAnchor,
        SceneBindingRegistry,
        SceneBindingSpec;

import '../formats/engine_words.dart';
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
  bindingsSection,
  pipelineSection,
  lightTypesSection,
  vertexLayoutsSection,
  lodTablesSection,
];

/// A data plugin's `lightTypes`: light types of its own in the light loop
/// (D22), each packed as the built-in shape it is based on, with up to four
/// numbers of its own in the row's last `vec4` — what its `lighttype`
/// declaration in a `.f3dmat` reads as `lightParams`.
///
/// ```json
/// "lightTypes": [{"name": "tube", "base": "point", "params": [1.5, 0, 0, 0]}]
/// ```
///
/// Registered with the renderer's [LightTypes] as `<id>.<name>`, so a light
/// of that type gets a code of a plugin's own, which a Wasm render module
/// asks with `light_code`. On an engine that draws nothing it is read and
/// noted.
const DataSection lightTypesSection = _LightTypesSection();

/// A data plugin's `vertexLayouts`: the vertex layouts its meshes and its
/// materials' stages are written against, by name, each a list of the
/// engine's vertex attributes.
///
/// ```json
/// "vertexLayouts": [{"name": "ribbon", "attributes": ["position", "color"]}]
/// ```
///
/// **Declared, and held to what the engine draws.** Every attribute is one
/// of the engine's (`position`, `normal`, `texcoord`, `tangent`, `color`,
/// `joints`, `weights`), in a layout no larger than the engine's skinned
/// one; an attribute of a plugin's own is refused when the document is
/// read, naming it, since a stage that read one would be bound to nothing.
/// The declaration is the shape a later minor's own attributes arrive in.
const DataSection vertexLayoutsSection = _VertexLayoutsSection();

/// A data plugin's `lodTables`: levels of detail chosen by distance, a
/// table each, for the groups named after it.
///
/// ```json
/// "lodTables": [{"name": "trees", "distances": [12, 40, 90]}]
/// ```
///
/// A `LodGroup` named `<id>.trees` shows level 0 nearer than 12 metres from
/// the camera, level 1 to 40, level 2 to 90 and level 3 beyond, clamped to
/// its levels; any other group passes to the next policy. Registered as a
/// `LodPolicy` with the renderer's [RenderHooks], chained in dependency
/// order with every other plugin's.
const DataSection lodTablesSection = _LodTablesSection();

/// A data plugin's `pipeline`: an `f3d.pipeline` document's body — its
/// anchors and its nodes, each made by a `PipelineNodeKind` a Dart plugin
/// registered — applied to the renderer with `RendererSteps.fromDocument`
/// (D44). Its anchors and nodes are in the plugin's namespace like any it
/// adds by hand; on an engine that draws nothing it is read and noted.
///
/// ```json
/// "pipeline": {
///   "anchors": [{"name": "acme_glow.after glow", "after": "f3d.after_bloom"}],
///   "nodes": [{"name": "acme_glow.streak", "kind": "acme_glow.streak",
///              "anchor": "acme_glow.after glow", "options": {"length": 8}}]
/// }
/// ```
const DataSection pipelineSection = _PipelineSection();

/// A data plugin's `bindings`: how its components are shown in the scene
/// (D37), each entry a `SceneBindingSpec` —
///
/// ```json
/// "bindings": [
///   {"component": "acme_forge.heat", "node": "f3d.mesh",
///    "material": "glow.fmat", "parameters": {"temperature": "glowStrength"},
///    "interpolation": "linear", "lifetime": "component"}
/// ]
/// ```
///
/// Installed into the engine's `SceneBindingRegistry` (the renderer's
/// `SceneBindings`); on an engine that draws nothing the section is read
/// and noted, not installed.
const DataSection bindingsSection = _BindingsSection();

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
/// The anchor is one of the engine's (`f3d.after_bloom`, or as Dart spells it,
/// `afterBloom`), checked when the document is read, or one another plugin
/// added to the renderer, resolved and checked when this one is installed.
/// A step over the scene's light goes before tone mapping, one over the
/// finished picture (`"present": true`) after it. The engine needs a
/// [RuntimeShaders] and the renderer's [RendererSteps] among its registries.
const DataSection renderStepsSection = _RenderStepsSection();

/// A material in the material language, as a file of the plugin's or as
/// text written into the document.
final class DataMaterial {
  /// A material read from [source] or written as [text]; exactly one of the
  /// two is given, asserted.
  const DataMaterial({this.source, this.text})
    : assert(
        (source == null) != (text == null),
        'a material is a source path or text, not both',
      );

  /// The `.f3dmat` file, relative to the plugin's own directory.
  final String? source;

  /// The material written out in the document.
  final String? text;

  /// The entry as written in the document's `materials` list: whichever of
  /// `source` and `text` is set.
  Map<String, Object?> toJson() => <String, Object?>{
    'source': ?source,
    'text': ?text,
  };
}

/// A render step a data plugin adds: a full-screen stage per backend at an
/// anchor. See [RuntimeRenderStep], which it becomes.
final class DataRenderStep {
  /// A step named [name] at [anchor], drawn by [shaders]; by default over
  /// the scene's light, with no needs and no ordering.
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

  /// Whether the step draws over the finished picture, after tone mapping,
  /// rather than over the scene's light before it. False by default.
  final bool present;

  /// Built-in steps it cannot run without, by name: `bloom`. Empty by
  /// default.
  final List<String> needs;

  /// Other nodes at [anchor] it goes after, by name.
  final List<String> after;

  /// Other nodes at [anchor] it goes before, by name.
  final List<String> before;

  /// The entry as written in the document's `renderSteps` list; `present`
  /// and the empty lists are left out.
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
  Object read(DataSectionRead step) {
    final written = step.written;
    return _Materials(
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
  }

  @override
  Object? write(Object section) => <Object?>[
    for (final m in (section as _Materials).materials) m.toJson(),
  ];

  @override
  List<String> resources(Object section) => <String>[
    for (final m in (section as _Materials).materials) ?m.source,
  ];

  @override
  Object load(DataSectionLoad step) {
    final section = step.section;
    final context = step.context;
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
  void install(DataSectionInstall step) {
    final host = step.host;
    final section = step.section;
    final context = step.context;
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
  Object read(DataSectionRead step) {
    final written = step.written;
    return _RenderSteps(
      List<DataRenderStep>.unmodifiable(<DataRenderStep>[
        for (final entry in _entries(written, name)) _renderStep(entry),
      ]),
    );
  }

  @override
  Object? write(Object section) => <Object?>[
    for (final s in (section as _RenderSteps).steps) s.toJson(),
  ];

  @override
  List<String> resources(Object section) => <String>[
    for (final s in (section as _RenderSteps).steps) ...s.shaders.values,
  ];

  @override
  Object load(DataSectionLoad given) {
    final section = given.section;
    final context = given.context;
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
  void install(DataSectionInstall given) {
    final host = given.host;
    final section = given.section;
    final context = given.context;
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
      // A Wasm render module of the document's drives the step, when one
      // names it: the runtime that read the document made it.
      final program = context.renderProgram(step.name);
      shaders.addRenderStep(
        RuntimeRenderStep(
          name: '$id.${step.name}',
          anchor: anchor,
          shaders: stages[step.name]!,
          present: step.present,
          needs: step.needs,
          after: step.after,
          before: step.before,
          program: program,
          lightTypes: program == null ? null : host.maybeRegistry<LightTypes>(),
        ),
        renderer,
      );
    }
  }
}

final class _BindingsSection extends DataSection {
  const _BindingsSection();

  @override
  String get name => 'bindings';

  @override
  Object read(DataSectionRead step) {
    final written = step.written;
    return List<SceneBindingSpec>.unmodifiable(<SceneBindingSpec>[
      for (final entry in _entries(written, name))
        SceneBindingSpec.fromJson(entry),
    ]);
  }

  @override
  Object? write(Object section) => <Object?>[
    for (final spec in section as List<SceneBindingSpec>) spec.toJson(),
  ];

  @override
  void install(DataSectionInstall step) {
    final host = step.host;
    final section = step.section;
    final context = step.context;
    final specs = section as List<SceneBindingSpec>;
    if (specs.isEmpty) return;
    final bindings = host.maybeRegistry<SceneBindingRegistry>();
    if (bindings == null) {
      context.note('bindings not installed: this engine draws nothing');
      return;
    }
    specs.forEach(bindings.add);
  }
}

final class _PipelineSection extends DataSection {
  const _PipelineSection();

  @override
  String get name => 'pipeline';

  @override
  Object read(DataSectionRead step) {
    final written = step.written;
    return switch (written) {
      final Map<Object?, Object?> map when map.keys.every((k) => k is String) =>
        PipelineDocument.fromJson(<String, Object?>{
          // The section is the body; the envelope is the document's own.
          'format': 'f3d.pipeline',
          'version': 1,
          ...map.cast<String, Object?>(),
        }),
      _ => throw const DocumentFormatException('"pipeline" is not an object'),
    };
  }

  @override
  Object? write(Object section) {
    final json = (section as PipelineDocument).toJson();
    return <String, Object?>{
      for (final MapEntry(:key, :value) in json.entries)
        if (!FormatSpec.envelopeKeys.contains(key)) key: value,
    };
  }

  @override
  void install(DataSectionInstall step) {
    final host = step.host;
    final section = step.section;
    final context = step.context;
    final document = section as PipelineDocument;
    if (document.anchors.isEmpty && document.nodes.isEmpty) return;
    if (host.backend == null) {
      context.note('pipeline not applied: this engine draws nothing');
      return;
    }
    final steps =
        host.maybeRegistry<RendererSteps>() ??
        (throw PluginException(
          'plugin "${context.plugin}" brings a pipeline, and this engine has '
          'no RendererSteps to apply it to',
        ));
    try {
      steps.fromDocument(document);
    } on ArgumentError catch (refused, stack) {
      Error.throwWithStackTrace(
        PluginException(
          'plugin "${context.plugin}": its pipeline ${refused.invalidValue} '
          '${refused.message}',
        ),
        stack,
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

/// The anchor of [anchors] called [written], by its name
/// (`f3d.after_bloom`), by the word from before the `f3d.` prefix that files
/// written then carry (`after bloom`), or as Dart spells it (`afterBloom`),
/// which is how a reader of the API will write it; null when none is.
RenderAnchor? _anchorIn(List<RenderAnchor> anchors, String written) {
  final spaced = engineWordFor(
    written.replaceAllMapped(
      RegExp('[A-Z]'),
      (Match m) => ' ${m[0]!.toLowerCase()}',
    ),
  );
  return anchors
      .where((RenderAnchor a) => a.name == written || a.name == spaced)
      .firstOrNull;
}

/// Refuses, through [refuse], a step on the wrong side of tone mapping. A
/// plugin's anchor is judged by the engine anchor it follows
/// ([RenderAnchor.engineAnchor]).
///
/// A stage over the scene's light reads `hdr_color`, which tone mapping
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

/// The numbers of a written list, or a refusal naming [what].
List<double> _numbers(Object? written, String what, {int? most}) =>
    switch (written) {
      null => const <double>[],
      final List<Object?> list
          when list.every((e) => e is num && e.isFinite) &&
              (most == null || list.length <= most) =>
        List<double>.unmodifiable(<double>[
          for (final e in list) (e! as num).toDouble(),
        ]),
      _ => throw DocumentFormatException(
        '$what is not a list of${most == null ? '' : ' at most $most'} '
        'finite numbers',
      ),
    };

/// A name of a data plugin's own, without the dot its id is put before it
/// with, or a refusal naming [what].
String _ownName(Object? written, String what) => switch (written) {
  final String name when name.isNotEmpty && !name.contains('.') => name,
  _ => throw DocumentFormatException(
    '$what names no "name" of its own, without a dot: the plugin\'s id is '
    'put before it',
  ),
};

/// A data plugin's light type, as read: its name, its base, its numbers.
final class DataLightType {
  /// A light type named [name], packed as [base] with up to four [params].
  const DataLightType({
    required this.name,
    required this.base,
    this.params = const <double>[],
  });

  /// The name without the plugin's prefix.
  final String name;

  /// The built-in shape it is packed as.
  final LightType base;

  /// Up to four numbers, written into floats 12–15 of its row.
  final List<double> params;

  /// The entry as written in the document's `lightTypes` list; empty
  /// `params` are left out.
  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'base': base.name,
    if (params.isNotEmpty) 'params': params,
  };
}

/// Packs one data light type: its base's row, with its numbers in the last
/// `vec4`.
final class _DataLightTypeHook extends LightTypeHook {
  _DataLightTypeHook(this.type, this.params);

  @override
  final LightType type;

  final List<double> params;

  @override
  void pack(LightPackContext context) {
    final row = context.row;
    for (var i = 0; i < params.length; i++) {
      row[12 + i] = params[i];
    }
  }
}

final class _LightTypesSection extends DataSection {
  const _LightTypesSection();

  @override
  String get name => 'lightTypes';

  @override
  Object read(DataSectionRead step) =>
      List<DataLightType>.unmodifiable(<DataLightType>[
        for (final entry in _entries(step.written, name)) _lightType(entry),
      ]);

  static DataLightType _lightType(Map<String, Object?> entry) {
    final type = _ownName(entry['name'], 'a light type');
    final base = switch (entry['base'] ?? 'point') {
      final String written => LightType.byName(written),
      _ => null,
    };
    if (base == null) {
      throw DocumentFormatException(
        'light type "$type": "base" is ${entry['base']}, and a light type is '
        'based on ${LightType.values.map((t) => t.name).join(', ')}',
      );
    }
    return DataLightType(
      name: type,
      base: base,
      params: _numbers(
        entry['params'],
        'light type "$type": "params"',
        most: 4,
      ),
    );
  }

  @override
  Object? write(Object section) => <Object?>[
    for (final type in section as List<DataLightType>) type.toJson(),
  ];

  @override
  void install(DataSectionInstall step) {
    final types = step.section as List<DataLightType>;
    if (types.isEmpty) return;
    final registry = step.host.maybeRegistry<LightTypes>();
    if (registry == null) {
      step.context.note(
        'light types not registered: this engine draws nothing',
      );
      return;
    }
    for (final type in types) {
      registry.register(
        _DataLightTypeHook(
          LightType.custom(
            '${step.context.plugin}.${type.name}',
            base: type.base,
          ),
          type.params,
        ),
      );
    }
  }
}

/// A data plugin's vertex layout, as read: its name and its attributes, in
/// order.
final class DataVertexLayout {
  /// A layout named [name] made of the engine's [attributes], in order.
  const DataVertexLayout({required this.name, required this.attributes});

  /// The name without the plugin's prefix.
  final String name;

  /// The engine's attributes it is made of, in order.
  final List<String> attributes;

  /// It as the engine describes a layout.
  VertexLayout get layout => VertexLayout(<VertexAttribute>[
    for (final attribute in attributes) _vertexAttributes[attribute]!,
  ]);

  /// The entry as written in the document's `vertexLayouts` list.
  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'attributes': attributes,
  };
}

/// The engine's vertex attributes, by name: what a layout may hold.
const Map<String, VertexAttribute> _vertexAttributes =
    <String, VertexAttribute>{
      'position': VertexLayout.position,
      'normal': VertexLayout.normal,
      'texcoord': VertexLayout.texcoord,
      'tangent': VertexLayout.tangent,
      'color': VertexLayout.color,
      'joints': VertexLayout.joints,
      'weights': VertexLayout.weights,
    };

final class _VertexLayoutsSection extends DataSection {
  const _VertexLayoutsSection();

  @override
  String get name => 'vertexLayouts';

  @override
  Object read(DataSectionRead step) =>
      List<DataVertexLayout>.unmodifiable(<DataVertexLayout>[
        for (final entry in _entries(step.written, name)) _vertexLayout(entry),
      ]);

  static DataVertexLayout _vertexLayout(Map<String, Object?> entry) {
    final layout = _ownName(entry['name'], 'a vertex layout');
    final attributes = switch (entry['attributes']) {
      final List<Object?> list
          when list.isNotEmpty && list.every((e) => e is String) =>
        List<String>.unmodifiable(list.cast<String>()),
      _ => throw DocumentFormatException(
        'vertex layout "$layout": "attributes" is not a list of the '
        'engine\'s attribute names',
      ),
    };
    for (final attribute in attributes) {
      if (!_vertexAttributes.containsKey(attribute)) {
        throw DocumentFormatException(
          'vertex layout "$layout" names the attribute "$attribute", which '
          'no stage of this engine reads: a layout is made of '
          '${_vertexAttributes.keys.join(', ')}; an attribute of a plugin\'s '
          'own arrives with the minor that binds one',
        );
      }
    }
    if (attributes.toSet().length != attributes.length) {
      throw DocumentFormatException(
        'vertex layout "$layout" names an attribute twice',
      );
    }
    return DataVertexLayout(name: layout, attributes: attributes);
  }

  @override
  Object? write(Object section) => <Object?>[
    for (final layout in section as List<DataVertexLayout>) layout.toJson(),
  ];

  @override
  void install(DataSectionInstall step) {
    // Held to the engine's attributes when read; nothing of the engine's
    // takes a plugin's layout by name yet, so what installs is the
    // declaration the document keeps, which a minor's own attributes
    // arrive in.
  }
}

/// A data plugin's level-of-detail table, as read.
final class DataLodTable {
  /// A table named [name] switching levels at [distances], in metres.
  const DataLodTable({required this.name, required this.distances});

  /// The name without the plugin's prefix: the groups it chooses for are
  /// named `<id>.<name>`.
  final String name;

  /// Where each level gives way to the next, in metres from the camera,
  /// ascending.
  final List<double> distances;

  /// The entry as written in the document's `lodTables` list.
  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'distances': distances,
  };
}

/// Chooses a group's level by its distance from the camera, for the groups
/// named after its table; any other group passes to the next policy.
final class _DistanceLod extends LodPolicy {
  const _DistanceLod(this.group, this.distances);

  final String group;
  final List<double> distances;

  @override
  int? select(LodContext context) {
    if (context.group.name != group) return null;
    final distance = context.group.worldPosition.distanceTo(
      context.camera.worldPosition,
    );
    return distances.where((double at) => distance >= at).length;
  }
}

final class _LodTablesSection extends DataSection {
  const _LodTablesSection();

  @override
  String get name => 'lodTables';

  @override
  Object read(DataSectionRead step) =>
      List<DataLodTable>.unmodifiable(<DataLodTable>[
        for (final entry in _entries(step.written, name)) _lodTable(entry),
      ]);

  static DataLodTable _lodTable(Map<String, Object?> entry) {
    final table = _ownName(entry['name'], 'a level-of-detail table');
    final distances = _numbers(
      entry['distances'],
      'level-of-detail table "$table": "distances"',
    );
    if (distances.isEmpty) {
      throw DocumentFormatException(
        'level-of-detail table "$table" gives no "distances"',
      );
    }
    for (var i = 0; i < distances.length; i++) {
      if (distances[i] <= 0 || (i > 0 && distances[i] <= distances[i - 1])) {
        throw DocumentFormatException(
          'level-of-detail table "$table": its "distances" climb from above '
          'nought, each further than the one before, in metres',
        );
      }
    }
    return DataLodTable(name: table, distances: distances);
  }

  @override
  Object? write(Object section) => <Object?>[
    for (final table in section as List<DataLodTable>) table.toJson(),
  ];

  @override
  void install(DataSectionInstall step) {
    final tables = step.section as List<DataLodTable>;
    if (tables.isEmpty) return;
    final hooks = step.host.maybeRegistry<RenderHooks>();
    if (hooks == null) {
      step.context.note(
        'level-of-detail tables not registered: this engine draws nothing',
      );
      return;
    }
    for (final table in tables) {
      hooks.addLodPolicy(
        _DistanceLod('${step.context.plugin}.${table.name}', table.distances),
      );
    }
  }
}
