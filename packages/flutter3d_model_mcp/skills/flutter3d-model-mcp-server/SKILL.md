---
name: flutter3d-model-mcp-server
description: Use when starting or building the flutter3d model editor's MCP server — what it runs as today, why the graph must stay free of the Flutter SDK, and the tool table it is built to.
---

# One project per process, over stdio

```bash
dart run flutter3d_model_mcp:model_mcp my-model.f3dproj
```

**Today that entry point says the server is not built yet and exits non-zero.**
What it already proves is what has to hold before any of the server exists: this
package resolves and runs with no Flutter SDK anywhere near it.

## Why plain Dart is a hard requirement here

`dart run` cannot resolve a package that depends on the Flutter SDK, so a
Flutter import anywhere in this graph gives **a server that will not start** on
a machine with the Dart SDK and no Flutter tool — which is what an agent host
usually is. CI checks it in a container with the Dart SDK and
nothing else.

The scan that guards the boundary matches the text `package:flutter/` and does
not see a transitive dependency, so check what a new dependency drags in.

## The shape it is built to

`ModelSession` wraps a project with the verbs an agent needs — listing, select,
run, undo, redo, check, save, export, import, journal — and `ModelMcpServer`
offers them over stdio. The tool table is generated from `modelCommandNames` in
`flutter3d_model_core`, so a command added without a tool is a failing test.
Anything beyond the generated tools is a named set, and every description is a
sentence rather than a label.

Errors come back as `isError` with a sentence an agent can act on, and every
refusal phrase has a test quoting the same words — which is what keeps them
stable enough to be worth reading.

The level editor's server is the worked example: see
`flutter3d-editor-mcp-editing-order` and `flutter3d-editor-mcp-what-it-refuses`.
