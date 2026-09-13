# edu-00: the interactive format

Written 2026-09-12, as a format — ahead of any authoring code (`edu-01`)
or playback code (`wg-01`). Serves all four segments from
[doc/lesson-scenarios-plan.md](lesson-scenarios-plan.md) — games,
education, industry, VR/XR — through one document, not four format
versions, one per segment.

## 1. Decision: there is no second scene format

An interactive is just a few more entity types (`EntityDef`) in the same
`Level` document (`packages/flutter3d_sim/lib/src/level/level.dart`)
already read by the game, the editor and the MCP servers — not a separate
`.json` with its own schema, not a new node in the package tree.

This is not a shortcut for simplicity — it is how the format was already
built, to accept a new type for free. `EntityDef` is "one typed field plus
a bag of properties," deliberately with no visible class per kind (see the
class's own doc comment); the editor validates geometry, materials and
light, but its **entity-type list is open**, not a closed registry:

```dart
// packages/flutter3d_editor_core/lib/src/vocabulary.dart
final class OpenKind extends EntityKind {
  const OpenKind(super.type);
}

EntityRegistry vocabularyOf(Level level) => EntityRegistry(<EntityKind>[
  for (final type in level.entities.map((EntityDef e) => e.type).toSet())
    OpenKind(type),
]);
```

Meaning: the document below opens, saves and passes editor validation
today, with no edit to `flutter3d_editor_core` at all — a new entity type
turns into an `OpenKind` automatically, and this is confirmed by an actual
run of `Level.fromJson` + `vocabularyOf` on the example in §11, not just
assumed (§12). `edu-01` writes an authoring panel on top of this;
`edu-00` is only the property vocabulary that panel will read and write.

The format is additive under the same rule already stated in
`Level.formatVersion`'s own doc comment: the version moves when the
*meaning* of an existing field changes, not when a new one appears.
Nothing in `edu-00` changes the meaning of `brushes`/`entities`/`lights` —
it only adds entities with new `type` values. `formatVersion` does not
move.

## 2. Properties sit flat, with no `"properties"` wrapper

**An important format detail found by checking the example, not guessed
in advance.** `EntityDef.fromJson` does not read a nested `properties`
object — it takes the whole entity JSON and puts everything outside the
four reserved keys (`type`, `at`, `yaw`, `name`) into the `properties`
bag. The key `properties` inside the document itself is not reserved at
all: if the step below had been written as `{"type": "edu_step", ...,
"properties": {"caption": "..."}}`, the whole contents would have landed
in `entity.properties['properties']` as one nested object, not in
`entity.properties['caption']`. The real format is flat, like any
existing level entity (`door` carries `size`/`travel`/`speed`/`wait`
directly alongside `type`/`at`/`name`, not under a separate key), and
`edu_step` follows the same shape:

```json
{
  "type": "edu_step",
  "name": "step-2",
  "at": [1.2, 1.6, -0.4],
  "yaw": 2.1,
  "caption": "Removing the valve cover",
  "offsets": {"engine-body#valve_cover": [0.0, 0.35, 0.0]}
}
```

Every field below (`caption`, `visible`, `offsets`, `annotations`, ...) is
a key directly on the entity, not under `properties`.

## 3. Naming — snake_case, the same style as the rest of the format

Existing levels name types in `snake_case`
(`player_spawn`, `reflection_probe`, `door`) — not `camelCase`. New types
follow the same convention: `edu_sequence`, `edu_step`, `edu_annotation`,
`edu_clip_plane`, `edu_data_source`.

References between entities go by `EntityDef.name`, the same technique
already at work: "the door that a button opens" today names the button by
name in its own properties; a step that highlights a part names it by
name exactly the same way.

## 4. `edu_sequence` — the order of steps

One per document (or one per self-contained interactive inside a
document — nothing forbids a second `edu_sequence` for a second,
independent lesson in the same scene, but the first implementation need
not support that).

