/// What this repository is made of, and where each rule is relaxed.
///
/// **One table rather than a file per package.** The rules used to live as a
/// `boundaries_test.dart` in each package, which meant a new package was
/// covered only if somebody remembered to add one — and thirteen of twenty-one
/// were not. A runner that walks `packages/` covers a new package the day it
/// exists, and every exemption is visible in one place instead of being spread
/// across twenty-one files nobody reads together.
///
/// Every entry here should say *why*. An exemption nobody explained is an
/// exemption on its way to being the rule.
library;

import 'dart:io';

/// Every package that holds one genre's vocabulary.
///
/// Two of them did not exist when the list was written. They are named anyway,
/// because the cost of a name in a list is nothing and the cost of finding out
/// later is a package that was allowed to grow the wrong way for a month.
const List<String> genrePackages = <String>[
  'flutter3d_game_shooter',
  'flutter3d_game_platformer',
  'flutter3d_game_racing',
  'flutter3d_game_strategy',
];

/// Packages named `flutter3d_game_*` that are not a genre, and what they are.
///
/// The prefix is how the list above is checked against the workspace: a
/// fifth genre arrives as `flutter3d_game_<genre>` and is told to join it.
/// These three take the prefix for the reader on pub.dev, where they sit
/// beside `flutter3d_game` as the parts a game is built from; neither holds
/// a genre's vocabulary, and the genre rules scan them like any package.
const Map<String, String> notAGenre = <String, String>{
  'flutter3d_game_kit':
      'the gameplay parts every genre shares — reactions, a soundtrack, '
      'ghosts, seeded levels and the world',
  'flutter3d_game_physics':
      'the gameplay parts every genre shares that need the native physics '
      'core — ragdolls, wrecks, parties and the elements heard',
  'flutter3d_game_ui':
      'the widgets around any game — the HUD, touch controls, '
      'accessibility, screens, photo mode and capture',
};

/// Every application in this repository, which is also its directory name.
///
/// `_demo_` marks the ones that exist to show the engine works. The others are
/// tools — a level editor and a modeller — and the lessons, and rules about
/// *games* filter on the infix rather than carrying a fourth list. The seed a
/// new project starts from is not here: it is two package examples,
/// `flutter3d_app`'s for an application and `flutter3d_game`'s for a game.
const List<String> applications = <String>[
  'flutter3d_demo_arcade',
  'flutter3d_demo_dungeon',
  'flutter3d_demo_platformer',
  'flutter3d_demo_racing',
  'flutter3d_demo_river',
  'flutter3d_demo_sandbox',
  'flutter3d_demo_strategy',
  'flutter3d_demo_water',
  'flutter3d_demo_hollow',
  'flutter3d_demo_reef',
  'flutter3d_editor',
  'flutter3d_modeler',
  'flutter3d_showcase',
  'flutter3d_lesson_viewer',
  'flutter3d_stereo_lesson_viewer',
  'flutter3d_lab_incident',
  'flutter3d_lab_pendulum',
];

/// Packages that must run with no Flutter SDK anywhere near them, and what
/// each one is for.
///
/// **A list rather than a rule per package, because the second one arrived.**
/// The rule was written for `flutter3d_sim` alone and named it in its own
/// source, so `flutter3d_editor_core` — extracted for exactly the same reason,
/// from an application instead of from a package — would have got either a
/// thirty-first rule that reads the same file twice or no rule at all. A list
/// makes the third one a line here.
///
/// What earns a place is not "happens to compile without Flutter". It is a
/// package with a caller that has no Flutter SDK to give it: the simulation
/// because a server replays a submitted run through the same code the player
/// ran, and the editor's core because a linter, a service or a tool opens a
/// level without a window. Since 1.0 that is every package that is plain Dart
/// today (`tasks/1.0-arch-review.md`): a package left off this list was one
/// a Flutter import could reach unnoticed, and `tool/ci.sh` ran its suite
/// under `flutter test`, where it passes either way.
const Map<String, String> flatDartPackages = <String, String>{
  'flutter3d_core':
      'mcp-03n\'s own split: a modeller\'s document layer, the tool an agent '
      'starts with `dart run`, and a service checking an uploaded asset all '
      'want a `Renderer` that draws a frame with no window in front of it, '
      'and the geometry and model formats under it, which the same callers '
      'read with no window at all. `flutter3d` stays the thin '
      'Flutter shell three seams could not leave: `BundleAssetSource` and '
      '`assetUriResolver` name `rootBundle`, `defaultImageDecoder` names '
      '`dart:ui`, and `ModelAsset`/`bindMaterial`/`loadMaterial` default to '
      'that decoder so every existing caller of either keeps compiling '
      'unchanged',
  'flutter3d_mesh':
      'the mesh a modeller edits is a document before it is a picture: a bench '
      'compiled by `dart compile exe`, the tool an agent starts with `dart '
      'run`, and a test of a loop cut all hold one and none of them draws',
  'flutter3d_particles':
      '`pro-sim-02`\'s own row: `flutter3d_model_core`\'s '
      '`BakeParticleSystemJobRequest` bakes a `ParticleSystem` into a cache from '
      'a command line or a service with no window in front of it, the same '
      'way `BakeRigidBodyJobRequest` already does through `flutter3d_physics`. '
      'The two contributors that draw a system live beside it because they '
      'draw through `flutter3d_core` and name no Flutter either',
  'flutter3d_model_core':
      'a model is a document, and the programs that check, convert or drive '
      'one — an exporter on a command line, a service validating an upload, '
      'the tool an agent speaks to — have no window',
  'flutter3d_mcp':
      'it is those tools. A host starts the level editor\'s, the modeller\'s '
      'and the project server with `dart run`, which cannot resolve a '
      'package that depends on the Flutter SDK — so a single Flutter import '
      'anywhere in this graph is not a heavier process, it is every server '
      'here failing to start on a machine without the Flutter tool. The kit '
      'they share is a library of the same package, and `flutter3d_sim_mcp`, '
      'which plays a game and so needs Flutter, stays a package of its own '
      'for exactly this reason',
  'flutter3d_sim':
      'a server replays a run through it, in a container with no '
      'Flutter SDK in it',
  'flutter3d_foundation':
      'every package depends on it, the simulation and the plugin API '
      'included, so it is in every graph a replaying server or a command '
      'line resolves',
  'flutter3d_matter':
      'a world\'s properties and the material catalogue are read by the '
      'simulation a server replays, by the audio\'s mix and by the tool that '
      'writes the native core\'s header, none of which has a window',
  'flutter3d_plugin_api':
      '`flutter3d_sim` implements its loop and bus against it, so it is in '
      'the graph the replaying server resolves; and a plugin that touches '
      'only the simulation runs on that server too',
  'flutter3d_plugin_runtime':
      'a Wasm module or a data plugin that touches the simulation is '
      'replayed with the rest of the run, so the interpreter that steps it '
      'resolves where the replaying server does',
  'flutter3d_education':
      'a server verifies a student\'s submitted lab run the same way it '
      'verifies a game run — by replaying it, in a container with no '
      'Flutter SDK in it; and `cloud/lti` checks a launch with the LTI '
      'library beside it, in another. The chemistry bench that draws is '
      'this package\'s `example/`, an application of its own',
  'flutter3d_voxel':
      'a sandbox\'s state is its blocks, and a server that holds or checks '
      'one reads the same edits into the same colliders and navigation the '
      'player\'s game did — in a container with no Flutter SDK in it',
  'flutter3d_build':
      '`hook/build.dart` is a separate process the Flutter tool starts with '
      'no window and no Flutter SDK to resolve — `ap-00`\'s spike is the '
      'reason this is stated as a fact rather than assumed: a hook that '
      'named Flutter would not fail loudly, it would simply not start',
  'flutter3d_build_hooks':
      'it is what a package\'s own `hook/build.dart` imports to compile its '
      'materials, a process the Flutter tool starts with no Flutter SDK to '
      'resolve, as `flutter3d_build`\'s is',
  'flutter3d_editor_core':
      'a level is a document, and the programs that check one — a linter, a '
      'service, a tool an agent speaks to — have no window',
  'flutter3d_level_scene':
      'the editor\'s agent server and its light optimizer draw a level on '
      'the software renderer under `dart run`, through the same scene a '
      'game\'s level loader builds',
  'flutter3d_editor_play':
      'the editor\'s MCP server (`flutter3d_mcp`) runs Play through it, and '
      'that server is '
      'started with `dart run`: a Flutter import here is `play` taking the '
      'whole server down with it',
  'flutter3d_hardware':
      'the vocabulary a backend implements named no graphics API already; '
      '`GraphicsDevice.present` was its one Flutter import, returning the '
      'widget a finished frame becomes, and replacing it with a device '
      'registry a backend adds itself to (mcp-01n) left nothing here that '
      'names Flutter at all',
  'flutter3d_shaders':
      '`lib/`\'s own `requiredShaders` is a plain `const` list; its `flutter: '
      'sdk` dependency was never real, only ever inherited from the split out '
      'of `flutter3d_impeller`, and every backend\'s own `conformance_test.dart` '
      'resolved the Flutter SDK through it for no reason at all',
  'flutter3d_conformance':
      'the behaviour a backend has to have is not itself GPU-shaped; it names '
      'no Flutter import of its own, and `flutter3d_shaders` — the one '
      'dependency that used to carry the SDK in — no longer does either',
  'flutter3d_cpu':
      'no GPU, no shading language, and now nothing in its own dependency '
      'graph names Flutter either: `flutter3d_conformance` and '
      '`flutter3d_shaders`, dev dependencies for `conformance_test.dart` and '
      '`shader_names_test.dart` alone, are both flat themselves',
  'flutter3d_physics':
      'the simulation steps it, so it is in the graph the replaying server '
      'resolves, and a tool that bakes a rigid body\'s cache '
      '(`flutter3d_model_core`) runs it with no window',
  'flutter3d_physics_native':
      'the native core a server steps a run with is the one the player\'s '
      'game stepped; its `flutter: assets:` key only lists the web build\'s '
      'files for an application, and names no SDK',
  'flutter3d_camera':
      'the virtual cameras are simulation, stepped and snapshotted with the '
      'run, so a replaying server steps them too',
  'flutter3d_post':
      'its effects are render steps over `flutter3d_core`, which draws '
      'headless; a tool that renders a frame with no window installs them',
  'flutter3d_effects':
      'its views are render steps over the core and the particles, which a '
      'tool that draws a replayed run with no window installs; the fire and '
      'the water a server replays are `flutter3d_elements`\', and '
      'its `flutter: assets:` key only ships compiled materials to an '
      'application',
  'flutter3d_net':
      'a dedicated server, a relay or a bot runs the rollback session in a '
      'process with no window',
  'flutter3d_audio_core':
      'the mix is decided in the simulation, which a server replays, before '
      'any speaker is opened',
  'flutter3d_lints':
      'an analyzer plugin and `dart run flutter3d_lints:migrate` run in the '
      'analysis server and on a command line, neither of which has a Flutter '
      'SDK to resolve',
  'flame_multiplayer':
      'a party\'s wire protocol is spoken by a relay or a server as well as '
      'by the game',
  'flame_multiplayer_dashwire':
      'the transport a relay or a server speaks, as `flame_multiplayer` is',
};

