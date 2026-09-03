#!/usr/bin/env python3
"""Runs every generator that a tracked document names, and nothing else.

    python3 tool/regenerate_levels.py

**This exists because the list was kept by hand and the hand forgot.** The
`levels` step of `tool/ci.sh` named its generators one by one, and its own
comment said "all six are byte-reproducible" — by then there were nine, and two
of them had never been run by it at all: `make_cistern.py` and
`make_sanctum.py` write `cistern.json` and `sanctum.json`, both tracked, both
shipped, and neither covered by the regenerate-and-diff check that exists to
catch a document edited past its generator. They were reproducible, as it
happens. Nothing had ever asked.

That is the same failure `tool/structure.dart` was written to end for packages,
and its header says why: *a runner that walks `packages/` covers a package the
day it exists*. So this walks the documents instead of a list. Every generated
level document already records the tool that wrote it — `leveldoc.dump` puts
`generatedBy` in the file — which makes the repository's own content the index,
and makes a new level covered the day somebody commits it.

## Resolving what `generatedBy` says

Three spellings are in the tree and all three are load-bearing:

  * `apps/flutter3d_demo_dungeon/tool/make_cistern.py` — from the repository root
  * `tool/make_level.py` — from the application that owns the document
  * `tool/make_templates.py` — from the repository root again, for the template
    application, which has no `tool/` directory of its own

So each is tried against the owning application first and the repository root
second, and a path that resolves to neither is an error rather than a skip: a
document naming a generator nobody can find is exactly the drift this is for.
"""

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def tracked_documents():
    """Every tracked JSON under an application's assets. `git ls-files` rather
    than a walk, because `build/` is full of copies of these documents and a
    walk would run each generator once per platform that had ever been built."""
    listed = subprocess.run(
        ["git", "ls-files", "apps/*/assets/**/*.json", "apps/*/assets/*.json"],
        cwd=ROOT, capture_output=True, text=True, check=True,
    )
    return [ROOT / line for line in listed.stdout.split("\n") if line]


def generator_of(document):
    """The tool a document says wrote it, as (working directory, script)."""
    text = document.read_text()
    # Cheap first: most documents are large and most of them are levels, but a
    # texture atlas or an icon table is neither and need not be parsed.
    if '"generatedBy"' not in text:
        return None
    named = json.loads(text).get("generatedBy")
    if not named:
        return None

    # The application that owns it: apps/<name>/assets/... → apps/<name>
    owner = document.relative_to(ROOT).parts[:2]
    for base in (ROOT.joinpath(*owner), ROOT):
        script = base / named
        if script.is_file():
            return base, script
    raise SystemExit(
        f"{document.relative_to(ROOT)} says it was written by {named!r}, "
        f"and there is no such file under {'/'.join(owner)} or the repository "
        "root"
    )


def main():
    found = {}
    for document in tracked_documents():
        made_by = generator_of(document)
        if made_by is None:
            continue
        base, script = made_by
        found.setdefault((base, script), []).append(document)

    if not found:
        raise SystemExit("no tracked document names a generator")

    for base, script in sorted(found, key=lambda pair: str(pair[1])):
        done = subprocess.run(
            [sys.executable, str(script.relative_to(base))],
            cwd=base, capture_output=True, text=True,
        )
        if done.returncode != 0:
            sys.stderr.write(done.stdout + done.stderr)
            raise SystemExit(
                f"{script.relative_to(ROOT)} failed with {done.returncode}"
            )
        # Named rather than counted, because the whole point of this tool is
        # which generators run: a list that silently got shorter is the bug it
        # was written for, and a bare number would hide it just as well as the
        # hand-kept list did.
        print(
            f"  {str(script.relative_to(ROOT)):<52} "
            f"{len(found[(base, script)])} document(s)"
        )

    wrote = sum(len(v) for v in found.values())
    print(f"{len(found)} generators, {wrote} documents")


if __name__ == "__main__":
    main()
