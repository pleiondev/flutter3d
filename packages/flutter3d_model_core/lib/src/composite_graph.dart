/// `pro-rn-03`: the composite chain a frame runs through, as a value a
/// panel can draw and a person can switch passes off in.
///
/// **A fixed chain, not a graph somebody wires.** Scene, ambient occlusion,
/// reflections, bloom, tonemap, look, output — in that order, always. A node
/// editor over a chain that cannot be rewired would be a lie about what the
/// renderer does, and the renderer does not take a graph: it takes a
/// [RenderSettings]. So what there is to decide is which of the middle
/// passes run and what each of them is set to, and [CompositeGraph] is those
/// two facts in one value.
///
/// **It reads from and writes to `RenderSettings` rather than replacing
/// it.** The settings object is what every renderer in this repository
/// already takes and what a project already stores; a second description of
/// the same frame would be a second thing to keep in step. [CompositeGraph
/// .of] is the read and [CompositeGraph.settings] is the write, and the pair
/// round-trips.
///
/// **Editing one pass dirties one branch.** A person dragging a bloom slider
/// has not changed the scene, the ambient occlusion or the reflections, and
/// a renderer that redrew all of them per frame of that drag would be one
/// nobody drags. [CompositeGraph.dirty] says which passes an edit reached —
/// bloom and everything after it, never anything before — which is the whole
/// of what `renderPost` is for.
library;

import 'package:flutter3d_core/flutter3d_core.dart'
    show
        AmbientOcclusionSettings,
        BloomSettings,
        LookSettings,
        ReflectionSettings,
        RenderSettings;

/// One pass of the chain.
///
/// A final class with const instances rather than an enum, the same choice
/// `BrushKind` makes: this package is published, and an eighth pass would be
/// a breaking change for every external `switch` written against an enum's
/// closed set.
final class CompositePass {
  const CompositePass._(this.name, this.at, {required this.fixed});

  /// What the pass is called, on a panel and in an argument.
  final String name;

  /// Where it runs in the chain, counting from zero. What decides which
  /// passes an edit dirties: everything at or after the one that changed.
  final int at;

  /// Whether it always runs. The scene and the output are not optional, and
  /// drawing them with a switch that does nothing would be worse than
  /// drawing them without one.
  final bool fixed;

  static const CompositePass scene = CompositePass._('scene', 0, fixed: true);
  static const CompositePass ambientOcclusion = CompositePass._(
    'ssao',
    1,
    fixed: false,
  );
  static const CompositePass reflections = CompositePass._(
    'reflections',
    2,
    fixed: false,
  );
  static const CompositePass bloom = CompositePass._('bloom', 3, fixed: false);
  static const CompositePass tonemap = CompositePass._(
    'tonemap',
    4,
    fixed: false,
  );
  static const CompositePass look = CompositePass._('look', 5, fixed: false);
  static const CompositePass output = CompositePass._('output', 6, fixed: true);

  /// The chain, in the order it runs.
  static const List<CompositePass> values = <CompositePass>[
    scene,
    ambientOcclusion,
    reflections,
    bloom,
    tonemap,
    look,
    output,
  ];

  /// The pass [name] names, or null.
  static CompositePass? named(String name) {
    for (final CompositePass pass in values) {
      if (pass.name == name) return pass;
    }
    return null;
  }

  @override
  String toString() => 'CompositePass.$name';
}

/// Which passes of the chain are on, and what an edit to one of them
/// reached.
final class CompositeGraph {
  const CompositeGraph({
    required this.enabled,
    this.dirty = const <CompositePass>{},
  });

  /// The chain as [settings] describes it.
  ///
  /// A pass is on where the setting behind it is: bloom by
  /// [BloomSettings.enabled], the look by whether it does anything at all —
  /// a look pass set to no contrast, no saturation shift and no temperature
  /// is a pass that costs a frame and changes nothing, so it reads as off.
  factory CompositeGraph.of(RenderSettings settings) => CompositeGraph(
    enabled: <CompositePass>{
      CompositePass.scene,
      if (settings.ambientOcclusion.enabled) CompositePass.ambientOcclusion,
      if (settings.reflections.enabled) CompositePass.reflections,
      if (settings.bloom.enabled) CompositePass.bloom,
      if (settings.tonemap) CompositePass.tonemap,
      if (_looks(settings.look)) CompositePass.look,
      CompositePass.output,
    },
  );

  /// Which passes run. The two fixed ones are always in it.
  final Set<CompositePass> enabled;

  /// Which passes the last edit reached — empty for a graph nobody has
  /// edited. See the library comment.
  final Set<CompositePass> dirty;

