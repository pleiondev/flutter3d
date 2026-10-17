// The road to 1.0 on one page: every row of the plan with its status, the
// goals the candidate is tagged on, and what the tree says about itself today.
//
//   dart run tool/progress.dart [--out dir] [--no-structure]
//
// Reads `tasks/1.0-rc1-plan.md` and `tasks/1.0-api-migrations.md` for the
// rows and their text, `tasks/1.0-progress.json` for each row's status, and
// the tree itself for the numbers (rules, tests, deprecations, sealed types,
// the migration table, git). Writes one self-contained `index.html`; nothing
// on the page talks to a server. `tool/progress.sh` builds and publishes it.
import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final root = _repositoryRoot();
  final out = Directory(_option(args, '--out') ?? '${root.path}/build/progress')
    ..createSync(recursive: true);

  final status =
      jsonDecode(
            File('${root.path}/tasks/1.0-progress.json').readAsStringSync(),
          )
          as Map<String, Object?>;
  final rows = (status['rows']! as Map).cast<String, String>();
  final notes = (status['notes'] as Map? ?? const {}).cast<String, String>();
  final goals = (status['goals'] as Map? ?? const {}).cast<String, String>();

  final plan = File('${root.path}/tasks/1.0-rc1-plan.md').readAsStringSync();
  final migrations = File(
    '${root.path}/tasks/1.0-api-migrations.md',
  ).readAsStringSync();

  final sections = <_Section>[
    ..._sections(plan),
    ..._sections(migrations).where((s) => s.key == 'M'),
  ];
  // Wave M runs before wave 2; the page shows the work in the order it goes.
  final m = sections.indexWhere((s) => s.key == 'M');
  if (m >= 0) {
    final wave = sections.removeAt(m);
    final two = sections.indexWhere((s) => s.key == '2');
    sections.insert(two < 0 ? sections.length : two, wave);
  }

  final metrics = _metrics(
    root,
    runStructure: !args.contains('--no-structure'),
  );
  final proofs = _proofs(plan);
  final html = _page(
    sections: sections,
    rows: rows,
    notes: notes,
    goals: goals,
    proofs: proofs,
    metrics: metrics,
    updated: status['updated'] as String? ?? '',
  );
  File('${out.path}/index.html').writeAsStringSync(html);
  stdout.writeln('wrote ${out.path}/index.html');
}

// ------------------------------------------------------------------- reading

final class _Row {
  _Row(this.id, this.text, this.size);

  final String id;
  final String text;
  final String size;
}

final class _Section {
  _Section(this.key, this.title, this.candidate);

  final String key;
  final String title;
  final String candidate;
  final List<_Row> rows = <_Row>[];
  final List<String> status = <String>[];
}

/// The waves and steps of a plan document, each with its table's rows and
/// any `**Status (…)**` paragraphs written under it.
List<_Section> _sections(String text) {
  final heading = RegExp(r'^#{2,3} (Wave|Step) ([\w.]+)\b(.*)$');
  final found = <_Section>[];
  _Section? current;
  final lines = const LineSplitter().convert(text);
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final match = heading.firstMatch(line);
    if (match != null) {
      final key = match.group(2)!;
      final title = line.replaceFirst(RegExp(r'^#+ '), '');
      current = _Section(key, title, _candidate(key, title));
      found.add(current);
      continue;
    }
    if (line.startsWith('## ')) {
      current = null;
      continue;
    }
    if (current == null) continue;
    if (line.startsWith('|') && !line.startsWith('|---')) {
      final cells = _cells(line);
      if (cells.length < 3) continue;
      final id = _plain(cells[0]);
      if (id == '#' || id == 'Agent' || id.isEmpty) continue;
      // `| # | Item | Owner | Size |` and `| Agent | Owns | Items | Size |`.
      final text = cells.length >= 4 && cells[1].length < cells[2].length
          ? cells[2]
          : cells[1];
      current.rows.add(_Row(id, text, _plain(cells.last)));
      continue;
    }
    if (line.startsWith('**Status')) {
      final paragraph = <String>[line];
      while (i + 1 < lines.length && lines[i + 1].trim().isNotEmpty) {
        paragraph.add(lines[++i]);
      }
      current.status.add(paragraph.join('\n'));
    }
  }
  return found.where((s) => s.rows.isNotEmpty).toList();
}

