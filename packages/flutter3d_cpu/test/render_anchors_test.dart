/// Render anchors and the open `RenderStep` — step 3 of the plugin plan.
///
///     dart test test/render_anchors_test.dart
///
/// **The first claim is that nothing moved.** The engine's own passes are
/// now registered through the same anchored schedule a plugin's node goes
/// through, and the frame graph's registration order is its version chain,
/// so a pass registered one place later can change a picture. The order is
/// held to `goldens/frame_order.jsonl`, written by the renderer before the
/// anchors existed: for the default settings and for a frame with every step
/// on, as they are, with each step switched off on its own and with each
/// step kept on its own — and all of that again with the application's nodes
/// in both phases. Each line holds the passes that ran in order, the passes
/// left out in registration order, and every skip with its reason; the three
/// together are the registration order. Mutation: register the reflections
/// after the meter, and the "everything" lines fail.
///
/// Then what the anchors are for: a plugin's node lands at its anchor,
/// constraints order the nodes at one anchor, a plugin's step switches and
/// is taken down and reported as a built-in one is, and the plugin host
/// hands the registry to a plugin scoped to it.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show
        BusChannel,
        BusEvent,
        ConstraintCycleException,
        EventCodec,
        EventDeclaration,
        EventHandler,
        EventRegistry,
        Flutter3dPlugin,
        LoopPhase,
        LoopRegistry,
        LoopSystem,
        PluginApiVersion,
        PluginHost,
        PluginManager,
        PluginManifest,
        PluginRegistry,
        PluginScope,
        RenderAnchor;
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

const int _size = 24;

/// The settings `render_steps_test.dart` draws every step with: each one on
/// and with something to do.
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

typedef _Stage = ({Renderer renderer, Scene scene, List<RenderView> views});

/// The scene the fixture was written against, object for object: something
/// for every step to do, a reflection probe among it.
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
    renderer: Renderer.create(device: device),
    scene: scene,
    views: <RenderView>[RenderView(camera: camera)],
  );
}

CompiledFrameGraph _plan(_Stage it, RenderSettings settings) =>
    it.renderer.planFrame(scene: it.scene, views: it.views, settings: settings);

/// One line of the fixture, as the capture wrote it.
String _line(_Stage it, String label, RenderSettings settings) {
  final plan = _plan(it, settings);
  return jsonEncode(<String, Object>{
    'case': label,
    'order': <String>[for (final n in plan.order) n.name],
    'culled': <String>[for (final n in plan.culled) n.name],
    'skipped': <String>[
      for (final s in RenderStep.reportSkips(settings, plan.skipped))
        '${s.name}:${s.reason.name}',
    ],
  });
}

/// The fixture's cases, in its order.
List<String> _sweep(_Stage it, String prefix) => <String>[
  for (final (label, base) in <(String, RenderSettings)>[
    ('default', const RenderSettings()),
    ('everything', _everything),
  ]) ...<String>[
    _line(it, '$prefix$label', base),
    for (final step in RenderStep.values) ...<String>[
      _line(
        it,
        '$prefix$label without ${step.name}',
        base.without(<RenderStep>{step}),
      ),
      _line(
        it,
        '$prefix$label only ${step.name}',
        base.only(<RenderStep>{step}),
      ),
    ],
  ],
];

/// A pass that reads and writes one resource, and draws nothing.
final class _Node extends RenderNode {
  _Node(this.name, this._target);

  @override
  final String name;
  final ResourceId _target;

  @override
  List<ResourceId> get reads => <ResourceId>[_target];

  @override
  List<ResourceId> get writes => <ResourceId>[_target];

  @override
  void execute(RenderFrame frame) {}
}

_Node _hdr(String name) => _Node(name, FrameResourceIds.hdrColor);
_Node _frame(String name) => _Node(name, FrameResourceIds.frame);

/// The default frame on the stage, its passes by name in the order they
/// ran.
List<String> _ran(_Stage it, [RenderSettings s = const RenderSettings()]) =>
    <String>[for (final n in _plan(it, s).order) n.name];

/// What a frame reports switched off, by name.
List<String> _switchedOff(_Stage it, RenderSettings s) => <String>[
  for (final skip in RenderStep.reportSkips(
    s,
    _plan(it, s).skipped,
    also: it.renderer.renderSteps.added,
  ))
    if (skip.reason == PassSkip.switchedOff) skip.name,
];

