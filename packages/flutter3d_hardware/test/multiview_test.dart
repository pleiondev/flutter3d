// Multiview: a pass that names its views, the refusal where a device cannot
// draw them at once, and the one-pass-per-view fallback that every device
// with array layers can.
import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show UnsupportedCapabilityException;
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter3d_hardware/trace.dart';
import 'package:test/test.dart';

/// A fake that makes the array texture two eyes are drawn into.
FakeBackend _fake([List<DeviceFeature> extra = const <DeviceFeature>[]]) =>
    FakeBackend(
      extraFeatures: <DeviceFeature>[
        DeviceFeature.textureWrites,
        DeviceFeature.textureArrays,
        ...extra,
      ],
    );

RenderPassDescriptor _twoEyes(GraphicsDevice device) {
  final eyes = device.createTexture(
    const TextureDescriptor(
      width: 4,
      height: 4,
      format: TextureFormat.r8g8b8a8UNormInt,
      dimension: TextureDimension.d2Array,
      depthOrArrayLayers: 2,
      usage: TextureUsage.renderTarget,
    ),
  );
  return RenderPassDescriptor(
    colors: <ColorTarget>[ColorTarget(texture: eyes)],
    label: 'eyes',
    viewMask: 0x3,
  );
}

void main() {
  test('a view mask names its views, lowest first', () {
    // Mutation: count the bits from the top, and the second eye is drawn
    // into the first eye's layer.
    final device = _fake();
    expect(_twoEyes(device).views, <int>[0, 1]);
    expect(
      RenderPassDescriptor(colors: const <ColorTarget>[], viewMask: 0x5).views,
      <int>[0, 2],
    );
    expect(const RenderPassDescriptor(colors: <ColorTarget>[]).views, <int>[0]);
  });

  test('a pass for one view draws into that view\'s layer, and no mask', () {
    // Mutation: keep the attachment's own layer, and both per-view passes
    // draw into layer zero.
    final device = _fake();
    final view = _twoEyes(device).forView(1);
    expect(view.viewMask, isNull);
    expect(view.colors.single.layer, 1);
    expect(view.label, 'eyes (view 1)');
  });

  test('a device without multiview refuses a masked pass by name', () {
    // Mutation: drop the view-mask clause in checkFeatures, and the pass
    // opens and draws one view where two were asked for.
    final device = _fake(const <DeviceFeature>[
      DeviceFeature.renderToArrayLayer,
    ]);
    expect(
      () => device.beginRenderPass(_twoEyes(device)),
      throwsA(
        isA<UnsupportedCapabilityException>().having(
          (e) => e.feature,
          'feature',
          DeviceFeature.multiview,
        ),
      ),
    );
  });

  test('ViewPasses falls back to one pass per view, each in its layer', () {
    // Mutation: open one pass for the whole mask, and the device above
    // refuses it.
    final device = _fake(const <DeviceFeature>[
      DeviceFeature.renderToArrayLayer,
    ]);
    final seen = <int?>[];
    final opened = ViewPasses.draw(
      device,
      _twoEyes(device),
      (CommandEncoder pass, ViewPass view) => seen.add(view.viewIndex),
    );
    expect(opened, 2);
    expect(seen, <int?>[0, 1]);
    expect(device.passes.map((p) => p.descriptor.colors.single.layer), <int>[
      0,
      1,
    ]);
    expect(device.passes.every((p) => p.descriptor.viewMask == null), isTrue);
  });

  test('multiview reported but no views allowed is still per view', () {
    // Mutation: ask only the feature, and a device reporting multiview with
    // a limit of zero views is handed a pass it cannot draw.
    final device = _fake(const <DeviceFeature>[
      DeviceFeature.multiview,
      DeviceFeature.renderToArrayLayer,
    ]);
    expect(device.limits.maxMultiviewViews, 0);
    expect(ViewPasses.inOnePass(device, _twoEyes(device)), isFalse);
  });

  test('a pass without a mask is one pass, as it always was', () {
    final device = _fake();
    final opened = ViewPasses.draw(
      device,
      RenderPassDescriptor(
        colors: <ColorTarget>[
          ColorTarget(
            texture: device.createTexture(
              const TextureDescriptor(
                width: 2,
                height: 2,
                format: TextureFormat.r8g8b8a8UNormInt,
                usage: TextureUsage.renderTarget,
              ),
            ),
          ),
        ],
      ),
      (CommandEncoder pass, ViewPass view) {
        expect(view.viewIndex, 0);
        expect(view.isMultiview, isFalse);
      },
    );
    expect(opened, 1);
  });

  test('a recording says it did not trace a masked pass', () {
    // Mutation: drop `viewMask` from the recorder's list of untraced pass
    // fields, and a multiview pass is traced as a single view with nothing
    // saying so.
    final inner = _fake(const <DeviceFeature>[
      DeviceFeature.renderToArrayLayer,
      DeviceFeature.multiview,
    ]);
    final device = RecordingDevice(inner);
    try {
      device.beginRenderPass(_twoEyes(device)).submit();
    } on UnsupportedCapabilityException {
      // A fake that cannot draw two views still had the pass recorded first.
    }
    expect(device.unrecorded, contains('beginRenderPass descriptor fields'));
  });
}
