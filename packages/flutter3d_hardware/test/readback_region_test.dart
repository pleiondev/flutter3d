/// What `readbackRegionOf` refuses, and what it lets through.
///
///     flutter test test/readback_region_test.dart
///
/// The conformance check `a readback returns the frame before` asks the same
/// questions of a live device; this asks them of the rule itself, which is the
/// one place the three backends share their refusals — and the place a new
/// refusal is added, so it is the place a test of one belongs.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter_test/flutter_test.dart';

TextureHandle _texture({
  TextureFormat format = TextureFormat.r8g8b8a8UNormInt,
  StorageMode storageMode = StorageMode.devicePrivate,
  int sampleCount = 1,
  TextureType type = TextureType.texture2D,
}) => TextureHandle(
  backend: 'not a texture',
  width: 8,
  height: 6,
  format: format,
  sampleCount: sampleCount,
  storageMode: storageMode,
  type: type,
);

/// An [ArgumentError] whose message names [what], which is the part a caller
/// reads.
Matcher _refusalNaming(String what) => throwsA(
  isA<ArgumentError>().having(
    (ArgumentError e) => '${e.message}',
    'message',
    contains(what),
  ),
);

void main() {
  test('the whole texture when no region is given, the region otherwise', () {
    expect(
      readbackRegionOf(_texture(), null),
      const ScreenRect(width: 8, height: 6),
    );
    const corner = ScreenRect(x: 6, y: 3, width: 2, height: 3);
    expect(readbackRegionOf(_texture(), corner), corner);
  });

  test('every layout it admits is a linear eight-bit RGBA one', () {
    // The set itself, not a sample of it: what `readbackFormats` promises is
    // that a backend copying these bytes straight out has told the truth on
    // every one of them, and nothing but a linear eight-bit layout can. A
    // format added here without a conformance pass over it is the defect this
    // catches. Mutation: put an sRGB twin back — the layout check fails, and
    // so does the refusal below.
    expect(readbackFormats, <TextureFormat>{
      TextureFormat.r8g8b8a8UNormInt,
      TextureFormat.b8g8r8a8UNormInt,
    });
    for (final format in readbackFormats) {
      expect(
        readbackRegionOf(_texture(format: format), null),
        const ScreenRect(width: 8, height: 6),
        reason: format.name,
      );
    }
  });

  test('refuses an sRGB layout, and says why that one is different', () {
    // Eight bits per channel and still not the same bytes everywhere: one
    // backend reads an sRGB texture through `toByteData`, which may hand back
    // the linear values the encoding stands for, and another reads the stored
    // bytes as they sit. The message has to send the caller somewhere else
    // than the float one does — the bytes exist, it is the view of them that
    // is wrong — so it is checked by what it names.
    for (final format in const <TextureFormat>[
      TextureFormat.r8g8b8a8UNormIntSRGB,
      TextureFormat.b8g8r8a8UNormIntSRGB,
    ]) {
      expect(
        () => readbackRegionOf(_texture(format: format), null),
        _refusalNaming('sRGB texture is not '),
        reason: format.name,
      );
    }
  });

  test('refuses any other format, by name', () {
    // The engine's own HDR colour, which is the texture a caller is most
    // likely to hand over by mistake — and the one WebGL2 would answer with
    // zeros and no error. Mutation: drop the format check — the half-float
    // texture is accepted and three backends convert three ways.
    expect(
      () => readbackRegionOf(
        _texture(format: TextureFormat.r16g16b16a16Float),
        null,
      ),
      _refusalNaming('r16g16b16a16Float'),
    );
    expect(
      () => readbackRegionOf(_texture(format: TextureFormat.r32Float), null),
      _refusalNaming('r32Float'),
    );
  });

  test('refuses tile memory, multisampling and a cube', () {
    expect(
      () => readbackRegionOf(
        _texture(storageMode: StorageMode.deviceTransient),
        null,
      ),
      _refusalNaming('deviceTransient'),
    );
    expect(
      () => readbackRegionOf(_texture(sampleCount: 4), null),
      _refusalNaming('x4'),
    );
    expect(
      () => readbackRegionOf(_texture(type: TextureType.textureCube), null),
      _refusalNaming('textureCube'),
    );
  });

  test('refuses a region that is not inside the texture', () {
    for (final region in const <ScreenRect>[
      ScreenRect(x: 4, y: 4, width: 8, height: 2),
      ScreenRect(x: -1, width: 2, height: 2),
      ScreenRect(width: 0, height: 2),
      ScreenRect(y: 5, width: 1, height: 2),
    ]) {
      expect(
        () => readbackRegionOf(_texture(), region),
        _refusalNaming('8x6'),
        reason: '$region',
      );
    }
  });
}