String _candidate(String key, String title) {
  if (title.contains('rc.2') || key == '4.2' || key == '4.5') return 'rc.2';
  if (key == '5') return 'rc.1 + rc.2';
  return 'rc.1';
}

/// A table line's cells, splitting on `|` outside backticks.
List<String> _cells(String line) {
  final cells = <String>[];
  final cell = StringBuffer();
  var code = false;
  for (final char in line.trim().split('')) {
    if (char == '`') code = !code;
    if (char == '|' && !code) {
      cells.add(cell.toString().trim());
      cell.clear();
    } else {
      cell.write(char);
    }
  }
  return cells.where((c) => c.isNotEmpty).toList();
}

String _plain(String cell) =>
    cell.replaceAll('*', '').replaceAll('`', '').trim();

/// P1–P5 and the nightly, with their thresholds, from the plan's own list.
List<(String, String)> _proofs(String plan) {
  final proofs = <(String, String)>[];
  final item = RegExp(r'^\d+\. \*\*(P\d|Nightly)\*\* (.*)$');
  final lines = const LineSplitter().convert(plan);
  for (var i = 0; i < lines.length; i++) {
    final match = item.firstMatch(lines[i]);
    if (match == null) continue;
    final text = StringBuffer(match.group(2)!);
    while (i + 1 < lines.length && lines[i + 1].startsWith('   ')) {
      text.write(' ${lines[++i].trim()}');
    }
    proofs.add((match.group(1)!, text.toString()));
  }
  for (final audience in const ['Games', 'Twins', 'Laboratories']) {
    final at = plan.indexOf('- $audience:');
    if (at < 0) continue;
    final end = plan.indexOf('\n- ', at + 2);
    final stop = plan.indexOf('\n\n', at);
    final until = [end, stop].where((e) => e > 0).fold(plan.length, _min);
    proofs.add((
      audience,
      plan.substring(at + audience.length + 3, until).replaceAll('\n', ' '),
    ));
  }
  return proofs;
}

int _min(int a, int b) => a < b ? a : b;

// ------------------------------------------------------------------- the tree

typedef _Metric = ({String label, String value, String hint, bool good});

