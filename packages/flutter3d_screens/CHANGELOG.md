## 0.4.0

* **Renamed from `flutter3d_ui`.** pub.dev's name-similarity check refused the
  old name (too close to an unrelated `flutter_3dui`), and this package was
  never published under it — so the rename costs nobody a migration. The name
  is the package's own first words: the screens a game has that are not the
  game.
* Opening the settings from the gamepad's menu button now runs the same
  `opening` callback the Escape key and the gear button already ran — the one
  that clears the input, so a control held on the way into the panel does not
  stay held under it.

## 0.3.0

* No changes of its own. The workspace is released as a set, in the order
  `ARCHITECTURE.md` §16 gives, so this package's version moves with the rest
  and its constraints on its siblings move with it.

## 0.2.0

* The screens a game has that are not the game: settings with volumes,
  rebinding and accessibility, the gear that opens them, credits, and where a
  save and a settings document are kept on each platform.
* Screen state in a Cubit rather than spread across `setState`, which is what
  makes it reachable from a test. The simulation step deliberately does not go
  through it.
