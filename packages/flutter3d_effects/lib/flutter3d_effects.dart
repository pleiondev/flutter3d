/// The physics core's water and fire, drawn.
///
/// `flutter3d_physics_native` simulates water over ground, the sheet a
/// stream throws off a cliff, its spray and bubbles, and fires that heat,
/// burn and spread; this draws them. A [LiquidView] is one water's surface
/// with the [LiquidLook] material, its falling sheet, drops and bubbles; a
/// [FireView] is every fire of a world, with the bodies it chars; and
/// [liquidMeshes] is a liquid in a vessel of `flutter3d_physics`, one mesh
/// a layer, with [jetMesh] and [particleMesh] for what pours out of it. [Elements] draws and sounds a whole `ElementsSimulation` of
/// `flutter3d_elements`, which steps the world with nothing of this
/// package's: the looks kept on its bodies ([Elements.lookOf]) and the view
/// and look of each water ([Elements.viewOf], [Elements.waterLookOf]) are
/// held here, not on the simulation's bodies and waters.
///
/// **No Flutter**, as `flutter3d_particles` has none: the views draw
/// through `flutter3d_core`'s scene and renderer, so the package runs under
/// `dart test`. The one thing an application hands it is the material's
/// bundle, read from its asset bundle as [LiquidLook.asset].
library;

export 'src/elements.dart';
export 'src/fire_light.dart';
export 'src/fire_view.dart';
export 'src/liquid_look.dart';
export 'src/liquid_shapes.dart';
export 'src/liquid_view.dart';
// Item 22: the typed accessors of the package's two materials.
export 'src/materials.g.dart';
export 'src/physics_hearing.dart';
export 'src/seabed_look.dart';
