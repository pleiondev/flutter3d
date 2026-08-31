# Security policy

## Reporting a vulnerability

Report privately through GitHub's
[security advisories](https://github.com/pleiondev/flutter3d/security/advisories/new)
rather than in a public issue.

Please include what an attacker gains, the smallest input or sequence that shows
it, and which package it is in. A failing test is the clearest report there is.

You should get an acknowledgement within a week. This is a small project without
a security team, so a fix may take longer than that; you will be told where it
stands rather than left waiting.

## What is in scope

This is a rendering and game engine, so the interesting surface is **the data it
reads**, not a network it does not open:

- **Asset parsing** — glTF, GLB, OBJ and `.f3d` are read from files an
  application may not control. A malformed document must fail, not read out of
  bounds or allocate without limit.
- **Level and save documents** — JSON read from disk and from a game's own save
  file, which a player can edit.
- **Shader bundles** — loaded as assets, and the format is tied to the Flutter
  version that produced it.

## What is not

- Anything requiring an attacker who already runs code in your process.
- Denial of service by asking the renderer to draw something enormous. A scene
  budget is an application's decision, and the engine takes what it is given.
- The demo applications' saved files being editable by their own player. A
  single-player game's save is the player's to edit.

## Supported versions

Nothing is published to pub.dev yet, and there are no releases to back-port to:
fixes land on `main`.
