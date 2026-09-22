/// `textureInfo`'s own claim against the real upload — `mat-02`'s own
/// "размеры = `TextureHandle` после загрузки".
///
///     flutter test test/texture_info_upload_test.dart
///
/// **Read before anything decodes, checked against what actually decoded.**
/// `flutter3d_model_core`'s own `textureInfo` reads a file's header with no
/// Flutter SDK behind it — the whole point of that package — so nothing in
/// its own test suite can hold its answer to a real texture upload, which
/// needs `flutter3d`'s own `uploadEncodedImage` and a device. This app is the
/// one place both sides are in reach.
library;

import 'dart:io';

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_graphics_backend.dart';

void main() {
  test(
    'a Basis Universal KTX2 uploads at the size its own header claims',
    () async {
      // A real encoder's own output, not a hand-built fixture — the smallest
      // of the three `flutter3d_samples` already keeps for exactly this
      // format. Basis Universal transcodes to plain RGBA8 on the way to the
      // device, so `textureInfo`'s own fallback (the level index's stored
      // total, since there is no block layout for an undefined `vkFormat`)
      // is read here only for its width and height — the one part of the
      // acceptance this row asks for, not the byte count a transcode changes
      // on purpose.
      final bytes = await File(
        '../../packages/flutter3d_samples/assets/ktx2/etc1s_gradient_quadrants.ktx2',
      ).readAsBytes();

      final info = textureInfo(bytes);
      expect(info, isNotNull, reason: 'a real KTX2 file should read a header');

      final it = fakeTestDevice();
      final handle = await uploadEncodedImage(
        it.device,
        bytes,
        decodeImage: defaultImageDecoder,
      );

      expect(
        handle,
        isNotNull,
        reason:
            'a plain RGBA8 upload should not be '
            'refused by a device that samples everything uncompressed',
      );
      expect(handle!.width, info!.width);
      expect(handle.height, info.height);
    },
  );
}
