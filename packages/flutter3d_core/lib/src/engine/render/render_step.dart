/// Every step of a frame that can be switched off, as one vocabulary.
///
/// **The switches already existed; what was missing was a way to name them
/// together.** Bloom is `bloom.enabled`, the occlusion is
/// `ambientOcclusion.enabled`, the tone curve is `tonemap`, the distance fog
/// is a density of nought, a lens is a distortion of nought, and a caller who
/// wanted "this frame without the post chain" had to know thirty of those by
/// heart and get each one right. [RenderStep] is a list of the steps with the
/// switch each one already has, and `RenderSettings.without` throws the
/// switches for any set of them at once.
///
/// **It is not a second way to switch a pass off.** A step off is its own
/// setting off, written by the same `copyWith` a caller would have written;
/// a frame from `without({RenderStep.bloom})` is the frame from
/// `bloom: BloomSettings(enabled: false)`, and a test holds the two to the
/// same passes. The one thing recorded beside the settings is which steps
/// were asked off, so `FrameResult.skipped` can say so — see
/// [PassSkip.switchedOff].
///
/// **And it is the only one, since 1.0.** `RenderSettings.disabledPasses`,
/// which suppressed a node by name whatever its settings said, went: two
/// ways to switch a pass off reported it two ways, and a name typed into a
/// set was a key space beside this typed one. A pass is switched off by the
/// step that owns it ([ownsPass]); a plugin's pass by the step it was added
/// with.
library;

import '../scene/occlusion/occlusion_test.dart';
import 'frame_graph.dart' show PassSkip, SkippedPass;
import 'render_settings.dart';

/// One step of the frame that can be switched off — the passes before the
/// scene, the scene's own extras, and the post chain.
///
/// **A final class with const instances rather than an enum**, which
/// `tool/structure.dart` asks of a published package: the list will grow,
/// and a step added should not break an exhaustive `switch` somebody wrote.
///
/// Each step knows three things:
///
///  * the passes it owns — the frame-graph nodes whose `isActive` its switch
///    decides, which is what disappears from `FrameResult.passes` when it is
///    off. Some steps own none: the tone curve, the grade, the lens's bend,
///    the vignette and grain, the distance fog and the caustics are all
///    arithmetic inside a pass that runs anyway;
///  * how to switch itself off, by changing its own setting;
///  * which other steps it needs ([needs]). Switching off a step another
///    needs switches that one off too: `without({bloom})` is also without
///    the lens flare, which is drawn from the glow, and the flare is
///    reported switched off beside it. Nothing is refused.
///
/// **What is not a step, and why.** The scene itself and the composite are
/// the frame. The surface buffer is not a switch at all: the scene writes it
/// exactly when some surviving pass reads it, so switching off its readers
/// is what removes it. The velocity passes are shared by the temporal
/// resolve and the motion blur and run while either does, and the object
/// ids answer picks already taken. The transparent half and its colour copy
/// run only when the scene holds glass or a reader of its depth, which is
/// content; they are steps all the same ([transparent], [sceneColorCopy]),
/// switched by [RenderSettings.stepsOff] alone, so a frame can be drawn the
/// way it was before the scene was split.
///
/// ## A step of one's own
///
/// **The set is open: a plugin defines a step with the public constructor**
/// and registers it with `RendererSteps.addStep`, and from then on it is a
/// step like the thirty built in. It has a name the frame reports it under,
/// the passes it owns, the steps it [needs], and a switch, and it gets the
/// same treatment: [RenderSettings.without] and [RenderSettings.only] switch
/// it, switching off a step it needs switches it off too, and
/// `FrameResult.skipped` names it with [PassSkip.switchedOff].
///
/// Its switch is one of two things:
///
///  * **nothing given:** the step is switched by being listed in
///    [RenderSettings.stepsOff] — off once `without` names it, on again
///    once a `copyWith` takes it out of the set. The step needs no field of
///    [RenderSettings], which it could not add;
///  * **`switchOff` and `isOn` given:** the step has a setting of its own
///    somewhere the plugin keeps it, and these two read and write it, as the
///    built-in steps' switches do.
///
/// Either way an added step is on only while every step it [needs] is on,
/// so its own switch need not repeat theirs.
final class RenderStep {
  const RenderStep._(
    this.name,
    this._off,
    this._isOn, {
    this.passes = const <String>{},
    this.passPrefix,
    this.needs = const <RenderStep>{},
  }) : _builtIn = true;

