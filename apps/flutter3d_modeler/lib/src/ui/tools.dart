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
/// **Only tools that do something are in it.** Inset, bevel and merge are
/// modelling operations this repository does not have yet — merge exists but
/// hands back a new mesh, which would throw the undo history away — and a rail
/// full of buttons that answer nothing is the fastest way to make a tool feel
/// broken. They arrive here when the operation behind them does.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
/// **Only the weight brush is in it, and only its two paint modes.** `ui-40d`
/// gives the weights sub-mode four tools — `weights.paint`/`weights.assign`
/// both ride `PaintWeights` over however many `BrushSample`s one drag
/// collects, which is what a stroke is; `weights.mirror`/`weights.normalize`
/// run once, over whatever a stroke already touched, and belong beside
/// [kDragTools]'s own single-gesture tools instead.
const Set<String> kStrokeTools = <String>{'weights.paint', 'weights.assign'};

/// What the modeller is being used for.
///
/// **All eight are here and five of them work**, which is deliberate: a person
/// opening this should be able to see what the thing is going to be, and a mode
/// that is missing entirely reads as a mode that was never planned. The rest
/// are shown disabled, with the phase they arrive in — see [ModelerMode.phase].
enum ModelerMode {
  object('Object', Icons.category_outlined, 1, ready: true),
  mesh('Mesh', Icons.hexagon_outlined, 1, ready: true),
  material('Material', Icons.palette_outlined, 2, ready: true),
  uv('UV', Icons.grid_on_outlined, 4, ready: false),
  sculpt('Sculpt', Icons.brush_outlined, 4, ready: false),
  animation('Animation', Icons.animation_outlined, 3, ready: true),
  render('Render', Icons.camera_outlined, 4, ready: false),
  scene('Scene', Icons.light_mode_outlined, 2, ready: true);

  const ModelerMode(this.label, this.icon, this.phase, {required this.ready});

  /// English, and not through `l10n` yet: the strings move to `app_en.arb` and
  /// `app_ru.arb` in `ui-22`, and moving them one at a time as each screen
  /// lands is how half a interface ends up translated.
  final String label;

  final IconData icon;

  /// Which phase of the plan brings this mode to life — shown in the tooltip
  /// of a mode that is not [ready] yet. No longer what gates the switcher: a
  /// phase-2 mode (material, scene) and a phase-3 one (animation) are ready
  /// today while another phase-2 mode (uv) and a phase-4 one (sculpt, render)
  /// are not, so the number alone cannot answer it any more.
  final int phase;

  /// Whether this mode's panel is built and wired up, so the switcher should
  /// actually let a person choose it. `ui-39d`: object, mesh, material,
  /// animation and scene are; uv, sculpt and render — the pro-mode rows — are
  /// deliberately not, regardless of their [phase].
  final bool ready;
}

