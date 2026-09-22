# Design handover: a 3D editor in Flutter

## What this is

A cross-platform editor for 3D shapes: importing the common formats, building
primitives and lathes, editing a mesh, materials, UV, animation, sculpting,
simulation, rendering and a game character pipeline. The renderer underneath is
**flutter3d**, this repository's own. Targets are the web, the desktop, a
tablet with a pen, and a phone. The interface is **Material 3**, read
minimally.

Written in Russian and translated here; the interface labels quoted below stay
in the original, with English beside them, because those are the strings the
mock-ups actually show. The application ships both languages
(`apps/flutter3d_modeler/lib/l10n/`).

## About the files in this archive

The files under `designs/` are **design references built as HTML**. They are
neither production code nor the application's sources: they show the intended
look, density and behaviour of the interface.

The job is to **rebuild these layouts in Flutter** with Material 3
(`ThemeData.useMaterial3`, `ColorScheme.fromSeed`, and the `NavigationRail`,
`SegmentedButton`, `Slider`, `BottomSheet` and `FilledButton` components), not
to carry the HTML across. Every size and colour below is in Flutter logical
pixels, where 1 CSS px is 1 lp.

To open the mock-ups: `designs/Экраны редактора.dc.html` in a browser. The
second file, `designs/План разработки 3D-редактора.dc.html`, is the
development plan — phases, risks, architecture.

## Fidelity

**High.** The colours, sizes, density and composition of the panels are final
and are to be reproduced exactly. The exception is what is inside the viewport
— models, skeletons, cloth — which is schematic filler; the real geometry is
drawn by flutter3d.

The page around the mock-ups (the serif face, the light background, the
captions) is the document's own wrapper and **not** part of the product. What
belongs to the application is the dark interface inside the rounded
rectangles.

---

## The Material 3 theme

A dark scheme. One accent across the whole editor.