List<_Metric> _metrics(Directory root, {required bool runStructure}) {
  String git(List<String> args) =>
      (Process.runSync('git', args, workingDirectory: root.path).stdout
              as String)
          .trim();

  int countIn(String dir, RegExp pattern, {String suffix = '.dart'}) =>
      Directory('${root.path}/$dir').existsSync()
      ? Directory('${root.path}/$dir')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith(suffix))
            .where((f) => !f.path.contains('/.dart_tool/'))
            .map((f) => pattern.allMatches(f.readAsStringSync()).length)
            .fold(0, (a, b) => a + b)
      : 0;

  final libs = Directory('${root.path}/packages')
      .listSync()
      .whereType<Directory>()
      .map(
        (d) =>
            'packages/${d.uri.pathSegments[d.uri.pathSegments.length - 2]}/lib',
      );
  final deprecated = libs
      .map((d) => countIn(d, RegExp(r'^\s*@Deprecated\(', multiLine: true)))
      .fold(0, (a, b) => a + b);
  final sealed = countIn(
    'packages',
    RegExp(r'^\s*sealed class ', multiLine: true),
    suffix: '.api',
  );
  final enums = countIn(
    'packages',
    RegExp(r'^\s*enum ', multiLine: true),
    suffix: '.api',
  );

  final table = File(
    '${root.path}/packages/flutter3d_build/lib/migrations/0.8_to_1.0.yaml',
  ).readAsStringSync();
  final kinds = <String, int>{};
  for (final match in RegExp(
    r'^    kind: (\w+)',
    multiLine: true,
  ).allMatches(table)) {
    kinds.update(match.group(1)!, (n) => n + 1, ifAbsent: () => 1);
  }
  final entries = kinds.values.fold(0, (a, b) => a + b);

  final readme = File('${root.path}/README.md').readAsStringSync();
  final tests = RegExp(r'(\d+) tests across').firstMatch(readme)?.group(1);

  final dirty = git([
    'status',
    '--porcelain',
  ]).split('\n').where((l) => l.isNotEmpty).length;
  final ahead = git(['rev-list', '--count', 'origin/main..HEAD']);

  var rules = '—';
  var rulesGood = true;
  var rulesHint = 'not run';
  if (runStructure) {
    final run = Process.runSync('dart', [
      'run',
      'tool/structure.dart',
    ], workingDirectory: root.path);
    final text = '${run.stdout}';
    final total = RegExp(r'^(\d+) rules', multiLine: true).firstMatch(text);
    final broken = RegExp(
      r'^(\d+) of (\d+) rules broken',
      multiLine: true,
    ).firstMatch(text);
    final failing = RegExp(
      r'^✗ (.*)$',
      multiLine: true,
    ).allMatches(text).map((m) => m.group(1)!).toList();
    if (broken != null) {
      rules =
          '${broken.group(2)! == '' ? '' : int.parse(broken.group(2)!) - int.parse(broken.group(1)!)}/${broken.group(2)}';
      rulesGood = false;
      rulesHint = 'red: ${failing.join('; ')}';
    } else if (total != null) {
      rules = '${total.group(1)}/${total.group(1)}';
      rulesHint = 'all held';
    }
  }

  return <_Metric>[
    (label: 'Structure rules', value: rules, hint: rulesHint, good: rulesGood),
    (
      label: 'Tests',
      value: tests ?? '—',
      hint: 'as README states it; a rule holds it to the tree',
      good: true,
    ),
    (
      label: '@Deprecated',
      value: '$deprecated',
      hint: 'a major release deprecates nothing (D12): goes to 0 in step 2.0',
      good: deprecated == 0,
    ),
    (
      label: 'sealed in the API',
      value: '$sealed',
      hint: 'only an allowlist with reasons (D8), wave 2',
      good: false,
    ),
    (
      label: 'enum in the API',
      value: '$enums',
      hint: 'open classes where the set grows (A5), wave 2',
      good: false,
    ),
    (
      label: 'Migration by hand',
      value: '${kinds['manual'] ?? 0}',
      hint:
          '$entries entries; ${kinds['internal'] ?? 0} internal, '
          '${(kinds['rename'] ?? 0) + (kinds['moved'] ?? 0) + (kinds['parameters'] ?? 0)} for dart fix',
      good: true,
    ),
    (
      label: 'Uncommitted',
      value: '$dirty',
      hint: 'files in the working tree',
      good: dirty == 0,
    ),
    (
      label: 'Branch',
      value: git(['rev-parse', '--abbrev-ref', 'HEAD']),
      hint:
          '${git(['rev-parse', '--short', 'HEAD'])}, $ahead commits past main',
      good: true,
    ),
  ];
}

// ------------------------------------------------------------------- the page

const _labels = <String, String>{
  'done': 'done',
  'partial': 'partial',
  'active': 'in progress',
  'blocked': 'blocked',
  'todo': 'to do',
};

