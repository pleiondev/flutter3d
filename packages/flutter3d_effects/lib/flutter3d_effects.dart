/// The physics core's water and fire, drawn.
///
/// `flutter3d_physics_native` simulates water over ground, the sheet a
/// stream throws off a cliff, its spray and bubbles, and fires that heat,
/// burn and spread; this draws them. A [WaterView] is one water's surface
/// with the [WaterLook] material, its falling sheet, drops and bubbles; a
/// [FireView] is every fire of a world, with the bodies it chars.
///
/// **No Flutter**, as `flutter3d_particles` has none: the views draw
/// through `flutter3d_core`'s scene and renderer, so the package runs under
/// `dart test`. The one thing an application hands it is the material's
/// bundle, read from its asset bundle as [WaterLook.asset].
library;

export 'src/fire_view.dart';
export 'src/water_look.dart';
export 'src/water_view.dart';
