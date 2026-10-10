## 1.0.0-rc.1

- **Breaking: public constants are lowerCamelCase, without the k prefix,
  as Effective Dart asks.** `kBeaconGlow` is `beaconGlow`. The values are
  the same; `dart fix` carries the renames.
- **Breaking: American spelling in identifiers, as Flutter and Dart
  use.** `accentColour` is `accentColor`, `colour` is `color`,
  `metresPerSecond` is `metersPerSecond`, `othersColour` is `othersColor`,
  `playerColour` is `playerColor`. Only the Dart names changed: a file
  keeps the keys it was written with, and `dart fix` carries the renames.
- **Breaking: the HUD's colours are the theme's.** `HudLine.defaultAccent`
  and `HudLine.labelWidth` are gone; `GameUiTheme` (a `ThemeExtension` in
  `flutter3d_game`) holds the accent, the label colour, the label column's
  width and the panel's background, with the old values as its fallback.
  `HudLine.accentColor` is nullable and overrides the theme's accent.
  `Speedometer` says its unit in the player's language.

- **The HUD pieces the demos each drew for themselves.** `HudPanel` and
  `HudLine` from racing, `HudTally` and `HudBanner` from the platformer and
  strategy (one widget each now, with a `HudTallyStyle` for the ink and the
  sizes that differed), and the `Speedometer`, which takes metres a second
  rather than a race's readout.

- **The minimap draws any course.** `MiniMap` takes an outline and a list of
  markers, the first the player's, and fits the course to its box.
  `MiniMapPainter.place` says where a point lands, for a HUD that lays out
  its own frame.

- **A hint is a rule.** `MomentHint` is a sentence and the moment it is
  true; `MomentHints` says each of several once, one a step, until
  `forget`. The dungeon's first-shot hint is one.

- **An objective that can be found in the dark.** `lightBeacon` raises what
  already glows on an object to `beaconGlow`, normalised so a second call
  changes nothing.

- **The stereo HUD panel is part of this package.** `StereoHudPanel` builds
  a HUD once and redraws it from a `ValueListenable`, for a surface in front
  of a stereo camera. Too small for a package of its own.