| Role | Hex | Where |
| --- | --- | --- |
| `surfaceContainerLowest` | `#0B0E0F` | the window's background |
| `surface` (the viewport's dark half) | `#0E1112` | the scene's backing |
| `surfaceContainerLow` | `#131617` | the tool rail on the left, the status line |
| `surfaceContainer` | `#171A1B` | the top bar, the properties panel, the sheet |
| `surfaceContainerHigh` | `#1B1F20` | input fields, nodes, chips, floating panels |
| `surfaceContainerHighest` | `#262A2B` | the selected row of a list |
| `onSurface` | `#E1E3E3` | primary text |
| `onSurfaceVariant` | `#BFC8CA` | secondary text, inactive icons |
| `outline` | `#899295` | captions, incidental values |
| `outlineVariant` | `#3F484A` | dividers, slider tracks |
| `primary` | `#5FD4E4` | slider fill, selection in 3D, active icons |
| `primaryContainer` | `#004F58` | the active segment's background, the primary button |
| `onPrimaryContainer` | `#A2EEFF` | text and icons on `primaryContainer` |
| `secondary` (the second spot) | `#FF458E` | UV seams, the playhead, the brush cursor, bones with a problem |
| `error` / warning | `#FFB86B` (text `#FFD9B0`, background `#3A2118`) | budget warnings |
| success | `#7EE081` | "ready to export", filled budgets |

The viewport is a radial gradient:
`radial-gradient(120% 100% at 50% 0%, #1A1E1F 0%, #0E1112 70%)`. The floor
grid is `#2A3234` lines every 48 lp, laid in perspective at roughly 66°, at
0.35 to 0.55 opacity.

### Type

Roboto, at weights 400 and 500 only.

| Role | Size / weight | Where |
| --- | --- | --- |
| Panel heading | 14 / 500 | the file name, an operation card's title |
| Interface body | 13 / 400 | segments, list items, buttons |
| Values and fields | 12 / 400 | numeric fields, secondary rows |
| Section captions | 11 / 400, `letter-spacing: 0.08em`, UPPER CASE, `outline` | «ТРАНСФОРМАЦИЯ» (transform), «МОДИФИКАТОРЫ» (modifiers) |
| Status line | 11 / 400 | the bottom row |

### Metrics and shapes

| Quantity | Value |
| --- | --- |
| Top bar height | 52 |
| Tool rail width | 52; a button is 40 × 36 at radius 10 |
| Properties panel width | 250–330, typically 272 or 290 |
| Status line height | 30 |
| Window radius | 12 |
| Switch segment | height 30, radius 14, container radius 16, padding 2 |
| Pill button | padding 8 × 16, radius 16 |
| List row | padding 6–7 × 8, radius 8 |
| Numeric field | padding 6 × 8–10, radius 6 |
| Slider | track 4, `primary` fill, ⌀16 handle |
| Floating palette (tablet, sculpting) | radius 24, padding 8, button 48 × 48 at radius 16 |
| Bottom sheet | top corners at radius 24, a 32 × 4 handle at radius 2 in `outlineVariant` |
| Floating element shadow | `0 4px 16px rgba(0,0,0,0.4)` |

Icons are Material Symbols Outlined at weight 400: 20 in the rail and the top
bar, 16–18 in lists and fields, 22–24 on touch targets.

### Density

M3's compact density: a list row is 32, a rail button 36. The 48 touch target
is kept on touch platforms alone — tablet and phone — which are also where the
side panels give way to a floating palette and a sheet.

---

## The frame

One frame for every mode. Only its contents change.

```
┌─ top bar 52 ─────────────────────────────────────────────────┐
│ file name         [mode switch]          undo redo Export    │
├────┬──────────────────────────────────────────┬──────────────┤
│ 52 │  viewport (+ the mode's own lower area)  │  properties  │
│rail│                                          │  250–330     │
├────┴──────────────────────────────────────────┴──────────────┤
│ status line 30: metrics on the left, readiness on the right  │
└──────────────────────────────────────────────────────────────┘
```

**The frame's rules**

1. The mode switch is the top bar's one permanent element: `Объект` (object),
   `Меш` (mesh), `Материал` (material), `Анимация` (animation), `Сцена`
   (scene). Build it as a `SegmentedButton`.
2. A second segmented switch sits to its right and holds the current mode's
   sub-mode: the selection level; `Правка / UV / Ретопология` (edit, UV,
   retopology); `Поза / Веса / Ретаргет / Морфы` (pose, weights, retarget,
   morphs).
3. Panels do not accumulate. Changing mode replaces the rail's and the right
   panel's contents outright.
4. The status line is permanent: counts on the left, export readiness on the
   right — green `#7EE081` for fine, orange `#FFB86B` for a warning.
5. Colour belongs to the model. The chrome uses `primary` for an active state
   and `#FF458E` for the second layer of meaning — seams, the playhead,
   anything with a problem — and nothing else.

### Adapting

| Width class | Layout |
| --- | --- |
| Desktop (≥1200) | as drawn: rail on the left, properties on the right |
| Tablet (600–1199) | the viewport fills the screen; a floating palette on the left with 48 buttons; the mode switch centred at the top; properties in a sheet about 200 tall |
| Phone (<600) | a `NavigationBar` at the bottom (object, mesh, material, scene) in place of the switch; properties in a compact sheet above it; the primary action as a 56 × 56 FAB at radius 18 |

The set of tools is the same at every size.

---

## The screens

The numbering follows the captions in the mock-up.

### 01 · Object mode (phase 1)
The default. The rail: select, move, rotate, scale, a divider, primitives, the
lathe, booleans. The right panel, top to bottom: the scene's objects (icon and
name), the transform as a 3 × 3 grid (position, rotation, scale × XYZ, numeric
fields), the modifier stack (a row with a name and a visibility toggle, and an
«Добавить» (add) link).
The viewport: display-mode chips at the top left, a ⌀60 orientation gizmo at
the top right, a three-coloured manipulator on the object (X `#FF6B8A`,
Y `#7EE081`, Z `#6AA8FF`).
Status: `Треугольников N · вершин N · материалов N` (N triangles, N vertices,
N materials) and `Готово к экспорту в GLB` (ready to export as GLB).

