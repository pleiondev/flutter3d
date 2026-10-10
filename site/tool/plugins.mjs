// Writes content/reference/plugins.json: the plugin catalogue the site shows.
//
//   node tool/plugins.mjs              ask pub.dev, and read this repository
//   node tool/plugins.mjs --offline    keep the cached community list, read
//                                      this repository again
//
// Two lists. "community" is what pub.dev lists under the `flutter3d-plugin`
// topic, read from each package's own pubspec. "ours" is read from this
// repository's own packages at the time the script runs, not from pub.dev:
// the packages are published from here, and the tree is the version the site
// is built beside.
//
// The build never touches the network. It reads the cache this writes, which
// is committed, so a build on a machine with no network shows the catalogue
// as it was last fetched and says when that was.
import { readFileSync, writeFileSync, readdirSync, existsSync, statSync } from 'node:fs';

/** The catalogue's format version; `tool/build.mjs` refuses a newer one. */
const CATALOGUE_VERSION = 1;
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..');
const repo = join(root, '..');
const cachePath = join(root, 'content', 'reference', 'plugins.json');
const TOPIC = 'flutter3d-plugin';

const args = process.argv.slice(2);
const unknown = args.filter((a) => a !== '--offline');
if (unknown.length) {
  console.error(`unknown argument: ${unknown[0]}\nusage: node tool/plugins.mjs [--offline]`);
  process.exit(64);
}
const offline = args.includes('--offline');

// ------------------------------------------------------------------ pubspecs

// Enough YAML for a pubspec's top-level scalars and the `flutter3d_plugins:`
// block (`flutter3d:` before 1.0, still read until 2.0):
// a nested map of scalars and lists, two-space indented. A real YAML parser
// would be a dependency for six keys.
function scalar(text) {
  const t = text.trim();
  if (t === '') return '';
  if ((t.startsWith('"') && t.endsWith('"')) || (t.startsWith("'") && t.endsWith("'"))) {
    return t.slice(1, -1);
  }
  if (t === 'true') return true;
  if (t === 'false') return false;
  if (t.startsWith('[') && t.endsWith(']')) {
    return t.slice(1, -1).split(',').map((s) => scalar(s)).filter((s) => s !== '');
  }
  return t.replace(/\s+#.*$/, '');
}

function topLevel(pubspec, key) {
  const m = pubspec.match(new RegExp(`^${key}:\\s*(.*)$`, 'm'));
  return m ? scalar(m[1]) : undefined;
}

function flutter3dBlock(pubspec) {
  const lines = pubspec.split('\n');
  const at = (key) => lines.findIndex((l) => new RegExp(`^${key}:\\s*$`).test(l));
  const current = at('flutter3d_plugins');
  const start = current >= 0 ? current : at('flutter3d');
  if (start < 0) return null;
  const block = {};
  let listKey = null;
  for (const line of lines.slice(start + 1)) {
    if (/^\S/.test(line)) break;
    if (/^\s*(#.*)?$/.test(line)) continue;
    const item = line.match(/^\s{4,}-\s*(.*)$/);
    if (item && listKey) {
      block[listKey].push(scalar(item[1]));
      continue;
    }
    const entry = line.match(/^\s{2}([\w-]+):\s*(.*)$/);
    if (!entry) continue;
    const [, key, value] = entry;
    if (value.trim() === '') {
      block[key] = [];
      listKey = key;
    } else {
      block[key] = scalar(value);
      listKey = null;
    }
  }
  return block;
}

const list = (value) => (value == null || value === '' ? [] : Array.isArray(value) ? value : [value]);

// --------------------------------------------------------------------- ours

function pluginApiVersion() {
  const source = readFileSync(
    join(repo, 'packages/flutter3d_plugin_api/lib/src/version.dart'),
    'utf8',
  );
  const m = source.match(/static const PluginApiVersion current = PluginApiVersion\((\d+), (\d+)\)/);
  return m ? `${m[1]}.${m[2]}` : '';
}

// The packages whose plugins are the engine's addons: the game parts and the
// post-processing families. They were `packages/addons/*` until 1.0.0-rc.1
// merged them into these four.
const ADDONS = new Set(['flutter3d_camera', 'flutter3d_game_kit', 'flutter3d_game_ui', 'flutter3d_post']);
const GENRES = new Set(['flutter3d_game_platformer', 'flutter3d_game_racing', 'flutter3d_game_shooter', 'flutter3d_game_strategy']);

function packageDirs() {
  const out = [];
  const dir = join(repo, 'packages');
  for (const name of readdirSync(dir)) {
    const path = join(dir, name);
    if (statSync(path).isDirectory() && existsSync(join(path, 'pubspec.yaml'))) {
      out.push({ name, path, addon: ADDONS.has(name) });
    }
  }
  return out;
}

function dartFiles(dir) {
  if (!existsSync(dir)) return [];
  const out = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) out.push(...dartFiles(path));
    else if (entry.name.endsWith('.dart')) out.push(path);
  }
  return out;
}

// Code without comments: a doc comment showing how to write a plugin is not
// a plugin.
const code = (source) =>
  source.replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/\/\/.*$/gm, '');

