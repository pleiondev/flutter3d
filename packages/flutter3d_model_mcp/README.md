# flutter3d_model_mcp

[flutter3d](https://flutter3d.pleion.dev)'s model editor, offered to an agent:
an MCP server over stdio whose tools are the editor's own commands, one project
per process.

```bash
dart run flutter3d_model_mcp:model_mcp my-model.f3dproj
```

**Plain Dart, and a host is why.** `dart run` cannot resolve a package that
depends on the Flutter SDK, so a Flutter import anywhere in this graph is not a
heavier process — it is a server that will not start on a machine without the
Flutter tool. That is checked in CI, in a container with the Dart SDK and
nothing else.

## What is here today

The entry point and its usage line. Running it says the server is not built yet
and exits non-zero, which is the honest answer while it is true; what it proves
today is the thing that has to hold before any of the server exists — that this
package resolves and runs with no Flutter SDK anywhere near it.

The tools, the session and the agent scenario are `doc/model-editor-plan.md`
doc-19 through doc-22.

## Licence

MIT.