```json
{
  "type": "edu_sequence",
  "name": "engine-teardown",
  "title": "Engine teardown",
  "steps": ["step-1", "step-2", "step-3", "step-4", "step-5"]
}
```

`steps` is an array of `edu_step` entity names, in playback order. The
document sets the order, not a sort by name or by position in the
`entities` array — the same decision `Level.next` already made for moving
between levels (an explicit field, not a guessed order).

## 5. `edu_step` — a single step

```json
{
  "type": "edu_step",
  "name": "step-2",
  "at": [1.2, 1.6, -0.4],
  "yaw": 2.1,
  "caption": "Removing the valve cover",
  "visible": ["engine-body", "valve-cover"],
  "hidden": ["cylinder-head"],
  "highlight": ["valve-cover"],
  "offsets": {"engine-body#valve_cover": [0.0, 0.35, 0.0]},
  "annotations": ["step-2-note"],
  "clip": null,
  "bindings": [],
  "check": null
}
```

Fields a step already inherits from `EntityDef` for free:

- **Camera** — `at`/`yaw`, the same two fields any entity carries today.
  There is no separate nested camera object: the step itself is a point in
  space with a direction, and that is exactly what a camera position
  should be. A host reads `at` as the eye position and `yaw` as rotation
  around Y (pitch is not in the format yet — no entity in the engine tilts
  today, see `EntityDef.yaw`'s own doc comment: "Nothing in this game
  tilts"; if a teardown ever needs a top-down look, that is a separate
  decision, not part of `edu-00`).

Fields specific to a step:

| Field | Type | Meaning |
|---|---|---|
| `caption` | string | The step's text — what the step panel shows |
| `visible` | `[name]` | Entities/nodes visible on this step |
| `hidden` | `[name]` | Entities/nodes hidden on this step |
| `highlight` | `[name]` | A highlight — visual emphasis with no visibility change |
| `offsets` | `{path: [x,y,z]}` | Layer-by-layer disassembly — §6 |
| `annotations` | `[name]` | Names of `edu_annotation` entities active on this step |
| `clip` | name or `null` | Name of the `edu_clip_plane` entity active on this step |
| `bindings` | `[{...}]` | Property-to-data bindings active on this step — §7 |
| `check` | object or `null` | A checked question — §8 |

`visible`/`hidden` name either a whole entity's name or `name#node` (the
same path syntax as `offsets` — see §6) — so a step can hide a single
model node without touching the rest of the entity.

A host is not required to store state between steps as a diff: each step
carries the **full** state of everything it touches (the whole visible
list, the whole set of offsets), not "plus the previous one." This makes
a step reproducible on its own — a property already required of
`rp-02`/`ai-01` from a game run (scrubbing to a step without replaying
every earlier one), and `edu-04`'s "reproducible on a weak laptop"
requires the same thing for a lesson.

## 6. Layer-by-layer disassembly — `offsets` and node addressing

The model being disassembled arrives in the scene as an ordinary entity
(`type: "model"`, or whatever name the genre gives it — the format does
not decide this for the host) referencing an `.f3d`/glTF asset. Nodes
inside the model are already named (`ModelNode.name`,
`packages/flutter3d_formats/lib/src/model_node.dart`) — the same
mechanism a model already uses to name any of its parts today, well
before any lesson.

The path `"engine-body#valve_cover"` is an entity name, a `#`, and a node
name inside that entity's model. The value is an offset in meters,
**relative to the node's original pose**, not an absolute coordinate: a
node with offset `[0, 0, 0]` or with no entry in `offsets` sits wherever
it sits in the model itself.

Interpolating between neighboring steps (a part smoothly pulling away
rather than teleporting) is a decision for the playback host
(`wg-01`/the scene engine), not the format: the format names the target
offset at a step, not the trajectory between steps. A host is free to
animate the transition or switch instantly — the same split of
responsibility as between `Level` (what) and the renderer (how).

