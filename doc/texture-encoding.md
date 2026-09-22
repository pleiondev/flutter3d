# Texture encoding: what to ship, and what not to build

`fmt-23`'s own row asks for a decision between three ways of getting Basis
Universal ETC1S out of this repository — port the encoder to Dart, call the
native one over FFI, or run it on a server — and for a measurement to decide
on. This is both. Measured 2026-09-17 on an Apple M3 Pro.

## The measurement

One 1024×1024 albedo, generated rather than downloaded so the numbers can be
reproduced: smooth gradients over most of it, a checkerboard of noise tiles,
and one hard vertical edge. That mix matters — a flat texture flatters every
compressor and a noise field flatters none.

Eleven mip levels, stopping at 4×4 where a block format runs out of whole
blocks.

| Path | Bytes | bits/texel | Encode | Who encodes it |
|---|---|---|---|---|
| PNG, the source | 761,295 | 5.81 | — | anything |
| **ETC1S `.ktx2`** | **99,080** | **0.567** | 707 ms | `basisu`, C++ |
| UASTC `.ktx2` | 834,895 | 4.777 | 2,465 ms | `basisu`, C++ |
| BC1 `.ktx2` | 699,344 | 5.336 | 108 ms | this repository |
| BC3 `.ktx2` | 1,398,392 | 10.669 | 131 ms | this repository |
| ETC2 RGB8 `.ktx2` | 699,344 | 5.336 | 1,353 ms | this repository |
| ASTC 4×4 `.ktx2` | 1,398,392 | 10.669 | 158 ms | this repository |
| BC1 payload + `zstd -19` | 252,573 | 1.926 | — | anything |
| ETC2 payload + `zstd -19` | 262,951 | 2.005 | — | anything |

Two numbers decide everything below:

- **ETC1S is 7.06× smaller than the smallest thing this repository writes.**
- **It is 2.55× smaller than that same thing with `zstd -19` over it** — and
  KTX2 has a supercompression field for exactly that, which this repository's
  writer sets to "none" today.

## What ETC1S actually saves, and what it does not

It saves **download**, not memory. An ETC1S file is a codebook of endpoints
and selectors; the GPU never sees it. At load it transcodes to whatever the
device wants — BC1 on a desktop, ETC1 on an older Android — and the result is
5.33 bits/texel in VRAM, which is the same as the BC1 file in the table
above. A game that is tight on memory gains nothing from it. A game whose
first load is over a phone network gains sevenfold.

That is the whole case, and it is a real one: the web build's first visit
downloads every texture.

## The decision: an offline tool, not a port and not a service

**Do not port the encoder to Dart.** The cost is measurable rather than a
feeling. The *transcoder* — the read half, already in this tree as
`etc1s_transcoder.dart` — is 498 lines of Dart ported from a 45,962-line
`basisu_transcoder.cpp`, and that was the tractable half: it is a decoder,
with a specification and three fixture files to be held against. The encoder
is 120,697 lines across 31 files; its core alone — `basisu_comp`,
`basisu_frontend`, `basisu_backend` — is 11,285. Worse, it is not a
specification but a *search*: clusterisation, endpoint and selector codebook
generation, rate-distortion optimisation. A port would be judged on output
quality against a reference that has been tuned for a decade, and there is no
fixture that says "this encoder is good enough", only ones that say "this
decoder is correct".

**Do not run it as a service.** A texture is the largest thing a project
holds and the one a person iterates on most; a round trip to a server for
each save turns a tight loop into a network. It also puts an artist's
unreleased work on somebody else's machine, which is a decision nobody asked
for.

**Do call the native encoder offline**, from the build and the export path,
the way `impellerc` is already called for shaders. `basisu` builds from
source in under a minute with CMake and Ninja — this repository's own
`packages/flutter3d_samples/doc/ktx2_fixtures.md` already documents the exact
invocation, because the KTX2 fixtures were made that way. What that costs is
a build-time dependency on a native binary, which this repository already
has three of.

The web build is unaffected: it *reads* ETC1S, and reading is the half
already ported.

## What to do first, which is not ETC1S

**Turn on KTX2 supercompression.** The table says `zstd -19` over a BC1
payload is 2.77× for no new dependency, no new encoder and no quality loss
at all — it is the same blocks, packed. KTX2 has the field; the writer sets
it to zero. That is a smaller piece of work than anything else on this page
and it recovers more than a third of what ETC1S would.

Then, if the download budget still says so, add the offline ETC1S path for
the textures that are shipped rather than edited.

## What was not measured

- **Quality.** Every number here is a size. ETC1S at its default quality
  (128) is visibly softer than BC1 on the noise tiles; deciding *how much*
  softer needs a perceptual metric and a decision about what is acceptable,
  which is a different piece of work from this one.
- **Transcode time on a phone.** The read half is ported and tested, and
  nobody has timed it on the A55 — the same device `p0-03` and `pro-sc-11n`
  are waiting for.
- **UASTC.** It is in the table because the same tool produces it, and it is
  not a candidate: at 4.777 bits/texel it is barely smaller than the BC1 this
  repository already writes, and its case is quality rather than size.