/// The modes the phone `NavigationBar` offers, in the handoff's own order —
/// `README.md:137`: "Object, Mesh, Material, Scene". Not
/// `ModelerMode.values.where((m) => m.ready)`: animation is [ModelerMode.ready]
/// too as of `ui-39d`, but the phone bar has no room for a fifth destination
/// and the handoff's phone screens simply do not offer animation mode as one
/// — a person on a phone reaches everything else the same way a desktop does.
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
    required this.icon,
    required this.shortcut,
    required this.group,
  });

  /// What this tool is, for the rest of the application. Stable across a
  /// rename of the label, which is the point of having it.
  final String id;

  final String label;
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
      icon: Icons.near_me_outlined,
      shortcut: LogicalKeyboardKey.keyQ,
      group: 'transform',
    ),
    ModelerTool(
      id: 'object.move',
      label: 'Move',
      icon: Icons.open_with_outlined,
      shortcut: LogicalKeyboardKey.keyG,
      group: 'transform',
    ),
    ModelerTool(
      id: 'object.rotate',
      label: 'Rotate',
      icon: Icons.rotate_90_degrees_ccw_outlined,
      shortcut: LogicalKeyboardKey.keyR,
      group: 'transform',
    ),
    ModelerTool(
      id: 'object.scale',
      label: 'Scale',
      icon: Icons.aspect_ratio_outlined,
      shortcut: LogicalKeyboardKey.keyS,
      group: 'transform',
    ),
    ModelerTool(
      id: 'object.add',
      label: 'Add a box',
      icon: Icons.add_box_outlined,
      shortcut: LogicalKeyboardKey.keyA,
      group: 'create',
    ),
    ModelerTool(
      id: 'object.duplicate',
      label: 'Duplicate',
      icon: Icons.copy_all_outlined,
      shortcut: LogicalKeyboardKey.keyD,
      group: 'create',
    ),
    ModelerTool(
      id: 'object.bake',
      label: 'Convert to a mesh',
      icon: Icons.change_circle_outlined,
      shortcut: LogicalKeyboardKey.keyB,
      group: 'create',
    ),
    ModelerTool(
      id: 'object.lathe',
      label: 'Add a lathe',
      icon: Icons.wine_bar_outlined,
      shortcut: LogicalKeyboardKey.keyL,
      group: 'create',
    ),
    ModelerTool(
      id: 'object.origin',
      label: 'Origin to the bottom',
      icon: Icons.vertical_align_bottom_outlined,
      shortcut: LogicalKeyboardKey.keyO,
      group: 'cleanup',
    ),
    ModelerTool(
      id: 'object.apply',
      label: 'Apply the transform',
      icon: Icons.done_all_outlined,
      shortcut: LogicalKeyboardKey.keyY,
      group: 'cleanup',
    ),
    ModelerTool(
      id: 'object.delete',
      label: 'Delete',
      icon: Icons.backspace_outlined,
      shortcut: LogicalKeyboardKey.keyX,
      group: 'cleanup',
    ),
  ],
  ModelerMode.mesh => const <ModelerTool>[
    ModelerTool(
      id: 'mesh.select',
      label: 'Select',
      icon: Icons.near_me_outlined,
      shortcut: LogicalKeyboardKey.keyQ,
      group: 'transform',
    ),
    ModelerTool(
      id: 'mesh.move',
      label: 'Move',
      icon: Icons.open_with_outlined,
      shortcut: LogicalKeyboardKey.keyG,
      group: 'transform',
    ),
    ModelerTool(
      id: 'mesh.rotate',
      label: 'Rotate',
      icon: Icons.rotate_90_degrees_ccw_outlined,
      shortcut: LogicalKeyboardKey.keyR,
      group: 'transform',
    ),
    ModelerTool(
      id: 'mesh.scale',
      label: 'Scale',
      icon: Icons.aspect_ratio_outlined,
      shortcut: LogicalKeyboardKey.keyS,
      group: 'transform',
    ),
    ModelerTool(
      id: 'mesh.extrude',
      label: 'Extrude',
      icon: Icons.upload_outlined,
      shortcut: LogicalKeyboardKey.keyE,
      group: 'topology',
    ),
    ModelerTool(
      id: 'mesh.loopCut',
      label: 'Loop cut',
      icon: Icons.content_cut_outlined,
      shortcut: LogicalKeyboardKey.keyC,
      group: 'topology',
    ),
    ModelerTool(
      id: 'mesh.triangulate',
      label: 'Triangulate',
      icon: Icons.change_history_outlined,
      shortcut: LogicalKeyboardKey.keyT,
      group: 'topology',
    ),
    ModelerTool(
      id: 'mesh.separate',
      label: 'Separate',
      icon: Icons.call_split_outlined,
      shortcut: LogicalKeyboardKey.keyP,
      group: 'topology',
    ),
    ModelerTool(
      id: 'mesh.dissolve',
      label: 'Dissolve edges',
      icon: Icons.remove_outlined,
      shortcut: LogicalKeyboardKey.keyV,
      group: 'cleanup',
    ),
    ModelerTool(
      id: 'mesh.merge',
      label: 'Merge by distance',
      icon: Icons.compress_outlined,
      shortcut: LogicalKeyboardKey.keyM,
      group: 'cleanup',
    ),
    ModelerTool(
      id: 'mesh.normals',
      label: 'Recalculate normals',
      icon: Icons.north_outlined,
      shortcut: LogicalKeyboardKey.keyN,
      group: 'cleanup',
    ),
    ModelerTool(
      id: 'mesh.flip',
      label: 'Flip normals',
      icon: Icons.south_outlined,
      shortcut: LogicalKeyboardKey.keyF,
      group: 'cleanup',
    ),
    ModelerTool(
      id: 'mesh.delete',
      label: 'Delete',
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
        icon: Icons.near_me_outlined,
        shortcut: LogicalKeyboardKey.keyQ,
        group: 'select',
      ),
      ModelerTool(
        id: 'pose.key',
        label: 'Key the pose',
        icon: Icons.vpn_key_outlined,
        shortcut: LogicalKeyboardKey.keyI,
        group: 'keys',
      ),
      ModelerTool(
        id: 'pose.deleteKey',
        label: 'Delete the key',
        icon: Icons.backspace_outlined,
        shortcut: LogicalKeyboardKey.keyX,
        group: 'keys',
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
        icon: Icons.brush_outlined,
        shortcut: LogicalKeyboardKey.keyB,
        group: 'brush',
      ),
      ModelerTool(
        id: 'weights.assign',
        label: 'Assign to the joint',
        icon: Icons.push_pin_outlined,
        shortcut: LogicalKeyboardKey.keyA,
        group: 'brush',
      ),
      ModelerTool(
        id: 'weights.mirror',
        label: 'Mirror',
        icon: Icons.flip_outlined,
        shortcut: LogicalKeyboardKey.keyM,
        group: 'symmetry',
      ),
      ModelerTool(
        id: 'weights.normalize',
        label: 'Normalize',
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
        icon: Icons.file_open_outlined,
        shortcut: LogicalKeyboardKey.keyI,
        group: 'source',
      ),
      ModelerTool(
        id: 'retarget.autoMap',
        label: 'Map bones automatically',
        icon: Icons.auto_fix_high_outlined,
        shortcut: LogicalKeyboardKey.keyM,
        group: 'mapping',
      ),
      ModelerTool(
        id: 'retarget.apply',
        label: 'Apply the retarget',
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
        icon: Icons.add_circle_outlined,
        shortcut: LogicalKeyboardKey.keyA,
        group: 'shapes',
      ),
      ModelerTool(
        id: 'morphs.key',
        label: 'Key the shape',
        icon: Icons.vpn_key_outlined,
        shortcut: LogicalKeyboardKey.keyK,
        group: 'shapes',
      ),
      ModelerTool(
        id: 'morphs.delete',
        label: 'Delete the shape',
        icon: Icons.backspace_outlined,
        shortcut: LogicalKeyboardKey.keyX,
        group: 'shapes',
      ),
    ],
  },
  // Every mode past phase one is drawn on the bar and refused, so there is
  // nothing to offer. Returning an empty list rather than throwing, because a
  // rail asking a disabled mode what it holds is not a bug.
  _ => const <ModelerTool>[],
};
