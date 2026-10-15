# Security policy

Revised 2026-10-15, for the `1.0.0-rc.1+2` tree.

## Reporting a vulnerability

Report privately through GitHub's
[security advisories](https://github.com/pleiondev/flutter3d/security/advisories/new),
not in a public issue, a discussion or a chat channel. The advisory form is
the only private channel, and it is for security problems only.

Please include what an attacker gains, the smallest input or sequence that
shows it, and the package and version it is in. A failing test is the
clearest report there is.

You get an acknowledgement within a week. This is a small project with one
maintainer and no security team, so a fix can take longer than that; I will
tell you where it stands rather than leave you waiting. Once a fix is
released, the advisory is published with credit to the reporter, unless you
ask otherwise.

## Which versions get fixes

The ones [SUPPORT.md](SUPPORT.md#versions) names under "Which releases get
fixes", for as long as it says. In short: the newest minor gets every fix,
and the minor before it gets security fixes for three months after its
successor ships. A security fix is a patch release of every package it
touches.

Until 1.0.0 ships, that means the release candidate: fixes land on `main`
and go out in the next candidate. The 0.8.x line on pub.dev gets none.

## What is in scope

The engine opens no network port of its own and runs no code it is not
given, so most of the surface is **the data it reads**. The packages that do
talk to a network or load code come after it.

**Data an application may not control:**

- **Asset parsing.** glTF, GLB, OBJ, STL, PLY, KTX2, Draco, Radiance `.hdr`
  and `.f3d` are read from files an application may not control. A
  malformed document must fail, not read out of bounds or allocate without
  limit.
- **The writers on the other side of those decoders.** `F3dWriter`,
  `ObjWriter`, `StlWriter` and `GltfWriter` take a decoded document and
  produce bytes, and a document built from an untrusted import is exactly
  the input a writer sees next. The same rule applies.
- **The model editor's project format**, `.f3dproj` (`readProject` returns a
  sealed `ProjectOpened` or `ProjectRefused`): a file a person can edit by
  hand or send to somebody else.
- **Level, prefab and save documents**: JSON read from disk and from a
  game's own save file, which a player can edit.
- **Shader bundles**: loaded as assets, and tied to the Flutter version that
  produced them.

**The parts that talk to a network or load code:**

- **The relay** (`dart run flutter3d_net:relay`, in `flutter3d_net`). It
  joins sockets by a room code and forwards what they send without parsing
  it. In scope: reading or injecting into a room you did not join, crashing
  the relay or exhausting its memory with less traffic than it forwards,
  and taking another player's slot. Out of scope: a room code somebody
  guesses. A code only tells the relay which sockets to join, and it was
  never meant as a password. A game that needs one belongs behind a relay you run yourself, with your own
  authentication in front of it.
- **LTI 1.3 and xAPI** (`flutter3d_education_lti`).
  `LtiLaunchValidator` checks an `id_token`'s signature against the
  platform's JWKS, its issuer, audience and expiry, and the `state` and
  `nonce` of the login that started it. In scope: a launch it accepts and
  should refuse, a grade posted for the wrong user or line item, and a
  token or key that reaches a log.
- **The MCP servers** (`flutter3d_mcp`, `flutter3d_sim_mcp`). Over stdio
  they trust the process that started them. `LoopbackMcpServer` listens on
  `127.0.0.1` with a token per server. In scope: reaching a server without
  its token, from a browser page or another machine; a tool call that reads
  or writes a file outside the project it was given; and a document an
  agent makes the editor open that gets past the rules above.
- **Wasm plugins** (`flutter3d_plugin_runtime`). A module reaches the world
  only through the `f3d` imports and has no I/O. The default runtime is the
  package's own interpreter, which meters fuel per step, call depth and
  memory pages; the browser's own WebAssembly runtime holds the memory
  limit but cannot count fuel. A data plugin gets only the permissions its
  manifest declares and the application grants. In scope: a module that
  escapes the interpreter, outruns a limit the runtime says it enforces, or
  reaches anything an import does not hand it; and a plugin that uses a
  permission it was not granted.
- **The hosted services** built from `cloud/` (the model library at
  [models.pleion.dev](https://models.pleion.dev)) and the documentation
  site. Report them the same way.

## What is not

- Anything that needs an attacker who already runs code in your process,
  or who can replace your application's assets or its Dart code.
- Denial of service by asking the renderer to draw something enormous. A
  scene budget is the application's decision, and the engine takes what it
  is given.
- A player editing the save files of a single-player game. They are the
  player's to edit.
- Cheating in a multiplayer game by a player who runs a modified client.
  Rollback and the relay keep honest machines in agreement; they do not
  make a client trustworthy. An authoritative server (`AuthorityServer` in
  `flame_multiplayer`) is the tool for that.
- Vulnerabilities in Flutter, Dart, `flutter_gpu` or a pub dependency.
  Report those upstream. If flutter3d uses one in a way that makes it
  worse, that part is in scope here.