  /// A step of a plugin's, or an application's — see "A step of one's own"
  /// above.
  ///
  /// [name] is what the frame reports it under and must differ from every
  /// other step's; `RendererSteps.addStep` refuses a second step of one
  /// name. [passes] and [passPrefix] are the frame-graph nodes it owns: a
  /// node registered with `RendererSteps.addNode(…, step: this)` is owned
  /// whether or not it is listed. [needs] are the steps it cannot run
  /// without, built in or added. Give both [switchOff] and [isOn], or
  /// neither.
  const RenderStep(
    this.name, {
    this.passes = const <String>{},
    this.passPrefix,
    this.needs = const <RenderStep>{},
    RenderSettings Function(RenderSettings settings)? switchOff,
    bool Function(RenderSettings settings)? isOn,
  }) : assert(
         (switchOff == null) == (isOn == null),
         'a step with a setting of its own gives both switchOff and isOn',
       ),
       _off = switchOff,
       _isOn = isOn,
       _builtIn = false;

  /// What the step is called in `FrameResult.skipped` when it is off.
  ///
  /// The same string as the pass it owns where it owns one pass of that name
  /// — `bloom`, `decals` — so a reader holding either finds the other.
  final String name;

  /// The frame-graph nodes this step's switch decides, by name.
  ///
  /// A pass may be owned by two steps: `antialias` does the edge smoothing
  /// and the sharpening both, and runs while either has anything to do.
  final Set<String> passes;

  /// The passes whose names carry an index — `reflection probe 3` — owned by
  /// prefix, since their count belongs to the scene.
  final String? passPrefix;

  /// Steps this one cannot run without. Switching any of them off switches
  /// this one off too.
  final Set<RenderStep> needs;

  final RenderSettings Function(RenderSettings)? _off;
  final bool Function(RenderSettings)? _isOn;
  final bool _builtIn;

  /// Whether this is one of the engine's own steps, in [values], rather than
  /// one a plugin or an application defined.
  bool get isBuiltIn => _builtIn;

  /// [settings] with this step's own switch off and everything else as it
  /// was. A built-in step, or an added one with a setting of its own, leaves
  /// [RenderSettings.stepsOff] alone: that is [RenderSettings.without]'s to
  /// keep. An added step with no setting is switched by that set, so for it
  /// this adds the step to it.
  RenderSettings switchOff(RenderSettings settings) => switch (_off) {
    final off? => off(settings),
    null => settings.copyWith(
      stepsOff: <RenderStep>{...settings.stepsOff, this},
    ),
  };

  /// Whether this step's own switch is on in [settings].
  ///
  /// About the switch alone. A step whose switch is on may still draw
  /// nothing — reflection probes with no probe in the scene, light shafts
  /// with no sun — and that is the frame's business, reported by the passes.
  ///
  /// An added step is on only while every step it [needs] is on as well; a
  /// built-in step's own switch already says so.
  bool isOn(RenderSettings settings) {
    final own = switch (_isOn) {
      final on? => on(settings),
      null => !settings.stepsOff.contains(this),
    };
    return _builtIn ? own : own && needs.every((need) => need.isOn(settings));
  }

  /// Whether the pass called [pass] is one of this step's.
  bool ownsPass(String pass) =>
      passes.contains(pass) ||
      (passPrefix != null && pass.startsWith(passPrefix!));

  @override
  String toString() => 'RenderStep($name)';

  // -- Before the scene ----------------------------------------------------

  /// Every shadow map: the directional cascades, both cube atlases and the
  /// blurred moments the `evsm` filter reads. Off is `shadows.enabled`
  /// false, and every lit pass then shades unshadowed.
  static const RenderStep shadows = RenderStep._(
    'shadows',
    _shadowsOff,
    _shadowsOn,
    passes: <String>{
      'point shadows (static)',
      'point shadows',
      'directional shadows',
      'shadow moments',
    },
  );

