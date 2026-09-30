## 0.8.0

**The first release: heroes who share a maze and a screen.**
`CrawlerSimulation` steps one to four `Hero`s through a level's machinery,
with every living hero a focus of the monsters, so each goes for the hero it
can reach first and its blows land on whoever they hit, through that hero's
`HeroClass` armour. Health drains a point a second and `Food` restores it past
the starting amount; a `DoorKey` opens one locked `Door`, any of them, and is
spent; `Potion` and `Treasure` are carried and counted. `CrawlFraming` works
out the view the living heroes need and holds each of them inside it, and
`CrawlCamera` eases towards it through `CameraRig`.

**Generators, and the horde they pour.** A `Generator` is a mechanism that
makes a `MonsterKind` every `period` until `cap` of its own are alive, and
stops when it is broken. The `Horde` keeps every monster, removes the dead,
and writes down what it needs to build them again, so a save loaded into a
fresh world, or rolled back past a birth, continues exactly as the run did.
A `Chaser` walks at the hero it was given and bites, or, like the ghost,
strikes once and is gone.

**Heroes fight back.** Held fire shoots along the way the hero last walked,
at the class's rate; shots pass through other heroes and stop at the first
wall, monster or generator (`Volley`). Walking into a monster is attacking it,
at the class's `melee` rate. A potion reaches everything in view, scaled by
the class's `magic`. Kills and broken generators score for whoever made them.

**Death and the thief.** `MonsterKind.death` drains fast, cannot be shot or
fought (`shotproof`), and leaves once it has dealt its `appetite`; only a
potion reaches it. `MonsterKind.thief` harms nobody: it takes a potion, or a
key, from the hero it reaches and runs, and is gone with it after
`Thief.escapeAfter` seconds unless somebody kills it first, which gives the
thing back to them.

**A crawl from a level document.** `crawlerRegistry` reads the format's
spawns, doors and exits with this genre's `food`, `key`, `potion`,
`treasure`, `generator` and `monster`, and `crawlerRules` asks for a spawn and
an exit. `stageCrawl` turns a level into a `CrawlerSimulation` for a party, a
hero on each `player_spawn` by its `slot`. Loot and generators the author did
not name are saved under a name made from where they stand, so eaten food
stays eaten after a load.

Its `flutter3d_sim` dependency asks for `^0.8.1`, the release that let an
`ActorSystem` have several foci and rebuild what was born during play.