### 02 · Mesh mode (phase 1)
The second switch is the selection level: vertices, edges, faces, as icons.
The right panel shows **the last operation's parameters** as a card on
`surfaceContainerHigh` at radius 12: a heading with a close cross, a
«Смещение» (offset) slider with a numeric field, checkboxes. Below it, a
summary of the selection — faces, perimeter, area.
The requirement this screen exists for: a value set with the mouse is
immediately editable as a number. A selected face is `#004F58` at 55% with a
`primary` outline at 2.5.
Status, on the right: `2 n-гона — проверьте перед экспортом` (2 n-gons, check
before export), in orange.

### 03 · Tablet (phase 1)
A floating tool palette on the left, the mode switch centred at the top, undo
and export at the top right (44 × 44, radius 14), a sheet 200 tall at the
bottom holding the transform in three columns.

### 04 · Phone (phase 1)
The status bar, a compact top row (back, name, menu), a FAB, a 130 sheet above
an 80 `NavigationBar`.

### 05 · Material (phase 2)
A viewport previewing the material, and under it a collapsible **node graph**
250 tall: nodes 170–210 wide at radius 10, a node's header in
`surfaceContainerHighest` — `primaryContainer` for the input and output nodes
— and Bézier links in `primary` at thickness 2.
The right panel: the object's materials with a colour dot each, the properties
(base colour with a 22 × 22 swatch and its hex, sliders for metalness,
roughness and opacity), and texture slots (26 × 26 preview, name, resolution).
Two levels of access: sliders for the simple case, the graph for the hard one,
collapsed by default.

### 06 · UV unwrapping (phase 4)
A split view: 3D with its seams on the left (`#FF458E`, thickness 3.5), the
400 × 400 unwrap square on a 32 checkerboard on the right, islands drawn as
polygons at 50% fill with a 2 outline.
An island's colour is its stretch: `primary` for fine, `#FF458E` for
stretched.
The right panel: the unwrap method as two chips, the margin between islands, an
auto-pack checkbox, and the islands with their stretch factors.
Status: `Заполнение развёртки N % · островов N` (unwrap fill N%, N islands).

### 07 · Animation (phase 3)
Under the viewport, a timeline 270 tall: a 44 transport row with a ⌀36 play
button on `primaryContainer`, the frame number and a `Ключи / Кривые` (keys,
curves) switch; below it a 180-wide column of bone names on the left and the
tracks on the right, keys drawn as 12 × 12 diamonds (`primary`, or grey
`#899295` when inactive), with the current frame as a 2 lp `#FF458E` line
carrying its number on a plate.
The right panel: the skeleton as a tree indented by level, the constraints, the
actions.
Status: `Костей N · действий N · вес влияний 4 на вершину` (N bones, N
actions, 4 influences a vertex).

### 08 · Sculpting (phase 4)
The one mode with no side panels: the viewport fills the screen, a floating
brush palette on the left, a parameters card on the right (radius 20, width
250), the mode switch above.
The brush cursor is a ⌀140 circle outlined in `primary` at 2 with a dot at its
centre.
The layout is the same on desktop and tablet — it is drawn for a pen.
Status: `Треугольников 1 240 000 · плотность 0,8 мм` (1,240,000 triangles,
0.8 mm density) and `Перед экспортом потребуется ретопология` (retopology
needed before export).

### 09 · Lathe (phase 1)
A modal screen 720 tall. On the left, a 520 profile editor on a 40 grid: the
axis of revolution as a `#FF458E` dashed line, the profile as a path filled
`#004F58` at 28% and outlined `primary` at 2.5, its points ⌀12 (a control
point is hollow). Three chips underneath: point, curve, axis.
On the right, a viewport showing the result, updated as the profile changes.
The right panel: segments, angle, checkboxes for smoothing and caps, and a
summary — vertices, triangles, height.
The profile stays editable after the shape is created, because the shape is
kept parametrically.