## 7. An annotation as a widget — `edu_annotation`

```json
{
  "type": "edu_annotation",
  "name": "step-2-note",
  "widget": "torque-spec-card",
  "attachTo": "engine-body#valve_cover",
  "offset": [0.1, 0.1, 0.0]
}
```

`widget` is a name from the application's own registry — the same
registry `wg-01`'s own "the level document references a widget by name
from the application's registry" already refers to. `edu-00` does not
invent a second way to name a widget: an annotation is a `WidgetSurface`
positioned relative to a node (`attachTo` + `offset`), not a new
primitive.

Before `wg-01`, a `widget` reference renders nothing — a host with no
`WidgetSurface` reads `edu_annotation` as data (what it would show, if it
could) and is not required to be able to draw it. The format does not
wait for `wg-01` to be readable; it waits for `wg-01` for the annotation
to appear on screen.

## 8. A cross-section — `edu_clip_plane`

```json
{
  "type": "edu_clip_plane",
  "name": "cutaway-1",
  "at": [0.0, 1.0, 0.0],
  "normal": [0.0, 0.0, 1.0]
}
```

A clipping plane: a point (`at`, inherited from `EntityDef`) and a normal.
Geometry on one side of the plane is not drawn while a step's `clip`
names this entity. The format names only the plane — the clipping pass
itself (a shader, a separate cross-section material) is a decision for the
engine implementation, outside `edu-00`; the ROADMAP does not give it a
separate ticket, only assumes the cross-section exists by the time
`edu-01` lands.

## 9. A property-to-data binding — `edu_data_source` and `bindings`

```json
{
  "type": "edu_data_source",
  "name": "lathe-broker",
  "kind": "mqtt",
  "topic": "factory/lathe-3/telemetry"
}
```

`kind` is `mqtt`, `websocket`, or `sampler` (the last is a synthetic
source for demos and tests with no real broker, required so that
`edu-05`/`ls-i-00` are reproducible with no network). The format names
the source, not the transport: exactly how `edu-05` connects to MQTT is a
decision for `edu-05`'s own code, not the format's.

A binding inside a step (the value of the `bindings` field):

```json
"bindings": [
  {"source": "lathe-broker", "path": "temperature", "target": "lathe-body.material.emissiveColor"}
]
```

`path` is a path inside the source's JSON payload (`temperature`,
`sensors.spindle.rpm` — dot notation, one level deeper than
`EntityDef.vector`/`.number` already read their own properties). `target`
is an `entity.property-path` decided by the host (for a material property
that is `material.field`, for a transform it is `at`/`yaw`).

**Why a binding is part of a step, not a document-wide property.**
`ls-i-00`'s own acceptance requires that "what if" create a visible branch
from the current step rather than rewriting history — meaning a binding
must be part of the step's own state, tied to the input tape, exactly the
way `rp-02`/`ai-01` already read simulation state step by step. A value
from the source, once read, becomes an **input** for that tape step — the
same way joystick input becomes an input for `GameSimulation` — which is
why the twin scrubs and branches the way a game does, not as a separate
live stream with no history.

## 10. A checked question — `check`

```json
"check": {
  "question": "What torque does the valve cover use?",
  "answers": ["80 Nm", "80 nm", "80"],
  "attempts": 3
}
```

`answers` is a list of accepted answers as text (case- and
extra-whitespace-insensitive comparison is a host decision, not a format
one, but listing several spellings in the document itself, as in the
example above, removes most of the problem at the content level).
`attempts` is how many tries a host gives before showing the answer. The
format does not decide where the result goes: locally (`ls-e-02` — "the
result is visible to the instructor") or out through LTI/xAPI (`ls-e-03`,
`edu-03`) — both read the same `check` field, the difference is what the
host does with the result.

## 11. An example — three full steps of an engine teardown