function readOurs() {
  const api = pluginApiVersion();
  const packages = packageDirs().map((p) => {
    const pubspec = readFileSync(join(p.path, 'pubspec.yaml'), 'utf8');
    const classes = [];
    for (const file of dartFiles(join(p.path, 'lib'))) {
      const text = code(readFileSync(file, 'utf8'));
      const re = /((?:abstract\s+)?(?:base\s+|final\s+|interface\s+|sealed\s+)*)class\s+(\w+)(?:<[^>{]*>)?\s+extends\s+(\w+)/g;
      for (const m of text.matchAll(re)) {
        // The rest of the file from the declaration, for the manifest's
        // fields: a plugin's manifest is written in its own class, below it.
        const body = text.slice(m.index);
        classes.push({ name: m[2], parent: m[3], abstract: /abstract/.test(m[1]), body });
      }
    }
    return { ...p, pubspec, classes };
  });

  // Every class that is a plugin, by following `extends` up to
  // Flutter3dPlugin across the whole repository.
  const parentOf = new Map();
  for (const p of packages) for (const c of p.classes) parentOf.set(c.name, c.parent);
  const isPlugin = (name, seen = new Set()) => {
    if (name === 'Flutter3dPlugin') return true;
    if (seen.has(name) || !parentOf.has(name)) return false;
    seen.add(name);
    return isPlugin(parentOf.get(name), seen);
  };

  const ours = [];
  for (const p of packages) {
    if (p.name === 'flutter3d_plugin_api') continue;
    const marker = flutter3dBlock(p.pubspec);
    const declared = list(marker?.plugin).map((s) => String(s).split('#').pop());
    const found = p.classes.filter((c) => !c.abstract && isPlugin(c.name));
    const names = [...new Set([...declared, ...found.map((c) => c.name)])].sort();
    if (!names.length) continue;
    const touches = new Set();
    const backends = new Set();
    for (const c of found) {
      const t = c.body.match(/touches:\s*PluginTouches\.(\w+)/);
      if (t) touches.add(t[1]);
      // RenderStepAddon is a view plugin by construction.
      else if (c.parent === 'RenderStepAddon') touches.add('view');
      // A manifest that says nothing touches the simulation: the default.
      else touches.add('simulation');
      const b = c.body.match(/backends:\s*(?:const\s+)?<String>\{([^}]*)\}/);
      if (b) for (const s of b[1].matchAll(/'([^']+)'/g)) backends.add(s[1]);
    }
    ours.push({
      name: p.name,
      version: String(topLevel(p.pubspec, 'version') ?? ''),
      description: String(topLevel(p.pubspec, 'description') ?? ''),
      url: `https://pub.dev/packages/${p.name}`,
      plugins: names,
      api,
      backends: [...backends].sort(),
      touches: [...touches].sort().join(', '),
      kind: GENRES.has(p.name) ? 'genre' : p.addon ? 'addon' : 'other',
      demo: '',
      conformance: false,
    });
  }
  return ours.sort((a, b) => a.name.localeCompare(b.name));
}

// ---------------------------------------------------------------- community

async function json(url) {
  const response = await fetch(url, { headers: { accept: 'application/json' } });
  if (!response.ok) throw new Error(`${url} answered ${response.status}`);
  return response.json();
}

async function readCommunity() {
  const names = [];
  let url = `https://pub.dev/api/search?q=${encodeURIComponent(`topic:${TOPIC}`)}`;
  while (url) {
    const page = await json(url);
    for (const p of page.packages ?? []) names.push(p.package);
    url = page.next ?? null;
  }
  const out = [];
  for (const name of names) {
    const info = await json(`https://pub.dev/api/packages/${encodeURIComponent(name)}`);
    const pubspec = info.latest?.pubspec ?? {};
    const block = pubspec.flutter3d_plugins ?? pubspec.flutter3d ?? {};
    let publisher = '';
    try {
      publisher = (await json(`https://pub.dev/api/packages/${encodeURIComponent(name)}/publisher`)).publisherId ?? '';
    } catch {
      publisher = '';
    }
    out.push({
      name,
      version: String(info.latest?.version ?? ''),
      description: String(pubspec.description ?? ''),
      url: `https://pub.dev/packages/${name}`,
      publisher,
      plugins: list(block.plugin).map((s) => String(s).split('#').pop()),
      api: block.api == null ? '' : String(block.api),
      backends: list(block.backends).map(String),
      touches: block.touches == null ? '' : String(block.touches),
      kind: 'community',
      demo: typeof block.demo === 'string' ? block.demo : '',
      // The suite version the package says it passes: `conformant@1.0` in
      // its pubspec, `true` read as the first suite.
      conformance:
        block.conformance === true
          ? '1.0'
          : typeof block.conformance === 'string'
            ? String(block.conformance).replace(/^conformant@/, '')
            : false,
    });
  }
  return out.sort((a, b) => a.name.localeCompare(b.name));
}

// --------------------------------------------------------------------- main

const cached = existsSync(cachePath) ? JSON.parse(readFileSync(cachePath, 'utf8')) : null;
let community = cached?.community ?? [];
let fetched = cached?.fetched ?? null;

if (offline) {
  console.log('offline: kept the cached community list' + (fetched ? ` from ${fetched}` : ' (there is none)'));
} else {
  try {
    community = await readCommunity();
    fetched = new Date().toISOString();
    console.log(`pub.dev lists ${community.length} package${community.length === 1 ? '' : 's'} under topic:${TOPIC}`);
  } catch (error) {
    console.log(`pub.dev did not answer (${error.message}); kept the cached community list`);
  }
}

const ours = readOurs();
writeFileSync(
  cachePath,
  // The format envelope every flutter3d JSON document carries: the build
  // refuses a newer catalogue rather than misreading it.
  `${JSON.stringify(
    {
      format: 'f3d.plugin-catalogue',
      version: CATALOGUE_VERSION,
      requires: [],
      generator: 'flutter3d site/tool/plugins.mjs',
      fetched,
      community,
      ours,
    },
    null,
    2,
  )}\n`,
);
console.log(`wrote ${cachePath}: ${ours.length} of ours, ${community.length} from the community`);
