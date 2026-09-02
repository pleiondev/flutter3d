// Builds the static site: content/*.md -> dist/*.html.
//
// No framework and no client-side router. Every page is a file, which is what
// makes the whole thing serveable by nginx with `try_files` and nothing else,
// and what makes a broken page a broken page rather than a blank screen.
import { readFileSync, writeFileSync, mkdirSync, cpSync, existsSync, rmSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

import MarkdownIt from 'markdown-it';
import anchor from 'markdown-it-anchor';
import attrs from 'markdown-it-attrs';
import hljs from 'highlight.js';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..');
const contentDir = join(root, 'content');
const distDir = join(root, 'dist');

// Stated once. The footer, the topbar and the architecture link all point at the
// same place, and three copies of a URL is three chances to update two of them.
const GITHUB = 'https://github.com/pleiondev/flutter3d';
const LINKEDIN = 'https://www.linkedin.com/in/dmitrii-zolotov';
const EMAIL = 'dmitrii.zolotov@gmail.com';

const ICONS = {
  mail: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M22 6a2 2 0 0 0-2-2H4a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2Z"/><path d="m22 6-10 7L2 6"/></svg>',
  feedback: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/></svg>',
  linkedin: '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M20.447 20.452h-3.554v-5.569c0-1.328-.027-3.037-1.852-3.037-1.853 0-2.136 1.445-2.136 2.939v5.667H9.351V9h3.414v1.561h.046c.477-.9 1.637-1.85 3.37-1.85 3.601 0 4.267 2.37 4.267 5.455v6.286zM5.337 7.433c-1.144 0-2.063-.926-2.063-2.065 0-1.138.92-2.063 2.063-2.063 1.14 0 2.064.925 2.064 2.063 0 1.139-.925 2.065-2.064 2.065zm1.782 13.019H3.555V9h3.564v11.452zM22.225 0H1.771C.792 0 0 .774 0 1.729v20.542C0 23.227.792 24 1.771 24h20.451C23.2 24 24 23.227 24 22.271V1.729C24 .774 23.2 0 22.222 0h.003z"/></svg>',
  github: '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M12 .297c-6.63 0-12 5.373-12 12 0 5.303 3.438 9.8 8.205 11.385.6.113.82-.258.82-.577 0-.285-.01-1.04-.015-2.04-3.338.724-4.042-1.61-4.042-1.61C4.422 18.07 3.633 17.7 3.633 17.7c-1.087-.744.084-.729.084-.729 1.205.084 1.838 1.236 1.838 1.236 1.07 1.835 2.809 1.305 3.495.998.108-.776.417-1.305.76-1.605-2.665-.3-5.466-1.332-5.466-5.93 0-1.31.465-2.38 1.235-3.22-.135-.303-.54-1.523.105-3.176 0 0 1.005-.322 3.3 1.23.96-.267 1.98-.399 3-.405 1.02.006 2.04.138 3 .405 2.28-1.552 3.285-1.23 3.285-1.23.645 1.653.24 2.873.12 3.176.765.84 1.23 1.91 1.23 3.22 0 4.61-2.805 5.625-5.475 5.92.42.36.81 1.096.81 2.22 0 1.606-.015 2.896-.015 3.286 0 .315.21.69.825.57C20.565 22.092 24 17.592 24 12.297c0-6.627-5.373-12-12-12"/></svg>',
};

// Icons rather than text: this row needs to fit in the topbar next to the
// existing chips and still read clearly in the footer on a phone, where the
// topbar itself is hidden. Same markup both places, one function to update.
function iconLinks({ github = false } = {}) {
  const items = [
    { key: 'mail', href: `mailto:${EMAIL}?subject=${encodeURIComponent('Question about flutter3d')}`, label: 'Email a question' },
    { key: 'feedback', href: `mailto:${EMAIL}?subject=${encodeURIComponent('Feedback on flutter3d')}`, label: 'Send feedback' },
    { key: 'linkedin', href: LINKEDIN, label: 'LinkedIn' },
    ...(github ? [{ key: 'github', href: GITHUB, label: 'GitHub' }] : []),
  ];
  return `<div class="icon-links">${items.map((item) =>
    `<a class="icon-link" href="${item.href}" rel="noopener" aria-label="${item.label}" title="${item.label}">${ICONS[item.key]}</a>`
  ).join('')}</div>`;
}

// ---------------------------------------------------------------------------
// The site's shape. One list, in reading order: the sidebar, the prev/next
// links and the build order all come from it, so they cannot disagree.
// ---------------------------------------------------------------------------
const NAV = [
  {
    section: 'Start here',
    slug: 'start',
    pages: [
      { file: 'index.md', url: '/', title: 'flutter3d' },
      { file: 'quickstart.md', url: '/quickstart/', title: 'Quickstart' },
      { file: 'first-project.md', url: '/first-project/', title: 'Your first project', kind: 'guide' },
    ],
  },
  {
    section: 'Core',
    slug: 'core',
    badge: 'engine',
    pages: [
      { file: 'core/index.md', url: '/core/', title: 'What core is' },
      { file: 'core/architecture.md', url: '/core/architecture/', title: 'Architecture' },
      { file: 'core/backends.md', url: '/core/backends/', title: 'Writing a HAL backend', kind: 'guide' },
      { file: 'core/rendering.md', url: '/core/rendering/', title: 'The frame' },
      { file: 'core/scene.md', url: '/core/scene/', title: 'Scene graph' },
      { file: 'core/geometry.md', url: '/core/geometry/', title: 'Geometry & materials' },
      { file: 'core/assets.md', url: '/core/assets/', title: 'Assets & animation' },
      { file: 'core/simulation.md', url: '/core/simulation/', title: 'Simulation layer' },
      { file: 'core/physics.md', url: '/core/physics/', title: 'Collision & physics' },
      { file: 'core/extras.md', url: '/core/extras/', title: 'Particles & audio' },
      { file: 'core/tutorial.md', url: '/core/tutorial/', title: 'Tutorial: first scene', kind: 'tutorial' },
      { file: 'core/session.md', url: '/core/session/', title: 'Assembling an application', kind: 'guide' },
      { file: 'core/editor.md', url: '/core/editor/', title: 'The level editor', kind: 'guide' },
    ],
  },
  {
    section: 'Shooter',
    slug: 'shooter',
    badge: 'genre',
    pages: [
      { file: 'shooter/index.md', url: '/shooter/', title: 'What a shooter adds' },
      { file: 'shooter/tutorial.md', url: '/shooter/tutorial/', title: 'Tutorial: build an FPS', kind: 'tutorial' },
      { file: 'shooter/demo.md', url: '/shooter/demo/', title: 'Playable demo', kind: 'demo' },
    ],
  },
  {
    section: 'Platformer',
    slug: 'platformer',
    badge: 'genre',
    pages: [
      { file: 'platformer/index.md', url: '/platformer/', title: 'What a platformer adds' },
      { file: 'platformer/tutorial.md', url: '/platformer/tutorial/', title: 'Tutorial: build a platformer', kind: 'tutorial' },
      { file: 'platformer/demo.md', url: '/platformer/demo/', title: 'Playable demo', kind: 'demo' },
    ],
  },
  {
    section: 'Racing',
    slug: 'racing',
    badge: 'genre',
    pages: [
      { file: 'racing/index.md', url: '/racing/', title: 'What a racing game adds' },
      { file: 'racing/tutorial.md', url: '/racing/tutorial/', title: 'Tutorial: build a racer', kind: 'tutorial' },
      { file: 'racing/demo.md', url: '/racing/demo/', title: 'Playable demo', kind: 'demo' },
    ],
  },
  {
    section: 'Reference',
    slug: 'reference',
    pages: [
      { file: 'reference/glossary.md', url: '/reference/glossary/', title: 'Glossary' },
      { file: 'reference/tuning.md', url: '/reference/tuning/', title: 'The knobs' },
      { file: 'reference/pitfalls.md', url: '/reference/pitfalls/', title: 'Pitfalls' },
      { file: 'reference/testing.md', url: '/reference/testing/', title: 'Testing' },
      { file: 'reference/packages.md', url: '/reference/packages/', title: 'Package index' },
    ],
  },
];

const flat = NAV.flatMap((group) =>
  group.pages.map((page) => ({ ...page, section: group.section, sectionSlug: group.slug })));

// ---------------------------------------------------------------------------
// Markdown
// ---------------------------------------------------------------------------
const md = new MarkdownIt({
  html: true,
  linkify: true,
  typographer: false,
  highlight(code, lang) {
    if (lang === 'mermaid') return null; // handled by the fence rule below
    if (lang && hljs.getLanguage(lang)) {
      try {
        const out = hljs.highlight(code, { language: lang, ignoreIllegals: true }).value;
        return `<pre class="code" data-lang="${lang}"><code class="hljs">${out}</code></pre>`;
      } catch {
        /* fall through */
      }
    }
    return `<pre class="code"><code class="hljs">${md.utils.escapeHtml(code)}</code></pre>`;
  },
});

md.use(attrs);

const slugs = new Set();
md.use(anchor, {
  level: [2, 3],
  slugify: (text) => {
    const base = text
      .toLowerCase()
      .replace(/[^\wЀ-ӿ]+/g, '-')
      .replace(/^-+|-+$/g, '') || 'section';
    let slug = base;
    let n = 2;
    while (slugs.has(slug)) slug = `${base}-${n++}`;
    slugs.add(slug);
    return slug;
  },
  permalink: anchor.permalink.linkInsideHeader({ symbol: '#', placement: 'after' }),
});

// Mermaid blocks become a <pre class="mermaid">, which the vendored runtime
// picks up on load. Rendering them at build time would need a headless
// browser; the diagrams here are small enough that the runtime cost is a few
// milliseconds and the toolchain stays a single `npm install`.
const defaultFence = md.renderer.rules.fence;
md.renderer.rules.fence = (tokens, idx, options, env, self) => {
  const token = tokens[idx];
  if (token.info.trim() === 'mermaid') {
    return `<div class="diagram"><pre class="mermaid">${md.utils.escapeHtml(token.content)}</pre></div>\n`;
  }
  return defaultFence(tokens, idx, options, env, self);
};

// ---------------------------------------------------------------------------
// Front matter: three lines of `key: value` between `---` fences. A YAML
// parser would be a dependency for a feature nothing here uses.
// ---------------------------------------------------------------------------
function frontMatter(source) {
  if (!source.startsWith('---')) return { data: {}, body: source };
  const end = source.indexOf('\n---', 3);
  if (end === -1) return { data: {}, body: source };
  const head = source.slice(4, end);
  const data = {};
  for (const line of head.split('\n')) {
    const at = line.indexOf(':');
    if (at === -1) continue;
    data[line.slice(0, at).trim()] = line.slice(at + 1).trim();
  }
  return { data, body: source.slice(end + 4).replace(/^\n/, '') };
}

// Attribute order is not fixed: markdown-it-attrs writes `class` and
// markdown-it-anchor writes `id`, and which lands first depends on the
// heading. Matching on `id="` in a fixed position silently dropped every
// numbered tutorial step from the contents.
function tocFrom(html) {
  const out = [];
  const re = /<h([23])\s([^>]*)>(.*?)<a class="header-anchor"/gs;
  let m;
  while ((m = re.exec(html)) !== null) {
    const id = /id="([^"]+)"/.exec(m[2]);
    if (!id) continue;
    out.push({ level: Number(m[1]), id: id[1], text: m[3].replace(/<[^>]+>/g, '').trim() });
  }
  return out;
}

