// A feature mask over a live device: the report loses what was masked, the
// calls it gated refuse by its name before the device sees them, and every
// other call reaches the device unchanged.
import 'dart:typed_data';

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show LinearColor, UnsupportedCapabilityException;
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:test/test.dart';

Matcher _refusal(DeviceFeature feature) => throwsA(
  isA<UnsupportedCapabilityException>().having(
    (e) => e.feature,
    'feature',
    feature,
  ),
);

FakeBackend _fake() => FakeBackend(
  compute: true,
  extraFeatures: const <DeviceFeature>[
    DeviceFeature.textureWrites,
    DeviceFeature.buffers,
    DeviceFeature.blendConstant,
    DeviceFeature.depthBias,
    DeviceFeature.indirectDispatch,
    DeviceFeature.bufferCopy,
  ],
);

const RenderTargetDescriptor _target = RenderTargetDescriptor(
  width: 2,
  height: 2,
  format: TextureFormat.r8g8b8a8UNormInt,
);

void main() {
  test('the report loses the masked features and only those', () {
    // Mutation: answer the inner device's features, and a caller branching
    // on the report takes the path the mask was meant to close.
    final inner = _fake();
    final masked = MaskedDevice(
      inner,
      disabledFeatures: const <DeviceFeature>[
        DeviceFeature.blendConstant,
        DeviceFeature.compute,
      ],
    );
    expect(masked.features.has(DeviceFeature.blendConstant), isFalse);
    expect(masked.features.has(DeviceFeature.compute), isFalse);
    expect(
      masked.features.all.toSet(),
      inner.features
          .without(<DeviceFeature>[
            DeviceFeature.blendConstant,
            DeviceFeature.compute,
          ])
          .all
          .toSet(),
    );
    expect(masked.backendName, inner.backendName);
    expect(masked.backendId, inner.backendId);
  });

  test('a masked feature takes its limits and its sample count along', () {
    // Mutation: pass the limits through, and a caller sizing a dispatch
    // from them plans compute on a device that refuses it.
    final masked = MaskedDevice(
      _fake(),
      disabledFeatures: const <DeviceFeature>[
        DeviceFeature.compute,
        DeviceFeature.offscreenMultisample,
      ],
    );
    expect(masked.limits.maxComputeWorkgroupsPerDimension, 0);
    expect(masked.limits.maxComputeInvocationsPerWorkgroup, 0);
    expect(masked.limits.maxSampleCount, 1);
    expect(masked.preferredSampleCount, 1);
    expect(masked.limits.maxColorAttachments, 2);
  });

  test('a masked family answers no format, and is refused at creation', () {
    // Mutation: answer the inner table, and the honesty check finds a
    // family the report says is missing and the table says is there.
    final masked = MaskedDevice(
      _fake(),
      disabledFeatures: const <DeviceFeature>[
        DeviceFeature.textureCompressionBC,
      ],
    );
    expect(
      masked.textureFormatSupport(TextureFormat.bc7RGBAUNormInt),
      TextureFormatSupport.none,
    );
    expect(
      () => masked.createTextureFromPixels(
        width: 4,
        height: 4,
        format: TextureFormat.bc1RGBAUNormInt,
        pixels: ByteData(8),
      ),
      _refusal(DeviceFeature.textureCompressionBC),
    );
  });

  test('a masked call refuses before the inner device records it', () {
    // Mutation: forward first, and the inner device does the work the
    // report said it could not.
    final inner = _fake();
    final masked = MaskedDevice(
      inner,
      disabledFeatures: const <DeviceFeature>[
        DeviceFeature.blendConstant,
        DeviceFeature.depthBias,
        DeviceFeature.compute,
        DeviceFeature.bufferCopy,
        DeviceFeature.textureWrites,
      ],
    );
    final texture = masked.createTexture(_target);
    final pass = masked.beginRenderPass(
      RenderPassDescriptor(
        colors: <ColorTarget>[ColorTarget(texture: texture)],
      ),
    );
    expect(
      () => pass.setBlendColor(LinearColor.transparent),
      _refusal(DeviceFeature.blendConstant),
    );
    expect(
      () => pass.setBlend(
        const BlendState(sourceColorFactor: BlendFactor.blendColor),
      ),
      _refusal(DeviceFeature.blendConstant),
    );
    expect(
      () => pass.setDepthBias(const DepthBias(constant: 1)),
      _refusal(DeviceFeature.depthBias),
    );
    pass.submit();
    expect(inner.passes.single.commands, isEmpty);
    expect(masked.beginComputePass, _refusal(DeviceFeature.compute));
    expect(
      () => masked.writeTexture(texture, ByteData(16)),
      _refusal(DeviceFeature.textureWrites),
    );
    final buffer = masked.createBuffer(
      const BufferDescriptor(
        lengthInBytes: 16,
        usage: BufferUsage.copyDestination,
      ),
    );
    expect(
      () => masked.beginTransferPass().clearBuffer(buffer),
      _refusal(DeviceFeature.bufferCopy),
    );
  });

  test('what the mask keeps reaches the inner device unchanged', () {
    // Mutation: refuse a kept feature, or drop the call, and a mask that
    // narrows one answer breaks the rest of the device.
    final inner = _fake();
    final masked = MaskedDevice(
      inner,
      disabledFeatures: const <DeviceFeature>[DeviceFeature.depthBias],
    );
    final pass = masked.beginRenderPass(
      RenderPassDescriptor(
        colors: <ColorTarget>[
          ColorTarget(texture: masked.createTexture(_target)),
        ],
      ),
    )..setBlendColor(LinearColor.transparent);
    pass.submit();
    expect(inner.passes.single.commands, isNotEmpty);
    masked.beginComputePass().submit();
    expect(inner.computePasses, hasLength(1));
  });

  test('synchronous readback is the type exactly when the mask keeps it', () {
    // Mutation: always mix it in, and a device whose report says no
    // answers `is SynchronousBufferReadback` with yes.
    expect(
      MaskedDevice(_fake(), disabledFeatures: const <DeviceFeature>[]),
      isA<SynchronousBufferReadback>(),
    );
    expect(
      MaskedDevice(
        _fake(),
        disabledFeatures: const <DeviceFeature>[
          DeviceFeature.synchronousReadback,
        ],
      ),
      isNot(isA<SynchronousBufferReadback>()),
    );
  });

  test('without independent blend a call for attachment one lands on zero', () {
    // The contract's words for a device without it. Mutation: forward the
    // index, and the mask draws what no such device would.
    final inner = FakeBackend(
      extraFeatures: const <DeviceFeature>[
        DeviceFeature.independentBlend,
        DeviceFeature.colorWriteMask,
      ],
    );
    final masked = MaskedDevice(
      inner,
      disabledFeatures: const <DeviceFeature>[DeviceFeature.independentBlend],
    );
    masked
        .beginRenderPass(
          RenderPassDescriptor(
            colors: <ColorTarget>[
              ColorTarget(texture: masked.createTexture(_target)),
            ],
          ),
        )
        .setColorWriteMask(ColorWriteMask.red, attachment: 1);
    final call = inner.passes.single.commands.single as RecordedCall;
    expect(call.name, 'setColorWriteMask');
    expect(call.arguments, (mask: ColorWriteMask.red, attachment: 0));
  });
}
