# flutter3d_audio_core

Positional audio for flutter3d without a backend: attenuation, panning,
occlusion and voice limiting in `AudioScene`, the buses of a `Mixer`, and the
`SoundDef` and `SoundBank` a game describes its sounds with. `AudioBackend` is
the seam a backend fills.

Most games want [`flutter3d_audio`](https://pub.dev/packages/flutter3d_audio),
which re-exports this package and adds the SoLoud backend. Depend on this one
directly when a package only names buses, sounds or a scene and should not
carry native audio code: `flutter3d_game`'s settings panel is the case it was
split out for.

The design notes, why the geometry is computed in Dart and not in SoLoud's 3D
layer, are in `flutter3d_audio`'s README.
