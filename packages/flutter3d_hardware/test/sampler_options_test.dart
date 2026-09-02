/// `SamplerOptions.anisotropy`: a count of taps, one by default, and only ever
/// above one on a sampler that blends the chain it would take them across.
///
///     flutter test test/sampler_options_test.dart
///
/// The field is a value like the five enums beside it — it takes part in
/// equality, so the Impeller translation's cache tells eight taps from one,
/// and it is checked at construction, so flutter_gpu's refusal of anisotropy
/// on a nearest filter arrives as a Dart assertion at the place the sampler
/// was built rather than as an exception out of a bind three packages away.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('one by default, on every named sampler', () {
    // Every sampler the engine bound before the field existed bound with
    // one tap. A different default here would be a changed picture in every
    // textured golden at once, with nothing in any diff to say why.
    expect(const SamplerOptions().anisotropy, 1);
    expect(SamplerOptions.linearRepeat.anisotropy, 1);
    expect(SamplerOptions.trilinearRepeat.anisotropy, 1);
    expect(SamplerOptions.linearClamp.anisotropy, 1);
    expect(SamplerOptions.nearestClamp.anisotropy, 1);
  });

  test('withAnisotropy keeps every other field', () {
    // Mutation: drop a field from `withAnisotropy`. It comes back as the
    // constructor default — nearest and clamp — and a repeating trilinear
    // floor sampler becomes a clamped nearest one with eight taps, which the
    // constructor would then refuse. Asymmetric inputs, so a swap shows too.
    const source = SamplerOptions(
      minFilter: MinMagFilter.linear,
      magFilter: MinMagFilter.linear,
      mipFilter: MipFilter.linear,
      widthAddressMode: SamplerAddressMode.repeat,
      heightAddressMode: SamplerAddressMode.mirror,
    );
    final eight = source.withAnisotropy(8);

    expect(eight.anisotropy, 8);
    expect(eight.minFilter, source.minFilter);
    expect(eight.magFilter, source.magFilter);
    expect(eight.mipFilter, source.mipFilter);
    expect(eight.widthAddressMode, source.widthAddressMode);
    expect(eight.heightAddressMode, source.heightAddressMode);
  });

  test('takes part in equality and the hash', () {
    // The whole reason the Impeller cache can be keyed on the description:
    // two samplers that differ only in taps are two flutter_gpu objects, and
    // one that compared equal to the other would serve eight taps to a bind
    // that asked for one — or one to a bind that asked for eight.
    final one = SamplerOptions.trilinearRepeat;
    final eight = one.withAnisotropy(8);
    final anotherEight = one.withAnisotropy(8);

    expect(eight, isNot(equals(one)));
    expect(eight, equals(anotherEight));
    expect(eight.hashCode, anotherEight.hashCode);
    expect(eight.toString(), contains('anisotropy: 8'));
  });

  test('is refused on a sampler that is not trilinear', () {
    // flutter_gpu's rule, held at the constructor so the failure has a Dart
    // stack pointing at the sampler rather than at a bind.
    expect(
      () => SamplerOptions.linearRepeat.withAnisotropy(4),
      throwsA(isA<AssertionError>()),
      reason: 'linearRepeat blends no mip levels',
    );
    expect(
      () => SamplerOptions(
        minFilter: MinMagFilter.nearest,
        magFilter: MinMagFilter.linear,
        mipFilter: MipFilter.linear,
        anisotropy: 2,
      ),
      throwsA(isA<AssertionError>()),
      reason: 'a nearest min filter has nothing to spread taps over',
    );
    expect(
      () => SamplerOptions.trilinearRepeat.withAnisotropy(0),
      throwsA(isA<AssertionError>()),
      reason: 'zero taps is not a sampler',
    );
    // And the shape the engine actually builds is accepted.
    expect(SamplerOptions.trilinearRepeat.withAnisotropy(16).anisotropy, 16);
  });
}