/// Dev dependencies published after the package that names them, as
/// `'<package> -> <dependency>'`, with the reason it is so.
///
/// **The order is set by what a package needs at run time**, which `pub
/// publish` resolves against pub.dev; a dev dependency is resolved too, by
/// pana when it scores the upload, so the order puts it first wherever the
/// graph allows. These are the ones it cannot: a test that proves two
/// packages work together, written in the lower of the two because the
/// higher may not depend on it. Until the later package is up, pana reports
/// the dev dependency as missing and the score waits for its next analysis;
/// nothing a user resolves is affected. The rule `the publishing order names
/// every package` fails on an inversion not here, and on an entry here the
/// order no longer inverts.
const Map<String, String> devDependencyPublishedLater = <String, String>{
  'flutter3d_cpu -> flutter3d_model_core':
      '`render_project_test.dart` renders a modeller\'s project on the '
      'software device; `flutter3d_model_core` may not depend on a backend, '
      'so the proof that the two work together lives in the backend',
  'flutter3d_cpu -> flutter3d_mesh':
      'the same test builds the project it renders from a `ParametricCuboid`',
  'flutter3d_cpu -> flutter3d_particles':
      '`reactive_mask_test.dart` draws an ember through the engine\'s own '
      'particle contributor, which draws through the core on any device',
  'flutter3d_webgl -> flutter3d':
      '`engine_frame_test` drives the real renderer through the backend, the '
      'one thing the backend exists for; the engine sits above every backend',
  'flutter3d_webgpu -> flutter3d':
      'the same: a reflection probe is checked as a picture the engine draws '
      'through this backend',
  'flutter3d_webgpu -> flutter3d_plugin_runtime':
      '`runtime_material_test.dart` hands naga a material `RuntimeShaders` '
      'spliced into this backend\'s stage at run time',
  // The simulation stands on the physics, which stands on the material
  // catalogue since `flutter3d_matter` came out of it (1.0.0-rc.1), so the
  // simulation and what needs it at run time moved up past the backends and
  // the audio core, which need neither.
  'flutter3d_cpu -> flutter3d_conformance':
      '`conformance_test.dart` runs the contract suite every backend passes; '
      'the suite also checks a plugin through the simulation '
      '(`plugins.dart`), so it stands above the simulation, and a backend '
      'needs only the hardware layer and the shaders',
  'flutter3d_webgl -> flutter3d_conformance':
      'the same contract suite, run against a real WebGL2 context',
  'flutter3d_webgpu -> flutter3d_conformance':
      'the same contract suite, run against the WebGPU backend',
  'flutter3d_audio_core -> flutter3d_sim':
      '`audio_model_test.dart` installs `AudioPlugin` into an `EngineLoop`; '
      'the mix itself needs only the world\'s air, from `flutter3d_matter`, '
      'and the loop stands above the physics',
  'flutter3d_app -> flutter3d_testing':
      '`terrain_tiles_test.dart` draws the terrain material through the '
      'software stage `flutter3d_testing` provides, and `flutter3d_testing` '
      'needs `flutter3d_app` at run time, so one of the two has to wait',
};

/// Packages the genre rule does not apply to, and why.
const Map<String, String> genreRuleExempt = <String, String>{
  'flutter3d_game_shooter': 'it is a genre; the rule it keeps is isolation',
  'flutter3d_game_platformer': 'it is a genre',
  'flutter3d_game_racing': 'it is a genre',
  'flutter3d_game_strategy': 'it is a genre',
  'flutter3d_demo_content':
      'it is the demo games\' own content — the shooter\'s roster and crypt, '
      'the strategy map\'s world — and unpublished; nothing published may '
      'depend on it',
  // `flutter3d_sim_mcp` used to be here — "it deliberately plays one genre,
  // the shooter". It plays whatever `HeadlessGame` a host hands it now, and
  // the shooter's side of that lives in the shooter, so the rule holds it like
  // any other package.
};

/// Which files of a genre package are allowed to reach a renderer.
///
/// An allowlist rather than a directory rule, so that a second file needing a
/// renderer is a deliberate line here rather than a `mv`. The platformer's list
/// is empty and that is the strongest form of the rule: nothing there draws at
/// all, and it does not depend on `flutter3d`.
const Map<String, Set<String>> genreMayDraw = <String, Set<String>>{
  'flutter3d_game_shooter': <String>{'lib/src/weapon_view.dart'},
  'flutter3d_game_racing': <String>{'lib/bridge.dart'},
  'flutter3d_game_platformer': <String>{},
  'flutter3d_game_strategy': <String>{'lib/bridge.dart'},
};

/// Which files of a genre package belong to its visible half, and so may name
/// Flutter.
///
/// **A genre's simulation is plain Dart in everything but its pubspec.** The
/// package declares `flutter: sdk` because its readouts are widgets, and nothing
/// stopped a widget, a `debugPrint` or a `MediaQuery` from arriving in the
/// simulation beside them — the simulation a server replays and a test steps
/// with no device. So the files that may name Flutter are listed here, the
/// barrel the simulation is imported through may export none of them, and
/// `bridge.dart` is where they are reached from.
///
/// Checked apart from [genreMayDraw], because a widget is Flutter without being
/// a renderer.
const Map<String, Set<String>> genreBridgeHalf = <String, Set<String>>{
  'flutter3d_game_shooter': <String>{
    'lib/bridge.dart',
    'lib/src/hud.dart',
    'lib/src/weapon_view.dart',
  },
  'flutter3d_game_racing': <String>{'lib/bridge.dart', 'lib/src/hud.dart'},
  'flutter3d_game_platformer': <String>{'lib/bridge.dart', 'lib/src/hud.dart'},
  'flutter3d_game_strategy': <String>{'lib/bridge.dart'},
};

/// Genre cameras that do not turn [CameraRig], and why.
///
/// **The seam this protects was already built, which is exactly why it needs a
/// rule.** `FollowCamera` and `ChaseCamera` keep none of the hard parts: the
/// smoothing, the impulse decay, the shake and the pull out of walls all live
/// once, in `flutter3d_camera`'s `CameraRig`, and both genres forward `kick`,
/// `shake`, `widen` and `cut` straight into it. What differs between them is
/// what should differ — where the camera looks for a runner who is turning
/// around, and how a car's heading blends between its velocity and the track.
///
/// Nothing said so. A fourth genre would reach for a camera, find two
/// implementations that look complete, and write a third — smoothing and all —
/// without ever learning that the smoothing was already solved and tested. The
/// arrangement would decay by addition rather than by edit, which is the kind
/// nobody notices in review.
///
/// Scanned over packages *and* applications, because the third camera gets
/// written where a genre starts — in a demo — more readily than in a package
/// that already has one. Taking a file off the rule costs a sentence saying what
/// it does instead: a camera with no subject to follow has no rig to turn, and
/// that is a reason; "it was easier" is not.
const Map<String, String> notARigCamera = <String, String>{
  'flutter3d_camera/lib/flutter3d_camera.dart':
      'the barrel of the virtual cameras, named for its package: it exports '
      'and places nothing. Every camera it exports turns the rig, in '
      '`virtual_camera.dart`, which this rule scans like any other',
  'flutter3d_camera/lib/src/photo_camera.dart':
      'photo mode\'s camera, flown by the player with the world paused: it '
      'follows nothing, so there is no smoothing to share, and a shake or a '
      'kick on a camera lining up a still picture is the one thing it must '
      'not have. It keeps out of walls by sweeping each move, which the rig\'s '
      'ray back from a subject cannot do for a camera with no subject',
  'flutter3d_core/lib/src/engine/render/physical_camera.dart':
      'an exposure, not a camera that moves: an aperture, a shutter time and '
      'an ISO, and the exposure value they make. It has no position, follows '
      'nothing and sits below flutter3d_camera, where the rig is',
  'flutter3d_core/lib/src/engine/scene/camera_node.dart':
      'the scene-graph camera the rig steers, not a camera that follows '
      'anything: it holds the projection and the view, sits below '
      'flutter3d_camera, and could not name CameraRig without inverting the '
      'dependency that makes the rig possible',
  'flutter3d_editor/lib/src/fly_camera.dart':
      'a tool, not a game: it flies where the author points it, so it follows '
      'nothing and has no impulse, no shake and no wall to be pulled out of',
  'flutter3d_core/lib/src/formats/model_camera.dart':
      'data, not a rig: `ModelCamera` is what a glTF file said its camera\'s '
      'projection was — yfov, znear, an aspect ratio that may be absent on '
      'purpose — with no subject to follow and nothing that ever moves it',
  'flutter3d_core/lib/src/formats/gltf/gltf_loader_lights_cameras.dart':
      'reads that same data out of glTF JSON; still nothing to follow',
  'flutter3d_core/lib/src/formats/gltf/gltf_writer_lights_cameras.dart':
      'writes it back; still nothing to follow',
  'flame_flutter3d/lib/src/camera/camera_sync_controller.dart':
      'a mirror, not a rig: it copies one camera\'s position and zoom onto '
      'the other\'s, in whichever direction was asked for, and has no '
      'subject, no impulse and no wall — the smoothing and the pull-out '
      'CameraRig gives a followed subject would be a second opinion about '
      'where the camera already, definitionally, is',
  'flame_flutter3d/lib/src/camera/camera_sync_component.dart':
      'that same mirror called from a Flame component\'s update: it holds a '
      'CameraSyncController and nothing else, so it follows nothing either',
  'flutter3d_showcase/lib/pages/flame/flame_camera_bridge.dart':
      'demonstrates that same mirror, not a rig: the camera it builds is '
      'the one CameraSyncController reads from or writes to directly, with '
      'no subject to follow — a CameraRig here would be steering a camera '
      'the demo is using to test the opposite direction of sync',
  'flutter3d_showcase/lib/pages/formats/gltf_cameras_lights.dart':
      'a page about reading the cameras and lights a glTF file carries, not '
      'a camera that follows anything: it reports what the file said, and has '
      'no subject, no impulse and no wall to be pulled out of',
};

/// Packages the repeatable-step rule does **not** apply to, and why.
///
/// **This was the other way round**, and the file it lives in opens by naming
/// exactly that mistake: the rules used to be a test per package, "and thirteen
/// of twenty-one were not covered because somebody had to remember". The
/// repeatable-step rule was then written as a table of five packages to *scan*
/// — so a new genre, or any new package a fixed step runs through, got no scan
/// for `DateTime.now()` or an unseeded `Random()` until somebody edited the
/// table. The default was exempt, which is the shape that had just been
/// removed.
///
/// It is exclusions now, so a package added tomorrow is covered today, and
/// taking one out of the rule costs a sentence saying why. `_exemptionsResolve`
/// checks this list the way it checks every other: a name here that is not a
/// package is a rule that has outlived its subject.
const Map<String, String> notARepeatableStep = <String, String>{
  'flutter3d_core':
      'a renderer draws a frame; the clock it reads is the frame\'s. Its '
      'geometry turns a lathe profile with `math.sin` once, when a shape is '
      'built, and its formats slerp between two keys for a frame, on that '
      'same clock',
  'flutter3d_mesh':
      'a mesh, not a step: an extrusion happens when somebody asks for it, and '
      'the arithmetic that places its vertices is the same arithmetic '
      'geometry does one package down',
  'flutter3d_model_core':
      'a document, not a step: a command changes a project when it is run, and '
      'nothing here advances on a clock',
  'flutter3d_impeller': 'a backend, not a step',
  'flutter3d_webgl': 'a backend, not a step',
  'flutter3d_webgpu': 'a backend, not a step',
  'flutter3d_cpu': 'a backend, not a step',
  'flutter3d_hardware': 'the vocabulary a backend implements',
  'flutter3d_conformance': 'a test suite for backends',
  'flutter3d_shaders': 'GLSL and a manifest',
  'flutter3d_samples': 'fixtures',
  'flutter3d_particles':
      'display and preview, not a verified replay: its contributors draw '
      'with the frame\'s own delta, and `flutter3d_model_core`\'s '
      '`BakeParticleSystemJobRequest` steps it at a fixed `dt` only to fill a '
      '`SimulationCache` a modeller scrubs locally — nothing here is a run a '
      'server replays against a client\'s own answer the way `flutter3d_sim`\'s '
      'is, so the platform\'s libm disagreeing with itself across machines has '
      'nothing to fail',
  'flutter3d_testing': 'a test helper',
  'flutter3d_game':
      'a run\'s lifecycle, the screens that run on the frame clock, and '
      'display: it reads devices once a frame, reads a simulation and moves '
      'nodes, loads and saves, and steps nothing itself',
  'flutter3d_app':
      'chooses a device, loads a level into a scene and draws it; steps '
      'nothing',
  'flutter3d_audio': 'display: a mix is recomputed once a frame',
  'flutter3d_audio_core': 'display: a mix is recomputed once a frame',
  'pad_input': 'a device, read once a frame',
  'pointer_lock': 'a platform channel',
  'flutter3d_build':
      'a build-time tool, not a step: `dart run flutter3d_build:convert` reads a '
      'wall clock to report how long a decode or an encode took a human '
      'watching it run, the same way `step_time_trace.dart` does for a '
      'step from outside it — there is no simulation here to replay, only '
      'a CLI printing what it just measured',
  'flutter3d_editor_widgets':
      'a colour swatch, not a step: `ColorField.encodeSrgb`/`decodeSrgb` '
      'convert whatever colour a person is looking at right now, on this '
      'one machine, the same formula and the same exemption '
      '`flutter3d_cpu`\'s own `cpu_shaders_color.dart` already has — never '
      'a run a server replays',
  'flutter3d_lints':
      'a linter: it names the clock, the dice and the machine\'s '
      'transcendentals in order to find them, and runs inside the analysis '
      'server rather than inside any step',
};

