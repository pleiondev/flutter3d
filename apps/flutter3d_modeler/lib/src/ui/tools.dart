/// The modes, and the tools each of them offers.
///
/// **One table, read by four things.** The rail on a desktop, the palette on a
/// tablet, the sheet on a phone and the keyboard all show the same set of
/// tools, and every one of them would otherwise be a second place where a
/// tool's name, icon and shortcut are written down. The rule `ui-07` states is
/// that there is one source: this file. A tool missing from the rail because
/// somebody added it to the palette is a bug that cannot happen if there is
/// nowhere else to add it.
///
/// **No commands here, and that is on purpose.** A tool names what it does with
/// an [id]; what it *does* is one `switch` in `mesh_session.dart` today and a
/// command against a `ModelProject` when there is one. Putting a callback in
/// the table would spread that decision across every row and would have to be
/// unpicked the day the document arrives.
///
/// **Only tools that do something are in it.** Inset is a modelling
/// operation this repository does not have yet — merge exists but hands
/// back a new mesh, which would throw the undo history away — and a rail
/// full of buttons that answer nothing is the fastest way to make a tool feel
/// broken. They arrive here when the operation behind them does. Bevel did,
/// `tut-04`, and has a row below rather than being named here any more.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../settings.dart' show Workspace;

/// The tools that wait for a pointer instead of acting when pressed.
///
/// A set rather than a check at the call site, so that the shell can ask
/// whether a button arms or acts without knowing what any of them do — and so a
/// tool added to the table without a case behind it is a name in one place
/// rather than a button that silently does nothing.
const Set<String> kDragTools = <String>{
  'object.move',
  'object.rotate',
  'object.scale',
  'mesh.move',
  'mesh.rotate',
  'mesh.scale',
};

/// The tools that draw a continuous stroke — a drag sampled many times
/// rather than one gesture resolved on release, the same distinction
/// `InputPolicy.classify` (`input_policy.dart`) reads off `ToolCategory` to
/// decide who gets a touch pointer, the camera or the tool.
///
/// **The weight brush is in it, and only its two paint modes.** `ui-40d`
/// gives the weights sub-mode four tools — `weights.paint`/`weights.assign`
/// both ride `PaintWeights` over however many `BrushSample`s one drag
/// collects, which is what a stroke is; `weights.mirror`/`weights.normalize`
/// run once, over whatever a stroke already touched, and belong beside
/// [kDragTools]'s own single-gesture tools instead.
///
/// `pro-sc-08` adds the eight sculpting brushes, which are what this set was
/// named for in the first place: every one of them is a drag sampled many
/// times over a surface, and `ui-29`'s own "touch doesn't create a stroke"
/// is `InputPolicy` reading this to decide who gets a finger.
const Set<String> kStrokeTools = <String>{
  'weights.paint',
  'weights.assign',
  'sculpt.draw',
  'sculpt.clay',
  'sculpt.inflate',
  'sculpt.smooth',
  'sculpt.flatten',
  'sculpt.grab',
  'sculpt.pinch',
  'sculpt.crease',
  // `pro-pt-05`: the texture brush is a stroke the same way the sculpting
  // one is — sampled over a drag, and kept off a finger by `InputPolicy`.
  'paint.brush',
};

/// What the modeller is being used for.
///
/// **Eleven, and ten of them work.** A person opening this should be able to
/// see what the thing is going to be, so a mode that is not built yet is
/// shown disabled with the phase it arrives in rather than left out
/// entirely — see [ModelerMode.phase]. UV is the one still waiting: `ui-28`
/// built the screen and nothing switches into it yet.
enum ModelerMode {
  object('Object', Icons.category_outlined, 1, ready: true, inEssential: true),
  mesh('Mesh', Icons.hexagon_outlined, 1, ready: true),
  material(
    'Material',
    Icons.palette_outlined,
    2,
    ready: true,
    inEssential: true,
  ),
  uv('UV', Icons.grid_on_outlined, 4, ready: false),
  sculpt('Sculpt', Icons.brush_outlined, 4, ready: true),
  // `pro-rt-03`/`pro-rt-07`, `pro-pt-05`, `pro-sim-06`, `pro-rn-04`: the
  // four screens whose panels were built before a mode switch could reach
  // them. Each is its own mode rather than a sub-mode of another, for the
  // reason `AnimationSubmode`'s own doc comment gives about what a sub-mode
  // is: these are four different workflows over one document, not one
  // workflow looked at four grains.
  retopo('Retopo', Icons.grid_4x4_outlined, 4, ready: true),
  paint('Paint', Icons.format_paint_outlined, 4, ready: true),
  simulation('Simulate', Icons.waves_outlined, 4, ready: true),
  animation('Animation', Icons.animation_outlined, 3, ready: true),
  render('Render', Icons.camera_outlined, 4, ready: true),
  scene('Scene', Icons.light_mode_outlined, 2, ready: true, inEssential: true);

