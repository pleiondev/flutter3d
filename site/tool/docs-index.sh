#!/usr/bin/env bash
# Writes site/docs-dist/index.html from whatever package trees are there.
#
# Split out of build-docs.sh so the landing page can be changed without a
# twenty-two package dartdoc run behind it. Called at the end of that script;
# safe to run on its own.
#
# The list comes from the directories on disk rather than from a list in this
# file, because a hand-kept list is what goes stale the day somebody adds a
# package — and each line is the package's pubspec description, which is already
# the sentence pub.dev would show, so there is no second summary to keep true.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo="$(cd "$here/.." && pwd)"
out="$here/docs-dist"
github='https://github.com/pleiondev/flutter3d'

rows=''
count=0
for tree in "$out"/*/; do
  name="$(basename "$tree")"
  [ -f "$repo/packages/$name/pubspec.yaml" ] || continue
  description="$(
    python3 - "$repo/packages/$name/pubspec.yaml" <<'PY'
import re, sys
text = open(sys.argv[1], encoding='utf-8').read()
match = re.search(r'^description:\s*(?:>-\s*\n((?:[ \t]+.*\n)+)|(.*)$)', text, re.M)
raw = (match.group(1) or match.group(2) or '') if match else ''
out = ' '.join(raw.split()).strip().strip('"')
print(out.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;'))
PY
  )"
  rows+="    <li><a href=\"/docs/$name/\"><code>$name</code><span>$description</span></a></li>"$'\n'
  count=$((count + 1))
done

cat > "$out/index.html" <<HTML
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>API reference · flutter3d</title>
<meta name="description" content="Generated Dart API documentation for every flutter3d package.">
<link rel="icon" href="/assets/favicon.svg" type="image/svg+xml">
<link rel="stylesheet" href="/assets/site.css">
<style>
  /* Deliberately not the site's three-column shell. This page has no sidebar
     and no table of contents, and borrowing a grid built for both leaves the
     content depending on rules about columns that are not here. */
  .api-shell { max-width: 940px; margin: 0 auto; padding: 40px 22px 80px; }
  .api-shell h1 { margin: 0 0 .6rem; }
  .api-list { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
              gap: 14px; margin: 2rem 0 2.6rem; padding: 0; list-style: none; }
  .api-list li { margin: 0; }
  .api-list a { display: block; height: 100%; padding: 16px 17px;
                background: var(--surface); border: 1px solid var(--border);
                border-radius: var(--radius); text-decoration: none; color: var(--text);
                transition: border-color .14s, transform .14s; }
  .api-list a:hover { border-color: var(--amber-dim); transform: translateY(-2px); }
  .api-list code { display: block; margin-bottom: 6px; padding: 0; background: none;
                   font: 600 15px/1.3 var(--mono); letter-spacing: -.01em; color: var(--amber); }
  .api-list span { display: block; font-size: 14px; line-height: 1.55; color: var(--muted); }
</style>
</head>
<body class="doc">
<header class="topbar">
  <a class="brand" href="/">
    <span class="brand-mark" aria-hidden="true"></span>
    <span class="brand-name">flutter3d</span>
  </a>
  <div class="topbar-meta">
    <a class="chip chip-link" href="/">Documentation</a>
    <a class="chip chip-link" href="/reference/packages/">What each package is for</a>
    <a class="chip chip-link" href="$github" rel="noopener">GitHub</a>
  </div>
</header>

<main class="api-shell">
  <h1>API reference</h1>
  <p class="lead">Generated from the source with <code>dart doc</code>, one tree per
     package. For what a package is <em>for</em> rather than what it exports, start
     at the <a href="/reference/packages/">package index</a>; for how the pieces fit
     together, read
     <a href="$github/blob/main/ARCHITECTURE.md" rel="noopener">ARCHITECTURE.md</a>.</p>

  <ul class="api-list">
$rows  </ul>

  <footer class="foot">
    <p class="foot-legal">
      An independent implementation of a 3D engine for Flutter, not affiliated
      with the Flutter team.<br>
      &copy; 2026 Dmitrii Zolotov. Released under the
      <a href="$github/blob/main/LICENSE" rel="noopener">MIT licence</a>.
    </p>
  </footer>
</main>

<script src="/assets/site.js"></script>
</body>
</html>
HTML

echo "index lists $count packages"