```json
{
  "name": "engine-lesson",
  "entities": [
    {"type": "model", "name": "engine-body", "at": [0, 0, 0],
     "asset": "assets/models/engine.f3d"},
    {"type": "edu_sequence", "name": "engine-teardown",
     "title": "Engine teardown",
     "steps": ["step-1", "step-2", "step-3"]},
    {"type": "edu_step", "name": "step-1", "at": [2, 1.5, 2], "yaw": 2.4,
     "caption": "The assembled engine",
     "visible": ["engine-body"], "highlight": []},
    {"type": "edu_step", "name": "step-2", "at": [1.2, 1.6, -0.4], "yaw": 2.1,
     "caption": "Removing the valve cover",
     "highlight": ["step-2-note"],
     "offsets": {"engine-body#valve_cover": [0, 0.35, 0]},
     "annotations": ["step-2-note"]},
    {"type": "edu_annotation", "name": "step-2-note",
     "widget": "torque-spec-card",
     "attachTo": "engine-body#valve_cover",
     "offset": [0.1, 0.1, 0]},
    {"type": "edu_step", "name": "step-3", "at": [1.2, 1.6, -0.4], "yaw": 2.1,
     "caption": "The cover's torque spec",
     "check": {"question": "What torque does it use?",
               "answers": ["80 Nm", "80 nm", "80"],
               "attempts": 3}}
  ]
}
```

Checked by an actual run, not just by eye: `Level.fromJson` reads all six
entities with no exceptions; `vocabularyOf(level).knows(type)` is true for
each of the five new `type` values, with not one edit to
`flutter3d_editor_core`; `Level.toJson()` followed by a fresh
`Level.fromJson()` preserves `offsets`, `steps`, `widget`/`attachTo` and
`check.attempts` unchanged — exactly the path on which §2's earlier
version of this document (with a nested `properties`) silently broke (the
whole object landed in one `properties` field, rather than in its own
fields), until exactly this kind of run caught it.

## 12. What already works for free, and what waits on code

**Free, with today's tree:**
- a document with `edu_sequence`/`edu_step`/`edu_annotation`/
  `edu_clip_plane`/`edu_data_source` opens through `Level.fromJson`, saves
  through `Level.toJson`, passes `flutter3d_editor_core` validation — not
  one line of edit, `OpenKind` accepts any `type` it has not seen before;
- `EntityDef.name`, `.at`/`.yaw`, the flat property bag already carry
  everything described above — not one new field on `EntityDef` itself.

**Waits on code, explicitly outside `edu-00`:**
- drawing, highlighting, clipping by `edu_clip_plane`, interpolating
  `offsets` between steps — all of the visualization is outside the
  format;
- an authoring panel that writes these entities by dragging, not by hand
  in JSON — `edu-01`;
- `WidgetSurface`, without which `edu_annotation.widget` does not draw —
  `wg-01`;
- a real MQTT/WebSocket connection behind `edu_data_source` — `edu-05`;
- scrubbing and branching the tape that `bindings` write a value into as
  an input — `edu-04`/`rp-02`;
- LTI/xAPI export of a `check` result — `edu-03`.

## 13. What this document does not close

`edu-00`'s acceptance in `doc/tooling-plan.md` is "the document has been
read by two people with different backgrounds (an instructor, an
engineer), and their notes have been folded in." That is a live-review
step, one this session cannot perform on its own: there is no second
person here, let alone one with an instructor's or a plant engineer's
background, whose note could honestly be folded in. The document above is
what gets offered for that review, not confirmation that the review
happened. Until that is done, `edu-00` is not formally closed by its own
acceptance criterion — it is ready to read, not read.

Checked separately by running code (this is something this session could
and did do on its own): the example in §11 is a valid document matching
the real `Level`/`EntityDef` format, including the §2 finding about the
missing `properties` wrapper, caught by an actual code run, not by
reading a doc comment.
