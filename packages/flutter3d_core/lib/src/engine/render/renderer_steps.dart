/// The renderer's side of the plugin API: [RendererSteps], the registry a
/// plugin adds render steps and anchored nodes through, and the schedule the
/// frame graph is registered from.
///
/// **A part of `renderer.dart`**, so the frame compile can read what the
/// registry holds without the registry publishing it.
part of 'renderer.dart';

/// The [RenderStepRegistry] a [Renderer] fills: a plugin's own render steps,
/// and its passes placed at the engine's anchors.
///
/// **What a plugin that draws is handed.** Its `install` asks the host for
/// this type, `host.registry<RendererSteps>()`, and gets a view scoped to
/// the plugin: everything added through it is withdrawn when the plugin is
/// switched off, and ranked by the plugin's place in the install order. An
/// application without plugins uses [Renderer.renderSteps] directly.
///
/// ```dart
/// const glow = RenderStep('soft glow', needs: {RenderStep.bloom});
///
/// void install(PluginHost host) {
///   host.registry<RendererSteps>()
///     ..addStep(glow)
///     ..addNode(SoftGlowNode(), at: RenderAnchor.afterBloom, step: glow);
/// }
/// ```
///
/// The registry reaches the plugin host by being one of its registries:
/// `EngineLoop(registries: [renderer.renderSteps], plugins: …)`.
///
/// ## Steps
///
/// [addStep] makes a [RenderStep] one of this renderer's, beside the thirty
/// built in: `RenderSettings.without` and `only` switch it (given [added]
/// as `also`), a step it needs takes it down when switched off, and
/// `FrameResult.skipped` reports it — see [RenderStep].
///
/// ## Nodes
///
/// [addNode] places a [RenderNode] at a [RenderAnchor] — the node's own
/// [RenderNode.defaultAnchor] when none is named. The nodes at one anchor run
/// in this order: the application's; then each plugin's, in install order —
/// and `after`/`before`, naming other nodes at the same anchor, move them
/// within that. A name at another anchor, or nowhere, is ignored, as a loop
/// constraint naming an absent system is.
///
/// ## A plugin's own anchors
///
/// [addAnchor] adds a `RenderAnchor.after` — an anchor of a plugin's own,
/// standing right after an engine anchor or another added one — so the
/// plugin, and those built on it, place nodes relative to something that
/// does not move when an engine pass is renamed. A node at an anchor nobody
/// added is refused.
///
/// ## Contributors
///
/// [addContributor] adds a [PassContributor]: draws that go *inside* the
/// engine's own passes — the scene's, the transparent half, the velocity and
/// the depth pre-pass — as particles and splats do. Everything else is a
/// node.
///
/// A node given a `step` runs only while the step is on: switched off, the
/// node is inactive, and the frame reports its pass as switched off.
final class RendererSteps extends RenderStepRegistry {
  RendererSteps._() : _store = _StepStore(), _scope = null;

  RendererSteps._scoped(RendererSteps root, PluginScope scope)
    : _store = root._store,
      _scope = scope;

  final _StepStore _store;
  final PluginScope? _scope;

  String get _owner =>
      _scope == null ? 'the application' : 'plugin "${_scope.manifest.id}"';

  /// The steps added to this renderer, in the order they were added.
  List<RenderStep> get added => List<RenderStep>.unmodifiable(<RenderStep>[
    for (final entry in _store.steps) entry.step,
  ]);

  /// Every step this renderer knows: the built-in ones, then [added].
  List<RenderStep> get all => List<RenderStep>.unmodifiable(<RenderStep>[
    ...RenderStep.values,
    ...added,
  ]);

  /// The step called [name], built in or added, or null.
  RenderStep? named(String name) {
    for (final step in all) {
      if (step.name == name) return step;
    }
    return null;
  }

  /// The names of the nodes added at [anchor], in the order they will be
  /// registered there. For a test, or an inspector, that wants to see where a
  /// node went without compiling a frame.
  List<String> nodesAt(RenderAnchor anchor) => <String>[
    for (final entry in _store.orderedAt(anchor)) entry.node.name,
  ];

