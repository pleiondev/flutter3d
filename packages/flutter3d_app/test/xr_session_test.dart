/// The XR contract driven by the fake runtime: a view paced by the
/// runtime's frames, its time, poses on the tape, controls as actions,
/// layers back to the runtime, anchors kept in a level, the room's depth
/// in the frame, and every refusal by name.
///
///     flutter test test/xr_session_test.dart
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_app/xr_testing.dart';
import 'package:flutter3d_core/flutter3d_core.dart'
    show EnvironmentDepth, EnvironmentDepthNode;
import 'package:flutter3d_foundation/flutter3d_foundation.dart' show RigidPose;
import 'package:flutter3d_hardware/testing.dart' show FakeBackend;
import 'package:flutter3d_matter/flutter3d_matter.dart'
    show GeoOrigin, WorldProperties;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show ExternalStateInput, LoopPhase, ReadingKind;
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter_test/flutter_test.dart';

/// Shows nothing: there is no backend to present a fake's frame.
Widget _noPresenter(
  GraphicsDevice device,
  TextureHandle frame, {
  BoxFit fit = BoxFit.fill,
  FilterQuality quality = FilterQuality.none,
}) => const SizedBox.expand();

/// A fake device that can feed a runtime's images.
FakeBackend _device({bool copies = true}) => FakeBackend(
  extraFeatures: <DeviceFeature>[
    if (copies) DeviceFeature.textureCopy,
    DeviceFeature.textureArrays,
    DeviceFeature.textureWrites,
  ],
);

/// A frame of [session] whose right trigger is pulled from frame 3 on.
XrFrame _triggered(FakeXrSession session, int index) {
  final frame = FakeXrSession.standardFrame(session, index);
  return XrFrame(
    index: frame.index,
    predictedDisplayTime: frame.predictedDisplayTime,
    predictedDisplayPeriod: frame.predictedDisplayPeriod,
    space: frame.space,
    views: frame.views,
    poses: frame.poses,
    inputs: <XrInputSource>[
      XrInputSource(
        hand: XrHand.right,
        profiles: const <String>['generic-trigger'],
        controls: <XrControl, XrControlReading>{
          XrControl.trigger: XrControlReading(
            pressed: index >= 3,
            value: index >= 3 ? 1.0 : 0.0,
          ),
        },
      ),
    ],
  );
}

Widget _view({
  required XrSettings xr,
  required GraphicsDevice device,
  void Function(Flutter3dEngine engine)? onCreated,
  Widget Function(Object error)? failure,
}) => Directionality(
  textDirection: TextDirection.ltr,
  child: SizedBox(
    width: 64,
    height: 32,
    child: Flutter3dView(
      xr: xr,
      device: DeviceSettings(device: device, presenter: _noPresenter),
      view: ViewSettings(warmUp: false, failure: failure),
      onCreated: onCreated,
    ),
  ),
);

Future<void> _frames(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(microseconds: 11111));
  }
}

