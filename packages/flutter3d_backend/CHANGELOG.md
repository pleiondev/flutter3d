## 0.1.0

* Picks the graphics backend a build draws through — Impeller on a desktop,
  WebGL2 in a browser — with a conditional import rather than a runtime branch,
  because the two pull in worlds that do not compile for each other's platform.
* `openDevice` and `kFixedResolution`, which were three files in each of three
  games and byte-identical in two of them.
* Deliberately does not decide resolution or shadow budget. Those are a game's
  trade against its own scene, and a shared constant would be wrong for two of
  the three.
