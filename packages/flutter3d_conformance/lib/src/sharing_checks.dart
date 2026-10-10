/// Sharing between devices: the copy through host memory that every device
/// has, and zero copy refused by name where it is demanded and missing —
/// 1.0.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import '../flutter3d_conformance.dart';

const TextureDescriptor _square = TextureDescriptor(
  width: 4,
  height: 4,
  format: TextureFormat.r8g8b8a8UNormInt,
);

/// A texture shared with the copy carries what the producer wrote to the
/// consumer: the device is both here, which is the copy path's every step
/// on one backend. Written with `overwriteTexture` rather than drawn, so a
/// device that computes and draws nothing — the wgpu sidecar — is held to
/// it too.
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
  final texels = Uint8List.fromList(<int>[
    for (var i = 0; i < 4 * 4 * 4; i++) (i * 37 + 11) & 0xFF,
  ]);
  await device.overwriteTexture(
    shared.producerTexture,
    ByteData.sublistView(texels),
  );
  await shared.publish();
  final ByteData got = await device.readback(shared.consumerTexture);
  for (var i = 0; i < texels.length; i++) {
    require(
      got.getUint8(i) == texels[i],
      'the consumer\'s byte $i is ${got.getUint8(i)} where the producer '
      'wrote ${texels[i]}: the copy did not carry it',
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