void main() {
  testWidgets('the runtime paces the view and is handed every frame back', (
    tester,
  ) async {
    final session = FakeXrSession();
    final steps = <int>[];
    final recorder = InputTapeRecorder(seed: 1);
    await tester.pumpWidget(
      _view(
        xr: XrSettings(
          session: session,
          swapchain: const XrSwapchainRequest(width: 32, height: 32),
        ),
        device: _device(),
        onCreated: (engine) {
          engine.loop.recorders.add(recorder);
          XrPoses.install(engine.loop);
          engine.loop.addSystem(
            'test.count',
            LoopPhase.rules,
            (context) => steps.add(context.step),
          );
        },
      ),
    );
    await tester.pump();
    await _frames(tester, 45);
    expect(session.state, XrSessionState.focused);
    expect(session.request!.mode, XrCapability.immersiveVr);
    // Mutation: step by the vsync gaps and 45 refreshes of 11 ms bring
    // thirty steps; by the runtime's frames, 1/90 s each, they bring
    // about the same here — so the steps are checked against the display
    // times the frames carried, not against the refreshes.
    final ended = session.ended;
    expect(ended, isNotEmpty);
    final shown =
        ended.last.frame.predictedDisplayTime -
        ended.first.frame.predictedDisplayTime;
    expect(steps.length, closeTo(shown * 60, 2));
    // Each frame ended with its projection layer: both eyes, one image.
    for (final end in ended) {
      final layer = end.layers.single as XrProjectionLayer;
      expect(layer.views, hasLength(2));
      expect(layer.image.depthOrArrayLayers, 2);
    }
    expect(session.framesWaited, greaterThanOrEqualTo(ended.length));
    final swapchain = session.swapchains.single;
    expect(swapchain.acquired, swapchain.released);
    expect(swapchain.acquired, ended.length);
    // The head is on the tape, predicted for its frame's display time.
    final heads = <ExternalStateInput>[
      for (final frame in recorder.tape.frames)
        for (final input in frame.external)
          if (input.source == XrPoseSources.head) input,
    ];
    expect(heads, isNotEmpty);
    expect(heads.first.kind, ReadingKind.predicted);
    expect(heads.first.sourceTime, greaterThanOrEqualTo(session.startTime));

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(session.state, XrSessionState.ended);
  });

  testWidgets('a trigger reaches the game as its bound action', (tester) async {
    final session = FakeXrSession(frameAt: _triggered);
    final used = <bool>[];
    await tester.pumpWidget(
      _view(
        xr: XrSettings(
          session: session,
          swapchain: const XrSwapchainRequest(width: 32, height: 32),
          actions: <String, InputAction<Object>>{
            XrActionSource.sourceId(XrHand.right, XrControl.trigger):
                GameAction.use,
          },
        ),
        device: _device(),
        onCreated: (engine) => engine.loop.addSystem(
          'test.use',
          LoopPhase.rules,
          (context) => used.add(engine.loop.input.held(GameAction.use)),
        ),
      ),
    );
    await tester.pump();
    await _frames(tester, 20);
    // Mutation: drop `_actions?.apply` in `beginFrame` and nothing is held.
    expect(used, contains(true));
    expect(used.first, isFalse);
  });

  testWidgets('a session missing what it is asked for does not start', (
    tester,
  ) async {
    final session = FakeXrSession(
      capabilities: <XrCapability>{XrCapability.immersiveVr},
    );
    Object? failed;
    await tester.pumpWidget(
      _view(
        xr: XrSettings(
          session: session,
          request: const XrSessionRequest(
            mode: XrCapability.immersiveAr,
            required: <XrCapability>{XrCapability.planes},
          ),
        ),
        device: _device(),
        failure: (error) {
          failed = error;
          return const SizedBox();
        },
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(
      failed,
      isA<UnsupportedCapabilityException>().having(
        (e) => e.feature,
        'feature',
        XrCapability.immersiveAr,
      ),
    );
    expect(session.state, XrSessionState.idle);
  });

  testWidgets('a device that cannot feed the runtime is refused by name', (
    tester,
  ) async {
    final session = FakeXrSession();
    Object? failed;
    await tester.pumpWidget(
      _view(
        xr: XrSettings(session: session),
        device: _device(copies: false),
        failure: (error) {
          failed = error;
          return const SizedBox();
        },
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(
      failed,
      isA<UnsupportedCapabilityException>().having(
        (e) => e.feature,
        'feature',
        DeviceFeature.textureCopy,
      ),
    );
    expect(session.state, XrSessionState.ended);
  });

  group('the driver', () {
    Future<void> settle() => Future<void>.delayed(Duration.zero);

    test(
      'panels are layers of their own, and the room is in the frame',
      () async {
        final device = _device();
        final scene = Scene();
        final origin = SceneNode(name: 'stage');
        final sun = LightNode();
        scene
          ..add(origin)
          ..add(sun);
        final renderer = Renderer.create(device: device);
        final depth = EnvironmentDepth(
          width: 2,
          height: 1,
          meters: Float32List.fromList(<double>[1.5, 2.5]),
        );
        final session = FakeXrSession(
          frameAt: (session, index) {
            final frame = FakeXrSession.standardFrame(session, index);
            return XrFrame(
              index: index,
              predictedDisplayTime: frame.predictedDisplayTime,
              space: frame.space,
              views: frame.views,
              depth: depth,
              planes: <XrPlane>[
                XrPlane(
                  id: 'floor',
                  pose: RigidPose.identity(),
                  width: 4,
                  depth: 4,
                ),
              ],
              light: XrLightEstimate(
                ambient: const LinearColor(1.0, 0.8, 0.6),
                ambientIntensity: 120.0,
                direction: Vector3(0.0, 1.0, 0.0),
                intensity: 20000.0,
              ),
            );
          },
        );
        final panel = XrPanel(
          child: const SizedBox(),
          pose: RigidPose.identity(),
          shape: XrPanelShape.cylinder,
        );
        var drawn = 0;
        final driver = XrDriver(
          settings: XrSettings(
            session: session,
            panels: <XrPanel>[panel],
            request: const XrSessionRequest(
              mode: XrCapability.immersiveAr,
              optional: <XrCapability>{XrCapability.depthOcclusion},
            ),
            swapchain: const XrSwapchainRequest(width: 16, height: 16),
            mainLight: sun,
          ),
          renderer: renderer,
          origin: origin,
          drawPanel: (widget, width, height) async {
            drawn++;
            return device.createTexture(
              RenderTargetDescriptor(
                width: width,
                height: height,
                format: TextureFormat.r8g8b8a8UNormInt,
              ),
            );
          },
        );
        final input = InputState();
        await driver.start(input: input);
        await settle();
        for (var i = 0; i < 3; i++) {
          final frame = driver.beginFrame(input)!;
          expect(input.externalThisStep.map((e) => e.source), <String>[
            XrPlane.sourceOf('floor'),
          ]);
          expect(driver.environmentDepth.depth, same(depth));
          expect(driver.views, hasLength(frame.views.length));
          input.endStep();
          await driver.endFrame();
          await settle();
        }
        // Mutation: hand the panel's layer before its texture exists and the
        // first frame ends with a null image.
        expect(session.ended.first.layers, hasLength(1));
        final last = session.ended.last.layers;
        expect(last.first, isA<XrProjectionLayer>());
        final band = last.last as XrCylinderLayer;
        expect(band.centralAngle, closeTo(panel.width / panel.radius, 1e-12));
        expect(drawn, 1, reason: 'drawn once, not every frame');
        // The room's light: the ambient follows it, and the sun shines
        // down from where the runtime says the light is.
        expect(scene.ambientIntensity, 120.0);
        expect(scene.ambientColor, const LinearColor(1.0, 0.8, 0.6));
        expect(sun.intensity, 20000.0);
        final shines = sun.worldMatrix.storage;
        expect(-shines[9], closeTo(-1.0, 1e-6), reason: 'down, along -y');
        panel.invalidate();
        driver.beginFrame(input);
        await driver.endFrame();
        await settle();
        expect(drawn, 2);
        expect(driver.projection.target, isNull, reason: 'handed back');
        expect(driver.framesEnded, 4);
        expect(EnvironmentDepthNode.id.name, 'environment_depth');
        await driver.dispose();
        expect(session.state, XrSessionState.ended);
        expect(origin.children, isEmpty, reason: 'the eyes are taken away');
      },
    );
  });

  group('anchors', () {
    test('an anchor is kept in a level and found again next session', () async {
      final store = <String, XrAnchor>{};
      final first = FakeXrSession(anchorStore: store);
      await first.start(const XrSessionRequest());
      final anchor = await first.placeAnchor(
        XrAnchorRequest(
          pose: RigidPose(
            position: Vector3(0.4, 0.9, -1.2),
            orientation: Quaternion(0.0, 0.38268343236, 0.0, 0.92387953251),
          ),
          geo: GeoOrigin(latitude: 0.9, longitude: 0.5, altitude: 120.0),
        ),
      );
      final level = Level(entities: <EntityDef>[anchor.toEntity()]);
      final read = Level.fromJson(level.toJson());
      final kept = XrAnchor.fromEntity(
        read.entities.singleWhere((e) => e.type == XrAnchor.entityType),
      );
      // Mutation: write the anchor's position only and the turn is lost.
      expect(kept.id, anchor.id);
      expect(kept.pose, anchor.pose);
      expect(kept.geo, anchor.geo);

      final second = FakeXrSession(anchorStore: store);
      await second.start(const XrSessionRequest());
      final restored = await second.restoreAnchor(kept.id);
      expect(restored!.pose, kept.pose);
      expect(await second.restoreAnchor('nobody'), isNull);
    });

    test('an outdoor anchor stands where its place is in the world', () {
      // Mutation: answer the anchor's own pose, or the origin's place, and
      // a bench placed by latitude stands a hundred metres off.
      // Radians: 52° north, and about a hundred metres further north.
      final site = GeoOrigin(latitude: 0.9076, longitude: 0.2269, altitude: 40);
      final north = GeoOrigin(
        latitude: 0.9076 + 1.566e-5,
        longitude: 0.2269,
        altitude: 40.0,
      );
      final anchor = XrAnchor(
        id: 'bench',
        pose: RigidPose.identity(),
        geo: north,
      );
      final world = WorldProperties(geoOrigin: site);

      final at = anchor.placeIn(world)!;
      expect(at, site.positionOf(north));
      expect(at.z, closeTo(-100.0, 1.5), reason: 'north is −z');
      expect(at.x.abs(), lessThan(0.01));

      // Nowhere to stand: a world nowhere in particular, an anchor placed by
      // no place on the Earth.
      expect(anchor.placeIn(WorldProperties()), isNull);
      expect(
        XrAnchor(id: 'indoor', pose: RigidPose.identity()).placeIn(world),
        isNull,
      );
    });

    test('a runtime without anchors or haptics refuses them by name', () async {
      final session = FakeXrSession(
        capabilities: <XrCapability>{XrCapability.immersiveVr},
      );
      await session.start(const XrSessionRequest());
      await expectLater(
        session.placeAnchor(XrAnchorRequest(pose: RigidPose.identity())),
        throwsA(
          isA<UnsupportedCapabilityException>().having(
            (e) => e.feature,
            'feature',
            XrCapability.anchors,
          ),
        ),
      );
      expect(
        () => session.vibrate(const XrHaptic(hand: XrHand.left)),
        throwsA(isA<UnsupportedCapabilityException>()),
      );
      final buzzing = FakeXrSession()
        ..vibrate(const XrHaptic(hand: XrHand.right));
      expect(buzzing.pulses.single.hand, XrHand.right);
      expect(XrCapability.byName('anchors'), XrCapability.anchors);
      expect(XrCapability.values, hasLength(14));
    });
  });

  test('a session written against the contract alone gets every default', () {
    final bare = _Bare();
    expect(
      () => bare.createSwapchain(const XrSwapchainRequest(width: 1, height: 1)),
      throwsA(isA<UnsupportedCapabilityException>()),
    );
    expect(
      bare.restoreAnchor('a'),
      throwsA(isA<UnsupportedCapabilityException>()),
    );
    final settings = XrSettings(
      session: bare,
      mainLight: LightNode(),
    ).copyWith(clearMainLight: true, near: 0.1);
    expect(settings.mainLight, isNull);
    expect(settings.near, 0.1);
    unawaited(bare.end());
  });
}

/// A runtime that implements only what it must.
final class _Bare extends XrSession {
  @override
  String get runtimeName => 'bare';

  @override
  Set<XrCapability> get capabilities => const <XrCapability>{
    XrCapability.inline,
  };

  @override
  XrSessionState get state => XrSessionState.idle;

  @override
  Stream<XrSessionState> get states => const Stream<XrSessionState>.empty();

  @override
  Future<void> start(XrSessionRequest request) async =>
      requireCapabilities(request);

  @override
  Future<XrFrame> waitFrame() => Completer<XrFrame>().future;

  @override
  void endFrame(XrFrameEnd end) {}

  @override
  Future<void> end() async {}
}