/// Applications the two determinism rules do **not** scan, and why.
///
/// **The rules cover `apps/` now** (decision 11 of `tasks/0.9-plugins.md`):
/// a demo is where a game's step is written first, and the shooter's own
/// first clock read was found in one. Excluded here is what steps no run at
/// all: tools a person drives, and pages that show a feature. A demo is never
/// excluded whole; a file of one that draws rather than steps says so in
/// [repeatableStepExempt] or [portableStepExempt], with its reason.
const Map<String, String> notARepeatedApp = <String, String>{
  'flutter3d_editor':
      'a tool: it edits a level on the frame clock, and its Play runs '
      'through `flutter3d_editor_play`, a package both rules scan',
  'flutter3d_modeler':
      'a tool: a model is a document, and the preview it plays is the '
      'modeller\'s own, on the frame clock, with nothing recorded',
  'flutter3d_showcase':
      'pages that each show one feature on the frame clock; none records a '
      'run, and the features they show live in packages both rules scan',
  'flutter3d_lesson_viewer':
      'a viewer: a lesson is a scene a person turns and reads, with nothing '
      'stepped and nothing recorded',
  'flutter3d_stereo_lesson_viewer':
      'the same viewer through a phone holder: a head pose, read once a '
      'frame, turns a scene nothing steps',
};

// What the files of the demos below are, by kind, so a reason is written
// once and read the same everywhere it applies.

/// A file of a demo that only draws.
const String _drawn =
    'draws, aims a camera or names a file for a person; nothing a step runs '
    'reads what it computes';

/// The LTI library's files in `flutter3d_education`, which read the wall
/// clock: the lab library beside them is a step and is scanned, so the
/// exemption is by file rather than the whole package's, as it was while
/// LTI was a package of its own.
const String _ltiClock =
    'a cloud tool, not a step: an LTI launch is checked against the wall '
    'clock its own `exp`/`iat` claims are written in, and an xAPI statement '
    'or an AGS score carries the moment it was sent — nothing here is a run '
    'a client and a server must replay to the same frame';

/// Files inside a scanned package that are allowed to be unrepeatable, and why.
const Map<String, Map<String, String>> repeatableStepExempt =
    <String, Map<String, String>>{
      'flutter3d_sim': <String, String>{
        'lib/src/save/game_random.dart': 'it is the seeded generator',
        'lib/src/save/step_time_trace.dart':
            'a profiler observing a step from outside it, not a step: '
            '`record` reads a `Stopwatch` to measure how long a caller\'s '
            'step took and writes the answer into a trace nothing in the '
            'simulation reads back, the same one-way relationship '
            '`FrameTimingLog` already has with the render loop it watches',
        'lib/src/loop/isolate_link_native.dart':
            'the frame clock of a simulation in an isolate, outside every '
            'step: it hands `EngineLoop.frame` the real seconds a `Stopwatch` '
            'measured, as a view\'s ticker does, and a step still sees only '
            'the count of fixed steps the loop owes',
      },
      'flutter3d_editor_core': <String, String>{
        'lib/src/editing.dart':
            'the ids of rows a person adds in the editor (`LevelIds.fresh`): '
            'an edit is not a step and nothing replays it, and an id only '
            'has to differ from the level\'s others; the simulation\'s own '
            '`LevelIds.fresh` takes the generator it is handed',
      },
      'flutter3d_education': <String, String>{
        'lib/src/lti/lti_launch_validator.dart': _ltiClock,
        'lib/src/lti/ags_client.dart': _ltiClock,
        'lib/src/lti/ags_score.dart': _ltiClock,
        'lib/src/lti/xapi_statement.dart': _ltiClock,
      },
      'flutter3d_mcp': <String, String>{
        'lib/src/kit/tool_table.dart':
            "`tut-16`'s own `onCall` hook: `ToolTableServer` reads a "
            '`Stopwatch` around a tool\'s own `run`, purely to hand a '
            'caller watching a screen (`ModelerCubit.agentToolCalled`, an '
            'MCP session\'s own tool-call feed) how long that one call '
            'took — nothing a tool\'s own answer reads back, the same '
            'observing-from-outside relationship `step_time_trace.dart` '
            'above already has. `onCall` is null on every server that has '
            'no screen watching (`flutter3d_mcp`\'s own `bin/'
            'model_mcp.dart`, `flutter3d_sim_mcp` included), so nothing '
            'here reaches the clock on a run this table\'s own rule '
            'actually cares about replaying bit-for-bit',
      },
      // The demos, scanned since step 8 of `tasks/0.9-plugins.md`.
      'flutter3d_demo_dungeon': <String, String>{
        'lib/main.dart':
            'a `Stopwatch` timing each live step for the frame overlay, '
            'observing the step from outside as `step_time_trace.dart` '
            'does, and `DateTime.now()` naming a screenshot file',
      },
      'flutter3d_demo_platformer': <String, String>{
        'lib/main.dart': '`DateTime.now()` names a screenshot file',
      },
      'flutter3d_demo_racing': <String, String>{
        'lib/main.dart': '`DateTime.now()` names a screenshot file',
        'lib/src/net_race_session.dart':
            'an unseeded `Random()` makes the five letters of a room code two '
            'people read to each other before a race; nothing in the race '
            'reads it',
      },
      'flutter3d_demo_sandbox': <String, String>{
        'lib/main.dart': '`DateTime.now()` names a screenshot file',
      },
    };

/// Files in `flutter3d_hardware` allowed to name Flutter, and why.
///
/// **Empty since `GraphicsDevice.present` moved to `presentFrame` in
/// `flutter3d_app` (mcp-01n).** `graphics_device.dart` and
/// `testing_fake_backend.dart` were the only two files this ever excused, both
/// for the same method; nothing here names Flutter now, and this map stays
/// rather than being deleted so a future exception has to be written down
/// again rather than the check quietly reopening.
///
/// The `flutter_gpu` half of that rule has no exceptions and never will. The
/// Flutter half is narrower than it looks: it is there to stop Flutter's
/// vocabulary leaking into this one, and `PixelFormat` is the collision it was
/// written for — already handled by naming ours `TextureFormat`.
///
/// **`package:flutter/` is banned as well as `dart:ui`, on purpose.** Widgets
/// re-export half of `dart:ui`, so a rule naming only `dart:ui` would let the
/// whole of Flutter in through a technicality, and an exemption here would be
/// documenting a loophole rather than a decision.
const Map<String, String> hardwareMayUseFlutter = <String, String>{};

/// Files in `flutter3d` that must still compile with `dart compile exe`, and
/// why — checked **through their imports**, not just their own text.
///
/// **Checked through imports rather than one file's own text is the whole
/// point.** A rule reading a single file's own source for `dart:ui` — this
/// package's `flutter3d_core` used to carry exactly one, for the same reason
/// `frame_resources.dart` needed one before mcp-03n moved it there, and
/// `flatDartPackages` now holds every file in that package to it, not one —
/// would have missed how this actually broke: `mesh_geometry.dart` declared both
/// `MeshGeometry`, which needs no device, and `DeviceMesh`, which holds two
/// buffers a device made. One `flutter3d_hardware` import served both. Through
/// it `geometry.dart` reached `GraphicsDevice`, whose `present` returns a
/// `Widget` — so every file that generated or decoded a mesh reached
/// `package:flutter/widgets.dart`, four hops away and named nowhere.
///
/// Nothing failed on a device, which is why it survived. What failed was
/// `dart compile exe`, where `dart:ui` does not exist: the benchmark stopped
/// building, and the numbers in ARCHITECTURE.md §14 became numbers nobody could
/// re-run. A rule that reads single files would have stayed green throughout.
const Map<String, String> engineCompilesOffDevice = <String, String>{
  'tool/bench/bench.dart':
      'the benchmark is compiled ahead of time on purpose, so that the figures '
      'in ARCHITECTURE.md §14 come from the pipeline a release build uses — a '
      'suite that cannot be compiled produces numbers that cannot be '
      'contradicted',
  // The CPU geometry layer used to be named here, as `lib/src/engine/geometry/
  // geometry.dart`. It is `flutter3d_core`'s geometry library now, in a
  // package with no Flutter SDK in its pubspec at all, and `a flat Dart package
  // resolves without the Flutter SDK` holds it to something stronger than this
  // rule could: not "no import reaches Flutter today" but "no dependency
  // could".
};

/// Sentences that say a number of scenes and are not claims about how many
/// there are, with the fragment that identifies each and why it is spared.
///
/// **The rule reads Dart now, and Dart is where this repository keeps its
/// history.** A comment saying "thirty goldens leaked thirty of them" is right
/// about the afternoon it describes and would be a lie rewritten to say
/// thirty-nine; a comment saying "two goldens caught it at 25% and 0.6%" counts
/// the two that caught a bug, not the set. Both read exactly like the claims the
/// rule exists to recount, and no phrasing tells them apart — which is why this
/// is a table of sentences rather than a cleverer regular expression.
///
/// The key is a fragment of the sentence *as the prose reads*, wrap undone. It
/// has to span the number, and `_exemptionsResolve` checks that it is still in
/// the file: rewrite the sentence and the exemption stops applying, which is the
/// direction that matters. An exemption that outlives its sentence is the rule
/// quietly narrower than it reads.
const Map<String, Map<String, String>>
goldenCountExempt = <String, Map<String, String>>{
  // History: right about the day it describes.
  'packages/flutter3d/example/lib/src/spike/golden_extras.dart':
      <String, String>{
        'all twenty-seven goldens came back byte-identical':
            'the run that found the pool bug, on the day it was run',
      },
  'packages/flutter3d_core/lib/src/engine/render/renderer.dart':
      <String, String>{
        'gives all twenty-seven goldens byte-identical':
            'the experiment that settled the registration order, as it was run',
      },
  'packages/flutter3d/test/xray_test.dart': <String, String>{
    'a call thirty-four goldens were recorded without':
        'the recording those goldens came from; a later set does not '
        'change what that one was recorded without',
  },
  'packages/flutter3d_testing/lib/src/golden.dart': <String, String>{
    'thirty goldens leaked thirty of them':
        'the leak as it was found, and the second number is the first',
  },
  'packages/flutter3d/test/ssao_test.dart': <String, String>{
    'carried "thirty-one goldens" for eight scenes':
        'the wrong number this rule was extended to catch, quoted. Both '
        'numbers in it are about the drift, not about today',
  },
  'packages/flutter3d_webgl/test/bloom_orientation_test.dart': <String, String>{
    'thirty-two goldens did not':
        'the set on the day a flipped blit got past it',
  },
  'packages/flutter3d/example/lib/src/spike/golden_store_io.dart':
      <String, String>{
        'so forty-three scenes meant':
            'the size of the set on the day the dart-define build was '
            'measured and abandoned; the megabytes and the count are both '
            'about that afternoon',
      },
  'tool/structure/rules.dart': <String, String>{
    '"thirty scenes" in `tool/ci.sh`':
        'the three wrong answers this rule was written for, quoted',
    '"twenty-six scenes" in `golden_web.sh`': 'the same three',
    '"32 scenes" in `ARCHITECTURE.md`': 'the same three',
    'still saying "thirty scenes" two recounts later':
        'why the prose pages are scanned, told as what happened',
    'said "thirty-one goldens" for eight scenes':
        'the drift that made the rule read Dart, quoted from the file it '
        'was found in',
  },

  // A subset: the number is right about some of them.
  'packages/flutter3d/example/lib/cpu_main.dart': <String, String>{
    'Two scenes, switched with the space bar':
        'the example application\'s two scenes, which are not a golden set',
  },
  'packages/flutter3d_core/lib/src/formats/lighting_model.dart':
      <String, String>{
        'Two goldens caught it at 25% and 0.6%':
            'the two that caught it, named with what each one showed',
      },
  'packages/flutter3d/test/lighting_model_test.dart': <String, String>{
    'which two goldens found at 25% and 0.6%': 'the same two',
  },
  'packages/flutter3d_cpu/lib/src/cpu_encoder.dart': <String, String>{
    'the twenty-seven scenes that have no mip chain':
        'the scenes without a mip chain, which is fewer than all of them',
  },
  'packages/flutter3d/test/engine_parity_test.dart': <String, String>{
    'the lesson of two goldens that sat at 0.178%':
        'the two that sat under a threshold nobody was reading',
  },
  'packages/flutter3d_webgl/test/engine_parity_test.dart': <String, String>{
    'how two goldens sat under one': 'the same two',
    'the lesson of two goldens that sat at 0.178%': 'the same two',
    'equal on both backends across six scenes': 'the six the atlas appeared in',
  },
  'packages/flutter3d_webgl/lib/engine_shaders.dart': <String, String>{
    'equal on both backends across six scenes':
        'the six the atlas appeared in, restated in each generated shader',
  },
  'packages/flutter3d_webgl/test/cross_backend_test.dart': <String, String>{
    'Seven scenes have been in the second group':
        'the seven that disagreed by whole percents, counted across the life '
        'of this backend rather than today',
    'the three scenes that were exactly': 'the three that were exactly zero',
  },
  // ARCHITECTURE.md's four are the same species, written up rather than in
  // a comment: each counts the scenes one measurement touched.
  'ARCHITECTURE.md': <String, String>{
    'five scenes passed through it': 'the five that passed one merge',
    'Six scenes disagreed by whole percents':
        'the six the third set found on the day it was recorded',
    'the three scenes that were': 'the three that were exactly zero',
    'Six scenes were in whole percents': 'the same six',
    'While WebGPU had 42 of the 43 scenes recorded':
        'the count as it stood on the branch that recorded WebGPU\'s set, '
        'before mesh-overlay existed to make either number bigger',
  },
};