  /// Light through glass followed as photons into the directional map —
  /// `ShadowSettings.caustics`. Drawn inside the shadow pass, so it owns no
  /// pass of its own, and needs [shadows].
  static const RenderStep caustics = RenderStep._(
    'caustics',
    _causticsOff,
    _causticsOn,
    needs: <RenderStep>{shadows},
  );

  /// The scene's reflection probes, recaptured. Off is
  /// `RenderSettings.reflectionProbes` false: the probes keep the last
  /// picture they took and the scene goes on sampling it.
  static const RenderStep reflectionProbes = RenderStep._(
    'reflection probes',
    _probesOff,
    _probesOn,
    passPrefix: 'reflection probe ',
  );

  /// The irradiance field's probes updated on the GPU. Off is
  /// `RenderSettings.irradianceUpdates` false: the field keeps the light it
  /// has gathered and the scene goes on reading it.
  static const RenderStep irradianceUpdate = RenderStep._(
    'irradiance update',
    _irradianceOff,
    _irradianceOn,
    passes: <String>{'irradiance update'},
  );

  /// Every `RenderTexture` drawn through its own camera. Off is
  /// `RenderSettings.renderTextures` false: each texture keeps its last
  /// picture.
  static const RenderStep renderTextures = RenderStep._(
    'render textures',
    _renderTexturesOff,
    _renderTexturesOn,
    passes: <String>{'render textures'},
  );

  /// The mirrored pictures behind each planar reflector. Off is
  /// `planarReflections.enabled` false.
  static const RenderStep planarReflections = RenderStep._(
    'planar reflections',
    _planarOff,
    _planarOn,
    passes: <String>{'planar reflections'},
  );

  // -- The scene's own extras ----------------------------------------------

  /// Decals painted onto the opaque half. Off is `decals.enabled` false.
  static const RenderStep decals = RenderStep._(
    'decals',
    _decalsOff,
    _decalsOn,
    passes: <String>{'decals'},
  );

  /// The scene's second half — `M3`: on a frame that holds glass, a
  /// contributor that reads the scene's depth, a material that reads the
  /// scene behind it, or decals, the transmissive and transparent draws and
  /// the contributors are drawn in a pass of their own after the opaque
  /// half, over what it stored.
  ///
  /// **Off, the frame is drawn in one pass**, as it was before the split:
  /// glass reads the environment rather than the scene behind it, and a
  /// contributor that asked for the scene's depth is handed none and draws
  /// as it would without it. The split follows content rather than a
  /// setting, so this step has no field of [RenderSettings]: it is off while
  /// [RenderSettings.stepsOff] holds it, which [RenderSettings.without]
  /// writes and a `copyWith(stepsOff: …)` that leaves it out undoes.
  static const RenderStep transparent = RenderStep._(
    'transparent',
    _transparentOff,
    _transparentOn,
    passes: <String>{'transparent'},
  );

  /// The copy of the opaque half the glass reads the scene behind it from,
  /// at six sizes. Off keeps the split, and the glass in the second half
  /// reads the environment. Needs [transparent], its only reader; switched,
  /// like it, by [RenderSettings.stepsOff].
  static const RenderStep sceneColorCopy = RenderStep._(
    'scene colour copy',
    _copyOff,
    _copyOn,
    passes: <String>{'scene colour copy'},
    needs: <RenderStep>{transparent},
  );

  /// The distance and height fog the lit stages mix in. Off is a density of
  /// nought; arithmetic inside the scene pass, so no pass of its own.
  static const RenderStep fog = RenderStep._('fog', _fogOff, _fogOn);

  /// The occlusion read back for culling by the next frame — `C3`, the
  /// depth pyramid. Off sets `occlusion` from `OcclusionMode.hiZ` to
  /// `OcclusionMode.none`; a software occlusion test, which needs no
  /// pyramid, is left alone.
  static const RenderStep hiZOcclusion = RenderStep._(
    'hi-z occlusion',
    _hiZOff,
    _hiZOn,
    passes: <String>{'depth pyramid'},
  );

