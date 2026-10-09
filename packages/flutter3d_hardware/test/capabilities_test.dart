import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:test/test.dart';

void main() {
  group('DeviceFeature', () {
    test('every feature has a distinct name and is found by it', () {
      // Mutation: give two constants the same name string, and a report or
      // a refusal would name the wrong capability.
      final names = DeviceFeature.values.map((f) => f.name).toList();
      expect(names.toSet().length, names.length);
      for (final feature in DeviceFeature.values) {
        expect(DeviceFeature.byName(feature.name), same(feature));
      }
      expect(DeviceFeature.byName('a feature from a newer version'), isNull);
    });

    test('only the named future capabilities are reserved', () {
      // Mutation: mark a feature reserved that has calls behind it, and no
      // backend could ever report it.
      expect(
        DeviceFeature.values
            .where((f) => f.stability == FeatureStability.reserved)
            .map((f) => f.name),
        unorderedEquals(<String>[
          'ray-query',
          'mesh-shaders',
          'bindless-resources',
          'immediate-data',
        ]),
      );
    });
  });

  group('DeviceFeatures', () {
    test('a reserved feature cannot be reported', () {
      // Mutation: drop the check in the constructor, and a backend could
      // claim ray queries no call can deliver.
      expect(
        () => DeviceFeatures(<DeviceFeature>[DeviceFeature.rayQuery]),
        throwsArgumentError,
      );
    });

    test('require refuses with the feature and the backend named', () {
      // Mutation: throw a bare UnsupportedError, and the conformance check
      // could not tell the promised refusal from a backend falling over.
      final features = DeviceFeatures(<DeviceFeature>[DeviceFeature.stencil]);
      features.require(DeviceFeature.stencil, backend: 'X');
      expect(
        () => features.require(
          DeviceFeature.textureArrays,
          backend: 'WebGL9',
          reason: 'no arrays here',
        ),
        throwsA(
          isA<UnsupportedCapability>()
              .having((e) => e.feature, 'feature', DeviceFeature.textureArrays)
              .having((e) => e.backend, 'backend', 'WebGL9')
              .having(
                (e) => e.message,
                'message',
                allOf(
                  contains('2d-array-textures'),
                  contains('WebGL9'),
                  contains('no arrays here'),
                  contains('GraphicsDevice.features'),
                ),
              ),
        ),
      );
    });

    test('union and without are sets, and equality ignores order', () {
      final a = DeviceFeatures(<DeviceFeature>[
        DeviceFeature.stencil,
        DeviceFeature.compute,
      ]);
      expect(
        a,
        DeviceFeatures(<DeviceFeature>[
          DeviceFeature.compute,
          DeviceFeature.stencil,
        ]),
      );
      expect(
        a.without(<DeviceFeature>[DeviceFeature.compute]).all,
        <DeviceFeature>[DeviceFeature.stencil],
      );
      expect(
        a
            .union(<DeviceFeature>[DeviceFeature.wireframe])
            .has(DeviceFeature.wireframe),
        isTrue,
      );
      expect(a.missing, isNot(contains(DeviceFeature.stencil)));
    });
  });

  group("the fake's flags", () {
    test('become its features and limits', () {
      // Mutation: let the fake keep a flag in a field of its own instead of
      // its feature set, and a caller asking `features` would get a
      // different answer from the one the test configured.
      final device = FakeBackend(
        supportsWireframe: false,
        supportsStencil: false,
        maxAnisotropy: 4,
        maxColorAttachments: 1,
      );
      expect(device.features.has(DeviceFeature.wireframe), isFalse);
      expect(device.features.has(DeviceFeature.stencil), isFalse);
      expect(device.features.has(DeviceFeature.compute), isFalse);
      expect(device.limits.maxSamplerAnisotropy, 4);
      expect(device.limits.maxColorAttachments, 1);
      device.supportsOffscreenMsaa = false;
      expect(device.features.has(DeviceFeature.offscreenMultisample), isFalse);
    });
  });

  group('the fake honours its features', () {
    test('a call it lacks is refused, one it has is recorded', () {
      // Mutation: let the fake record a 1.0 call without asking its
      // features, and an engine test would pass against a device nobody has.
      final device = FakeBackend();
      expect(
        () => device.createQuerySet(QueryType.occlusion, 4),
        throwsA(isA<UnsupportedCapability>()),
      );
      final pass = device.beginRenderPass(
        const RenderPassDescriptor(colors: <ColorTarget>[]),
      );
      expect(
        () => pass.setDepthBias(const DepthBias(constant: 2)),
        throwsA(isA<UnsupportedCapability>()),
      );

      final able = FakeBackend(
        extraFeatures: <DeviceFeature>[DeviceFeature.depthBias],
      );
      final recorded =
          able.beginRenderPass(
                  const RenderPassDescriptor(colors: <ColorTarget>[]),
                )
                as FakePass
            ..setDepthBias(const DepthBias(constant: 2));
      expect(
        recorded.commands.whereType<RecordedCall>().single.name,
        'setDepthBias',
      );
    });

    test('a pass naming a layer needs render-to-array-layer', () {
      // Mutation: skip checkFeatures in beginRenderPass, and a pass would
      // draw into layer zero of an array on a device that cannot attach one.
      final device = FakeBackend();
      final texture = device.createTexture(
        const RenderTargetDescriptor(
          width: 4,
          height: 4,
          format: TextureFormat.r8g8b8a8UNormInt,
        ),
      );
      expect(
        () => device.beginRenderPass(
          RenderPassDescriptor(
            colors: <ColorTarget>[ColorTarget(texture: texture, layer: 1)],
          ),
        ),
        throwsA(
          isA<UnsupportedCapability>().having(
            (e) => e.feature,
            'feature',
            DeviceFeature.renderToArrayLayer,
          ),
        ),
      );
    });

    test('a bundle refuses what belongs to a pass', () {
      // Mutation: let a bundle record a viewport, and a replay would move
      // the viewport of whatever pass it lands in.
      final device = FakeBackend(
        extraFeatures: <DeviceFeature>[DeviceFeature.renderBundles],
      );
      final bundle = device.createRenderBundleEncoder(
        const RenderBundleDescriptor(
          colorFormats: <TextureFormat>[TextureFormat.r8g8b8a8UNormInt],
        ),
      );
      expect(
        () => bundle.setViewport(const ScreenRect(width: 1, height: 1)),
        throwsStateError,
      );
      bundle.draw();
      expect(bundle.finish(label: 'grass').label, 'grass');
    });
  });

  test('every format has one statement of its texel facts', () {
    // Mutation: forget a new format in TextureFormatInfo, and a backend
    // would compute a zero row pitch for it.
    for (final format in TextureFormat.values) {
      if (format == TextureFormat.unknown || format.isCompressed) continue;
      expect(format.bytesPerTexel, greaterThan(0), reason: format.name);
    }
    expect(TextureFormat.r32UInt.isInteger, isTrue);
    expect(TextureFormat.d32Float.isDepthOrStencil, isTrue);
    expect(TextureFormat.r8g8b8a8UNormIntSRGB.isSrgb, isTrue);
    expect(extendedTextureFormats.every((f) => !f.isMirrored), isTrue);
  });
}
