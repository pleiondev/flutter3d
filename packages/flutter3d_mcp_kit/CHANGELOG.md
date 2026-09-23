## 0.7.1

**Released with the rest of the stack at 0.7.1.** Nothing in this package
changed. The release it resolves against builds from pub.dev again and no
longer crashes Metal on the first unlit draw.

Its `flutter3d_*` dependencies ask for `^0.7.1`.

## 0.7.0

- **The first publication.** The 0.6.0 below was a number carried inside the
  workspace and never reached pub.dev. 0.7.0 is the number the whole shelf
  goes out on, so that one number names one tree and `^0.7.0` on any
  `flutter3d_*` package resolves against every other;
  `doc/boundary-0.7.0.md` lists the thirteen packages that begin here. Three
  servers depend on this one: `flutter3d_model_mcp`, `flutter3d_editor_mcp`
  and `flutter3d_sim_mcp`.
- **The names the entry below describes without naming.**
  `OfferedTool<S, A>(tool, run)` is a tool and its handler as one value, and
  `run` may return a `Future`. `ToolTableServer<S, A>` registers a list of them
  over one `session` and turns each answer into a result with `toResult`.
  `Answer` is `({bool did, String says})` and `PictureAnswer` adds a nullable
  `png`; `resultOf` and `pictureResultOf` make the results, with `isError` set
  when `did` is false. `LoopbackMcpServer.start` binds 127.0.0.1 only, takes
  one JSON-RPC message per POST and wants a bearer token of 32 random bytes;
  `writeMcpSessionFile` and `deleteMcpSessionFile` keep the `{port, token}`
  file a client finds it by.
- **A wrong argument is refused by name.** With `refusal` given,
  `ToolTableServer` switches off `dart_mcp`'s `validateArguments` and runs
  `refuseArguments(tool, arguments)` first. It answers a sentence for an
  unknown key, saying which keys the tool does take, and then for the first
  schema error: an enum miss, a wrong type, a wrong item count, a number out
  of range, a missing required key. The sentence comes back as an ordinary
  error result the model can act on. Without `refusal` the framework's own
  check runs as before.
- **`pausedBecause`: the person stays in charge.** A function asked before
  every call; a non-null sentence is returned as the refusal and the tool does
  not run. It is asked ahead of the argument check, since a complaint about a
  misspelt key is a strange answer to "you are paused". It is consulted only on
  a server that was also given `refusal`, because that is what builds the
  answer.
- **`onCall` and `onInitialize`, for whoever is watching.** `onCall(toolName,
  arguments, answer, elapsed)` runs after each tool and
  `onInitialize(clientName)` when a client connects. An exception thrown by
  either is swallowed: a re-sync inside the hook once threw for one object a
  device had refused, and the answer, already computed and correct, reached
  the agent as a stack trace, for that call and every one after it. The
  stopwatch is started only when `onCall` is set, so a headless server never
  reads the clock.
- **Prompts.** `OfferedPrompt(name:, description:, text:)` and the `prompts`
  list; `prompts/get` hands back the text as one user message. A prompt here
  takes no arguments. `ToolTableServer` mixes in `PromptsSupport` for it.
- Plain Dart on `dart_mcp` `>=0.5.2 <0.6.0` and `stream_channel` `^2.1.4`, with
  no sibling dependency. `loopback_http.dart` imports `dart:io`.

## 0.6.0

- **The arrangement four servers each wrote, written once.** A tool paired with
  its handler, a server that registers a list of them over one session, the
  two shapes of answer and the functions that turn them into results, and the
  loopback HTTP transport that used to belong to the modeller's server alone.