  // -- Light and shadow on the lit picture ---------------------------------

  /// Screen-space reflections. Off is `reflections.enabled` false.
  static const RenderStep reflections = RenderStep._(
    'reflections',
    _reflectionsOff,
    _reflectionsOn,
    passes: <String>{'reflections'},
  );

  /// Ambient occlusion and its blur, whichever method. Off is
  /// `ambientOcclusion.enabled` false.
  static const RenderStep ambientOcclusion = RenderStep._(
    'ambient occlusion',
    _aoOff,
    _aoOn,
    passes: <String>{'ssao', 'ssao blur'},
  );

  /// The short march towards the sun at every pixel, and the resolve that
  /// averages its dither. Off is `contactShadows.enabled` false.
  static const RenderStep contactShadows = RenderStep._(
    'contact shadows',
    _contactOff,
    _contactOn,
    passes: <String>{'contact shadows', 'contact shadow resolve'},
  );

  /// The fog marched through the light. Off is `volumetricFog.enabled`
  /// false.
  static const RenderStep volumetricFog = RenderStep._(
    'volumetric fog',
    _volumetricOff,
    _volumetricOn,
    passes: <String>{'volumetric fog'},
  );

  /// Shafts of sunlight through the air. Off is `lightShafts.enabled` false.
  static const RenderStep lightShafts = RenderStep._(
    'light shafts',
    _shaftsOff,
    _shaftsOn,
    passes: <String>{'light shafts'},
  );

  // -- The lens and the sensor ---------------------------------------------

  /// Off is `depthOfField.enabled` false.
  static const RenderStep depthOfField = RenderStep._(
    'depth of field',
    _dofOff,
    _dofOn,
    passes: <String>{'depth of field'},
  );

  /// Off is `motionBlur.enabled` false. The velocity passes stay while the
  /// temporal resolve still reads them.
  static const RenderStep motionBlur = RenderStep._(
    'motion blur',
    _motionOff,
    _motionOn,
    passes: <String>{'motion blur'},
  );

  /// The jittered frames blended across time, with the reactive mask that
  /// guides it and the two histories it keeps for the noisy effects. Off is
  /// `antiAlias.temporal.enabled` false. The velocity passes stay while the
  /// motion blur still reads them.
  ///
  /// The spatial upscale only runs without it, so switching this off is
  /// what lets an upscale that was asked for appear — the one step whose
  /// absence adds a pass.
  static const RenderStep temporalAntiAliasing = RenderStep._(
    'temporal anti-aliasing',
    _temporalOff,
    _temporalOn,
    passes: <String>{
      'temporal resolve',
      'reactive mask',
      'ssao history',
      'contact shadow history',
    },
  );

  /// The meter that adapts the exposure. Off is `autoExposure.enabled`
  /// false; the composite then uses `RenderSettings.exposure`.
  static const RenderStep autoExposure = RenderStep._(
    'auto exposure',
    _autoExposureOff,
    _autoExposureOn,
    passes: <String>{'luminance'},
  );

  /// Off is `localExposure.enabled` false.
  static const RenderStep localExposure = RenderStep._(
    'local exposure',
    _localExposureOff,
    _localExposureOn,
    passes: <String>{'local exposure'},
  );

  /// Off is `bloom.enabled` false.
  static const RenderStep bloom = RenderStep._(
    'bloom',
    _bloomOff,
    _bloomOn,
    passes: <String>{'bloom'},
  );

  /// Ghosts and a halo drawn from the glow, so it needs [bloom]. Off is
  /// `bloom.lensFlare.enabled` false.
  static const RenderStep lensFlare = RenderStep._(
    'lens flare',
    _flareOff,
    _flareOn,
    passes: <String>{'lens flare'},
    needs: <RenderStep>{bloom},
  );

  // -- Inside the composite ------------------------------------------------

  /// The tone curve, and a display transform in its place. Off is
  /// `tonemap` false: the composite clamps instead.
  static const RenderStep tonemap = RenderStep._(
    'tonemap',
    _tonemapOff,
    _tonemapOn,
  );

