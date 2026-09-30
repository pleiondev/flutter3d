## 0.8.0

**The first release: heroes who share a maze and a screen.**
`CrawlerSimulation` steps one to four `Hero`s through a level's machinery,
with every living hero a focus of the `ActorSystem`, so each monster goes for
the hero it can reach first and its blows land on whoever they hit, through
that hero's `HeroClass` armour. Health drains a point a second and `Food`
restores it past the starting amount; a `DoorKey` opens one locked `Door`,
any of them, and is spent; `Potion` and `Treasure` are carried and counted.
`CrawlFraming` works out the view the living heroes need and holds each of
them inside it, and `CrawlCamera` eases towards it through `CameraRig`.

Its `flutter3d_sim` dependency asks for `^0.8.1`, the release that let an
`ActorSystem` have several foci.
