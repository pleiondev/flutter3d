---
description: Every number a designer wants to change, where it lives, and what it is measured in.
---

# The knobs

How a game feels is a few dozen numbers, and this page says where each of them is. All of it is data on `const` classes, so changing one is a recompile and never a schema change, and none of it needs a renderer to test.

<div class="note">
<p><strong>Units are metres, seconds and radians throughout.</strong> A speed is metres per second, a rate is per second, an angle is radians, and a chance is 0 to 1. There is no scale factor anywhere: a corridor two metres wide is <code>2.0</code>, and a body that walks at <code>6.0</code> crosses it in a third of a second.</p>
</div>

## Where the numbers are

| What you want to change | Class | Package |
|---|---|---|
| Walking, gravity, jump height | `MovementTuning` | `flutter3d_physics` |
| Double jumps, dashes, wall slides, ground pounds | `RunnerTuning` | `flutter3d_game_platformer` |
| Weapons | `WeaponDef` | `flutter3d_game_shooter` |
| Monsters | `MonsterDef`, gathered into a `Bestiary` | `flutter3d_game_shooter` |
| How a car drives | `VehicleTuning`, `Tyres` | `flutter3d_game_racing` |
| How hard the AI drivers are | `AiTuning` | `flutter3d_game_racing` |
| Where the camera sits | `RigTuning`, `FollowTuning`, `ChaseTuning` | `flutter3d_game`, the two genres |
| Shadows, bloom, fog, exposure, colour | `ShadowSettings` and the rest of `RenderSettings` | `flutter3d` |

## Movement

`MovementTuning` is what every body in every genre stands on, player and monster alike.

```dart
const MovementTuning(
  walkSpeed: 6.0,            // sprintSpeed is 10.0
  groundAcceleration: 70.0,  // how fast it reaches that speed
  groundFriction: 55.0,      // and how fast it stops
  airAcceleration: 14.0,     // control in the air, deliberately much lower
  gravity: 24.0,             // 9.81 feels like a documentary
  jumpSpeed: 8.0,            // straight up, metres per second
  stepHeight: 0.4,           // a kerb it walks over instead of into
  coyoteTime: 0.1,           // a jump still counts this long after a ledge
  jumpBufferTime: 0.1,       // and this long before landing
);
```

The two forgiveness numbers at the end are the ones a player feels and cannot name. Set both to zero and the game plays as if it were fighting you, with nothing on screen having changed.

<div class="why">
<p><code>CharacterController.tuning</code> is <strong>not <code>final</code></strong>. That is the whole of what ice, mud, water, a low-gravity room and a slow-effect are made of: assign a different constant and the body changes on the next step, with no state to migrate and nothing to unwind when the effect ends.</p>
</div>

## What a platformer adds on top

`RunnerTuning` is the second layer, and it is large because a platformer is a verb list. A sample of it, with the shipped defaults:

| | | |
|---|---|---|
| `jumpSpeed` | 9.5 | Higher than the base body's 8.0 |
| `airJumps`, `airJumpSpeed` | 1, 8.2 | The double jump, weaker than the first |
| `jumpCut` | 0.45 | Releasing the button keeps this fraction of the rise, which is what makes a tap a small hop |
| `coyoteTime`, `jumpBufferTime` | 0.12, 0.12 | Slightly more forgiving than the base body |
| `dashSpeed`, `dashCooldown` | 18.0, 0.55 | |
| `wallSlideSpeed`, `wallJumpUp`, `wallJumpPush` | 3.2, 9.0, 7.5 | Falling speed against a wall, and the two halves of the jump off it |
| `stompBounce`, `stompBounceHeld` | 7.5, 11.0 | Landing on something, and landing on it holding jump |
| `mantleLow`, `mantleHigh`, `mantleReach` | 0.35, 1.5, 0.45 | The band of ledge heights it will pull itself onto |

## Weapons and monsters

A weapon is a `WeaponDef`, and a game's arsenal is a list of them. The five it insists on are `name`, `behaviour`, `ammo`, `damage` and `shotsPerSecond`; everything else has a default that means "the simple case".

The shipped shotgun, from `flutter3d_game_shooter`'s sample arsenal:

