# CLAUDE.md — the documentation site

Instructions for working on `site/`. The engine itself is the rest of the
repository; nothing here is imported by it.

## What this is

A static documentation site for the flutter3d engine, published at
**https://flutter3d.pleion.dev/** behind basic auth.

Twenty-five pages of Markdown and one build script, with no framework and no
client-side router. Every page is a file on disk, so nginx serves it with
`try_files` and nothing else, and a broken page is a broken page instead of a
blank screen.

## Commands

```bash
cd site
npm install                                    # once
npm run build                                  # content/*.md -> dist/
python3 -m http.server 8765 --directory dist   # preview
tool/deploy.sh                                 # build + rsync to bob
```

`dist/` and `node_modules/` are gitignored.

## The rule that matters most

**Every code example is real API from this repository.** Before writing a
snippet, check the signature in `packages/*/lib/` — constructor parameter
names, whether a class is `const`-constructible, whether a getter exists.

This has already caught several plausible-looking mistakes: `DeviceMesh` has
`upload(device, meshData)` and no `fromShape`; `Raycaster.setFromScreen` takes
`(camera, x, y, {width, height})` and not an `Offset`; `LodGroup` takes
`levels:` as a named argument; `CollisionLayers.pickup` is bit 4, not bit 3;
`Level` has an `addTo(world)` extension, not `buildCollision`. An example that does not compile is worse than no example, because a reader
will trust it.

The same goes for prose. Numbers on this site (2901 tests, 4.54 ms → 1.1 µs,
fourteen centimetres per texel, 17.7 ms per frame) come from the repository's
own READMEs and `ARCHITECTURE.md`. Do not
invent one, and do not round one someone measured.

State unfinished things as unfinished, and re-check the claim before repeating
it. The site said for a while that the WebGL backend had no shaders, which its
own library docstring still says; the shaders had in fact been generated, and
the real defect was that they had gone stale. A stale claim about the code is
the same defect as a stale example of it.

## Structure

| | |
|---|---|
| `content/` | The pages, as Markdown with front matter |
| `tool/build.mjs` | The whole build |
| `tool/deploy.sh` | Build, rsync, chown |
| `assets/site.css` | Impeller Dark, plus a light theme by token flip |
| `assets/site.js` | Theme toggle, mermaid theming, scrollspy, mobile nav |
| `assets/favicon.svg` | Two triangles, amber and cyan |

### `NAV` is the single source

The `NAV` array at the top of `tool/build.mjs` drives the sidebar, the
prev/next pager and the build order. Adding a page means adding a file *and* an
entry there — nothing scans the directory, deliberately, so a half-written page
cannot appear in the nav by accident.

```js
{ file: 'core/backends.md', url: '/core/backends/', title: 'Writing a HAL backend', kind: 'guide' }
```

`kind` is optional and renders as a small chip in the sidebar (`tutorial`,
`guide`).

## Writing a page

```markdown
---
description: One sentence. Becomes the meta description.
---

# Page title

The lead paragraph. Styled larger and muted — say what the page is for, not
what is in it.

## A section

<div class="note">…</div>   a neutral aside
<div class="warn">…</div>   something that bites
<div class="why">…</div>    why a decision is what it is

## A numbered step {.step}
```

Callouts are raw HTML because the content is prose, not Markdown blocks — put
`<p>` around each paragraph and use `<code>`, `<strong>`, `<em>` inline.

### Numbered steps

`{.step}` on an `h2` renders an amber `01` chip and increments a counter.
**Only in tutorials**, where the order carries information a reader needs.
Everything else is a set, and numbering a set is decoration.

If you add or remove a step, fix the count in the page's lead paragraph and in
any page that links to it — three of them said the wrong number on the first
pass.

### Diagrams

