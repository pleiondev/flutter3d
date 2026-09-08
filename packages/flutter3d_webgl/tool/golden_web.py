#!/usr/bin/env python3
"""Records or compares a browser backend's goldens, in a real browser.

    tool/golden_web.sh                 compare every scene, on WebGL2
    tool/golden_web.sh --update        record them instead
    tool/golden_web.sh cube-shadow     just that one
    tool/golden_web.sh --backend=webgpu   hold the other browser backend to
                                          its own set instead

**Why a server and not a test.** The pictures have to be drawn by a browser's
GPU API, which means a browser, and a browser cannot open a file or write one.
So the page fetches its reference over HTTP and posts back what it drew, and
this is the other end of both. It is the same shape as
`flutter3d/tool/golden.sh`, which drives the desktop build and reads an exit
code — a browser has no exit code either, so the verdict is posted too.

**Why each backend records its own set rather than being held to Impeller's.**
Two independently written implementations agreeing is evidence; one agreeing
with a picture the other drew is a comparison with a different question in it.
The cross-backend question is asked separately and headlessly, over the
committed sets, by `cross_backend_test.dart`.

**Why one script for both browser backends rather than a copy per backend.**
Everything expensive here is shared: the same dart2js build, the same scene
list, the same server, the same Chrome, the same ninety-frame wait. Exactly two
things are not, and they are the two fields of `BACKENDS` — which directory
the references live in, and which flags Chrome is started with. A fork would
have duplicated the rest and then drifted, which is how a stand comes to
compare a backend against a suite the other one has since grown out of.

The page is told which backend to draw through by a query parameter beside the
scene's, not by a compile-time define, because a define would cost one dart2js
run per backend and the whole saving of this stand is that it costs one in
total.
"""
import collections
import http.server
import os
import re
import shutil
import socketserver
import subprocess
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
PACKAGE = os.path.dirname(HERE)
ROOT = os.path.dirname(os.path.dirname(PACKAGE))
EXAMPLE = os.path.join(ROOT, "packages", "flutter3d", "example")
BUILD = os.path.join(EXAMPLE, "build", "web")
SCENES_DART = os.path.join(
    EXAMPLE, "lib", "src", "spike", "golden_scenes.dart")

CHROME = ("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
          "/usr/bin/google-chrome", "/usr/bin/chromium")

# How long one scene may take in the browser before it is treated as stalled.
# A scene renders ninety frames; a cold page load is most of this.
SCENE_TIMEOUT = float(os.environ.get("FLUTTER3D_WEB_SCENE_TIMEOUT", "90"))

Backend = collections.namedtuple("Backend", "package flags")

# The two things that are not shared, per backend, and nothing else.
#
# `package` names where the references live: `<package>/test/goldens`, the same
# path the structure rules already hold the three recorded sets to.
#
# `flags` is spelled out per backend rather than shared, because the two
# entries are allowed to diverge and the day one of them needs a flag the other
# must not have is the day a shared tuple would have to be unpicked. They agree
# today, and that is a measurement rather than an accident: under exactly these
# flags headless Chrome hands the page a hardware Metal adapter and not a
# software one, for WebGPU as well as for WebGL2. So no WebGPU-specific flag is
# warranted, and adding one on the assumption that a newer API must need newer
# flags would be changing a thing that was measured to work.
BACKENDS = {
    "webgl": Backend(
        package="flutter3d_webgl",
        # The whole point is a real GPU behind WebGL2. Headless Chrome falls
        # back to SwiftShader without this, which draws a different picture
        # and would make the reference a reference for a software rasteriser
        # nobody ships.
        flags=("--use-angle=default", "--enable-unsafe-swiftshader"),
    ),
    "webgpu": Backend(
        package="flutter3d_webgpu",
        # The same two, for the same reason and by the same measurement. See
        # the note above this table before changing either of them.
        flags=("--use-angle=default", "--enable-unsafe-swiftshader"),
    ),
}

DEFAULT_BACKEND = "webgl"


def goldens_directory(backend):
    """Where this backend's references live, beside its own package's tests."""
    return os.path.join(
        ROOT, "packages", BACKENDS[backend].package, "test", "goldens")


def scene_names():
    """The suite, read from the definitions rather than kept as a second list."""
    text = open(SCENES_DART, encoding="utf-8").read()
    names = re.findall(r"name: '([a-z0-9-]+)'", text)
    # The per-model scenes are generated in a loop, so their names are not
    # literals and the pattern above cannot see them. The desktop runner says
    # the same thing about the same list.
    names += [f"lighting-{m}" for m in
              ("unlit", "lambert", "blinnphong", "pbr", "toon", "normals")]
    return names


