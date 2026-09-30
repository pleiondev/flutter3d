# flutter3d_game_crawler

A top-down dungeon crawl for one to four players on one screen.

## Why it exists

It is the first genre here with more than one player in the same world, and
the reason to write it was to find out what the engine assumed about that.
The answer was one thing: everything that walks paid attention to a single
focus. `flutter3d_sim` 0.8.1 lifted that, so a monster now goes for the hero
it can reach first by walking, found by the same flow-field sweep that used to
serve one player, and a blow is counted against the hero it landed on. This
package is what a hero is on top of that.

## What is in it

| | |
|---|---|
| `CrawlerSimulation` | The step order: the maze's machinery, the monsters with every living hero as a focus, the heroes inside the shared view, doors, loot, hunger, exits. |
| `Hero`, `HeroClass` | A body, a class (warrior, valkyrie, wizard, elf), health that drains a point a second, keys, potions and score. |
| `Food`, `DoorKey`, `Potion`, `Treasure` | Loot a living hero takes by walking into it. |
| `Generator`, `MonsterKind`, `Horde`, `Chaser` | Where monsters come from until it is broken, what they are, the list that keeps them and rebuilds them from a save, and the mind that walks them at a hero. |
| `Volley`, `Bolt` | The heroes' shots in flight: through each other, into the first wall or monster. |
| `MonsterKind.death`, `Thief` | What only a potion can stop, and what takes a potion or a key and runs. |
| `crawlerRegistry`, `crawlerRules`, `stageCrawl` | A level document turned into a crawl for a party. |
| `CrawlFraming`, `FramingTuning` | Where the shared view has to be for every hero to be in it, and the edge none of them may walk past. |
| `CrawlCamera` | Eases towards that framing through `CameraRig`. |

A locked door is the engine's `Door` with a key and no wait: a hero carrying a
key who walks into it spends the key and the door stays open.

## A horde born during play still loads

A snapshot fills in a world that already exists, and nearly every monster in a
crawl was born after the level loaded. The `Horde` records each monster's kind,
generator and entity, and on restore builds them again under the same entities
before the entity save pours their numbers in, so a save loaded afresh or
rolled back past a birth continues as the run did. The tests check both
against a run that was never interrupted.

## The edge of the view is a rule, not a camera

Nobody walks off the screen, so one hero heading for the exit cannot drag the
view away from the others. That decides where a hero may go, so it is part of
the step, and it is read off `CrawlFraming`, which remembers nothing between
steps, rather than off the eased camera, whose state no save carries. The
playfield's aspect ratio is the game's, not the window's.

Nothing here imports the renderer or another genre, so every test runs with no
device.
