/// Which of the properties panel's own sections belong to which mode —
/// `ui-04`'s own "content is replaced wholesale," pulled out where it can be
/// tested directly.
///
/// `PropertiesPanel` (`ui/properties/properties_panel.dart`) is a wide
/// widget to pump for one mapping, so the table this file owns is what
/// stands in for testing that mapping through it directly — a pure
/// function, checkable without a `WidgetTester` at all.
library;

import 'tools.dart';

/// One section the properties panel can show.
enum PropertiesSection {
  display,
  view,
  objects,
  transform,
  modifiers,
  materials,

  /// `ux-40`'s own row: the rest of the Material workspace — a live preview
  /// of the material being edited, its texture slots and its texture graph.
  /// Material mode's alone; object mode keeps [materials] on its own, which
  /// is the compact row a person fixing a mesh needs and not a screen they
  /// have to scroll past to reach the modifier stack.
  materialWorkspace,
  lastOperation,
  selection,
  mesh,
  budget,
  animation,
  sceneSources,
  sceneShadows,
  sceneEnvironment,
  scenePost,

  /// `ui-40d`'s own row: the weight-paint sub-mode's own panel — brush
  /// radius/strength, mirror and normalize flags, the held vertex's own
  /// influences — screen 13 of the hand-off. Built in `anim-12`/`anim-10`'s
  /// own app half, not here; this is the section id `sectionsFor` answers
  /// with for [AnimationSubmode.weights] so that half has somewhere to hang
  /// its panel off of.
  weightPaint,

  /// The retarget sub-mode's own panel — the bone-map table, root-motion
  /// and correction controls — screen 14. `anim-18`'s own row builds the
  /// widget; this is its section id.
  retarget,

  /// The morphs sub-mode's own panel — the shape list with its key dot,
  /// driver rows below it — screen 15. `anim-19`'s own app half builds the
  /// widget; this is its section id.
  morphs,
}

/// Every section [mode] shows — [animation] picks which of the four the
/// animation mode shows, and is ignored by every other mode.
///
/// Display/View/Budget are cross-mode utility — the camera and the export
/// budget mean the same thing regardless of what is being edited — so they
/// answer `true` in every mode rather than disappearing along with the
/// mode-specific sections. Object mode owns the object list, the transform
/// grid, the modifier stack and — `mat-04a-n`'s own row — the material
/// panel: a full `Material` workspace of its own is `ModelerMode.material`'s
/// phase-2 row, but phase 1's own scenario ("clean a mesh, fix its
/// material, export to GLB") needs a way to paint an object today, and
/// object mode is where that object already is. Mesh mode owns the
/// last-operation card, the selection summary and the mesh row counts.
/// `mat-34d`'s own row gives scene mode `mat-24`'s own four panels —
/// sources, shadows, environment, post — all four together, the same
/// "wholesale, not piecemeal" rule every other mode already follows here.
///
/// **Animation mode owns one of four sections, picked by [animation] —
/// `ui-40d`'s own row.** `anim-07`'s own screen — the clip/skeleton panel
/// [PropertiesSection.animation] already named before this row — is what
/// [AnimationSubmode.pose] shows; [AnimationSubmode.weights] answers
/// [PropertiesSection.weightPaint], [AnimationSubmode.retarget] answers
/// [PropertiesSection.retarget], [AnimationSubmode.morphs] answers
/// [PropertiesSection.morphs]. [animation] left null answers the same as
/// [AnimationSubmode.pose] — every caller that predates this row read
/// `sectionsFor(ModelerMode.animation)` with one argument and got
/// `anim-07`'s own section back, and this keeps that true rather than
/// silently emptying the panel for whichever of them nothing has widened
/// yet to pass the sub-mode along.
Set<PropertiesSection> sectionsFor(
  ModelerMode mode, {
  AnimationSubmode? animation,
}) => <PropertiesSection>{
  PropertiesSection.display,
  PropertiesSection.view,
  PropertiesSection.budget,
  ...switch (mode) {
    ModelerMode.object => const <PropertiesSection>{
      PropertiesSection.objects,
      PropertiesSection.transform,
      PropertiesSection.modifiers,
      PropertiesSection.materials,
    },
    ModelerMode.mesh => const <PropertiesSection>{
      PropertiesSection.lastOperation,
      PropertiesSection.selection,
      PropertiesSection.mesh,
    },
    ModelerMode.animation => switch (animation ?? AnimationSubmode.pose) {
      AnimationSubmode.pose => const <PropertiesSection>{
        PropertiesSection.animation,
      },
      AnimationSubmode.weights => const <PropertiesSection>{
        PropertiesSection.weightPaint,
      },
      AnimationSubmode.retarget => const <PropertiesSection>{
        PropertiesSection.retarget,
      },
      AnimationSubmode.morphs => const <PropertiesSection>{
        PropertiesSection.morphs,
      },
    },
    ModelerMode.scene => const <PropertiesSection>{
      PropertiesSection.sceneSources,
      PropertiesSection.sceneShadows,
      PropertiesSection.sceneEnvironment,
      PropertiesSection.scenePost,
    },
    // **`ux-07`: Material mode is no longer empty.** It was enabled, it
    // switched, and it showed Display/View/Budget and nothing else — the
    // materials were edited in Object mode, with no hint and no link. The
    // live run's own finding, and the first minute of the application is
    // where it lands. The material list and the object it belongs to are
    // what a material workspace is built around, so both are here; the rest
    // of the workspace — the graph, the preview, the slots as their own
    // screen — is `ux-40`, and this is its first step rather than a
    // placeholder for it.
    // **`ux-40` finished it.** The list and the object it belongs to were
    // `ux-07`'s own first step out of an empty mode; what makes it a
    // workspace is the preview, the slots and the graph, which object mode
    // does not get and this one shows expanded rather than behind a dialog
    // and a disclosure triangle.
    ModelerMode.material => const <PropertiesSection>{
      PropertiesSection.objects,
      PropertiesSection.materials,
      PropertiesSection.materialWorkspace,
    },
    _ => const <PropertiesSection>{},
  },
};
