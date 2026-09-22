# Handover addendum: what changed on 11 September 2026

Read alongside `README.md`, which still holds. The theme, the metrics, the
density, the frame and the behaviour did not change. What follows is only what
was added or changed after the mock-ups were checked against the plan's actual
status (`model-editor-functions.md`).

Interface labels stay in the original Russian with English beside them, for
the reason `README.md` gives: those are the strings the mock-ups show.

## Files

```
designs/
  Экраны редактора.dc.html              the 19 main screens (01–19); 01, 02 and 05 edited
  Экраны редактора — дополнение.dc.html 8 new screens (20–27)
  План разработки 3D-редактора.dc.html  phase status added, two new tracks, §7 rewritten
  support.js, doc-page.js, _ds/…        needed to open the mock-ups
model-editor-functions.md               the functionality overview the design was checked against
```

## Edits to the existing screens

**01 · Object.** A second row of chips in the viewport: the pivot
(`Медиана` / `Себя` / `Курсор` — median, individual origins, cursor) and the
space (`Глобальное` / `Локальное` — global, local), with the 3D cursor's
coordinates beside them. The cursor itself is drawn in the scene: a ⌀20 circle
outlined `#FF458E` at 2 lp with a 40 lp crosshair. Shift and a right click
place it. The chips are segmented switches 26 tall at radius 14.

**02 · Mesh.** Three additions.

- *Modal transforms.* A plate at the bottom centre of the viewport: the
  operation with its icon, the active axis in that axis's colour
  (`X — #FF6B8A`), the value in a `surfaceContainerHighest` field with a
  caret, and the unit. Radius 16, padding 10 × 16, shadow
  `0 4px 16px rgba(0,0,0,0.4)`. Under it a row of hints at 11 / 400 on
  `rgba(11,14,15,0.72)`: type a number, Shift, Ctrl, Esc.
  The plate lives only while the operation does; when it finishes the
  parameters move into the last-operation card on the right. An axis
  constraint draws as a line across the whole scene in that axis's colour.
- *Snapping.* Two chips at the top right: what to snap to
  (`вершина` / `ребро` / `грань` / `шаг` — vertex, edge, face, increment) and
  the increment itself. The active mode's text is `onPrimaryContainer`.
- *Diagnosis and repair.* A new block in the right panel below the selection
  summary: four rows — n-gons, open boundaries, non-manifold edges, degenerate
  faces — each with a count and an arrow that jumps to the first one; rows with
  a problem on `#3A2118`, clean ones on `surfaceContainerHigh` with a green
  tick. Pill buttons underneath: fill holes, triangulate n-gons, make normals
  consistent, split non-manifold edges. A repair is a command and goes into
  the history.

**05 · Material.** The node graph panel is collapsed to a 44 strip (icon,
heading, a «свёрнут» (collapsed) caption, a chevron), and the space it gave up
goes to the preview. The expanded state returns with the texture compositor.
The texture slots gained a compression format and a weight beside the
resolution, and a row for the alpha mode — what is read out of the file's own
header and checked on export.

**The status line.** Screens 01, 02 and 05 gained texel density (`текс/см`,
texels per centimetre) and texture weight against the profile's budget. The
rule is unchanged: counts on the left, readiness on the right.

## The new screens

| № | Screen | Phase | The point of it |
| --- | --- | --- | --- |
| 20 | Start, drag and drop, recovery | 1 | Recent files, four cards to create from, a 440 drop zone dashed in `primary`, a draft recovery bar on `#3A2118` |
| 21 | Import: the report and the limits | 1 | A 1180 × 720 modal: a preview with the bounding size, what the file contains, units and up axis, mesh preparation, the decoder's report. Beside it a card for merging into the open project, placing several assets |
| 22 | Export with checks | 1 | A 1080 × 720 modal: format, profile, contents; on the right the checks with a «Показать» (show) link and four budget bars. A warning does not block — the button's label changes |
| 23 | Sockets and attachment points | 1 | A socket is an object with no geometry: an axis cross with a label, a parent bone, an offset, a preview of what attaches. They leave as empty nodes in glTF |
| 24 | The whole modifier stack | 2 | A 330 panel: a drag handle, two toggles (viewport, export), one modifier expanded, a warning inside its row, an in → out count and the time it took |
| 25 | Profile: budgets and texel density | 2 | Three presets, the geometry limits, what a mesh must satisfy, the target density with its tolerance; on the right the texture budget by file and the measured density by object |
| 26 | An agent's session | 2 | The tool calls as a feed, a history with `Вы` / `Агент` (you, agent) badges where only the agent's own steps can be undone, a contact sheet of six angles under the viewport, chips for what to show |
| 27 | The keyboard reference | 1 | A 1080 × 720 overlay on `?`, three keymaps, four groups of bindings. The table is built from the same tool descriptions that feed the rail |

No new colours or metrics were introduced. The one new shape is the key cap in
the reference: `surfaceContainerHigh`, radius 6, padding 3 × 8, text
`onSurface`.

## Left undrawn on purpose

- The expanded material graph and the texture compositor — they arrive with
  their implementation.
- Phase 4 screens beyond those already drawn (06, 08, 10, 11, 12, 17, 18) —
  until the phase's scope is settled.
- A `render` panel for the agent as a screen of its own: the contact sheet on
  screen 26 shows what the agent gets, and that is enough to build the tool
  against.

## One open question the mock-up shows

The modifier stack on screen 24 draws **two** toggles a row — in the viewport
and on export. The plan leaves the choice between one flag and two open
(group Ж, §8). If it goes to one, the row loses its right-hand toggle and
nothing else changes.
