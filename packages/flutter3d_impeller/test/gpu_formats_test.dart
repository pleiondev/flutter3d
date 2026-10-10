/// Proves the enum translation, value by value.
///
/// The hazard this exists for: a wrong mapping compiles, runs, and renders
/// wrong only for the values a scene happens to use. The goldens cover the
/// values the 96 scenes exercise and nothing else — `BlendFactor` has
/// fifteen members and the engine draws with two of them — so a mistake in the
/// other thirteen would be found by a user rather than by us.
///
/// Three claims, and it takes all three:
///
///  1. **Each value lands on the flutter_gpu value of the same name.** This is
///     the one that matters. "Distinct" would happily accept a swapped
///     `frontFace` / `backFace` pair, and swapping those is exactly the mistake
///     a hand-written mapping makes.
///  2. **The two enums have the same number of values.** The analyser already
///     refuses a mapping that misses one of *ours* — every switch in
///     `gpu_formats.dart` is an expression with no `default`. This covers the
///     other direction: flutter_gpu gaining a value we have not mirrored.
///  3. **The round trip is identity**, wherever a reverse mapping exists.
///
/// It runs off-device. The enums are const and flutter_gpu's `SamplerDescriptor`
/// is a plain Dart object, so nothing here needs a GPU context — the same
/// property `render_target_spec_test.dart` and `composite_mix_test.dart` rely
/// on.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_impeller/src/gpu_formats.dart';
import 'package:flutter3d_impeller/src/gpu_texture.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';

/// Checks one enum's forward mapping against flutter_gpu's values.
///
/// [toGpu] is passed as a function rather than looked up, because the mapping
/// under test is the thing being pinned and reaching it through anything
/// clever would let the test agree with a bug.
void checkForward<E extends Object, G extends Enum>(
  String name,
  List<E> ours,
  List<G> theirs,
  G Function(E) toGpu,
) {
  group(name, () {
    test('has exactly the values flutter_gpu has', () {
      expect(
        ours.length,
        theirs.length,
        reason:
            '$name: flutter_gpu has ${theirs.length} values and this '
            'engine has ${ours.length}. Adding or dropping one silently is '
            'how the two stop meaning the same thing.',
      );
      expect(ours.map(_nameOf), theirs.map((e) => e.name));
    });

    test('every value maps to the flutter_gpu value of the same name', () {
      for (final value in ours) {
        expect(
          toGpu(value).name,
          _nameOf(value),
          reason: '$name.${_nameOf(value)} maps to ${toGpu(value).name}',
        );
      }
    });

    test('no two values map to the same one', () {
      final seen = <G, E>{};
      for (final value in ours) {
        final mapped = toGpu(value);
        expect(
          seen[mapped],
          isNull,
          reason:
              '$name.${_nameOf(value)} and $name.${_nameOf(seen[mapped])} both '
              'map to ${mapped.name}',
        );
        seen[mapped] = value;
      }
    });
  });
}

/// Checks that a value survives a trip through flutter_gpu and back.
void checkRoundTrip<E extends Object, G extends Enum>(
  String name,
  List<E> ours,
  List<G> theirs,
  G Function(E) toGpu,
  E Function(G) toEngine,
) {
  group('$name round trip', () {
    test('ours -> flutter_gpu -> ours is identity', () {
      for (final value in ours) {
        expect(toEngine(toGpu(value)), value);
      }
    });

    test('flutter_gpu -> ours -> flutter_gpu is identity', () {
      for (final value in theirs) {
        expect(toGpu(toEngine(value)), value);
      }
    });
  });
}

/// The values flutter_gpu has, in declaration order — every value but the
/// `extended*` tails, which `flutter3d_hardware` names so this need not.
final List<TextureFormat> mirroredFormats = <TextureFormat>[
  for (final format in TextureFormat.values)
    if (format.isMirrored) format,
];
final List<BlendFactor> mirroredFactors = <BlendFactor>[
  for (final factor in BlendFactor.values)
    if (!factor.isDualSource) factor,
];
final List<BlendOperation> mirroredOperations = <BlendOperation>[
  for (final operation in BlendOperation.values)
    if (!extendedBlendOperations.contains(operation)) operation,
];

