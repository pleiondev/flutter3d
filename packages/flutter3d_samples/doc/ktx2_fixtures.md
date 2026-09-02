# The KTX2 fixtures under `assets/ktx2/`

Three Basis Universal (ETC1S) files, encoded by a from-source build of
`BinomialLLC/basis_universal`'s `basisu` — neither `toktx` nor `basisu` ships
as a package — and held, pixel for pixel and level by level, against that
same tool's own `-unpack` output. The transcoder in
`flutter3d/lib/src/engine/assets/ktx2/basis_universal/` is proved against
these, not against its own understanding of the format.

```
git clone --depth 1 https://github.com/BinomialLLC/basis_universal.git
cmake -G Ninja -B build -DCMAKE_BUILD_TYPE=Release -DBASISU_EXAMPLES=OFF \
  -DBASISU_BUILD_PYTHON=OFF -DBASISU_OPENCL=OFF -DBASISU_SUPPORT_ASTCENC=OFF
ninja -C build basisu
```

| File | Source | Encoder flags | What it exercises |
|---|---|---|---|
| `etc1s_gradient_quadrants.ktx2` | 8×8, four 4×4 quadrants (red, green, blue, yellow) with a small gradient in each | `-ktx2 -linear -no_multithreading` | One level, one slice; the byte layout below |
| `etc1s_alpha_mips.ktx2` | 16×16, four quadrants, alpha ramping across x | `-ktx2 -linear -no_multithreading -mipmap -force_alpha` | Five levels, each two slices (colour, then alpha as a grey image) |
| `etc1s_field_mips.ktx2` | 64×64 chequer of gradient tiles and noise tiles | `-ktx2 -linear -no_multithreading -mipmap` | Seven levels; sixteen tiles of endpoint prediction and selector runs long enough to reach the run-length path |

The expected pixels are `basisu -unpack <file> -output_path <dir>`'s
`*_RGBA32_level_N_*.png`, converted to raw RGBA bytes and stored beside the
tests as `flutter3d/test/fixtures/ktx2/<name>_level_N.rgba` (the `rgba`
images for the file with alpha, the `rgb` ones for the file without). The
8×8 file's sixty-four pixels are written into `ktx2_etc1s_test.dart` by hand
instead.

The source images were generated with Pillow rather than drawn: quadrant
colours plus `(x % 8) * 3` per channel for the small gradients, `16 + x * 15`
for the alpha ramp, and for the field `random.seed(7)` noise in every other
16×16 tile. Nothing about them matters except that an encoder given them has
more than one colour to choose a selector for.

## The byte layout of `etc1s_gradient_quadrants.ktx2`, verified

Cross-checked field by field between `basisu -info` and a hand read of the
hex dump, and it all agrees — which is how the supercompression global data
layout in `ktx2_format.dart` came to be stated rather than guessed.

| Field | Offset | Value |
|---|---|---|
| identifier | 0 | standard |
| vkFormat | 12 | 0 (undefined: Basis) |
| pixelWidth / pixelHeight | 20 / 24 | 8 / 8 |
| supercompressionScheme | 44 | 1 (BasisLZ) |
| dfdByteOffset / Length | 48 / 52 | 104 / 44 |
| kvdByteOffset / Length | 56 / 60 | 148 / 36 |
| sgdByteOffset / Length | 64 / 72 | 184 / 145 |
| level[0].byteOffset / Length | 80 / 88 | 329 / 2 |

Supercompression global data, from offset 184:

| Field | Offset | Value |
|---|---|---|
| endpointCount (u16) | 184 | 4 |
| selectorCount (u16) | 186 | 4 |
| endpointsByteLength (u32) | 188 | 44 |
| selectorsByteLength (u32) | 192 | 17 |
| tablesByteLength (u32) | 196 | 44 |
| extendedByteLength (u32) | 200 | 0 |
| ImageDesc[0].flags (u32) | 204 | 0 |
| ImageDesc[0].rgbSliceByteOffset (u32) | 208 | 0 |
| ImageDesc[0].rgbSliceByteLength (u32) | 212 | 2 |
| ImageDesc[0].alphaSliceByteOffset (u32) | 216 | 0 |
| ImageDesc[0].alphaSliceByteLength (u32) | 220 | 0 |
| endpointsData | 224 | 44 bytes |
| selectorsData | 268 | 17 bytes |
| tablesData | 285 | 44 bytes |

224 + 44 = 268, 268 + 17 = 285, 285 + 44 = 329: the codebooks end exactly where
the level's bytes begin. So the global data is a 20-byte header, then one
20-byte `ImageDesc` per image (`flags, rgbOfs, rgbLen, alphaOfs, alphaLen`,
all u32), then the three codebooks back to back — and the slice offsets are
relative to the *level's* bytes, not to this section, since `rgbSliceByteOffset`
is 0 while the level's own bytes start at 329. The files with mip chains carry
one `ImageDesc` per level, level 0 first, whatever order the levels' bytes sit
in the file.
