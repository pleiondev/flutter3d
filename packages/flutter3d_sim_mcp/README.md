# flutter3d_sim_mcp

An MCP server, part of [flutter3d](https://flutter3d.pleion.dev): a shooter
level an agent can play blind — `ai-00` in `doc/tooling-plan.md`. Open a
level, step it forward with input, read positions and health back in
words, capture a headless frame with no GPU, and hand over the run it
made as a `.f3drun` any other tool in this repository can open.

A claim about the run comes with its proof: `expect` steps until a
predicate over the reading holds (near a point, inside a box, alive,
health) and writes the `.f3drun` that got there, and `verify` replays
such a file in a world of its own and names the first checkpoint where
it stops matching, if there is one. What touched what cannot be claimed:
game events are not saved in a run.

**Genre-aware on purpose**, unlike `flutter3d_editor_mcp`/
`flutter3d_model_mcp`: it knows what a monster and a weapon are, because
the question it answers — "what does the room look like from here, and
is the player still alive" — has no genre-agnostic version.

Speaks MCP over a socket rather than literal stdio: `flutter test` itself
rewrites everything a test writes to stdout with its own prefix, which a
protocol tied to an exact line format does not survive.
