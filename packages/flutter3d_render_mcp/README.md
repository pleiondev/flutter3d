# flutter3d_render_mcp

An MCP server, part of [flutter3d](https://flutter3d.pleion.dev): why is
the frame wrong, without guessing — `par-02` in `doc/tooling-plan.md`.
A headless frame through `flutter3d_cpu` (no GPU), the raw HDR value of
one pixel before it is clamped to eight bits, one of the renderer's own
debug views, and a scan for the first pixel that is not finite.

Genre-agnostic, unlike `flutter3d_sim_mcp`: it opens any level and asks
questions about the frame itself, not about a monster or a weapon in it.
Speaks MCP over a socket rather than literal stdio, for the same reason
`flutter3d_sim_mcp` does — a `flutter test` process rewrites stdout
through its own logger.