String _page({
  required List<_Section> sections,
  required Map<String, String> rows,
  required Map<String, String> notes,
  required Map<String, String> goals,
  required List<(String, String)> proofs,
  required List<_Metric> metrics,
  required String updated,
}) {
  String statusOf(_Section s, _Row r) => rows['${s.key}/${r.id}'] ?? 'todo';

  double share(Iterable<_Section> of) {
    var done = 0.0;
    var all = 0;
    for (final s in of) {
      for (final r in s.rows) {
        all++;
        final st = statusOf(s, r);
        done += st == 'done'
            ? 1
            : (st == 'partial' || st == 'active' ? 0.5 : 0);
      }
    }
    return all == 0 ? 0 : done / all;
  }

  final rc1 = share(sections.where((s) => s.candidate.startsWith('rc.1')));
  final rc2 = share(sections.where((s) => s.candidate == 'rc.2'));
  final goalsDone = goals.values.where((g) => g == 'done').length;

  final html = StringBuffer();
  html.write(_head);
  html.write('''
<header>
  <div>
    <h1>flutter3d → 1.0</h1>
    <p class="sub">rc.1 is reliability and the API's shape; rc.2 is breadth;
    1.0.0 follows rc.2. Status as of ${_esc(updated)}, page built
    ${_esc(DateTime.now().toUtc().toIso8601String().substring(0, 16))} UTC.</p>
  </div>
</header>
<section class="kpis">
  ${_kpi('rc.1 rows', '${(rc1 * 100).round()}%', rc1)}
  ${_kpi('rc.2 rows', '${(rc2 * 100).round()}%', rc2)}
  ${_kpi('Goals proven', '$goalsDone/${goals.length}', goals.isEmpty ? 0 : goalsDone / goals.length)}
''');
  for (final m in metrics) {
    html.write('''
  <div class="kpi ${m.good ? '' : 'warn'}" title="${_esc(m.hint)}">
    <div class="label">${_esc(m.label)}</div>
    <div class="value">${_esc(m.value)}</div>
    <div class="hint">${_esc(m.hint)}</div>
  </div>''');
  }
  html.write('</section>');

  // Filled from live.json, which changes without a rebuild: the step the
  // work is on, who is on it since when, and what happened last.
  html.write('''
<h2>Now <span id="live-age" class="age"></span></h2>
<section id="now" class="now"><div class="empty">Waiting for live.json…</div></section>
''');

  html.write('<h2>Goals the tag is gated on</h2><section class="goals">');
  for (final (id, text) in proofs) {
    final st = goals[id] ?? 'todo';
    html.write('''
  <details class="goal $st">
    <summary><span class="chip $st">${_labels[st]}</span><b>${_esc(id)}</b>
    <span class="gist">${_inline(_gist(text))}</span></summary>
    <p>${_inline(text)}</p>
  </details>''');
  }
  html.write('</section>');

  html.write('<h2>Waves</h2><section class="waves">');
  for (final s in sections) {
    final total = s.rows.length;
    final done = s.rows.where((r) => statusOf(s, r) == 'done').length;
    final active = s.rows
        .where((r) => const ['active', 'partial'].contains(statusOf(s, r)))
        .length;
    final state = done == total
        ? 'done'
        : (done + active > 0 ? 'active' : 'todo');
    html.write('''
  <details class="wave $state" ${state == 'active' ? 'open' : ''}>
    <summary>
      <span class="cand">${_esc(s.candidate)}</span>
      <span class="title">${_inline(s.title)}</span>
      <span class="count">$done/$total</span>
      <span class="bar"><i style="width:${total == 0 ? 0 : (100 * done / total).round()}%"></i><i class="half" style="width:${total == 0 ? 0 : (100 * active / total).round()}%"></i></span>
    </summary>
    <table>''');
    for (final r in s.rows) {
      final st = statusOf(s, r);
      final note = notes['${s.key}/${r.id}'];
      html.write('''
      <tr class="$st">
        <td class="id">${_esc(r.id)}</td>
        <td><span class="chip $st">${_labels[st]}</span></td>
        <td class="text"><details><summary>${_inline(_gist(r.text))}</summary><p>${_inline(r.text)}</p></details>${note == null ? '' : '<div class="note">${_inline(note)}</div>'}</td>
        <td class="size">${_esc(r.size)}</td>
      </tr>''');
    }
    html.write('</table>');
    for (final p in s.status) {
      html.write('<div class="status">${_block(p)}</div>');
    }
    html.write('</details>');
  }
  html.write('</section>');
  html.write(
    '<footer>Built by <code>tool/progress.dart</code> from '
    '<code>tasks/1.0-rc1-plan.md</code>, <code>tasks/1.0-api-migrations.md</code> '
    'and <code>tasks/1.0-progress.json</code>; the Now panel from '
    '<code>live.json</code>, read every 10 s.</footer></main>'
    '<script>$_liveScript</script></body></html>',
  );
  return html.toString();
}

String _kpi(String label, String value, double share) =>
    '''
  <div class="kpi">
    <div class="label">${_esc(label)}</div>
    <div class="value">${_esc(value)}</div>
    <div class="bar"><i style="width:${(share * 100).round()}%"></i></div>
  </div>''';

/// The first sentence, or the first 140 characters, of a cell.
String _gist(String text) {
  final plain = text.trim();
  final stop = RegExp(r'[.;:](\s|$)').firstMatch(plain);
  final end = stop == null ? plain.length : stop.start + 1;
  final cut = end > 160 ? 157 : end;
  return cut < plain.length && cut == 157
      ? '${plain.substring(0, cut)}…'
      : plain.substring(0, end);
}

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// Code spans and bold, from the plan's own Markdown.
String _inline(String s) => _esc(s)
    .replaceAllMapped(RegExp(r'`([^`]+)`'), (m) => '<code>${m[1]}</code>')
    .replaceAllMapped(RegExp(r'\*\*([^*]+)\*\*'), (m) => '<b>${m[1]}</b>')
    .replaceAllMapped(RegExp(r'\*([^*\s][^*]*)\*'), (m) => '<em>${m[1]}</em>');

