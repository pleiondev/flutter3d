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
/// const glow = RenderStep('acme.soft_glow', needs: {RenderStep.bloom});
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

  /// Refuses, with a [PluginException], a [name] a plugin registers as
  /// [what] outside its namespace (`PluginManifest.nameProblem`). The
  /// application's own registrations, and the engine's packages', are not
  /// held to one.
  void _inNamespace(String name, String what) {
    final problem = _scope?.manifest.nameProblem(name, what: what);
    if (problem != null) throw PluginException(problem);
  }

  /// The manifest of the plugin from outside the engine this view files
  /// under, or null for the application's view and an engine plugin's: what
  /// is held to its namespace and may take over nothing undeclared.
  PluginManifest? get _outside => switch (_scope?.manifest) {
    final PluginManifest manifest when !manifest.isEngine => manifest,
    _ => null,
  };

  /// Whether the outside plugin [manifest] declared, through its
  /// `RenderStepAddon.replaces` or `replacesStages`, that it takes over
  /// [name], a built-in step's or an engine stage's.
  bool _takesOver(PluginManifest manifest, String name) =>
      _store.takeovers[manifest.id]?.contains(name) ?? false;

  /// Refuses, with a [PluginException], [what] from a plugin that declares
  /// it touches only tooling (`PluginTouches.tooling`): a game ships without
  /// such a plugin, so nothing it adds may be part of the frame the game
  /// draws.
  void _notTooling(String what) {
    final manifest = _scope?.manifest;
    if (manifest == null || manifest.touches != PluginTouches.tooling) return;
    throw PluginException(
      'plugin "${manifest.id}" declares that it touches only tooling, and '
      'added $what to the frame, which a game draws without it. Add it from '
      'a plugin that touches the view',
    );
  }

  /// The steps added to this renderer, in the order they were added.
  List<RenderStep> get added => List<RenderStep>.unmodifiable(<RenderStep>[
    for (final entry in _store.steps) entry.step,
  ]);

  /// Every step this renderer knows: the built-in ones, then [added].
  List<RenderStep> get all => List<RenderStep>.unmodifiable(<RenderStep>[
    ...RenderStep.values,
    ...added,
  ]);

  /// The step called [name], built in or added, or null. A built-in step's
  /// word from before the `f3d.` prefix (`bloom`, `color grade`) finds it
  /// too, as the files written then name it.
  RenderStep? named(String name) {
    final word = engineWordFor(name);
    for (final step in all) {
      if (step.name == name || step.name == word) return step;
    }
    return null;
  }

  /// The names of the nodes added at [anchor], in the order they will be
  /// registered there. For a test, or an inspector, that wants to see where a
  /// node went without compiling a frame.
  List<String> nodesAt(RenderAnchor anchor) => <String>[
    for (final entry in _store.orderedAt(anchor)) entry.node.name,
  ];

  /// Every node added, at every anchor, in the order the frame meets them.
  @override
  List<String> get nodeNames => <String>[
    for (final anchor in anchors) ...nodesAt(anchor),
  ];

  /// Makes [step] one of this renderer's steps.
  ///
  /// Throws a [NameTakenException] for a built-in step and for a name
  /// another step already has, naming who has it, and an [ArgumentError]
  /// for a step that needs one this renderer does not know — add the need
  /// first.
  ///
  /// Through a plugin's view, a [PluginException] for a step named outside
  /// the plugin's namespace, `<namespace>.<name>` (D23).
  Registration addStep(RenderStep step) {
    _notTooling('the render step "${step.name}"');
    _inNamespace(step.name, 'the render step');
    if (step.isBuiltIn) {
      throw NameTakenException(
        step.name,
        what: 'the render step',
        owner: 'the engine',
        detail: 'it is one of the engine\'s own steps and needs no adding',
      );
    }
    final taken = named(step.name);
    if (taken != null) {
      final owner = _store.steps
          .where((entry) => entry.step == taken)
          .map((entry) => entry.owner)
          .firstOrNull;
      throw NameTakenException(
        step.name,
        what: 'the render step',
        owner: owner ?? 'the engine',
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
  /// Throws a [NameTakenException] for a node named as one of the engine's
  /// passes (`RenderSettings.passOrder`, or a `reflection probe N`) and for
  /// a name another added node has, and an [ArgumentError] for a step this
  /// renderer does not know and for a plugin's anchor nobody added with
  /// [addAnchor]. Through a plugin's view, a [PluginException] for a node,
  /// or a resource it makes (`FrameGraphBuilder.create`), named outside the
  /// plugin's namespace.
  ///
  /// **Cancelling the result takes the node out and disposes it**
  /// (`FrameGraphNode.dispose`), once no frame in flight can still be using
  /// what it holds.
  ///
  /// **A node that throws is quarantined, and the frame goes on.** It is
  /// left out of every frame after, reported as `PassSkip.failed` with the
  /// plugin that placed it named (`SkippedPass.failure`); what only read
  /// its output is culled or does without; the frame it threw in is drawn
  /// to the end and lists it in `FrameResult.nodeFailures`. Placing it again
  /// — the plugin switched off and on — lets it run again.
  Registration addNode(
    RenderNode node, {
    RenderAnchor? at,
    RenderStep? step,
    List<String> after = const <String>[],
    List<String> before = const <String>[],
  }) => _placeNode(
    _checkedNode(node, at: at, step: step, after: after, before: before),
  );

  /// [entry] in the frame until the result is cancelled, which takes it
  /// out, runs [also], and disposes its node once no frame in flight can
  /// still be using it.
  Registration _placeNode(_AnchoredNode entry, {void Function()? also}) {
    _store.nodes.add(entry);
    final registration = Registration(() {
      _store.nodes.remove(entry);
      also?.call();
      _store.disposeNode(entry.node);
    });
    _scope?.track(registration);
    return registration;
  }

  /// [placing], the load of what [entry]'s node runs with, followed: the
  /// node stays pending in the frame until it settles (the node's own
  /// `isReady`); an error it ends in quarantines the node, naming its
  /// owner, rather than reaching nobody as an unhandled one; and once it
  /// settles after the node was taken out, [afterCancelled] lets go of what
  /// the load made. [whenPlaced] waits for it.
  void _follow(
    _AnchoredNode entry,
    Future<Object?> placing, {
    void Function()? afterCancelled,
  }) {
    late final Future<void> followed;
    followed = placing
        .then<void>(
          (_) {},
          onError: (Object error, StackTrace stack) {
            if (_store.nodes.contains(entry)) entry.fail(error, stack);
          },
        )
        .whenComplete(() {
          _store.placing.remove(followed);
          if (!_store.nodes.contains(entry)) afterCancelled?.call();
        });
    _store.placing.add(followed);
  }

  /// Completes once every placement started by this renderer's
  /// registrations so far has settled — [addComputeStep], [addWorkload],
  /// [addFieldUpload], [placeSkinningHook], and the compute a node asked
  /// for with `FrameGraphBuilder.place` — placed, refused or failed.
  ///
  /// **What a test or a loading screen waits on; a frame never does.** The
  /// registrations are synchronous and the frame draws without what is
  /// still loading (`PassSkip.pending`); this is for a caller that wants
  /// the frame with it.
  Future<void> whenPlaced() async {
    while (_store.placing.isNotEmpty) {
      await Future.wait(List<Future<void>>.of(_store.placing));
    }
  }

  /// [node] at [at] with its constraints, checked as [addNode] checks it and
  /// not yet in the frame.
  _AnchoredNode _checkedNode(
    RenderNode node, {
    RenderAnchor? at,
    RenderStep? step,
    List<String> after = const <String>[],
    List<String> before = const <String>[],
  }) {
    final anchor = at ?? node.defaultAnchor;
    _notTooling('the node "${node.name}"');
    _inNamespace(node.name, 'the node');
    for (final desc in NodeDeclarations.of(node).created) {
      _inNamespace(desc.id.name, 'the resource');
    }
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
      throw NameTakenException(
        name,
        what: 'the node',
        owner: 'the engine',
        detail:
            'it is one of the engine\'s passes; a node needs a name of '
            'its own',
      );
    }
    for (final entry in _store.nodes) {
      if (entry.node.name != name) continue;
      throw NameTakenException(
        name,
        what: 'the node',
        owner: entry.owner,
        detail: 'it stands at ${entry.anchor.name}',
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
    return _AnchoredNode(
      node,
      anchor,
      step,
      List<String>.unmodifiable(after),
      List<String>.unmodifiable(before),
      _scope,
      _owner,
      _store.sequence++,
    );
  }

  /// The device this renderer draws on, whose compute the hardware layer
  /// places this renderer's compute steps, workloads, fields and hooks on.
  GraphicsDevice _drawing(String what) => switch (_store.renderer) {
    final renderer? => renderer.device,
    null => throw StateError(
      '$what on a registry no renderer owns: its compute is the drawing '
      'device\'s, and there is none',
    ),
  };

  /// Adds [step] as a node at [at], as [addNode] does, and places it
  /// (`ComputeStep.prepare`) — the one call that puts a compute step in the
  /// frame.
  ///
  /// **Added at once, placed behind it, because a frame cannot wait.**
  /// Loading a kernel is asynchronous on every device; the registration is
  /// not. The step is in the frame from this call on and reported as
  /// `PassSkip.pending` until it is placed, and the frame after that runs
  /// it. Where it goes is the hardware layer's to say, from the device this
  /// renderer draws on and the registry that opened it: that device, the
  /// sidecar `registerWgpuSidecar` added, the CPU `registerCpuBackend`
  /// added. A step nothing can run stays in the frame as
  /// `PassSkip.unsupported`, with `ComputeStep.refusal` saying why, and
  /// culls what only read its output; a placement that fails some other way
  /// quarantines the step as a node that threw is. Cancelling the result
  /// while the placement is still loading takes the step out at once.
  /// [whenPlaced] waits for the placement.
  ///
  /// Throws what [addNode] throws, before anything is loaded.
  ///
  /// **Breaking in 1.0.0-rc.1+1:** no executors are handed in, and the
  /// result is the [Registration] itself, not a `Future` of it.
  Registration addComputeStep(
    ComputeStep step, {
    RenderAnchor? at,
    RenderStep? owner,
    List<String> after = const <String>[],
    List<String> before = const <String>[],
  }) {
    // The checks first, then the node, then the placement: a name refused
    // loads no kernel on any device.
    final entry = _checkedNode(
      step,
      at: at,
      step: owner,
      after: after,
      before: before,
    );
    final device = _drawing('addComputeStep');
    final registration = _placeNode(entry);
    _follow(entry, step.prepare(device));
    return registration;
  }

  /// Puts [workload] in the frame, placed by the hardware layer's workload
  /// rule for the device this renderer draws on: the GPUs the frame has,
  /// then the workload's own host code where it has some, then the CPU
  /// device; [workloadStep] answers what it was told
  /// ([WorkloadStep.binding], [WorkloadStep.refusal]) — since 1.0.0-rc.1+1.
  ///
  /// **The workload is told, the caller decides nothing.** A simulation
  /// handing its step over learns where it runs through
  /// `ComputeWorkload.placed` and draws from what that says, and neither it
  /// nor whoever adds it says where it may run.
  ///
  /// In the frame at once and placed behind it, as [addComputeStep] is:
  /// `PassSkip.pending` until the workload is told. Cancelling the result
  /// takes the step out of the frame and lets go of its buffers once no
  /// frame in flight can be using them (`WorkloadStep.dispose`). A workload
  /// nothing can run — no executor and no host code — stays in the frame
  /// and is reported as `PassSkip.unsupported`, as a compute step is.
  ///
  /// **Breaking in 1.0.0-rc.1+1:** the result is the [Registration]
  /// itself, not a `Future` of it.
  Registration addWorkload(ComputeWorkload workload, {RenderAnchor? at}) {
    final step = WorkloadStep(workload);
    final entry = _checkedNode(step, at: at);
    final device = _drawing('addWorkload');
    _store.workloads.add(step);
    final registration = _placeNode(
      entry,
      also: () => _store.workloads.remove(step),
    );
    // A placement that lands after the step was taken out made buffers
    // nobody will draw: they go at once, since no frame ever ran it there.
    _follow(
      entry,
      step.prepare(device),
      afterCancelled: () {
        if (step.binding != null) step.dispose();
      },
    );
    return registration;
  }

  /// The step [workload] is in the frame as ([addWorkload]): what it was
  /// told, or why it was refused. Null for a workload not added here.
  WorkloadStep? workloadStep(ComputeWorkload workload) {
    for (final step in _store.workloads) {
      if (identical(step.workload, workload)) return step;
    }
    return null;
  }

  /// Adds [upload] as a node and places it (`FieldUpload.place`), as
  /// [addComputeStep] does for a compute step: the one call that puts a
  /// simulation's field in the frame.
  ///
  /// In the frame at once, `PassSkip.pending` until it is placed. An upload
  /// nothing can hold stays in the frame: the frame reports it as
  /// `PassSkip.unsupported`, with `FieldUpload.refusal` saying why, and
  /// culls whatever only read the field. Cancelling the registration takes
  /// the node out and lets go of the storage it held
  /// (`FieldUpload.dispose`).
  ///
  /// Throws what [addNode] throws, before anything is placed.
  ///
  /// **Breaking in 1.0.0-rc.1+1:** no executors are handed in, and the
  /// result is the [Registration] itself, not a `Future` of it.
  Registration addFieldUpload(
    FieldUpload upload, {
    RenderAnchor? at,
    RenderStep? owner,
    List<String> after = const <String>[],
    List<String> before = const <String>[],
  }) {
    final entry = _checkedNode(
      upload,
      at: at,
      step: owner,
      after: after,
      before: before,
    );
    final device = _drawing('addFieldUpload');
    final registration = _placeNode(entry);
    _follow(entry, upload.place(device), afterCancelled: upload.dispose);
    return registration;
  }

  /// Puts [hook] in the frame and places it: the one call that makes a
  /// [SkinningHook] skin (D22b).
  ///
  /// A hook with kernels is placed as a `ComputeStep` is, by the hardware
  /// layer, except never beside the drawing device, whose vertices would
  /// reach it only through the host: on the drawing device, or on the CPU.
  /// Until it is placed it claims no mesh, and the engine skins them as it
  /// would without the hook. A [HostSkinningHook] needs no placement. The
  /// step runs before the shadows and writes
  /// `FrameResourceIds.skinnedVertices`, which the scene reads. Through a
  /// plugin's view the step is named in the plugin's namespace,
  /// `<namespace>.skinning_<n>`.
  ///
  /// The hook is listed in [RenderHooks.skinningHooks] too, and the result
  /// takes both out again.
  ///
  /// **Breaking in 1.0.0-rc.1+1:** no executors are handed in, a hook
  /// demands nothing, `skinningPlacement` and `skinningRefusal` are gone (a
  /// hook nothing can place is reported by the frame, as any compute step
  /// is), and the result is the [Registration] itself, not a `Future` of
  /// it.
  Registration placeSkinningHook(SkinningHook hook) {
    final scope = _scope;
    final step = _SkinningStep(
      hook,
      _store.skinning,
      scope == null
          ? 'skinning ${_store.sequence}'
          : '${scope.manifest.namespace}.skinning_${_store.sequence}',
    );
    final entry = _checkedNode(step);
    final placed = hook is! HostSkinningHook && hook.kernels.isNotEmpty;
    final device = placed ? _drawing('placeSkinningHook') : null;
    final listed = _store.hooks.addSkinningHook(hook);
    _store.skinning.steps.add(step);
    final registration = _placeNode(
      entry,
      also: () {
        _store.skinning.steps.remove(step);
        listed.cancel();
      },
    );
    if (device != null) _follow(entry, prepareForThisFrame(step, device));
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
    final word = engineWordFor(name);
    for (final anchor in anchors) {
      if (anchor.name == name || anchor.name == word) return anchor;
    }
    return null;
  }

  /// Makes [anchor], a `RenderAnchor.after`, one of this renderer's: nodes
  /// may be placed at it from now on, and run right after the nodes at the
  /// anchor it follows.
  ///
  /// Throws a [NameTakenException] for an engine anchor and for a name
  /// another anchor has, and an [ArgumentError] for an anchor following
  /// one this renderer does not know — add that one first.
  Registration addAnchor(RenderAnchor anchor) {
    if (!anchor.isEngine) _inNamespace(anchor.name, 'the anchor');
    if (anchor.isEngine) {
      throw NameTakenException(
        anchor.name,
        what: 'the anchor',
        owner: 'the engine',
        detail: 'it is one of the engine\'s own anchors and needs no adding',
      );
    }
    if (anchorNamed(anchor.name) case final taken?) {
      throw NameTakenException(
        anchor.name,
        what: 'the anchor',
        owner: taken.isEngine
            ? 'the engine'
            : _store.anchors
                  .where((entry) => entry.anchor == taken)
                  .map((entry) => entry.owner)
                  .firstOrNull,
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
  ///
  /// Through the view of a plugin that touches only tooling, a
  /// [PluginException]: a game draws without that plugin. A contributor
  /// added twice is counted once, by the first who added it.
  T addContributor<T extends PassContributor>(T contributor) {
    _notTooling('a contributor to the engine\'s passes');
    if (_store.contributorOwners[contributor] != null) return contributor;
    _store.contributors.add(contributor);
    _store.contributorOwners[contributor] = _ContributorOwner(_scope);
    _scope?.track(Registration(() => _removeContributor(contributor)));
    return contributor;
  }

  /// Takes [contributor] out, and says whether it was there: an editor
  /// switching a feature off, a widget leaving the tree.
  ///
  /// **Only the caller's own.** The application's view takes out what the
  /// application added, and a plugin's view what that plugin added; a
  /// contributor somebody else added is a [PluginException] naming who, so
  /// one plugin cannot switch off another's particles.
  bool removeContributor(PassContributor contributor) {
    final owner = _store.contributorOwners[contributor];
    if (owner == null) return false;
    if (owner.id != _scope?.manifest.id) {
      throw PluginException(
        '$_owner took out a contributor ${owner.name} added: only the one '
        'who adds a contributor takes it out',
      );
    }
    return _removeContributor(contributor);
  }

  bool _removeContributor(PassContributor contributor) {
    _store.contributorOwners[contributor] = null;
    return _store.contributors.remove(contributor);
  }

  /// The steps taken with [provide], in the order they were taken.
  List<RenderStep> get provided => List<RenderStep>.unmodifiable(<RenderStep>[
    for (final entry in _store.provided) entry.step,
  ]);

  /// Who provides [step] — `plugin "flutter3d_post.bloom"`, or `the
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
  /// for a step this renderer does not know, and a [NameTakenException] for
  /// one already provided — naming who provides it.
  ///
  /// **A built-in step is the engine's to switch**, and a plugin from
  /// outside the engine takes it over only as a `RenderStepAddon` that
  /// declares it in `replaces`, with `PluginPermission.replace` in its
  /// manifest; through any other plugin's view, providing a built-in step
  /// is a [PluginException]. A step of a plugin's own, in its namespace, it
  /// provides freely.
  Registration provide(RenderStep step) {
    if (!step.isBuiltIn && !_store.steps.any((e) => e.step == step)) {
      throw ArgumentError.value(
        step.name,
        'step',
        'is not a step of this renderer. Add it with addStep first',
      );
    }
    if (_outside case final manifest?
        when step.isBuiltIn && !_takesOver(manifest, step.name)) {
      throw PluginException(
        'plugin "${manifest.id}" provided "${step.name}", a step the engine '
        'draws: a plugin from outside the engine takes one over only as a '
        'RenderStepAddon that declares it in `replaces`, with the '
        '"${PluginPermission.replace}" permission in its manifest',
      );
    }
    final owner = providerOf(step);
    if (owner != null) {
      throw NameTakenException(
        step.name,
        what: 'the provided step',
        owner: owner,
        detail: 'one plugin provides a step',
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
  /// share one. Throws a [NameTakenException] for a different slot under an
  /// id already taken.
  Registration addSettings(SettingsSlot<Object> slot) {
    // The engine's own slots are what an addon of the engine's family
    // provides the settings of; any other is the plugin's, in its namespace.
    if (!SettingsSlot.builtIn.contains(slot)) {
      _inNamespace(slot.id, 'the settings slot');
    }
    final taken = settingsNamed(slot.id);
    if (taken != null && !identical(taken, slot)) {
      throw NameTakenException(
        slot.id,
        what: 'the settings slot',
        detail: 'a different slot is added under this id',
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
  ///
  /// **A plugin from outside the engine adds stages in its namespace
  /// only.** Through its view, the library answers the stages named
  /// `<namespace>__…` — its lighting models' (`LightingModel.shaderNameOf`)
  /// and their vertex stages — and nothing else, so a stage the engine draws
  /// with (`Pbr`, `Unlit`, the shadow passes) is never shadowed by one that
  /// happens to share its name. A stage under another name it takes over
  /// only as a `RenderStepAddon` that declares it in `replacesStages`, with
  /// `PluginPermission.replace` in its manifest. The application's view and
  /// the engine's plugins replace any stage, as a layer does.
  Registration addMaterials(ShaderLibrary library) {
    _notTooling('stages');
    final added = switch (_outside) {
      final manifest? => _store.confined[library] ??= _ConfinedLibrary(
        library,
        manifest,
        this,
      ),
      null => library,
    };
    final renderer = _store.renderer!.._addMaterials(added);
    final registration = Registration(() => renderer._removeMaterials(added));
    _scope?.track(registration);
    return registration;
  }

  /// The registries that come with this one, so a plugin host handed
  /// `renderer.renderSteps` finds them too: the renderer's
  /// [LightingModels], the one entrance a plugin's lighting model comes in
  /// by (`host.registry<LightingModels>()`), its [LightTypes], its
  /// [RenderHooks], its [SceneBindings] and its [PipelineNodeKinds].
  @override
  Iterable<PluginRegistry> get companions => <PluginRegistry>[
    _store.lightingModels,
    _store.lightTypes,
    _store.hooks,
    _store.sceneBindings,
    _store.nodeKinds,
  ];

  /// Applies [document] to this renderer (D44): adds its anchors, and makes
  /// and places each node of its own through the [PipelineNodeKinds] its
  /// kind names, at its anchor, under its step, after and before what it
  /// says. Every registration it made goes when the result is cancelled.
  ///
  /// The engine's own nodes the document lists stand where the engine puts
  /// them and are not placed again; one this renderer does not have is
  /// refused, as is a kind nobody registered, an anchor or a step this
  /// renderer does not know. A refusal takes back what was already added.
  /// Through a plugin's view, every name is held to its namespace as
  /// [addNode] and [addAnchor] hold it. The steps the document switches off
  /// are a setting: [settingsFor].
  ///
  /// `RendererSteps.fromDocument` in D44's words: a pipeline written as data
  /// becomes the frame's.
  Registration fromDocument(PipelineDocument document) {
    final made = <Registration>[];
    void takeBack() {
      for (final registration in made.reversed) {
        registration.cancel();
      }
    }

    try {
      for (final anchor in document.anchors) {
        final follows =
            anchorNamed(anchor.after) ??
            (throw ArgumentError.value(
              anchor.after,
              'document',
              'anchor "${anchor.name}" follows an anchor this renderer does '
                  'not know',
            ));
        made.add(addAnchor(RenderAnchor.after(follows, anchor.name)));
      }
      for (final node in document.nodes) {
        if (node.engine) {
          if (!RenderSettings.passOrder.contains(node.name) &&
              !node.name.startsWith(RenderStep.reflectionProbes.passPrefix!)) {
            throw ArgumentError.value(
              node.name,
              'document',
              'is listed as one of the engine\'s passes, and this renderer '
                  'has none of that name',
            );
          }
          continue;
        }
        final kindName =
            node.kind ??
            (throw ArgumentError.value(
              node.name,
              'document',
              'names no kind, and is not one of the engine\'s passes',
            ));
        final kind =
            _store.nodeKinds.kindNamed(kindName) ??
            (throw ArgumentError.value(
              kindName,
              'document',
              'is the kind of node "${node.name}", and no plugin registered '
                  'it with PipelineNodeKinds',
            ));
        final at =
            anchorNamed(node.anchor) ??
            (throw ArgumentError.value(
              node.anchor,
              'document',
              'is where node "${node.name}" stands, and not an anchor of '
                  'this renderer',
            ));
        final stepName = node.step;
        final step = stepName == null
            ? null
            : named(stepName) ??
                  (throw ArgumentError.value(
                    stepName,
                    'document',
                    'is the step of node "${node.name}", and not one of this '
                        'renderer\'s',
                  ));
        final created = kind.create(PipelineNodeContext(node));
        _store.kindOf[created] = kind.name;
        made.add(
          addNode(
            created,
            at: at,
            step: step,
            after: node.after,
            before: node.before,
          ),
        );
      }
    } catch (_) {
      takeBack();
      rethrow;
    }
    return Registration(takeBack);
  }

  /// [settings] with [document]'s switched-off steps off, through
  /// [RenderSettings.without], the added steps included. Throws an
  /// [ArgumentError] for a step this renderer does not know.
  RenderSettings settingsFor(
    PipelineDocument document,
    RenderSettings settings,
  ) {
    if (document.stepsOff.isEmpty) return settings;
    return settings.without(<RenderStep>{
      for (final name in document.stepsOff)
        named(name) ??
            (throw ArgumentError.value(
              name,
              'document',
              'is switched off, and is not a step of this renderer',
            )),
    }, also: added);
  }

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
  final LightingModels lightingModels = LightingModels();
  final LightTypes lightTypes = LightTypes();
  final RenderHooks hooks = RenderHooks();
  final _SkinningState skinning = _SkinningState();

  /// The workloads in the frame ([RendererSteps.addWorkload]): while there
  /// are any, the scene reads what they write.
  final List<WorkloadStep> workloads = <WorkloadStep>[];

  final SceneBindings sceneBindings = SceneBindings();
  final PipelineNodeKinds nodeKinds = PipelineNodeKinds();

  /// The kind each node [RendererSteps.fromDocument] made was made by, for
  /// a document that describes the frame again.
  final Expando<String> kindOf = Expando<String>();
  final ContributorRegistry contributors = ContributorRegistry();

  /// Who added each contributor, which only they may take out again.
  final Expando<_ContributorOwner> contributorOwners =
      Expando<_ContributorOwner>();

  /// What each plugin from outside the engine declared it takes over, by
  /// plugin id: built-in step names and engine stage names, from its
  /// `RenderStepAddon.replaces` and `replacesStages`.
  final Map<String, Set<String>> takeovers = <String, Set<String>>{};

  /// The view of each library an outside plugin added, confined to its
  /// namespace and what it took over.
  final Expando<_ConfinedLibrary> confined = Expando<_ConfinedLibrary>();
  int sequence = 0;

  /// The placements still loading: the registrations' and the frame
  /// placer's. `RendererSteps.whenPlaced` waits on them.
  final Set<Future<void>> placing = <Future<void>>{};

  /// [node], taken out of the frame, disposed once no frame in flight can
  /// still be using what it holds — at once with no renderer.
  void disposeNode(FrameGraphNode node) {
    final owner = renderer;
    if (owner == null) {
      node.dispose();
    } else {
      owner._disposeNodeAfterFrame(node);
    }
  }

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

/// What a `RenderStepAddon` needs from [RendererSteps] to take over what
/// the engine draws, and nobody else. Not exported by `flutter3d_core.dart`.
extension RendererStepsTakeovers on RendererSteps {
  /// Declares that the plugin of this view takes over [steps], built-in
  /// render steps it then provides, and [stages], shader stages under the
  /// engine's names its libraries may answer, until the result is
  /// cancelled.
  ///
  /// The application's view and an engine plugin's need no declaration:
  /// nothing is recorded and the result does nothing. Through the view of a
  /// plugin from outside the engine, a [PluginException] unless its manifest
  /// carries `PluginPermission.replace`, and an [ArgumentError] for a step
  /// that is not built in, which needs taking over by nobody.
  Registration takeOver({
    Iterable<RenderStep> steps = const <RenderStep>[],
    Iterable<String> stages = const <String>[],
  }) {
    final manifest = _outside;
    if (manifest == null || (steps.isEmpty && stages.isEmpty)) {
      return Registration(() {});
    }
    if (!manifest.permissions.contains(PluginPermission.replace)) {
      throw PluginException(
        'plugin "${manifest.id}" takes over '
        '${<String>[for (final step in steps) step.name, ...stages].map((n) => '"$n"').join(', ')}, '
        'which the engine draws, without the "${PluginPermission.replace}" '
        'permission in its manifest',
      );
    }
    for (final step in steps) {
      if (step.isBuiltIn) continue;
      throw ArgumentError.value(
        step.name,
        'steps',
        'is not one of the engine\'s steps; a plugin provides a step of its '
            'own without taking it over',
      );
    }
    final names = <String>{for (final step in steps) step.name, ...stages};
    final held = _store.takeovers.putIfAbsent(manifest.id, () => <String>{})
      ..addAll(names);
    final registration = Registration(() {
      held.removeAll(names);
      if (held.isEmpty) _store.takeovers.remove(manifest.id);
    });
    _scope?.track(registration);
    return registration;
  }
}

/// Who added a contributor: a plugin's id, or null for the application.
final class _ContributorOwner {
  _ContributorOwner(PluginScope? scope) : id = scope?.manifest.id;

  final String? id;

  String get name => switch (id) {
    final String id => 'plugin "$id"',
    null => 'the application',
  };
}

/// A library an outside plugin added, answering only the stages in its
/// namespace and those it declared it takes over.
final class _ConfinedLibrary with ShaderLibrary {
  _ConfinedLibrary(this._library, this._manifest, this._steps);

  final ShaderLibrary _library;
  final PluginManifest _manifest;
  final RendererSteps _steps;

  @override
  ShaderHandle? operator [](String name) =>
      name.startsWith('${_manifest.namespace}__') ||
          _steps._takesOver(_manifest, name)
      ? _library[name]
      : null;
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

  /// What the node threw, once it threw: from then on it is quarantined,
  /// left out of every frame as `PassSkip.failed`. State of the entry, not
  /// of the node, so placing the node again lets it run.
  NodeFailure? get failure => _failure;
  NodeFailure? _failure;

  /// Quarantines the node for [error], thrown at [stack]; the first failure
  /// is the one kept.
  NodeFailure fail(Object error, StackTrace stack) => _failure ??= NodeFailure(
    node: node.name,
    owner: owner,
    plugin: scope?.manifest.id,
    error: error,
    stackTrace: stack,
  );

  int get rank => scope?.rank ?? -1;

  static int compare(_AnchoredNode a, _AnchoredNode b) {
    final byRank = a.rank.compareTo(b.rank);
    return byRank != 0 ? byRank : a.sequence.compareTo(b.sequence);
  }
}

/// An anchored node as this frame registers it: active only while its step
/// is on in this frame.
///
/// Everything else is the node's own, so the graph sees the pass the plugin
/// declared, and the name it reports is the node's.
final class _SteppedNode extends RenderNode {
  const _SteppedNode(this._node, this._step, this._context);

  final RenderNode _node;
  final RenderStep _step;
  final RenderStepContext _context;

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
  void setup(FrameGraphBuilder builder) => _node.setup(builder);

  @override
  bool get isActive => _step.isOn(_context) && _node.isActive;

  @override
  bool get isSupported => _node.isSupported;

  @override
  bool get isReady => _node.isReady;

  @override
  RenderAnchor get defaultAnchor => _node.defaultAnchor;

  @override
  ViewRuns get viewRuns => _node.viewRuns;

  @override
  void execute(RenderFrame frame) => _node.execute(frame);
}

/// Where a renderer's frames have placed the nodes that asked with
/// `FrameGraphBuilder.place`: the frame's placer, wired to the hardware
/// layer's placement (`placeComputeRequest`).
///
/// **The graph asks synchronously, the hardware answers later.** The first
/// compile that meets a request starts its placement and answers
/// [FramePlacer.pending]; once the placement settles the placer is a new
/// one ([placer] changes with every answer that arrives), so the graph,
/// which compiles again only when something it was asked changed, compiles
/// the node in.
final class _FramePlacements {
  _FramePlacements(this._renderer);

  final Renderer _renderer;
  final Map<String, _Placing> _byNode = <String, _Placing>{};
  int _answered = 0;

  /// The placer this frame's compile is handed.
  FramePlacer get placer => _ComputePlacer(this, _answered);

  Object? _answer(FramePlacementContext context) {
    final request = context.request;
    if (request is! ComputePlacementRequest) return null;
    final name = context.node.name;
    final known = _byNode[name];
    if (known != null && known.request == request) {
      return known.done ? known.answer : FramePlacer.pending;
    }
    final placing = _byNode[name] = _Placing(request);
    final store = _renderer.renderSteps._store;
    late final Future<void> settled;
    settled = placeComputeRequest(name, request, _renderer.device)
        .then<void>(
          (ComputeNodePlacement? placed) => placing.answer = placed,
          onError: (Object error, StackTrace stack) {
            // Not a refusal — the hardware layer turns those into null —
            // but a placement that broke: the node is quarantined as one
            // that threw is, naming whose it was.
            for (final entry in store.nodes) {
              if (entry.node.name == name) entry.fail(error, stack);
            }
          },
        )
        .whenComplete(() {
          placing.done = true;
          _answered++;
          store.placing.remove(settled);
        });
    store.placing.add(settled);
    return FramePlacer.pending;
  }
}

/// One node's placement as [_FramePlacements] keeps it.
final class _Placing {
  _Placing(this.request);

  final ComputePlacementRequest request;
  bool done = false;
  ComputeNodePlacement? answer;
}

/// The placer one compile is handed: equal to another while no placement
/// has settled between them, which is what lets the graph reuse a compile.
final class _ComputePlacer extends FramePlacer {
  const _ComputePlacer(this._placements, this._answered);

  final _FramePlacements _placements;
  final int _answered;

  @override
  Object? place(FramePlacementContext context) => _placements._answer(context);

  @override
  bool operator ==(Object other) =>
      other is _ComputePlacer &&
      identical(other._placements, _placements) &&
      other._answered == _answered;

  @override
  int get hashCode => Object.hash(identityHashCode(_placements), _answered);
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

  /// Every node in the order the graph registers them, with the anchor it
  /// stands at, whether it is one of the engine's passes, and its ordering
  /// constraints — what `Renderer.describePipeline` writes down.
  List<({RenderAnchor anchor, _Slotted slotted, bool engine})> described() =>
      <({RenderAnchor anchor, _Slotted slotted, bool engine})>[
        for (var i = 0; i < _slots.length; i++)
          for (final slotted in orderByConstraints<_Slotted>(
            _slots[i],
            nameOf: (s) => s.node.name,
            after: (s) => s.after,
            before: (s) => s.before,
            what: 'passes',
          ))
            (
              anchor: RenderAnchor.values[i ~/ 2],
              slotted: slotted,
              engine: i.isOdd,
            ),
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
