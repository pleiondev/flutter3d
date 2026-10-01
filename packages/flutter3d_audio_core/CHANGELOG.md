## 0.8.0

**The half of `flutter3d_audio` that makes no noise.** `AudioScene`, the
`Mixer` and its buses, `SoundDef`, `SoundBank`, `EngineSound`, the listener
and the attenuation curves, with `AudioBackend` as the seam a backend fills.
It is the code `flutter3d_audio` 0.8.1 shipped, moved rather than changed, and
`flutter3d_audio` re-exports all of it, so a type is the same type whichever
package names it.

It exists so that a package which only names a bus or a sound need not carry
SoLoud. `flutter3d_game` offers volume sliders and nothing else of audio, and
through `flutter3d_audio` it brought `flutter_soloud`, whose native build asks
for `hooks` 2.2, which needs a newer `meta` than Flutter 3.44 pins: a game on
Flutter 3.44 could not depend on it at all.