  const ModelerMode(
    this.label,
    this.icon,
    this.phase, {
    required this.ready,
    this.inEssential = false,
  });

  /// Whether the Essential workspace offers this mode — `ux-37`. See
  /// [modesFor].
  final bool inEssential;

  /// English, and not through `l10n` yet: the strings move to `app_en.arb` and
  /// `app_ru.arb` in `ui-22`, and moving them one at a time as each screen
  /// lands is how half a interface ends up translated.
  final String label;

  final IconData icon;

  /// Which phase of the plan brings this mode to life — shown in the tooltip
  /// of a mode that is not [ready] yet. No longer what gates the switcher:
  /// every phase-four mode but UV is ready now, so the number alone cannot
  /// answer it any more.
  final int phase;

  /// Whether this mode's panel is built and wired up, so the switcher should
  /// actually let a person choose it, regardless of its [phase] — `ui-39d`'s
  /// own rule. UV is the one false: its screen exists (`ui-28`) and nothing
  /// switches into it.
  final bool ready;
}

/// Which modes a workspace offers — `ux-37`.
///
/// **Essential is three: Object, Material, Scene.** "Open a model, paint it,
/// export it" is what most people who open a modeller are doing, and a
/// switcher with five icons on it asks them to decide what Mesh mode and
/// Animation mode are before they have done anything. Full is everything
/// this build has.
///
/// Always filtered by [ModelerMode.ready] as well, so a mode nobody has built
/// cannot appear in either workspace — `ux-07`'s own rule, kept here rather
/// than restated at the switcher.
List<ModelerMode> modesFor(Workspace workspace) => <ModelerMode>[
  for (final ModelerMode mode in ModelerMode.values)
    if (mode.ready && (workspace == Workspace.full || mode.inEssential)) mode,
];

/// The modes the phone `NavigationBar` offers, in the handoff's own order —
/// `doc/design/modeler-handoff/README.md`'s own layout table: "Телефон
/// (<600) — `NavigationBar` снизу (Объект, Меш, Материал, Сцена)".
///
/// Deliberately not `ModelerMode.values.where((m) => m.ready)`: animation is
/// [ModelerMode.ready] too as of `ui-39d`, but the phone bar has no room for a
/// fifth destination and the handoff's phone screens simply do not offer
/// animation mode as one — a person on a phone reaches everything else the
/// same way a desktop does.
const List<ModelerMode> kPhoneModes = <ModelerMode>[
  ModelerMode.object,
  ModelerMode.mesh,
  ModelerMode.material,
  ModelerMode.scene,
];

/// What a sub-mode is: the element level a mesh is edited at.
///
/// Only the mesh mode has one, which is why this is its own enum rather than a
/// field every mode carries. `Selection` in `flutter3d_mesh` has the same three
/// levels; they are not the same type on purpose — that one is a fact about a
/// mesh and this is a state of the interface, and the day a fourth level
/// arrives in one of them it will not arrive in the other.
enum MeshSubmode {
  vertex('Vertex', Icons.scatter_plot_outlined, LogicalKeyboardKey.digit1),
  edge('Edge', Icons.timeline_outlined, LogicalKeyboardKey.digit2),
  face('Face', Icons.pentagon_outlined, LogicalKeyboardKey.digit3);

  const MeshSubmode(this.label, this.icon, this.shortcut);

  final String label;
  final IconData icon;
  final LogicalKeyboardKey shortcut;
}

/// What a sub-mode is for the animation mode: which of the four workflows
/// screens 07/13/14/15 of the hand-off draw is on screen — `ui-40d`'s own
/// row, the same shape [MeshSubmode] already is and, like it, a state of the
/// interface rather than a fact `flutter3d_model_core` itself knows about.
///
/// **Four, not three, and the tool rail changes with it.** A mesh's three
/// levels all reach for the same twelve tools — `toolsFor(ModelerMode.mesh)`
/// does not even take a [MeshSubmode] — because vertex, edge and face are one
/// workflow looked at three grains. Pose, weight-paint, retarget and morphs
/// are four different workflows that happen to share a mode button; posing a
/// joint and mapping a bone name are not the same operation at a different
/// grain, so [toolsFor] and `sectionsFor` (`properties_sections.dart`) both
/// take this as an argument and switch their whole answer on it, the same
/// "replaced wholesale" rule the mode switch itself already follows.
enum AnimationSubmode {
  pose('Pose', Icons.accessibility_new_outlined, LogicalKeyboardKey.digit1),
  weights('Weights', Icons.gradient_outlined, LogicalKeyboardKey.digit2),
  retarget('Retarget', Icons.sync_alt_outlined, LogicalKeyboardKey.digit3),
  morphs('Morphs', Icons.face_outlined, LogicalKeyboardKey.digit4);