```dart
const WeaponDef(
  name: 'Shotgun',
  behaviour: HitscanBehaviour(),   // or MeleeBehaviour, or ProjectileBehaviour
  ammo: AmmoType.shells,
  damage: 11.0,                    // per ray
  shotsPerSecond: 1.4,
  rayCount: 8,                     // what makes it a shotgun
  spread: 0.10,                    // radians
  range: 60.0,
  falloffStart: 6.0,               // full damage to here
  falloffEnd: 26.0,                // and a floor of minimumDamageFraction past here
  minimumDamageFraction: 0.2,
  knockback: 2.0,
  recoil: 0.05,
  recoilRecovery: 4.5,
  loudness: 28.0,
);
```

`loudness` is the one worth knowing about: firing is a noise with a radius in metres, and it is what wakes the room next door. A quiet weapon is a design decision rather than an audio setting.

`AmmoType.none` exists so a starting weapon can never run out. A player stranded with nothing to fire is a player reloading a save.

A monster is a `MonsterDef` — `health`, `speed`, `attack`, `radius`, `height`, and then `sightRange` (26 m), `turnRate` (6.0 rad/s), `painChance` (1.0) and `painCooldown` (0.2). The last two are what make a heavy monster feel heavy: a `painChance` under one means some hits do not interrupt it, and it keeps walking at you.

The catalogue is handed to `Bestiary` rather than reached for, so a second shooter brings its own and inherits none of this one's.

## Cars

`VehicleTuning` is a car, and `Tyres` is what it is standing on. The engine numbers are the obvious half:

| | | |
|---|---|---|
| `maxSpeed`, `maxReverse` | 52.0, 12.0 | m/s: about 187 km/h |
| `enginePush`, `brakeStrength` | 14.0, 26.0 | Stopping is harder than going, as it is in a real car |
| `maxSteer`, `steerFalloff` | 0.62, 26.0 | Radians of lock, and how much of it is taken away by speed |
| `wheelBase` | 2.7 | Metres between axles; what decides the turning circle |
| `rollingResistance`, `holdSpeed`, `holdSlope` | 0.9, 0.7, 1.2 | Why a parked car stays parked |

Those last three are a repaired bug rather than a feature: the circuit's starting grid sits on a one-in-fifty rise, and a car with no rolling resistance and no static hold rolled backwards off it, gaining speed, from the moment the level loaded. `holdSlope` is what stops the fix becoming a handbrake that is always on.

Grip lives in `Tyres` instead, and `Tyres.road` is the shipped set. That split is deliberate: a wet race is the same car with different tyres.

## Difficulty, as a number

`AiTuning.skill` is 1.0, and it scales the rest. Under it sit the numbers that decide *how* a driver is fast: `brakeHorizon` (45 m of lookahead for a corner), `corneringGrip` (14.0, how much the driver believes the car has), `lookAheadPerSpeed` (0.55) and `rubberBandClamp` (0.22, the ceiling on catching up).

<div class="warn">
<p>Rubber banding is capped at 22% on purpose. A rubber band with no ceiling turns every race into the same race, and players notice within two laps — not as "the AI is cheating", but as "nothing I do matters".</p>
</div>

## The picture

`RenderSettings` holds the look, and most of it is off by default because most of it costs. `exposure` is 1.6 and `tonemap` is on; `bloom`, `fog`, `look` (contrast, saturation, temperature, vignette, grain) and `sky` are each their own settings object. `reflections` and `ambientOcclusion` both default to `enabled: false`.

`ShadowSettings` is where the two expensive numbers are:

- `resolution` (1024) is the directional light's map, split into `cascades` (3) tiles.
- `cubeResolution` (512) is the atlas point and spot lights share, six faces across and one row per shadowed light.

<div class="warn">
<p><strong>Those two are separate settings and used to be one.</strong> Sizing the cube atlas from the sun's number put 402 MB of texture on the GPU and made the racing game unplayable in a browser for months. Raise <code>resolution</code> for crisper sun shadows; raise <code>cubeResolution</code> only when you can see the stair-stepping, and know that it costs six faces times the number of lit rooms.</p>
</div>

## Changing them honestly

Every class on this page is reachable from a plain `test()` with no window and no GPU, because the packages they live in import no renderer. That is the difference between tuning and guessing: a jump height that has to clear a specific ledge, an AI lap that has to come in under a time, a car that has to still be on the grid after ten seconds — each is a test that runs in milliseconds and says what happened, where a playthrough shows you a frame and leaves you to judge it.

[Testing](/reference/testing/) is how this repository does that, and the racing package's `test/parked_test.dart` is a short worked example of a feel bug caught that way.