  /// The grade: contrast, saturation, temperature, lift, gamma, gain, white
  /// balance, tint and the colour table. Off sets each to its neutral value
  /// and leaves the lens, the film and the dither as they were.
  static const RenderStep colorGrade = RenderStep._(
    'colour grade',
    _gradeOff,
    _gradeOn,
  );

  /// The lens's bend and its colour fringes — `look.distortion` and
  /// `look.chromaticAberration`, both nought when off.
  static const RenderStep lensDistortion = RenderStep._(
    'lens distortion',
    _distortionOff,
    _distortionOn,
  );

  /// The film: `look.vignette` and `look.grain`, both nought when off.
  static const RenderStep vignetteAndGrain = RenderStep._(
    'vignette and grain',
    _filmOff,
    _filmOn,
  );

  // -- After the composite -------------------------------------------------

  /// The finished picture brought up from a reduced render scale. Off is
  /// `spatialUpscale.enabled` false, and the frame is stretched by the
  /// present instead.
  static const RenderStep spatialUpscale = RenderStep._(
    'spatial upscale',
    _upscaleOff,
    _upscaleOn,
    passes: <String>{'spatial upscale'},
  );

  /// FXAA or SMAA on the finished picture. Off is `antiAlias.enabled` false.
  ///
  /// Shares the `antialias` pass with [sharpening], which is done in the
  /// same draw, so the pass runs while either has something to do.
  /// Multisampling is not here: it is the device's sample count, chosen when
  /// the renderer is made, rather than a step of the frame.
  static const RenderStep edgeSmoothing = RenderStep._(
    'edge smoothing',
    _edgesOff,
    _edgesOn,
    passes: <String>{'antialias'},
  );

  /// Contrast-adaptive sharpening, after the edge smoothing, the temporal
  /// resolve or the upscale, whichever asked for it. Off sets all three
  /// strengths to nought.
  static const RenderStep sharpening = RenderStep._(
    'sharpening',
    _sharpenOff,
    _sharpenOn,
    passes: <String>{'antialias'},
  );

  /// The high-contrast look and the outlines it rings marked nodes in. Off
  /// is `highContrast.enabled` false.
  static const RenderStep highContrast = RenderStep._(
    'high contrast',
    _contrastOff,
    _contrastOn,
    passes: <String>{'outline mask', 'high contrast'},
  );

  /// The editor's normals, clay, outline and curvature views. Off is
  /// `ViewportShading.off`.
  static const RenderStep viewportShading = RenderStep._(
    'viewport shading',
    _shadingOff,
    _shadingOn,
    passes: <String>{'viewport shading'},
  );

  /// Every step, in the order the frame meets them.
  static const List<RenderStep> values = <RenderStep>[
    shadows,
    caustics,
    reflectionProbes,
    irradianceUpdate,
    renderTextures,
    planarReflections,
    decals,
    transparent,
    sceneColorCopy,
    fog,
    hiZOcclusion,
    reflections,
    ambientOcclusion,
    contactShadows,
    volumetricFog,
    lightShafts,
    depthOfField,
    motionBlur,
    temporalAntiAliasing,
    autoExposure,
    localExposure,
    bloom,
    lensFlare,
    tonemap,
    colorGrade,
    lensDistortion,
    vignetteAndGrain,
    spatialUpscale,
    edgeSmoothing,
    sharpening,
    highContrast,
    viewportShading,
  ];

  /// [steps] and every step that needs one of them, transitively — what
  /// switching [steps] off actually switches off.
  ///
  /// The dependants are looked for among the built-in steps and [also]: an
  /// added step is known to the renderer that registered it, not to this
  /// class, so a caller who wants plugins' steps taken down with the ones
  /// they need passes them — `RendererSteps.added`.
  static Set<RenderStep> withDependants(
    Set<RenderStep> steps, {
    Iterable<RenderStep> also = const <RenderStep>[],
  }) {
    final among = <RenderStep>[
      ...values,
      for (final step in also)
        if (!step.isBuiltIn) step,
    ];
    final closed = <RenderStep>{...steps};
    for (var grew = true; grew;) {
      grew = false;
      for (final step in among) {
        if (closed.contains(step)) continue;
        if (!step.needs.any(closed.contains)) continue;
        closed.add(step);
        grew = true;
      }
    }
    return closed;
  }