/// A status paragraph: its list items as a list, the rest as text.
String _block(String text) {
  final out = StringBuffer();
  var inList = false;
  for (final line in const LineSplitter().convert(text)) {
    final item = RegExp(r'^\s*- (.*)$').firstMatch(line);
    if (item != null) {
      if (!inList) out.write('<ul>');
      inList = true;
      out.write('<li>${_inline(item[1]!)}');
    } else if (inList && line.startsWith('  ')) {
      out.write(' ${_inline(line.trim())}');
    } else {
      if (inList) out.write('</ul>');
      inList = false;
      out.write('${_inline(line)} ');
    }
  }
  if (inList) out.write('</ul>');
  return out.toString();
}

// ------------------------------------------------------------------- plumbing

String? _option(List<String> args, String name) {
  final at = args.indexOf(name);
  return at >= 0 && at + 1 < args.length ? args[at + 1] : null;
}

Directory _repositoryRoot() {
  var dir = File.fromUri(Platform.script).parent;
  while (!File('${dir.path}/tasks/1.0-rc1-plan.md').existsSync()) {
    if (dir.parent.path == dir.path) {
      throw StateError('run from inside the flutter3d repository');
    }
    dir = dir.parent;
  }
  return dir;
}

/// Reads `live.json` beside the page every ten seconds and draws the Now
/// panel from it: `{updated, step, active: [{id, title, who, since, state}],
/// events: [{at, text}]}`.
const _liveScript = r'''
const esc = s => String(s ?? '').replace(/[&<>"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
const code = s => esc(s).replace(/`([^`]+)`/g, '<code>$1</code>');
function ago(iso) {
  const s = Math.max(0, (Date.now() - Date.parse(iso)) / 1000);
  if (s < 90) return Math.round(s) + ' s';
  if (s < 5400) return Math.round(s / 60) + ' min';
  if (s < 172800) return (s / 3600).toFixed(1) + ' h';
  return Math.round(s / 86400) + ' d';
}
let live = null;
function draw() {
  const now = document.getElementById('now');
  const age = document.getElementById('live-age');
  if (!live) return;
  age.textContent = 'updated ' + ago(live.updated) + ' ago';
  const rows = (live.active || []).map(a => `
    <div class="task ${esc(a.state || 'active')}">
      <span class="pulse"></span>
      <b>${esc(a.id)}</b>
      <span class="title">${code(a.title)}</span>
      <span class="who">${esc(a.who || '')}</span>
      <span class="since">${a.since ? ago(a.since) : ''}</span>
    </div>`).join('');
  const events = (live.events || []).slice(0, 12).map(e => `
    <li><span class="when">${ago(e.at)}</span> ${code(e.text)}</li>`).join('');
  now.innerHTML = `
    ${live.step ? `<div class="step">${code(live.step)}</div>` : ''}
    <div class="tasks">${rows || '<div class="empty">Nothing running right now.</div>'}</div>
    ${events ? `<ul class="events">${events}</ul>` : ''}`;
}
async function poll() {
  try {
    const r = await fetch('live.json', {cache: 'no-store'});
    if (r.ok) live = await r.json();
  } catch (_) {}
  draw();
}
poll();
setInterval(poll, 10000);
setInterval(draw, 1000);
''';