const RenderStep _glow = RenderStep(
  'soft glow',
  needs: <RenderStep>{RenderStep.bloom},
);
const RenderStep _grade = RenderStep('plugin grade');

// -- The plugin host, with a loop and a bus that keep nothing ---------------

final class _Loop extends LoopRegistry {
  @override
  Registration addPhase(
    LoopPhase phase, {
    List<String> after = const <String>[],
    List<String> before = const <String>[],
  }) => Registration(() {});

  @override
  Registration addSystem(
    String name,
    LoopPhase phase,
    LoopSystem system, {
    List<String> after = const <String>[],
    List<String> before = const <String>[],
  }) => Registration(() {});

  @override
  LoopRegistry forPlugin(PluginScope scope) => this;
}

final class _Events extends EventRegistry {
  @override
  List<EventDeclaration> get declared => const <EventDeclaration>[];

  @override
  Registration declare<T extends BusEvent>(
    String name, {
    BusChannel channel = BusChannel.step,
    EventCodec<T>? codec,
    String? description,
  }) => Registration(() {});

  @override
  Registration onFrame<T extends BusEvent>(
    String label,
    EventHandler<T> handler,
  ) => Registration(() {});

  @override
  Registration onStep<T extends BusEvent>(
    String label,
    EventHandler<T> handler,
  ) => Registration(() {});

  @override
  void publish(BusEvent event) {}

  @override
  EventRegistry forPlugin(PluginScope scope) => this;
}

/// A plugin that puts one node before tone mapping, under its own step.
final class _GradePlugin extends Flutter3dPlugin {
  _GradePlugin(this.id);

  final String id;

  @override
  PluginManifest get manifest =>
      PluginManifest(id: id, apiVersion: PluginApiVersion.current);

  @override
  void install(PluginHost host) {
    final step = RenderStep('$id step');
    host.registry<RendererSteps>()
      ..addStep(step)
      ..addNode(_hdr('$id pass'), at: RenderAnchor.beforeTonemap, step: step);
  }
}