  /// The steps [settings] reports as switched off: the ones
  /// [RenderSettings.without] recorded whose switch is still off
  /// ([RenderSettings.switchedOffSteps]), and every step of [also] that
  /// needs one of those, transitively.
  ///
  /// The second half is the take-down for steps the settings never heard
  /// of. `without({RenderStep.bloom})` cannot record a plugin's glow step it
  /// was not told about, and that step is off all the same — it needs the
  /// bloom — so the frame names it beside the bloom, as it names the lens
  /// flare. With no [also] this is [RenderSettings.switchedOffSteps].
  static Set<RenderStep> switchedOffIn(
    RenderSettings settings, {
    Iterable<RenderStep> also = const <RenderStep>[],
  }) {
    final off = settings.switchedOffSteps;
    if (off.isEmpty || also.isEmpty) return off;
    final added = <RenderStep>[
      for (final step in also)
        if (!step.isBuiltIn) step,
    ];
    for (var grew = true; grew;) {
      grew = false;
      for (final step in added) {
        if (off.contains(step) || !step.needs.any(off.contains)) continue;
        off.add(step);
        grew = true;
      }
    }
    return off;
  }

  /// [steps] and every step one of them needs, transitively — what has to
  /// stay on for [steps] to run.
  static Set<RenderStep> withPrerequisites(Set<RenderStep> steps) {
    final closed = <RenderStep>{...steps};
    final pending = <RenderStep>[...steps];
    while (pending.isNotEmpty) {
      for (final need in pending.removeLast().needs) {
        if (closed.add(need)) pending.add(need);
      }
    }
    return closed;
  }

  /// [nodeSkips] — the compiled graph's — with every step [settings]
  /// switched off named in it.
  ///
  /// A step whose name a skipped pass already carries is that entry, so a
  /// name is never listed twice. A step recorded as off whose switch has
  /// since been turned back on through `copyWith` is not listed: the
  /// switch is what decides the frame, and the list reports the frame.
  ///
  /// The built-in steps come first, in the order of [values]; then the
  /// added ones — those [settings] recorded, and those of [also] taken down
  /// with a step they need (see [switchedOffIn]).
  static List<SkippedPass> reportSkips(
    RenderSettings settings,
    List<SkippedPass> nodeSkips, {
    Iterable<RenderStep> also = const <RenderStep>[],
  }) {
    final off = switchedOffIn(settings, also: also);
    if (off.isEmpty) return nodeSkips;
    final named = <String>{for (final skip in nodeSkips) skip.name};
    return List<SkippedPass>.unmodifiable(<SkippedPass>[
      ...nodeSkips,
      for (final step in <RenderStep>[
        ...values,
        for (final step in off)
          if (!step.isBuiltIn) step,
      ])
        if (off.contains(step) && !named.contains(step.name))
          (name: step.name, reason: PassSkip.switchedOff),
    ]);
  }
}

// The switches, one pair per step. Top-level so each `const` instance above
// can hold a tear-off of them.

RenderSettings _shadowsOff(RenderSettings s) =>
    s.copyWith(shadows: s.shadows.copyWith(enabled: false));
bool _shadowsOn(RenderSettings s) =>
    s.shadows.enabled && s.shadows.strength > 0.0;

RenderSettings _causticsOff(RenderSettings s) =>
    s.copyWith(shadows: s.shadows.copyWith(caustics: false));
bool _causticsOn(RenderSettings s) => _shadowsOn(s) && s.shadows.caustics;

RenderSettings _probesOff(RenderSettings s) =>
    s.copyWith(reflectionProbes: false);
bool _probesOn(RenderSettings s) => s.reflectionProbes;

RenderSettings _irradianceOff(RenderSettings s) =>
    s.copyWith(irradianceUpdates: false);
