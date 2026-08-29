---
description: Fourteen steps from an empty project to a playable first-person shooter — weapons, monsters that path around corners, an inventory, locked doors, saves and a HUD.
---

# Tutorial: build a shooter

Fourteen steps. Every one of them runs, and the first nine need no GPU at all — the simulation is headless, which is how you find out whether the game works before deciding what it looks like.

<div class="goal">
<ul>
<li>A first-person shooter with four weapons across hitscan, melee and projectile</li>
<li>Three monsters with a six-state brain that paths around corners</li>
<li>Pickups, keys, locked doors, lifts and an exit, all authored in a level file</li>
<li>A view model, a HUD, positional audio, particles and a save file</li>
<li>A headless test that plays the level to its exit</li>
</ul>
</div>

## Set the project up {.step}

```yaml
dependencies:
  flutter:
    sdk: flutter

  flutter3d_impeller: ^0.4.0
  flutter3d:          ^0.4.0
  flutter3d_game:     ^0.4.0
  flutter3d_game_shooter:  ^0.4.0
  flutter3d_bridge:   ^0.4.0
  flutter3d_audio:    ^0.4.0
  flutter3d_particles:^0.4.0
  vector_math: ^2.2.0

dev_dependencies:
  flutter_test: { sdk: flutter }
  # Only the tests use it, and only to draw a frame without a GPU.
  flutter3d_cpu: ^0.4.0
```

Set `FLTEnableFlutterGPU` and `FLTEnableImpeller` in `macos/Runner/Info.plist`, and build the shader bundle. Both are covered in the [quickstart](/quickstart/).

<div class="warn">
<p>The versions come from <a href="https://pub.dev/publishers/pleion.dev/packages">pub.dev</a>. Working against a checkout instead — for engine changes of your own — means swapping each line for a <code>path:</code> into it. <a href="/first-project/">Your first project</a> covers the deployment-target trap that lives beside the pubspec.</p>
</div>

## Decide what a weapon is {.step}

Before any code that draws. A weapon is a value, so the whole arsenal is a `const` list and every number in it is one you can change and re-run a test against.

```dart
abstract final class Weapons {
  // Free, short, and the reason running out of ammo is a setback rather than
  // a dead end.
  static const WeaponDef fists = WeaponDef(
    name: 'Fists',
    behaviour: MeleeBehaviour(),
    ammo: AmmoType.none,
    damage: 20.0,
    shotsPerSecond: 2.0,
    range: 2.2,
    automatic: true,
  );

  static const WeaponDef pistol = WeaponDef(
    name: 'Pistol',
    behaviour: HitscanBehaviour(),
    ammo: AmmoType.bullets,
    damage: 14.0,
    shotsPerSecond: 4.0,
    range: 120.0,
    falloffStart: 25.0,
    falloffEnd: 70.0,
    minimumDamageFraction: 0.4,
  );

  // Eight pellets, and all of the reason to close the distance.
  static const WeaponDef shotgun = WeaponDef(
    name: 'Shotgun',
    behaviour: HitscanBehaviour(),
    ammo: AmmoType.shells,
    damage: 11.0,
    shotsPerSecond: 1.4,
    rayCount: 8,
    spread: 0.10,
    range: 60.0,
    falloffStart: 6.0,
    falloffEnd: 26.0,
    minimumDamageFraction: 0.2,
    knockback: 2.0,
  );

  static const WeaponDef rocketLauncher = WeaponDef(
    name: 'Rocket Launcher',
    behaviour: ProjectileBehaviour(),
    ammo: AmmoType.rockets,
    damage: 90.0,
    shotsPerSecond: 0.9,
    range: 200.0,
    knockback: 9.0,
    projectileSpeed: 34.0,
    splashRadius: 4.5,
    splashMinimumFraction: 0.15,
  );

  /// In keyboard order: slot n is `all[n]`.
  static const List<WeaponDef> all = <WeaponDef>[
    fists, pistol, shotgun, rocketLauncher,
  ];
}
```

<div class="why">
<p>Slot and index are the same thing, so nothing maps between them. The moment they diverge, "press 3" and "the third weapon" become two facts that can disagree, and the disagreement only shows up after somebody adds a weapon in the middle.</p>
</div>

## Decide what a monster is {.step}

A monster's attack is a `WeaponDef` — the same type the player's shotgun is. That is what makes a claw, a fireball and a rocket one code path.