void main() {
  group('the engine\'s order', () {
    test('is the order it was before the anchors, case for case', () {
      // **The proof the move changed nothing.** 244 frames, each compared
      // line for line with what the renderer registered by hand.
      final expected = File(
        'test/goldens/frame_order.jsonl',
      ).readAsLinesSync().where((line) => line.isNotEmpty).toList();
      final it = _stage();
      final lines = _sweep(it, '');
      it.renderer
        ..renderSteps.addNode(_hdr('app overlay a'))
        ..renderSteps.addNode(
          _frame('app present'),
          at: RenderAnchor.beforePresent,
        )
        ..renderSteps.addNode(_hdr('app overlay b'));
      lines.addAll(_sweep(it, 'app nodes, '));

      expect(lines.length, expected.length);
      for (var i = 0; i < lines.length; i++) {
        expect(lines[i], expected[i], reason: 'line ${i + 1}');
      }
    });

    test('the anchors are unique and in frame order', () {
      // Mutation: give two anchors one name, and a plugin's error message
      // names the wrong place.
      final names = RenderAnchor.values.map((a) => a.name).toList();
      expect(names.toSet().length, names.length);
      for (final anchor in RenderAnchor.values) {
        expect(RenderAnchor.named(anchor.name), same(anchor));
      }
      expect(RenderAnchor.values.first, RenderAnchor.beforeShadows);
      expect(RenderAnchor.values.last, RenderAnchor.beforePresent);
    });

    test('a node goes to its own anchor when none is named', () {
      // What the two phases were before 1.0: a node built for the finished
      // picture says so once, and is placed after the composite.
      final it = _stage();
      it.renderer.renderSteps
        ..addNode(_hdr('lit'))
        ..addNode(_Presenting('graded'));
      expect(it.renderer.renderSteps.nodesAt(RenderAnchor.afterScene), <String>[
        'lit',
      ]);
      expect(
        it.renderer.renderSteps.nodesAt(RenderAnchor.beforePresent),
        <String>['graded'],
      );
    });

    test('a plugin anchor stands right after the one it follows', () {
      const glow = RenderAnchor.after(RenderAnchor.afterScene, 'test.glow');
      final it = _stage();
      final steps = it.renderer.renderSteps;
      expect(
        () => steps.addNode(_hdr('early'), at: glow),
        throwsArgumentError,
        reason: 'an anchor nobody added is refused',
      );
      steps
        ..addAnchor(glow)
        ..addNode(_hdr('glowing'), at: glow)
        ..addNode(_hdr('lit'));
      expect(steps.anchorNamed('test.glow'), glow);
      expect(steps.nodesAt(glow), <String>['glowing']);
      expect(glow.engineAnchor, RenderAnchor.afterScene);
    });
  });

  group('a node at an anchor', () {
    test('runs between the passes the anchor names', () {
      final it = _stage();
      it.renderer.renderSteps
        ..addNode(_hdr('after opaque'), at: RenderAnchor.afterOpaque)
        ..addNode(_hdr('before bloom'), at: RenderAnchor.beforeBloom)
        ..addNode(_hdr('after bloom'), at: RenderAnchor.afterBloom)
        ..addNode(_frame('after tonemap'), at: RenderAnchor.afterTonemap);
      final ran = _ran(it);

      // Mutation: map every anchor to its neighbour's slot, and one of these
      // four lands on the other side of the pass it names.
      expect(ran.indexOf('after opaque'), ran.indexOf('scene') + 1);
      expect(ran.indexOf('before bloom'), lessThan(ran.indexOf('bloom')));
      expect(ran.indexOf('after bloom'), greaterThan(ran.indexOf('bloom')));
      expect(ran.indexOf('after bloom'), lessThan(ran.indexOf('composite')));
      expect(
        ran.indexOf('after tonemap'),
        greaterThan(ran.indexOf('composite')),
      );
    });

    test('keeps the order it was added in, then constraints', () {
      final it = _stage();
      it.renderer.renderSteps
        ..addNode(_frame('c'), at: RenderAnchor.beforePresent)
        ..addNode(
          _frame('b'),
          at: RenderAnchor.beforePresent,
          before: <String>['c'],
        )
        ..addNode(
          _frame('a'),
          at: RenderAnchor.beforePresent,
          before: <String>['b'],
          // At another anchor, so ignored rather than refused.
          after: <String>['before bloom'],
        );
      it.renderer.renderSteps.addNode(
        _frame('last'),
        at: RenderAnchor.beforePresent,
      );

      // The phases are gone: a node with no constraint keeps the place it was
      // added in, so the one added last runs last, after the three the
      // constraints turned round.
      //
      // Mutation: drop `before` from the topological order in
      // `RendererSteps`, and the three run as added, `c, b, a`.
      expect(
        it.renderer.renderSteps.nodesAt(RenderAnchor.beforePresent),
        <String>['a', 'b', 'c', 'last'],
      );
      final ran = _ran(it);
      expect(ran.sublist(ran.indexOf('a')), <String>['a', 'b', 'c', 'last']);
    });

    test('a cycle at an anchor names its members', () {
      final it = _stage();
      it.renderer.renderSteps
        ..addNode(_hdr('x'), at: RenderAnchor.afterScene, after: <String>['y'])
        ..addNode(_hdr('y'), at: RenderAnchor.afterScene, after: <String>['x']);
      expect(
        () => _ran(it),
        throwsA(
          isA<ConstraintCycleException>().having(
            (e) => e.cycle.toSet(),
            'cycle',
            <String>{'x', 'y'},
          ),
        ),
      );
    });

    test('takes no name of the engine\'s, and no name twice', () {
      final steps = _stage().renderer.renderSteps;
      expect(
        () => steps.addNode(_hdr('bloom'), at: RenderAnchor.afterBloom),
        throwsArgumentError,
      );
      expect(
        () => steps.addNode(
          _hdr('reflection probe 9'),
          at: RenderAnchor.afterCaptures,
        ),
        throwsArgumentError,
      );
      steps.addNode(_hdr('mine'), at: RenderAnchor.afterBloom);
      expect(
        () => steps.addNode(_hdr('mine'), at: RenderAnchor.afterScene),
        throwsArgumentError,
      );
    });

    test('is gone when its registration is cancelled', () {
      final it = _stage();
      final registration = it.renderer.renderSteps.addNode(
        _hdr('brief'),
        at: RenderAnchor.afterScene,
      );
      expect(_ran(it), contains('brief'));
      registration.cancel();
      expect(_ran(it), isNot(contains('brief')));
    });
  });

  group('a step of a plugin\'s', () {
    _Stage staged() {
      final it = _stage();
      it.renderer.renderSteps
        ..addStep(_glow)
        ..addStep(_grade)
        ..addNode(_hdr('glow'), at: RenderAnchor.afterBloom, step: _glow)
        ..addNode(
          _frame('grade'),
          at: RenderAnchor.beforePresent,
          step: _grade,
        );
      return it;
    }

    test('runs while on, and is switched by without', () {
      final it = staged();
      expect(_ran(it), containsAll(<String>['glow', 'grade']));

      final off = const RenderSettings().without(<RenderStep>{_grade});
      // Mutation: drop the step's gate from the node, and the grade runs.
      expect(_ran(it, off), isNot(contains('grade')));
      expect(_switchedOff(it, off), <String>['grade', 'plugin grade']);
      // On again once a copyWith takes it out of the record.
      final on = off.copyWith(stepsOff: const <RenderStep>{});
      expect(_ran(it, on), contains('grade'));
    });

    test('is taken down with a step it needs, and says so', () {
      final it = staged();
      final off = const RenderSettings().without(<RenderStep>{
        RenderStep.bloom,
      });
      // Mutation: leave the needs out of an added step's isOn, and the glow
      // runs over a picture with no glow in it.
      expect(_ran(it, off), isNot(contains('glow')));
      expect(
        _switchedOff(it, off),
        containsAll(<String>['bloom', 'lens flare', 'glow', 'soft glow']),
      );
      // Told about the renderer's steps, without records it too.
      expect(
        const RenderSettings().without(<RenderStep>{
          RenderStep.bloom,
        }, also: it.renderer.renderSteps.added).stepsOff,
        contains(_glow),
      );
    });

    test('is switched off by only, when only is told about it', () {
      final it = staged();
      final kept = const RenderSettings().only(<RenderStep>{
        RenderStep.tonemap,
      }, also: it.renderer.renderSteps.added);
      expect(_ran(it, kept), isNot(contains('glow')));
      expect(_ran(it, kept), isNot(contains('grade')));
      final keptGrade = const RenderSettings().only(<RenderStep>{
        _grade,
      }, also: it.renderer.renderSteps.added);
      expect(_ran(it, keptGrade), contains('grade'));
    });

    test('is refused a built-in name, a second name, an unknown need', () {
      final steps = _stage().renderer.renderSteps;
      expect(() => steps.addStep(RenderStep.bloom), throwsArgumentError);
      expect(
        () => steps.addStep(const RenderStep('bloom')),
        throwsArgumentError,
      );
      expect(
        () => steps.addStep(
          const RenderStep('late', needs: <RenderStep>{_grade}),
        ),
        throwsArgumentError,
      );
      steps.addStep(_grade);
      expect(
        () => steps.addStep(const RenderStep('plugin grade')),
        throwsArgumentError,
      );
      expect(steps.named('plugin grade'), same(_grade));
      expect(steps.all.last, same(_grade));
    });
  });

  group('the plugin host', () {
    test('hands each plugin the registry, ranked and withdrawn', () {
      final it = _stage();
      final manager = PluginManager(
        loop: _Loop(),
        events: _Events(),
        registries: <PluginRegistry>[it.renderer.renderSteps],
      )..installAll(<Flutter3dPlugin>[_GradePlugin('b'), _GradePlugin('a')]);

      // Install order, not names, decides between two plugins at one anchor.
      expect(
        it.renderer.renderSteps.nodesAt(RenderAnchor.beforeTonemap),
        <String>['b pass', 'a pass'],
      );
      expect(it.renderer.renderSteps.added.map((s) => s.name), <String>[
        'b step',
        'a step',
      ]);

      manager
        ..disable('b')
        ..applyPending(1);
      // Mutation: forget to track the node's registration, and it stays.
      expect(
        it.renderer.renderSteps.nodesAt(RenderAnchor.beforeTonemap),
        <String>['a pass'],
      );
      expect(it.renderer.renderSteps.added.map((s) => s.name), <String>[
        'a step',
      ]);
    });
  });
}

/// A node over the finished picture, placed there by its own default.
final class _Presenting extends RenderNode {
  const _Presenting(this.name);

  @override
  final String name;

  @override
  RenderAnchor get defaultAnchor => RenderAnchor.beforePresent;

  @override
  List<ResourceId> get reads => const <ResourceId>[FrameResourceIds.frame];

  @override
  List<ResourceId> get writes => const <ResourceId>[FrameResourceIds.frame];

  @override
  void execute(RenderFrame frame) {}
}