bool _irradianceOn(RenderSettings s) => s.irradianceUpdates;

RenderSettings _renderTexturesOff(RenderSettings s) =>
    s.copyWith(renderTextures: false);
bool _renderTexturesOn(RenderSettings s) => s.renderTextures;

RenderSettings _planarOff(RenderSettings s) =>
    s.copyWith(planarReflections: s.planarReflections.copyWith(enabled: false));
bool _planarOn(RenderSettings s) => s.planarReflections.enabled;

RenderSettings _decalsOff(RenderSettings s) =>
    s.copyWith(decals: s.decals.copyWith(enabled: false));
bool _decalsOn(RenderSettings s) => s.decals.enabled;

// The two halves of a split scene have no setting of their own: the record
// of steps switched off is their switch.
RenderSettings _transparentOff(RenderSettings s) =>
    s.copyWith(stepsOff: <RenderStep>{...s.stepsOff, RenderStep.transparent});
bool _transparentOn(RenderSettings s) =>
    !s.stepsOff.contains(RenderStep.transparent);

RenderSettings _copyOff(RenderSettings s) => s.copyWith(
  stepsOff: <RenderStep>{...s.stepsOff, RenderStep.sceneColorCopy},
);
bool _copyOn(RenderSettings s) =>
    _transparentOn(s) && !s.stepsOff.contains(RenderStep.sceneColorCopy);

RenderSettings _fogOff(RenderSettings s) =>
    s.copyWith(fog: s.fog.copyWith(density: 0.0));
bool _fogOn(RenderSettings s) => s.fog.enabled;

RenderSettings _hiZOff(RenderSettings s) => s.occlusion == OcclusionMode.hiZ
    ? s.copyWith(occlusion: OcclusionMode.none)
    : s;
bool _hiZOn(RenderSettings s) => s.occlusion == OcclusionMode.hiZ;

RenderSettings _reflectionsOff(RenderSettings s) =>
    s.copyWith(reflections: s.reflections.copyWith(enabled: false));
bool _reflectionsOn(RenderSettings s) => s.reflections.enabled;

RenderSettings _aoOff(RenderSettings s) =>
    s.copyWith(ambientOcclusion: s.ambientOcclusion.copyWith(enabled: false));
bool _aoOn(RenderSettings s) =>
    s.ambientOcclusion.enabled && s.ambientOcclusion.strength > 0.0;

RenderSettings _contactOff(RenderSettings s) =>
    s.copyWith(contactShadows: s.contactShadows.copyWith(enabled: false));
bool _contactOn(RenderSettings s) => s.contactShadows.enabled;

RenderSettings _volumetricOff(RenderSettings s) =>
    s.copyWith(volumetricFog: s.volumetricFog.copyWith(enabled: false));
bool _volumetricOn(RenderSettings s) => s.volumetricFog.enabled;

RenderSettings _shaftsOff(RenderSettings s) =>
    s.copyWith(lightShafts: s.lightShafts.copyWith(enabled: false));
bool _shaftsOn(RenderSettings s) => s.lightShafts.enabled;

RenderSettings _dofOff(RenderSettings s) =>
    s.copyWith(depthOfField: s.depthOfField.copyWith(enabled: false));
bool _dofOn(RenderSettings s) => s.depthOfField.enabled;

RenderSettings _motionOff(RenderSettings s) =>
    s.copyWith(motionBlur: s.motionBlur.copyWith(enabled: false));
bool _motionOn(RenderSettings s) => s.motionBlur.enabled;

RenderSettings _temporalOff(RenderSettings s) => s.copyWith(
  antiAlias: s.antiAlias.copyWith(
    temporal: s.antiAlias.temporal.copyWith(enabled: false),
  ),
);
bool _temporalOn(RenderSettings s) => s.antiAlias.temporal.enabled;

RenderSettings _autoExposureOff(RenderSettings s) =>
    s.copyWith(autoExposure: s.autoExposure.copyWith(enabled: false));
bool _autoExposureOn(RenderSettings s) => s.autoExposure.enabled;