  /// Makes [step] one of this renderer's steps.
  ///
  /// Throws an [ArgumentError] for a built-in step, for a name another step
  /// already has, and for a step that needs one this renderer does not know
  /// — add the need first.
  Registration addStep(RenderStep step) {
    if (step.isBuiltIn) {
      throw ArgumentError.value(
        step.name,
        'step',
        'is one of the engine\'s own steps; it needs no adding',
      );
    }
    final taken = named(step.name);
    if (taken != null) {
      final owner = _store.steps
          .where((entry) => entry.step == taken)
          .map((entry) => entry.owner)
          .firstOrNull;
      throw ArgumentError.value(
        step.name,
        'step',
        'a step of this name is already ${owner == null ? 'built in' : 'added, by $owner'}',
      );
    }
    for (final need in step.needs) {
      if (need.isBuiltIn || _store.steps.any((e) => e.step == need)) continue;
      throw ArgumentError.value(
        step.name,
        'step',
        'needs "${need.name}", which this renderer does not know. Add that '
            'step first',
      );
    }
    final entry = _AddedStep(step, _owner);
    _store.steps.add(entry);
    final registration = Registration(() => _store.steps.remove(entry));
    _scope?.track(registration);
    return registration;
  }

  /// Places [node] at [at] — the node's own [RenderNode.defaultAnchor] when
  /// left out — owned by [step] when one is given.
  ///
  /// [after] and [before] name other nodes at the same anchor. [step] must be
  /// built in or added; switched off, it makes [node] inactive and the frame
  /// reports the pass as switched off.
  ///
  /// Throws an [ArgumentError] for a node named as one of the engine's
  /// passes (`RenderSettings.passOrder`, or a `reflection probe N`), for a
  /// name another added node has, for a step this renderer does not know,
  /// and for a plugin's anchor nobody added with [addAnchor].
  Registration addNode(
    RenderNode node, {
    RenderAnchor? at,
    RenderStep? step,
    List<String> after = const <String>[],
    List<String> before = const <String>[],
  }) {
    final anchor = at ?? node.defaultAnchor;
    if (!anchor.isEngine && !_store.anchors.any((e) => e.anchor == anchor)) {
      throw ArgumentError.value(
        anchor.name,
        'at',
        'is not an anchor of this renderer. Add it with addAnchor first',
      );
    }
    final name = node.name;
    if (RenderSettings.passOrder.contains(name) ||
        name.startsWith(RenderStep.reflectionProbes.passPrefix!)) {
      throw ArgumentError.value(
        name,
        'node',
        'is the name of one of the engine\'s passes; a node needs a name of '
            'its own',
      );
    }
    for (final entry in _store.nodes) {
      if (entry.node.name != name) continue;
      throw ArgumentError.value(
        name,
        'node',
        'a node of this name is already at ${entry.anchor.name}, added by '
            '${entry.owner}',
      );
    }
    if (step != null &&
        !step.isBuiltIn &&
        !_store.steps.any((e) => e.step == step)) {
      throw ArgumentError.value(
        step.name,
        'step',
        'is not a step of this renderer. Add it with addStep first',
      );
    }
    final entry = _AnchoredNode(
      node,
      anchor,
      step,
      List<String>.unmodifiable(after),
      List<String>.unmodifiable(before),
      _scope,
      _owner,
      _store.sequence++,
    );
    _store.nodes.add(entry);
    final registration = Registration(() => _store.nodes.remove(entry));
    _scope?.track(registration);
    return registration;
  }

  /// Every anchor a node can be placed at here: the engine's, then the ones
  /// added with [addAnchor], in the order they were added.
  @override
  List<RenderAnchor> get anchors =>
      List<RenderAnchor>.unmodifiable(<RenderAnchor>[
        ...RenderAnchor.values,
        for (final entry in _store.anchors) entry.anchor,
      ]);

  /// The anchor called [name] — the engine's or an added one — or null.
  RenderAnchor? anchorNamed(String name) {
    for (final anchor in anchors) {
      if (anchor.name == name) return anchor;
    }
    return null;
  }

