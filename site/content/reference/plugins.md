---
description: Plugins for flutter3d, ours and the community's, read from pub.dev by topic, with the plugin API each is written against, the backends it runs on and whether it holds the conformance badge.
---

# Plugin catalogue

Everything outside the engine's kernel is a plugin: the genres, the elements, the post-processing addons, and whatever somebody else writes. A plugin is a `Flutter3dPlugin` with a manifest (its id, the plugin API version it was written against, its dependencies, the backends it runs on, whether it touches the simulation or only the view, and the permissions it asks for) and an `install` that registers what it adds through the host it is handed. The [architecture page](/core/architecture/) says how the host orders and switches them, and the [`flutter3d_plugin_api` README](https://github.com/pleiondev/flutter3d/blob/main/packages/flutter3d_plugin_api/README.md) is what a plugin is written against.

## Getting listed

The list below is read from pub.dev. A package appears in it when it carries the `flutter3d-plugin` topic, and what the table says about it comes from the `flutter3d_plugins:` block of its pubspec (`flutter3d:` before 1.0, still read until 2.0): the same block discovery reads to find the plugin class, plus a few keys the catalogue shows.

```yaml
topics:
  - flutter3d-plugin

flutter3d_plugins:
  plugin: package:wind/wind.dart#WindPlugin
  api: "1.0"              # the plugin API version the manifest names
  backends: [webgpu, cpu] # leave out for every backend
  touches: simulation     # or view
  demo: https://example.dev/wind/   # somewhere to run it in a browser
  conformance: conformant@1.0       # the suite its report says it passed
```

`conformance:` names the suite, `conformant@1.0`. The older `true` is read as suite 1.0, and says less, since a badge earned later against a larger suite is `conformant@1.1`.

The catalogue is fetched when the site is built from a fresh checkout by `npm run plugins`, and the result is committed beside this page, so a build with no network shows the list as it was last read and says when that was.

## The conformance badge

`flutter3d_conformance` has a suite a plugin runs against itself, the way a backend runs the device suite. The badge reads **flutter3d conformant**, and it means: `checkPluginConformance` passes every check on every declared backend, with a world given to determinism and a budget declared and kept, on the plugin API version in its manifest. The eight checks are that the manifest is valid, that the plugin switches off and on at a step boundary and leaves nothing registered behind, that every name it registers is in its namespace, that two runs of one step from one state agree, that it installs on each backend it names and stays off on one it does not, that it keeps the budget it declares, that the physical materials it declares hold to what the engine's own do, and whether it places nodes in the frame.

A plugin that places nodes in the frame earns the badge only with its render checks passed on the software backend too: `runPluginRenderConformance` from `flutter3d_conformance_render`, run beside the plugin suite with `backend: 'cpu'`. The render suite holds a plugin's nodes, its lit model, its light type, its decal, its velocity reader, its shadow technique, its draw-list hook, its level-of-detail policy, its skinning hook, its compute step and its image format, each where the plugin names one, and a render check that fails on any backend keeps the badge away from a plugin of any kind. CI runs the software backend on every change.

A plugin with no world handed to the determinism check, or no budget declared, still passes what it can be asked; it does not get the badge, because the two checks that matter most to a replay were declined rather than run.

The suite is the only judge. Once its checks have run, `runPluginConformance` writes `<package>.conformance.json` beside the pubspec: every outcome, and the badge `earnsBadge` gave, `conformant@1.0` or none. The render suite writes its outcomes into the same file, keeping the plugin suite's, so the badge in it is judged on both. Publish it with the package. The catalogue reads the badge from that file, and falls back on the pubspec's `conformance:` only for a package published without one. `plugin.report`, the plugin author's MCP tool, reads the same file and says how each check went.

## Starting one

```bash
dart run flutter3d_build:create plugin --kind render-step --name soft_glow
```

`--kind` is one of `render-step`, `effect`, `genre`, `element`, `tool` or `backend` (a graphics backend started from the null backend, opened rather than installed). Each writes a package with the pubspec block above, a plugin class with its manifest, and a test that runs the conformance suite, so the badge is something a new plugin starts out able to earn.

{{plugin-catalogue}}
