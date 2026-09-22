# Radiance `.hdr` fixtures

Three files and the floats they decode to, for `mat-17`'s own
`hdr_decoder_test.dart`.

## Where they came from, and why it matters

Written by **ImageMagick 7** on 2026-09-17, with the commands below. The
provenance is the point of the fixture rather than a footnote: a decoder
checked against a file its own encoder wrote proves that the two agree, which
is a weaker claim than it looks — `fmt-30n`'s index codec passed its own
round trip for a week while writing a byte a real decoder read as index
4294967295.

Nothing in this repository can write a `.hdr`. So these come from a program
that has written them for thirty years, and the `.rgbf` beside each one is
*that program's own reading* of the same file, dumped as raw little-endian
`float32` RGB triples, row 0 at the top. The test decodes the `.hdr` and
compares against the `.rgbf`, which makes it a comparison between two
independent implementations rather than a round trip.

```
magick -size 64x32 gradient:'#ff2000-#0040ff' gradient.hdr
magick -size 40x10 plasma:fractal             plasma.hdr
magick -size 4x4   xc:'#804020'               tiny.hdr

magick gradient.hdr -depth 32 -define quantum:format=floating-point RGB:gradient.rgbf
magick plasma.hdr   -depth 32 -define quantum:format=floating-point RGB:plasma.rgbf
magick tiny.hdr     -depth 32 -define quantum:format=floating-point RGB:tiny.rgbf
```

## What each one covers

| File | Size | Encoding | Why it is here |
|---|---|---|---|
| `gradient.hdr` | 64×32 | new-style RLE | Long runs in every channel — the path a real sky takes, and the one where a reader that interleaves the channels instead of walking each down the whole scanline gets plausible nonsense |
| `plasma.hdr` | 40×10 | new-style RLE | Noise, so the runs are short and the literal spans are long: the same path with the other branch taken |
| `tiny.hdr` | 4×4 | flat | Below eight pixels wide, where the format *requires* uncompressed quads — a reader that always looks for `0x02 0x02` reads the first pixel's red as a marker |

The one path no fixture covers is the **old-style run** — `(1, 1, 1, n)`
repeating the previous pixel — which nothing has written since about 1991.
The decoder reads it, and `hdr_decoder.dart` says so rather than leaving a
reader to assume it was tested.

## Licence

ImageMagick's generated patterns (`gradient:`, `plasma:`, `xc:`) are output
of the program rather than authored images, and carry no third-party rights.
