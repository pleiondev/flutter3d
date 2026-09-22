---
description: Where to try the modeller — the hosted editor on models.pleion.dev, what the web build can and cannot do, and why it is an editor in a browser rather than a viewer.
---

# Trying it

The modeller runs at **[models.pleion.dev](https://models.pleion.dev/)**, in a browser, as the editor rather than a picture of one. Open a file, edit it, and save it into a cabinet the account keeps.

<div class="note">
<p>Unlike the genre demos on this site, this one is not embedded in the page yet. The editor wants a window rather than a frame — file dialogs, a keyboard that is not competing with a scrolling document, and a viewport worth more than a third of the screen — and an iframe on a documentation page gives it none of those. The link opens the real thing.</p>
</div>

## What the web build actually does

It is the same source as the desktop build, compiled by the same compiler the rest of this site ships with, over the WebGL2 backend. What that buys and what it costs:

| | |
|---|---|
| **Imports** | glTF, GLB, STL, OBJ, FBX — the same readers, in Dart, no server round trip |
| **Edits** | Every mode: object, mesh, material, sculpt, retopo, paint, simulation, animation, scene, render |
| **Keeps** | The project in browser storage, and in a cabinet when signed in — with the recovery journal, so a crashed tab reopens where it was |
| **Exports** | GLB and the project format, straight to a download |
| **Costs** | Arithmetic is roughly four to five times slower than the native build on the same machine — the usual price of the same Dart with no SIMD path, measured rather than assumed |

That last row is the honest one. A sculpting stroke on a 1.2-million-triangle mesh does not hold a frame in a browser, and the editor says so rather than letting a drag stutter: the [budget measurements](/reference/tuning/) are in the repository with dates and machines beside them.

## The desktop build

`flutter build macos --release` from `apps/flutter3d_modeler`, or the same for Windows and Linux. There is no signing or notarisation yet, so macOS asks you to open it the long way the first time — right-click, Open — which is a decision recorded in the plan rather than an oversight.

## Driving it from an agent

The editor speaks MCP. Started with `--mcp-port`, it exposes its whole command table as tools and binds them over *the document a person already has open*, so an agent's edits and yours land on the same history and the same undo stack.

That is the sixth case of the [tutorial](/modeler/tutorial/), and the thing worth knowing about it is that the agent gets no private door: every tool is a command the menu could have run.
