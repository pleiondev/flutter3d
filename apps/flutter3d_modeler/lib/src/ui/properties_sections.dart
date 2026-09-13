/// Which of the properties panel's own sections belong to which mode —
/// `ui-04`'s own "content is replaced wholesale," pulled out where it can be
/// tested directly.
///
/// `_Properties` (`main.dart`) is private to that library and nothing in
/// this app's own test suite pumps the whole screen, so the mapping this
/// file owns is what stands in for a widget test of `_Properties` itself —
/// a pure function, checkable without a `WidgetTester` at all.
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
  lastOperation,
  selection,
  mesh,
  budget,
}

/// Every section [mode] shows.
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
/// last-operation card, the selection summary and the mesh row counts. A
/// mode with no sections of its own yet (animation, scene — not built this
/// phase) gets only the cross-mode ones.
Set<PropertiesSection> sectionsFor(ModelerMode mode) => <PropertiesSection>{
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
    _ => const <PropertiesSection>{},
  },
};
