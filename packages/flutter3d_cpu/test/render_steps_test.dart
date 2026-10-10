/// `RenderSettings.without` — every step of the frame switched off, in any
/// combination, on the software device.
///
///     dart test test/render_steps_test.dart
///
/// **The claim is that any set of steps can be taken out and the frame still
/// draws what is left.** One step at a time is the easy half: each step's
/// switch is a setting somebody already tested. What breaks is two steps at
/// once — a pass that reads what another pass wrote, a version chain with two
/// links missing, a resolve that assumed the upscale it sits beside. So this
/// draws every pair of steps switched off together, and a seeded sample of
/// larger sets, and holds each frame to two things: it draws without error,
/// and its `FrameResult` lists exactly the passes and steps a model written
/// here says it should, each with the reason the model gives.
///
/// The model is a second statement of which pass each setting gates, written
/// from the node's documentation rather than read off the renderer. When the
/// two disagree, one of them is wrong, and the failure names the pass.
library;

import 'dart:math' as math;

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const int _size = 24;

/// Every step on, each with something to do, so nothing is missing from the
/// frame for having been off already.
const RenderSettings _everything = RenderSettings(
  shadows: ShadowSettings(
    filter: ShadowFilter.evsm,
    translucentCasters: true,
    caustics: true,
    resolution: 64,
    cubeResolution: 16,
  ),
  reflections: ReflectionSettings(enabled: true),
  ambientOcclusion: AmbientOcclusionSettings(enabled: true, blurTaps: 4),
  contactShadows: ContactShadowSettings(enabled: true),
  volumetricFog: VolumetricFogSettings(enabled: true),
  lightShafts: LightShaftSettings(enabled: true),
  depthOfField: DepthOfFieldSettings(enabled: true),
  motionBlur: MotionBlurSettings(enabled: true),
  antiAlias: AntiAliasSettings(
    enabled: true,
    temporal: TemporalSettings(enabled: true, reactive: 0.5),
  ),
  autoExposure: AutoExposureSettings(enabled: true),
  localExposure: LocalExposureSettings(enabled: true),
  bloom: BloomSettings(
    intensity: 0.8,
    lensFlare: LensFlareSettings(enabled: true),
  ),
  look: LookSettings(
    contrast: 1.1,
    saturation: 0.9,
    vignette: 0.3,
    grain: 0.02,
    distortion: 0.1,
    chromaticAberration: 0.003,
  ),
  fog: FogSettings(density: 0.05),
  renderScale: 0.75,
  spatialUpscale: SpatialUpscaleSettings(enabled: true),
  highContrast: HighContrastSettings(enabled: true),
  viewportShading: ViewportShadingSettings(
    mode: ViewportShading.outline,
    amount: 0.5,
  ),
  occlusion: OcclusionMode.hiZ,
  decals: DecalSettings(enabled: true),
  planarReflections: PlanarReflectionSettings(enabled: true),
);

typedef _Stage = ({CpuDevice device, Renderer renderer, Scene scene});

