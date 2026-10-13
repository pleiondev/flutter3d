/// A texture of any shape and an attachment at any layer reach the trace.
///
/// The trace kept a pool's 2D target and an attachment's face and level, and
/// named everything else unrecorded: an array, a volume, a chain or a
/// storage texture made through `createTexture`, and a pass into a layer
/// above zero or onto a read-only depth. A replay of such a frame drew a
/// different one. Since the trace's targets are classes and a created
/// texture carries its `TextureDescriptor`, both are written and replayed.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter3d_hardware/trace.dart';
import 'package:test/test.dart';

const List<DeviceFeature> _layers = <DeviceFeature>[
  DeviceFeature.textureWrites,
  DeviceFeature.textureArrays,
  DeviceFeature.renderToArrayLayer,
];

/// Records a pass into layer one of a two-layer array, depth read-only.
RecordingDevice _record() {
  final device = RecordingDevice(FakeBackend(extraFeatures: _layers));
  final array = device.createTexture(
    const TextureDescriptor(
      width: 4,
      height: 4,
      format: TextureFormat.r8g8b8a8UNormInt,
      dimension: TextureDimension.d2Array,
      depthOrArrayLayers: 2,
      usage: TextureUsage.standard,
    ),
  );
  final depth = device.createTexture(
    const RenderTargetDescriptor(
      width: 4,
      height: 4,
      format: TextureFormat.d32Float,
    ),
  );
  device
      .beginRenderPass(
        RenderPassDescriptor(
          colors: <ColorTarget>[ColorTarget(texture: array, layer: 1)],
          depth: DepthTarget(
            texture: depth,
            loadAction: LoadAction.load,
            depthReadOnly: true,
          ),
        ),
      )
      .submit();
  return device;
}

void main() {
  test('an array texture and a layered pass are recorded, not skipped', () {
    // Mutation: keep listing `createTexture` for a descriptor that is not
    // a pool's target, or a layer above zero, as unrecorded.
    final device = _record();
    expect(device.unrecorded, isEmpty);
    final created = device.events.whereType<TraceCreateTexture>().first;
    expect(created.spec.dimension, TextureDimension.d2Array);
    expect(created.spec.depthOrArrayLayers, 2);
    final pass = device.events.whereType<TraceBeginRenderPass>().single;
    expect(pass.colors.single.layer, 1);
    expect(pass.depth!.depthReadOnly, isTrue);
  });

  test(
    'a replay asks for the layer and the shape the frame asked for',
    () async {
      // Mutation: drop `layer:` from the replay's `ColorTarget`. The replayed
      // pass draws into layer zero, and its trace says so.
      final original = Trace(_record().events);
      final again = RecordingDevice(FakeBackend(extraFeatures: _layers));
      await replayTrace(original, again);
      expect(Trace(again.events).encode(), original.encode());
    },
  );
}
