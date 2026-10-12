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
  'flutter3d_playground',
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
  'flutter3d_app -> flutter3d_build':
      '`level_loader_test.dart` loads levels with lightmaps baked for the '
      'test; the baker is a build step and the loader may not depend on a '
      'build tool, so the bake for the test comes from the package above',
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
  'flutter3d_wgpu -> flutter3d_conformance':
      'the contract suite\'s compute and sharing checks, run against the '
      'wgpu sidecar',
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
  'flutter3d_pointer_lock': 'a platform channel',
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
      'flutter3d_net': <String, String>{
        'lib/src/rollback_clock.dart':
            'a profiler observing a rollback from outside its steps: '
            '`RollbackSession.stats` reads a `Stopwatch` to time each step '
            'run again, and the times go into the stats nothing in the '
            'simulation reads back, as `step_time_trace.dart` does for a '
            'step',
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
/// What survives since 1.0 is a set closed for good, whose members are fixed by
/// what the type means (a direction, a sign, a yes or a no, a specification's
/// own frozen list), or one nothing outside can reach: private, or exported by
/// no library. The public ones are in [closedForGood] too, which the rule
/// `a public enum or sealed type is decided` reads against the snapshots.
/// Machinery that merely mirrors something (`flutter_gpu`'s state, a document
/// key) was opened rather than kept here, because the thing it mirrors grows.
///
/// A file's entry names each enum and says why. An enum that appears in a
/// published package without a reason here fails the rule, which is the point:
/// the next one has to be argued for rather than typed.
const Map<String, Map<String, String>>
boundaryEnumExempt = <String, Map<String, String>>{
  'flutter3d_lints/lib/src/migration/migration_rule.dart': <String, String>{
    'MigrationKind':
        'private to the package (under src/, exported by no library): the '
        'three things the generated migration table asks of a resolved use. A '
        'new kind comes with the scan that carries it out, in the same '
        'commit, and nothing outside switches over it',
    'MigrationMatch':
        'private to the package for the same reason as MigrationKind: which '
        'uses a manual migration reports, read only by the scan beside it',
  },
  'flame_flutter3d/lib/src/world/grid_mover.dart': <String, String>{
    'GridHeading':
        'closed for good, as `closedForGood` says: the four ways out of a '
        'square cell, and standing still: a square has no fifth side to leave '
        'by',
  },
  'flame_flutter3d/lib/src/transform/object3d_component.dart': <String, String>{
    'SyncDirection':
        'closed for good, as `closedForGood` says: which of the two engines '
        "writes the other's transform: a bridge has two ends, and a write "
        'comes from one of them',
  },
  'flutter3d_education/lib/src/lti/ags_score.dart': <String, String>{
    'AgsActivityProgress':
        'closed for good, as `closedForGood` says: the five values of IMS '
        'Assignment and Grade Services 2.0: the specification carries its own '
        'version, and another value is another version of it',
    'AgsGradingProgress':
        'closed for good, as `closedForGood` says: the five values of IMS '
        'Assignment and Grade Services 2.0: the specification carries its own '
        'version, and another value is another version of it',
  },
  'flutter3d_core/lib/src/formats/gltf/gltf_accessor_type.dart': <String, String>{
    'GltfComponentType':
        "closed for good, as `closedForGood` says: glTF 2.0's own component "
        'types: the specification is versioned, and a file naming another is '
        'not glTF 2.0',
    'GltfAccessorType':
        "closed for good, as `closedForGood` says: glTF 2.0's own accessor "
        'types: the specification is versioned, and a file naming another is '
        'not glTF 2.0',
  },
  'flutter3d_core/lib/src/formats/gltf/gltf_primitive_mode.dart': <String, String>{
    'GltfPrimitiveMode':
        "closed for good, as `closedForGood` says: glTF 2.0's seven primitive "
        'modes, numbered by the format: the specification is versioned, and a '
        'file naming an eighth is not glTF 2.0',
  },
  'flutter3d_core/lib/src/engine/render/shadow_settings.dart': <String, String>{
    'ShadowCasterFaces':
        'closed for good, as `closedForGood` says: front, back or both: every '
        "non-empty set of a triangle's two faces",
  },
  'flutter3d_core/lib/src/engine/render/composite_mix.dart': <String, String>{
    'CompositeView':
        'exported by no library: which buffer the composite shows, each value '
        'a branch in a shader that ships compiled',
  },
  'flutter3d_core/lib/src/engine/render/parity_scene.dart': <String, String>{
    'ParityScene':
        'exported by no library: names the fixtures this repository compares '
        'across backends. Adding one is recording three golden sets, which is '
        'not something a caller does',
  },
  'flutter3d_core/lib/src/engine/render/renderer_shadow_pass.dart':
      <String, String>{
        '_StaticTile':
            'private to the shadow pass: what a static tile does this frame, one '
            'branch of the pass each',
      },
  'flutter3d_cpu/lib/src/cpu_encoder.dart': <String, String>{
    '_Storage':
        'private to the encoder: the three pixel storages the software '
        'rasteriser keeps a target in',
  },
  'flutter3d_webgpu/lib/src/webgpu_bundle_section.dart': <String, String>{
    'WebGpuTextureDimension':
        'exported by no library: the shapes of texture this backend has a '
        'bind group layout entry for, spelled the way WebGPU spells them',
  },
  'flutter3d_physics/lib/src/collision_wedge.dart': <String, String>{
    'WedgeUphill':
        'closed for good, as `closedForGood` says: the four horizontal '
        'directions of the grid a wedge rises towards: a grid has no fifth',
  },
  'flutter3d_sim/lib/src/level/level_sketch.dart': <String, String>{
    '_Axis':
        'private to the sketch: the two horizontal axes a wall runs along. '
        'There is no third horizontal axis',
  },
  'flutter3d_model_core/lib/src/texture_graph.dart': <String, String>{
    'TextureChannel':
        'closed for good, as `closedForGood` says: r, g, b and a: the four '
        'channels of an RGBA colour',
  },
  'flutter3d_model_core/lib/src/autosave.dart': <String, String>{
    'RecoveryDecision':
        'closed for good, as `closedForGood` says: open the saved file or '
        'offer the autosave: the two answers to whether the autosave is newer',
  },
  'flutter3d_hardware/lib/src/formats.dart': <String, String>{
    'WindingOrder':
        'closed for good, as `closedForGood` says: clockwise or '
        'counter-clockwise: the two orientations a triangle has',
    'CompareFunction':
        'closed for good, as `closedForGood` says: never, always and the six '
        'comparisons: every function from less, equal and greater to pass or '
        'fail',
    'StencilFace':
        'closed for good, as `closedForGood` says: front, back or both: every '
        "non-empty set of a triangle's two faces",
    'FramebufferOrigin':
        'closed for good, as `closedForGood` says: whether row zero is the '
        'top or the bottom: the sign of the y axis',
  },
  'flutter3d_hardware/lib/src/resources.dart': <String, String>{
    'StorageTextureAccess':
        'closed for good, as `closedForGood` says: read, write, or both: '
        'every non-empty set of the two ways to touch a texel',
  },
  'pad_input/lib/src/gamepad_platform_interface.dart': <String, String>{
    'PadConnection':
        'closed for good, as `closedForGood` says: connected or not: a yes or '
        'a no, kept as two states for which way it changed',
  },
  'flutter3d_pointer_lock/lib/src/pointer_lock_platform_interface.dart':
      <String, String>{
        'CaptureState':
            'closed for good, as `closedForGood` says: captured or released: a '
            'yes or a no, kept as two states for who released it',
      },
};

/// Whole packages whose enums are all machinery, and the one reason each time.
///
/// Empty since 1.0. Three packages used to be here because they mirror
/// something they do not own (`flutter_gpu`'s pipeline state, a gamepad, the
/// browser's pointer lock), but a mirrored set still grows when the thing on
/// the other side does, and that growth is exactly what an enum cannot take
/// in a minor release. What is left of them is one closed enum each, named
/// above with its reason like any other.
const Map<String, String> boundaryEnumPackageExempt = <String, String>{};

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

/// Libraries that are where a substance's numbers are written, whole, each
/// with its reason: `a world's gravity, air and sea are read from the
/// world` reads none of them.
const Map<String, String> worldLiteralCatalogues = <String, String>{
  'flutter3d_matter/lib/src/materials/materials.g.dart':
      'the material catalogue, generated from its data: f3d.air\'s density, '
      'f3d.seawater\'s, a law\'s points at 20 °C and the sources quoting '
      'them are what the rule sends a reader to',
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

/// Where each property of a world and each group of a material is read, as
/// `package/lib/...`: one library of a package other than
/// `flutter3d_matter` that reads it, for `every world property and material
/// group has a reader`. One is enough; it is the proof that the number goes
/// somewhere, not a list of every use.
const Map<String, String> propertyReaders = <String, String>{
  'WorldProperties.gravity':
      'flutter3d_physics_native/lib/src/native_dynamics.dart',
  'WorldProperties.gravityMagnitude':
      'flutter3d_physics/lib/src/cloth/cloth_settings.dart',
  'WorldProperties.wind': 'flutter3d_physics/lib/src/cloth/cloth_settings.dart',
  'WorldProperties.airDensity':
      'flutter3d_physics/lib/src/cloth/cloth_settings.dart',
  'WorldProperties.airDensityOverride':
      'flutter3d_game_racing/lib/src/vehicle/sphere_vehicle.dart',
  'WorldProperties.airTemperature':
      'flutter3d_physics_native/lib/src/native_world.dart',
  'WorldProperties.airPressure':
      'flutter3d_physics_native/lib/src/native_world.dart',
  'WorldProperties.medium': 'flutter3d_sim/lib/src/level/level.dart',
  'WorldProperties.profile':
      'flutter3d_physics/lib/src/cloth/cloth_settings.dart',
  'WorldProperties.speedOfSound': 'flutter3d_audio_core/lib/src/spatial.dart',
  'WorldProperties.geoOrigin': 'flutter3d_app/lib/src/xr/xr_anchor.dart',
  'PhysicalMaterial.mechanical':
      'flutter3d_physics/lib/src/cloth/cloth_settings.dart',
  'PhysicalMaterial.fluid': 'flutter3d_physics/lib/src/fluid/fluid_medium.dart',
  'PhysicalMaterial.thermal':
      'flutter3d_physics_native/lib/src/native_world.dart',
  'PhysicalMaterial.acoustic':
      'flutter3d_game/lib/src/visuals/sound_occlusion.dart',
  'PhysicalMaterial.optical': 'flutter3d_level_scene/lib/src/level_scene.dart',
  'PhysicalMaterial.electrical':
      'flutter3d_physics_native/lib/src/native_world.dart',
  'PhysicalMaterial.inelastic': 'flutter3d_physics/lib/src/impact_loss.dart',
};

/// Properties with no reader yet, with what would read one.
///
/// **A to-do list, not an exemption**, like [hookParametersPending]: the
/// rule passes these while no library reads them and fails on an entry once
/// one is named in [propertyReaders], so the list only shrinks. A property
/// added from now on is not added here; it comes with its reader.
const Map<String, String> propertyReadersPending = <String, String>{};

/// The packages and applications that promise WCAG 2.2 at level AA, with
/// what the promise covers (decision 34 of the readiness review).
///
/// **A promise a rule can see.** For each, `a package that promises WCAG AA
/// keeps it` reads its libraries — no colour typed outside
/// [accessibleColorsAllowed], no pinned text size, no `TextPainter` without
/// a scaler, no control a screen reader cannot name, no animation in a
/// library that never asks for reduced motion — and finds its
/// `test/accessibility_test.dart`, which `tool/ci.sh` runs in every package and
/// application that carries one. The demo games are best effort and are not
/// here.
const Map<String, String> accessibleUis = <String, String>{
  'flutter3d_game_ui':
      'every widget around a game: the heads-up display, the touch '
      'controls, the settings, the screens, photo mode and sharing',
  'flutter3d_lesson_viewer':
      'the lesson viewer for the laboratory audience: Semantics on every '
      'control, the textScaler, the focus order and the reduced-motion flag',
  'flutter3d_lab_pendulum':
      'the pendulum laboratory: its length as a slider a screen reader and '
      'a keyboard reach, the pause for reduced motion',
};

/// Where a package of [accessibleUis] may type a colour in, by file under
/// the package, with the reason.
const Map<String, String> accessibleColorsAllowed = <String, String>{
  'flutter3d_game_ui/lib/src/theme/game_ui_theme.dart':
      'the tokens themselves, held to their ratios over any frame by '
      '`GameUiTheme.contrastPairs` and the accessibility test',
  'flutter3d_game_ui/lib/src/theme/contrast.dart':
      'the arithmetic: the clear background a pair defaults to, and the '
      'colour a blend makes',
  'flutter3d_lesson_viewer/lib/src/lesson_theme.dart':
      'the viewer\'s tokens themselves, each in one of `LessonTheme.pairs`, '
      'held to its ratio over any frame by test/theme_contrast_test.dart',
  'flutter3d_lab_pendulum/lib/src/lab_theme.dart':
      'the lab\'s tokens themselves, each in one of `LabTheme.pairs`, held '
      'to its ratio over any frame by test/theme_contrast_test.dart',
};

/// Applications whose promise is not kept yet, with when it will be.
///
/// **A to-do list, not an exemption**, like [propertyReadersPending]: the
/// rule fails on an entry that already carries
/// `test/accessibility_test.dart`, so it moves to [accessibleUis] the day it can be held.
const Map<String, String> accessibleUisPending = <String, String>{};

/// Fixtures a format's reader is held to beyond its one per version: a
/// section added at a version, which a file of every version since has to
/// carry, by the format's name in [versionedFormats], with the version it
/// came in and the fixture's path, `<N>` standing for the version.
const Map<String, Map<String, ({int since, String fixture})>>
formatSectionFixtures = <String, Map<String, ({int since, String fixture})>>{
  '.f3d': <String, ({int since, String fixture})>{
    'physicalMaterials, section 36': (
      since: 2,
      fixture: 'packages/flutter3d_core/test/fixtures/v<N>/physical.f3d',
    ),
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
  'packages/flutter3d_hub/lib/src/hub_reference.dart#maxVersion':
      'the largest version of a model on the hub a reference can name, '
      'which is no file a reader opens: the reference format itself has no '
      'version and never gains one, and its fixture is '
      'test/fixtures/references.json',
  'packages/flutter3d_core/lib/src/formats/material_language/material_ast.dart#materialLanguageFirstVersion':
      'a version of `.f3dmat` that `f3dmatFormat` already lists, the one a '
      'file with no version line is; its fixture is v1/rim_glow.f3dmat',
  'packages/flutter3d_core/lib/src/formats/material_language/material_parser.dart#materialLanguageStagesVersion':
      'the `.f3dmat` version that brought the stages, one `f3dmatFormat` '
      'already lists; its fixture is v2/rim_glow.f3dmat',
  'packages/flutter3d_core/lib/src/formats/material_language/material_parser.dart#materialLanguageUpdatesVersion':
      'the `.f3dmat` version that brought a material\'s own version, one '
      '`f3dmatFormat` already lists; its fixture is v3/rim_glow.f3dmat',
  'packages/flutter3d_core/lib/src/formats/material_language/material_ast.dart#firstMaterialVersion':
      'a material\'s own version counts its parameters\' changes, written '
      'inside the `.f3dmat` file and beside an instance in a level, and is '
      'no file a reader opens',
  'packages/flutter3d_foundation/lib/src/expressions/expression_bytecode.dart#expressionBytecodeVersion':
      'the version of an internal bytecode no file carries in 1.0: it is '
      'compiled in memory and run there, and becomes a format, with '
      'fixtures, only when a minor publishes it',
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
  'packages/flutter3d_hardware/lib/src/shader_bundle.dart#'
          'kernelSectionVersion':
      'a section inside an F3SB bundle, versioned inside it as the material '
      'section is; a newer one is refused as stale, and a bundle is a build '
      'artifact the build remakes',
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
const Map<String, String> interfaceClassAllowed = <String, String>{};

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
/// the last two (`GpuUnavailable`, `RenderRefusal`) are `…Exception` now.
/// The entry goes when its type is renamed (the rule fails on an entry no
/// snapshot declares), and a new exception is named `…Exception` from the
/// start, so the list stays empty.
const Map<String, String> exceptionNamePending = <String, String>{};

// ------------------------------------------------- 1.0: closed sets

/// Public enums and sealed types that stay closed, by name, with the reason
/// no member can ever be added to them.
///
/// **Item 5 of what a 1.x minor cannot fix** (`tasks/1.0-stability.md`): a
/// value added to a public `enum`, or a subtype to a public `sealed` class,
/// breaks every exhaustive `switch` somebody wrote against it, so it can only
/// come in a major. Under strict semver that freezes the type for the life of
/// 1.x. A type earns a place here only when a new member would change what
/// the type means: a direction, a sign, the two answers of a yes or a no, a
/// fixed mathematical set, a specification's own frozen list with its own
/// version. Everything that names a kind, a tier, a reason, a phase, a mode,
/// a refusal, a placement, a backend, a format or a policy is open, and is in
/// [openedSets] instead. Each type here says the same in its own doc.
const Map<String, String> closedForGood = <String, String>{
  'AgsActivityProgress':
      'the five values of IMS Assignment and Grade Services 2.0: the '
      'specification carries its own version, and another value is another '
      'version of it',
  'AgsGradingProgress':
      'the five values of IMS Assignment and Grade Services 2.0: the '
      'specification carries its own version, and another value is another '
      'version of it',
  'CaptureState':
      'captured or released: a yes or a no, kept as two states for who '
      'released it',
  'CloudFetch':
      'a copy, none, or the store could not say: yes, no and unknown to '
      'whether there is a copy',
  'CloudPut':
      'kept, overtaken, or the store could not say: yes, no and unknown to '
      'whether a write won',
  'CompareFunction':
      'never, always and the six comparisons: every function from less, equal '
      'and greater to pass or fail',
  'FramebufferOrigin':
      'whether row zero is the top or the bottom: the sign of the y axis',
  'GltfAccessorType':
      "glTF 2.0's own accessor types: the specification is versioned, and a "
      'file naming another is not glTF 2.0',
  'GltfComponentType':
      "glTF 2.0's own component types: the specification is versioned, and a "
      'file naming another is not glTF 2.0',
  'GltfPrimitiveMode':
      "glTF 2.0's seven primitive modes, numbered by the format: the "
      'specification is versioned, and a file naming an eighth is not glTF '
      '2.0',
  'GridHeading':
      'the four ways out of a square cell, and standing still: a square has '
      'no fifth side to leave by',
  'LevelPatchResult':
      'patched or refused: the two answers to whether a patch applies, with '
      'the reason inside the refusal',
  'PadConnection':
      'connected or not: a yes or a no, kept as two states for which way it '
      'changed',
  'ProjectRead':
      'opened or refused: the two answers to whether a file could be read, '
      'with the reason inside the refusal',
  'RecoveryDecision':
      'open the saved file or offer the autosave: the two answers to whether '
      'the autosave is newer',
  'SaveRead':
      'found or not read: the two answers to whether a document holds a save, '
      'with the reason inside the refusal',
  'SaveUpgrade':
      'upgraded or refused: the two answers to whether a save can be carried '
      'forward, with the reason inside the refusal',
  'ScrubAnswer':
      'moved or refused: the two answers to whether a scrub landed, with the '
      'reason inside the refusal',
  'ServiceAnswer':
      'done or refused: the two answers a service gives, with the reason '
      'inside the refusal',
  'ShadowCasterFaces':
      "front, back or both: every non-empty set of a triangle's two faces",
  'StencilFace':
      "front, back or both: every non-empty set of a triangle's two faces",
  'StorageTextureAccess':
      'read, write, or both: every non-empty set of the two ways to touch a '
      'texel',
  'SyncDirection':
      "which of the two engines writes the other's transform: a bridge has "
      'two ends, and a write comes from one of them',
  'TapeBisection':
      'agree or diverge: the two answers to whether two tapes play alike, '
      'with where inside the divergence',
  'TextureChannel': 'r, g, b and a: the four channels of an RGBA colour',
  'WedgeUphill':
      'the four horizontal directions of the grid a wedge rises towards: a '
      'grid has no fifth',
  'WindingOrder':
      'clockwise or counter-clockwise: the two orientations a triangle has',
};

/// Public types that were an `enum` or a `sealed` class and were opened
/// before 1.0, by name, with the package and the shape they took.
///
/// **A record of a decision, and a guard on it.** Each was decided open: an
/// enum became a class with `static const` members and a private constructor
/// (the shape `DeviceFeature` has, keeping `values`, `name`, `byName` and the
/// enum's `toString`), a sealed result or command became an `abstract final`
/// hierarchy this package alone grows, and the texture graph's nodes an
/// `abstract base class` with a visitor. The rule fails on a name here that a
/// snapshot declares as an `enum` or `sealed` again, and on a name no
/// snapshot declares at all.
const Map<String, String> openedSets = <String, String>{
  'ActionKind': 'flutter3d_sim: a class with constants',
  'AnimationCondition': 'flutter3d_core: an abstract final hierarchy',
  'AnimationGoal': 'flutter3d_core: an abstract final hierarchy',
  'AnimationInterpolation': 'flutter3d_core: a class with constants',
  'AnimationPath': 'flutter3d_core: a class with constants',
  'AnimationPointerProperty': 'flutter3d_core: a class with constants',
  'AnimationPointerTarget': 'flutter3d_core: a class with constants',
  'AnimationWrap': 'flutter3d_core: a class with constants',
  'AuditCheck': 'flutter3d_model_core: a class with constants',
  'BehaviorStatus': 'flutter3d_sim: a class with constants',
  'BlendFactor': 'flutter3d_hardware: a class with constants',
  'BlendOperation': 'flutter3d_hardware: a class with constants',
  'CompositePart': 'flutter3d_game: a class with constants',
  'ConflictPolicy': 'flutter3d_game: a class with constants',
  'CsgOperation': 'flutter3d_mesh: a class with constants',
  'CullMode': 'flutter3d_hardware: a class with constants',
  'DebrisStatic': 'flutter3d_physics_native: an abstract final hierarchy',
  'DepthRange': 'flutter3d_hardware: a class with constants',
  'DiagnosticView': 'flutter3d_sim_mcp: a class with constants',
  'DocumentCommand': 'flutter3d_editor_core: an abstract final hierarchy',
  'EditorCommand': 'flutter3d_editor_core: an abstract final hierarchy',
  'ElementLevel': 'flutter3d_mesh: a class with constants',
  'ExportFormat': 'flutter3d_model_core: a class with constants',
  'ExportResult': 'flutter3d_model_core: an abstract final hierarchy',
  'FeatureStability': 'flutter3d_hardware: a class with constants',
  'FuzzTransform': 'flutter3d_conformance: an abstract final hierarchy',
  'Geometry': 'flutter3d_model_core: an abstract final hierarchy',
  'GeometryUsage': 'flutter3d_hardware: a class with constants',
  'IndexType': 'flutter3d_hardware: a class with constants',
  'InputAction': 'flutter3d_sim: an abstract final hierarchy',
  'LoadAction': 'flutter3d_hardware: a class with constants',
  'LtiLaunchException': 'flutter3d_education: an abstract final hierarchy',
  'LtiMessageType': 'flutter3d_education: a class with constants',
  'MapMode': 'flutter3d_hardware: a class with constants',
  'MaterialHintKind': 'flutter3d_core: an abstract final hierarchy',
  'MaterialMap': 'flutter3d_core: a class with constants',
  'MaterialStatement': 'flutter3d_core: an abstract base class with a visitor',
  'MeshAttribute': 'flutter3d_mesh: a class with constants',
  'MeshDomain': 'flutter3d_mesh: a class with constants',
  'MinMagFilter': 'flutter3d_hardware: a class with constants',
  'MipFilter': 'flutter3d_hardware: a class with constants',
  'ModelCameraProjection': 'flutter3d_core: an abstract final hierarchy',
  'ModelCommand': 'flutter3d_model_core: an abstract final hierarchy',
  'ModelWriteFormat': 'flutter3d_core: a class with constants',
  'Modifier': 'flutter3d_mesh: an abstract final hierarchy',
  'NumberUnit': 'flutter3d_editor_widgets: a class with constants',
  'ObjNormals': 'flutter3d_core: a class with constants',
  'OriginPlacement': 'flutter3d_model_core: a class with constants',
  'PadAxis': 'pad_input: a class with constants',
  'ParamHint': 'flutter3d_model_core: an abstract final hierarchy',
  'ParametricShape': 'flutter3d_mesh: an abstract final hierarchy',
  'Piece': 'flutter3d_editor_core: a class with constants',
  'PipelineStatistic': 'flutter3d_hardware: a class with constants',
  'PlaneAxis': 'flame_flutter3d: a class with constants',
  'PlayState': 'flutter3d_editor_play: an abstract final hierarchy',
  'PlaytestOutcome': 'flutter3d_sim_mcp: a class with constants',
  'PolygonMode': 'flutter3d_hardware: a class with constants',
  'PrimitiveType': 'flutter3d_hardware: a class with constants',
  'ProfileTarget': 'flutter3d_model_core: a class with constants',
  'RagdollJoint': 'flutter3d_physics_native: an abstract final hierarchy',
  'ReactiveShape': 'flutter3d_core: a class with constants',
  'ReadingPredicate': 'flutter3d_sim_mcp: an abstract final hierarchy',
  'RecipeCategory': 'flutter3d_mesh: a class with constants',
  'Resimulation': 'flutter3d_sim: an abstract final hierarchy',
  'ResizeFilter': 'flutter3d_model_core: a class with constants',
  'ResourceOrigin': 'flutter3d_core: a class with constants',
  'ResourceSize': 'flutter3d_core: an abstract base class with a visitor',
  'RunStatus': 'flutter3d_game: an abstract final hierarchy',
  'SamplerAddressMode': 'flutter3d_hardware: a class with constants',
  'SamplerBorderColor': 'flutter3d_hardware: a class with constants',
  'SaveResolution': 'flutter3d_sim: a class with constants',
  'SelectionMode': 'flutter3d_model_core: a class with constants',
  'ShadowCasting': 'flutter3d_sim: a class with constants',
  'SplatColorSpace': 'flutter3d_core: a class with constants',
  'SplatComposite': 'flutter3d_core: a class with constants',
  'StencilOperation': 'flutter3d_hardware: a class with constants',
  'StepAuthor': 'flutter3d_model_core: a class with constants',
  'StlNormals': 'flutter3d_core: a class with constants',
  'StorageMode': 'flutter3d_hardware: a class with constants',
  'StoreAction': 'flutter3d_hardware: a class with constants',
  'StrategyOrder': 'flutter3d_game_strategy: an abstract final hierarchy',
  'SurfaceAlphaMode': 'flutter3d_core: a class with constants',
  'TemporalClip': 'flutter3d_core: a class with constants',
  'TextureBlendMode': 'flutter3d_model_core: a class with constants',
  'TextureDimension': 'flutter3d_hardware: a class with constants',
  'TextureEncoding': 'flutter3d_model_core: a class with constants',
  'TextureFileFormat': 'flutter3d_model_core: a class with constants',
  'TextureNode': 'flutter3d_model_core: an abstract base class with a visitor',
  'TextureSampleKind': 'flutter3d_hardware: a class with constants',
  'TextureType': 'flutter3d_hardware: a class with constants',
  'TextureValueType': 'flutter3d_model_core: a class with constants',
  'TextureWrap': 'flutter3d_core: a class with constants',
  'TransformPivot': 'flutter3d_model_core: a class with constants',
  'TransformSpace': 'flutter3d_model_core: a class with constants',
  'UpAxis': 'flutter3d_model_core: a class with constants',
  'VertexStepMode': 'flutter3d_hardware: a class with constants',
};

/// Sealed types whose conversion belongs to a later step, by name, with who
/// converts them.
///
/// **A to-do list, not an exemption**, like [interfaceClassPending]: the rule
/// passes these while they are sealed and fails on an entry once its type is
/// not, so the list only shrinks. A new closed set is not added here.
const Map<String, String> closedSetPending = <String, String>{};

/// Hooks whose methods take more than one parameter, each with why
/// (amendment 2 of the field review). Keyed `Class.member`, or `Class` for
/// every member of a class.
///
/// **A list of reasons, not a list of debts.** A hook's method takes one
/// context object that can gain members; an entry here is a class whose
/// methods are a fixed shape no minor will grow, or that nobody outside the
/// engine implements. [hookParametersPending] holds the debts.
const Map<String, String> hookParametersAllowed = <String, String>{
  'ActionBinding.withSource':
      'flutter3d_game: a binding copied with another source and part, a value\'s own copyWith',
  'AnimationPointerSink':
      'flutter3d_core: a pointer track\'s path and its sampled values, set per channel per frame, for AnimationTarget\'s reason',
  'AnimationTarget':
      'flutter3d_core: a node\'s transform as a player drives it, set per channel per frame as a vector\'s three components so a sampled frame allocates nothing',
  'BackendOpener':
      'flutter3d_hardware: opening a backend at a surface\'s size, the one shape every backend\'s `open` has; the hardware interface, for GraphicsDevice\'s reason',
  'BinaryStorage': 'flutter3d_app: a key and its bytes, for Storage\'s reason',
  'BridgeSpace':
      'flame_flutter3d: a Flame point to a scene position (and an angle to a rotation), written into the caller\'s vector per component per frame: a coordinate transform whose inputs are the coordinates',
  'CollisionShape':
      'flutter3d_physics: the geometric queries a narrow phase asks per pair per step (a support point along a direction at a pose, an overlap of two posed shapes, a ray against one), whose inputs are the mathematics of the query; a context per call would be an allocation per pair in the hottest loop the physics has, and a new query arrives as a new member with a default body',
  'ComponentRegistry':
      'flutter3d_plugin_api: a registry the engine implements and a plugin calls, for LoopRegistry\'s reason',
  'ComputeEncoder':
      'flutter3d_hardware: the hardware interface, for GraphicsDevice\'s reason',
  'CpuComputeShader':
      'flutter3d_cpu: the per-workgroup call, for CpuVertexShader\'s reason',
  'CpuFragmentShader':
      'flutter3d_cpu: the per-fragment call, for CpuVertexShader\'s reason',
  'CpuMaterialCompiler':
      'flutter3d_cpu: a test seam with the shape of the compiler it stands in for (stage, source)',
  'CpuVertexShader':
      'flutter3d_cpu: the software rasteriser\'s per-vertex call, where a context object made per call would be an allocation in the hottest loop the backend has',
  'CpuVertexShaderByIndex':
      'flutter3d_cpu: the per-vertex call, for CpuVertexShader\'s reason',
  'CustomShape':
      'flutter3d_physics: CollisionShape\'s queries derived from one support function, for CollisionShape\'s reason',
  'DeviceFactory':
      'flutter3d_conformance: a device at a size, BackendOpener\'s shape',
  'ElementBodyEvent.codecOf':
      'flutter3d_elements: a codec for the package\'s own body events, made from each event\'s constructor `(body, made)`; nobody outside makes one',
  'ElementFields':
      'flutter3d_elements: the world\'s fields as the core that steps them implements them and an element calls them; it grows by members with defaults, and its calls by named parameters a caller may leave out',
  'EncodedImageUpload':
      'flutter3d_hardware: a capability of the hardware interface, for GraphicsDevice\'s reason',
  'EntityKind.place':
      'flutter3d_sim: a helper a kind calls from its spawn to place its collider, not a hook it overrides; it grows by named parameters a caller may leave out',
  'EntityKind.requireKeyExists':
      'flutter3d_sim: a check a kind calls from its validate, not a hook it overrides, for EntityKind.place\'s reason',
  'EntityKind.requireSize':
      'flutter3d_sim: a check a kind calls from its validate, not a hook it overrides, for EntityKind.place\'s reason',
  'EntityKind.requireTarget':
      'flutter3d_sim: a check a kind calls from its validate, not a hook it overrides, for EntityKind.place\'s reason',
  'EntityKind.requireText':
      'flutter3d_sim: a check a kind calls from its validate, not a hook it overrides, for EntityKind.place\'s reason',
  'EntityKind.requireTravel':
      'flutter3d_sim: a check a kind calls from its validate, not a hook it overrides, for EntityKind.place\'s reason',
  'EventRegistry':
      'flutter3d_plugin_api: a registry the engine implements and a plugin calls, for LoopRegistry\'s reason',
  'FormatDocument':
      'flutter3d_foundation: `write` is the helper a document calls to put its body in the envelope, not a hook it overrides',
  'FrameContext':
      'flutter3d_core: a context the engine makes and hands to every node and contributor; nobody outside implements it',
  'FramePresenter':
      'flutter3d_app: the backend packages register presenters of this shape through `DeviceRegistry.addPresenter` as closures, and cannot import a context from this package, which depends on them; the shape is shared structurally or not at all',
  'GameAsk':
      'flutter3d_mcp: a test seam with the shape of `callGameExtension` it stands in for',
  'GraphicsDevice':
      'flutter3d_hardware: the hardware interface mirrors the call shapes of the GPU APIs it wraps, and grows by a member with a default body (D25), never by a parameter',
  'GroundField':
      'flutter3d_game_racing: what is under a wheel, asked per wheel per step with a position and a hint and written into the caller\'s GroundSample, which is where the answer grows',
  'GroundHeight':
      'flutter3d_game_kit: a height field over the ground, a function of x and z',
  'HasFlutter3d.open3d':
      'flame_flutter3d: a method the mixin gives a game to call, not one it overrides; it grows by named parameters a caller may leave out',
  'JetObstacle':
      'flutter3d_physics: whether a drop of a stream, at a point and of a radius, reaches or touches a wall: a geometric query per drop per step, for CollisionShape\'s reason',
  'JetReceiver.catches':
      'flutter3d_physics: whether a drop, at a point and of a radius, lands in a vessel, for JetObstacle\'s reason',
  'JsonPost':
      'flutter3d_sim: an HTTP POST of a JSON body to a URL, the shape of the client call it wraps',
  'KernelImage':
      'flutter3d_shaders: the kernel language\'s store(i, x, y, v), one call per texel, mirroring the shader builtin it runs in place of',
  'KernelTexture':
      'flutter3d_shaders: the kernel language\'s load(t, x, y), one call per texel, mirroring the shader builtin it runs in place of',
  'LevelKit':
      'flutter3d_sim: a kit of the engine\'s own table of level recipes (room, corridor, scatter), `(sketch, recipe)`; a recipe names one of those kits and nobody outside adds one',
  'LightBehavior':
      'flutter3d_sim: a light\'s brightness as a function of time and a seed, a curve with nothing else to be handed',
  'LoopRegistry':
      'flutter3d_plugin_api: a registry the engine implements and a plugin calls; it grows by a member with a default, and its calls by named parameters a caller may leave out',
  'MaskRead':
      'flutter3d_model_core: a mask\'s value at a texel, a function of x and y',
  'NewRun':
      'flutter3d_mcp: a test seam with the shape of `FlutterRun`\'s constructor (project root, device) it stands in for',
  'ParameterType':
      'flutter3d_core: one value laid out as the floats a uniform block reads, per parameter per draw: a layout kernel whose inputs are the value and the floats it writes',
  'ParticleEmitter.randomDirection':
      'flutter3d_particles: a uniform unit vector written into the caller\'s vector, a maths helper an emitter calls per particle, not a hook it overrides',
  'PassEncoder':
      'flutter3d_hardware: the hardware interface, for GraphicsDevice\'s reason',
  'PluginProcessRunner':
      'flutter3d_build: `Process.run`\'s shape (executable, arguments, working directory), for ProcessProbe\'s reason',
  'ProcessProbe':
      'flutter3d_build: `Process.run`\'s shape (executable, arguments), mirrored so a test hands a canned answer',
  'Projection':
      'flutter3d_core: a camera\'s projection maths, an eye-space point to normalized device coordinates at an aspect, whose inputs the maths fixes',
  'RunFlutterIn':
      'flutter3d_mcp: `Process.run`\'s shape (arguments, working directory), for ProcessProbe\'s reason',
  'RunSession.load':
      'flutter3d_game: the session\'s driver, which a game calls and nobody overrides; it grows by named parameters a caller may leave out',
  'SimCommands':
      'flutter3d_plugin_api: the simulation\'s own command buffer, which the engine implements and a system calls',
  'SimWorld':
      'flutter3d_plugin_api: the simulation\'s world, which the engine implements and a system calls',
  'SimulationHandle':
      'flutter3d_sim: what the engine hands the view, implemented by the engine in this isolate or another, for LoopRegistry\'s reason',
  'SimulationQueryRegistry':
      'flutter3d_sim: a registry the engine implements and a plugin calls, for LoopRegistry\'s reason',
  'SixWayField':
      'flutter3d_particles: a density field over the cube and the animation\'s time, a function of x, y, z and t',
  'SizedImageDecoder':
      'flutter3d_core: an `ImageDecoder` with one optional cap, so the same function serves wherever an `ImageDecoder` is asked for (`uploadEncodedImage` tests `is SizedImageDecoder`); the decoding seam that grows is `TextureCodec.decode`, which takes one context',
  'SpatialRenderer':
      'flutter3d_audio_core: the query it reads and the result it writes are both objects that grow by fields, reused per voice per frame, so the call already takes its context and its answer',
  'SplatRangeReader':
      'flutter3d_core: a byte range of a file, an offset and a length, the shape of the range read it wraps (`RandomAccessFile`, an HTTP range request)',
  'StartFlutter':
      'flutter3d_editor_play: `Process.start`\'s shape (arguments, working directory), for ProcessProbe\'s reason',
  'Storage':
      'flutter3d_app: a key and its document, the shape of every store it wraps (localStorage, a file, shared preferences); a store grows by members with defaults, never by a parameter',
  'SynchronousBufferReadback':
      'flutter3d_hardware: a capability of the hardware interface, for GraphicsDevice\'s reason',
  'TileDevice':
      'flutter3d_model_core: a device for one tile at its size, BackendOpener\'s shape, a top-level function so it crosses an isolate',
  'ToolEventPoster':
      'flutter3d_game: `dart:developer`\'s `postEvent(kind, data)`, mirrored so a test hears what a tool would',
  'TransferEncoder':
      'flutter3d_hardware: the hardware interface, for GraphicsDevice\'s reason',
  'UnitPace':
      'flutter3d_game_strategy: a unit\'s pace along a ground direction, asked per unit per step, a function of the unit and the direction\'s two components',
  'VesselShape':
      'flutter3d_physics: the volume of a vessel below a plane, a function of the plane fixed by the geometry, asked per vessel per step',
  'VmExtensionHandler':
      'flutter3d_plugin_api: `dart:developer`\'s `ServiceExtensionHandler`, (method, parameters), mirrored so a handler registers unchanged',
  'WasmImports':
      'flutter3d_plugin_runtime: the module\'s imports as the ABI declares them (`field_get(field, index)`), mirrored one to one; an import arrives with an ABI version as a member with a default body, never as a parameter',
  'WgslStageCompiler':
      'flutter3d_build_hooks: a test seam with the shape of `compileStage` it stands in for',
  // Callbacks a `final class` holds, read since the rule reads them: each a
  // function of its inputs, Flutter's builder shape, or a test seam.
  'AudioScene.occlusion':
      'flutter3d_audio_core: how much of a sound is blocked between two points, a function of the points',
  'ElementHeightfield.heightAt':
      'flutter3d_elements: the ground\'s height at x and z, a function of them, as GroundHeight',
  'FakeBackend.answerReadback':
      'flutter3d_hardware: a test seam with the shape of the readback it answers (texture, region)',
  'FakeXrSession.frameAt':
      'flutter3d_app: a test seam, the frame a fake session answers at an index',
  'GridMover.passable':
      'flame_flutter3d: whether a cell can be entered, a function of its column and row',
  'MaterialSurfaceValues.sample':
      'flutter3d_core: a texture slot sampled at u and v, the shape of the shader builtin it runs in place of, as KernelTexture',
  'Model3dComponent.openSharedDevice':
      'flame_flutter3d: a test seam with BackendOpener\'s shape (width, height)',
  'OverheadFraming.groundHeight':
      'flutter3d_camera: the ground\'s height at x and z, as GroundHeight',
  'PendulumLabRun.lengthAt':
      'flutter3d_education: the pendulum\'s length at a step from the length before, a function of the two',
  'PlaySession.push':
      'flutter3d_mcp: a test seam with the shape of the VM service call it stands in for (service, level)',
  'ProbeBuilder.builder':
      'flutter3d_app: Flutter\'s builder shape, `(BuildContext, T)`, which every Flutter developer writes',
  'SpatialQuery.occlusion':
      'flutter3d_audio_core: as AudioScene.occlusion, read per voice per frame',
  'StereoHudPanel.builder':
      'flutter3d_game_ui: Flutter\'s builder shape, as ProbeBuilder.builder',
  'UniversalTarget.encodeBlock':
      'flutter3d_core: a test seam with the shape of the block encoder it stands in for (blocks, index)',
  'ViewCamera.view':
      'flame_flutter3d: whether an eye sees a target, a line-of-sight test of the two points',
  'ViewFraming.view': 'flame_flutter3d: as ViewCamera.view',
};

/// Hooks whose methods still take a list of parameters, by class, with the
/// package whose owner converts each to one context object.
///
/// **A to-do list, not an exemption**, like [closedSetPending]: the rule
/// passes these while they take more than one parameter and fails on an
/// entry once no method of its class does, so the list only shrinks. A new
/// hook is not added here; it takes one context from the start.
///
/// **The callbacks a `final class` holds** joined the rule late: its first
/// version read only types an outside author extends, so a field or a
/// constructor parameter of a function type of two values (`Model3D.onTap`,
/// `Flutter3dView.onFrame`) passed unread. Those that are events an outside
/// author hears, and so grow, are listed here with the package whose owner
/// gives each one event object; the ones that are a function of their
/// inputs have their reason in [hookParametersAllowed].
const Map<String, String> hookParametersPending = <String, String>{
  'Actor': 'flutter3d_sim: `onDamage(amount, from)`, one damage event',
  'ActorAnimations':
      'flutter3d_game: `write(actor, graph, wish)`, one animation-write context',
  'ChunkStreamer': 'flame_flutter3d: `drop(index, chunk)`, one chunk event',
  'DeviceSettings':
      'flutter3d_app: `onDeviceLost(engine, loss)`, one device-loss event',
  'EngineRollback':
      'flutter3d_net: `onSettled` and `onMessage`, as RollbackSession\'s',
  'Flutter3dView':
      'flutter3d_app: `onBeforeFrame` and `onFrame(engine, frame)`, one frame event',
  'GridMover': 'flame_flutter3d: `onArrive(column, row)`, one arrival event',
  'LiveLevel':
      'flutter3d_game: `present(next, diff)` and `swapped(next, step)`, one swap event each',
  'LocalSimulation':
      'flutter3d_sim: `applyInput(seat, input)`, one seat-input context, with SimulationSetup',
  'Model3D': 'flutter3d_app: `onTap(part, hit)`, one tap event',
  'ModelWardrobe': 'flutter3d: `onDressed(instance, key)`, one dressing event',
  'PlatformerHeadlessGame':
      'flutter3d_game_platformer: `dress(level, staged)`, one staging context',
  'RollbackSession':
      'flutter3d_net: `onSettled(step, after, frames)` and `onMessage(from, message)`, one event each',
  'SimulationObserver':
      'flutter3d_net: `restore(start, step)`, one restore context',
  'SimulationPlacement':
      'flutter3d_app: `applyInput(seat, input)`, as LocalSimulation\'s',
  'SimulationSetup':
      'flutter3d_sim: `applyInput(seat, input)`, as LocalSimulation\'s',
  'TiledWorld3d': 'flame_flutter3d: `spawn(object, at)`, one spawn context',
  'XrDriver':
      'flutter3d_app: `drawPanel(widget, width, height)`, one panel request',
};

// The reasons a hook may be handed one value, shared by the entries below.
const String _stepLength =
    'the step\'s or the frame\'s length in seconds, the one input of an '
    'integrator or a clock; what else a step knows arrives as a member of '
    'the type that is handed it';
const String _ownState =
    'its own saved state handed back, what its own capture wrote; a later '
    'shape is told apart by the version saved beside it, never by a second '
    'parameter';
const String _codec =
    'the value a codec writes or the document it reads, the one input of a '
    'conversion; what a later minor hands it (a target version, an entity '
    'remap) arrives as a member with a default body that calls this one, '
    'or as a named parameter of the factory';
const String _ofItsInput =
    'a function of one number, vector or name with nothing else to be '
    'handed: a curve, a test, a lookup';
const String _engineImplements =
    'a registry, a context or a sink the engine implements and a plugin '
    'calls by a name or a value; nobody outside implements it';
const String _valueChanged =
    'Flutter\'s `ValueChanged` shape: the new value of a control, a progress '
    'or a flag, heard by the widget that owns it';
const String _ioSeam =
    'a file, a URL or a process stood in for by a test, in the shape of the '
    'call it wraps';
const String _serverEmbedding =
    'how a host embeds the server: what the server calls back with its own '
    'answer, refusal or client name, not a hook a tool implements';

/// Hooks, callbacks and typedefs handed one value that cannot gain members
/// — a number, a string, a `Map`, a list, bytes, a vector, a type
/// parameter — each with why it needs no context. Keyed as
/// [hookParametersAllowed] is.
///
/// **Reviewed one by one, not a default.** A hook handed one value grows
/// only by a second parameter, which breaks it; so the shape that cannot
/// grow is the exception, and each entry says why that is right here. The
/// one-parameter hooks that take a type of the engine's own (`LoopContext`,
/// `Activation`, `Mind`) are not listed: those types grow.
///
/// **Decided at rc.1, by the second plugin audit:** `ComponentCodec.encode`
/// and `EventCodec.encode` stay handed the value, and `SnapshotPart.capture`
/// and `digest` (handed nothing, which the rule does not read) stay as they
/// are: a minor that needs to say what a capture is for adds a member with a
/// default body that calls the old one, which breaks nobody. `PluginSource.read`
/// stays the path it reads. `ProjectToolRun` and `OfferedTool.run` were
/// given a `ToolCall`.
const Map<String, String> hookValueParameters = <String, String>{
  'Announce': 'flutter3d_game_ui: a sentence to say aloud, $_valueChanged',
  'AssetSourceFactory':
      'flutter3d_core: a source made from the rest of a URI after its scheme, $_ioSeam',
  'AssimilationContext': 'flutter3d_plugin_api: $_engineImplements',
  'Attenuation':
      'flutter3d_audio_core: gain as a function of distance, $_ofItsInput',
  'AudioBackend.preload':
      'flutter3d_audio_core: a sound loaded by its path, $_ioSeam',
  'AuthorityServer': 'flame_multiplayer: $_codec',
  'BakeParticleSystemJobRequest.advancePerFrame':
      'flutter3d_model_core: $_stepLength',
  'BatonStream':
      'flame_multiplayer: one decoded wire message, whose shape is the wire\'s, versioned by the protocol',
  'BestRun': 'flutter3d_game_kit: $_codec',
  'Binding3D.materials':
      'flutter3d_app: a material looked up by its id, $_ofItsInput',
  'BlendCurve': 'flutter3d_camera: a blend\'s weight at a time, $_ofItsInput',
  'Breaches.onHole':
      'flutter3d_sim: the box of the hole a breach opened, a test of its geometry, $_ofItsInput',
  'BridgeClock.onTick': 'flame_flutter3d: $_stepLength',
  'BusEffect': 'flutter3d_audio_core: an effect at a mix weight, $_ofItsInput',
  'CharacterBodyComponent.drive': 'flame_flutter3d: $_stepLength',
  'ChunkStreamer.build':
      'flame_flutter3d: a chunk made for its index, $_ofItsInput',
  'ClothSystem': 'flutter3d_physics_native: $_engineImplements',
  'CloudSaveStore.fetch': 'flutter3d_game: a save fetched by its key, $_ioSeam',
  'ColorSwatchField.onWrite': 'flutter3d_editor_widgets: $_valueChanged',
  'CommandReader': 'flutter3d_editor_core: $_codec',
  'ComponentCodec': 'flutter3d_plugin_api: $_codec',
  'ConnectVmService':
      'flutter3d_editor_play: a VM service at its URI, $_ioSeam',
  'DataPluginLoader': 'flutter3d_plugin_runtime: $_ioSeam',
  'DataSection':
      'flutter3d_plugin_api: a section\'s own body, written back or asked for its resources; $_codec',
  'DebrisSystem': 'flutter3d_physics_native: $_engineImplements',
  'DepthRules':
      'flutter3d_game_kit: a rule for a depth of the dungeon, $_ofItsInput',
  'DeterminismCheck.restore': 'flutter3d_sim: $_ownState',
  'DeviceClassMemory.write':
      'flutter3d_core: a device class remembered by its name, $_ioSeam',
  'EduDataSource.sample': 'flutter3d_sim: a sample by its index, $_ofItsInput',
  'EffectAffectorReader': 'flutter3d_particles: $_codec',
  'EffectEmitterReader': 'flutter3d_particles: $_codec',
  'ElementHook.restore': 'flutter3d_elements: $_ownState',
  'EngineLoop.drainLook':
      'flutter3d_sim: the look delta a frame gathered, written into the caller\'s vector, $_ofItsInput',
  'EngineRollback.applyFrames':
      'flutter3d_net: one step\'s inputs by seat, the shape the wire carries, versioned by the protocol',
  'EnumField.unknownLabel':
      'flutter3d_editor_widgets: a label for a name, $_ofItsInput',
  'EnvironmentBuild': 'flutter3d_app: an asset built from its bytes, $_codec',
  'EventCodec': 'flutter3d_plugin_api: $_codec',
  'EventDigestSink': 'flutter3d_plugin_api: $_engineImplements',
  'ExpressionBuiltin':
      'flutter3d_foundation: a builtin\'s value of its arguments, $_ofItsInput',
  'FieldRegistry': 'flutter3d_fields: $_engineImplements',
  'FieldRow': 'flutter3d_editor_widgets: $_valueChanged',
  'FixedStepUpdate': 'flame_flutter3d: $_stepLength',
  'Flutter3dFlameWidget.onTick': 'flame_flutter3d: $_stepLength',
  'Flutter3dView.onPausedChanged': 'flutter3d_app: $_valueChanged',
  'Flutter3dView.restoreState': 'flutter3d_app: $_ownState',
  'FluidSystem': 'flutter3d_physics_native: $_engineImplements',
  'FormatMigration': 'flutter3d_foundation: $_codec',
  'FormatRefusal':
      'flutter3d_foundation: a format\'s own exception made from its sentence, $_codec',
  'GeneratorSource': 'flutter3d_editor_core: $_ioSeam',
  'GenrePlugin':
      'flutter3d_sim: the genre\'s own simulation captured, digested or published, $_ownState',
  'HasFixedStep': 'flame_flutter3d: $_stepLength',
  'HeadlessRun':
      'flutter3d_sim: a run stepped by a length or aimed at a point, the driver a test calls; $_stepLength',
  'HintTextBox.onWrite': 'flutter3d_editor_widgets: $_valueChanged',
  'ImageDecoder': 'flutter3d_core: $_codec',
  'ImpulseRule': 'flutter3d_camera: a shake for an event, $_ofItsInput',
  'InPlaceCodec': 'flutter3d_plugin_api: $_codec',
  'InstancedPoseComponent.place':
      'flame_flutter3d: a pose at a point, $_ofItsInput',
  'KeyEase': 'flutter3d_particles: an easing curve, $_ofItsInput',
  'Launchable.launch':
      'flutter3d_game_platformer: a launch at a speed, $_ofItsInput',
  'LoadedShaderLibrary.refresh':
      'flutter3d_hardware: a shader bundle reloaded from its bytes, the hardware interface; $_codec',
  'LoopChange.at':
      'flutter3d_sim: the same change at another step, a value\'s own copy',
  'LoopSettings.drainLook':
      'flutter3d_app: the look delta a frame gathered, as EngineLoop.drainLook',
  'MaterialUpdate.apply':
      'flutter3d_core: a material\'s parameters by name, the shape its document writes; $_codec',
  'Mechanism':
      'flutter3d_sim: stepped by a length and restored from its own state; $_stepLength',
  'ModelBuild': 'flutter3d_app: an asset built from its bytes, $_codec',
  'ModelDocument':
      'flutter3d_core: a mask looked up by name or index, $_ofItsInput',
  'ModelMcpServer.onInitialize': 'flutter3d_mcp: $_serverEmbedding',
  'ModelProjectView.holds':
      'flutter3d_model_core: a test of an object id, $_ofItsInput',
  'ModelVisuals.source': 'flutter3d_app: a source for a path, $_ioSeam',
  'MomentHint.when': 'flutter3d_game_ui: a test of an event, $_ofItsInput',
  'MorphSink':
      'flutter3d_core: a frame\'s morph weights, set per frame, for AnimationTarget\'s reason',
  'Mover': 'flutter3d_sim: for Mechanism\'s reason',
  'NativeForceField.restoreState': 'flutter3d_physics_native: $_ownState',
  'NativeParticleCloud.emit': 'flutter3d_physics_native: $_engineImplements',
  'NumbersRow.onWrite': 'flutter3d_editor_widgets: $_valueChanged',
  'OcclusionTest':
      'flutter3d_core: whether a box may be seen, per box per frame, $_ofItsInput',
  'PagedSplatOctree.onPage':
      'flutter3d_core: a page index loaded, $_valueChanged',
  'PartyTape': 'flame_multiplayer: $_codec',
  'PartyTapeWatcher': 'flame_multiplayer: $_codec',
  'PathOffers':
      'flutter3d_editor_widgets: the paths a field offers, $_ofItsInput',
  'PeerWire.listen':
      'flutter3d_net: one decoded wire message, as BatonStream\'s; `listenFrom` hands a PeerMessage that grows',
  'PhotoSaving.add': 'flutter3d_app: a photo\'s bytes, $_ioSeam',
  'PhotoShelf.open': 'flutter3d_app: a shelf at a path, $_ioSeam',
  'PlatformerHeadlessGame.dress': 'flutter3d_game_platformer: $_stepLength',
  'PlatformerSnapshotPart': 'flutter3d_game_platformer: $_ownState',
  'PlaySession.projectRootOf': 'flutter3d_mcp: a test seam, $_ioSeam',
  'PluginChange.at': 'flutter3d_plugin_api: for LoopChange.at\'s reason',
  'PluginHarness.registries':
      'flutter3d_conformance: the registries for a backend by its name, $_ofItsInput',
  'PluginSource.read':
      'flutter3d_plugin_runtime: a plugin\'s file by its path, $_ioSeam',
  'PngStripWriter.sink': 'flutter3d_cpu: the bytes of a strip, $_ioSeam',
  'PredictingClient': 'flame_multiplayer: $_codec',
  'PropertyGroup.writeGroup': 'flutter3d_matter: $_codec',
  'ResourceCache':
      'flutter3d_core: a cache\'s key and value types, its load, size and dispose a function of one; $_ofItsInput',
  'RigidDynamics':
      'flutter3d_physics: stepped by a length and restored from its own state; $_stepLength',
  'RollbackSession':
      'flutter3d_net: a step\'s inputs by seat and its own state handed back; $_ownState',
  'RunFlutter': 'flutter3d_editor_play: `flutter run`\'s arguments, $_ioSeam',
  'RunSession':
      'flutter3d_game: a session over a level type it is generic in, each member a function of the level or its name; $_ofItsInput',
  'RuntimeShaders': 'flutter3d_core: shaders from bytes or by name, $_codec',
  'SaveMigration': 'flutter3d_sim: $_codec',
  'SceneBindingRegistry': 'flutter3d_plugin_api: $_engineImplements',
  'SettingsSlot': 'flutter3d_core: $_codec',
  'ShareStrip.onOpen': 'flutter3d_game_ui: a link opened, $_valueChanged',
  'Signal': 'flutter3d_sim: $_ownState',
  'SimQuery': 'flutter3d_plugin_api: $_engineImplements',
  'SimulationFactory':
      'flutter3d_sim: a simulation made from its configuration document, $_codec',
  'SimulationObserver.readings':
      'flutter3d_net: one step\'s readings, $_valueChanged',
  'SnapshotRegistry': 'flutter3d_plugin_api: $_engineImplements',
  'Spoken': 'flutter3d_game_ui: a sentence for an event, $_ofItsInput',
  'StrategySimulation': 'flutter3d_game_strategy: $_stepLength',
  'SubsystemContext': 'flutter3d_fields: $_engineImplements',
  'Takeable':
      'flutter3d_sim: stepped by a length, offered to a taker and restored from its own state; for Mechanism\'s reason',
  'Tap3dCallbacks':
      'flame_flutter3d: Flame\'s tap callbacks hand the point in the canvas; `hitAt3d` takes the Tap3dProbe that grows',
  'TextureBuild': 'flutter3d_app: an asset built from its bytes, $_codec',
  'TextureCodec.sniff':
      'flutter3d_core: whether bytes are this codec\'s, $_codec',
  'TextureDecodeContext': 'flutter3d_core: $_engineImplements',
  'TexturePathField.onWrite': 'flutter3d_editor_widgets: $_valueChanged',
  'ToolTableServer': 'flutter3d_mcp: $_serverEmbedding',
  'UpdatesAtRoot': 'flame_flutter3d: $_stepLength',
  'VehicleController.restore': 'flutter3d_game_racing: $_ownState',
  'ViewSettings':
      'flutter3d_app: a warm-up\'s progress and a failure heard by the view, $_valueChanged',
  'WasmInstance.restore':
      'flutter3d_plugin_runtime: a module\'s memory and globals as its own capture wrote them; $_ownState',
  'XrSession.restoreAnchor':
      'flutter3d_app: an anchor restored by its id, $_ofItsInput',
  'RenderBundleEncoder.finish':
      'flutter3d_hardware: a bundle finished under a label, the hardware interface, for GraphicsDevice\'s reason',
  'Brain.restore': 'flutter3d_sim: $_ownState',
  'ActorCorpses.step': 'flutter3d_game: $_stepLength',
  'ReplaySubject.frame': 'flutter3d_testing: the frame at a step, $_ofItsInput',
};

// ------------------------------------------------------------ 1.0: naming

/// Names the naming rules of item 28 let stand, each with the reason. Keyed
/// by the subject a finding names (`Type.member`, or a bare name).
const Map<String, String> britishSpellingAllowed = <String, String>{};

/// Public types named as a library in `tool/structure/sdk_names.txt` names
/// one, with why each stays (A.8 of the API review).
///
/// **Only names a first game does not meet.** A name `package:flutter/
/// material.dart` or `dart:core` exports is never listed: a program that
/// imports a facade and material would read it as ambiguous, which is the
/// failure the rule exists for. What is here collides with `dart:ui` or
/// `dart:io`, which a game imports only to reach the engine underneath
/// Flutter or the file system, and there a `prefix` is the usual way in.
const Map<String, String> nameCollisionAllowed = <String, String>{
  'Scene':
      'the engine\'s scene graph, its first type; `dart:ui`\'s is a '
      'compositor layer tree that a widget never names',
  'FrameInfo':
      'what a view hands each frame\'s handler; `dart:ui`\'s is a decoded '
      'image codec\'s frame, reached only through `instantiateImageCodec`',
  'ResourceHandle':
      'a borrowed reference to a cached resource; `dart:io`\'s is a socket '
      'or file handle passed between processes',
  'Link':
      'the texture graph command that wires one node into another; '
      '`dart:io`\'s is a symbolic link, in code that already prefixes '
      '`dart:io` beside Flutter',
  'Pipe':
      'a pipe a liquid flows along between two vessels; `dart:io`\'s is an '
      'anonymous pipe between processes',
};

/// Readers that answer null for "not there", as `Type.member` or
/// `function`, each with what absent means (E.7).
///
/// **Absent, skipped, or a word that is not one.** A field a file need not
/// have, a part a newer build wrote that this one skips rather than refuse
/// the whole document over, or text a person typed that `double.tryParse`
/// would answer null for too.
const Map<String, String> nullAsErrorAllowed = <String, String>{
  'parseChunkThreshold':
      'a command-line word that is not a count; the command throws its '
      'usage exception',
  'parseDeviceClasses':
      'a command-line word that names no class; the command falls back to '
      'every class',
  'AnimationPath.fromGltf':
      'a glTF channel path this build does not animate, which a model skips',
  'readSurface':
      'a software shader stage, not a reader: null discards the '
      'fragment',
  'uploadCoatMap': 'absent: a material with no coat maps binds white',
  'uploadSheenMap': 'absent: a material with no sheen maps binds white',
  'EditorCommand.fromJson':
      'an agent\'s command whose arguments do not read is refused whole, as '
      'a value the server answers with',
  'SetLights.fromArguments':
      'an agent\'s command whose arguments do not read is refused whole',
  'ExperimentEdit.fromJson':
      'an agent\'s edit whose arguments do not read is refused whole',
  'ColorField.parseHex': 'text a person typed that is not six hex digits',
  'NumberField.parse': 'text a person typed that is not a finite number',
  'CheckQuestion.fromStepProperties':
      'the lenient reading of a hand-authored step: no question is a step '
      'without one; `fromJson` is the strict reader',
  'HarvestJob.fromSnapshot':
      'a save must load: a worker whose seam is gone comes back idle',
  'ActionBinding.fromJson':
      'a binding shape a newer build wrote, kept by the map rather than read',
  'ModifierSlot.fromJson':
      'a modifier kind a newer build wrote, skipped rather than the project '
      'refused',
  'ProjectSelection.fromJson':
      'a stale selection is skipped, not a reason to lose the document',
  'decodeSectionJson':
      'answers the JSON value, which may be null; it throws for bytes that '
      'are not JSON',
  'EngineBundleStamp.decode':
      'absent: a bundle written by a build that does not stamp has none',
  'PublishedActor.read': 'absent: an actor that published no body',
  'ShadowCasting.fromWireName':
      'a word that names no mode, as `byName` answers',
};

/// Members of implementable types that name a record, as `Type.member`,
/// each with why the record never grows.
///
/// **Maths pairs and triples only.** A coordinate has as many components as
/// its space, and a minor never adds a fourth axis to a 3D dispatch.
const Map<String, String> recordInContractAllowed = <String, String>{
  'CpuComputeShader.runWorkgroup':
      'a workgroup\'s x, y and z: a dispatch has three dimensions',
  'CpuComputeShader.workgroupSize':
      'a workgroup\'s x, y and z sizes: a dispatch has three dimensions',
  'FrameContext.jitter':
      'a subpixel offset, x and y: the image plane has two axes',
  'ResourceSize.resolve': 'a width and a height: a 2D resource\'s size',
  'VesselShape.span': 'an interval\'s two ends along one axis',
};

/// Constructors that keep optional positional parameters, as `Type.Type`
/// or `Type.named`, each with why it never grows (E.5).
///
/// **A value that is its numbers, or a registry seeded with its first
/// entries.** A colour's alpha after its three channels is `Color`'s own
/// shape and no fifth channel comes; a registry grows by `add` or
/// `register`, never by its constructor; a wrapper of one number has no
/// second one to take.
const Map<String, String> optionalPositionalAllowed = <String, String>{
  'LinearColor.LinearColor': 'r, g, b and an alpha: a colour has no fifth',
  'LinearColor.fromSrgb': 'r, g, b and an alpha: a colour has no fifth',
  'SrgbColor.SrgbColor': 'r, g, b and an alpha: a colour has no fifth',
  'FormatSpecs.FormatSpecs':
      'a registry seeded with its first specs; it grows by `add`',
  'FormatRegistry.FormatRegistry':
      'a registry seeded with its first specs; it grows by `add`',
  'DataSections.DataSections':
      'a registry seeded with its first sections; it grows by `register`',
  'WorldFields.WorldFields':
      'a registry seeded with its first fields; it grows by `add`',
  'MaterialCompilerRegistry.MaterialCompilerRegistry':
      'a registry seeded with its first compilers; it grows by `register`',
  'EntityKinds.EntityKinds':
      'a registry seeded with its first kinds; it grows by `add`',
  'AssetSources.AssetSources':
      'a registry seeded with its first schemes; it grows by `add`',
  'Bindings.Bindings':
      'a table seeded with its first bindings; it grows by `bind`',
  'Mixer.Mixer':
      'a table seeded with its first bus volumes; it grows by '
      'setting one',
  'MemoryStorage.MemoryStorage':
      'a store seeded with its first documents; it grows by writing one',
  'EntityLayout.ecs': 'the path the layout is, segment by segment',
  'FrameFraction.FrameFraction': 'the one divisor the size is',
  'InterpolatedAngle.InterpolatedAngle': 'the one angle it starts at',
  'Stockpile.Stockpile': 'the one amount it holds',
  'InMemoryDeviceClassMemory.InMemoryDeviceClassMemory':
      'a test double of one value, the class it answers',
  'PluginDependency.PluginDependency':
      'the plugin contract\'s own: made named with the dependency ranges '
      'in that package, which owns the migration',
  'PluginFormatException.PluginFormatException':
      'the plugin contract\'s own: made named in that package with its '
      'other exceptions',
};

/// British words a tool still takes beside the American one, as
/// `server/tool/word`, each with why: a word an agent written against an
/// earlier version sends, which the tool goes on reading so that no caller
/// breaks, as an `alias` keeps an old tool name.
const Map<String, String> britishSchemaAllowed = <String, String>{
  'flutter3d.model/paint.stroke/colour':
      'the argument before `color`; read when `color` is not given',
  'flutter3d.model/paint.stroke/centre':
      'a sample\'s point before `center`; read when `center` is not given',
  'flutter3d.model/paint.vertexColor/colour':
      'the argument before `color`; read when `color` is not given',
  'flutter3d.model/paint.vertexColor/centre':
      'a sample\'s point before `center`; read when `center` is not given',
  'flutter3d.model/object.setOrigin/boundsCentre':
      'the placement before `boundsCenter`, and the word a journal writes',
};

/// Verbs the creation and teardown rule lets stand.
const Map<String, String> verbAllowed = <String, String>{
  'SimWorld.get':
      'the ECS pair `get`/`set` the review names for `SimWorld` (§C): a '
      'component is got and set, and neither is a creation',
  'EcsWorld.get': 'the implementation of `SimWorld.get`',
  'SaveResolution.takeRemote':
      'a value of an open set, not a call: the answer "take the remote copy" '
      'a comparison gives, named as the enum value it was, beside '
      '`keepLocal`',
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
  'ExpressionSystemSpec':
      'an expression system\'s declaration to the runtime, read from a '
      '`.f3dplugin`',
  'WasmFieldSpec': 'a field\'s declaration to the Wasm host',
  'SceneBindingSpec':
      'a declaration made to the `SceneBindingRegistry` (D37): how a '
      'component is shown, as a `.f3dplugin`\'s `bindings:` writes it, not a '
      'setting',
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

// --------------------------------------------------------- a test's minute

/// Test files that give a test, or themselves, longer than a minute, each
/// with the reason and the time it was measured at.
///
/// **A test that runs longer than a minute is a bug until proven otherwise.**
/// Every package's `dart_test.yaml` says `timeout: 1m`, and a `testWidgets`
/// is held to it by `test/flutter_test_config.dart`. A test that genuinely
/// needs longer says so where it is declared — a `timeout:` on the test or a
/// `@Timeout` on its file, with the reason and the measured time in a comment
/// beside it — and is listed here, keyed by its path from the repository
/// root. The rule fails on a longer timeout that is not listed, and on a
/// listed file that no longer has one.
///
/// The slow tests found when the rule arrived were fixed rather than listed:
/// a share server built inside a test, ninety frames rasterised and never
/// looked at, a sun map reset tile by tile on every frame of a bake, a
/// screenshot pumping twenty-four full-window frames per JSON-RPC call.
const Map<String, String> slowTestsAllowed = <String, String>{
  'packages/flutter3d/test/render_benchmark_test.dart':
      'a benchmark, tagged and skipped outside tool/benchmarks.sh: three '
      'frames up to 7680x4320 on the software rasteriser, 139.6 s together '
      'on an M3 Pro on 2026-09-25',
  'packages/flutter3d/test/sculpt_budget_benchmark_test.dart':
      'a benchmark, tagged and skipped outside tool/benchmarks.sh: a '
      '1.2-million-triangle mesh uploaded, a BVH built over it and a stroke '
      'repeated three times — 3.35 s of setup and about 306 ms a stroke on '
      'an M3 Pro on 2026-09-13',
  'packages/flutter3d_app/test/widget_surface_pipeline_benchmark_test.dart':
      'a benchmark, tagged and skipped outside tool/benchmarks.sh: sixty '
      '512x512 frames rasterised and read back, twice, to time a redraw '
      'against a skip',
  'packages/flutter3d_build/test/create_project_kinds_test.dart':
      'tagged slow: every kind `create project` makes, scaffolded, resolved, '
      'analysed and its own widget test run by `flutter test` in a process '
      'of its own, which runs the build hooks first (the C physics core and '
      'the shader bundle): 2 to 4.5 min a kind the first time on an M3 Pro '
      'on 2026-10-12, 10 to 75 s once the hooks are built',
};

/// The widget test that checks `test/flutter_test_config.dart` still does what
/// it says: holds a widget test to a factor of one, through an order inside
/// flutter_test that an upgrade could change, and leaves the binding's HTTP
/// stub where it was. Every suite's configuration is held identical to the
/// one beside it, so this one test speaks for all of them.
const String minuteConfigGuard =
    'packages/flutter3d_editor_widgets/test/minute_config_test.dart';

/// Longer timeouts that were in the tree before the minute was the rule,
/// with what each one is for as its own comment or test says it.
///
/// **A to-do list, not an exemption**, like [interfaceClassPending]: none of
/// these has been timed against the minute yet. When a test here is timed,
/// it is made to fit the minute and its timeout removed, or it moves to
/// [slowTestsAllowed] with the measurement beside its reason. A new long
/// timeout is not added here.
const Map<String, String> slowTestsPending = <String, String>{
  'apps/flutter3d_demo_dungeon/test/frame_test.dart':
      'walks the crypt\'s whole five-level chain on the software rasteriser; '
      'its comment calls two minutes three times the measurement',
  'apps/flutter3d_demo_dungeon/test/headless_verify_test.dart':
      'a recorded run verified by playing the crypt blind, fire and water '
      'included',
  'apps/flutter3d_demo_dungeon/test/replay_video_test.dart':
      'a .f3drun rendered to a video with no GPU, through ffmpeg',
  'apps/flutter3d_demo_strategy/test/demo_test.dart':
      'a whole match recorded and replayed twice, once from a bare match',
  'apps/flutter3d_demo_strategy/test/map_world_test.dart':
      'a match on the map world saved, restored and stepped on beside the '
      'original',
  'packages/flame_multiplayer/test/party_relay_test.dart':
      'a party of four over real sockets on the relay, rolling back into '
      'agreement',
  'packages/flutter3d_build/test/lights_test.dart':
      'the light optimizer from a command line, once per device class',
  'packages/flutter3d_build/test/migrate_fixture_test.dart':
      'the 0.8 fixture project migrated and then `flutter analyze`d in a '
      'process of its own',
  'packages/flutter3d_build/test/migration_kinds_enum_to_class_test.dart':
      'a migration kind applied to its fixture and the result analysed',
  'packages/flutter3d_build/test/migration_kinds_hook_context_test.dart':
      'a migration kind applied to its fixture and the result analysed',
  'packages/flutter3d_build/test/migration_kinds_internal_test.dart':
      'a migration kind applied to its fixture and the result analysed',
  'packages/flutter3d_build/test/migration_kinds_null_to_throw_test.dart':
      'a migration kind applied to its fixture and the result analysed',
  'packages/flutter3d_build/test/migration_kinds_parameters_test.dart':
      'a migration kind applied to its fixture and the result analysed',
  'packages/flutter3d_build/test/migration_kinds_record_to_class_test.dart':
      'a migration kind applied to its fixture and the result analysed',
  'packages/flutter3d_build/test/migration_kinds_regroup_test.dart':
      'a migration kind applied to its fixture and the result analysed',
  'packages/flutter3d_demo_content/test/sim_mcp/fixtures/sim_mcp_server.dart':
      'the server the suite starts once in a process of its own, alive long '
      'enough for each of its tests to connect, open a level and step it; '
      'killed before this runs out',
  'packages/flutter3d_game/test/run_timeline_extensions_test.dart':
      'a fixture game started under `flutter run` and driven through its '
      'VM service',
  'packages/flutter3d_impeller/test/metal_bindings_test.dart':
      'every stage compiled by impellerc and its Metal reflection read',
  'packages/flutter3d_impeller/test/shader_bundle_build_test.dart':
      'a real impellerc build of the shader bundle',
  'packages/flutter3d_impeller/test/stage_bindings_test.dart':
      'every stage compiled by impellerc and compared with the committed '
      'table',
  'packages/flutter3d_mcp/test/editor/dungeon_frame_test.dart':
      'runs only with FLUTTER3D_RUN_GAMES=1: the dungeon under `flutter run` '
      'with an agent driving it from a cold session',
  'packages/flutter3d_mcp/test/model/phase_four_scenario_test.dart':
      'the phase-four scenario end to end over MCP: subdivided, sculpted, '
      'retopologised, unwrapped, baked, painted and exported',
  'packages/flutter3d_mesh/test/bake_test.dart':
      'a 256x256 bake, timed and printed',
  'packages/flutter3d_mesh/test/multires_test.dart':
      'a multiresolution stack built over a dense mesh, timed and printed',
  'packages/flutter3d_mesh/test/ux39_fuzz_test.dart':
      'five hundred insets, slides and bridges over three seeds, validated '
      'after each',
  'packages/flutter3d_sim_mcp/test/fixtures/render_mcp_server.dart':
      'the server a test starts in a process of its own; killed before '
      'this runs out',
  'packages/flutter3d_testing/test/flip_test.dart':
      'runs only with FLIP_IMAGES set: FLIP over full reference images',
};
