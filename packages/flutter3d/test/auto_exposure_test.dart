/// Auto exposure: the meter's arithmetic, the adapter's rate, and the frame
/// the renderer builds to feed them — none of it needing a device.
///
///     flutter test test/auto_exposure_test.dart
///
/// The rendered half — a dark scene climbing to the ceiling through a real
/// luminance pass and a real readback — is
/// `flutter3d_cpu/test/auto_exposure_test.dart`. What is here is everything
/// that can be pinned with bytes handed in by hand, which is most of it: a
/// meter that read the wrong band of the histogram, an adapter that lerped the
/// multiplier instead of the stops, or a frame that ran the pass with the
/// setting off would each be a golden that moved for a reason nobody could
/// name.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d/src/engine/geometry/box_shapes.dart';
import 'package:flutter3d/src/engine/geometry/device_mesh.dart';
import 'package:flutter3d/src/engine/render/material.dart';
import 'package:flutter3d/src/engine/render/render_view.dart';
import 'package:flutter3d/src/engine/render/renderer.dart';
import 'package:flutter3d/src/engine/scene/camera_node.dart';
import 'package:flutter3d/src/engine/scene/mesh_node.dart';
import 'package:flutter3d/src/engine/scene/scene.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter_test/flutter_test.dart';

/// A luminance target's worth of bytes, every texel at [encoded].
ByteData _flat(int encoded) {
  final bytes = Uint8List(ExposureMeter.size * ExposureMeter.size * 4);
  for (var i = 0; i < bytes.length; i += 4) {
    bytes[i] = encoded;
    bytes[i + 3] = 255;
  }
  return ByteData.sublistView(bytes);
}

double _log2(double x) => math.log(x) / math.ln2;

/// The byte whose stop makes the meter ask for exactly [exposure].
int _encodedFor(double exposure, AutoExposureSettings settings) =>
    ((_log2(settings.target / exposure) - ExposureMeter.floorStops) /
            ExposureMeter.rangeStops *
            255)
        .round();