// ---------------------------------------------------------------------------
// Layout
// ---------------------------------------------------------------------------
function sidebar(current) {
  return NAV.map((group) => {
    const items = group.pages.map((page) => {
      const active = page.url === current ? ' class="on"' : '';
      const kind = page.kind ? `<span class="rail-kind">${page.kind}</span>` : '';
      return `<li><a href="${page.url}"${active}>${page.title}${kind}</a></li>`;
    }).join('');
    const badge = group.badge ? `<span class="rail-badge">${group.badge}</span>` : '';
    return `<div class="rail-group" data-group="${group.slug}">
        <p class="rail-title">${group.section}${badge}</p>
        <ul>${items}</ul>
      </div>`;
  }).join('\n');
}

function layout({ page, html, toc, index }) {
  const prev = index > 0 ? flat[index - 1] : null;
  const next = index < flat.length - 1 ? flat[index + 1] : null;
  // Absolute asset paths: the site is served at the domain root, and a
  // relative path would have to be recomputed for the 404 page, which nginx
  // serves from wherever the miss happened.

  const tocHtml = toc.length
    ? `<nav class="toc" aria-label="On this page">
         <p class="toc-title">On this page</p>
         <ul>${toc.map((t) => `<li class="lv${t.level}"><a href="#${t.id}">${t.text}</a></li>`).join('')}</ul>
       </nav>`
    : '<div class="toc"></div>';

  const pager = (prev || next)
    ? `<nav class="pager">
        ${prev ? `<a class="pager-prev" href="${prev.url}"><span>Previous</span><strong>${prev.title}</strong></a>` : '<span></span>'}
        ${next ? `<a class="pager-next" href="${next.url}"><span>Next</span><strong>${next.title}</strong></a>` : '<span></span>'}
       </nav>`
    : '';

  const isHome = page.url === '/';

  return `<!doctype html>
<html lang="en" data-section="${page.sectionSlug}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${page.title === 'flutter3d' ? 'flutter3d — a 3D engine on Flutter GPU' : `${page.title} · flutter3d`}</title>
<meta name="description" content="${(page.description || 'A 3D engine on Flutter GPU, a game layer on top of it, and three games built from both.').replace(/"/g, '&quot;')}">
<link rel="icon" href="/assets/favicon.svg" type="image/svg+xml">
<link rel="stylesheet" href="/assets/site.css">
<!-- Google tag (gtag.js) -->
<script async src="https://www.googletagmanager.com/gtag/js?id=G-6F6VZ4H7CF"></script>
<script>
window.dataLayer = window.dataLayer || [];
function gtag(){dataLayer.push(arguments);}
gtag('js', new Date());
gtag('config', 'G-6F6VZ4H7CF');
</script>
</head>
<body class="${isHome ? 'home' : 'doc'}">
<a class="skip" href="#main">Skip to content</a>

<header class="topbar">
  <a class="brand" href="/">
    <span class="brand-mark" aria-hidden="true"></span>
    <span class="brand-name">flutter3d</span>
  </a>
  <button class="rail-toggle" aria-expanded="false" aria-controls="rail">Menu</button>
  <div class="topbar-meta">
    <span class="chip">Flutter 3.47 · Impeller</span>
    <a class="chip chip-link" href="/reference/packages/">23 packages</a>
    <a class="chip chip-link" href="/docs/">API reference</a>
    ${iconLinks({ github: true })}
  </div>
</header>

<div class="shell">
  <aside class="rail" id="rail">
    ${sidebar(page.url)}
  </aside>

  <main id="main" class="page">
    ${html}
    ${pager}
    <footer class="foot">
      <p>flutter3d documentation. Flutter 3.47.0 stable, Dart 3.12.2.
         Source: <code>${page.file ?? 'site/content'}</code></p>
      <p class="foot-links">
        <a href="${GITHUB}" rel="noopener">GitHub</a> ·
        <a href="/docs/">API reference</a> ·
        <a href="${GITHUB}/blob/main/ARCHITECTURE.md" rel="noopener">Architecture</a>
      </p>
      ${iconLinks()}
      <p class="foot-legal">
        An independent implementation of a 3D engine for Flutter, not affiliated
        with the Flutter team.<br>
        © 2026 Dmitrii Zolotov. Released under the
        <a href="${GITHUB}/blob/main/LICENSE" rel="noopener">MIT licence</a>.
      </p>
    </footer>
  </main>

  ${tocHtml}
</div>

<script src="/assets/mermaid.min.js"></script>
<script src="/assets/site.js"></script>
</body>
</html>
`;
}

