/// The dispose contract: one owner, one `dispose`, and nothing used after it.
///
/// Held on the fake because it is where a test sees a handle's life whole:
/// it counts what was made and not given back, and its pass makes the
/// use-after-dispose check every backend makes. Both checks are assertions,
/// which a test run has on.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/backend.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:test/test.dart';

const _target = RenderTargetDescriptor(
  width: 4,
  height: 4,
  format: TextureFormat.r8g8b8a8UNormInt,
);

void main() {
  group('the live-handle count', () {
    test('counts what was made and not given back', () {
      // Mutation: `_born` not called from a creator leaves this at zero
      // after the texture, and a leak in a test goes unseen.
      final device = FakeBackend(
        extraFeatures: const <DeviceFeature>[
          DeviceFeature.buffers,
          DeviceFeature.occlusionQuery,
        ],
      );
      final texture = device.createTexture(_target);
      final geometry = device.uploadGeometry(
        ByteData(16),
        GeometryUsage.vertices,
      );
      final buffer = device.createBuffer(
        const BufferDescriptor(lengthInBytes: 16, usage: BufferUsage.uniform),
      );
      final queries = device.createQuerySet(QueryType.occlusion, 2);
      final shaders = device.shaders;
      final pipeline = device.createPipeline(
        shaders['quad.vert']!,
        shaders['quad.frag']!,
      );
      expect(device.liveHandles, <Object>[
        texture,
        geometry,
        buffer,
        queries,
        pipeline,
      ]);

      // Mutation: a `release…` that does not take the handle out leaves the
      // count where it was.
      texture.dispose();
      geometry.dispose();
      buffer.dispose();
      queries.dispose();
      pipeline.dispose();
      expect(device.liveHandleCount, 0);
    });

    test('empties when the device is disposed, which ends every handle', () {
      final device = FakeBackend()..createTexture(_target);
      expect(device.liveHandleCount, 1);
      device.dispose();
      expect(device.liveHandles, isEmpty);
    });
  });

  group('a handle disposed twice', () {
    test('is an assertion', () {
      // Mutation: the assert in `TextureHandle.dispose` removed — the
      // second call does nothing, as it did before 1.0, and a double free
      // on WebGL deletes an object a later texture may have been given.
      final texture = FakeBackend().createTexture(_target)..dispose();
      expect(texture.dispose, throwsA(isA<AssertionError>()));
    });

    test('is not, for a view with nothing to give back', () {
      final slice =
          FakeBackend()
              .uploadGeometry(ByteData(16), GeometryUsage.vertices)
              .slice(length: 8)
            ..dispose();
      expect(slice.dispose, returnsNormally);
    });
  });

  group('a disposed handle used again', () {
    test('is refused at the bind, naming the call', () {
      // Mutation: `debugCheckLive` taken out of `FakePass.bindTexture` —
      // the bind is recorded, and the test that should fail draws.
      final device = FakeBackend();
      final texture = device.createTexture(_target)..dispose();
      final pass = device.beginRenderPass(
        RenderPassDescriptor(
          colors: <ColorTarget>[
            ColorTarget(texture: device.createTexture(_target)),
          ],
        ),
      );
      expect(
        () => pass.bindTexture(device.shaders['quad.frag']!, 'tex', texture),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('bindTexture'),
          ),
        ),
      );
    });

    test('passes the check while it is live', () {
      final texture = FakeBackend().createTexture(_target);
      expect(() => debugCheckLive(texture, 'a test'), returnsNormally);
    });
  });
}