  /// Makes [anchor], a `RenderAnchor.after`, one of this renderer's: nodes
  /// may be placed at it from now on, and run right after the nodes at the
  /// anchor it follows.
  ///
  /// Throws an [ArgumentError] for an engine anchor, for a name another
  /// anchor has, and for an anchor following one this renderer does not
  /// know — add that one first.
  Registration addAnchor(RenderAnchor anchor) {
    if (anchor.isEngine) {
      throw ArgumentError.value(
        anchor.name,
        'anchor',
        'is one of the engine\'s own anchors; it needs no adding',
      );
    }
    if (anchorNamed(anchor.name) != null) {
      throw ArgumentError.value(
        anchor.name,
        'anchor',
        'an anchor of this name is already here',
      );
    }
    final follows = anchor.follows!;
    if (!anchors.contains(follows)) {
      throw ArgumentError.value(
        anchor.name,
        'anchor',
        'follows "${follows.name}", which this renderer does not know. Add '
            'that anchor first',
      );
    }
    final entry = _AddedAnchor(anchor, _owner);
    _store.anchors.add(entry);
    final registration = Registration(() => _store.anchors.remove(entry));
    _scope?.track(registration);
    return registration;
  }

  /// The contributors added, in the order they draw.
  List<PassContributor> get contributors => _store.contributors.all;

  /// Adds [contributor] — draws that go inside the engine's own passes: the
  /// scene's, the transparent half, the velocity and the depth pre-pass —
  /// ordered by [PassContributor.order] and then by when they were added,
  /// and hands it back. [removeContributor] takes it out again; one added
  /// by a plugin goes when the plugin is uninstalled.
  T addContributor<T extends PassContributor>(T contributor) {
    _store.contributors.add(contributor);
    _scope?.track(Registration(() => _store.contributors.remove(contributor)));
    return contributor;
  }

  /// Takes [contributor] out, and says whether it was there: an editor
  /// switching a feature off, a widget leaving the tree.
  bool removeContributor(PassContributor contributor) =>
      _store.contributors.remove(contributor);

  /// The steps taken with [provide], in the order they were taken.
  List<RenderStep> get provided => List<RenderStep>.unmodifiable(<RenderStep>[
    for (final entry in _store.provided) entry.step,
  ]);

  /// Who provides [step] — `plugin "flutter3d_addon_light.bloom"`, or `the
  /// application` — or null when nobody has taken it.
  String? providerOf(RenderStep step) => _store.provided
      .where((entry) => entry.step == step)
      .map((entry) => entry.owner)
      .firstOrNull;

  /// The steps whose provider was switched off, and which every frame of
  /// this renderer draws without until one provides them again.
  Set<RenderStep> get withdrawn =>
      Set<RenderStep>.unmodifiable(_store.withdrawn);

  /// Takes [step] as the caller's own: the plugin providing it is its
  /// switch.
  ///
  /// **What an addon registers for a pass the kernel still draws.** The
  /// post-processing families (`flutter3d_post/light.dart`, `_shading`,
  /// `_reflections`, `_atmosphere`, `_motion`, `_style`) each provide the
  /// steps of their effects. While the plugin is on, the step is drawn as
  /// its settings say, exactly as before. When the plugin is switched off —
  /// its registrations cancelled — the step is *withdrawn*: every frame of
  /// this renderer is drawn [RenderSettings.without] it, and with whatever
  /// needs it, and `FrameResult.skipped` reports it switched off. Provided
  /// again, it is back.
  ///
  /// **A step nobody provided is drawn as its settings say.** That is the
  /// 1.0 promise: a renderer with no plugin installed draws the frame it
  /// always drew, and installing the `standard` preset changes nothing. Only
  /// switching an addon off takes its effects out.
  ///
  /// [step] is built in or one [addStep] added. Throws an [ArgumentError]
  /// for a step this renderer does not know, and for one already provided —
  /// naming who provides it.
  Registration provide(RenderStep step) {
    if (!step.isBuiltIn && !_store.steps.any((e) => e.step == step)) {
      throw ArgumentError.value(
        step.name,
        'step',
        'is not a step of this renderer. Add it with addStep first',
      );
    }
    final owner = providerOf(step);
    if (owner != null) {
      throw ArgumentError.value(
        step.name,
        'step',
        'is already provided, by $owner',
      );
    }
    final entry = _ProvidedStep(step, _owner);
    _store.provided.add(entry);
    _store.withdrawn.remove(step);
    final registration = Registration(() {
      _store.provided.remove(entry);
      _store.withdrawn.add(step);
    });
    _scope?.track(registration);
    return registration;
  }