/// Calls that put a document's contents into a world, or dress what it built.
///
/// Each is something a shipped game does exactly once, and a second caller is a
/// second answer to "what is in this level" — which will disagree with the
/// first, not today but on the day somebody adds a field to one of them.
///
/// **Deliberately not the simulation constructors**, and this list was narrowed
/// after they were tried: `slope_test.dart` builds a bare `PlatformerSimulation`
/// on purpose, because it measures the shape of a level's brushes and spawning
/// its entities would put a crate in the way. Those are narrower harnesses, not
/// second assemblies, and a rule calling them offenders is a rule people learn
/// to route around.
const List<String> assemblyCalls = <String>[
  'spawnInto(',
  'startSlot(',
  'ActorVisuals(',
  'FixtureVisuals(',
];

// ------------------------------------------------------------------ the tree

/// The repository root, found by walking up from wherever this was run.
///
/// Walked rather than assumed, so that `dart run tool/structure.dart` works
/// from a subdirectory — which is where somebody chasing one rule will be.
Directory get repositoryRoot {
  var dir = Directory.current;
  while (true) {
    final pubspec = File('${dir.path}/pubspec.yaml');
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('name: flutter3d_workspace')) {
      return dir;
    }
    final up = dir.parent;
    if (up.path == dir.path) {
      throw StateError(
        'no flutter3d_workspace pubspec above ${Directory.current.path} — '
        'run this from inside the repository',
      );
    }
    dir = up;
  }
}

/// Every package directory, by name: `packages/*`.
///
/// **`packages/addons/` is still read when it exists.** The game parts and
/// the post-processing families lived there, a directory down, until 1.0.0-rc.1
/// merged them into `flutter3d_game_kit`, `flutter3d_game_ui`,
/// `flutter3d_camera` and `flutter3d_post`; a package put there again is
/// covered by every rule the day it appears.
Map<String, Directory> get packages => <String, Directory>{
  ..._childrenOf('packages'),
  if (Directory('${repositoryRoot.path}/packages/addons').existsSync())
    ..._childrenOf('packages/addons'),
};

/// Every application directory, by name.
Map<String, Directory> get apps => _childrenOf('apps');

Map<String, Directory> _childrenOf(String what) {
  final root = repositoryRoot;
  final entries = Directory('${root.path}/$what')
      .listSync()
      .whereType<Directory>()
      .where((Directory d) => File('${d.path}/pubspec.yaml').existsSync());
  return <String, Directory>{
    for (final dir in entries) dir.path.split(Platform.pathSeparator).last: dir,
  };
}

/// Every `.dart` file under [dir], recursively, skipping build output.
///
/// `build/` and `.dart_tool/` hold copies of the very files being scanned, so a
/// walk that included them would report every offence twice and every path in a
/// form nobody can open.
List<File> dartFilesIn(Directory dir) {
  if (!dir.existsSync()) return const <File>[];
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((File f) => f.path.endsWith('.dart'))
      .where(
        (File f) =>
            !f.path.contains(
              '${Platform.pathSeparator}build${Platform.pathSeparator}',
            ) &&
            !f.path.contains('.dart_tool'),
      )
      .toList();
}

/// [file]'s path relative to [dir], in the form the rules and the exemption
/// tables use: forward slashes, no leading dot.
String relative(File file, Directory dir) => file.path
    .substring(dir.path.length + 1)
    .replaceAll(Platform.pathSeparator, '/');

