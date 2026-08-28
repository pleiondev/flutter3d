/// Model textures arrive with a mip chain, and with a filter that blends it.
///
///     flutter test test/texture_mipmaps_test.dart
///
/// Everything a chain needs existed for months and nothing built one: `MipChain`
/// was written and tested, all three backends upload a chain, all three answer
/// `supportsMipmaps`, and `SamplerOptions.trilinearRepeat` was sitting there for
/// exactly this — but the one production call that uploads a decoded image
/// passed no levels, so every model texture in every app was a single level.
/// The visible cost is a minified surface that crawls as the camera moves.
///
/// The pair of decisions is what this file is really about. A chain uploaded
/// and then sampled with `MipFilter.nearest` — the default — is memory spent on
/// levels nothing blends between, and the picture is indistinguishable from
/// having built no chain at all. So both come from one input, and both are
/// asserted here.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter_test/flutter_test.dart';

/// A device that says it cannot sample a hand-built chain.
///
/// Not hypothetical: `GraphicsDevice.supportsMipmaps` exists because on an
/// OpenGL ES 2 device without `GL_APPLE_texture_max_level` such a texture
/// samples as **black** — not blurrier, black.
final class _NoMipmaps implements GraphicsDevice {
  @override
  bool get supportsMipmaps => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _WithMipmaps implements GraphicsDevice {
  @override
  bool get supportsMipmaps => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('whether a chain is built', () {
    test('an asset that asks for mipmaps gets one', () {
      // Mutation: drop `sampling.useMipmaps` from the predicate. Every UI atlas
      // and lookup table in every model gains levels it asked not to have.
      expect(
        buildsMipChain(_WithMipmaps(), const TextureSampling(), 256, 256),
        isTrue,
      );
    });

    test('an asset that asks for a single level does not', () {
      expect(
        buildsMipChain(
          _WithMipmaps(),
          const TextureSampling(useMipmaps: false),
          256,
          256,
        ),
        isFalse,
      );
    });

    test('a device that cannot sample a chain is not given one', () {
      // Mutation: assume the capability. The texture comes back black on the
      // one class of device this question exists for, and nothing is logged.
      expect(
        buildsMipChain(_NoMipmaps(), const TextureSampling(), 256, 256),
        isFalse,
      );
    });

    test('a one-by-one image has no level below the base', () {
      // Mutation: drop the `levelsFor > 0` term. `MipChain.build` returns an
      // empty list, and the texture is allocated claiming a chain it has not
      // got — which on WebGL is a `texStorage2D` level count of one and a
      // `TEXTURE_MAX_LEVEL` of zero, i.e. an incomplete texture that samples
      // black.
      expect(
        buildsMipChain(_WithMipmaps(), const TextureSampling(), 1, 1),
        isFalse,
      );
      expect(MipChain.levelsFor(1, 1), 0);
    });

    test('a non-square image still gets the levels it has', () {
      // 64x1 halves along one axis only, which is the case a `w > 1 && h > 1`
      // loop condition gets wrong — it would stop at the first level.
      expect(
        buildsMipChain(_WithMipmaps(), const TextureSampling(), 64, 1),
        isTrue,
      );
      expect(MipChain.levelsFor(64, 1), 6);
    });
  });

  group('the sampler that goes with it', () {
    test('mipmapped sampling asks for a blended chain', () {
      // Mutation: leave `mipFilter` unset. The chain uploads, costs a third
      // more memory, and changes nothing about the picture — the failure that
      // looks like "mipmaps do not work" and is really "mipmaps are not read".
      final sampler = samplerOptionsFor(const TextureSampling());
      expect(sampler.mipFilter, MipFilter.linear);
    });

    test('single-level sampling does not', () {
      final sampler = samplerOptionsFor(
        const TextureSampling(useMipmaps: false),
      );
      expect(sampler.mipFilter, MipFilter.nearest);
    });

    test('the two decisions are made from the same field', () {
      // The property that keeps them from drifting: for any sampling, asking
      // for a chain and asking for it to be blended agree.
      for (final wants in <bool>[true, false]) {
        final sampling = TextureSampling(useMipmaps: wants);
        expect(
          buildsMipChain(_WithMipmaps(), sampling, 128, 128),
          samplerOptionsFor(sampling).mipFilter == MipFilter.linear,
          reason: 'useMipmaps: $wants',
        );
      }
    });

    test('filters and wrapping are untouched by any of this', () {
      // Mutation: rewrite `samplerOptionsFor` around the mip decision and lose
      // a wrap mode. A tiled wall clamps and stretches its last texel across
      // fourteen metres.
      final sampler = samplerOptionsFor(
        const TextureSampling(
          magLinear: false,
          minLinear: false,
          wrapS: TextureWrap.clampToEdge,
          wrapT: TextureWrap.mirroredRepeat,
        ),
      );

      expect(sampler.magFilter, MinMagFilter.nearest);
      expect(sampler.minFilter, MinMagFilter.nearest);
      expect(sampler.widthAddressMode, SamplerAddressMode.clampToEdge);
      expect(sampler.heightAddressMode, SamplerAddressMode.mirror);
    });
  });
}
