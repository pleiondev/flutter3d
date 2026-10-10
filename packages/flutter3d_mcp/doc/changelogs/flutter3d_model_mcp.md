## 1.0.0-rc.1

- **Breaking: one suffix for settings, Settings, and Descriptor in the
  HAL.** `ImportOptions` is `ImportSettings`. Every settings class is
  `final` with a `const` constructor and a `copyWith` over every field; a
  nullable field is reset with `copyWith(clearX: true)`. `dart fix` carries
  the renames.
- **Breaking: `ModelSession.makeGameReady` is `prepareForGame`.** The MCP
  tool keeps its name; `dart fix` carries the Dart call.
- **Tools are named `area.verb`, and the old names still answer.**
  `object.addPrimitive`, `mesh.extrude`, `selection.facing`,
  `material.setField`: `modelToolNames` lists every one with what it does to
  the project, and the command names (`addPrimitive`, `extrude`), which
  `history.batch` still takes inside its list, stay aliases until 2.0. The
  server announces itself as `flutter3d.model`, schema 1.1.0.
- **Every tool declares the shape of its structured answer.**
  `modelAnswerSchema` (`did`, `says`, `ids`, `selection`) is each tool's
  `outputSchema`, so a host can validate what it reads.
- **Breaking:** tools are `ToolSpec`s and answers `ToolResult`s (see
  `flutter3d_mcp_kit`); this package re-exports them, so a host adding its
  own tools needs no import of the MCP library.
