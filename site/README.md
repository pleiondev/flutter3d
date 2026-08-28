# site

The documentation site for this engine, at **https://flutter3d.pleion.dev/** (basic auth).

Thirty pages of Markdown, a 250-line build script, and no framework. Every page
is a file on disk, which is what makes it serveable by nginx with `try_files`
and nothing else — and what makes a broken page a broken page rather than a
blank screen.

## Building

```bash
npm install
npm run build          # content/*.md -> dist/
```

Then open `dist/index.html` through any static server:

```bash
python3 -m http.server 8765 --directory dist
```

## Deploying

```bash
tool/deploy.sh
```

Builds and rsyncs `dist/` to `bob:/opt/flutter3d`. Nothing else changes on a
redeploy — the nginx vhost, the credentials and the tunnel all stay put.

## How it is put together

| | |
|---|---|
| `content/` | The pages, as Markdown with a two-line front matter |
| `tool/build.mjs` | The whole build. `NAV` at the top is the single source for the sidebar, the prev/next links and the build order, so the three cannot disagree |
| `assets/site.css` | Impeller Dark, plus a light theme by token flip |
| `assets/site.js` | Theme toggle, mermaid theming, scrollspy, mobile nav |
| `dist/` | Generated. Not in the repository |

### Writing a page

```markdown
---
description: One sentence, used as the meta description.
---

# Page title

The lead paragraph, styled larger and muted.

## A section

<div class="note">…</div>   a neutral aside
<div class="warn">…</div>   something that bites
<div class="why">…</div>    why a decision is what it is

## A numbered step {.step}

Only in tutorials, where the order carries information.
```

Add the file to `NAV` in `tool/build.mjs` and it appears in the sidebar, the
pager and the build. Nothing scans the directory, so a half-written page cannot
turn up in the nav by accident.

The conventions behind all of this — the palette's two load-bearing choices,
when numbered steps are allowed, the mermaid label-clipping trap, and the rule
that every snippet is checked against `packages/*/lib/` before it is written —
are in [CLAUDE.md](CLAUDE.md).

Fenced ```mermaid blocks become diagrams, themed from the same tokens as the
page. The mermaid runtime is vendored out of `node_modules` at build time, so
the published page loads nothing from a CDN.

## Where it runs

- **Files** — `bob:/opt/flutter3d`, owned by `www-data`
- **nginx** — `/etc/nginx/sites-available/flutter3d.pleion.dev`, listening on `127.0.0.1:8790`
- **Basic auth** — `/etc/nginx/.htpasswd-flutter3d`
- **Tunnel** — `cloudflared-flutter3d.service`, config at `/etc/cloudflared/flutter3d.yml`

Cloudflare terminates TLS, so nginx serves plain HTTP on a loopback port and is
not reachable from outside the machine.
