# flutter3d_mcp_kit

What every flutter3d MCP server shares, written once:

- `OfferedTool<S, A>` — a tool and the code that runs it, one value, so a tool
  that is offered is a tool that has a body.
- `ToolTableServer<S, A>` — a server that is a list of those over one session.
- `Answer` and `PictureAnswer` — what a call did and the sentence to say about
  it, with `resultOf` and `pictureResultOf` turning a refusal into an error
  result the agent reads rather than a failed server.
- `LoopbackMcpServer` — any of those servers over `127.0.0.1` HTTP with a
  per-server token, for an application that wants to hand an agent the session
  a person already has open.

`flutter3d_editor_mcp`, `flutter3d_model_mcp` and `flutter3d_sim_mcp` (with
both of its servers) are built on it. Plain Dart: no Flutter SDK is needed to
start a server that uses it.
