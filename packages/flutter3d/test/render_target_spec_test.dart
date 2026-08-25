import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const base = RenderTargetSpec(
    width: 1920,
    height: 1080,
    format: TextureFormat.r16g16b16a16Float,
  );

  group('what makes two targets interchangeable', () {
    test('the same description is the same key', () {
      const other = RenderTargetSpec(
        width: 1920,
        height: 1080,
        format: TextureFormat.r16g16b16a16Float,
      );
      expect(other, base);
      expect(other.hashCode, base.hashCode);
      // The pool is a map lookup, so equality is the whole mechanism.
      expect(<RenderTargetSpec, int>{base: 1}[other], 1);
    });

    test('every field participates', () {
      expect(
        const RenderTargetSpec(
          width: 1920,
          height: 1081,
          format: TextureFormat.r16g16b16a16Float,
        ),
        isNot(base),
      );
      expect(
        const RenderTargetSpec(
          width: 1920,
          height: 1080,
          format: TextureFormat.r8g8b8a8UNormInt,
        ),
        isNot(base),
      );
      expect(
        const RenderTargetSpec(
          width: 1920,
          height: 1080,
          format: TextureFormat.r16g16b16a16Float,
          sampleCount: 4,
        ),
        isNot(base),
      );
      expect(
        const RenderTargetSpec(
          width: 1920,
          height: 1080,
          format: TextureFormat.r16g16b16a16Float,
          storageMode: StorageMode.deviceTransient,
        ),
        isNot(base),
      );
    });
  });

  group('the bloom chain', () {
    test('halving keeps everything but the size', () {
      final half = base.scaled(2);
      expect(half.width, 960);
      expect(half.height, 540);
      expect(half.format, base.format);
      expect(half.sampleCount, base.sampleCount);
      expect(half.storageMode, base.storageMode);
    });

    test('a chain of halvings never reaches zero', () {
      // A long enough chain would otherwise ask for a zero-sized texture, and
      // that fails inside the driver rather than as an exception.
      var spec = base;
      for (var i = 0; i < 20; i++) {
        spec = spec.scaled(2);
        expect(spec.width, greaterThanOrEqualTo(1));
        expect(spec.height, greaterThanOrEqualTo(1));
      }
      expect(spec.width, 1);
      expect(spec.height, 1);
    });

    test('an odd size rounds down rather than up', () {
      const odd = RenderTargetSpec(
        width: 1601,
        height: 541,
        format: TextureFormat.r16g16b16a16Float,
      );
      expect(odd.scaled(2).width, 800);
      expect(odd.scaled(2).height, 270);
    });
  });
}
