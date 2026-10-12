# The C core across platforms

P3 of the release proof: the racing and shooter tapes played on the physics
core for 1 000 steps, the world's digest every 100 steps, on every target a
game ships to. The threshold is every digest bitwise equal on every column.
ARCHITECTURE §9.3 holds the Dart maths to the same question; this holds the
core and the games over it.

## What is played

`packages/flutter3d_physics_native/tool/tape_parity/tape_play.dart`:

- **The racing tape** (`site/assets/samples/racing.f3drun`, 600 steps) on
  the ring circuit (`apps/flutter3d_demo_racing/assets/tracks/ring.json`)
  through `RacingHeadlessGame`, and **the shooter tape**
  (`site/assets/samples/shooter.f3drun`, 220 steps) in the crypt
  (`apps/flutter3d_demo_dungeon/assets/levels/crypt.json`) through
  `ShooterHeadlessGame`, both on the core (`startPhysics(asked: 'native')`;
  a target that would fall back to the Dart reference fails instead).
- Each run starts from the recording's own start (`RestorableRun.restore`)
  and plays the tape looped: when it ends, its frames start again into the
  same run.
- **The world's digest** is `StateDigest` of the run's whole save, the one a
  `.f3drun` checkpoint holds and rollback compares machines by: the core's
  bodies, as its snapshot, and everything the game keeps beside them.

## The table

`tool/digest_platforms.sh tapes vm dart2js dart2wasm`, run from
`packages/flutter3d_physics_native` on 2026-10-12 at `82b03ec80`. The
reference column is this Mac (Apple clang, ARM64, the library the package's
hook builds); a cell that agrees with it reads "=".

| Tape, step | macOS clang/ARM64 | clang/ARM64 Android | clang/ARM64 iOS | clang/x64 Linux | MSVC/x64 | dart2js | dart2wasm |
|---|---|---|---|---|---|---|---|
| racing, start | `dcb02509` | to measure | to measure | to measure | to measure | = | = |
| racing, 100 | `419317c5` | to measure | to measure | to measure | to measure | = | = |
| racing, 200 | `f32b37ae` | to measure | to measure | to measure | to measure | = | = |
| racing, 300 | `ab0b3b5d` | to measure | to measure | to measure | to measure | = | = |
| racing, 400 | `df1977e6` | to measure | to measure | to measure | to measure | = | = |
| racing, 500 | `b65ea297` | to measure | to measure | to measure | to measure | = | = |
| racing, 600 | `4b917ab1` | to measure | to measure | to measure | to measure | = | = |
| racing, 700 | `b1b07677` | to measure | to measure | to measure | to measure | = | = |
| racing, 800 | `646a606b` | to measure | to measure | to measure | to measure | = | = |
| racing, 900 | `526cce31` | to measure | to measure | to measure | to measure | = | = |
| racing, 1 000 | `de0f4cdf` | to measure | to measure | to measure | to measure | = | = |
| shooter, start | `9668a5c4` | to measure | to measure | to measure | to measure | `80b3f6be` | = |
| shooter, 100 | `30df01c3` | to measure | to measure | to measure | to measure | `ecacde0a` | = |
| shooter, 200 | `b85e2381` | to measure | to measure | to measure | to measure | `a1e6db78` | = |
| shooter, 300 | `85aeb5e3` | to measure | to measure | to measure | to measure | `bae76e2f` | = |
| shooter, 400 | `b7e914d7` | to measure | to measure | to measure | to measure | `61a0758b` | = |
| shooter, 500 | `ce6e922b` | to measure | to measure | to measure | to measure | `ecba9253` | = |
| shooter, 600 | `d6cc77a1` | to measure | to measure | to measure | to measure | `d20da751` | = |
| shooter, 700 | `8736077d` | to measure | to measure | to measure | to measure | `fe4675b1` | = |
| shooter, 800 | `96c56352` | to measure | to measure | to measure | to measure | `59f3638e` | = |
| shooter, 900 | `9e6c874b` | to measure | to measure | to measure | to measure | `935752d7` | = |
| shooter, 1 000 | `55f6d44e` | to measure | to measure | to measure | to measure | `ac51ce3a` | = |

**dart2wasm agrees with the native library on all 22 digests**: the core
compiled to WebAssembly by clang steps both worlds to the bits the ARM64
library does. **dart2js agrees on the racing tape and not on the shooter's,
from before the first step**, and the core is not why: the same WebAssembly
core agrees under dart2wasm. Two things on the Dart side differ under
dart2js, where every number is a double:

1. **The crypt is staged with other wood.** `CryptWorld.seedOf`
   (`packages/flutter3d_demo_content/lib/crypt.dart`) is FNV-1a with the
   multiply `(h ^ unit) * 0x01000193`, whose product needs 56 bits; under
   dart2js it is rounded to 53, so `seedOf('crypt')` is 1555578911 on the VM
   and 2200777500 in JavaScript, and the crates and barrels the seed places
   differ (17 pieces against 16). The multiply wants splitting into 16-bit
   halves, as a hash that must agree across platforms does.
2. **The dynamics' save names its standing colliders in text.**
   `NativeDynamics._keyOf` (`packages/flutter3d_physics_native/lib/src/native_dynamics.dart`)
   writes `'${shape.runtimeType} ${half.x} …'`: `CollisionBox 7.0 0.5 7.0 …`
   on the VM and `CollisionBox 7 0.5 7 …` under dart2js, where `7.0` prints
   as `7` — and a minified release build names the type something else
   again. Two worlds in the same state then save to different bytes, and a
   save written by one cannot be matched by key in the other. The key wants
   the floats' bits and a kind number in place of the text.

P3's rule for a mismatch is `-ffp-contract=off` on every target and a
retry, then an architecture field in `WireHello` if it still differs. Neither
applies here: the core already builds with `-ffp-contract=off`, and the
difference is in Dart code that a fix makes portable. The dart2js column is
to be measured again once both are fixed; until then rollback between a
dart2js build and any other is not proven for the shooter.

## To measure

Each command runs from `packages/flutter3d_physics_native` and prints one
line per target, failing when a target's digests differ from the first
target's; the lines are kept in `build/tape_parity/<target>.txt`.

| Column | Where | Command |
|---|---|---|
| clang/ARM64 Android | the Galaxy A55 over adb | `tool/digest_platforms.sh tapes vm device:<adb-serial>` |
| clang/ARM64 iOS | a named iPhone, cabled, signed for development | `tool/digest_platforms.sh tapes vm device:<iphone-udid>` |
| clang/x64 Linux | an x86-64 Linux host with Flutter, Chrome and clang | `tool/digest_platforms.sh tapes vm`, its `vm.txt` compared with this table's first column |
| MSVC/x64 | a Windows x64 host with Flutter and Visual Studio's C++ build tools, in Git Bash (the package's hook builds with MSVC there) | `tool/digest_platforms.sh tapes vm`, as for Linux |

A device target is played through the racing demo, which has both games:
the script copies `tool/tape_parity/tape_digests_device_test.dart` into the
demo's `integration_test/` for the run (`flutter test -d` runs a file on the
device only from there) and hands the tapes in as one define, so the phone
reads nothing from the host's disk. The route was tried on this Mac's
desktop, `tapes vm device:macos`: the racing demo built for macOS, and all
22 digests equal the VM's.