void main() {
  group('the meter', () {
    test('decodes a byte to the stop the shader encoded it as', () {
      // The two ends of one encoding, in two languages. Mutation: change the
      // floor or the range on either side alone — a flat frame meters as a
      // different brightness and the exposure lands somewhere else.
      expect(ExposureMeter.stopsOf(0), ExposureMeter.floorStops);
      expect(
        ExposureMeter.stopsOf(255),
        ExposureMeter.floorStops + ExposureMeter.rangeStops,
      );
      // Zero stops — one unit of light — is where a scene lit at one sits, and
      // it has to be inside the byte rather than at either end of it.
      final unit = (-ExposureMeter.floorStops / ExposureMeter.rangeStops * 255)
          .round();
      expect(ExposureMeter.stopsOf(unit), closeTo(0.0, 0.05));
    });

    test('meters a flat frame as its own value', () {
      expect(
        ExposureMeter.meanStops(_flat(128)),
        closeTo(ExposureMeter.stopsOf(128), 1e-9),
      );
    });

    test('reads the band between the percentiles and nothing outside it', () {
      // Three quarters black, a quarter bright: a plain mean would call this
      // frame dark and blow the bright quarter out. The band from 80% to 98%
      // lies entirely inside the bright quarter, so that is what it meters.
      //
      // Mutation: average every texel — the answer drops towards the black
      // bin's stop and this fails. Or count the band from the bright end — the
      // top 2% cut then takes the bright quarter's own top and the low cut
      // reaches into the black.
      final bytes = Uint8List(ExposureMeter.size * ExposureMeter.size * 4);
      final total = ExposureMeter.size * ExposureMeter.size;
      for (var i = 0; i < total; i++) {
        bytes[i * 4] = i < total * 3 ~/ 4 ? 0 : 200;
        bytes[i * 4 + 3] = 255;
      }
      final stops = ExposureMeter.meanStops(ByteData.sublistView(bytes));
      expect(stops, ExposureMeter.stopsOf(200));

      // Widen the band into the black and the mean moves down, but not to it.
      final wider = ExposureMeter.meanStops(
        ByteData.sublistView(bytes),
        lowPercentile: 0.5,
        highPercentile: 0.98,
      );
      expect(wider, lessThan(stops));
      expect(wider, greaterThan(ExposureMeter.stopsOf(0)));
    });

    test('exposes a brightness to the target', () {
      // Middle grey at zero stops asks for an exposure of exactly the target;
      // two stops darker asks for four times as much. Mutation: divide the
      // other way — a dark scene gets darker.
      expect(ExposureMeter.exposureFor(0.0, 0.18), closeTo(0.18, 1e-9));
      expect(ExposureMeter.exposureFor(-2.0, 0.18), closeTo(0.72, 1e-9));
      expect(ExposureMeter.exposureFor(1.0, 0.5), closeTo(0.25, 1e-9));
    });
  });

  group('the adapter', () {
    const settings = AutoExposureSettings(
      enabled: true,
      speedUp: 3.0,
      speedDown: 3.0,
    );

    test('holds the initial value until something is metered', () {
      final adapter = ExposureAdapter(initial: 1.6)..step(1.0, settings);
      expect(adapter.value, 1.6);
      expect(adapter.target, isNull);
    });

    test('climbs to the ceiling on a dark frame, within two seconds', () {
      // A byte of zero is the darkest thing the encoding says, so the target
      // is far above the ceiling and the ceiling is where it stops. A hundred
      // and twenty frames at sixty a second: at a rate of three, 1 − e^(−6) of
      // the two and a third stops from 1.6 to 8 is closed, leaving a
      // hundredth of a stop — under 0.05 in the multiplier.
      //
      // Mutation: step towards the unclamped target — the value leaves the
      // ceiling behind; or forget the clamp in `meter` — the target reads as
      // 184 rather than 8.
      final adapter = ExposureAdapter(initial: 1.6)..meter(_flat(0), settings);
      expect(adapter.target, settings.maxExposure);

      var previous = adapter.value;
      for (var frame = 0; frame < 120; frame++) {
        adapter.step(1.0 / 60.0, settings);
        expect(adapter.value, greaterThanOrEqualTo(previous));
        previous = adapter.value;
      }
      expect(adapter.value, closeTo(settings.maxExposure, 0.05));
    });

    test('falls to the floor on a bright frame', () {
      final adapter = ExposureAdapter(initial: 1.6)
        ..meter(_flat(255), settings);
      expect(adapter.target, settings.minExposure);
      for (var frame = 0; frame < 120; frame++) {
        adapter.step(1.0 / 60.0, settings);
      }
      expect(adapter.value, closeTo(settings.minExposure, 0.01));
    });

    test('moves in stops, so a doubling and a halving take the same time', () {
      // From 2 towards 4 and from 2 towards 1 are one stop each way, and after
      // the same interval each has covered the same fraction of its stop —
      // the fraction the rate promises. Mutation: lerp the multiplier rather
      // than its logarithm — the doubling covers twice the distance of the
      // halving in the same time, and the two fractions disagree.
      const wide = AutoExposureSettings(
        enabled: true,
        speedUp: 2.0,
        speedDown: 2.0,
        minExposure: 0.01,
        maxExposure: 100.0,
      );
      const dt = 0.2;
      double fractionTowards(double to) {
        final adapter = ExposureAdapter(initial: 2.0)
          ..meter(_flat(_encodedFor(to, wide)), wide)
          ..step(dt, wide);
        final target = adapter.target!;
        return (_log2(adapter.value) - _log2(2.0)) /
            (_log2(target) - _log2(2.0));
      }

      final promised = 1.0 - math.exp(-dt * 2.0);
      expect(fractionTowards(4.0), closeTo(promised, 1e-9));
      expect(fractionTowards(1.0), closeTo(promised, 1e-9));
    });

    test('rises at one rate and falls at the other', () {
      // Mutation: pick the rate by the sign of the multiplier's difference
      // rather than the stops', or swap the two — the fall borrows the climb's
      // rate.
      const lopsided = AutoExposureSettings(
        enabled: true,
        speedUp: 1.0,
        speedDown: 4.0,
        minExposure: 0.01,
        maxExposure: 100.0,
      );
      final up = ExposureAdapter(initial: 2.0)
        ..meter(_flat(_encodedFor(8.0, lopsided)), lopsided)
        ..step(0.5, lopsided);
      final down = ExposureAdapter(initial: 2.0)
        ..meter(_flat(_encodedFor(0.5, lopsided)), lopsided)
        ..step(0.5, lopsided);
      final climbed = (_log2(up.value) - 1.0) / (_log2(up.target!) - 1.0);
      final fell = (_log2(down.value) - 1.0) / (_log2(down.target!) - 1.0);
      expect(climbed, closeTo(1.0 - math.exp(-0.5), 1e-9));
      expect(fell, closeTo(1.0 - math.exp(-2.0), 1e-9));
    });

    test('an infinite rate lands on the target at once', () {
      // What a golden asks for: a frame that must be the same every time it is
      // drawn cannot depend on the wall clock. Mutation: compute
      // `1 − e^(−dt·∞)` unguarded — with dt of zero that is NaN, and the value
      // becomes NaN with it.
      const instant = AutoExposureSettings(
        enabled: true,
        speedUp: double.infinity,
        speedDown: double.infinity,
      );
      final adapter = ExposureAdapter(initial: 1.6)
        ..meter(_flat(0), instant)
        ..step(0.0, instant);
      expect(adapter.value, instant.maxExposure);
    });
  });

  group('the settings', () {
    test('are off by default, and copyWith keeps every field', () {
      expect(const AutoExposureSettings().enabled, isFalse);
      const original = AutoExposureSettings(
        enabled: true,
        minExposure: 0.5,
        maxExposure: 4.0,
        speedUp: 0.7,
        speedDown: 1.3,
        target: 0.2,
        lowPercentile: 0.3,
        highPercentile: 0.8,
      );
      final copy = original.copyWith();
      expect(copy.enabled, original.enabled);
      expect(copy.minExposure, original.minExposure);
      expect(copy.maxExposure, original.maxExposure);
      expect(copy.speedUp, original.speedUp);
      expect(copy.speedDown, original.speedDown);
      expect(copy.target, original.target);
      expect(copy.lowPercentile, original.lowPercentile);
      expect(copy.highPercentile, original.highPercentile);
    });
  });

  group('the frame', () {
    late FakeBackend device;
    late Renderer renderer;
    late Scene scene;
    late RenderView view;

    setUp(() {
      device = FakeBackend();
      renderer = Renderer.create(device: device);
      scene = Scene()
        ..add(
          MeshNode(DeviceMesh.upload(device, CuboidShape().build()), Material())
            ..setPosition(0.0, 0.0, -5.0),
        )
        ..add(CameraNode());
      view = RenderView(camera: scene.cameras.single);
    });

    FrameResult frame(RenderSettings settings) => renderer.render(
      width: 64,
      height: 48,
      scene: scene,
      views: <RenderView>[view],
      settings: settings,
    );

    Iterable<FakePass> luminancePasses() => device.passes.where(
      (FakePass pass) =>
          pass.descriptor.colors.length == 1 &&
          pass.color.texture.width == ExposureMeter.size &&
          pass.color.texture.height == ExposureMeter.size,
    );

    test('runs no luminance pass and reads nothing back while it is off', () {
      // The promise every golden rests on. Mutation: make the node active
      // regardless of the setting — a pass and a readback appear.
      final result = frame(const RenderSettings(exposure: 2.5));
      expect(luminancePasses(), isEmpty);
      expect(device.readbacks, isEmpty);
      expect(result.exposure, 2.5, reason: 'the setting is the exposure');
      expect(renderer.exposure, 2.5);
    });

    test('draws a small eight-bit luminance target and reads it back', () {
      // Mutation: declare the target at the frame's size, or in the HDR
      // format — a readback of sixty-four kilobytes of half floats per frame
      // is what the fixed small eight-bit square exists to avoid.
      frame(
        const RenderSettings(autoExposure: AutoExposureSettings(enabled: true)),
      );
      final pass = luminancePasses().single;
      expect(pass.color.texture.format, TextureFormat.r8g8b8a8UNormInt);
      expect(pass.submitted, isTrue);
      expect(
        pass.recordedOf<RecordedTexture>().map((RecordedTexture t) => t.slot),
        contains('scene_texture'),
      );

      final readback = device.readbacks.single;
      expect(identical(readback.texture, pass.color.texture), isTrue);
      expect(readback.region, ScreenRect.of(pass.color.texture));
    });

    test('asks the device once per answer, not once per frame', () async {
      // The fake answers on a microtask, so two frames with nothing pumped
      // between them are two frames with the first ask still in the air: the
      // second frame draws its luminance and asks nothing. Pumped, the
      // answer lands and the next frame asks again. Mutation: drop the
      // in-flight check — three readbacks for three frames, and on
      // flutter_gpu a staging pool that grows to the queue's depth.
      const settings = RenderSettings(
        autoExposure: AutoExposureSettings(enabled: true),
      );
      frame(settings);
      frame(settings);
      expect(luminancePasses(), hasLength(2), reason: 'the pass ran twice');
      expect(device.readbacks, hasLength(1), reason: 'one ask in the air');
      await pumpEventQueue();
      frame(settings);
      expect(device.readbacks, hasLength(2));
    });

    test(
      'a device that refuses on the spot costs a count, not the frame',
      () async {
        // Every backend refuses *synchronously*: `readbackRegionOf` throws
        // before a future exists, which is what the conformance check tests
        // for, and WebGL2 does the same when a lost context will not give it a
        // fence. The fake refuses that way here, from inside `answerReadback`.
        //
        // Three claims, and the middle one is the reason the first two are
        // worth anything. Mutation: call `device.readback` bare rather than
        // through `Future.sync` — the throw comes out of the luminance node,
        // `render` rethrows it, this test's `frame` throws instead of returning
        // a picture, and `_meterInFlight` is left true for ever, so the two
        // later expectations fail as well.
        device.answerReadback = (_, _) =>
            throw StateError('the context refused a fence for the readback');
        const settings = RenderSettings(
          exposure: 1.6,
          autoExposure: AutoExposureSettings(enabled: true),
        );
        final result = frame(settings);
        expect(result.exposure, 1.6, reason: 'the frame was drawn and exposed');
        expect(device.readbacks, hasLength(1), reason: 'the device was asked');
        await pumpEventQueue();
        expect(
          renderer.debugMeterFailures,
          1,
          reason: 'counted, not swallowed',
        );

        // And the meter is not wedged: the ask that failed is over, so the next
        // frame asks again rather than believing one is still in the air.
        frame(settings);
        expect(device.readbacks, hasLength(2));
        await pumpEventQueue();
        expect(renderer.debugMeterFailures, 2);
      },
    );

    test('exposes the next frame with what the last one metered', () async {
      // The device answers black, so the target is the ceiling; at an infinite
      // rate the frame after the readback is composited at the ceiling. The
      // frame that asked is not — it was composited before the answer came —
      // which is the "frame before" this whole mechanism is named for.
      //
      // Mutation: read the setting's exposure in the composite instead of the
      // adapter's — the second frame stays at 1.6.
      device.answerReadback = (_, _) => _flat(0);
      const settings = RenderSettings(
        exposure: 1.6,
        autoExposure: AutoExposureSettings(
          enabled: true,
          speedUp: double.infinity,
          speedDown: double.infinity,
        ),
      );
      final first = frame(settings);
      expect(first.exposure, 1.6, reason: 'nothing has been metered yet');
      await pumpEventQueue();
      final second = frame(settings);
      expect(second.exposure, settings.autoExposure.maxExposure);
      expect(renderer.exposure, settings.autoExposure.maxExposure);

      // And the composite was handed that number, not the setting.
      final composite = device.passes.last;
      final block = composite.recordedOf<RecordedUniformBlock>().firstWhere(
        (RecordedUniformBlock b) => b.block == 'CompositeInfo',
      );
      expect(block.members['params']![0], settings.autoExposure.maxExposure);
    });
  });
}