class Handler(http.server.SimpleHTTPRequestHandler):
    """Serves the build, answers `goldens/`, and accepts what the page posts."""

    verdicts = []
    written = []
    # Set by main() once the backend is known. There is one server per run and
    # one backend per run, so the directory is a property of the run rather
    # than of a request.
    goldens = None

    def translate_path(self, path):
        clean = path.split("?", 1)[0].split("#", 1)[0].lstrip("/")
        if clean.startswith("goldens/"):
            return os.path.join(Handler.goldens, clean[len("goldens/"):])
        return os.path.join(BUILD, clean) if clean else os.path.join(
            BUILD, "index.html")

    def do_POST(self):  # noqa: N802 - the base class names it
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)
        route = self.path.lstrip("/")

        if route == "report":
            Handler.verdicts.append(body.decode("utf-8", "replace"))
            self.send_response(204)
            self.end_headers()
            return

        for prefix in ("record/", "actual/"):
            if route.startswith(prefix):
                name = os.path.basename(route[len(prefix):])
                if prefix == "actual/":
                    name = name.replace(".png", ".actual.png")
                os.makedirs(Handler.goldens, exist_ok=True)
                with open(os.path.join(Handler.goldens, name), "wb") as out:
                    out.write(body)
                Handler.written.append(name)
                self.send_response(204)
                self.end_headers()
                return

        self.send_error(404)

    def log_message(self, *_):
        """Quiet: the verdicts are the output, not the request log."""


def chrome_binary():
    for path in CHROME:
        if os.path.exists(path):
            return path
    sys.exit("no Chrome found; the golden run needs one to draw with")


def chosen_backend(argv):
    """Which backend this run is about, from `--backend=<name>`."""
    name = DEFAULT_BACKEND
    for arg in argv:
        if arg.startswith("--backend="):
            name = arg.split("=", 1)[1]
    if name not in BACKENDS:
        sys.exit(f"no backend named {name!r}; this stand drives "
                 f"{', '.join(sorted(BACKENDS))}")
    return name


def run_scene(port, scene, backend, update, profile):
    """Loads one scene and returns the verdict line, or None if it stalled."""
    Handler.verdicts.clear()
    query = (f"?golden={scene}&backend={backend}"
             + ("&update=1" if update else ""))
    process = subprocess.Popen(
        [chrome_binary(),
         "--headless=new",
         "--disable-gpu-sandbox",
         *BACKENDS[backend].flags,
         f"--user-data-dir={profile}",
         "--no-first-run",
         "--window-size=1280,900",
         f"http://127.0.0.1:{port}/{query}"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        deadline = time.time() + SCENE_TIMEOUT
        while time.time() < deadline:
            for line in Handler.verdicts:
                if line.startswith(f"GOLDEN {scene}:"):
                    return line
            time.sleep(0.25)
        return None
    finally:
        process.terminate()
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()


def main(argv):
    update = "--update" in argv
    backend = chosen_backend(argv)
    wanted = [a for a in argv if not a.startswith("-")] or scene_names()

    if not os.path.isfile(os.path.join(BUILD, "main.dart.js")):
        sys.exit(f"no web build at {BUILD}. tool/golden_web.sh builds one first.")

    Handler.goldens = goldens_directory(backend)
    print(f"{backend}, against {os.path.relpath(Handler.goldens, ROOT)}")
    os.makedirs(Handler.goldens, exist_ok=True)
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("127.0.0.1", 0), Handler) as server:
        port = server.server_address[1]
        threading.Thread(target=server.serve_forever, daemon=True).start()

        profile = os.path.join("/tmp", "flutter3d-golden-web-profile")
        shutil.rmtree(profile, ignore_errors=True)

        passed, failed, stalled = 0, [], []
        for scene in wanted:
            print(f"{scene:<28}", end="", flush=True)
            verdict = run_scene(port, scene, backend, update, profile)
            if verdict is None:
                print("STALLED (no verdict in "
                      f"{SCENE_TIMEOUT:.0f}s)")
                stalled.append(scene)
                continue
            body = verdict.split(":", 1)[1].strip()
            print(body)
            if body.startswith("PASS") or body.startswith("recorded"):
                passed += 1
            else:
                failed.append(scene)

        shutil.rmtree(profile, ignore_errors=True)

    print()
    print(f"{passed} passed, {len(failed)} failed, {len(stalled)} stalled")
    for scene in failed + stalled:
        print(f"  {scene}")
    return 0 if not failed and not stalled else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
