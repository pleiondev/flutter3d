---
description: A level or a prefab document as JSON in an editor, drawn by flutter3d's web backend in this page as you type it, with what is wrong with it said under the text.
---

# Playground

A level document on the left, the level it describes on the right. Change a number and the scene changes a quarter of a second after you stop typing; break the JSON and the line and column of the break appear under the text, while the last document that read stays on screen.

<div class="demo">
  <iframe class="demo-frame" src="/demo/playground/" title="The playground: a level document and its scene" loading="lazy"></iframe>
  <p class="demo-bar">
    <span>WebGPU, or WebGL2 where the browser has no adapter</span>
    <span><a href="/demo/playground/" target="_blank" rel="noopener">Open full screen ↗</a></span>
  </p>
</div>

<div class="note">
<p>A drag on the scene turns the camera, a scroll or a pinch moves it in and out. The two buttons above the text load a level and a prefab to start from; nothing you type leaves the page.</p>
</div>

## What it reads

**A level document**: the `f3d.level` format the level editor writes and every game reads, with `materials`, `brushes`, `lights`, `entities`, `prefabs` and `recipes`. Prefab instances and recipes are expanded as a game expands them, so an override on an instance shows on the instance.

**A prefab on its own**: an object with `entities` and no `format`, drawn as one instance of itself at the origin.

## What it draws

The brushes in their materials and the lights the level carries, through the same `LevelScene` a game builds its level with. **An entity is a small box, one colour per type.** What an entity looks like is a game's vocabulary (a `pickup` is a model the game names), and the playground has no game, so it shows where each one is and how many there are. A document with no light of its own is lit by a sun.

## What it says

An error stops a document being drawn: JSON that does not parse (with its line and column), a document of another format or a newer version, a field of the wrong type, an instance of a prefab nobody wrote. A warning is said beside a document that is drawn anyway, such as an override addressed to an entity its prefab no longer has.

## Where it goes from here

The text is a level document like any other: save it as `assets/levels/first.level.json` in a project and open it in the [level editor](/download/), or read it in a game with `Level.parse`. [Your first project](/first-project/) starts from a template that already has one.

The page is `apps/flutter3d_playground` built for the web by `site/tool/demos.sh playground`, the same script the playable demos are built with.