/// Enums a published package may keep, and why each is machinery.
///
/// **The rule this feeds refuses an enum in a published package**, because a
/// published enum is a closed list somebody else's `switch` is written against:
/// adding a value to it is a breaking change, and for a package whose whole
/// purpose is that other people build on it, that is the wrong shape by
/// default. The audit that produced this table is `doc/boundary-0.5.0.md`.
///
/// What survives is machinery: a set that is finite, ours, and complete — the
/// backends' mirror of `flutter_gpu`, a document key the engine has to
/// understand to act on, a state the whole repository is built around. Content
/// — what a weapon fires, what a monster is doing, where an asset lives — is
/// not on this list, and four such enums were opened rather than added to it.
///
/// A file's entry names each enum and says why. An enum that appears in a
/// published package without a reason here fails the rule, which is the point:
/// the next one has to be argued for rather than typed.
const Map<String, Map<String, String>>
boundaryEnumExempt = <String, Map<String, String>>{
  'flutter3d_lints/lib/src/migration/migration_rule.dart': <String, String>{
    'MigrationKind':
        'private to the package (under src/, exported by no library): the '
        'three things the generated migration table asks of a resolved use. '
        'A new kind comes with the scan that carries it out, in the same '
        'commit, and nothing outside switches over it',
    'MigrationMatch':
        'private to the package for the same reason as MigrationKind: which '
        'uses a manual migration reports, read only by the scan beside it',
  },
  'flutter3d_sim/lib/src/actors/blackboard.dart': <String, String>{
    'BehaviorStatus':
        'success, failure and running are the whole algebra a behaviour '
        "tree's composites are defined over. A fourth is not an outcome a "
        "leaf is missing; it is a different kind of tree, and every "
        'composite would have to be rewritten for it anyway',
  },
  'flame_flutter3d/lib/src/world/grid_mover.dart': <String, String>{
    'GridHeading':
        'the four ways out of a square cell and standing still. A fifth '
        'would not be a heading this grid is missing — a square cell has '
        'no other side to leave by',
  },
  'flutter3d_sim/lib/src/input/game_action.dart': <String, String>{
    'ActionKind':
        'mirrors the sealed InputAction family one for one: button, axis, '
        'dual axis. A tape, a saved action map and a rebinding screen each '
        'write every kind down, so a fourth kind is a format change that '
        'comes with its own sealed subclass, not a value somebody adds',
  },
  'flutter3d_game/lib/src/input/action_map.dart': <String, String>{
    'CompositePart':
        'the two ends of a one-axis composite and the four directions of a '
        'two-axis one: the parts the two sealed composite bindings have. A '
        'composite with another part is another binding shape, sealed in the '
        'same file',
    'ConflictPolicy':
        'take, trade or refuse are the whole of what can be done with a '
        'source another action holds; ActionMap.rebind switches over them '
        'and nothing outside it does',
  },
  'flutter3d_education/lib/src/lti/lti_launch_claims.dart': <String, String>{
    'LtiMessageType':
        "the IMS LTI 1.3 core spec's own closed set of message types "
        '(`LtiResourceLinkRequest`, `LtiDeepLinkingRequest`, ...). A launch '
        "naming a sixth is not naming a message type this package's own "
        'switch is missing — it is not a valid LTI 1.3 launch',
  },
  'flutter3d_education/lib/src/lti/ags_score.dart': <String, String>{
    'AgsActivityProgress':
        "the IMS Assignment and Grade Services spec's own five values for "
        "how far a student got. A sixth is not this package's to invent",
    'AgsGradingProgress':
        "the same spec's own values for how far grading got, for the same "
        'reason',
  },
  'flutter3d_mesh/lib/src/recipes.dart': <String, String>{
    'RecipeCategory':
        'how a gallery groups the models this package builds, and the set '
        'is the gallery\'s own four sections rather than a taxonomy '
        'anybody outside switches over. The one `switch` is the heading a '
        'card draws; a fifth section is a fifth heading in that same file, '
        'not a case somebody else has to answer',
  },
  'flutter3d_editor_widgets/lib/src/number_expression.dart': <String, String>{
    'NumberUnit':
        'what one field\'s own numbers mean, and the set is the two things '
        'this application measures — a length and an angle — plus "neither". '
        'A `switch` over it lives in one function beside the enum, and a '
        'third kind of field would be a third kind of unit table in the same '
        'file rather than a new case anybody outside has to answer',
  },
  'flutter3d_core/lib/src/formats/gltf/gltf_accessor_type.dart':
      <String, String>{
        'GltfComponentType':
            "the glTF specification's own component types. The set is the "
            "format's, and a file that names a fifth is not a glTF file",
        'GltfAccessorType':
            "the same specification's accessor types, for the same reason",
      },
  'flutter3d_core/lib/src/formats/gltf/gltf_primitive_mode.dart':
      <String, String>{
        'GltfPrimitiveMode':
            "the glTF specification's seven primitive modes, numbered by the "
            'format',
      },
  'flutter3d_core/lib/src/formats/surface_material.dart': <String, String>{
    'SurfaceAlphaMode':
        "glTF's three alpha modes. A decoder for another format maps onto "
        'these; it does not add to them',
    'MaterialMap':
        "the five maps glTF's core material names, each read through its own "
        '`KHR_texture_transform` slot in the layered stage. A sixth map is a '
        'slot in that stage, not a value here',
    'TextureWrap':
        'the three wrap modes glTF names, which are also the three every '
        'GPU sampler has',
  },
  'flutter3d_core/lib/src/engine/render/material.dart': <String, String>{
    'MaterialAlphaMode':
        'the engine side of SurfaceAlphaMode, and a fourth would need a '
        'pipeline the shaders do not have',
  },
  'flutter3d_core/lib/src/formats/animation/animation_track.dart':
      <String, String>{
        'AnimationInterpolation':
            "glTF's three interpolations; the sampler implements exactly these",
        'AnimationPath':
            'the four channel targets glTF defines. A fifth is not a thing the '
            'format can express',
      },
  'flutter3d_core/lib/src/engine/animation/animation_target.dart':
      <String, String>{
        'AnimationWrap':
            'how a clip ends. Each value is a branch in the sampler, so a fifth '
            'is code rather than a name',
      },
  'flutter3d_model_core/lib/src/exporting.dart': <String, String>{
    'ExportFormat':
        'each value carries the writer that produces it — `f3d(F3dModelWriter())`, '
        '`glb(GlbModelWriter())` and the rest — so a fifth format is a `ModelWriter` '
        'somebody wrote, not a name added to a list. The one `switch` over it picks '
        'an extension in `bin/export.dart`, beside the enum, and a caller outside '
        'reads `ExportFormat.values` rather than naming cases',
    'TextureEncoding':
        'what an export does to its images, and the set is what the writers can '
        'actually produce. A sixth encoding is an encoder in `flutter3d_core`, not a '
        'value here; the switches over it live in this same file, choosing which of '
        'those encoders to call',
  },
  'flutter3d_core/lib/src/engine/animation/animation_layer.dart':
      <String, String>{
        'AnimationBlend':
            'how a layer meets the base. Both values are whole arithmetic in '
            'the player — one replaces a joint, the other adds a delta to it '
            'per path — so a third is a third set of formulas there rather '
            'than a name anybody outside has to answer',
      },
  'flutter3d_core/lib/src/engine/scene/light_node.dart': <String, String>{
    'LightType':
        'the three the lit shaders have code for. A fourth kind of light is '
        'a shader, not a value',
  },
  'flutter3d_core/lib/src/engine/scene/mesh_node.dart': <String, String>{
    'ShadowCastingMode':
        "the engine side of the level document's ShadowCasting, which is "
        'closed for the reason that one is',
  },
  'flutter3d_core/lib/src/engine/render/render_node.dart': <String, String>{
    'FramePhase':
        "the renderer's own passes, in the order it runs them. A phase it "
        'does not run is not a phase',
  },
  'flutter3d_core/lib/src/engine/render/render_view.dart': <String, String>{
    'SortMode':
        'the orders the renderer knows how to sort in. Each is code in the '
        'sort, not a label',
  },
  'flutter3d_core/lib/src/engine/render/composite_mix.dart': <String, String>{
    'CompositeView':
        'which buffer the composite shows. Each value is a branch in a '
        'shader that ships compiled',
  },
  'flutter3d_core/lib/src/engine/render/resource_desc.dart': <String, String>{
    'ResourceOrigin':
        'where a frame resource comes from, which the frame graph switches '
        'on to allocate it',
  },
  'flutter3d_core/lib/src/engine/render/shadow_settings.dart': <String, String>{
    'ShadowCasterFaces':
        'which faces go into the shadow map. Three ways to set cull state, '
        'and there is no fourth',
  },
  'flutter3d_core/lib/src/engine/render/parity_scene.dart': <String, String>{
    'ParityScene':
        'names the fixtures this repository compares across backends. '
        'Adding one is recording three golden sets, which is not something '
        'a caller does',
  },
  'flutter3d_core/lib/src/formats/model_loader.dart': <String, String>{
    'ModelFormat':
        'names the three decoders this package ships, plus auto. A format it '
        'does not ship never reaches this switch: a game supplies a '
        "ModelDecoder on the request and that decoder's own `handles` picks "
        'it, before any of these are consulted. Adding a value here means '
        'adding a decoder to this package',
  },
  'flutter3d_mesh/lib/src/attributes.dart': <String, String>{
    'MeshDomain':
        'the four things a half-edge mesh is made of — vertex, corner, edge, '
        'face. A fifth is not a value somebody passes; it is a different data '
        'structure, and every operation in the package switches on these four',
    'MeshAttribute':
        'the layers `EditMesh` stores. Adding one means adding an array to '
        'that class, so a caller cannot name a value this list does not have',
  },
  'flutter3d_mesh/lib/src/checks.dart': <String, String>{
    'IssueSeverity':
        'how much a check\'s finding matters: worth knowing, probably not '
        'what somebody meant, or will not survive being drawn. Three is what '
        'a panel can show and a person can triage, and a fourth would be a '
        'shade of one of these rather than a new kind of answer. The set of '
        '*findings* is open and is a value with instances, not an enum',
  },
  'flutter3d_mesh/lib/src/bsp.dart': <String, String>{
    'CsgOperation':
        'the three boolean operations a binary space partition answers — '
        'union, subtract, intersect. A fourth would need its own clip/invert '
        'recipe worked out from the same reference algorithm this file '
        'already transcribes the other three from, not a value slipped into '
        'an existing switch',
  },
  'flutter3d_model_core/lib/src/command.dart': <String, String>{
    'TransformPivot':
        'the three points a turn or a scale can be about: the middle of the '
        'selection, each object own centre, and the cursor. A fourth is not a '
        'value somebody passes — it is a place the interface would have to '
        'let a person put, which is a feature with its own control',
    'TransformSpace':
        'world axes or the object own. There is no third frame a transform '
        'can be expressed in that this editor has a control for; a gimbal or '
        'a parent frame would arrive with the rig that needs it',
  },
  'flutter3d_model_core/lib/src/project.dart': <String, String>{
    'ProfileTarget':
        'the three kinds of machine a profile is written for. A rule reading '
        'it switches on exactly these three, and a fourth — a console, say — '
        'is a shape of hardware nothing here has been measured against, not '
        'a value somebody passes to an existing rule',
  },
  'flutter3d_model_core/lib/src/object_commands.dart': <String, String>{
    'OriginPlacement':
        'where an object own origin goes: the middle of the bounds, the '
        'middle of the bottom, or the world origin. The first is what a spin '
        'wants, the second is what anything standing on a floor wants, and '
        'the third is how a model authored off-centre gets put back. A fourth '
        'would be a point somebody picks, and picking a point is the cursor, '
        'which is a control and not a value',
  },
  'flutter3d_model_core/lib/src/readiness.dart': <String, String>{
    'ExportSeverity':
        'whether the result will fail to load or merely disappoint. Those are '
        'the two answers an export dialogue can act on — refuse, or warn and '
        'let the person decide — and a third would be an answer with nothing '
        'to do about it',
  },
  'flutter3d_model_core/lib/src/selection.dart': <String, String>{
    'SelectionMode':
        'whether the modeller is pointing at objects or at parts of one mesh. '
        'The two are the modes the plan names, and a third would not be a '
        'value passed to anything — it would be a mode with its own tools, '
        'its own commands and its own panel, which is a feature rather than '
        'an enum value',
  },
  'flutter3d_mesh/lib/src/selection.dart': <String, String>{
    'ElementLevel':
        'the three things in a half-edge mesh a person can point at. A fourth '
        'is not a value somebody passes; every conversion, grow and shrink in '
        'the file switches on these three, and decision Б7 of the model '
        'editor plan chose an enum here over a sealed class for that reason',
  },
  'flutter3d_core/lib/src/formats/obj/obj_loader.dart': <String, String>{
    'ObjNormals':
        'what to do when an OBJ has no normals. Smooth or flat, and there '
        'is no third answer the decoder could give',
  },
  'flutter3d_model_core/lib/src/project_document.dart': <String, String>{
    'UpAxis':
        'the two conventions a 3D file actually uses. A third axis being '
        '"up" is not a thing any format this reads asks for',
  },
  'flutter3d_model_core/lib/src/autosave.dart': <String, String>{
    'RecoveryDecision':
        'open the file or offer the autosave — a two-way fork a dialog reads '
        'to know which button to show, and there is no third answer opening '
        'a project could need',
  },
  'flutter3d_model_core/lib/src/texture_info.dart': <String, String>{
    'TextureFileFormat':
        "the vkFormat families this file's own switch maps to a block "
        "layout — BC1/BC3/BC7/ETC2 RGBA8/ASTC 4×4, the set mat-30's encoder "
        'targets — plus rgba8 for a plain PNG/JPEG and other for every '
        'vkFormat none of those name. A format this does not recognise '
        'already falls into other rather than needing a new case, so a '
        'texture panel switching on this never sees a value it was not '
        'built for',
  },
  'flutter3d_model_core/lib/src/texture_graph.dart': <String, String>{
    'TextureValueType':
        "the two socket kinds mat-10's own texture compositor reads and "
        "writes — color and scalar. A third would be a new kind of data a "
        "texture slot could hold, not a value slipped into an existing "
        "node's switch, and every node's own inputs/outputType already "
        "names one of exactly these two",
    'TextureBlendMode':
        'the blend recipes this compositor bakes — normal, multiply, add, '
        'screen — a fixed list by the same Ж1 decision that fixed the node '
        "set itself. A fifth needs its own baked recipe worked out, the "
        "same way CsgOperation's own boolean recipes do, not a name added "
        "to an existing switch",
    'TextureChannel':
        'the four channels a colour has — r, g, b, a — which is not a '
        "number this format is ever going to grow a fifth of",
  },
  'flutter3d_model_core/lib/src/texture_resize.dart': <String, String>{
    'ResizeFilter':
        'the two ways `resizeRgba` samples a source image — an average '
        'over an area, or an interpolation between four points. A third '
        'resampling algorithm is a real feature, worth its own review, not '
        'a value slipped into the switch these two already are',
  },
  'flutter3d_model_core/lib/src/history.dart': <String, String>{
    'StepAuthor':
        "mcp-10n's own two hands on the keyboard — a person at the app, "
        'an agent over MCP. A third kind of author is a different feature '
        '(a second agent, a plugin) worth its own row, not a value added '
        'to the one switch an undo\'s own authorship check already is',
  },
  'flutter3d_core/lib/src/formats/stl/stl_loader.dart': <String, String>{
    'StlNormals':
        'whether a facet\'s own normal record is trusted or recomputed from '
        'its triangle. Unlike OBJ, STL always carries a normal, so this is a '
        'choice about how much to trust it rather than what to do when it is '
        'missing — and there is no third answer there either',
  },
  'flutter3d_core/lib/src/formats/model_light.dart': <String, String>{
    'ModelLightType':
        "`KHR_lights_punctual`'s own three light shapes. The extension "
        'defines exactly directional, point and spot; a fourth is not a '
        'thing a decoded document can honestly claim to hold',
  },
  'flutter3d_core/lib/src/engine/assets/model_writer.dart': <String, String>{
    'ModelWriteFormat':
        'the writers `flutter3d_formats` has: `ObjWriter`, `GltfWriter`, '
        '`F3dWriter`, `StlWriter` (binary and ASCII). A fifth value needs a '
        'fifth writer built and reviewed first — this enum only names the '
        'ones `encodeModel`\'s own switch already knows how to reach',
  },
  'flutter3d_webgpu/lib/src/webgpu_bundle_section.dart': <String, String>{
    'WebGpuTextureDimension':
        'the shapes of texture this backend has a bind group layout entry '
        'for, spelled the way WebGPU spells them. A value it does not have '
        'is a sampler declaration the shader translator refuses, so the set '
        'is closed at the far end of the pipeline rather than here',
  },
  'flutter3d_physics/lib/src/collider.dart': <String, String>{
    'ColliderKind':
        'the four the solver has paths for. A fifth kind is a solver '
        'change, not a value',
  },
  'flutter3d_physics/lib/src/collision_wedge.dart': <String, String>{
    'WedgeUphill':
        'which way a wedge rises. Four directions on a grid, and geometry '
        'has no fifth',
  },
  'flutter3d_sim/lib/src/level/brush.dart': <String, String>{
    'ShadowCasting':
        'a level document key. The engine has to understand it to act on '
        'it, so a document naming a mode this build does not know is a '
        'document it cannot draw — see doc/boundary-0.5.0.md',
  },
  'flutter3d_sim/lib/src/level/level_light.dart': <String, String>{
    'LevelLightType':
        "the document's spelling of LightType, closed for the reason that "
        'one is',
  },
  'flutter3d_sim/lib/src/level/level_issue.dart': <String, String>{
    'LevelIssueSeverity':
        'how badly a level is wrong. Three, and the validator decides what '
        'to do with each',
  },
  'flutter3d_sim/lib/src/world/mover.dart': <String, String>{
    'MoverState':
        'where a moving platform is in its cycle, which its own step '
        'drives. A game does not put it in a state the step cannot leave',
  },
  'flutter3d_sim/lib/src/loop/run_outcome.dart': <String, String>{
    'RunOutcome':
        'playing, won, lost. The vocabulary all three games and every '
        'screen are built on, and the same set RunStatus is sealed around',
  },
  'flutter3d_sim/lib/src/save/save_record.dart': <String, String>{
    'SaveResolution':
        'what can come of comparing two copies of one thing: they are the '
        'same, keep this one, keep that one, or nobody but the player can '
        'say. A fifth would not be an answer this comparison is missing',
  },
  'flutter3d_editor_core/lib/src/gizmos.dart': <String, String>{
    'Piece':
        'the three things a level document is made of, seen from an editor: '
        'geometry, a light, and everything else the document names. It is '
        'closed because the format is — a fourth member would be a fourth '
        'top-level list in Level, which is a document change and not a value',
  },
  'flutter3d_game_shooter/lib/src/simulation.dart': <String, String>{
    'GameState':
        'whether this simulation is running, over, or finished. Pausing and '
        "cutscenes belong to the application; these three are the step's "
        'own',
  },
  'flutter3d_game_platformer/lib/src/simulation.dart': <String, String>{
    'RunState': 'the same three the shooter has, in this genre',
  },
  'flutter3d_game_racing/lib/src/race_phase.dart': <String, String>{
    'RacePhase':
        'countdown, running, finished. The lights, the race and the end of '
        'it, driven by this package',
  },
  'flutter3d_sim_mcp/lib/src/playtest.dart': <String, String>{
    'PlaytestOutcome':
        'died, exited, stuck, or timed out — the four ways `Playtest.run`\'s '
        'own loop can decide a playthrough is over, tied to the parameters '
        '(`maxSteps`, `stuckAfter`) that same loop reads. Not content: a '
        'fifth way to end would be a fifth branch in that loop, not a '
        "monster or a weapon this package has never heard of",
  },
  'flutter3d_sim_mcp/lib/src/diagnostic_renderer.dart': <String, String>{
    'DiagnosticView':
        'lit, normals, shadowMap, staticShadowMap — the four debug outputs '
        '`RenderSettings` itself already knows how to produce. A fifth view '
        'would need a fifth setting on that class before this package could '
        'read it back at all; this enum only names what is already there, '
        'the same reason `RenderSettings.showShadowMap` and its siblings are '
        'booleans and not a growing list',
  },
  'flame_flutter3d/lib/src/transform/object3d_component.dart': <String, String>{
    'SyncDirection':
        'which of two sides writes a frame\'s transform into the other, and '
        'there are exactly two sides to a bridge between two engines. A '
        'third value would not be a third direction — there is nowhere else '
        'for a write to come from — so the `switch` beside it in the same '
        'file is exhaustive by the shape of the problem, not by omission',
  },
  'flame_flutter3d/lib/src/transform/plane.dart': <String, String>{
    'PlaneAxis':
        'which flutter3d axis, Y or Z, a bridge plane holds constant. A '
        'third case is not a third plane the game genres this package '
        'targets — top-down and side-scrolling — actually have; it would be '
        'a plane perpendicular to X, which reads as neither a ground nor a '
        'backdrop, and adding it is exactly the kind of case this rule '
        'wants argued for rather than typed. It is not, yet',
  },
  'flutter3d_sim/lib/src/level/level_sketch.dart': <String, String>{
    '_Axis':
        'private to the sketch: the two horizontal axes a wall runs '
        'along. There is no third horizontal axis',
  },
  'flutter3d_core/lib/src/formats/splat/splat_cloud.dart': <String, String>{
    'SplatColorSpace':
        "how a capture's colours were stored, which decides the one "
        'conversion the reader makes. A colour is stored encoded or it '
        'is not',
  },
  'flutter3d_core/lib/src/formats/animation/animation_pointer.dart':
      <String, String>{
        'AnimationPointerTarget':
            'the two objects `KHR_animation_pointer` paths reach that the '
            'player applies to. A third is code in `PointerTargets`, not a '
            'name',
        'AnimationPointerProperty':
            'the pointer paths the player knows how to apply, each carrying '
            'its component count. A path it cannot apply is refused on '
            'load, so a new one is code in the player first',
      },
  'flutter3d_core/lib/src/geometry/mesh_tangents.dart': <String, String>{
    'TangentMethod':
        'the two tangent frames the generator has code for: the one glTF '
        'and every baker assume, and a one-pass fast path. A third frame is '
        'a third generator in the same file before it is a value',
  },
  'flutter3d_core/lib/src/engine/render/renderer_shadow_pass.dart':
      <String, String>{
        '_StaticTile':
            'private to the shadow pass: what a static tile does this '
            'frame, one branch of the pass each',
      },
  'flutter3d_core/lib/src/engine/render/pass_contributor.dart':
      <String, String>{
        'ReactiveShape':
            'the coverage shapes `post/reactive_sprite.frag` has code for, '
            'in its order. A fourth is a shader branch before it is a value',
      },
  'flutter3d_core/lib/src/engine/render/render_settings.dart': <String, String>{
    'OutputTransform':
        'the curves the composite stage has code for and the swap-chain '
        'formats the backends expose. Another curve is shader code and '
        'a surface format first',
    'TransparencyMode':
        'the two ways the renderer composites what blends: the sorted '
        'pass and the weighted blended targets. Each is a pass of its '
        'own',
    'DiffuseModel':
        'the diffuse lobes the lit stages have code for, chosen by one '
        'frame-wide lane. A third lobe is a shader branch',
    'TemporalClip':
        'the axis tables the temporal resolve clips against, each a '
        'precomputed set the shader reads. Another size is another '
        'table',
  },
  'flutter3d_core/lib/src/engine/render/splat_contributor.dart':
      <String, String>{
        'SplatComposite':
            'how a splat cloud composites: sorted blending, a hashed test, '
            "or whichever the frame's temporal setting calls for. Each is a "
            'stage and a draw path',
      },
  'flutter3d_core/lib/src/engine/scene/occlusion/occlusion_test.dart':
      <String, String>{
        'OcclusionMode':
            'the occlusion tests the renderer runs: none, the software '
            "rasteriser's, and the depth pyramid's. Each is a pass the "
            'renderer schedules',
      },
  'flutter3d_model_core/lib/src/asset_audit.dart': <String, String>{
    'AuditCheck':
        'the checks `auditAsset` runs, each a function in the same file '
        'that a report groups its findings under. A sixth is a sixth '
        'function there',
  },
  'flutter3d_cpu/lib/src/cpu_encoder.dart': <String, String>{
    '_Storage':
        'private to the encoder: the three pixel storages the software '
        'rasteriser keeps a target in',
  },
};