### 10 · Retopology and baking (phase 4)
The source mesh shows through the new one; a floating slider at the bottom left
controls how much. The new mesh is `primary` curves at 1.6; the active quad is
`#FF458E` at 22% fill with a 2 outline and ⌀9 corners.
The right panel is 290 wide in two blocks split by a line: automatic
retopology (the target quad count, checkboxes, a «Пересобрать сетку» (rebuild
mesh) button on `surfaceContainerHigh`) and map baking (the source-to-target
pair chosen automatically, the maps with checkboxes and a resolution, the cage
thickness, and a primary «Запечь N карты» (bake N maps) button).

### 11 · Simulation and physics (phase 4)
Physics is a property of an object. The right panel: the kind as chips —
`Ткань / Твёрдое тело / Частицы` (cloth, rigid body, particles) — the
material's parameters, the interactions (collisions, wind, pinned vertices),
and the accuracy.
Under the viewport, a strip 150 tall: the transport, a «Запечь симуляцию»
(bake simulation) button, and **the cache bar** — a 16 lp track at radius 8
with the solved frames filled `#004F58` and the current frame `#FF458E`.
Status: `Симуляций в сцене N · кэш N МБ` (N simulations, N MB cached) and
`Запечь перед экспортом в движок` (bake before exporting to an engine).

### 12 · Rendering and compositing (phase 4)
On the left, a 230 panel of passes (rows with a visibility icon) and the render
settings. In the middle, the render in a 760 × 428 frame with a progress
plate. At the bottom, a 260 compositing graph, its nodes built like screen 05's.
Editing a node recomputes only the branch it affects; the status line reports
how long that took.

### 13 · Weight painting (phase 3)
Weights colour the mesh through a gradient: 0 → `#2A3A7A`, 0.25 → `#4AA3FF`,
0.5 → `#7EE081`, 0.75 → `#FFB347`, 1 → `#FF3B5C`. The legend is a 140 × 8 bar
at the top right.
Under the viewport, a 74 strip: a bend slider for the selected bone
(`#FF458E`), so deformation can be checked without leaving the mode, and a
«Сбросить позу» (reset pose) button.
The right panel: the brush (radius, stroke weight, mirror and normalise
checkboxes), the selected vertex's influences (bone name, a mini track, the
value), and the bones with a vertex count each.
The influence limit comes from the project profile, and normalisation happens
on every stroke.

### 14 · Retargeting and the library (phase 3)
On the left, a 230 clip library: a search field at radius 18, cards with a
34 × 34 icon, a name and a duration. In the middle, two viewports side by side
— the source (a grey mocap skeleton) and the target (the character with its
skeleton lit). At the bottom, clip tracks 22 tall with a blend slider.
The right panel: the bone mapping as a table (`source → target`), unmapped rows
on `#3A2118` with an icon and `#FFB86B` text, a «Сопоставить автоматически»
(map automatically) link, a root motion block (`В анимации` / `Кодом` — in the
animation, or in code) and the corrections (fit to height, plant the feet).

### 15 · Morphs and facial animation (phase 3)
A 330 right panel: the shapes, each row a name (96), a slider, a value and **a
key dot** on the right — `radio_button_checked` `#FF458E` where a key exists,
`radio_button_unchecked` `#3F484A` where it does not. A key is set in the row
itself; there is no separate editor.
Below that, corrective shapes bound to a driving bone's angle, and shape sets
as chips.
In the viewport, the shape's points: `primary` for the ordinary ones,
`#FF458E` for the active one.

### 16 · Auto-rigging (phase 3)
A modal screen 720 tall. On the left, a silhouette with eight markers ⌀16
(hollow, outlined `primary` at 3; the active one solid `#FF458E`), with dashed
links between them for the chains to come.
On the right: the template (`Гуманоид / Четвероногое / Своё` — humanoid,
quadruped, custom), the composition (fingers and spine joints as small
two-state switches; checkboxes for IK and controllers), binding the mesh
(initial weights, symmetry), and a summary card: how many bones will be
created and how many of them deform.