  bool isOn(CompositePass pass) => pass.fixed || enabled.contains(pass);

  /// This chain written back into [settings].
  ///
  /// **Only the switches, never the numbers.** A pass switched off keeps
  /// whatever it was set to, so switching it on again brings back the bloom
  /// somebody had tuned rather than a default — which is what every
  /// renderer's own pass list does and what a checkbox that threw the
  /// settings away would not.
  RenderSettings settings(RenderSettings from) => from.copyWith(
    // `AmbientOcclusionSettings` and `ReflectionSettings` have no
    // `copyWith` of their own in `flutter3d_core`, so the switch is written
    // out beside the numbers it keeps — which is the whole of "only the
    // switches, never the numbers" said in code.
    ambientOcclusion: AmbientOcclusionSettings(
      enabled: isOn(CompositePass.ambientOcclusion),
      radius: from.ambientOcclusion.radius,
      samples: from.ambientOcclusion.samples,
      strength: from.ambientOcclusion.strength,
      bias: from.ambientOcclusion.bias,
    ),
    reflections: ReflectionSettings(
      enabled: isOn(CompositePass.reflections),
      steps: from.reflections.steps,
      stride: from.reflections.stride,
      thickness: from.reflections.thickness,
      intensity: from.reflections.intensity,
      debugOnly: from.reflections.debugOnly,
    ),
    bloom: from.bloom.copyWith(enabled: isOn(CompositePass.bloom)),
    tonemap: isOn(CompositePass.tonemap),
  );

  /// This chain with [pass] switched on or off, and the branch that changed
  /// marked.
  CompositeGraph withPass(CompositePass pass, {required bool on}) {
    if (pass.fixed) return this;
    return CompositeGraph(
      enabled: <CompositePass>{
        for (final CompositePass each in enabled)
          if (each != pass) each,
        if (on) pass,
      },
      dirty: <CompositePass>{...dirty, ...branchFrom(pass)},
    );
  }

  /// This chain, unchanged, with [pass]'s own branch marked — what an edit
  /// to a pass's *numbers* leaves behind.
  ///
  /// `pro-rn-03`'s own `renderPost`: dragging a bloom slider changes nothing
  /// about which passes run and everything about what has to be redrawn.
  ///
  /// **Added to whatever was already dirty rather than replacing it.** One
  /// call to [renderPost] can edit bloom and the look together, and the
  /// branch that has to be redrawn is the earlier of the two — replacing
  /// would leave the bloom out and a renderer would skip the pass it was
  /// asked to change.
  CompositeGraph touched(CompositePass pass) => CompositeGraph(
    enabled: enabled,
    dirty: <CompositePass>{...dirty, ...branchFrom(pass)},
  );

  /// [pass] and every pass after it — what an edit to it reaches.
  ///
  /// **After, never before.** A bloom setting cannot change the scene that
  /// was drawn before the bloom ran; a renderer that redrew the scene for it
  /// would spend a frame's worth of geometry on a slider drag.
  static Set<CompositePass> branchFrom(CompositePass pass) => <CompositePass>{
    for (final CompositePass each in CompositePass.values)
      if (each.at >= pass.at) each,
  };

  /// Whether a look pass would do anything.
  static bool _looks(LookSettings look) =>
      look.contrast != 1.0 || look.saturation != 1.0 || look.temperature != 0.0;

  @override
  String toString() =>
      'CompositeGraph(${<String>[for (final CompositePass pass in CompositePass.values)
        if (isOn(pass)) pass.name].join(' → ')})';
}

/// Edits one post pass's own numbers and says what that reached —
/// `pro-rn-03`'s own `renderPost`.
///
/// **The settings and the dirty branch come back together**, because a
/// caller that got one without the other would have to work the other out,
/// and working out which passes a bloom edit reached is exactly the thing
/// this file exists to answer once.
({RenderSettings settings, CompositeGraph graph}) renderPost(
  RenderSettings from,
  CompositeGraph graph, {
  BloomSettings? bloom,
  LookSettings? look,
  bool? tonemap,
}) {
  var settings = from;
  var touched = graph;
  if (bloom != null) {
    settings = settings.copyWith(bloom: bloom);
    touched = touched.touched(CompositePass.bloom);
  }
  if (tonemap != null) {
    settings = settings.copyWith(tonemap: tonemap);
    touched = touched.touched(CompositePass.tonemap);
  }
  if (look != null) {
    settings = settings.copyWith(look: look);
    touched = touched.touched(CompositePass.look);
  }
  return (settings: settings, graph: touched);
}