  /// The device of the renderer this registry belongs to — what a plugin
  /// loads its own stages with, `device.loadShaders(bytes)`.
  GraphicsDevice get device => _store.renderer!.device;

  /// The settings slots added to this renderer, each once, in the order
  /// they were first added — what a settings screen walks, and what a
  /// level's `renderSettings` section is read against:
  ///
  /// ```dart
  /// final extensions = SettingsExtensions.fromJson(
  ///   level.renderSettings,
  ///   slots: renderer.renderSteps.settings,
  /// );
  /// settings = settings.copyWith(extensions: extensions);
  /// ```
  List<SettingsSlot<Object>> get settings {
    final seen = <String>{};
    return List<SettingsSlot<Object>>.unmodifiable(<SettingsSlot<Object>>[
      for (final entry in _store.settings)
        if (seen.add(entry.id)) entry,
    ]);
  }

  /// The slot added under [id], or null.
  SettingsSlot<Object>? settingsNamed(String id) =>
      _store.settings.where((slot) => slot.id == id).firstOrNull;

  /// Makes [slot] one of this renderer's settings, until the result is
  /// cancelled — what `RenderStepAddon.settings` does for each of its own.
  ///
  /// **A third-party addon's settings join `RenderSettings` this way, with
  /// nothing in the kernel touched.** The values live in
  /// [RenderSettings.extensions] whether or not the slot is added here;
  /// adding it is what makes the renderer able to name it — to decode it
  /// from a document, and to list it.
  ///
  /// Adding the same slot twice is counted, as two addons of one family may
  /// share one. Throws an [ArgumentError] for a different slot under an id
  /// already taken.
  Registration addSettings(SettingsSlot<Object> slot) {
    final taken = settingsNamed(slot.id);
    if (taken != null && !identical(taken, slot)) {
      throw ArgumentError.value(
        slot.id,
        'slot',
        'another settings slot is already added under this id',
      );
    }
    _store.settings.add(slot);
    final registration = Registration(() => _store.settings.remove(slot));
    _scope?.track(registration);
    return registration;
  }

  /// Adds [library] to the stages this renderer finds by name, ahead of
  /// everything it already had — `P8` — until the result is cancelled: how
  /// a plugin hands the renderer the stages of the lighting models it
  /// registers, and how an application adds a bundle of its own.
  ///
  /// **More than one bundle of materials.** The build hook compiles each
  /// `.f3dmat` into a bundle of its own, a level loaded after the renderer
  /// was made brings its own, and `materials` at [Renderer.create] is one
  /// library. Added later means consulted earlier, as a layer is: a bundle
  /// that names a stage another already has is replacing it, which is what a
  /// game loading a variant of a look means by it. Adding a library that is
  /// already here moves it to the front. What the renderer resolved by name
  /// is forgotten, since a name may now answer differently, and linked again
  /// at the next draw that asks. Cancelling the result takes the library out
  /// again; a material still naming one of its stages draws as a material
  /// whose stage is missing does.
  ///
  /// **The one way in, since 1.0.** `Renderer.addMaterials` and
  /// `removeMaterials` did the same without the registration.
  Registration addMaterials(ShaderLibrary library) {
    final renderer = _store.renderer!.._addMaterials(library);
    final registration = Registration(() => renderer._removeMaterials(library));
    _scope?.track(registration);
    return registration;
  }