/// Whole packages whose enums are all machinery, and the one reason each time.
///
/// Three packages mirror something they do not own — `flutter_gpu`'s pipeline
/// state, the gamepad the platform reports, the pointer lock the browser has —
/// and every value in them exists because the thing on the other side has it.
/// A third-party backend or platform implementation is obliged to handle all of
/// them, which is the definition of a set that is finite and not ours to grow
/// on a whim. Listing them one at a time would be the same sentence twenty-five
/// times.
///
/// Adding a value to one of these is still a breaking change and is still
/// recorded as one; see `doc/boundary-0.5.0.md`.
const Map<String, String> boundaryEnumPackageExempt = <String, String>{
  'flutter3d_hardware':
      'mirrors flutter_gpu. Every value is one the graphics API has, and a '
      'third-party backend must handle each of them',
  'pad_input':
      'mirrors what a gamepad platform reports. The buttons and axes are the '
      "device's, not this package's",
  'pointer_lock':
      "mirrors the platform's pointer lock, which has exactly these states",
};

/// Files inside a stepped package allowed to call the machine's `dart:math`.
///
/// **The rule and this table are about a run, not about accuracy.** A
/// transcendental in `dart:math` is the host's libm on the VM and the browser's
/// own routine on the web, and `flutter3d_sim/test/parity_test.dart` measured
/// that all ten of them give different bits in the two places — which cost a
/// car twenty-three of forty checkpoints. `Portable` is what a step calls
/// instead; see `flutter3d_sim/lib/src/math/portable_math.dart`.
///
/// Ten rather than nine because of `pow`, which is worth a sentence. On the one
/// machine the sweep first ran on it agreed in both places, and a function that
/// agrees on both runtimes of one machine looks like a function the
/// specification pins. A third machine, an x86-64 Ubuntu, disagreed with both —
/// so the agreement was two runtimes sharing one host's libm rather than a
/// guarantee, and `pow` joined the list a step may not call.
///
/// Everything below is outside a run: it decides what a frame *looks* like, or
/// it runs once before the game ships. Two platforms drawing a lamp a
/// ten-thousandth of a shade apart is not a divergence, and holding a camera to
/// this would be a cost with nothing bought. Each line says which it is, and a
/// file that stops being one of those stops being exempt.
const Map<String, Map<String, String>>
portableStepExempt = <String, Map<String, String>>{
  // The modeller's server was excused whole while it was a package of its
  // own (`notARepeatableStep` said "a server that answers a host"); in
  // `flutter3d_mcp` beside the kit and the level editor's server, the one
  // file that needs it says so.
  'flutter3d_mcp': <String, String>{
    'lib/src/model/render_tool.dart':
        'aims the camera a picture of a model is rendered through for an '
        'agent to look at; a picture is not a run, and nothing replays it',
  },
  'flutter3d_foundation': <String, String>{
    'lib/src/linear_color.dart':
        'the sRGB curve, applied when a colour a person picked enters the '
        'engine or leaves it for a swatch; a colour is what a frame looks '
        'like, and no snapshot or tape holds one',
  },
  'flame_flutter3d': <String, String>{
    'lib/src/debug/hitboxes3d.dart':
        'rings drawn round hitboxes for a person to look at; nothing steps '
        'on a debug line',
    'lib/src/embed/model3d_component.dart':
        'frames a camera on a model drawn into the canvas; the angle is '
        'where the picture is taken from and no run depends on it',
    'lib/src/transform/billboard_atlas.dart':
        'the quad a sprite card is drawn on, stood up once and shared; '
        'nothing steps on a vertex of it',
    'lib/src/transform/sprite_billboard_component.dart':
        'turns a sprite card to face the camera it is seen through; the '
        'component it draws is moved by Flame and never reads the turn',
  },
  'flutter3d_sim': <String, String>{
    'lib/src/world/light_fixture.dart':
        'how bright a lamp looks on a frame, which nothing steps on',
    'lib/src/level/lightmap_baker.dart':
        'runs once, before a level ships, and its output is committed',
    'lib/src/loop/pace.dart':
        'a dropped-frame meter, measured against the wall clock — it is '
        'already a thing no two machines agree about',
  },
  'flutter3d_game_kit': <String, String>{
    'lib/src/world/daylight.dart':
        'where the sun and the moon stand and how the sky is lit, moved on '
        'the frame for a person to look at; nothing steps on the hour',
    'lib/src/world/horizon.dart':
        'the ground and the sea past the simulated square, built once as '
        'meshes to be drawn; nothing collides with or steps on them',
    'lib/src/ghost/ghost.dart':
        'places the drawn ghost where a recorded track already says it '
        'was; a ghost is not in the collision world and nothing steps on '
        'where it stands',
  },
  'flutter3d_level_scene': <String, String>{
    'lib/src/level_scene.dart':
        'turns a level document into the nodes it is drawn with — meshes, '
        'lights, probes and decals; the simulation reads the document, '
        'never these',
  },
  'flutter3d_camera': <String, String>{
    'lib/src/camera_rig.dart':
        'a camera is where the picture is taken from; no run depends on it',
    'lib/src/photo_camera.dart':
        'flown only while the run is paused for a photo, and nothing it '
        'does reaches a snapshot or a tape',
    'lib/src/framing.dart':
        'where a camera wants to stand to keep its subjects in the picture; '
        'no step reads a camera and no run depends on where one was',
    'lib/src/presets.dart':
        'the genres\' cameras as framings, with the arithmetic they had '
        'before they moved here; a camera, as `chase_camera.dart` was',
    'lib/src/shake.dart':
        'how the view rattles after a blow. Its noise is seeded by the step '
        'so a replay shakes alike, but the shake itself is drawn and never '
        'stepped on, and a last-bit difference between two machines moves '
        'a picture, not a run',
  },
  'flutter3d_effects': <String, String>{
    'lib/src/fire_light.dart':
        'the lumens and colour a flame shows a person, worked out from a '
        'fire the core has already stepped; nothing steps on a light',
    'lib/src/liquid_view.dart':
        'the mist over falling water drawn for a person to look at; the '
        'water itself is the core\'s, already stepped',
    'lib/src/fire_view.dart':
        'tongues of flame, smoke and embers drawn for a person to look '
        'at, from fires the core has already stepped; nothing steps on '
        'a particle of them',
    'lib/src/physics_hearing.dart':
        'how loud the fires and the falls are to a listener, read off '
        'a world the core has already stepped; it steps nothing and '
        'nothing steps on what it says',
    'lib/src/liquid_shapes.dart':
        'the meshes a liquid in a vessel, a jet and its particles are drawn '
        'with, built from what the physics already stepped; nothing steps '
        'on a vertex of them',
  },
  'flutter3d_editor_core': <String, String>{
    'lib/src/picking.dart':
        'where a click points, given a camera. Nothing steps on it: the '
        'answer is compared against the boxes on one machine and then '
        'thrown away, and the document only ever records which box was '
        'chosen',
  },
  'flutter3d_stereo': <String, String>{
    'lib/src/stereo_viewer.dart':
        'the frustum a holder lens gives an eye, worked out on the device '
        'from the size of its own screen. A pose is stepped on; the shape '
        'of the picture around it is not, and two phones disagreeing in '
        'the last bit of a field of view change nothing a replay could '
        'notice',
    'lib/src/head_pose.dart':
        'turns a sensor reading into the frame the eye cameras look '
        'through. The reading is already different on every phone, and a '
        'game that steps on where the head looks steps on the pose it was '
        'handed, not on how it was worked out',
    'lib/src/stereo_rig.dart':
        'turns the stage the eye cameras stand on to a yaw the game has '
        'already stepped; a camera is where the picture is taken from',
  },
  'flutter3d_game_racing': <String, String>{
    'lib/src/sky.dart': 'the colour of the sky',
    'lib/src/chase_camera.dart': 'a camera',
  },
  'flutter3d_game_platformer': <String, String>{
    'lib/src/follow_camera.dart': 'a camera',
  },
  'flutter3d_demo_platformer': <String, String>{
    'lib/src/elements.dart':
        'water, fire and floating wood drawn in a physics world of their '
        'own, which reads the run and never writes to it; the air that '
        'drifts the wood and the lean it is held to steps nothing a '
        'replay or a ghost depends on',
    'lib/src/runner_looks.dart':
        'how the runner is drawn — squash, stretch and lean eased with '
        '`exp` — worked out from a runner the step already moved',
  },
  // The rest of the demos, scanned since step 8 of
  // `tasks/0.9-plugins.md`. What the scan first found inside a step, or
  // building the world before it, has moved onto `Portable`; what is left
  // here only draws.
  'flutter3d_demo_arcade': <String, String>{
    'lib/src/crafts.dart':
        'turns the model a craft is drawn with to face its course; the '
        'body it draws is stepped elsewhere and never reads the angle',
  },
  'flutter3d_demo_dungeon': <String, String>{
    'lib/src/wooden_props.dart':
        'the lathe of a barrel\'s and its hoops\' meshes, built once and '
        'uploaded to be drawn; nothing in the step reads a vertex of them',
    'lib/src/exit_door.dart':
        'stands the drawn arch where the level says the exit is; the step '
        'reads the exit from the level, never from the model',
    'lib/src/fixture_looks.dart':
        'what a torch, a lamp and a window look like; the fixture itself '
        'and its brightness are the simulation\'s, already stepped',
  },
  'flutter3d_demo_hollow': <String, String>{'lib/main.dart': _drawn},
  'flutter3d_demo_racing': <String, String>{
    'lib/reel_main.dart': _drawn,
    'lib/src/elements.dart':
        'water, fire and dust in a world of their own beside the race, '
        'which reads the cars and never writes to them; the laps, the '
        'ghosts and the demos are stepped without it',
  },
  'flutter3d_demo_reef': <String, String>{
    'lib/reel_main.dart': _drawn,
    'lib/src/diver.dart': _drawn,
    'lib/src/launch.dart': _drawn,
    'lib/src/reef_life.dart': _drawn,
  },
  'flutter3d_demo_river': <String, String>{
    'lib/src/pieces.dart':
        'the yaw a model is drawn at; Flame moves the piece and the '
        'bridge only draws it',
    'lib/src/river_water.dart': _drawn,
    'lib/src/craft.dart':
        'the yaw a craft\'s model is uploaded at, so it faces the way its '
        'body moves; the body is stepped elsewhere and never reads it',
    'lib/src/models.dart': _drawn,
  },
  'flutter3d_demo_sandbox': <String, String>{'lib/src/staging.dart': _drawn},
  'flutter3d_demo_strategy': <String, String>{
    'lib/reel_main.dart': _drawn,
    'lib/src/kit.dart': _drawn,
    'lib/src/effects.dart':
        'the map\'s water, fire and thrown stones drawn and heard from a '
        'world the match has already stepped; it never writes to it',
  },
  'flutter3d_demo_water': <String, String>{
    'lib/main.dart': _drawn,
    'lib/reel_main.dart': _drawn,
  },
  'flutter3d_lab_pendulum': <String, String>{
    'lib/main.dart':
        'places the drawn bob where the lab\'s angle says; the angle is '
        'stepped by `flutter3d_education`\'s lab library, which both rules '
        'scan',
  },
  'flutter3d_game_shooter': <String, String>{
    'lib/src/weapon_view.dart':
        'the weapon the player sees, not the one '
        'that fires',
  },
};

