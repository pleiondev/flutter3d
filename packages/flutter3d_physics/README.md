# flutter3d_physics

Collision shapes, a broadphase grid, ray and overlap queries, rigid bodies and a
character controller.

The package contains no Flutter and no renderer. It runs under `dart test`, and
keeping it that way is the reason it is a separate package: if it ever needs a
widget, something has been put in the wrong package.

```dart
final world = CollisionWorld();
world.add(Collider(shape: CollisionBox(Vector3(2, 1, 2))));

final body = CharacterController(world: world, position: Vector3(0, 2, 0));
body.step(dt, wishDirection: forward, sprint: false);
```

## What the character controller is for

Walking, which is harder than falling. The controller handles slopes it can
climb and slopes it slides off, steps it can walk up without a jump, ramps whose
surface it follows, a coyote window after walking off an edge, and a buffered
jump pressed just before landing. Each of those is a decision, and each has a
test beside it saying which way it went and why.

## Ground, and the joins in it

`CollisionHeightfield` is a field of samples a body can walk on. It is the fifth
shape, and the first that is not one convex solid. A query names the box it
cares about, the shape hands back the convex pieces near it, and the plane walk
that every other query already used runs once per piece.

The joins are where this can go wrong. Where two triangles meet, each piece
ends in a vertical face that the other continues through, and a sweep that
reports one of those faces stops the body dead against a wall nobody drew. The
shape names those faces and the world refuses to contact them.
`heightfield_test.dart` holds the two measurements that catch it going wrong,
and `tool/ground_cost.dart` measures what the whole thing costs.

## Friction is one number

A body has one coefficient of friction, `RigidBody.friction`, and no static
and kinetic pair. The solver limits the sideways impulse at a contact to μ
times the normal one, whether the body is sliding or at rest, so a crate on
a slope starts to slide at the same angle it keeps sliding at. Two bodies
meeting take the geometric mean of their two μ, √(μ_a μ_b), and the larger
restitution; the C core combines them the same way. A material in the
catalogue may record both a static and a kinetic coefficient, and the one
the engine uses is the kinetic (`MechanicalProperties.friction`), or the
static where that is all it says. A pair measured on its own (`MaterialPair`)
replaces the mean.

## Two profiles: deterministic and accurate

Every stepper here takes a `SimulationProfile` (from
`flutter3d_plugin_api`). The default, `deterministic`, is what games run on:
float32 vectors, a fixed sequence of operations, and the same bits as the C
core's parity tests expect, so rollback, replay and a server's verification
by replay work. `accurate` is for a laboratory or a twin that demonstrates
rather than replays. It keeps state in doubles and lets an adaptive
Runge–Kutta integrator (Dormand and Prince's 5(4) pair, relative tolerance
1e-10) take its own steps inside the loop's fixed one. It promises nothing
about bits across platforms.

What `accurate` covers, in the Dart engine only:

- **Point masses** (`Dynamics(profile:)`). A body nothing pushes on flies
  the step on its laws: the exact parabola under gravity alone, or the
  integrator under `Dynamics.forces` (`BodyForce`, read at every stage).
  Its position and velocity are kept in doubles (`exactStateOf`) beside the
  float32 collider, and they are saved with the dynamics' state. A body in
  contact is solved as on the deterministic path and carried on in
  doubles. `projectile_test.dart` and `orbit_test.dart` hold it to the
  analytic answers: a parabola within 1e-9 m, a linear-drag throw within
  1e-8, and ten turns of a Kepler orbit with e = 0.5 within 1e-5 m and
  1e-8 of its energy.
- **Cloth** (`ClothSettings(profile:)`). The sheet is integrated, not
  stepped by XPBD. Gravity, the wind and damping are forces. A compliant
  constraint is a spring of stiffness 1/α. A constraint with no compliance
  is held by Lagrange multipliers and projected back onto its length after
  each of the integrator's steps. `pendulum_period_test.dart`: a pendulum
  released at θ₀ = 0.1 rad keeps its period within 1e-4 of the series
  over 100 periods (measured 1.7e-9), and its energy within 1e-6 of the
  swing's (measured 4.7e-8). The XPBD step at its default eight substeps
  misses the period by 4.6e-4 and loses almost all of the swing.
- **Liquids** (`FluidWorld(profile:)`). What floats or sinks is pushed by
  its velocity's own equation (lift, gravity, drag at the speed it has),
  integrated through the step. The push no longer depends on how the step
  is cut.

What it does not cover: a body's turning, and contacts between bodies,
with obstacles or between a sheet's layers, all of which are resolved as
on the deterministic path and are not held to analytic tests; the waves,
streams, pipes and particles of a liquid; and the C core, which stays
float32 (`accurate` means this Dart engine). A laboratory that a server
verifies by replay stays on `deterministic`.

## A liquid at its temperature

A `LiquidBody` has a `state` (a `MaterialState`: temperature, pressure),
and what floats in it reads the liquid's density and viscosity at that
state through the catalogue's laws (`FluidMedium.at`). Glycerol at 40 °C
is a fifth as viscous as at 20 °C, so a ball sinks through it nearly five
times as fast. With no state, or at the reference state, the numbers are
the catalogue's to the bit.

## Tolerances

`Nearly` names the four magnitudes this package compares against, because the
number itself was never what mattered. A distance nobody can perceive, the
slack between two numbers computed different ways, and a denominator guard on a
squared quantity are different questions, and they used to look identical.

---

Part of [flutter3d](https://github.com/pleiondev/flutter3d), an independent
implementation of a 3D engine for Flutter. It is not a fork or a binding of
another engine, and it is not affiliated with Google or the Flutter project. It has four
switchable rendering backends: Impeller via Flutter GPU, WebGL2, WebGPU and a
software rasteriser. It loads glTF, OBJ and `.f3d`, and has six lighting models,
shadows, bloom, skinning, animation, BVH culling and picking, plus a
deterministic fixed-step game layer with collision, navigation, positional
audio, and gamepad and touch input. Four example games (shooter, platformer,
racing, strategy) are each built on a genre package:
[`flutter3d_game_shooter`](https://pub.dev/packages/flutter3d_game_shooter),
[`flutter3d_game_platformer`](https://pub.dev/packages/flutter3d_game_platformer),
[`flutter3d_game_racing`](https://pub.dev/packages/flutter3d_game_racing),
[`flutter3d_game_strategy`](https://pub.dev/packages/flutter3d_game_strategy).
A new game starts from the editor's scaffold, which writes one from a template:
<https://flutter3d.pleion.dev/first-project/>. Documentation:
<https://flutter3d.pleion.dev>.
