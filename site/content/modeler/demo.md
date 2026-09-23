---
description: Where to try the modeller, the hosted editor on models.pleion.dev, what the web build can and cannot do, and why it is an editor in a browser and not a viewer.
---

# Trying it

The modeller runs at **[models.pleion.dev](https://models.pleion.dev/)**, in a browser, and what opens there is the editor itself. Open a file, edit it, and save it into a cabinet the account keeps.

<div class="note">
<p>Unlike the genre demos on this site, this one is not embedded in the page yet. The editor wants a whole window: file dialogs, a keyboard that isn't competing with a scrolling document, and a viewport bigger than a third of the screen. An iframe on a documentation page gives it none of those, so the link opens the real thing.</p>
</div>

## What the web build does

It is the same source as the desktop build, compiled by the same compiler the rest of this site ships with, over the WebGL2 backend. Here is what that buys and what it costs:

| | |
|---|---|
| **Imports** | glTF, GLB, STL, OBJ, FBX, with the same readers in Dart and no round trip to a server |
| **Edits** | Every mode: object, mesh, material, sculpt, retopo, paint, simulation, animation, scene, render |
| **Keeps** | The project in browser storage, and in a cabinet when signed in, with the recovery journal, so a crashed tab reopens where it was |
| **Exports** | GLB and the project format, straight to a download |
| **Costs** | Arithmetic runs roughly four to five times slower than the native build on the same machine, which is the usual price of the same Dart with no SIMD path. That figure was measured, not assumed |

The last row is where the web build falls short. A sculpting stroke on a 1.2-million-triangle mesh does not hold a frame in a browser, and the editor tells you so instead of letting the drag stutter. The [budget measurements](/reference/tuning/) are in the repository with dates and machines beside them.

## The desktop build

Run `flutter build macos --release` from `apps/flutter3d_modeler`, or the same for Windows and Linux. The build is not signed or notarised yet, so the first time macOS makes you open it the long way (right-click, Open). The plan records that as a decision; nobody forgot.

## Driving it from an agent

The editor speaks MCP. Started with `--mcp-port`, it exposes its whole command table as tools and binds them over *the document a person already has open*, so an agent's edits and yours land on the same history and the same undo stack.

That is the sixth case of the [tutorial](/modeler/tutorial/). The agent gets no private door: every tool is a command the menu could have run.