```dart
abstract final class Monsters {
  static const MonsterDef runner = MonsterDef(
    name: 'runner', health: 45.0, speed: 5.4,
    radius: 0.35, height: 1.7, sightRange: 24.0,
    attack: WeaponDef(
      name: 'claws', behaviour: MeleeBehaviour(), ammo: AmmoType.none,
      damage: 9.0, shotsPerSecond: 1.6, range: 1.9, automatic: true,
    ),
  );

  // Keeps its distance and throws something slow enough to dodge, which is
  // what makes the room's geometry matter.
  static const MonsterDef shooter = MonsterDef(
    name: 'shooter', health: 60.0, speed: 3.0,
    radius: 0.38, height: 1.8, sightRange: 30.0,
    attack: WeaponDef(
      name: 'fireball', behaviour: ProjectileBehaviour(), ammo: AmmoType.none,
      damage: 22.0, shotsPerSecond: 0.55, range: 30.0,
      projectileSpeed: 13.0, splashRadius: 2.2, splashMinimumFraction: 0.2,
    ),
  );

  // Slow, heavy, and largely indifferent to being shot.
  static const MonsterDef tank = MonsterDef(
    name: 'tank', health: 320.0, speed: 2.2,
    radius: 0.62, height: 2.4, sightRange: 22.0,
    painChance: 0.15, painCooldown: 1.4, hurtDuration: 0.18,
    attack: WeaponDef(
      name: 'slam', behaviour: MeleeBehaviour(arcDegrees: 100.0),
      ammo: AmmoType.none, damage: 34.0, shotsPerSecond: 0.7,
      range: 2.6, automatic: true,
    ),
  );

  static const Map<String, MonsterDef> byName = <String, MonsterDef>{
    'runner': runner, 'shooter': shooter, 'tank': tank,
  };
}
```

`painChance` and `painCooldown` are what stop a tank from being staggered into a corner by a pistol: it flinches 15% of the time and no more often than every 1.4 s, so it keeps coming.

## Compose the level vocabulary {.step}

There is no ready-made registry. A game names what its levels may contain, and **the same registry validates a document and spawns it**, so the two cannot disagree about what a level is allowed to hold.

```dart
EntityRegistry shooterRegistry() => EntityRegistry(<EntityKind>[
      const PlayerSpawnKind(),
      MonsterKind(Monsters.byName),
      PickupKind(gifts),
      const KeyKind(),
      const DoorKind(),
      const LiftKind(),
      const PlatformKind(),
      const ButtonKind(),
      const TriggerKind(),
      const NoteKind(),
      const ExitKind(),
      ...lightKinds(),
    ]);

final GiftRegistry gifts = GiftRegistry(<Gift>[
  const HealthGift(),
  const ArmourGift(),
  const AmmoGift('bullets', AmmoType.bullets, defaultAmount: 20.0),
  const AmmoGift('shells', AmmoType.shells, defaultAmount: 8.0),
  const AmmoGift('rockets', AmmoType.rockets, defaultAmount: 4.0),
  const KeyGift(),
  const PowerUpGift('invulnerability', defaultAmount: 20.0),
]);
```

Rules about the level *as a whole* are this game's, not the format's:

```dart
List<LevelRule> shooterRules() => const <LevelRule>[
      ExactlyOne(EntityTypes.playerSpawn,
          because: 'the player would start at the origin, which is usually '
              'inside the floor'),
      AtLeastOne(EntityTypes.exit, because: 'the level cannot be finished'),
    ];
```

## Author a level {.step}

```json
{
  "version": 1,
  "name": "Crypt",
  "next": "assets/levels/vault.json",
  "fogColor": [0.04, 0.04, 0.06],
  "fogDensity": 0.02,
  "materials": {
    "stone": { "roughness": 1.0, "albedo": "assets/textures/stone_albedo.png",
               "normal": "assets/textures/stone_normal.png",
               "orm": "assets/textures/stone_orm.png", "texelsPerMetre": 0.5 }
  },
  "brushes": [
    {"at": [0, -0.5, 0],  "size": [40, 1, 60], "material": "stone"},
    {"at": [-20.5, 2, 0], "size": [1, 5, 60],  "material": "stone"}
  ],
  "entities": [
    {"type": "player_spawn", "at": [0, 0, -25], "yaw": 0},
    {"type": "torch",   "at": [-19, 2.4, -10], "color": [1.0, 0.72, 0.4]},
    {"type": "monster", "at": [3, 0, 6],  "monster": "runner"},
    {"type": "monster", "at": [-6, 0, 14], "monster": "tank"},
    {"type": "pickup",  "at": [2, 0.5, -8], "gift": "shells", "amount": 8},
    {"type": "key",     "at": [8, 0.5, 12], "color": "blue"},
    {"type": "door",    "name": "vault door", "at": [0, 1.5, 22],
     "size": [4, 3, 0.4], "travel": [0, 3, 0], "speed": 2.0, "key": "blue"},
    {"type": "exit",    "at": [0, 1, 28], "size": [4, 3, 1]}
  ]
}
```