  /// Makes [model] one a material may name, through [LightingModels], until
  /// the result is cancelled — the lighting-model half of a
  /// `LightingModelAddon`. The stages are not this call's: a model whose
  /// stages the backend's bundle does not carry comes with [addMaterials].
  Registration addLightingModel(LightingModel model) {
    final shared = LightingModels.register(model);
    _store.lightingModels.add(model);
    final registration = Registration(() {
      _store.lightingModels.remove(model);
      shared.cancel();
    });
    _scope?.track(registration);
    return registration;
  }

  /// The lighting models this renderer draws: the built-in ones, then those
  /// added to it with [addLightingModel], in the order they were added —
  /// this engine's own, where `LightingModels.all` is every engine's in the
  /// process (the table a document is read against).
  List<LightingModel> get lightingModels =>
      List<LightingModel>.unmodifiable(<LightingModel>[
        ...LightingModel.builtIn,
        for (final model in _store.lightingModels)
          if (!LightingModel.builtIn.contains(model)) model,
      ]);

  /// [settings] without the [withdrawn] steps — [settings] itself, the same
  /// object, while nothing is withdrawn, so a frame with every provider on
  /// is the frame with none installed.
  RenderSettings _framed(RenderSettings settings) => _store.withdrawn.isEmpty
      ? settings
      : settings.without(_store.withdrawn, also: added);

  @override
  RendererSteps forPlugin(PluginScope scope) =>
      RendererSteps._scoped(this, scope);
}

/// What a renderer's [RendererSteps] and all its scoped views share.
final class _StepStore {
  final List<_AddedStep> steps = <_AddedStep>[];
  final List<_AnchoredNode> nodes = <_AnchoredNode>[];
  final List<_ProvidedStep> provided = <_ProvidedStep>[];
  final Set<RenderStep> withdrawn = <RenderStep>{};
  final List<SettingsSlot<Object>> settings = <SettingsSlot<Object>>[];
  final List<_AddedAnchor> anchors = <_AddedAnchor>[];
  final List<LightingModel> lightingModels = <LightingModel>[];
  final ContributorRegistry contributors = ContributorRegistry();
  int sequence = 0;

  /// [engine] and every added anchor that stands after it, directly or
  /// through another added one, in the order the frame meets them: an
  /// anchor, then what follows it, depth first, in the order they were
  /// added.
  List<RenderAnchor> anchorsFrom(RenderAnchor engine) {
    final out = <RenderAnchor>[];
    void walk(RenderAnchor at) {
      out.add(at);
      for (final entry in anchors) {
        if (entry.anchor.follows == at) walk(entry.anchor);
      }
    }

    walk(engine);
    return out;
  }

  /// The renderer the registry belongs to, set as it is made.
  Renderer? renderer;

  /// The nodes at [anchor] in registration order — the application's, then
  /// each plugin's by rank — before any constraint moves them.
  List<_AnchoredNode> orderedAt(RenderAnchor anchor) {
    final at = <_AnchoredNode>[
      for (final entry in nodes)
        if (entry.anchor == anchor) entry,
    ]..sort(_AnchoredNode.compare);
    return orderByConstraints<_AnchoredNode>(
      at,
      nameOf: (entry) => entry.node.name,
      after: (entry) => entry.after,
      before: (entry) => entry.before,
      what: 'passes at ${anchor.name}',
    );
  }
}

final class _AddedAnchor {
  _AddedAnchor(this.anchor, this.owner);

  final RenderAnchor anchor;
  final String owner;
}

final class _AddedStep {
  _AddedStep(this.step, this.owner);

  final RenderStep step;
  final String owner;
}

final class _ProvidedStep {
  _ProvidedStep(this.step, this.owner);

  final RenderStep step;
  final String owner;
}

final class _AnchoredNode {
  _AnchoredNode(
    this.node,
    this.anchor,
    this.step,
    this.after,
    this.before,
    this.scope,
    this.owner,
    this.sequence,
  );

  final RenderNode node;
  final RenderAnchor anchor;
  final RenderStep? step;
  final List<String> after;
  final List<String> before;
  final PluginScope? scope;
  final String owner;
  final int sequence;

  int get rank => scope?.rank ?? -1;

  static int compare(_AnchoredNode a, _AnchoredNode b) {
    final byRank = a.rank.compareTo(b.rank);
    return byRank != 0 ? byRank : a.sequence.compareTo(b.sequence);
  }
}

