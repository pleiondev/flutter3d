---
title: Placeholder — the real cases are coming
summary: Proves the route, the Markdown and the pictures work end to end. Not one of the six tutorial cases.
---

# Placeholder — the real cases are coming

**This page is a placeholder, not a tutorial case.** It exists to prove that
`/learn/modeler/` and a case's own page both render, that Markdown under
`content/learn/modeler/` turns into HTML through this page, and that a
picture under `web/assets/learn/modeler/` loads — nothing here is a step to
follow.

The six real cases — a prop from a scan, a vase from a profile, a lit corner,
a character from a bare mesh, borrowing a walk, and an agent beside you —
land once the modeler screens they walk through are finished. This page is
replaced by the first of them, not kept alongside it.

## What the plumbing proves

- A Markdown file with front matter (`title`, `summary`) becomes this page,
  through the same `Page` layout as the rest of the site.
- An image under `web/assets/learn/modeler/<case>/` loads at its own path:

![A placeholder frame, not a screenshot of the modeler](/assets/learn/modeler/placeholder/01-hello.png)

- The index at `/learn/modeler/` lists this page as a card, and a slug that
  is not one of the published cases answers 404 instead of a stack trace.