// ---------------------------------------------------------------------------
// Build
// ---------------------------------------------------------------------------
if (existsSync(distDir)) rmSync(distDir, { recursive: true });
mkdirSync(distDir, { recursive: true });

let built = 0;
flat.forEach((page, index) => {
  const source = readFileSync(join(contentDir, page.file), 'utf8');
  const { data, body } = frontMatter(source);
  slugs.clear();
  const html = md.render(body);
  const toc = tocFrom(html);
  const full = { ...page, description: data.description };
  const out = layout({ page: full, html, toc, index });

  const target = page.url === '/'
    ? join(distDir, 'index.html')
    : join(distDir, page.url.replace(/^\/|\/$/g, ''), 'index.html');
  mkdirSync(dirname(target), { recursive: true });
  writeFileSync(target, out);
  built += 1;
});

// A 404 that looks like the rest of the site rather than like nginx.
writeFileSync(
  join(distDir, '404.html'),
  layout({
    page: { url: '/404/', title: 'Not here', sectionSlug: 'start', description: 'That page does not exist.' },
    html: `<h1>Not here</h1>
<p>That URL does not match a page. The sidebar has everything there is; these are the usual starting points.</p>
<ul class="cards">
  <li><a href="/"><span class="card-kind">Home</span><h3>flutter3d</h3><p>What the engine is, and how the packages fit together.</p></a></li>
  <li><a href="/quickstart/"><span class="card-kind">15 minutes</span><h3>Quickstart</h3><p>From a fresh checkout to a lit mesh on screen.</p></a></li>
  <li><a href="/reference/packages/"><span class="card-kind">Reference</span><h3>Package index</h3><p>Every package, what it owns, and which barrel to import.</p></a></li>
</ul>`,
    toc: [],
    index: -1,
  }),
);

// Assets, then the mermaid runtime out of node_modules so the page loads
// nothing from a CDN.
cpSync(join(root, 'assets'), join(distDir, 'assets'), { recursive: true });
cpSync(
  join(root, 'node_modules/mermaid/dist/mermaid.min.js'),
  join(distDir, 'assets/mermaid.min.js'),
);

console.log(`built ${built} pages -> ${relative(process.cwd(), distDir)}`);