- **1.0.0 is a promise: strict semver from there.** This release candidate
  already keeps it. A patch fixes bugs and
  breaks nothing, a minor adds, and a break waits for a major. The whole
  public API is stable, with no experimental exceptions, and is held to the
  snapshot in `api/`. A deprecated name stays until the next major and for
  at least six months, and says what replaces it.
  [CONTRIBUTING.md](https://github.com/pleiondev/flutter3d/blob/main/CONTRIBUTING.md#the-api-is-a-snapshot)
  has the rules, and
  [SUPPORT.md](https://github.com/pleiondev/flutter3d/blob/main/SUPPORT.md)
  says which releases get fixes and on which platforms.

- **The modeller's server takes the project's tools.**
  `serveModelMcp(arguments, projectTools:)` is what `bin/model_mcp.dart`
  runs, and a project's own `bin/` passes the registry its plugins filled.

- **The project's plugin tools are offered beside the server's own.**
  `ModelMcpServer` takes an optional `projectTools`, the project's
  `McpTools` from `flutter3d_mcp_kit`, and `onProjectCall` to watch calls
  to them. Each plugin tool is listed as `<plugin id>.<name>` after the
  server's own and after `extraTools`, and the list follows plugins as they
  are switched on and off. A server built without it offers exactly what
  `api/flutter3d_model_mcp.mcp` lists, so the schema version does not move.
  An addition.

- **The tools are a contract too.** Their names and input schemas — as the
  server offers them, with the target arguments every selection command
  gains — are written down in `api/flutter3d_model_mcp.mcp` and held to the
  same semver as the Dart API: a tool removed or renamed without an alias,
  or a new required argument, waits for a major. The server announces
  `modelMcpSchemaVersion` (1.0.0) as `schemaVersion` in its `initialize`
  result, and it moves only when the tools do; tools a GUI host adds through
  `extraTools` are the host's and not part of it.
  [CONTRIBUTING.md](https://github.com/pleiondev/flutter3d/blob/main/CONTRIBUTING.md#tools-for-agents-are-a-contract-too)
  has the rules.

**`setAnimationGraph` and `removeAnimationGraph`.** An agent sets a
character's graph by name over the project's clips, with the whole shape
described in the tool, and is told where a wrong one is wrong.

Its `flutter3d_*` dependencies ask for `^1.0.0`.

## 0.8.1

**`ModelSession.rebind` points a session at the document now on screen.** A
host that opens a file or starts a new project installs a new
`ModelHistory`; a session left on the old one edited a document nobody could
see or save, and every call reported success. `rebind` attaches the recovery
journal to the new history and forgets the export cache, since ids start
again. Nothing an agent calls can swap the document: the host does.

## 0.8.0

**`audit` checks an asset that came from somewhere else.** It answers with
`flutter3d_model_core`'s `AssetAudit` in words (overall size, origin against
the middle of the base, duplicate materials, what rebuilding each imported
mesh would drop or split, and every `check` issue with the triangle and
texture budgets) and a 4x2 sheet of all seven views, the underside included.
`repair: true` rebuilds the imported meshes, moves the base onto the origin,
bakes transforms, sets origins and runs `makeGameReady` for `profile`
(`desktop` by default), all as one undo step, and answers with the audit
before, what it did and the audit after. Units and duplicate materials are
reported and left to the person.

**`import` passes on what the reader said.** A skipped primitive or an
undefined material used to be dropped from the answer; the reader's own
warnings now follow the object count.

**`poseJoint` no longer offers `pointer`.** `AnimationPath` gained the path
for animation pointers, and the command refuses it as it refuses `weights`, so
the schema leaves both out.

`modelMcpVersion` is `'0.8.0'`.

Its `flutter3d_*` dependencies ask for `^0.8.0`.

## 0.7.1

**Released with the rest of the stack at 0.7.1.** Nothing in this package
changed. The release it resolves against builds from pub.dev again and no
longer crashes Metal on the first unlit draw.

Its `flutter3d_*` dependencies ask for `^0.7.1`, and it asks for `vector_math` ^2.4.3.

## 0.7.0

**The first publication.** The 0.6.0 below was a number carried inside the
workspace and never reached pub.dev. 0.7.0 is the number the whole shelf goes
out on, so that one number names one tree and `^0.7.0` on any `flutter3d_*`
package resolves against every other; `doc/boundary-0.7.0.md` lists the
thirteen packages that begin here. The server 0.6.0 describes offered 48
tools. This one offers 150: 18 on the session, 114 model commands, 15 for the
rig pipeline and 3 that render. None of the 48 was removed or renamed.

**Breaking for code built on the server's types.** `ModelMcpServer` extends
`flutter3d_mcp_kit`'s `ToolTableServer<ModelSession, PictureAnswer>` where it
extended `MCPServer with ToolsSupport`. `ModelTool` is a typedef of
`OfferedTool<ModelSession, Answer>` and its `run` may return a `Future`;
`Answer` is the kit's record, re-exported under the same name.

**Breaking for an agent in three places.** An argument the tool does not
take, an enum value it does not have, a wrong type or a vector of the wrong
length is refused in a sentence before the tool runs, where it used to be
ignored. `undo` refuses when the step on top is a person's. `select` is a
journaled `SelectElements` command and so a step in the history. Every
numeric field's description states its unit, and a removal that shifts
indices says so.

**`export` writes `.glb`, `.stl` and `.usdz` beside `.f3d` and `.obj`.** The
format is looked up among `flutter3d_core`'s `builtInModelWriters`. `.gltf`
with a separate `.bin` is still refused by name and points at `.glb`. A GLB
leaves out skins, animations and morph targets. The `ExportReadiness` gate and
`force` are unchanged, and a `ProjectModelDocument` kept across calls means a
second export converts only the objects that changed.

**`import` merges, and takes options.** It goes through `importInto`:
materials and images are deduplicated by content, the hierarchy is kept and
the whole import is one undo step. `unit` of `mm`, `cm` or `m`, `upAxis`,
`weld`, `fixNormals` and `triangulate` are new arguments that default to what
0.6.0 did. An FBX is recognised and refused with the reason. An import is not
written to the recovery journal. `linkToSource`, `unlinkSource` and `reimport`
keep an object tied to the file it came from.

**Three tools draw, on the software rasteriser.** `render` takes one of seven
views, a `mode` of `material`, `normals`, `selection`, `weights` or
`wireframe`, and a `size` from 128 to 1024. `renderSheet` is front, right, top
and iso on one labelled sheet. `renderSnapshot` takes `width` and `height`
from 64 to 4096, `ssaa` of 1 or 2 and `tiles` from 1 to 8, and spreads the
tiles over `Platform.numberOfProcessors` isolates; one measured snapshot went
from 3283 ms to 993 ms on eight workers. All three use `flutter3d_cpu`'s
`CpuDevice`, need no GPU or display, draw with the project's own lighting,
pose and shape weights, and answer a PNG as MCP image content.

**An agent can read what it is editing.** `describe` lists an object's
elements, the first 50 unless `limit` or `elements` says otherwise.
`selectFacing` and `selectNear` select by direction and by position. `list`
rows carry parent, place, version, materials and counts. `describe_type`
answers the fields of a `modifier`, a `shape` or a `textureNode`. Every
result carries `structuredContent` with `did`, `says`, the `ids` the call
created and the `selection` afterwards.

**A command can name its target, and several can be one step.** A command
tool whose schema has no `id` or `index` accepts `object` with `faces`,
`edges` or `vertices`, or `ids`, and the selection is put back afterwards.
`batch` is all or nothing and one undo step, with a rollback marker in the
journal. `amend` replaces the step on top. The recipes `cleanup`, `buildFrom`,
`inspect` and `makeGameReady`, the last with a profile of `desktop`, `mobile`
or `web`, each run as one step.

**Modelling and the modifier stack.** New tools: `addSocket`, `fillHoles`,
`bevelEdges`, `insetFaces`, `bridgeLoops`, `slideEdges`, `markSeam`, `unwrap`,
`subdivideMesh`, `drawQuad`, `retopologize`, `buildTopology`,
`setObjectVisible` and `setObjectLocked`; and `addModifier`,
`setModifierField`, `toggleModifier`, `toggleModifierExport`,
`reorderModifier`, `removeModifier`, `applyModifier` and `applyJobResult`.
`sculptStroke` takes a whole polyline as one command and one undo step.

**Materials, texture graphs and paint.** `listMaterials`, `linkMaterialFile`,
`embedMaterial`, `setMaterialGraph`, `bakeTextureGraph`, the six node tools
`addNode`, `link`, `unlink`, `setNodeField`, `moveNode` and `removeNode`,
`bakeMaps`, `paintStroke`, `adoptTexture`, `paintVertexColour`, `packAtlas`
and `setProfileLimits`.

**Rig, skin, animation and shapes.** `addSkeleton`, `bindSkin`, `addJoint`,
`removeJoint`, `renameJoint`, `reparentJoint`, `setRestPose`, `mirrorJoints`,
`bendJoint`, `setRig`, `autoRig`, `paintWeights`, `retargetClip`, `bakeIk`,
`bakeDrivers` and `validateRig`. `autoRig` runs a `SetRig` command, so it is
in the history. For clips and shapes: `addClip`, `setKey`, `moveKeys`,
`deleteKeys`, `setInterpolation`, `setTangent`, `poseJoint`,
`extractRootMotion`, `bakeRootMotionIntoClip`, `applyClipResult`,
`setShapeWeight`, `addShapeFromMesh`, `renameShape`, `deleteShape`,
`keyShape`, `addShapeDriver`, `removeShapeDriver` and `setShapeDriverField`.

**Simulation, levels of detail and lights.** `applySimulationCache`,
`bakeSimulationToShapes`, `addLod`, `setLodRatio`, `regenerateLods`,
`addLight`, `removeLight`, `setLightField`, `setLightTransform`,
`setEnvironment`, `setSceneLightingField` and `setPanorama`. There is no tool
for impostors.

**The person stays in charge.** Every step carries a `StepAuthor`, and the
journal records it. `ModelSession.client` is stamped from `initialize`, and
`pausedBecause` refuses every call with a sentence while a person has paused
the agent. Command, batch, amend and import tools wait while the history is
inside somebody else's transaction. `save` takes `includeHistory`, off by
default since it measured about nine times the file, and `ModelSession.open`
restores an undo stack a file carries.

**Loopback HTTP beside stdio, and one prompt.** `ModelHttpServer.start` binds
127.0.0.1 with a bearer token and takes one JSON-RPC message per POST, over
`flutter3d_mcp_kit`'s `LoopbackMcpServer`; `extraTools`, `onToolCall` and
`onInitialize` let a host with a window add its own tools and watch the
calls. `modelling_strategy` is the one prompt, with no arguments. The server
offers no resources.

**The server says the version it is.** `modelMcpVersion`, which a client sees
in the handshake and a log quotes back, was the constant `'0.1.0'` while the
package carried 0.6.0 and then 0.7.0. It is `'0.7.0'`, and a test reads the
pubspec and holds the two together. `inspect`'s description ended "No picture
yet", which stopped being true when `render` arrived; it points at `render`.

**Still Dart only.** Dependencies are `flutter3d_model_core`,
`flutter3d_core`, `flutter3d_mesh`, `flutter3d_cpu`, `flutter3d_hardware` and
`flutter3d_mcp_kit` at `^0.7.0`, with `dart_mcp`, `stream_channel` and
`vector_math`. None of them needs Flutter, so
`dart run flutter3d_model_mcp:model_mcp` resolves on a machine that has the
Dart SDK and nothing else. The archive carries four skills for a coding
agent under `skills/`, installed with `dart run skills@ get`.

## 0.6.0

**The server itself, offering every model command as a tool.** `ModelSession`
wraps a project with `list`, `select`, `undo`, `redo`, `check`, `save`,
`export`, `import` and `journal`; `ModelMcpServer` speaks the rest of
`modelCommandNames` over MCP, one tool each, dispatched through
`modelCommandFromJson` the same reader the project file and `CommandJournal`
use. `export` writes `.f3d` and `.obj` and refuses `glb`/`gltf` by name, since
`fmt-06` is not built yet. `test/agent_builds_a_table_test.dart` drives the
real protocol over an in-memory pair of streams and diffs the files a table,
built from primitives, comes out as.

Along the way: `modelCommandFromJson` learned to default `AddPrimitive`'s
`size`/`segments`, `AddLathe`'s `segments`/`closedProfile`/`label`, `LoopCut`'s
`cuts`/`factor` and `RecalculateNormals`'s `flip` when a caller leaves them
out, matching what their constructors already default to — a gap only a
partial JSON call could have found, and this tool table is the first one that
sends one. `flutter3d_model_core` also gained `ReplaceDocument`, the one
command not addressable by name or replayable from a journal, for `import`'s
sake: bringing a whole decoded file's objects in is not an edit any existing
command describes.

**An entry point that said what it could not do yet, and a graph that proved
what it could.** `dart run flutter3d_model_mcp:model_mcp --help` resolved and
printed usage on a machine with the Dart SDK and no Flutter before any of the
above existed — which is the property the whole package split keeps, checked
from the first commit rather than after the server was written.