Validate before you trust it:

```dart
final issues = LevelValidator(registry: kinds, rules: shooterRules())
    .validate(level);
for (final issue in issues) debugPrint('level: $issue');
```

The validator checks what is true of any level — names unique, references resolving, brushes not degenerate, something to stand on, something to see by, and your rules check the rest.

<div class="note">
<p>The textures and levels this page names are not shipped as a starter kit. The real ones are in the demo at <code>apps/flutter3d_demo_dungeon/assets/</code>: <code>levels/crypt.json</code>, and stone as <code>textures/stone_albedo.jpg</code> with <code>stone_normal.png</code> and <code>stone_orm.png</code>. Point your paths there, or at your own files.</p>
</div>

## Wire the simulation, with nothing drawn {.step}

This is the whole game, and none of it needs a device.

```dart
final level = Level.fromJson(jsonDecode(source) as Map<String, Object?>);
final collision = CollisionWorld();
level.addTo(collision);   // brushes become colliders

final kinds = shooterRegistry();

// One entity world for everything that has moved onto components, so one
// save covers the lot. Two would be a save covering half the game.
final entities = EcsWorld();
final hitscan = Hitscan(world: collision);
final projectiles = ProjectileSystem(world: collision, entities: entities);
final actors = ActorSystem(world: collision, entities: entities);
final mechanisms = MechanismWorld(collision);

final bestiary = Bestiary(
  actors: actors,
  shot: WeaponShot(world: collision, hitscan: hitscan, projectiles: projectiles),
  catalog: Monsters.byName,
);
// Attached here instead of at construction: it needs a world to put monsters
// in, and there is no world until the level has loaded.
(kinds[ShooterEntities.monster] as MonsterKind?)?.bestiary = bestiary;

level.spawnInto(
  SpawnContext(world: collision, actors: actors, mechanisms: mechanisms),
  registry: kinds,
);

final body = CharacterController(
  world: collision,
  // A spawn is authored where the feet go, which is the only place an author
  // can see. Lift it by half the body height.
  position: (level.playerStart?.position ?? Vector3.zero()) + Vector3(0, 0.9, 0),
);

// Who the collider *is*, rather than what it happens to be carrying. A locked
// door reads the keys off the player, and a rocket asks the player to take
// damage, without the physics knowing what either is.
final player = Player(
  body: body,
  inventory: Inventory(arsenal: Arsenal(
    slots: Weapons.all,
    owned: <WeaponDef>[Weapons.fists, Weapons.pistol],
    ammo: <AmmoType, int>{AmmoType.bullets: 40},
    startingSlot: 1,
  )),
  eyeOffset: 0.7,
);

final sim = GameSimulation(
  player: player,
  collision: collision,
  input: input,
  mechanisms: mechanisms,
  actors: actors,
  projectiles: projectiles,
  shot: WeaponShot(world: collision, hitscan: hitscan, projectiles: projectiles),
  levelNext: level.next,
  random: GameRandom(1),
);
```

<div class="why">
<p><code>GameRandom</code> rather than <code>math.Random</code>, and one instance shared by the bestiary, the hitscan and the simulation. <code>math.Random</code> has no readable state, which makes it the one thing in a simulation that cannot be written down; pass one <code>GameRandom</code> everywhere and two loads of the same save agree for ever, leave it out and they agree until the first flinch roll.</p>
</div>

## Give the monsters a map {.step}

Optional, and null keeps the plain behaviour — see the player, walk straight, get stuck on the corner.

```dart
final navIssues = <LevelIssue>[];
actors.navigation = Navigation.bake(level, cellSize: 0.25, issues: navIssues);
```