  const AnimationSubmode(this.label, this.icon, this.shortcut);

  final String label;
  final IconData icon;
  final LogicalKeyboardKey shortcut;
}

/// One button, wherever it is shown.
@immutable
final class ModelerTool {
  const ModelerTool({
    required this.id,
    required this.label,
    required this.about,
    required this.icon,
    required this.shortcut,
    required this.group,
  });

  /// What this tool is, for the rest of the application. Stable across a
  /// rename of the label, which is the point of having it.
  final String id;

  final String label;

  /// One sentence saying what pressing this actually does — `ux-18`.
  ///
  /// **A label is a name and not an explanation.** "Dissolve edges", "Bake",
  /// "Normalize" and "Loop cut" are words somebody who has used a modeller
  /// before already knows and somebody opening their first one has no way to
  /// guess at, and the review watched people find out by pressing and
  /// undoing. The desktop rail puts this on the second line of its tooltip,
  /// the tablet palette does the same, the command palette shows it under the
  /// name, and `tools_test.dart` refuses a tool that has none: a button
  /// nobody can describe in a sentence is a button that should not have been
  /// added.
  final String about;

  final IconData icon;

  /// The key that arms it. One key, not a combination: the modelling keys are
  /// single letters because a hand rests on them, and the combinations belong
  /// to the application-wide actions — save, undo, export.
  final LogicalKeyboardKey shortcut;

  /// Tools of one group are drawn together with a divider between groups.
  final String group;
}