/// A floor, a box on it with an outline, a bright ball, a sun and a point
/// lamp that both cast, a reflection probe, an irradiance field, a picture
/// drawn through a second camera, a mirror in the floor and a decal on it:
/// something for every step to do.
_Stage _stage() {
  final device = CpuDevice(
    width: _size,
    height: _size,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  MeshNode mesh(MeshData shape, RenderMaterial material, Vector3 at) =>
      MeshNode(DeviceMesh.upload(device, shape), material)..setPositionFrom(at);
  final floor = mesh(
    const PlaneShape(width: 8.0, depth: 8.0).build(),
    RenderMaterial(baseColor: LinearColor.fromSrgb(0.6, 0.6, 0.6, 1.0)),
    Vector3.zero(),
  );
  final camera = CameraNode()
    ..setPosition(0.0, 2.5, 4.0)
    ..lookAt(Vector3.zero());
  final field =
      IrradianceField(
          origin: Vector3(-2.0, 0.0, -2.0),
          spacing: Vector3(4.0, 2.0, 4.0),
          countX: 2,
          countY: 2,
          countZ: 2,
          tile: 4,
          depthTile: 4,
        )
        ..gpuUpdates = 1
        ..fillGutters();
  final scene = Scene()
    ..add(floor)
    ..add(
      mesh(
        CuboidShape(size: Vector3.all(1.0)).build(),
        RenderMaterial(baseColor: LinearColor.fromSrgb(0.8, 0.3, 0.2, 1.0)),
        Vector3(0.0, 0.5, 0.0),
      )..outlineColor = LinearColor(1.0, 1.0, 0.0),
    )
    ..add(
      mesh(
        const SphereShape(radius: 0.3).build(),
        RenderMaterial(
          lighting: LightingModel.unlit,
          baseColor: LinearColor.fromSrgb(1.0, 1.0, 1.0, 1.0),
          emissive: Vector3.all(8.0).toLinearColor(),
        ),
        Vector3(1.2, 1.2, 0.0),
      ),
    )
    ..add(
      LightNode(intensity: 3.0 * Photometric.legacyUnit, castsShadow: true)
        ..setPosition(2.0, 4.0, 1.0)
        ..lookAt(Vector3.zero()),
    )
    ..add(
      LightNode(
        type: LightType.point,
        intensity: 10.0 * Photometric.legacyUnit,
        range: 8.0,
        castsShadow: true,
      )..setPosition(-1.5, 1.5, 1.0),
    )
    ..add(ReflectionProbeNode(faceSize: 8, levels: 2))
    ..add(PlanarReflectorNode(surfaces: <MeshNode>[floor]))
    ..add(
      DecalNode(color: LinearColor.fromSrgb(0.1, 0.2, 0.9, 1.0))
        ..setPosition(-1.0, 0.0, 1.0)
        ..setScale(1.0, 0.5, 1.0),
    )
    ..add(camera)
    ..irradianceField = field;
  scene.addTextureView(
    RenderView.texture(device, camera: camera, width: 8, height: 8),
  );
  return (
    device: device,
    renderer: Renderer.create(device: device),
    scene: scene,
  );
}

FrameResult _render(_Stage it, RenderSettings settings) => it.renderer.render(
  width: _size,
  height: _size,
  scene: it.scene,
  views: <RenderView>[RenderView(camera: it.scene.cameras.single)],
  settings: settings,
);

/// Every pass the frame registers: the published order and the one probe.
final Set<String> _registered = <String>{
  ...RenderSettings.passOrder,
  RenderSettings.probePassName(0),
};

/// The passes this stage runs with every step in [off] switched off — the
/// model, written from what each node's documentation says gates it.
///
/// Three passes are not any one step's and are written out: the velocity
/// passes run while the temporal resolve or the motion blur reads them, the
/// transparent half (its own step since 1.0) runs here only because the
/// decals paint before it, so it needs both steps on, and the sharpening
/// rides in the `antialias` pass. Two run only when another step
/// is *off*: the spatial upscale and the contact shadows' own resolve both
/// stand aside while the temporal resolve runs.
Set<String> _running(Set<RenderStep> off) {
  bool on(RenderStep step) => !off.contains(step);
  final temporal = on(RenderStep.temporalAntiAliasing);
  final upscale = on(RenderStep.spatialUpscale) && !temporal;
  return <String>{
    if (on(RenderStep.shadows)) ...<String>[
      'point shadows (static)',
      'point shadows',
      'directional shadows',
      'shadow moments',
    ],
    if (on(RenderStep.reflectionProbes)) RenderSettings.probePassName(0),
    if (on(RenderStep.irradianceUpdate)) 'irradiance update',
    if (on(RenderStep.renderTextures)) 'render textures',
    if (on(RenderStep.planarReflections)) 'planar reflections',
    'scene',
    if (on(RenderStep.decals)) 'decals',
    if (on(RenderStep.decals) && on(RenderStep.transparent)) 'transparent',
    if (on(RenderStep.highContrast)) 'outline mask',
    if (on(RenderStep.reflections)) 'reflections',
    if (on(RenderStep.autoExposure)) 'luminance',
    if (on(RenderStep.hiZOcclusion)) 'depth pyramid',
    if (on(RenderStep.ambientOcclusion)) ...<String>['ssao', 'ssao blur'],
    if (on(RenderStep.contactShadows)) 'contact shadows',
    if (on(RenderStep.contactShadows) && !temporal) 'contact shadow resolve',
    if (temporal || on(RenderStep.motionBlur)) ...<String>[
      'camera velocity',
      'object velocity',
    ],
    if (temporal) 'reactive mask',
    if (temporal && on(RenderStep.ambientOcclusion)) 'ssao history',
    if (temporal && on(RenderStep.contactShadows)) 'contact shadow history',
    if (on(RenderStep.volumetricFog)) 'volumetric fog',
    if (on(RenderStep.lightShafts)) 'light shafts',
    if (on(RenderStep.depthOfField)) 'depth of field',
    if (on(RenderStep.motionBlur)) 'motion blur',
    if (temporal) 'temporal resolve',
    if (on(RenderStep.localExposure)) 'local exposure',
    if (on(RenderStep.bloom)) 'bloom',
    if (on(RenderStep.bloom) && on(RenderStep.lensFlare)) 'lens flare',
    'composite',
    if (upscale) 'spatial upscale',
    if (on(RenderStep.edgeSmoothing) ||
        (on(RenderStep.sharpening) && (temporal || upscale)))
      'antialias',
    if (on(RenderStep.highContrast)) 'high contrast',
    if (on(RenderStep.viewportShading)) 'viewport shading',
  };
}

/// What `FrameResult.skipped` should hold with [off] switched off, name to
/// reason.
///
/// A pass that does not run is switched off when a step that is off owns
/// it. Otherwise it is off for a reason of the frame's own: the two
/// histories starve when the effect they keep did not run, and every other
/// pass is inactive by its settings — the pick pass with no pick, the colour
/// copy with no glass, the velocity with nobody to read it. Then every step
/// that is off and that no skipped pass already names, under its own name.
Map<String, PassSkip> _expectedSkips(Set<RenderStep> off) {
  final running = _running(off);
  final temporal = !off.contains(RenderStep.temporalAntiAliasing);
  final skips = <String, PassSkip>{
    for (final pass in _registered)
      if (!running.contains(pass))
        pass: switch (pass) {
          _ when off.any((step) => step.ownsPass(pass)) => PassSkip.switchedOff,
          'ssao history' ||
          'contact shadow history' when temporal => PassSkip.starved,
          _ => PassSkip.settings,
        },
  };
  return <String, PassSkip>{
    ...skips,
    for (final step in off)
      if (!skips.containsKey(step.name)) step.name: PassSkip.switchedOff,
    // Not a step: the software device has no multisampled target, and every
    // frame on it says it declined the renderer's multisampling.
    'multisampling': PassSkip.declined,
  };
}

/// Draws [off] switched off and holds the frame to the model.
void _expectFrame(_Stage it, Set<RenderStep> asked) {
  final settings = _everything.without(asked);
  final off = RenderStep.withDependants(asked);
  final FrameResult result;
  try {
    result = _render(it, settings);
  } on Object catch (error) {
    fail('${_names(asked)} switched off threw: $error');
  }
  final ran = result.passes.map((p) => p.name).toSet();
  expect(ran, _running(off), reason: '${_names(asked)}: the passes that ran');
  final skipped = <String, PassSkip>{
    for (final skip in result.skipped) skip.name: skip.reason,
  };
  expect(
    result.skipped,
    hasLength(skipped.length),
    reason: '${_names(asked)}: a name listed twice',
  );
  expect(
    skipped,
    _expectedSkips(off),
    reason: '${_names(asked)}: what skipped says',
  );
  _expectDrawn(it, result, asked);
}

/// The frame holds a picture: every value finite, and not all one colour.
void _expectDrawn(_Stage it, FrameResult result, Set<RenderStep> asked) {
  final pixels = it.device.readHdrPixels(result.frame);
  expect(
    pixels.every((v) => v.isFinite),
    isTrue,
    reason: '${_names(asked)}: a pixel that is not a number',
  );
  final first = <double>[pixels[0], pixels[1], pixels[2]];
  final varies = <int>[for (var i = 0; i < pixels.length; i += 4) i].any(
    (i) => <int>[0, 1, 2].any((c) => (pixels[i + c] - first[c]).abs() > 1e-3),
  );
  expect(varies, isTrue, reason: '${_names(asked)}: a frame of one colour');
}

String _names(Set<RenderStep> steps) =>
    '{${steps.map((s) => s.name).join(', ')}}';

void main() {
  group('the model', () {
    test('everything on runs every registered pass but four', () {
      // The baseline the rest leans on: if a step were already off here, its
      // test below would pass vacuously. The four that never run in this
      // stage have no step — no glass, no pick — or stand aside for the
      // temporal resolve.
      final it = _stage();
      final ran = _render(it, _everything).passes.map((p) => p.name).toSet();
      // Mutation: dropping `ReflectionProbeNode` from the stage leaves
      // 'reflection probe 0' unregistered and this set one short.
      expect(_registered.difference(ran), <String>{
        'scene colour copy',
        'object ids',
        'contact shadow resolve',
        'spatial upscale',
      });
      for (final step in RenderStep.values) {
        expect(step.isOn(_everything), isTrue, reason: step.name);
      }
    });
  });

  group('one step off', () {
    for (final step in RenderStep.values) {
      test('${step.name}: its passes go and the frame still draws', () {
        // Mutation: dropping `enabled &&` from the probe node's `isActive`
        // keeps 'reflection probe 0' running with the step off, and this
        // fails on the passes that ran; dropping the `switchedOff` arm from
        // the compile reports each owned pass as `settings`, and this fails
        // on what skipped says.
        final it = _stage();
        _expectFrame(it, <RenderStep>{step});
        final owned = _registered.where(step.ownsPass);
        final ran = _render(
          it,
          _everything.without(<RenderStep>{step}),
        ).passes.map((p) => p.name);
        // Every pass the step owns is gone, unless another step still on
        // shares it — the sharpening in the `antialias` pass.
        for (final pass in owned) {
          if (pass == 'antialias' && ran.contains(pass)) continue;
          expect(ran, isNot(contains(pass)), reason: pass);
        }
      });
    }
  });

  test('every pair of steps off draws what is left', () {
    // Pairwise coverage over two states each: everything on is the test
    // above, one off is the group above, and both off is every pair here.
    // Mutation: letting the compile bind a link's read forward to its own
    // write (`resolveForwardReferences` without its `writes[reader]` check)
    // runs 'ssao history' with the occlusion off, and every pair holding
    // the occlusion fails on the passes that ran.
    final it = _stage();
    const steps = RenderStep.values;
    for (var a = 0; a < steps.length; a++) {
      for (var b = a + 1; b < steps.length; b++) {
        _expectFrame(it, <RenderStep>{steps[a], steps[b]});
      }
    }
  });

  test('a seeded sample of larger sets draws what is left', () {
    // Sets of three up to all of them, forty of them, from a fixed seed so a
    // failure names the same set on the next run.
    final it = _stage();
    final random = math.Random(20261008);
    for (var round = 0; round < 40; round++) {
      final size = 3 + random.nextInt(RenderStep.values.length - 2);
      final steps = (List<RenderStep>.of(
        RenderStep.values,
      )..shuffle(random)).take(size).toSet();
      _expectFrame(it, steps);
    }
    // And the two ends: nothing off, and everything.
    _expectFrame(it, const <RenderStep>{});
    _expectFrame(it, RenderStep.values.toSet());
  });

  group('the API', () {
    test('a step off is its own setting off, the same frame', () {
      // **Not a second mechanism.** The frame from `without` and the frame
      // from the setting by hand run the same passes and draw the same
      // pixels; only the reason in `skipped` differs.
      // Mutation: record nothing in `stepsOff` from `without`. The frame is
      // the same, the skip reads `settings`, and the reason check below
      // fails.
      final byStep = _stage();
      final byHand = _stage();
      final stepped = _render(
        byStep,
        _everything.without(<RenderStep>{RenderStep.bloom}),
      );
      final handed = _render(
        byHand,
        _everything.copyWith(bloom: _everything.bloom.copyWith(enabled: false)),
      );
      expect(
        stepped.passes.map((p) => p.name),
        handed.passes.map((p) => p.name),
      );
      expect(
        byStep.device.readHdrPixels(stepped.frame),
        byHand.device.readHdrPixels(handed.frame),
      );
      expect(stepped.skipReasonOf('bloom'), PassSkip.switchedOff);
      expect(handed.skipReasonOf('bloom'), PassSkip.settings);
    });

    test('switching off what another step needs switches it off too', () {
      // Mutation: emptying `lensFlare`'s `needs` leaves it out of
      // `stepsOff`, and the first expectation fails.
      final settings = _everything.without(<RenderStep>{RenderStep.bloom});
      expect(settings.stepsOff, <RenderStep>{
        RenderStep.bloom,
        RenderStep.lensFlare,
      });
      final shadowless = _everything.without(<RenderStep>{RenderStep.shadows});
      expect(shadowless.stepsOff, contains(RenderStep.caustics));
      expect(shadowless.shadows.caustics, isFalse);
    });

    test('only keeps what the kept steps need', () {
      // Mutation: `only` without `withPrerequisites` switches the bloom off
      // under the flare, and the flare with it.
      final settings = _everything.only(<RenderStep>{RenderStep.lensFlare});
      expect(RenderStep.lensFlare.isOn(settings), isTrue);
      expect(RenderStep.bloom.isOn(settings), isTrue);
      expect(
        RenderStep.values.where((s) => s.isOn(settings)).toSet(),
        <RenderStep>{RenderStep.lensFlare, RenderStep.bloom},
      );
      final it = _stage();
      _expectFrame(
        it,
        RenderStep.values
            .where((s) => s != RenderStep.lensFlare && s != RenderStep.bloom)
            .toSet(),
      );
    });

    test('a step turned back on by hand is drawn and not reported', () {
      // The switch decides the frame and the record only names it, so a
      // `copyWith` after `without` wins, and the report follows the frame.
      // Mutation: reporting `stepsOff` rather than `switchedOffSteps` in
      // `RenderStep.reportSkips` lists the shadows as switched off on a
      // frame that drew them.
      final settings = _everything
          .without(<RenderStep>{RenderStep.shadows})
          .copyWith(shadows: _everything.shadows);
      final result = _render(_stage(), settings);
      expect(result.passes.map((p) => p.name), contains('directional shadows'));
      expect(result.skipReasonOf('shadows'), isNull);
    });

    test('every step without a pass of its own is still named', () {
      // The tone curve, the grade, the lens, the film, the fog and the
      // caustics are arithmetic inside passes that run anyway; the report
      // still has to say they were taken out.
      // Mutation: returning `nodeSkips` unchanged from
      // `RenderStep.reportSkips` drops all six.
      final passless = RenderStep.values
          .where((s) => !_registered.any(s.ownsPass))
          .toSet();
      expect(passless, <RenderStep>{
        RenderStep.caustics,
        RenderStep.fog,
        RenderStep.tonemap,
        RenderStep.colorGrade,
        RenderStep.lensDistortion,
        RenderStep.vignetteAndGrain,
      });
      final result = _render(_stage(), _everything.without(passless));
      for (final step in passless) {
        expect(result.skipReasonOf(step.name), PassSkip.switchedOff);
      }
    });
  });
}