Fenced ` ```mermaid ` blocks become diagrams, themed from the same tokens as
the page. The runtime is vendored out of `node_modules` at build time, so the
published page loads nothing from a CDN.

Mermaid measures monospace labels badly and **clips long ones**. Keep a node to
three or four short lines with `<br>` between them rather than two long ones,
and check the rendered result rather than trusting the source.

Nodes inside a `subgraph` with no edges between them lay out horizontally
however you set `direction`. Chain them with the invisible link `~~~` to stack
them.

## House style

The repository's own source comments explain *why* a thing is the way it is,
usually by naming the bug that made it so, and the site borrows that voice.
Prefer "a platform that moves sideways cannot carry you if the deltas are
cleared first" to "be careful with ordering", and where the repository says a
claim is untested, say that too.

Borrowed at full strength across twenty-odd pages, though, that voice stops
reading as documentation and starts reading as generated text. These limits are
deliberate:

| Limit | Why |
|---|---|
| **Em dashes: about one per 250 words** | The first draft ran one per 95. Prefer a comma, a colon, a semicolon, a full stop or brackets. `rg -o '—' content \| wc -l` against `wc -w` is the check |
| **No maxim at the end of a section** | "A test suite that cannot fail is worse than none" and its relatives were cut. State the fact and stop |
| **One war story, one place** | The sideways platform, the five identical goldens and the shadow slab each appeared three or four times. Each now lives on one page and the others link to it. `reference/pitfalls.md` is the exception: it is a symptom index, so repetition there is the point |
| **Plain table cells** | A cell states the fact. If the reason is worth a sentence it goes in prose, not in every row |
| **Vary the contrastive** | "rather than" ran 135 times. Half became "instead of" or were dropped |

Before adding a page, read one already there and check the new one does not repeat its anecdotes.

## Design

Impeller Dark. The tokens are at the top of `assets/site.css`; change them
there and both themes follow.

```
--bg      #0B0F14   --text   #E6EDF3   --amber  #FF8A3D   (links, headings)
--surface #131A22   --muted  #8A9BA8   --cyan   #4DD0E1   (code, diagrams)
--well    #0E141B   --border #22303C   --green  #7BD88F
```

Two things carry the identity, and neither should be diluted:

- **Headings are set in the mono face.** The engine's subject is source,
  shader bundles and profiler tables, and a docs site that sets its titles in
  the same face as its code reads like the thing it documents. Docs sites
  almost never do this, which is the point.
- **The frame band on the home page** is the real pass order the renderer
  encodes, not decoration. If the pass order changes, that band changes.

The light theme is a token flip under `html[data-theme="light"]`. Any new
colour needs a value in both blocks — a colour defined only in the dark block
turns invisible on light.

## The playable demos

The games are built for the web against `flutter3d_webgl` into **`dist/demo/`**, which is inside the site rather than beside it, and embedded in `content/*/demo.md` through an iframe. `npm run build` wipes `dist/`, so `tool/demos.sh` runs after it — `tool/deploy.sh` does both in that order, and one rsync now carries the site and the games together. It used to be two deploys with an anchored exclude between them, which is a thing that breaks quietly.

All three are playable. The racing game was not for months — well under a frame a second — and the two changes that fixed it were `ShadowSettings.cubeResolution`, which stopped a cube shadow atlas being sized from the sun's tile and took 402 MB of texture down to 100, and `--wasm`. Its demo page keeps the hunt, because the measurement that looked like a dead end (shrinking the frame changed nothing) was the clue: the atlas is not sized from the frame.

```bash
tool/demos.sh            # regenerate shaders, build all three to wasm into dist/demo
tool/demos.sh racing     # or just one of them
```

Four traps, each of which cost a build:

- **The application directories are `apps/flutter3d_demo_*`.** The old deploy script named `apps/dungeon`, `apps/platformer` and `apps/racing` for months after the rename, and the breakage was invisible: those directories still existed on a machine that had built the games before, holding nothing but a stale `build/`, so `cd` succeeded and rsync pushed whatever was last compiled there.
- **`--base-href` is required.** The demos are served from a subdirectory, and Flutter's default `<base href="/">` makes the app request `/main.dart.js`. That is a 404 and a blank page.
- **The rsync exclude must be anchored.** `--exclude 'demo/'` also matches `platformer/demo/`, which is a documentation page; the first deploy deleted both demo pages. It is `--exclude '/demo/'`.
- **The generated GLSL goes stale silently.** `flutter3d_webgl/lib/engine_shaders.dart` is translated from `flutter3d_shaders` and nothing checks that it is current. When the engine's uniform blocks change, the backend draws nothing and says the block has no such member. `tool/demos.sh` regenerates it every time.

## The generated API reference

`/docs/` is `dart doc` output, one tree per package, plus an index this
repository writes.

```bash
tool/build-docs.sh              # every package -> site/docs-dist/
tool/build-docs.sh flutter3d    # one of them, while iterating
tool/deploy-docs.sh             # build + rsync to bob:/opt/flutter3d/docs
```

Three things about it are decisions rather than accidents:

- **It does not go into `dist/`.** `npm run build` wipes that on every run, and
  regenerating twenty-two dartdoc trees to publish a typo fix is minutes of work
  for nothing. `tool/deploy.sh` therefore excludes `/docs/` the same way and for
  the same reason it excludes `/demo/`.
- **The index is generated from the packages on disk**, with each package's
  pubspec description as its line. A hand-kept list is the thing that goes stale
  the day somebody adds a package, and the description is already the sentence
  pub.dev would show, so there is no second summary to keep true.
- **Each package is retried once.** One of twenty-two was killed with SIGTERM
  part way through a full sweep and documented cleanly on its own seconds later;
  `dart doc` precaches around 650k elements per run. A reference silently missing
  a package is worse than a slow one.

The prose pages and the reference are deployed separately because they change at
different rates: the prose is edited daily, the reference only when a public API
moves.

## Where it runs

| | |
|---|---|
| Files | `bob:/opt/flutter3d`, owned by `www-data` |
| nginx | `/etc/nginx/sites-available/flutter3d.pleion.dev`, listening on `127.0.0.1:8790` |
| Basic auth | `/etc/nginx/.htpasswd-flutter3d`, user `flutter3d` |
| Tunnel | `cloudflared-flutter3d.service`, config `/etc/cloudflared/flutter3d.yml`, tunnel `ebe796b0-5109-4645-87cf-8ca1698fcc15` |
| Demos | `bob:/opt/flutter3d/demo/{platformer,shooter,racing}`, about 160 MB together |
| API reference | `bob:/opt/flutter3d/docs/<package>/`, generated by `dart doc` |

Cloudflare terminates TLS, so nginx serves plain HTTP on a loopback port and is
not reachable from outside the machine. A redeploy replaces files only —
the vhost, the credentials and the tunnel all stay put.

**The password is not in this repository and must not be put in it.** It lives
in the htpasswd file on the server. To rotate it:

```bash
ssh bob "htpasswd -b /etc/nginx/.htpasswd-flutter3d flutter3d '<new>'"
```

### If the tunnel needs recreating

`cloudflared tunnel route dns` reads `/root/.cloudflared/config.yml` when no
`--config` is given and will silently attach the hostname to **that** tunnel.
Pass an empty config explicitly:

```bash
ssh bob "echo '{}' > /tmp/empty-cf.yml && \
  TUNNEL_ORIGIN_CERT=/etc/cloudflared/cert.pem cloudflared --config /tmp/empty-cf.yml \
  tunnel route dns --overwrite-dns <tunnel-id> flutter3d.pleion.dev"
```

Other tunnels on this host (`aux`, `prism-arina`) belong to other services.
Do not edit their configs.

## Checking a change

`npm run build` fails loudly on a missing content file and on nothing else, so
look at the result:

```bash
grep -o '<li class="lv[23]"' dist/<page>/index.html | wc -l   # the page's contents
grep -c 'class="mermaid"' dist/<page>/index.html              # diagrams present
grep -o 'data-lang="[a-z]*"' dist/<page>/index.html | sort -u # code fences tagged
```

Then open it. The build cannot tell you that a diagram clipped its labels or
that a table went off the edge, and both have happened.

## Keeping the counts honest

Three numbers on this site go stale on their own, and all three were wrong once:

- **Test count.** 2901, and the repository counts it rather than this site: the
  `the document says how many tests there are` rule scans every `test(` call and
  now holds both `ARCHITECTURE.md` and the README to the answer. Take the number
  from there — the README said 1242 for a year because nothing compared it with
  anything.
- **Package and game counts.** Twenty-three packages, five applications, three
  genres. "Two games" was hard-coded into a dozen sentences and the home page
  headline; grep for it before assuming.
- **Backend status.** What each of the three backends can actually run, which
  is not the same as what its library docstring claims.