RenderSettings _localExposureOff(RenderSettings s) => s.copyWith(
  localExposure: LocalExposureSettings(
    strength: s.localExposure.strength,
    shadowStops: s.localExposure.shadowStops,
    highlightStops: s.localExposure.highlightStops,
  ),
);
bool _localExposureOn(RenderSettings s) => s.localExposure.enabled;

RenderSettings _bloomOff(RenderSettings s) =>
    s.copyWith(bloom: s.bloom.copyWith(enabled: false));
bool _bloomOn(RenderSettings s) => s.bloom.enabled && s.bloom.intensity > 0.0;

RenderSettings _flareOff(RenderSettings s) => s.copyWith(
  bloom: s.bloom.copyWith(
    lensFlare: s.bloom.lensFlare.copyWith(enabled: false),
  ),
);
bool _flareOn(RenderSettings s) => _bloomOn(s) && s.bloom.lensFlare.enabled;

RenderSettings _tonemapOff(RenderSettings s) => s.copyWith(tonemap: false);
bool _tonemapOn(RenderSettings s) => s.tonemap;

RenderSettings _gradeOff(RenderSettings s) => s.copyWith(
  look: LookSettings(
    vignette: s.look.vignette,
    vignetteRoundness: s.look.vignetteRoundness,
    grain: s.look.grain,
    chromaticAberration: s.look.chromaticAberration,
    distortion: s.look.distortion,
    dither: s.look.dither,
    displayTransform: s.look.displayTransform,
  ),
);
// The grade's fields alone, asked whether they change anything.
bool _gradeOn(RenderSettings s) => !LookSettings(
  contrast: s.look.contrast,
  saturation: s.look.saturation,
  temperature: s.look.temperature,
  lift: s.look.lift,
  gamma: s.look.gamma,
  gain: s.look.gain,
  whiteBalance: s.look.whiteBalance,
  tint: s.look.tint,
  lut: s.look.lut,
  lutStrength: s.look.lutStrength,
).isNeutral;

RenderSettings _distortionOff(RenderSettings s) => s.copyWith(
  look: s.look.copyWith(distortion: 0.0, chromaticAberration: 0.0),
);
bool _distortionOn(RenderSettings s) =>
    s.look.distortion != 0.0 || s.look.chromaticAberration > 0.0;

RenderSettings _filmOff(RenderSettings s) =>
    s.copyWith(look: s.look.copyWith(vignette: 0.0, grain: 0.0));
bool _filmOn(RenderSettings s) => s.look.vignette > 0.0 || s.look.grain > 0.0;

RenderSettings _upscaleOff(RenderSettings s) => s.copyWith(
  spatialUpscale: SpatialUpscaleSettings(sharpen: s.spatialUpscale.sharpen),
);
bool _upscaleOn(RenderSettings s) => s.spatialUpscale.enabled;

RenderSettings _edgesOff(RenderSettings s) =>
    s.copyWith(antiAlias: s.antiAlias.copyWith(enabled: false));
bool _edgesOn(RenderSettings s) => s.antiAlias.enabled;

RenderSettings _sharpenOff(RenderSettings s) => s.copyWith(
  antiAlias: s.antiAlias.copyWith(
    sharpen: 0.0,
    temporal: s.antiAlias.temporal.copyWith(sharpen: 0.0),
  ),
  spatialUpscale: SpatialUpscaleSettings(
    enabled: s.spatialUpscale.enabled,
    sharpen: 0.0,
  ),
);
bool _sharpenOn(RenderSettings s) =>
    s.antiAlias.sharpen > 0.0 ||
    s.antiAlias.temporal.sharpen > 0.0 ||
    s.spatialUpscale.sharpen > 0.0;

RenderSettings _contrastOff(RenderSettings s) =>
    s.copyWith(highContrast: s.highContrast.copyWith(enabled: false));
bool _contrastOn(RenderSettings s) => s.highContrast.enabled;

RenderSettings _shadingOff(RenderSettings s) => s.copyWith(
  viewportShading: s.viewportShading.copyWith(mode: ViewportShading.off),
);
bool _shadingOn(RenderSettings s) =>
    s.viewportShading.mode != ViewportShading.off;
