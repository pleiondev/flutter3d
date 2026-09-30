// The showcase's guides and source, as pages of this site.
//
// **This file reads what `apps/flutter3d_showcase/tool/showcase_bundle.dart`
// wrote and nothing else.** It never opens a page file or a guide of the app
// itself. The bundle is written with the app's own functions (`regions.dart`,
// `tutorial.dart`), so a guide here quotes the lines the app's Step by step tab
// quotes, and a region that does not exist has already stopped the bundle
// before any page below is built.
//
// Three kinds of page come out of it, all under `/showcase/`, which is also
// where the live app is served from:
//
//     /showcase/learn/            every guide, by category
//     /showcase/learn/<id>/       one guide, with its version tag
//     /showcase/source/<id>/      the file that runs, highlighted, one anchor
//                                 a line and one a region
//
// The app itself is copied in afterwards by `tool/showcase.sh`, and skips
// `learn/` and `source/` so it cannot delete what is written here.

import hljs from 'highlight.js';
import { copyFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';

const SLUG = 'showcase';

/** The bundle, or null when it has not been generated. */
export function readBundle(root) {
  const dir = join(root, '.generated', 'showcase');
  const file = join(dir, 'manifest.json');
  if (!existsSync(file)) return null;
  return { dir, manifest: JSON.parse(readFileSync(file, 'utf8')) };
}

const esc = (text) =>
  text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

const sinceLabel = (feature) =>
  feature.approximate ? `since ${feature.since} or earlier` : `since ${feature.since}`;

/** The markdown that replaces `{{showcase-index}}` on the guides index page. */
export function indexMarkdown(bundle) {
  if (!bundle) {
    return [
      '> **Note.** The guides are generated from the showcase app. Run',
      '> `dart run tool/showcase_bundle.dart --out ../../site/.generated/showcase` in',
      '> `apps/flutter3d_showcase` first.',
    ].join('\n');
  }
  const { manifest } = bundle;
  const lines = [];
  for (const category of manifest.categories) {
    const inside = manifest.features.filter((f) => f.category === category.dir);
    if (inside.length === 0) continue;
    lines.push(`## ${category.title}`, '');
    for (const f of inside) {
      lines.push(`- [${f.title}](/showcase/learn/${f.id}/) (${sinceLabel(f)}): ${f.summary}`);
    }
    lines.push('');
  }
  return lines.join('\n');
}

/** `a` against `b` as `major.minor.patch`, numerically: 0.10.0 after 0.9.0. */
export function compareVersions(a, b) {
  const parts = (v) => v.split(/[+-]/)[0].split('.').map((p) => Number.parseInt(p, 10) || 0);
  const [x, y] = [parts(a), parts(b)];
  for (let i = 0; i < Math.max(x.length, y.length); i++) {
    const d = (x[i] ?? 0) - (y[i] ?? 0);
    if (d !== 0) return d;
  }
  return 0;
}

/**
 * The markdown that replaces `{{changelog}}`: every release, newest first, with
 * the showcase pages it changed and the ones it added.
 *
 * **Read from the catalog, not written by hand.** A page is listed as new
 * under its `since`, and as changed under each of its `changes`, and the
 * catalog test holds both to the CHANGELOG they quote. So this list cannot name
 * a page for news the record does not have, and a new page cannot be missing
 * from it.
 */
export function changelogMarkdown(bundle, packages = []) {
  if (!bundle) return indexMarkdown(null);
  const releases = new Map();
  const release = (version) => {
    if (!releases.has(version)) releases.set(version, { changed: [], added: [] });
    return releases.get(version);
  };
  for (const f of bundle.manifest.features) {
    release(f.since).added.push(f);
    for (const c of f.changes ?? []) release(c.version).changed.push({ f, c });
  }
  // A package with no showcase pages still has releases worth listing.
  for (const p of packages) {
    for (const version of p.leads.keys()) release(version);
  }
  const demo = (f) => `[live demo](/showcase/#/p/${f.id})`;
  const lines = [];
  for (const version of [...releases.keys()].sort((a, b) => compareVersions(b, a))) {
    const { changed, added } = releases.get(version);
    lines.push(`## ${version}`, '');
    if (changed.length) {
      lines.push('**Changed**', '');
      for (const { f, c } of changed) {
        lines.push(`- [${f.title}](/showcase/learn/${f.id}/): ${c.note} (${demo(f)})`);
      }
      lines.push('');
    }
    if (added.length) {
      // An approximate tag is a bound, so the page says so where it is listed.
      lines.push('**New in the showcase**', '');
      for (const f of added) {
        const bound = f.approximate ? ' (here or earlier)' : '';
        lines.push(`- [${f.title}](/showcase/learn/${f.id}/)${bound}: ${f.summary} (${demo(f)})`);
      }
      lines.push('');
    }
    for (const p of packages) {
      const leads = p.leads.get(version);
      if (!leads?.length) continue;
      // pub.dev anchors a CHANGELOG heading by its digits: `## 0.8.3` is #083.
      const record = `https://pub.dev/packages/${p.name}/changelog#${version.replace(/\D/g, '')}`;
      lines.push(`**${p.title}** ([${p.name} ${version}](${record}))`, '');
      const items = leads.map((lead) => `- ${lead}`);
      // A long release folds, so the page's releases stay a list you can scan.
      if (items.length > kFoldAfter) {
        lines.push(`<details><summary>${items.length} changes</summary>`, '', ...items, '', '</details>', '');
      } else {
        lines.push(...items, '');
      }
    }
  }
  return lines.join('\n');
}

/** How many entries a package's release lists before it folds. */
const kFoldAfter = 8;

/**
 * A package CHANGELOG as `version → the lead of each entry`, newest first.
 *
 * **The lead is the entry's own bold claim**, the sentence every entry in this
 * repository opens with ("**A host that goes lets go of the game.**"), so the
 * page quotes the record rather than summarising it. Entries are paragraphs or
 * `-`/`*` list items; one that opens without a bold claim is skipped rather
 * than guessed at.
 */
export function changelogLeads(text) {
  const leads = new Map();
  let version = null;
  let block = [];
  const flush = () => {
    const entry = block.join(' ').replace(/\s+/g, ' ').trim();
    block = [];
    if (!version) return;
    const lead = entry.match(/^(?:[-*]\s+)?\*\*(.+?)\*\*/)?.[1];
    if (lead) leads.get(version).push(lead.trim().replace(/[.:]$/, ''));
  };
  for (const line of text.split('\n')) {
    const heading = line.match(/^##\s+(\d+\.\d+\.\d+\S*)/);
    if (heading) {
      flush();
      version = heading[1];
      leads.set(version, []);
    } else if (line.trim() === '') {
      flush();
    } else {
      if (/^[-*]\s/.test(line)) flush();
      block.push(line.trim());
    }
  }
  flush();
  return leads;
}

/**
 * Highlighted HTML cut into lines, each still well formed.
 *
 * highlight.js can leave a span open across a newline (a block comment, a
 * multi-line string). A line wrapped around such a cut would have an unclosed
 * tag, so every line closes what is open at its end and the next one reopens it.
 */
export function splitLines(html) {
  const lines = [];
  let current = '';
  const open = [];
  for (const part of html.split(/(<span[^>]*>|<\/span>|\n)/)) {
    if (part === '\n') {
      lines.push(current + '</span>'.repeat(open.length));
      current = open.join('');
    } else if (part.startsWith('<span')) {
      open.push(part);
      current += part;
    } else if (part === '</span>') {
      open.pop();
      current += part;
    } else {
      current += part;
    }
  }
  lines.push(current + '</span>'.repeat(open.length));
  return lines;
}

function sourceHtml(feature, source) {
  const highlighted = hljs.highlight(source.replace(/\n$/, ''), {
    language: 'dart',
    ignoreIllegals: true,
  }).value;
  const marks = new Map(feature.regions.map((r) => [r.line, r]));
  const rows = splitLines(highlighted).map((line, i) => {
    const n = i + 1;
    const region = marks.get(n);
    const anchor = region ? `<span id="region-${region.name}"></span>` : '';
    return `<div class="src-line" id="L${n}">${anchor}<a class="src-no" href="#L${n}">${n}</a>` +
      `<span class="src-code">${line || ' '}</span></div>`;
  });
  return `<div class="src-file hljs" data-lang="dart">${rows.join('')}</div>`;
}

function chips(feature) {
  return `<p class="showcase-meta">
  <span class="chip" title="${esc(`${feature.evidenceFile}: ${feature.evidence}`)}">${sinceLabel(feature)}</span>
  <span class="chip">${esc(feature.categoryTitle)}</span>
</p>`;
}

function links(feature, current) {
  const parts = [
    `<a href="/showcase/#/p/${feature.id}">Open the live demo</a>`,
    current === 'learn'
      ? `<a href="/showcase/source/${feature.id}/">Read the source</a>`
      : `<a href="/showcase/learn/${feature.id}/">Read the guide</a>`,
    `<a href="__GITHUB__/blob/main/${feature.github}" rel="noopener">View on GitHub</a>`,
  ];
  return `<p class="showcase-links">${parts.join(' · ')}</p>`;
}

/** Previous and next guide, in catalog order, as the site's pager markup. */
function pagerFor(features, index, kind) {
  const link = (f, label, cls) =>
    `<a class="${cls}" href="/showcase/${kind}/${f.id}/"><span>${label}</span><strong>${esc(f.title)}</strong></a>`;
  const prev = index > 0 ? features[index - 1] : null;
  const next = index < features.length - 1 ? features[index + 1] : null;
  return `<nav class="pager">
    ${prev ? link(prev, 'Previous', 'pager-prev') : '<span></span>'}
    ${next ? link(next, 'Next', 'pager-next') : '<span></span>'}
   </nav>`;
}

/**
 * Writes the guide and source page of every feature.
 *
 * `render(markdown)` and `layout(...)` are the site's own, passed in so these
 * pages are made by the same code as the rest and cannot drift from them.
 */
export function buildShowcasePages({ bundle, root, distDir, render, layout, github }) {
  const { dir, manifest } = bundle;
  const features = manifest.features;
  const written = [];
  const shots = join(root, '..', 'apps', 'flutter3d_showcase', 'test', 'goldens');

  const write = (url, html) => {
    const target = join(distDir, url.replace(/^\/|\/$/g, ''), 'index.html');
    mkdirSync(dirname(target), { recursive: true });
    writeFileSync(target, html);
    written.push(url);
  };

  features.forEach((feature, index) => {
    const guideFile = join(dir, 'learn', `${feature.id}.md`);
    let guide = readFileSync(guideFile, 'utf8');

    // The two directives the bundle leaves for the site: a link to the live
    // page, and the picture of it when one has been recorded.
    guide = guide.replace(/^\{\{\s*demo\s*\}\}\s*$/gm,
      `[Open the live demo](/showcase/#/p/${feature.id})`);
    const shot = join(shots, `${feature.id}.png`);
    guide = guide.replace(/^\{\{\s*shot\s*\}\}\s*$/gm, () => {
      if (!existsSync(shot)) return '';
      const to = join(distDir, 'showcase', 'learn', 'img', `${feature.id}.png`);
      mkdirSync(dirname(to), { recursive: true });
      copyFileSync(shot, to);
      return `![${feature.title}](/showcase/learn/img/${feature.id}.png)`;
    });

    const rendered = render(guide);
    const head = chips(feature) + links(feature, 'learn').replace('__GITHUB__', github);
    const html = rendered.html.replace('</h1>', `</h1>\n${head}`);
    const url = `/showcase/learn/${feature.id}/`;
    write(url, layout({
      page: {
        url,
        title: feature.title,
        description: feature.summary,
        sectionSlug: 'core',
        file: `apps/flutter3d_showcase/${feature.pageFile}`,
      },
      html,
      toc: rendered.toc,
      index: -1,
      pager: pagerFor(features, index, 'learn'),
    }));

    const source = readFileSync(join(dir, 'src', `${feature.id}.dart`), 'utf8');
    const regionList = feature.regions.length
      ? `<p class="showcase-regions">Regions the guide quotes: ${feature.regions
          .map((r) => `<a href="#region-${r.name}">${esc(r.name)}</a> (line ${r.line})`)
          .join(', ')}.</p>`
      : '';
    const sourceUrl = `/showcase/source/${feature.id}/`;
    write(sourceUrl, layout({
      page: {
        url: sourceUrl,
        title: `${feature.title}, source`,
        description: `The Dart file that runs the ${feature.title} page of the showcase.`,
        sectionSlug: 'core',
        file: `apps/flutter3d_showcase/${feature.pageFile}`,
      },
      html: `<h1>${esc(feature.title)}: the source</h1>\n${chips(feature)}` +
        links(feature, 'source').replace('__GITHUB__', github) +
        regionList + sourceHtml(feature, source),
      toc: [],
      index: -1,
      pager: pagerFor(features, index, 'source'),
    }));
  });
  return written;
}