void main() {
  // -- Resource description --------------------------------------------------

  checkForward(
    'StorageMode',
    StorageMode.values,
    gpu.StorageMode.values,
    (v) => v.toGpu(),
  );
  checkRoundTrip(
    'StorageMode',
    StorageMode.values,
    gpu.StorageMode.values,
    (v) => v.toGpu(),
    (v) => v.toEngine(),
  );

  // The one type whose *name* differs from flutter_gpu's, because `dart:ui`
  // already exports a `PixelFormat`. The value names are identical, which is
  // what keeps the check below meaningful.
  //
  // Over the mirrored values only: `extendedTextureFormats` is the tail
  // flutter_gpu does not have, and the group after this one holds that each
  // of those is refused by name instead.
  checkForward(
    'TextureFormat',
    mirroredFormats,
    gpu.PixelFormat.values,
    (v) => v.toGpu(),
  );
  checkRoundTrip(
    'TextureFormat',
    mirroredFormats,
    gpu.PixelFormat.values,
    (v) => v.toGpu(),
    (v) => v.toEngine(),
  );

  group('the values flutter_gpu does not have', () {
    test('every extended TextureFormat is refused by name', () {
      // Mutation: map an extended format onto the nearest PixelFormat (say
      // r16Float onto r16g16b16a16Float). It compiles, allocates, and every
      // texel lands in the wrong place; only this asks.
      for (final format in extendedTextureFormats) {
        expect(
          () => format.toGpu(),
          throwsA(
            isA<UnsupportedError>().having(
              (e) => e.message,
              'message',
              contains('TextureFormat.${format.name}'),
            ),
          ),
          reason: format.name,
        );
      }
    });

    test('every extended BlendFactor is refused as dual-source blending', () {
      // Mutation: map source1Color onto sourceColor. The draw blends with
      // the first output twice and looks almost right.
      for (final factor in extendedBlendFactors) {
        expect(
          () => factor.toGpu(),
          throwsA(
            isA<UnsupportedCapability>()
                .having(
                  (e) => e.feature,
                  'feature',
                  DeviceFeature.dualSourceBlending,
                )
                .having((e) => e.backend, 'backend', 'Impeller'),
          ),
          reason: factor.name,
        );
      }
    });

    test('min and max are refused as min-max blending', () {
      // Mutation: map max onto add. Additive is a plausible picture of max.
      for (final operation in extendedBlendOperations) {
        expect(
          () => operation.toGpu(),
          throwsA(
            isA<UnsupportedCapability>()
                .having((e) => e.feature, 'feature', DeviceFeature.minMaxBlend)
                .having((e) => e.backend, 'backend', 'Impeller'),
          ),
          reason: operation.name,
        );
      }
    });

    test('the mirrored and extended lists cover every value once', () {
      // Mutation: drop a value from `isMirrored`'s complement. The same-name
      // checks above would then skip a value nothing else maps.
      expect(
        mirroredFormats.length + extendedTextureFormats.length,
        TextureFormat.values.length,
      );
      expect(
        mirroredFactors.length + extendedBlendFactors.length,
        BlendFactor.values.length,
      );
      expect(
        mirroredOperations.length + extendedBlendOperations.length,
        BlendOperation.values.length,
      );
    });
  });

  // `TextureCoordinateSystem` used to be checked here. flutter_gpu 3.47 deleted
  // the type, so the engine did too — see `gpu_device.createTextureFromPixels`
  // for why removing it changed no picture.

  group('TextureFormat.toGpu().isCompressed', () {
    // Exactly the block-compressed tail of the enum — see the comment on
    // `TextureFormat` in `formats.dart`. `createTextureFromPixels` asks this
    // to decide `enableRenderTargetUsage`: `gpuContext.createTexture` throws
    // for a compressed format asking for render-target usage, so getting this
    // set wrong either refuses an upload flutter_gpu would have accepted or
    // lets one through that fails deep inside the allocation instead of at
    // the boundary this test checks.
    const compressed = {
      TextureFormat.bc1RGBAUNormInt,
      TextureFormat.bc1RGBAUNormIntSRGB,
      TextureFormat.bc3RGBAUNormInt,
      TextureFormat.bc3RGBAUNormIntSRGB,
      TextureFormat.bc5RGUNormInt,
      TextureFormat.bc7RGBAUNormInt,
      TextureFormat.bc7RGBAUNormIntSRGB,
      TextureFormat.etc2RGB8UNormInt,
      TextureFormat.etc2RGB8UNormIntSRGB,
      TextureFormat.etc2RGBA8UNormInt,
      TextureFormat.etc2RGBA8UNormIntSRGB,
      TextureFormat.astc4x4LDR,
      TextureFormat.astc4x4LDRSRGB,
      TextureFormat.astc8x8LDR,
      TextureFormat.astc8x8LDRSRGB,
      TextureFormat.astc4x4HDR,
      TextureFormat.astc8x8HDR,
    };

    test('is true for exactly the block-compressed values', () {
      for (final format in mirroredFormats) {
        expect(
          format.toGpu().isCompressed,
          compressed.contains(format),
          reason: '$format',
        );
      }
    });
  });

  group('TextureFormat.blockLayout against flutter_gpu\'s own numbers', () {
    // `flutter3d_hardware` states block width, height and byte cost a second
    // time — see its doc comment on `TextureBlockLayout` for why a repository
    // rule against `flutter3d_hardware` importing `flutter_gpu` makes a
    // second statement unavoidable here, rather than merely tolerated. This is
    // the check that makes the second statement worth having: a hand-written
    // number that only ever agreed with itself would not be evidence of
    // anything.
    for (final format in mirroredFormats) {
      test('$format agrees on isCompressed', () {
        expect(format.isCompressed, format.toGpu().isCompressed);
      });
      if (!format.isCompressed) continue;
      test('$format', () {
        final gpuFormat = format.toGpu();
        final layout = format.blockLayout;
        expect(layout.blockWidth, gpuFormat.blockWidth);
        expect(layout.blockHeight, gpuFormat.blockHeight);
        expect(layout.bytesPerBlock, gpuFormat.bytesPerBlock);
      });
    }
  });

  // -- Geometry --------------------------------------------------------------

  checkForward(
    'IndexType',
    IndexType.values,
    gpu.IndexType.values,
    (v) => v.toGpu(),
  );
  checkRoundTrip(
    'IndexType',
    IndexType.values,
    gpu.IndexType.values,
    (v) => v.toGpu(),
    (v) => v.toEngine(),
  );

  // -- Sampling --------------------------------------------------------------

  checkForward(
    'MinMagFilter',
    MinMagFilter.values,
    gpu.MinMagFilter.values,
    (v) => v.toGpu(),
  );
  checkRoundTrip(
    'MinMagFilter',
    MinMagFilter.values,
    gpu.MinMagFilter.values,
    (v) => v.toGpu(),
    (v) => v.toEngine(),
  );

  checkForward(
    'MipFilter',
    MipFilter.values,
    gpu.MipFilter.values,
    (v) => v.toGpu(),
  );
  checkRoundTrip(
    'MipFilter',
    MipFilter.values,
    gpu.MipFilter.values,
    (v) => v.toGpu(),
    (v) => v.toEngine(),
  );

  checkForward(
    'SamplerAddressMode',
    SamplerAddressMode.values,
    gpu.SamplerAddressMode.values,
    (v) => v.toGpu(),
  );
  checkRoundTrip(
    'SamplerAddressMode',
    SamplerAddressMode.values,
    gpu.SamplerAddressMode.values,
    (v) => v.toGpu(),
    (v) => v.toEngine(),
  );

  // -- Pass and pipeline state -----------------------------------------------
  //
  // Write-only in this engine, so there is no reverse mapping to round-trip.

  checkForward(
    'LoadAction',
    LoadAction.values,
    gpu.LoadAction.values,
    (v) => v.toGpu(),
  );
  checkForward(
    'StoreAction',
    StoreAction.values,
    gpu.StoreAction.values,
    (v) => v.toGpu(),
  );
  checkForward(
    'PrimitiveType',
    PrimitiveType.values,
    gpu.PrimitiveType.values,
    (v) => v.toGpu(),
  );
  checkForward(
    'CullMode',
    CullMode.values,
    gpu.CullMode.values,
    (v) => v.toGpu(),
  );
  checkForward(
    'WindingOrder',
    WindingOrder.values,
    gpu.WindingOrder.values,
    (v) => v.toGpu(),
  );
  checkForward(
    'PolygonMode',
    PolygonMode.values,
    gpu.PolygonMode.values,
    (v) => v.toGpu(),
  );
  checkForward(
    'CompareFunction',
    CompareFunction.values,
    gpu.CompareFunction.values,
    (v) => v.toGpu(),
  );
  // The mirrored values only, as for TextureFormat above.
  checkForward(
    'BlendFactor',
    mirroredFactors,
    gpu.BlendFactor.values,
    (v) => v.toGpu(),
  );
  checkForward(
    'BlendOperation',
    mirroredOperations,
    gpu.BlendOperation.values,
    (v) => v.toGpu(),
  );
  checkForward(
    'TextureType',
    TextureType.values,
    gpu.TextureType.values,
    (v) => v.toGpu(),
  );
  checkForward(
    'StencilOperation',
    StencilOperation.values,
    gpu.StencilOperation.values,
    (v) => v.toGpu(),
  );
  checkForward(
    'StencilFace',
    StencilFace.values,
    gpu.StencilFace.values,
    (v) => v.toGpu(),
  );

  group('StencilState', () {
    test('every field is carried across, and none is crossed with another', () {
      // Every field a different value, and the three operations three
      // different ones, so a translation that put the depth-fail operation
      // where the pass operation goes could not come back looking right.
      const ours = StencilState(
        compare: CompareFunction.notEqual,
        failOp: StencilOperation.zero,
        depthFailOp: StencilOperation.incrementWrap,
        passOp: StencilOperation.setToReferenceValue,
        readMask: 0x0F,
        writeMask: 0xF0,
      );

      final theirs = ours.toGpu();
      expect(theirs.compareFunction, gpu.CompareFunction.notEqual);
      expect(theirs.stencilFailureOperation, gpu.StencilOperation.zero);
      expect(theirs.depthFailureOperation, gpu.StencilOperation.incrementWrap);
      expect(
        theirs.depthStencilPassOperation,
        gpu.StencilOperation.setToReferenceValue,
      );
      expect(theirs.readMask, 0x0F);
      expect(theirs.writeMask, 0xF0);
    });

    test('the disabled state is flutter_gpu\'s default but for the masks', () {
      // The one deliberate difference, stated in `StencilState`'s own doc:
      // eight bits rather than thirty-two, which every stencil format here
      // makes the same value. Everything else has to agree, or a pass that
      // says "switch it off" would be saying something else on this backend.
      final defaults = gpu.StencilConfig();
      final off = StencilState.disabled.toGpu();
      expect(off.compareFunction, defaults.compareFunction);
      expect(off.stencilFailureOperation, defaults.stencilFailureOperation);
      expect(off.depthFailureOperation, defaults.depthFailureOperation);
      expect(off.depthStencilPassOperation, defaults.depthStencilPassOperation);
      expect(off.readMask & 0xFF, defaults.readMask & 0xFF);
      expect(off.writeMask & 0xFF, defaults.writeMask & 0xFF);
    });
  });

  group('SamplerOptions', () {
    test('every field is carried across, and none is crossed with another', () {
      // Deliberately asymmetric in every axis, so a mapping that swapped min
      // for mag, or width for height, could not produce the same answer.
      const ours = SamplerDescriptor(
        minFilter: MinMagFilter.linear,
        magFilter: MinMagFilter.nearest,
        mipFilter: MipFilter.linear,
        widthAddressMode: SamplerAddressMode.repeat,
        heightAddressMode: SamplerAddressMode.mirror,
      );

      final theirs = ours.toGpu();
      expect(theirs.minFilter, gpu.MinMagFilter.linear);
      expect(theirs.magFilter, gpu.MinMagFilter.nearest);
      expect(theirs.mipFilter, gpu.MipFilter.linear);
      expect(theirs.widthAddressMode, gpu.SamplerAddressMode.repeat);
      expect(theirs.heightAddressMode, gpu.SamplerAddressMode.mirror);

      expect(theirs.toEngine(), ours);
    });

    test('the defaults are flutter_gpu\'s defaults', () {
      // A different default would be a silent behaviour change at every call
      // site that leaves a field out.
      final defaults = gpu.SamplerOptions().toEngine();
      expect(defaults, const SamplerDescriptor());
    });

    test('the named samplers say what they are named after', () {
      expect(SamplerDescriptor.linearRepeat.minFilter, MinMagFilter.linear);
      expect(SamplerDescriptor.linearRepeat.magFilter, MinMagFilter.linear);
      expect(
        SamplerDescriptor.linearRepeat.widthAddressMode,
        SamplerAddressMode.repeat,
      );
      expect(
        SamplerDescriptor.linearRepeat.heightAddressMode,
        SamplerAddressMode.repeat,
      );

      expect(SamplerDescriptor.linearClamp.minFilter, MinMagFilter.linear);
      expect(SamplerDescriptor.linearClamp.magFilter, MinMagFilter.linear);
      expect(
        SamplerDescriptor.linearClamp.widthAddressMode,
        SamplerAddressMode.clampToEdge,
      );
      expect(
        SamplerDescriptor.linearClamp.heightAddressMode,
        SamplerAddressMode.clampToEdge,
      );
    });

    test('equal descriptions share one flutter_gpu object', () {
      // The point of the value equality: `bindTexture` runs several times per
      // draw, and there are hundreds of draws in a frame.
      const a = SamplerDescriptor(minFilter: MinMagFilter.linear);
      const b = SamplerDescriptor(minFilter: MinMagFilter.linear);
      expect(identical(a.toGpu(), b.toGpu()), isTrue);

      const c = SamplerDescriptor(minFilter: MinMagFilter.nearest);
      expect(identical(a.toGpu(), c.toGpu()), isFalse);
    });

    test('anisotropy is carried across as maxAnisotropy, and back', () {
      // Mutation: leave `maxAnisotropy` out of `toGpu`. flutter_gpu's default
      // is one, every bind is isotropic, and the only thing that says so is
      // the far half of `anisotropic-floor` being blurrier than recorded.
      final eight = SamplerDescriptor.trilinearRepeat.withAnisotropy(8);
      final theirs = eight.toGpu();
      expect(theirs.maxAnisotropy, 8);
      expect(theirs.minFilter, gpu.MinMagFilter.linear);
      expect(theirs.mipFilter, gpu.MipFilter.linear);
      expect(theirs.toEngine(), eight);
      expect(theirs.toEngine().anisotropy, 8);
    });

    test('the default is flutter_gpu\'s: one tap', () {
      expect(const SamplerDescriptor().toGpu().maxAnisotropy, 1);
      expect(gpu.SamplerOptions().maxAnisotropy, 1);
    });

    test('a different anisotropy is a different flutter_gpu object', () {
      // The cache is keyed on the description, so the field has to be part
      // of what "same description" means — otherwise eight taps and one
      // would share an object and whichever was asked for first would win.
      final one = SamplerDescriptor.trilinearRepeat;
      final eight = one.withAnisotropy(8);
      expect(identical(one.toGpu(), eight.toGpu()), isFalse);
      expect(identical(eight.toGpu(), one.withAnisotropy(8).toGpu()), isTrue);
    });

    test('taps on a nearest filter come back as one', () {
      // Mutation: pass `maxAnisotropy` through unconditionally. flutter_gpu
      // lets these options exist — its check lives in `bindTexture` — and
      // the engine's constructor does not, so the translation would throw
      // an assertion out of what is meant to be a lossless read-back.
      final theirs = gpu.SamplerOptions(
        minFilter: gpu.MinMagFilter.nearest,
        magFilter: gpu.MinMagFilter.linear,
        mipFilter: gpu.MipFilter.linear,
        maxAnisotropy: 8,
      );
      expect(theirs.toEngine().anisotropy, 1);
      expect(theirs.toEngine().minFilter, MinMagFilter.nearest);
      final bilinear = gpu.SamplerOptions(
        minFilter: gpu.MinMagFilter.linear,
        magFilter: gpu.MinMagFilter.linear,
        mipFilter: gpu.MipFilter.nearest,
        maxAnisotropy: 8,
      );
      expect(bilinear.toEngine().anisotropy, 1);
    });
  });

  group('the colour format the context stops reporting', () {
    // **A trap with a timer on it.** `gpu.gpuContext.defaultColorFormat`
    // answers `b8g8r8a8UNormInt` for about a second after launch and `unknown`
    // for the rest of the process — while the depth format and the MSAA
    // capability keep answering, so it does not read as a context that has gone
    // away. The three games reach their first frame inside that second; the
    // editor reads a level off the disk first and did not, so every frame threw
    // `Texture creation failed` from a descriptor whose format was `unknown`.
    test('is substituted when it has gone', () {
      expect(
        colorFormatOrFallback(TextureFormat.unknown),
        TextureFormat.b8g8r8a8UNormInt,
      );
    });

    test('and a real answer is kept exactly', () {
      for (final format in <TextureFormat>[
        TextureFormat.b8g8r8a8UNormInt,
        TextureFormat.r8g8b8a8UNormInt,
        TextureFormat.r16g16b16a16Float,
      ]) {
        expect(colorFormatOrFallback(format), format);
      }
    });
  });
}

/// The stable name of an engine value: an enum's, or an open class's
/// (`TextureFormat` and `VertexFormat` are open sets since 1.0).
String _nameOf(Object? value) => switch (value) {
  Enum(:final name) => name,
  TextureFormat(:final name) => name,
  VertexFormat(:final name) => name,
  _ => '$value',
};
