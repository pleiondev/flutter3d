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
`packages/flutter3d_physics_native` on 2026-10-13 at `e94a04f79`: 22
digests on each of the three columns, every one equal to the VM's and to
the first run of the day (on top of `1a171e87f` with the two fixes below),
101 commits and 52 files of the physics, simulation and game packages
earlier. The
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
| shooter, start | `1609f295` | to measure | to measure | to measure | to measure | = | = |
| shooter, 100 | `61209dbe` | to measure | to measure | to measure | to measure | = | = |
| shooter, 200 | `f45d5fdc` | to measure | to measure | to measure | to measure | = | = |
| shooter, 300 | `0a096294` | to measure | to measure | to measure | to measure | = | = |
| shooter, 400 | `cff9df36` | to measure | to measure | to measure | to measure | = | = |
| shooter, 500 | `94ee7399` | to measure | to measure | to measure | to measure | = | = |
| shooter, 600 | `c933e8cc` | to measure | to measure | to measure | to measure | = | = |
| shooter, 700 | `12f45368` | to measure | to measure | to measure | to measure | = | = |
| shooter, 800 | `2ca39afb` | to measure | to measure | to measure | to measure | = | = |
| shooter, 900 | `ed68f54a` | to measure | to measure | to measure | to measure | = | = |
| shooter, 1 000 | `9112d28f` | to measure | to measure | to measure | to measure | = | = |

**dart2js and dart2wasm agree with the native library on all 22 digests.**
The core compiled to WebAssembly by clang steps both worlds to the bits the
ARM64 library does, and the game compiled to JavaScript stages and saves
them as the VM does.

That took two fixes on the Dart side, where under dart2js every number is a
double. The first run (2026-10-12, `82b03ec80`) agreed on the racing tape
and not on the shooter's, from before the first step:

1. **The crypt was staged with other wood.** `CryptWorld.seedOf`
   (`packages/flutter3d_demo_content/lib/crypt.dart`) is FNV-1a, and its
   multiply `(h ^ unit) * 0x01000193` needs 57 bits; dart2js rounded it to
   53, so `seedOf('crypt')` was 1555578911 on the VM and 2200777500 in
   JavaScript, and the seed placed 17 crates and barrels against 16. The
   multiply is now done in two 16-bit halves, each product under 2^53, and
   both platforms answer 1555578911.
2. **The dynamics' save named its standing colliders in text.**
   `NativeDynamics._keyOf` (`packages/flutter3d_physics_native/lib/src/native_dynamics.dart`)
   wrote `'${shape.runtimeType} ${half.x} …'`: `CollisionBox 7.0 0.5 7.0 …`
   on the VM and `CollisionBox 7 0.5 7 …` under dart2js, and a minified
   release build names the type something else again. The key is now a
   kind number and each float's 64 bits in hex. A save written before still
   restores on the VM that wrote it: the old key is looked up when the new
   one names nothing.

**The shooter's VM digests moved with the second fix, and only because of
it.** The digest is of the run's whole save, and the save carries each
standing collider's key, so a new spelling of the key is a new digest for
the same world. Played again with the old key and the new `seedOf`, the VM
gives the eleven shooter digests of the first run exactly (`9668a5c4` to
`55f6d44e`): the seed's answer on the VM did not change, and no step did.
The racing tape's digests did not move, so its save carries no such key.

P3's rule for a mismatch is `-ffp-contract=off` on every target and a
retry, then an architecture field in `WireHello` if it still differs.
Neither was needed: the core already builds with `-ffp-contract=off`, and
the difference was in Dart code the fixes made portable.

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
