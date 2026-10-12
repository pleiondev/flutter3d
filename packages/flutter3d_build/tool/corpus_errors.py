"""The analyzer errors of one corpus project that the migration did not
answer with a TODO.

    python3 -I corpus_errors.py <analyze report> <project dir>

Prints each `error` line of the report whose use carries no
`// TODO(flutter3d-1.0)` the migration wrote. A use carries one when the
TODO stands at most three lines above it, not counting the lines of a doc
comment or an annotation between them: `migrate` puts its TODO on the line
above the use, or above the statement or declaration the use opens (and so
above that declaration's doc comment). The same rule as
`test/migrate_fixture_test.dart`'s.
"""
import pathlib
import re
import sys

report = pathlib.Path(sys.argv[1])
project = pathlib.Path(sys.argv[2])
at = re.compile(r'^\s*error • .* • (\S+):(\d+):\d+ • \S+\s*$')
sources = {}


def under_todo(path, line):
    if path not in sources:
        file = project / path
        sources[path] = (
            file.read_text(errors='replace').splitlines() if file.exists() else []
        )
    lines = sources[path]
    seen = 0
    i = line - 2
    while i >= 0 and seen < 3:
        text = lines[i].strip()
        if 'TODO(flutter3d-1.0)' in text:
            return True
        if not (text.startswith('///') or text.startswith('@')):
            seen += 1
        i -= 1
    return False


for entry in report.read_text(errors='replace').splitlines():
    m = at.match(entry)
    if m and not under_todo(m.group(1), int(m.group(2))):
        print(entry)