### 17 · Levels of detail (phase 4)
Three viewports side by side captioned `LOD 0/1/2` with a triangle count each;
the geometry visibly simplifies left to right. Under them a 96 strip: a camera
distance slider whose track is split into three zones (`#004F58`, `primary`,
`#2C3A3D`) with the current distance marked `#FF458E`.
The right panel: a card per level (reduction percentage, triangles, distance
range), an «Добавить уровень» (add level) link, and the simplification
checkboxes — silhouette, UV borders, weight transfer.
Levels inherit the unwrap and the weights.

### 18 · 3D painting (phase 4)
Three areas: the viewport with its brush cursor (⌀96, outlined `#FF458E`), a
300 unwrap panel holding a 240 × 240 canvas where the stroke appears at the
same time, and a 290 right panel.
The right panel: the layers (visibility, name, blend mode and opacity), a
palette of four 32 × 32 swatches with the active one outlined
(`outline: 2px solid primary; offset: 2px`), the brush radius and opacity, and
masks by curvature and occlusion, which come from screen 10's maps.

### 19 · In-game preview (phase 3)
The viewport under game lighting (a `#243440 → #0F181D` gradient). A metrics
overlay at the top left on `rgba(11,14,15,0.72)`: frames a second, draw calls,
triangles in the frame, bones.
A floating control panel at the bottom centre: pause, clip segments, looping.
A 330 right panel: **the profile's budgets** as four rows with a 5 lp fill bar
each (green within, orange over), a warning card on `#3A2118`, and the scene's
conditions (lighting, runtime shadows, texture compression, the cage).
This is the last check before export: the runtime is the one the game runs.

---

## Behaviour

- **Changing mode** replaces the rail's and the right panel's contents
  outright; the selection and the camera are kept. Nothing about the contents
  animates — only the segment indicator does (M3, 200 ms,
  `easeInOutCubicEmphasized`).
- **A mouse operation becomes an editable number.** Any interactive operation
  — an extrusion, a bevel, a move — leaves a parameters card in the right panel
  once it finishes. Changing a value recomputes the result immediately, with
  nothing to confirm.
- **History.** Every edit goes through a command, which is what undo, redo and
  autosave are built on — and what collaborative editing would be built on
  later.
- **Heavy operations** — booleans, retopology, baking, simulation, rendering —
  run in an isolate. The interface does not block, and the progress appears
  where the button that started it was.
- **Export checks are continuous**: the status line is recomputed after every
  edit. Orange warns rather than blocks.
- **The project profile** — bone, influence and triangle limits, texture
  weights — is set once and read by every screen: the status lines, the
  preview's budgets, the weight normalisation limit.
- **The pen**: pressure drives brush strength in sculpting and painting; a
  finger only moves the camera, so a resting palm cannot draw.

## State

The smallest set that holds the interface up:

- `document` — the scene, its objects and hierarchy, materials, skeletons,
  animations; versioned by a queue of commands (`undoStack`, `redoStack`).
- `selection` — the mode (`object | mesh | material | animation | scene`), the
  sub-mode, the selected objects, the element level (vertex, edge, face) and
  the selected elements.
- `activeOperation` — the last operation's parameters, for the card in the
  right panel.
- `viewport` — the camera, the display mode, which overlays are shown (grid,
  gizmo, wireframe).
- `playback` — the current frame, the range, whether it is playing, the active
  clip, the blend.
- `projectProfile` — the target engine and its budgets; the input every check
  reads.
- `jobs` — the background work in flight (baking, simulation, rendering) with
  its progress.

## Resources

Icons are Material Symbols Outlined at weight 400, pulled from Google Fonts in
the mock-up; in Flutter use `Icons` / `Symbols`. Roboto is Material 3's own
face. The mock-ups carry no images of their own: everything is shapes and
gradients standing in for what flutter3d draws.

## Files

```
designs/
  Экраны редактора.dc.html             19 screens, the main reference
  План разработки 3D-редактора.dc.html  phases, architecture, risks, open questions
  support.js, doc-page.js              needed to open the mock-ups
  _ds/…/styles.css, _ds_bundle.js      the document page's own styling, not the product's
```

## What the mock-ups do not cover

The import screen with its checks and mesh cleanup, and the export dialog with
its checks, are not drawn yet. The development plan puts both in phase 1, so
both have to be designed before that phase starts.
