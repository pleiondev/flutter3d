# flutter3d_mcp_kit

The parts every flutter3d MCP server shares, written once:

- `OfferedTool<S, A>` holds a tool and the code that runs it in one value, so
  every tool a server offers has a body.
- `ToolTableServer<S, A>` is a server built from a list of those over one
  session.
- `Answer` and `PictureAnswer` carry what a call did and the sentence to say
  about it. `resultOf` and `pictureResultOf` turn a refusal into an error
  result the agent reads, so the server itself does not fail.
- `LoopbackMcpServer` serves any of those servers over `127.0.0.1` HTTP with a
  per-server token, for an application that wants to hand an agent the session
  a person already has open.

`flutter3d_editor_mcp`, `flutter3d_model_mcp` and `flutter3d_sim_mcp` (with
both of its servers) are built on it. It is plain Dart, so a server that uses
it starts without the Flutter SDK.
