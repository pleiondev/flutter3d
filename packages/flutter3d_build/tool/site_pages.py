"""Builds the Dart blocks of the site's guide pages into small projects.

    python3 -I site_pages.py <site/content dir> <packages dir> <out dir>

Used by `migrate_corpus.sh`: the code a user copied from the quickstart,
the first-project page, each tutorial and the cookbook pages, as it stood
at the release being migrated from, is migrated and analysed like the apps
are. Each page becomes `<out>/site_<page>/`, a Flutter project with one
library per Dart block under `lib/`.

A block on a page is a fragment more often than a file: a few statements
against a `world` the page built three blocks ago, or one expression. So
each block is placed where it parses: imports at the top, classes, enums,
typedefs and functions at the top level, statements inside an `async`
function, and a lone expression as the body of one. Names the page defined
elsewhere are still undefined; the corpus counts the errors a migration
adds, against the same project analysed at the release, not the ones the
fragments always had.
"""

import pathlib
import re
import sys

# The packages a page's code reaches without importing them on the page: the
# facade every guide starts from, and each area's genre or tool package.
AREA_PACKAGES = {
    "": ["flutter3d", "flutter3d_impeller", "flutter3d_game"],
    "core": ["flutter3d", "flutter3d_impeller"],
    "platformer": ["flutter3d_game_platformer", "flutter3d_game"],
    "racing": ["flutter3d_game_racing", "flutter3d_game"],
    "shooter": ["flutter3d_game_shooter", "flutter3d_game"],
    "strategy": ["flutter3d_game_strategy", "flutter3d_game"],
    "modeler": ["flutter3d_model_core", "flutter3d"],
}

COMMON_IMPORTS = [
    "import 'dart:async';",
    "import 'dart:convert';",
    "import 'dart:math' as math;",
    "import 'package:flutter/material.dart' hide Material;",
    "import 'package:flutter/services.dart';",
    "import 'package:vector_math/vector_math.dart' hide Colors;",
]

DECLARATION = re.compile(
    r"^(@|(abstract|base|final|sealed|interface|mixin)\b.*\bclass\b|class\b|"
    r"mixin\b|enum\b|typedef\b|extension\b)"
)
# A top-level function: a return type, a name and a parameter list, then a
# body or an arrow.
FUNCTION = re.compile(
    r"^[A-Za-z_][\w<>?,\s.]*\s+[A-Za-z_]\w*\s*(<[^>]*>)?\s*\(.*$"
)


def pages(content: pathlib.Path):
    wanted = ["quickstart.md", "first-project.md"]
    found = [content / name for name in wanted if (content / name).exists()]
    found += sorted(content.glob("*/tutorial.md"))
    found += sorted(content.glob("cookbook/*.md"))
    found += sorted(content.glob("**/*cookbook*.md"))
    seen = set()
    return [p for p in found if not (p in seen or seen.add(p))]


def blocks(text: str):
    return re.findall(r"^```dart\n(.*?)^```", text, flags=re.M | re.S)


def chunks(lines):
    """The lines of a block in runs that each start at column 0."""
    run = []
    for line in lines:
        if run and line and not line[0].isspace() and not line.startswith("}") \
                and not line.startswith(")") and not line.startswith("]"):
            yield run
            run = []
        run.append(line)
    if run:
        yield run


def is_function(first: str) -> bool:
    if not FUNCTION.match(first):
        return False
    head = first.split("(", 1)[0].split()
    # `final x = f(…)`, `return f(…)`, `await f(…)` are statements.
    return len(head) >= 2 and head[0] not in (
        "final", "var", "const", "late", "return", "await", "throw", "if",
        "for", "while", "switch", "else", "yield",
    ) and "=" not in first.split("(", 1)[0]


def place(block: str):
    """(imports, top-level code, statements, expression) for one block."""
    lines = block.rstrip("\n").split("\n")
    imports = [l for l in lines if re.match(r"^(import|export)\s", l)]
    rest = [l for l in lines if l not in imports]
    code = "\n".join(l for l in rest).strip()
    if not code:
        return imports, "", "", None
    meaningful = [l for l in rest if l.strip() and not l.strip().startswith("//")]
    last = meaningful[-1].rstrip() if meaningful else ""
    if not last.endswith((";", "}")):
        return imports, "", "", code
    top, body = [], []
    for run in chunks(rest):
        first = run[0]
        if DECLARATION.match(first) or is_function(first):
            top.extend(run)
        else:
            body.extend(run)
    return imports, "\n".join(top), "\n".join(body), None


def library(page_imports, packages, available, block: str) -> str:
    imports, top, body, expression = place(block)
    header = list(COMMON_IMPORTS)
    for package in packages:
        if package in available:
            header.append(f"import 'package:{package}/{package}.dart';")
    for line in page_imports + imports:
        if line not in header:
            header.append(line)
    out = ["// ignore_for_file: unused_import, unused_element, unused_local_variable",
           *header, ""]
    if top:
        out += [top, ""]
    if body.strip():
        out += ["Future<void> _block() async {", body, "}", ""]
    if expression is not None:
        out += ["Object? _expression() => (", expression, ");", ""]
    return "\n".join(out)


def main():
    content, packages_dir, out = (pathlib.Path(a) for a in sys.argv[1:4])
    available = {
        p.name for p in packages_dir.iterdir()
        if (p / "lib" / f"{p.name}.dart").exists()
    }
    for page in pages(content):
        relative = page.relative_to(content)
        area = relative.parts[0] if len(relative.parts) > 1 else ""
        slug = "_".join(relative.with_suffix("").parts).replace("-", "_")
        found = blocks(page.read_text())
        if not found:
            continue
        project = out / f"site_{slug}"
        (project / "lib").mkdir(parents=True)
        page_imports = sorted({
            line for block in found for line in block.split("\n")
            if re.match(r"^import\s", line)
        })
        named = sorted({
            m for line in page_imports
            for m in re.findall(r"package:(\w+)/", line)
            if m not in ("flutter", "vector_math")
        })
        packages = list(dict.fromkeys(AREA_PACKAGES.get(area, AREA_PACKAGES[""]) + named))
        for i, block in enumerate(found, start=1):
            (project / "lib" / f"b{i:02d}.dart").write_text(
                library(page_imports, packages, available, block)
            )
        deps = "".join(f"  {p}: ^0.8.0\n" for p in packages if p in available)
        (project / "pubspec.yaml").write_text(
            f"name: site_{slug}\n"
            "publish_to: none\n"
            "environment:\n"
            "  sdk: \">=3.12.0 <4.0.0\"\n"
            "dependencies:\n"
            "  flutter:\n"
            "    sdk: flutter\n"
            "  vector_math: ^2.2.0\n"
            f"{deps}"
        )


if __name__ == "__main__":
    main()
