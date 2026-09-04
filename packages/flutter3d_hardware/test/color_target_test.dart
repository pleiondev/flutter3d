/// What a colour attachment says about where it points, and what the fake
/// device records of a cube a pass may draw into.
///
///     flutter test test/color_target_test.dart
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final texture = TextureHandle(
    backend: const Object(),
    width: 8,
    height: 8,
    format: TextureFormat.r8g8b8a8UNormInt,
  );

  test('an attachment points at the base of the first face unless told', () {
    // The defaults every pass in the engine relied on before a face or a
    // level could be named: a 2D target's one face and its base level.
    final target = ColorTarget(texture: texture);
    expect(target.face, 0);
    expect(target.mipLevel, 0);
  });

  test('a face outside the six is refused at construction', () {
    expect(() => ColorTarget(texture: texture, face: 6), throwsA(anything));
    expect(() => ColorTarget(texture: texture, face: -1), throwsA(anything));
    expect(
      () => ColorTarget(texture: texture, mipLevel: -1),
      throwsA(anything),
    );
  });

  test(
    'a resolve target with a store action that never resolves is refused',
    () {
      // Mutation: delete the third assert in ColorTarget's constructor. The two
      // expectations below then pass construction, which is what every backend
      // did — the doc said "the backend checks" and none of the three looked at
      // the pair. A resolve that never happens is a next pass sampling whatever
      // the resolve target held before.
      expect(
        () => ColorTarget(texture: texture, resolveTexture: texture),
        throwsA(anything),
      );
      expect(
        () => ColorTarget(
          texture: texture,
          resolveTexture: texture,
          storeAction: StoreAction.dontCare,
        ),
        throwsA(anything),
      );
      // Both resolving actions are allowed, and `storeAndMultisampleResolve` is
      // not a typo for the other: it keeps the multisampled texture as well.
      for (final action in <StoreAction>[
        StoreAction.multisampleResolve,
        StoreAction.storeAndMultisampleResolve,
      ]) {
        expect(
          ColorTarget(
            texture: texture,
            resolveTexture: texture,
            storeAction: action,
          ).storeAction,
          action,
        );
      }
    },
  );

  test('the fake device makes a cube and remembers what was asked', () {
    final device = FakeBackend();
    final cube = device.createCubeRenderTarget(
      size: 16,
      format: TextureFormat.r16g16b16a16Float,
      mipLevels: 3,
    );
    expect(cube, isNotNull);
    expect(cube!.type, TextureType.textureCube);
    expect(cube.sliceCount, 6);
    expect(cube.width, 16);
    expect(device.createdCubeRenderTargets.single.mipLevels, 3);
  });

  test('the fake device answers render-to-mip either way', () {
    // The interesting device is the one that says no, and a test has to be
    // able to be it.
    expect(FakeBackend().supportsRenderToMip, isTrue);
    expect(
      FakeBackend(supportsRenderToMip: false).supportsRenderToMip,
      isFalse,
    );
  });
}
