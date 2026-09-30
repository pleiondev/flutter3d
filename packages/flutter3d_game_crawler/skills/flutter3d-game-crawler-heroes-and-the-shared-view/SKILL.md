---
name: flutter3d-game-crawler-heroes-and-the-shared-view
description: Use when building a co-op dungeon crawl on flutter3d — several heroes in one world, monsters that pick the hero they can reach, loot and keyed doors, and the shared view nobody can walk out of.
---

# Several heroes, one maze, one screen

```dart
final sim = CrawlerSimulation(heroes: heroes, collision: world, random: random,
    mechanisms: mechanisms, actors: actors);
hero.wish.setValues(stickX, 0, stickY);   // per hero, before each step
sim.step(dt);
camera.follow(sim.framing, dt);           // once a frame, after the step
```

| | |
|---|---|
| `Hero`, `HeroClass` | body, class armour, health that drains, keys, potions, score |
| `Food`, `DoorKey`, `Potion`, `Treasure` | loot a living hero takes by walking into it |
| `CrawlFraming` | the view the living heroes need, and the edge they may not cross |
| `CrawlCamera` | eases towards that framing through `CameraRig` |

## Monsters get every hero, and the engine picks

The simulation steps the `ActorSystem` with every living hero as a focus.
Do not pick a target in a brain: `Mind.focus` is already the hero this actor
can reach first by walking, and `Mind.hurtFocus(body, amount)` credits the
hero whose body was hit. A brain that searched the hero list itself would be
a second, disagreeing answer to a question the flow field has answered.

## The edge is a rule of the step

Where a hero may walk is read off `CrawlFraming`, which is a function of the
heroes' positions and `FramingTuning`, never off the eased camera and never
off the window's size. Keep it that way: a rule that read the camera would
stop agreeing with itself after a load, and one that read the window would
disagree between two players online.

## Every monster goes through the `Horde`

Spawn with `horde.spawn(kind, at)`, never `ActorSystem.spawn` directly. The
horde is what writes a monster down so that a save can build it again; an
actor it does not know is one a load quietly loses. A new kind of monster is
a `MonsterKind` added to the list the horde is given — the list is how a save
names it.

## A locked door is the engine's `Door`

Give it a `key` and `wait: 0`. The simulation spends one of the touching
hero's keys and activates it; do not add a colour check, because in this genre
any key opens any door.
