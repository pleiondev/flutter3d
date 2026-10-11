/// Water, fire and bodies in a world of the physics core's, stepped with
/// nothing that draws them.
///
/// [ElementsSimulation] owns or adopts a `NativeWorld` and steps it: the
/// flames an [Igniter] holds to a body ([Fires]), the waters poured over a
/// ground ([WaterBody]), the game's objects followed in ([Follower]), and
/// every element's step, fire's and water's first and then each a plugin
/// adds ([ElementHook]) over the world's fields ([ElementFields]). What the
/// world says is told to an [ElementsListener] and published on the bus as
/// [ElementEvent] and its kin; [ElementsSimulationPlugin] steps it in a
/// loop's `fields` phase and puts its own state in the loop's snapshots.
///
/// Beside it, what a game would otherwise keep a number for: a [Solid]
/// made and weighed from the catalogue ([Solid.of]), a throw aimed by the
/// core's own flight ([Ballistics]), and the brands a fire lofts
/// ([Firebrands]).
///
/// **No renderer, no hardware layer, no shaders, no particles**: a server
/// replaying a run, a headless test and a game's fixed step hold this and
/// nothing else. `flutter3d_effects` draws and sounds it (`Elements`,
/// `ElementsViewPlugin`), and keeps every look, view and material on its
/// side: a [TrackedBody] and a [WaterBody] name no scene node.
library;

export 'src/ballistics.dart';
export 'src/element_events.dart';
export 'src/element_hook.dart';
export 'src/firebrands.dart';
export 'src/simulation.dart';
export 'src/smoke_plume.dart';
export 'src/switches.dart';