/// An anchored node as this frame registers it: active only while its step
/// is on in this frame's settings.
///
/// Everything else is the node's own, so the graph sees the pass the plugin
/// declared, and the name it reports is the node's.
final class _SteppedNode extends RenderNode {
  const _SteppedNode(this._node, this._step, this._settings);

  final RenderNode _node;
  final RenderStep _step;
  final RenderSettings _settings;

  @override
  String get name => _node.name;

  @override
  List<ResourceId> get reads => _node.reads;

  @override
  List<ResourceId> get optionalReads => _node.optionalReads;

  @override
  List<ResourceId> get writes => _node.writes;

  @override
  List<ResourceId> get keeps => _node.keeps;

  @override
  bool get isActive => _step.isOn(_settings) && _node.isActive;

  @override
  bool get isSupported => _node.isSupported;

  @override
  RenderAnchor get defaultAnchor => _node.defaultAnchor;

  @override
  void execute(RenderFrame frame) => _node.execute(frame);
}

/// The frame's passes placed at anchors, and put in order — the one
/// mechanism the engine's own passes and a plugin's go through.
///
/// **The frame is a row of slots**: each [RenderAnchor] in the order of
/// [RenderAnchor.values], and after each anchor the engine's own passes that
/// stand there, if any — the shadow maps after `beforeShadows`, the bloom
/// after `beforeBloom`. Within a slot, the nodes are ordered by
/// [orderByConstraints], given in registration order; the engine's passes
/// are chained, each after the one before it, which is the order they were
/// always registered in. The registration order of the whole graph is the
/// slots read left to right, and that order is the version chain.
final class _FrameSchedule {
  final List<List<_Slotted>> _slots = List<List<_Slotted>>.generate(
    RenderAnchor.values.length * 2,
    (_) => <_Slotted>[],
  );

  static int _anchorSlot(RenderAnchor anchor) {
    final index = RenderAnchor.values.indexOf(anchor);
    assert(index >= 0, '$anchor is not one of this engine\'s anchors');
    return index * 2;
  }

  /// The engine's own [passes], standing just after [anchor], in order.
  void stage(RenderAnchor anchor, List<FrameGraphNode> passes) {
    final slot = _slots[_anchorSlot(anchor) + 1];
    for (var i = 0; i < passes.length; i++) {
      slot.add(
        _Slotted(
          passes[i],
          after: i == 0 ? const <String>[] : <String>[passes[i - 1].name],
        ),
      );
    }
  }

  /// [node] at [anchor], after whatever is already there unless [after] or
  /// [before] say otherwise.
  void at(
    RenderAnchor anchor,
    FrameGraphNode node, {
    List<String> after = const <String>[],
    List<String> before = const <String>[],
  }) => _slots[_anchorSlot(anchor)].add(
    _Slotted(node, after: after, before: before),
  );

  /// Every node, in the order the graph registers them.
  List<FrameGraphNode> ordered() => <FrameGraphNode>[
    for (var i = 0; i < _slots.length; i++)
      for (final slotted in orderByConstraints<_Slotted>(
        _slots[i],
        nameOf: (s) => s.node.name,
        after: (s) => s.after,
        before: (s) => s.before,
        what: i.isEven
            ? 'passes at ${RenderAnchor.values[i ~/ 2].name}'
            : 'engine passes after ${RenderAnchor.values[i ~/ 2].name}',
      ))
        slotted.node,
  ];

  /// The nodes placed at [anchor] or any anchor after it — not the engine's
  /// own passes, which the renderer names itself.
  List<FrameGraphNode> placedFrom(RenderAnchor anchor) => <FrameGraphNode>[
    for (var i = _anchorSlot(anchor); i < _slots.length; i += 2)
      for (final slotted in _slots[i]) slotted.node,
  ];
}

final class _Slotted {
  const _Slotted(
    this.node, {
    this.after = const <String>[],
    this.before = const <String>[],
  });

  final FrameGraphNode node;
  final List<String> after;
  final List<String> before;
}
