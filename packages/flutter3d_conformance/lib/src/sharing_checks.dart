/// Sharing between devices: the copy through host memory that every device
/// has, and zero copy refused by name where it is demanded and missing —
/// 1.0.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../flutter3d_conformance.dart';

const TextureDescriptor _square = TextureDescriptor(
  width: 4,
  height: 4,
  format: TextureFormat.r8g8b8a8UNormInt,
);

/// A texture shared with the copy carries what the producer drew to the
/// consumer: the device is both here, which is the copy path's every step
/// on one backend.
Future<void> checkSharedTextureCopies(GraphicsDevice device) async {
  final shared = SharedTexture.create(
    producer: device,
    consumer: device,
    descriptor: _square,
    demand: SharingMode.hostCopy,
  );
  require(
    shared.mode == SharingMode.hostCopy,
    'a share demanded as hostCopy came back ${shared.mode.name}',
  );
  device
      .beginRenderPass(
        RenderPassDescriptor(
          colors: <ColorTarget>[
            ColorTarget(
              texture: shared.producerTexture,
              clearValue: vm.Vector4(1, 0, 0, 1),
            ),
          ],
        ),
      )
      .submit();
  await shared.publish();
  final ByteData got = await device.readback(shared.consumerTexture);
  for (var i = 0; i < got.lengthInBytes; i += 4) {
    require(
      got.getUint8(i) == 255 &&
          got.getUint8(i + 1) == 0 &&
          got.getUint8(i + 3) == 255,
      'the consumer\'s texel ${i ~/ 4} is not the red the producer cleared '
      'to: the copy did not carry it',
    );
  }
  shared.dispose();
}

/// Zero copy demanded of a device that cannot export is a [SharingRefused]
/// naming the half that is missing, never a quiet copy.
Future<void> checkZeroCopyRefusedByName(GraphicsDevice device) async {
  if (device.features.has(DeviceFeature.sharedTextures) &&
      device.features.has(DeviceFeature.sharedFences)) {
    throw const ConformanceDeclinedException(
      'this device shares textures and fences, so zero copy with itself is '
      'not refused',
    );
  }
  try {
    SharedTexture.create(
      producer: device,
      consumer: device,
      descriptor: _square,
      demand: SharingMode.zeroCopy,
    ).dispose();
  } on SharingRefused catch (refusal) {
    require(
      refusal.mode == SharingMode.zeroCopy && refusal.reason.isNotEmpty,
      'zero copy was refused without saying which half is missing',
    );
    return;
  }
  require(false, 'zero copy was demanded of a device that cannot share');
}

/// The two, as checks.
List<ConformanceCheck> get sharingChecks => <ConformanceCheck>[
  (
    name: 'a shared texture carries the producer\'s pixels by copy',
    run: checkSharedTextureCopies,
  ),
  (
    name: 'zero copy is refused by name where it is missing',
    run: checkZeroCopyRefusedByName,
  ),
];