/// Where a world's or a substance's number may be written as a literal, by
/// file, by literal, with the reason.
///
/// **Each default is written once, where it is defined** — a world's in
/// `standard_world.dart`, a substance's on its preset — and everything else
/// reads the world or the preset. What is left here is the definitions
/// themselves, a law's own constant — the air a correlation was fitted in,
/// which no world's air may change — and numbers that only look like one of
/// a world's: a reason says which.
const Map<String, Map<String, String>> worldLiteralExempt =
    <String, Map<String, String>>{
      'flutter3d_matter/lib/src/standard_world.dart': <String, String>{
        '9.81': 'the definition of standardGravity',
        '293.15': 'the definition of standardAirTemperature',
        '1.204': 'the definition of standardAirDensity',
        '101325.0': 'the definition of standardAtmosphere',
        '343.0': 'the definition of standardSpeedOfSound',
      },
      'flutter3d_matter/lib/src/materials/materials.dart': <String, String>{
        '1025.0':
            'the definition of f3d.seawater — the sea\'s density is the '
            'catalogue entry\'s',
      },
      // A game's own world, set once where it stages (decision 1 of
      // tasks/1.0-physics-audit.md): everything in that game reads it from
      // the world these build.
      'flutter3d_game_shooter/lib/src/shooter_world.dart': <String, String>{
        '24.0': 'the shooter\'s world, `shooterWorld`, set where it stages',
      },
      'flutter3d_game_platformer/lib/src/runner.dart': <String, String>{
        '24.0':
            'the platformer\'s world, `platformerWorld`, set where it stages',
      },
      'flutter3d_game_racing/lib/src/racing_world.dart': <String, String>{
        '20.0': 'the racing game\'s world, `racingWorld`, set where it stages',
      },
      'flutter3d_sim/lib/src/procgen/erosion.dart': <String, String>{
        '4.0':
            'an erosion drop\'s unitless gain on its fall, a parameter of the '
            'algorithm and not any world\'s gravity',
      },
      'flutter3d_effects/lib/src/liquid_view.dart': <String, String>{
        '1.2':
            'the air in `mistShare`\'s correlation: the density the '
            'handbook\'s fit was made in (DOE-HDBK-3010-94, eq. 3-13), part '
            'of that law and not of any world\'s air',
      },
      'flutter3d_demo_platformer/lib/src/run_elements.dart': <String, String>{
        '1.204':
            'the cistern water\'s red absorption, per metre — a colour, '
            'which shares its digits with the air\'s density and nothing else',
      },
    };

/// A file format a 1.x build promises to keep reading: where its reader
/// declares the version it writes, which constant that is, and the fixture
/// minted at each version, with `<N>` standing for the version. [since] is
/// the oldest version the reader opens — 1 for every format so far.
typedef VersionedFormat = ({
  String reader,
  String constant,
  String fixture,
  int since,
});

/// **Every versioned format, and the fixture each of its versions is read
/// from** — decision 8 of `tasks/1.0-stability.md`. A 1.x engine reads every
/// 1.x file, so a version bump without a fixture is a promise nobody can
/// check; the rule that reads this fails on the bump, not on somebody's disk.
///
/// Keyed by the name a person calls the format. Paths are from the
/// repository root.
const Map<String, VersionedFormat> versionedFormats = <String, VersionedFormat>{
  '.f3d': (
    reader: 'packages/flutter3d_core/lib/src/formats/f3d/f3d_format.dart',
    constant: 'f3dVersion',
    fixture: 'packages/flutter3d_core/test/fixtures/v<N>/box.f3d',
    since: 1,
  ),
  '.fmat': (
    reader: 'packages/flutter3d_core/lib/src/formats/fmat/fmat.dart',
    constant: 'fmatVersion',
    fixture: 'packages/flutter3d_core/test/fixtures/v<N>/brass.fmat',
    since: 1,
  ),
  '.f3dmat': (
    reader:
        'packages/flutter3d_core/lib/src/formats/material_language/'
        'material_parser.dart',
    constant: 'materialLanguageVersion',
    fixture: 'packages/flutter3d_core/test/fixtures/v<N>/rim_glow.f3dmat',
    since: 1,
  ),
  '.f3dsplat': (
    reader: 'packages/flutter3d_core/lib/src/formats/splat/splat_octree.dart',
    constant: 'splatOctreeVersion',
    fixture: 'packages/flutter3d_core/test/fixtures/v<N>/one.f3dsplat',
    since: 1,
  ),
  'F3SB shader bundle': (
    reader: 'packages/flutter3d_hardware/lib/src/shader_bundle.dart',
    constant: 'formatVersion',
    fixture: 'packages/flutter3d_hardware/test/fixtures/v<N>/effects.f3shaders',
    since: 1,
  ),
  '.f3dtrace': (
    reader: 'packages/flutter3d_hardware/lib/src/trace/trace.dart',
    constant: 'formatVersion',
    fixture: 'packages/flutter3d_hardware/test/fixtures/v<N>/frame.f3dtrace',
    since: 1,
  ),
  '.f3dproj': (
    reader: 'packages/flutter3d_model_core/lib/src/project_format.dart',
    constant: 'projectVersion',
    fixture:
        'packages/flutter3d_model_core/test/fixtures/v<N>/workshop.f3dproj',
    since: 1,
  ),
  'level': (
    reader: 'packages/flutter3d_sim/lib/src/level/level.dart',
    constant: 'formatVersion',
    fixture: 'packages/flutter3d_sim/test/fixtures/v<N>/first.level.json',
    since: 1,
  ),
  'visibility table': (
    reader: 'packages/flutter3d_sim/lib/src/level/level_visibility.dart',
    constant: 'formatVersion',
    fixture: 'packages/flutter3d_sim/test/fixtures/v<N>/deep.visibility.json',
    since: 1,
  ),
  'lightmap': (
    reader: 'packages/flutter3d_sim/lib/src/level/lightmap.dart',
    constant: 'formatVersion',
    fixture: 'packages/flutter3d_sim/test/fixtures/v<N>/room.lightmap.bin',
    since: 1,
  ),
  'save': (
    reader: 'packages/flutter3d_sim/lib/src/save/snapshot.dart',
    constant: 'formatVersion',
    fixture: 'packages/flutter3d_sim/test/fixtures/v<N>/save.json',
    since: 1,
  ),
  '.f3drun': (
    reader: 'packages/flutter3d_sim/lib/src/save/demo.dart',
    constant: 'formatVersion',
    fixture: 'packages/flutter3d_sim/test/fixtures/v<N>/run.f3drun',
    since: 1,
  ),
  'input tape': (
    reader: 'packages/flutter3d_sim/lib/src/input/input_tape.dart',
    constant: 'formatVersion',
    fixture: 'packages/flutter3d_sim/test/fixtures/v<N>/input.tape.json',
    since: 1,
  ),
  'action map': (
    reader: 'packages/flutter3d_game/lib/src/input/action_map.dart',
    constant: 'formatVersion',
    fixture: 'packages/flutter3d_game/test/fixtures/v<N>/controls.actions.json',
    since: 1,
  ),
  'strategy match .f3drun': (
    reader: 'packages/flutter3d_game_strategy/lib/src/order_tape.dart',
    constant: 'formatVersion',
    fixture: 'packages/flutter3d_game_strategy/test/fixtures/v<N>/match.f3drun',
    since: 1,
  ),
  'share bundle': (
    reader: 'packages/flutter3d_sim/lib/src/share/share_bundle.dart',
    constant: 'formatVersion',
    fixture: 'packages/flutter3d_sim/test/fixtures/v<N>/first.share.json',
    since: 1,
  ),
  'telemetry upload': (
    reader: 'packages/flutter3d_sim/lib/src/telemetry/telemetry_upload.dart',
    constant: 'formatVersion',
    fixture: 'packages/flutter3d_sim/test/fixtures/v<N>/upload.json',
    since: 1,
  ),
  '.f3dfx': (
    reader: 'packages/flutter3d_particles/lib/src/effect_document.dart',
    constant: 'formatVersion',
    fixture: 'packages/flutter3d_particles/test/fixtures/v<N>/blast.f3dfx',
    since: 1,
  ),
  '.f3dplugin': (
    reader: 'packages/flutter3d_plugin_runtime/lib/src/data/data_plugin.dart',
    constant: 'formatVersion',
    fixture:
        'packages/flutter3d_plugin_runtime/test/fixtures/v<N>/glow.f3dplugin',
    since: 1,
  ),
  'track': (
    reader: 'packages/flutter3d_game_racing/lib/src/track_reader.dart',
    constant: 'formatVersion',
    fixture:
        'packages/flutter3d_game_racing/test/fixtures/v<N>/ring.track.json',
    since: 1,
  ),
};