/// The tools of [mode], in the order they are shown — [animation] picks
/// which of the four the animation mode shows, and is ignored by every
/// other mode.
///
/// A list rather than a map, because the order *is* part of the design: the
/// thing a person reaches for most is at the top of the rail, and a map would
/// leave that to whatever the iteration order happens to be.
///
/// **[animation] left null answers empty, not [AnimationSubmode.pose]'s own
/// tools.** Unlike `sectionsFor`, which falls back to the sub-mode the
/// animation section already showed before `ui-40d` so every caller of the
/// bare, one-argument form keeps reading exactly what it always has, nothing
/// here called the rail with one argument before this row — there is no old
/// behaviour a default could stand in for, and answering empty is the same
/// refusal every other not-yet-adopted mode already gets from the `_ =>`
/// case below.
List<ModelerTool> toolsFor(
  ModelerMode mode, {
  AnimationSubmode? animation,
}) => switch (mode) {
  ModelerMode.object => const <ModelerTool>[
    ModelerTool(
      id: 'object.select',
      label: 'Select',
      about:
          'Click an object to work on it; shift-click adds to what is '
          'already picked.',
      icon: Icons.near_me_outlined,
      shortcut: LogicalKeyboardKey.keyQ,
      group: 'transform',
    ),
    ModelerTool(
      id: 'object.move',
      label: 'Move',
      about:
          'Drag an arrow to slide it along one axis, or the centre to '
          'move it freely.',
      icon: Icons.open_with_outlined,
      shortcut: LogicalKeyboardKey.keyG,
      group: 'transform',
    ),
    ModelerTool(
      id: 'object.rotate',
      label: 'Rotate',
      about: 'Drag a ring to turn it about that axis.',
      icon: Icons.rotate_90_degrees_ccw_outlined,
      shortcut: LogicalKeyboardKey.keyR,
      group: 'transform',
    ),
    ModelerTool(
      id: 'object.scale',
      label: 'Scale',
      about:
          'Drag a handle to grow or shrink it — one axis at a time, or '
          'all three from the centre.',
      icon: Icons.aspect_ratio_outlined,
      shortcut: LogicalKeyboardKey.keyS,
      group: 'transform',
    ),
    ModelerTool(
      id: 'object.add',
      label: 'Add a box',
      about:
          'Puts a new box at the origin, still parametric: its size and '
          'segment counts stay editable in the panel.',
      icon: Icons.add_box_outlined,
      shortcut: LogicalKeyboardKey.keyA,
      group: 'create',
    ),
    ModelerTool(
      id: 'object.duplicate',
      label: 'Duplicate',
      about:
          'Copies what is selected and selects the copy, leaving the '
          'original where it was.',
      icon: Icons.copy_all_outlined,
      shortcut: LogicalKeyboardKey.keyD,
      group: 'create',
    ),
    ModelerTool(
      id: 'object.bake',
      label: 'Convert to a mesh',
      about:
          'Turns a shape that still knows its own parameters into plain '
          'editable geometry. Its size and segment fields go away.',
      icon: Icons.change_circle_outlined,
      shortcut: LogicalKeyboardKey.keyB,
      group: 'create',
    ),
    ModelerTool(
      id: 'object.lathe',
      label: 'Add a lathe',
      about:
          'Spins a profile you draw around an axis — how a vase, a '
          'bottle or a wheel is made.',
      icon: Icons.wine_bar_outlined,
      shortcut: LogicalKeyboardKey.keyL,
      group: 'create',
    ),
    ModelerTool(
      id: 'object.origin',
      label: 'Origin to the bottom',
      about:
          'Moves the point the object turns and scales about down to its '
          'lowest vertex, so it sits on the floor.',
      icon: Icons.vertical_align_bottom_outlined,
      shortcut: LogicalKeyboardKey.keyO,
      group: 'cleanup',
    ),
    ModelerTool(
      id: 'object.apply',
      label: 'Apply the transform',
      about:
          'Folds the position, rotation and scale into the vertices '
          'themselves and leaves the transform at rest.',
      icon: Icons.done_all_outlined,
      shortcut: LogicalKeyboardKey.keyY,
      group: 'cleanup',
    ),
    ModelerTool(
      id: 'object.delete',
      label: 'Delete',
      about: 'Removes what is selected. Undo brings it back.',
      icon: Icons.backspace_outlined,
      shortcut: LogicalKeyboardKey.keyX,
      group: 'cleanup',
    ),
  ],
  ModelerMode.mesh => const <ModelerTool>[
    ModelerTool(
      id: 'mesh.select',
      label: 'Select',
      about:
          'Click a vertex, edge or face; shift-click adds to what is '
          'already picked.',
      icon: Icons.near_me_outlined,
      shortcut: LogicalKeyboardKey.keyQ,
      group: 'transform',
    ),
    // `ux-28`. The same drag as Select, catching what a freehand loop
    // encloses rather than what a rectangle does — a button rather than a
    // modifier because a drag's two modifiers are already add and subtract
    // and the third is the camera's under half the navigation schemes.
    ModelerTool(
      id: 'mesh.lasso',
      label: 'Lasso select',
      about:
          'Draw a freehand loop round what you want instead of clicking '
          'each part of it.',
      icon: Icons.gesture_outlined,
      shortcut: LogicalKeyboardKey.keyK,
      group: 'transform',
    ),
    // `ux-28`. On the rail rather than on the keyboard alone, so that it is
    // reachable on a tablet and findable in the palette — and in the
    // `transform` group beside Select, because it is the other half of
    // choosing what to work on rather than an edit.
    ModelerTool(
      id: 'mesh.linked',
      label: 'Select linked',
      about:
          'Takes everything joined to what is already picked — one whole '
          'shell of a mesh that has several.',
      icon: Icons.hub_outlined,
      shortcut: LogicalKeyboardKey.keyL,
      group: 'transform',
    ),
    ModelerTool(
      id: 'mesh.move',
      label: 'Move',
      about:
          'Drags the picked elements. Typing a number while dragging sets '
          'the distance exactly.',
      icon: Icons.open_with_outlined,
      shortcut: LogicalKeyboardKey.keyG,
      group: 'transform',
    ),
    ModelerTool(
      id: 'mesh.rotate',
      label: 'Rotate',
      about: 'Turns the picked elements about the middle of the selection.',
      icon: Icons.rotate_90_degrees_ccw_outlined,
      shortcut: LogicalKeyboardKey.keyR,
      group: 'transform',
    ),
    ModelerTool(
      id: 'mesh.scale',
      label: 'Scale',
      about:
          'Grows or shrinks the picked elements about the middle of the '
          'selection.',
      icon: Icons.aspect_ratio_outlined,
      shortcut: LogicalKeyboardKey.keyS,
      group: 'transform',
    ),
    ModelerTool(
      id: 'mesh.extrude',
      label: 'Extrude',
      about:
          'Pulls new geometry out of the picked faces and leaves a wall '
          'joining it to where it came from.',
      icon: Icons.upload_outlined,
      shortcut: LogicalKeyboardKey.keyE,
      group: 'topology',
    ),
    ModelerTool(
      id: 'mesh.loopCut',
      label: 'Loop cut',
      about:
          'Adds a ring of edges all the way round the mesh, where the '
          'next change of shape needs one to bend at.',
      icon: Icons.content_cut_outlined,
      shortcut: LogicalKeyboardKey.keyC,
      group: 'topology',
    ),
    ModelerTool(
      id: 'mesh.bevel',
      label: 'Bevel',
      about:
          'Replaces a sharp edge with a narrow strip, so light catches it '
          'the way it does on a real object.',
      icon: Icons.rounded_corner_outlined,
      shortcut: LogicalKeyboardKey.keyB,
      group: 'topology',
    ),
    ModelerTool(
      id: 'mesh.inset',
      label: 'Inset',
      about:
          'Shrinks a face inward and walls the ring it leaves — how a '
          'panel, a window or a recessed button is made.',
      icon: Icons.filter_frames_outlined,
      shortcut: LogicalKeyboardKey.keyI,
      group: 'topology',
    ),
    ModelerTool(
      id: 'mesh.bridge',
      label: 'Bridge',
      about:
          'Joins two open borders with a ring of quads, so two halves of a '
          'tube become one surface.',
      icon: Icons.compare_arrows_outlined,
      shortcut: LogicalKeyboardKey.keyJ,
      group: 'topology',
    ),
    ModelerTool(
      id: 'mesh.slide',
      label: 'Edge slide',
      about:
          'Moves a loop along the edges that cross it, changing where a '
          'seam sits without changing a single face.',
      icon: Icons.swap_horiz_outlined,
      shortcut: LogicalKeyboardKey.keyZ,
      group: 'topology',
    ),
    ModelerTool(
      id: 'mesh.triangulate',
      label: 'Triangulate',
      about:
          'Cuts every face into triangles — what a game engine reads, and '
          'what a face with more than four corners has to become first.',
      icon: Icons.change_history_outlined,
      shortcut: LogicalKeyboardKey.keyT,
      group: 'topology',
    ),
    ModelerTool(
      id: 'mesh.separate',
      label: 'Separate',
      about: 'Moves the picked faces out into an object of their own.',
      icon: Icons.call_split_outlined,
      shortcut: LogicalKeyboardKey.keyP,
      group: 'topology',
    ),
    ModelerTool(
      id: 'mesh.dissolve',
      label: 'Dissolve edges',
      about:
          'Removes the picked edges but keeps the surface, merging the '
          'faces they divided into one.',
      icon: Icons.remove_outlined,
      shortcut: LogicalKeyboardKey.keyV,
      group: 'cleanup',
    ),
    // `ux-16`. `mesh_repair.dart`'s own `fillHoles` and `FillHoles` have both
    // existed since `mesh-81n` and nothing in the interface pressed either:
    // the one way to close a hole was to ask an agent.
    ModelerTool(
      id: 'mesh.fillHoles',
      label: 'Fill holes',
      about:
          'Closes every open boundary — the gaps that make a model look '
          'see-through from one side.',
      icon: Icons.format_color_fill_outlined,
      shortcut: LogicalKeyboardKey.keyH,
      group: 'cleanup',
    ),
    ModelerTool(
      id: 'mesh.merge',
      label: 'Merge by distance',
      about:
          'Fuses vertices sitting on top of each other, which is what a '
          'scan or an STL arrives full of.',
      icon: Icons.compress_outlined,
      shortcut: LogicalKeyboardKey.keyM,
      group: 'cleanup',
    ),
    ModelerTool(
      id: 'mesh.normals',
      label: 'Recalculate normals',
      about:
          'Points every face outward again, so the surface stops reading '
          'as inside-out.',
      icon: Icons.north_outlined,
      shortcut: LogicalKeyboardKey.keyN,
      group: 'cleanup',
    ),
    ModelerTool(
      id: 'mesh.flip',
      label: 'Flip normals',
      about:
          'Turns the picked faces the other way round, for the shell that '
          'really is meant to be seen from inside.',
      icon: Icons.south_outlined,
      shortcut: LogicalKeyboardKey.keyF,
      group: 'cleanup',
    ),
    ModelerTool(
      id: 'mesh.delete',
      label: 'Delete',
      about:
          'Removes the picked vertices, edges or faces, and whatever '
          'depended on them.',
      icon: Icons.backspace_outlined,
      shortcut: LogicalKeyboardKey.keyX,
      group: 'cleanup',
    ),
  ],
  // `ui-40d`'s own row: which four tools depends on which of the four
  // workflows [animation] names — null (nobody has told the rail which one
  // yet) answers empty rather than guessing [AnimationSubmode.pose], see
  // this function's own doc comment for why that differs from
  // `sectionsFor`'s default.
  ModelerMode.animation => switch (animation) {
    null => const <ModelerTool>[],
    AnimationSubmode.pose => const <ModelerTool>[
      // `keyframe_commands.dart`'s own `PoseJoint`, run once per
      // `AnimationPath` (translation/rotation/scale — its own "three
      // paths") inside one transaction, is what `key` keys; `select` arms
      // nothing of its own, the same as `object.select`/`mesh.select`.
      ModelerTool(
        id: 'pose.select',
        label: 'Select',
        about: 'Click a joint of the skeleton to pose it.',
        icon: Icons.near_me_outlined,
        shortcut: LogicalKeyboardKey.keyQ,
        group: 'select',
      ),
      ModelerTool(
        id: 'pose.key',
        label: 'Key the pose',
        about:
            'Writes the pose on screen into the clip, at the frame the '
            'playhead is on.',
        icon: Icons.vpn_key_outlined,
        shortcut: LogicalKeyboardKey.keyI,
        group: 'keys',
      ),
      ModelerTool(
        id: 'pose.deleteKey',
        label: 'Delete the key',
        about:
            'Takes this frame\'s key back out, leaving the keys either '
            'side to carry the motion through it.',
        icon: Icons.backspace_outlined,
        shortcut: LogicalKeyboardKey.keyX,
        group: 'keys',
      ),
      // `S8`'s own row: opens `autorig_dialog.dart` rather than acting
      // immediately, the same "arms the button, opens a dialog" shape
      // `object.lathe` already uses in `_ranTool`.
      ModelerTool(
        id: 'pose.autoRig',
        label: 'Auto-rig…',
        about:
            'Builds a skeleton from a handful of points you place on the '
            'model.',
        icon: Icons.accessibility_new_outlined,
        shortcut: LogicalKeyboardKey.keyU,
        group: 'rig',
      ),
    ],
    AnimationSubmode.weights => const <ModelerTool>[
      // All four ride `paint_weights.dart`'s own `PaintWeights` — `paint`
      // and `assign` are its two `PaintWeightsMode`s, sampled over a
      // stroke (`kStrokeTools`); `mirror` and `normalize` are its own
      // `mirror`/`normalize` arguments, run once over what a stroke
      // already touched rather than sampled themselves.
      ModelerTool(
        id: 'weights.paint',
        label: 'Paint weights',
        about:
            'Brushes how strongly the chosen joint pulls on the surface '
            'under the cursor.',
        icon: Icons.brush_outlined,
        shortcut: LogicalKeyboardKey.keyB,
        group: 'brush',
      ),
      ModelerTool(
        id: 'weights.assign',
        label: 'Assign to the joint',
        about:
            'Gives every vertex the brush touches to the chosen joint, at '
            'full strength.',
        icon: Icons.push_pin_outlined,
        shortcut: LogicalKeyboardKey.keyA,
        group: 'brush',
      ),
      ModelerTool(
        id: 'weights.mirror',
        label: 'Mirror',
        about:
            'Copies one side\'s weights onto the other, so a symmetrical '
            'model is painted once.',
        icon: Icons.flip_outlined,
        shortcut: LogicalKeyboardKey.keyM,
        group: 'symmetry',
      ),
      ModelerTool(
        id: 'weights.normalize',
        label: 'Normalize',
        about:
            'Makes each vertex\'s pulls add up to one and drops the '
            'smallest past the profile\'s own limit.',
        icon: Icons.balance_outlined,
        shortcut: LogicalKeyboardKey.keyN,
        group: 'symmetry',
      ),
    ],
    AnimationSubmode.retarget => const <ModelerTool>[
      // `import` opens a second document the same way `screen/files.dart`
      // already reads one for File/Open — `anim-18`'s own
      // `RetargetSource.fromDocument` is the retarget-shaped wrapper
      // around that read, not a second way of reading a file. `autoMap`
      // is `flutter3d_rig`'s own `autoMap`; `apply` is
      // `RetargetClipJobRequest` → `ApplyClipResult`, `retargetInBackground`'s
      // own job.
      ModelerTool(
        id: 'retarget.import',
        label: 'Import a source clip',
        about: 'Reads a clip out of another file to drive this rig with.',
        icon: Icons.file_open_outlined,
        shortcut: LogicalKeyboardKey.keyI,
        group: 'source',
      ),
      ModelerTool(
        id: 'retarget.autoMap',
        label: 'Map bones automatically',
        about:
            'Guesses which bone of the source matches which of this rig, '
            'from their names.',
        icon: Icons.auto_fix_high_outlined,
        shortcut: LogicalKeyboardKey.keyM,
        group: 'mapping',
      ),
      ModelerTool(
        id: 'retarget.apply',
        label: 'Apply the retarget',
        about: 'Writes the mapped motion onto this rig as a clip of its own.',
        icon: Icons.check_circle_outlined,
        shortcut: LogicalKeyboardKey.enter,
        group: 'mapping',
      ),
    ],
    AnimationSubmode.morphs => const <ModelerTool>[
      // `shape_commands.dart`'s own `AddShapeFromMesh`, `KeyShape` and
      // `DeleteShape`.
      ModelerTool(
        id: 'morphs.add',
        label: 'Add a shape',
        about:
            'Takes the mesh as it stands now as a shape the slider can '
            'blend towards.',
        icon: Icons.add_circle_outlined,
        shortcut: LogicalKeyboardKey.keyA,
        group: 'shapes',
      ),
      ModelerTool(
        id: 'morphs.key',
        label: 'Key the shape',
        about:
            'Writes the shape weights as they stand into the clip, at the '
            'playhead.',
        icon: Icons.vpn_key_outlined,
        shortcut: LogicalKeyboardKey.keyK,
        group: 'shapes',
      ),
      ModelerTool(
        id: 'morphs.delete',
        label: 'Delete the shape',
        about: 'Removes the selected shape and the slider that drove it.',
        icon: Icons.backspace_outlined,
        shortcut: LogicalKeyboardKey.keyX,
        group: 'shapes',
      ),
    ],
  },
  // `pro-sc-08`: the eight brushes, one rail tool each. The sculpting layout
  // has no rail on it — `SculptChrome`'s own palette is where these are
  // pressed — but they are rail tools all the same, because the armed tool
  // is one value and the keyboard, the command palette and an agent's own
  // `ui.setTool` all reach it through this list.
  ModelerMode.sculpt => const <ModelerTool>[
    ModelerTool(
      id: 'sculpt.draw',
      label: 'Draw',
      about:
          'Pushes everything under the brush out along one shared '
          'direction, the way a stamp would.',
      icon: Icons.brush_outlined,
      shortcut: LogicalKeyboardKey.keyQ,
      group: 'build',
    ),
    ModelerTool(
      id: 'sculpt.clay',
      label: 'Clay',
      about: 'Builds the surface up in flat layers, like thumbing clay on.',
      icon: Icons.layers_outlined,
      shortcut: LogicalKeyboardKey.keyW,
      group: 'build',
    ),
    ModelerTool(
      id: 'sculpt.inflate',
      label: 'Inflate',
      about:
          'Pushes each vertex along its own normal, so a rounded patch '
          'puffs up rather than rising as a plane.',
      icon: Icons.bubble_chart_outlined,
      shortcut: LogicalKeyboardKey.keyE,
      group: 'build',
    ),
    ModelerTool(
      id: 'sculpt.smooth',
      label: 'Smooth',
      about: 'Evens out what is under the brush, taking the bumps down.',
      icon: Icons.blur_on_outlined,
      shortcut: LogicalKeyboardKey.keyR,
      group: 'even',
    ),
    ModelerTool(
      id: 'sculpt.flatten',
      label: 'Flatten',
      about: 'Pulls everything under the brush toward one plane.',
      icon: Icons.horizontal_rule_outlined,
      shortcut: LogicalKeyboardKey.keyT,
      group: 'even',
    ),
    ModelerTool(
      id: 'sculpt.grab',
      label: 'Grab',
      about: 'Drags the vertices under the brush along with the pointer.',
      icon: Icons.pan_tool_outlined,
      shortcut: LogicalKeyboardKey.keyG,
      group: 'move',
    ),
    ModelerTool(
      id: 'sculpt.pinch',
      label: 'Pinch',
      about: 'Pulls the vertices under the brush toward its centre.',
      icon: Icons.compress_outlined,
      // **`P`, not `F`.** Two of the three keymap presets frame the
      // selection on `F` — the tool school's own habit — so a brush on the
      // same letter is one of the two never reached from the keyboard, and
      // which one wins is whichever the `Shortcuts` map happened to build
      // last. `keymap_test.dart` is what said so.
      shortcut: LogicalKeyboardKey.keyP,
      group: 'move',
    ),
    ModelerTool(
      id: 'sculpt.crease',
      label: 'Crease',
      about: 'Pinches and sinks at once, which is how a fold is cut in.',
      icon: Icons.change_history_outlined,
      shortcut: LogicalKeyboardKey.keyC,
      group: 'move',
    ),
  ],
  // `pro-rt-03`/`pro-rt-07`: drawing the new mesh over the old one, and the
  // two long jobs that follow.
  ModelerMode.retopo => const <ModelerTool>[
    ModelerTool(
      id: 'retopo.quad',
      label: 'Draw a quad',
      about:
          'Click four points on the high mesh; each one snaps to a vertex '
          'the new mesh already has, or lands on the surface.',
      icon: Icons.highlight_alt_outlined,
      shortcut: LogicalKeyboardKey.keyQ,
      group: 'draw',
    ),
    ModelerTool(
      id: 'retopo.auto',
      label: 'Retopologize',
      about:
          'Rebuilds the whole surface as quads at about the count the panel '
          'asks for, shrink-wrapped back onto the original.',
      icon: Icons.grid_on_outlined,
      shortcut: LogicalKeyboardKey.keyR,
      group: 'draw',
    ),
    ModelerTool(
      id: 'retopo.bake',
      label: 'Bake the maps',
      about:
          'Bakes the high mesh\'s own surface into the low one\'s UVs — a '
          'normal map, an occlusion map, or both.',
      icon: Icons.texture_outlined,
      shortcut: LogicalKeyboardKey.keyB,
      group: 'bake',
    ),
  ],
  // `pro-pt-05`: one brush, and the two one-shot actions beside it.
  ModelerMode.paint => const <ModelerTool>[
    ModelerTool(
      id: 'paint.brush',
      label: 'Brush',
      about:
          'Paints onto the object\'s own texture, through its UVs — a '
          'stroke over a seam paints both islands.',
      icon: Icons.brush_outlined,
      shortcut: LogicalKeyboardKey.keyQ,
      group: 'paint',
    ),
    ModelerTool(
      id: 'paint.fill',
      label: 'Fill the layer',
      about: 'Floods the whole layer with the colour on the palette.',
      icon: Icons.format_color_fill_outlined,
      // `B` for the bucket, and not `F` — see `sculpt.pinch` above for what
      // `F` already answers to.
      shortcut: LogicalKeyboardKey.keyB,
      group: 'paint',
    ),
    ModelerTool(
      id: 'paint.clear',
      label: 'Clear the layer',
      about: 'Empties the layer without touching the ones under it.',
      icon: Icons.layers_clear_outlined,
      shortcut: LogicalKeyboardKey.keyX,
      group: 'paint',
    ),
  ],
  // `pro-sim-06`: what is simulated, and what holds it up.
  ModelerMode.simulation => const <ModelerTool>[
    ModelerTool(
      id: 'sim.select',
      label: 'Select',
      about: 'Pick the vertices a cloth hangs from, or the object to solve.',
      icon: Icons.near_me_outlined,
      shortcut: LogicalKeyboardKey.keyQ,
      group: 'select',
    ),
    ModelerTool(
      id: 'sim.pin',
      label: 'Pin the selection',
      about: 'Holds the selected vertices still while everything else falls.',
      icon: Icons.push_pin_outlined,
      shortcut: LogicalKeyboardKey.keyP,
      group: 'select',
    ),
    ModelerTool(
      id: 'sim.bake',
      label: 'Bake',
      about: 'Solves the whole clip and keeps it, so it can be scrubbed.',
      icon: Icons.play_circle_outline,
      shortcut: LogicalKeyboardKey.keyB,
      group: 'cache',
    ),
  ],
  // `pro-rn-04`: one button and the pass list beside it.
  ModelerMode.render => const <ModelerTool>[
    ModelerTool(
      id: 'render.snapshot',
      label: 'Render',
      about:
          'Renders the project at the size on the panel, one tile at a time, '
          'and shows the result.',
      icon: Icons.camera_outlined,
      shortcut: LogicalKeyboardKey.keyR,
      group: 'render',
    ),
    ModelerTool(
      id: 'render.save',
      label: 'Save the picture',
      about: 'Writes the last render out as a PNG.',
      icon: Icons.save_outlined,
      shortcut: LogicalKeyboardKey.keyS,
      group: 'render',
    ),
  ],
  // Every mode past phase one is drawn on the bar and refused, so there is
  // nothing to offer. Returning an empty list rather than throwing, because a
  // rail asking a disabled mode what it holds is not a bug.
  _ => const <ModelerTool>[],
};