<div class="warn">
<p><strong>Quarter-metre cells, not the default half.</strong> A grid is conservative: a cell touching a wall has a clearance of one however far the wall actually is. At 0.5 a one-metre corridor is two cells, both touching, so a monster 0.7 wide, which physically fits — is refused the whole passage, and the grid silently falls back to walking straight at the player in exactly the places a route is worth having. Four times the cells and twice the bake, both at load time.</p>
</div>

Baked from `level.brushes`, deliberately **not** from `collision`: the world holds the doors, and whichever position one happened to be in at load would be frozen into the grid as architecture, a closed door becoming a wall nothing ever paths through again.

## Run the loop, headless {.step}

```dart
final input = InputState();
final loop = GameLoop(input: input, onStep: sim.step);

// In a test, drive it directly rather than from a Ticker.
for (var i = 0; i < 600; i++) {
  input.press(GameAction.moveForward);
  loop.advance(1.0 / 60.0);
  input.endStep();
}
expect(sim.state, GameState.complete);
```

That test is worth writing before anything is drawn. A game that can be played to its exit with no renderer is a game whose failures are reachable from a unit test.

## Drain what the step reported {.step}

```dart
void _afterStep() {
  if (sim.firedThisStep != null) {
    // muzzle flash, sound, recoil
  }
  for (final ShotHit hit in sim.hits) {
    particles.burst(Effects.impact, hit.point, direction: hit.normal);
  }
  switch (sim.usedThisStep) {
    case Refused(:final message): _say(message);      // "it is locked"
    case Activated(): break;
    case NothingToDo(): break;
    case null: break;
  }
  if (sim.damageTakenThisStep > 0) _painFlash = 1.0;

  for (final Actor dead in actors.died) _kills++;
  for (final Detonation blast in projectiles.detonations) {
    particles.burst(Effects.explosion, blast.position);
  }
  for (final String message in mechanisms.events.messages) _say(message);
}
```

Lists filled during the step and drained after it. Nothing here decides anything — it turns facts into sound and light.

<div class="note">
<p><code>Effects</code> is this application's own catalogue of <code>ParticleEffect</code> constants, not a package export; the demo's lives in <code>apps/flutter3d_demo_dungeon/lib/src/effects.dart</code>.</p>
</div>

## Load the level with visuals {.step}

Now the renderer. `LevelLoader` is the bridge: it reads the document, builds the collision world *and* the scene, and hands both back.

```dart
final loaded = await const LevelLoader().load(
  'assets/levels/crypt.json',
  device: device,
  registry: kinds,
  rules: shooterRules(),
);

final visuals = ActorVisuals(
  loaded.scene,
  appearance: const DungeonMonsters(),   // your game's opinion
  device: device,
);
final fixtures = FixtureVisuals(
  loaded.scene, loaded,
  appearance: const DungeonFixtures(),
  device: device,
)..bindLights();                       // before spawning: a torch finds its light

loaded.level.spawnInto(
  SpawnContext(
    world: loaded.collision,
    actors: actors,
    mechanisms: mechanisms,
    onActorSpawned: visuals.add,
    onFixture: fixtures.add,
  ),
  registry: kinds,
);
```

`ActorAppearance` and `FixtureAppearance` are the seams where the game says what things look like — everything in the bridge is mechanism.

```dart
final class DungeonMonsters implements ActorAppearance {
  const DungeonMonsters();

  // The engine hands over an `Actor`; what kind of thing it is lives on its
  // brain, and reading that here is the application admitting it is a shooter.
  // A platformer's appearance would cast to its own brain and never see a
  // MonsterState at all.
  @override
  String meshKeyFor(Actor actor) => _brainOf(actor)?.def.name ?? 'actor';

  @override
  Material materialFor(Actor actor) {
    final brain = _brainOf(actor);
    // Brightened for a moment after a hit: the cheapest damage feedback there
    // is, and the one whose absence makes a fight feel unresponsive.
    if (brain?.state == MonsterState.hurt) return _struck;
    return _materials[brain?.def.name] ?? _unknown;
  }

  static ChaseBrain? _brainOf(Actor actor) {
    final brain = actor.brain;
    return brain is ChaseBrain ? brain : null;
  }

  // Shared rather than built per call: materialFor runs for every monster
  // every frame, and a default that allocated would allocate once a frame
  // per monster.
  static final Map<String, Material> _materials = <String, Material>{
    'runner':  Material(baseColor: Vector4(0.52, 0.20, 0.18, 1.0), roughness: 0.7),
    'shooter': Material(baseColor: Vector4(0.22, 0.32, 0.52, 1.0), roughness: 0.6),
    'tank':    Material(baseColor: Vector4(0.30, 0.28, 0.16, 1.0), roughness: 0.85),
  };
  static final Material _struck = Material(baseColor: Vector4(1.4, 0.9, 0.8, 1.0));
  static final Material _unknown = Material();
}
```

