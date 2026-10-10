## 1.0.0-rc.1

- **Breaking: American spelling in identifiers, as Flutter and Dart
  use.** `ColourGradeAddon` is `ColorGradeAddon`. Only the Dart names
  changed: a file keeps the keys it was written with, and `dart fix`
  carries the renames.
- **The six post-processing families in one list.** `standardAddons` holds
  all twenty-two plugins of `flutter3d_addon_light`, `_shading`,
  `_reflections`, `_atmosphere`, `_motion` and `_style`, and this library
  exports all six.

- **Installing it changes nothing about the frame.** With the preset
  installed, the frame order fixture's 244 frames come out byte for byte the
  same as with no addon. What it adds is a switch for every effect.