/// Where a file format's code lives, for the rule that keeps enum ordinals
/// out of files: a directory (every Dart file under it) or one file, from the
/// repository root.
///
/// A binary format is where an ordinal hides best, because nothing reads
/// the number back as a word; the JSON formats write words from their wire
/// tables and are held by the envelope's own tests.
const List<String> formatCodePaths = <String>[
  'packages/flutter3d_core/lib/src/formats/f3d',
  'packages/flutter3d_core/lib/src/formats/fmat',
  'packages/flutter3d_hardware/lib/src/trace/trace.dart',
  'packages/flutter3d_hardware/lib/src/shader_bundle.dart',
  'packages/flutter3d_model_core/lib/src/project_format.dart',
];

/// Formats declared with a `FormatSpec` and no fixture, by id, with the
/// reason. Short on purpose: a format a 1.x build reads needs a file minted
/// at each version.
const Map<String, String> formatWithoutFixture = <String, String>{};

/// Libraries outside the simulation stack that still read a run's live
/// world, by `package/path`, with the work that takes each off the list.
const Map<String, String> readsSimulationWorld = <String, String>{
  'flutter3d_effects/lib/src/elements.dart':
      'the elements\' view and hearing take the native world itself; they '
      'move to probes and published components when probes land',
  'flutter3d_demo_platformer/lib/src/elements.dart':
      'the demo copies the world for its own scene; it moves to published '
      'state with the demos on the one view',
  'flutter3d_demo_hollow/lib/reel_main.dart':
      'the reel asks which roof burns; a probe answers it once the demos '
      'move to the one view',
  'flutter3d_demo_reef/lib/main.dart':
      'the depth gauge computes pressure from the world; a probe reads it '
      'once the demos move to the one view',
};

/// Version constants that number something other than a file a reader opens,
/// by `path#constant`, with the reason.
const Map<String, String> notAVersionedFormat = <String, String>{
  'packages/flutter3d_sim/lib/src/ecs/snapshots.dart#changesVersion':
      'a part version inside a run\'s snapshot, not a file: the run format '
      '(`f3d.run`) is the file, and its v5 fixture carries a capture at this '
      'part version while v1 to v4 carry the older one',
  'packages/flutter3d_editor_widgets/lib/src/dock_layout.dart#formatVersion':
      'the editor\'s panel arrangement, a per-person convenience file: one '
      'that does not read, or is newer, is the default layout, so there is '
      'no older file a release has to go on opening',
  'packages/flutter3d_build/lib/src/pipeline_version.dart#'
          'assetPipelineVersion':
      'a cache stamp: a mismatch reconverts the asset from its source, and '
      'there is no file of its own to read',
  'packages/flutter3d_core/lib/src/formats/splat/splat_spz.dart#'
          'spzLatestVersion':
      'SPZ is another project\'s format; the number is the newest of its '
      'versions this decoder knows, and its own suite reads each of them',
  'packages/flutter3d_shaders/lib/src/wgsl_section.dart#sectionVersion':
      'a section inside an F3SB bundle, a build artifact: flutter3d_build '
      'puts the number in the stamp it rebuilds bundles on, and a newer one '
      'is refused as stale',
  'packages/flutter3d_webgpu/lib/src/webgpu_loaded_shaders.dart#'
          'sectionVersion':
      'the reader of the section above, held equal to it by '
      '`wgsl_section_test.dart`; refused as stale, never kept',
  'packages/flutter3d_build/lib/src/cli_contract.dart#cliJsonVersion':
      'the shape of what `flutter3d --json` prints, read off stdout by a '
      'script and never opened as a file; it is written in the envelope '
      'every document carries, and the keys it covers are snapshotted in '
      '`api/flutter3d_build.cli` (`cliJsonBodies`)',
  'packages/flutter3d_voxel/lib/src/voxel_terrain.dart#generatorVersion':
      'the version of the drawing seeded terrain is made with, saved inside '
      'a voxel world beside the seed; the world document is the format '
      '(`VoxelWorld.format`, with its fixture), and a newer drawing is '
      'refused because its edits would land on other blocks',
  'packages/flutter3d_hardware/lib/src/shader_bundle.dart#'
          'materialSectionVersion':
      'a section inside an F3SB bundle; the bundle\'s own fixture carries it '
      'at version 1, and the build stamp rebuilds a bundle when it moves',
};

// ------------------------------------------------------- 1.0: base classes

/// `interface class` types that stay interfaces, by name, with the reason.
///
/// Decision 5 of `tasks/1.0-api-review.md`: a type somebody outside
/// implements is an `abstract base class` with default bodies, so a member
/// added in a minor release breaks nobody. The exceptions are pure markers
/// and value shapes, which have nothing to add and have to be implementable
/// beside a base class the implementer already extends. Keep this short:
/// every entry is a type that can never grow.
const Map<String, String> interfaceClassAllowed = <String, String>{
  'PlacedEvent':
      'a value shape, two getters saying where an effect goes, implemented '
      'by game events that already extend `BusEvent`, a base class; a class '
      'has one superclass, so this cannot be one',
  'StepClock':
      'implemented by Flame `Component`s, and `HasFixedStep` is a mixin on '
      '`FlameGame`; a base class would force every game class that mixes it '
      'in to be `base` or `final`. It does not grow: a new capability '
      'arrives as a type beside it (wave 3d decision)',
  'MixingBackend':
      'a capability an audio backend opts into beside `AudioBackend`, a '
      'base class (`extends AudioBackend implements MixingBackend`); a '
      'class has one superclass. A new capability is a new type beside it '
      '(wave 3d decision)',
  'DirectionalBackend':
      'a capability an audio backend opts into beside `AudioBackend`, as '
      '`MixingBackend` is (wave 3d decision)',
};

/// `interface class` types that wave 3 has not converted yet, by package.
///
/// **A to-do list, not an exemption.** This is every interface in the
/// snapshots on the day the rule was written (2026-10-08, wave 3 step 0). A
/// wave 3 agent who turns one into an `abstract base class` removes its
/// entry here in the same change, and the rule fails on an entry whose type
/// is no longer an interface, so the list only shrinks. A new interface is
/// not added here: it is a base class from the start, or it goes in
/// [interfaceClassAllowed] with its reason.
const Map<String, Set<String>> interfaceClassPending = <String, Set<String>>{
  'flame_flutter3d': <String>{'Bridged3d', 'Drawn3d', 'StepFollower'},
};

/// Exceptions not yet named `…Exception`, by name, with who renames them.
///
/// **A to-do list, not an exemption**, like [interfaceClassPending]: decision
/// H of `tasks/1.0-arch-review.md` names every thrown type `…Exception`, and
/// these three belong to the render and HAL work running beside the format
/// work that brought the rule in. The entry goes when its type is renamed
/// (the rule fails on an entry no snapshot declares), and a new exception is
/// named `…Exception` from the start.
const Map<String, String> exceptionNamePending = <String, String>{
  'GpuUnavailable':
      '`flutter3d_app`: what `openDevice` throws when no backend opens; the '
      'render/app agent renames it with the device-open work',
  'RenderRefusal':
      '`flutter3d_model_core`: a picture the modeller cannot draw headless; '
      'renamed with the render-snapshot work',
  'UnsupportedCapability':
      '`flutter3d_hardware`: the HAL contract CONTRIBUTING.md names by '
      'this word, fifty uses across the backends; renamed with the HAL '
      'pass that owns them',
};

// ------------------------------------------------------------ 1.0: naming

/// Names the naming rules of item 28 let stand, each with the reason. Keyed
/// by the subject a finding names (`Type.member`, or a bare name).
const Map<String, String> britishSpellingAllowed = <String, String>{};

/// Verbs the creation and teardown rule lets stand.
const Map<String, String> verbAllowed = <String, String>{
  'SimWorld.get':
      'the ECS pair `get`/`set` the review names for `SimWorld` (§C): a '
      'component is got and set, and neither is a creation',
  'EcsWorld.get': 'the implementation of `SimWorld.get`',
};

/// Unit-suffixed names the units rule lets stand.
const Map<String, String> unitSuffixAllowed = <String, String>{
  'degrees':
      'a value of the editor\'s `NumberUnit`: the widget that shows an angle '
      'to a person in degrees, which is where the contract says the '
      'conversion belongs',
};

/// Booleans the boolean rule lets stand.
const Map<String, String> booleanAllowed = <String, String>{
  'AnimationParameters.setBool':
      'the value written, as `setFloat` writes a `double`: the parameter is '
      'the datum, not a switch',
  'require':
      'an assertion: the condition is the subject of the call, as in '
      '`expect` and `assert`',
};

/// Settings-like types the settings rule lets stand.
const Map<String, String> settingsAllowed = <String, String>{
  'FormatSpec':
      'a declaration made to the `FormatRegistry`, named in docs/CONTRACTS.md '
      '— it describes a format, it does not tune one',
  'ToolSpec':
      'an MCP tool\'s declaration (decision 10 names it), not a setting',
  'WasmSystemSpec': 'a script system\'s declaration to the Wasm host',
  'ScriptSystemSpec': 'a script system\'s declaration to the runtime',
  'WasmFieldSpec': 'a field\'s declaration to the Wasm host',
  'DebrisSettings':
      'its defaults come from the world it is given (`world.gravity`), which '
      'a `const` constructor cannot read',
  'FluidSettings': 'as `DebrisSettings`: defaults from the world',
};

/// Each published package's public `double` fields and getters whose doc
/// names no unit, counted on the day the rule landed (1113 in all) and
/// written down since to five. The rule holds each package at or under its
/// number, so the table only shrinks. The five left are the `float` uniforms
/// of `flutter3d_effects`'s generated `materials.g.dart`: what unit they have
/// is written, where at all, in the `.f3dmat` comment above each uniform, and
/// the accessor generator does not carry that comment into the doc yet.
const Map<String, int> unitsUndocumentedPending = <String, int>{
  'flutter3d_effects': 5,
};