## The camera, and the weapon in your hands {.step}

`flutter3d_game` has no camera, and that is not an omission. `Player` owns the body, the inventory, where the eye is and which way it points; what a projection matrix should do about that belongs to the renderer.

```dart
// Interpolated, because the step is 60 Hz and the display may not be.
_smoothed.read(loop.alpha, _drawnAt);
player.eyeFrom(_drawnAt, _eye);
player.aim(_aim);

_camera
  ..setPositionFrom(_eye)
  ..lookAt(_eye + _aim);

_ears.aimAt(_eye, player.yaw);
audio.update(_ears);
```

The weapon is a second scene with its own camera, drawn on top:

```dart
_weaponView
  ..selectWeapon(arsenal.current)
  ..step(dt, speed: body.velocity.length, grounded: body.isGrounded);

if (sim.firedThisStep != null) _weaponView.recoil();
```

<div class="why">
<p>Its own field of view, not the scene's. A 90° scene camera makes a gun in the corner of the screen look like it is being fired from the elbow, which is why <code>WeaponView</code> keeps a separate <code>Scene</code> and <code>CameraNode</code> rather than parenting a mesh to the player's node.</p>
</div>

## A HUD that reads one object {.step}

```dart
Hud(
  health: inventory.health.current,
  armour: inventory.health.armour,
  weapon: arsenal.isEmpty ? null : arsenal.current,
  ammo: arsenal.isEmpty ? 0 : arsenal.ammoOf(arsenal.current.ammo),
  keys: inventory.keys,
  kills: _kills,
  state: sim.state,
  message: _message,
)
```

`Inventory` is one object rather than four fields precisely so this is one read, and so it can hang off the player's collider, which is how a locked door asks what the body in front of it holds without the physics knowing what a key is.

## Save the game {.step}

```dart
final Snapshot snapshot = sim.save();
await file.writeAsString(jsonEncode(snapshot.toJson()));

// Later — load the level first, then apply the snapshot.
sim.restore(Snapshot.fromJson(jsonDecode(await file.readAsString())));
```

<div class="note">
<p><strong>A snapshot is not a level loader.</strong> It restores objects that already exist: the same collision world, the same monsters in the same order, the same mechanisms under the same names. That boundary is what saves it from inventing an identity scheme for every collider. It is versioned like the level format and refuses a document from a newer build.</p>
</div>

A save file, a network packet and the input to a determinism test are the same thing, so there is one mechanism instead of three, and the determinism test that goes with it found a real defect on its first run.

## Test it by breaking it {.step}

The headless test that plays the level to its exit is the one that catches regressions nothing else will.

```dart
test('the crypt can be finished', () {
  final game = loadCrypt();
  final route = <(GameAction, int)>[
    (GameAction.moveForward, 240),
    (ShooterActions.fire, 30),
    (GameAction.use, 5),
    (GameAction.moveForward, 180),
  ];

  for (final (action, steps) in route) {
    for (var i = 0; i < steps; i++) {
      game.input.press(action);
      game.loop.advance(1 / 60);
      game.input.endStep();
    }
    game.input.release(action);
  }

  expect(game.sim.state, GameState.complete);
});
```

<div class="why">
<p>Write each new test by <strong>breaking the thing it covers</strong> and watching it fail. One of this repository's first attempts passed against a deliberately broken implementation, because it asserted a guarantee a different class makes. The full argument is on the <a href="/reference/testing/">testing</a> page.</p>
</div>

## Where to go from here

- [What a shooter adds](/shooter/): the reference for every type used here
- [Simulation layer](/core/simulation/): the machinery underneath
- [Platformer tutorial](/platformer/tutorial/): the same core, a completely different game
- [Pitfalls](/reference/pitfalls/): when the picture is wrong rather than absent