const _head = '''<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>flutter3d → 1.0</title>
<style>
:root{--bg:#0e1116;--panel:#161b22;--line:#262d36;--text:#e6edf3;--muted:#8b949e;
--done:#3fb950;--active:#d29922;--todo:#6e7681;--blocked:#f85149;--accent:#58a6ff}
@media (prefers-color-scheme:light){:root{--bg:#f6f8fa;--panel:#fff;--line:#d0d7de;
--text:#1f2328;--muted:#656d76;--done:#1a7f37;--active:#9a6700;--todo:#8c959f;
--blocked:#cf222e;--accent:#0969da}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);
font:15px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",Inter,sans-serif}
main{max-width:1180px;margin:0 auto;padding:24px 16px 64px}
h1{margin:0;font-size:28px}h2{margin:36px 0 12px;font-size:18px;color:var(--muted);
text-transform:uppercase;letter-spacing:.06em}.sub{color:var(--muted);margin:6px 0 0;max-width:70ch}
code{font:13px ui-monospace,SFMono-Regular,Menlo,monospace;background:var(--line);
padding:0 4px;border-radius:4px}
.kpis{display:grid;grid-template-columns:repeat(auto-fill,minmax(170px,1fr));gap:10px;margin-top:20px}
.kpi{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:12px}
.kpi .label{color:var(--muted);font-size:12px;text-transform:uppercase;letter-spacing:.05em}
.kpi .value{font-size:26px;font-weight:650;margin:2px 0}
.kpi .hint{color:var(--muted);font-size:12px;overflow:hidden;text-overflow:ellipsis;
display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical}
.kpi.warn .value{color:var(--active)}
.bar{display:flex;height:6px;background:var(--line);border-radius:3px;overflow:hidden;min-width:80px}
.bar i{display:block;background:var(--done)}.bar i.half{background:var(--active)}
.chip{display:inline-block;font-size:11px;padding:1px 8px;border-radius:10px;
border:1px solid currentColor;white-space:nowrap}
.chip.done{color:var(--done)}.chip.active,.chip.partial{color:var(--active)}
.chip.todo{color:var(--todo)}.chip.blocked{color:var(--blocked)}
details>summary{cursor:pointer;list-style:none}details>summary::-webkit-details-marker{display:none}
.goals{display:grid;gap:8px}
.goal{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:10px 14px}
.goal summary{display:flex;gap:10px;align-items:baseline}.goal .gist{color:var(--muted)}
.goal p{margin:8px 0 0;color:var(--muted)}
.waves{display:grid;gap:10px}
.wave{background:var(--panel);border:1px solid var(--line);border-radius:10px;overflow:hidden}
.wave>summary{display:grid;grid-template-columns:auto 1fr auto 140px;gap:12px;
align-items:center;padding:12px 14px}
.wave.done>summary .title{color:var(--muted)}
.cand{font-size:11px;color:var(--accent);border:1px solid var(--accent);border-radius:6px;padding:0 6px}
.count{color:var(--muted);font-variant-numeric:tabular-nums}
table{width:100%;border-collapse:collapse;border-top:1px solid var(--line)}
td{padding:8px 10px;border-bottom:1px solid var(--line);vertical-align:top}
td.id{font-weight:650;white-space:nowrap}td.size{color:var(--muted);white-space:nowrap}
td.text summary{color:var(--text)}td.text p{color:var(--muted);margin:6px 0 0}
tr.done td.text summary{color:var(--muted)}
.note{margin-top:4px;font-size:13px;color:var(--active)}
.status{padding:12px 14px;border-top:1px solid var(--line);color:var(--muted);font-size:14px}
.status ul{margin:6px 0;padding-left:20px}
footer{margin-top:40px;color:var(--muted);font-size:13px}
.age{font-size:12px;text-transform:none;letter-spacing:0;color:var(--muted);font-weight:400}
.now{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:14px}
.now .step{font-size:16px;margin-bottom:10px}.now .empty{color:var(--muted)}
.tasks{display:grid;gap:6px}
.task{display:grid;grid-template-columns:14px auto 1fr auto auto;gap:10px;align-items:baseline;
padding:6px 0;border-bottom:1px solid var(--line)}
.task .who,.task .since{color:var(--muted);font-size:13px;white-space:nowrap}
.pulse{width:9px;height:9px;border-radius:50%;background:var(--active);align-self:center;
animation:pulse 1.6s infinite}.task.waiting .pulse{background:var(--todo);animation:none}
.task.blocked .pulse{background:var(--blocked);animation:none}
@keyframes pulse{0%{box-shadow:0 0 0 0 rgba(210,153,34,.6)}70%{box-shadow:0 0 0 8px rgba(210,153,34,0)}100%{box-shadow:0 0 0 0 rgba(210,153,34,0)}}
.events{margin:12px 0 0;padding:0;list-style:none;font-size:14px;color:var(--muted)}
.events li{padding:3px 0}.events .when{display:inline-block;min-width:64px;font-variant-numeric:tabular-nums}
@media (max-width:640px){.task{grid-template-columns:14px auto 1fr}.task .who,.task .since{grid-column:2/-1}}
@media (max-width:640px){.wave>summary{grid-template-columns:auto 1fr auto}
.wave>summary .bar{grid-column:1/-1}td.size{display:none}}
</style></head><body><main>
''';
