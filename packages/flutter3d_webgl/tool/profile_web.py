"""Times a demo's frames in the browser the goldens are recorded in.

Copies a built web app, injects a sampler into its index.html, serves it, and
runs headless Chrome at it exactly as `golden_web.py` does — the same
`--use-angle=default` so WebGL2 is on a real GPU rather than on SwiftShader.

    python3 profile_web.py <build/web dir> [seconds] [--key=w] [--angle=...]

    (cd apps/flutter3d_demo_racing && flutter build web --wasm --release)
    python3 packages/flutter3d_webgl/tool/profile_web.py \\
        apps/flutter3d_demo_racing/build/web 10

## What it reports and why each number is there

**Frame times**, as `requestAnimationFrame` deltas. Headless is not a detail: a
tab that is not visible has rAF suspended outright, so the first attempt at
this measurement — driving a real window that turned out to be behind another
one — reported zero frames in eight seconds and looked exactly like a total
stall. A headless window is always visible to itself.

**Draws per frame, and per render target.** A frame time says how much there
is; the split says where. It is also the check that the thing being timed is
the scene rather than a title card, which is the way a measurement like this
is usually wrong.

**WebGL objects created per frame.** The one that found something. See
`webgl_encoder.dart`'s `bindVertexData`: this backend makes a buffer per call
and lets the driver own its lifetime, where the flutter_gpu backend keeps a
ring of bump allocators. That is a deliberate simplification and this is what
it costs — about two and a half GL buffers per draw call.

## The baseline, so a later run has something to be worse than

`flutter3d_demo_racing`, release, macOS-arm64 on an M3 Pro, 2026-09-07:

    build     angle        median frame   draws/frame   buffers made/frame
    wasm      default      16.7 ms        677           1552
    dart2js   default      16.7 ms        677           1552
    wasm      swiftshader  83 ms          618           —

The two compilers are the same picture at the same speed; software WebGL is
not, and its worst frame in ten seconds was 3.3 seconds long. Which is the
answer to a claim this repository carried for a week — that the racing demo
"runs at under a frame a second on the web". On a GPU it does not. Without one
it does, and that is a different sentence.
"""

import http.server
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time

CHROME = ("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
          "/usr/bin/google-chrome", "/usr/bin/chromium")

SAMPLER = """
<script>
(function () {
  // Patched before Flutter boots, which is why this script goes in the head:
  // a count of draws per frame is what says whether the frame being timed is
  // the scene or an empty title card.
  var draws = 0;
  // Draws attributed to the target they landed on, by watching the bind that
  // precedes them. A number for the whole frame says how much there is; a
  // number per target says where it is, which is the difference between a
  // measurement and a fact.
  var target = 'default';
  var byTarget = {};
  var order = [];
  [WebGL2RenderingContext, WebGLRenderingContext].forEach(function (ctx) {
    if (!ctx) return;
    var bind = ctx.prototype.bindFramebuffer;
    ctx.prototype.bindFramebuffer = function (slot, fb) {
      if (fb === null) {
        target = 'canvas';
      } else {
        if (!fb.__id) { fb.__id = 'fb' + (order.length + 1); order.push(fb.__id); }
        target = fb.__id;
      }
      return bind.apply(this, arguments);
    };
  });
  ['drawElements', 'drawArrays', 'drawElementsInstanced', 'drawArraysInstanced']
    .forEach(function (name) {
      [WebGL2RenderingContext, WebGLRenderingContext].forEach(function (ctx) {
        if (!ctx || !ctx.prototype[name]) return;
        var original = ctx.prototype[name];
        ctx.prototype[name] = function () {
          draws++;
          byTarget[target] = (byTarget[target] || 0) + 1;
          return original.apply(this, arguments);
        };
      });
    });

  var drawsPerFrame = [];
  var frameTargets = [];
  // How many WebGL objects are *made* each frame, not merely bound. A render
  // target created per frame is a render target the driver validates per
  // frame, and it is the shape a leak has as well.
  var created = {framebuffer: 0, texture: 0, buffer: 0, renderbuffer: 0};
  var creationsPerFrame = [];
  [WebGL2RenderingContext, WebGLRenderingContext].forEach(function (ctx) {
    if (!ctx) return;
    ['Framebuffer', 'Texture', 'Buffer', 'Renderbuffer'].forEach(function (kind) {
      var name = 'create' + kind;
      if (!ctx.prototype[name]) return;
      var original = ctx.prototype[name];
      ctx.prototype[name] = function () {
        created[kind.toLowerCase()]++;
        return original.apply(this, arguments);
      };
    });
  });
  var deltas = [];
  var marks = [];
  var last = performance.now();
  var started = performance.now();
  function tick(t) {
    deltas.push(t - last);
    drawsPerFrame.push(draws);
    frameTargets.push(byTarget);
    creationsPerFrame.push(created);
    created = {framebuffer: 0, texture: 0, buffer: 0, renderbuffer: 0};
    byTarget = {};
    draws = 0;
    last = t;
    requestAnimationFrame(tick);
  }
  requestAnimationFrame(tick);

  // The title card waits for a key. Dispatched rather than typed, because
  // there is nobody at this keyboard.
  setTimeout(function () {
    marks.push(['key', performance.now() - started]);
    ['keydown', 'keyup'].forEach(function (type) {
      var e = new KeyboardEvent(type, {
        key: KEY, code: 'Key' + KEY.toUpperCase(),
        keyCode: KEY.toUpperCase().charCodeAt(0), which: KEY.toUpperCase().charCodeAt(0),
        bubbles: true, cancelable: true,
      });
      document.dispatchEvent(e);
      window.dispatchEvent(e);
      var pane = document.querySelector('flt-glass-pane') || document.body;
      if (pane) pane.dispatchEvent(e);
    });
  }, WARMUP);

  setTimeout(function () {
    fetch('/report', {
      method: 'POST',
      body: JSON.stringify({deltas: deltas, draws: drawsPerFrame, targets: frameTargets.slice(-40), created: creationsPerFrame.slice(-120), marks: marks}),
    });
  }, WARMUP + WINDOW);
})();
</script>
"""


class Handler(http.server.SimpleHTTPRequestHandler):
    report = []

    def do_POST(self):
        length = int(self.headers.get('Content-Length', 0))
        Handler.report.append(json.loads(self.rfile.read(length) or b'{}'))
        self.send_response(200)
        self.end_headers()

    def log_message(self, *args):
        pass


def chrome_binary():
    for path in CHROME:
        if os.path.exists(path):
            return path
    sys.exit('no Chrome found')


def percentile(values, p):
    if not values:
        return float('nan')
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, int(len(ordered) * p))]


def main():
    source = sys.argv[1]
    seconds = float(sys.argv[2]) if len(sys.argv) > 2 else 10.0
    key = 'w'
    angle = 'default'
    for arg in sys.argv[3:]:
        if arg.startswith('--key='):
            key = arg.split('=', 1)[1]
        if arg.startswith('--angle='):
            angle = arg.split('=', 1)[1]

    staging = tempfile.mkdtemp(prefix='profile-web-')
    shutil.copytree(source, staging, dirs_exist_ok=True)
    index = os.path.join(staging, 'index.html')
    html = open(index).read()
    script = (SAMPLER
              .replace('KEY', repr(key))
              .replace('WARMUP', '6000')
              .replace('WINDOW', str(int(seconds * 1000))))
    open(index, 'w').write(html.replace('<head>', '<head>' + script, 1))

    os.chdir(staging)
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    port = server.server_address[1]
    threading.Thread(target=server.serve_forever, daemon=True).start()

    profile = tempfile.mkdtemp(prefix='profile-web-chrome-')
    process = subprocess.Popen(
        [chrome_binary(), '--headless=new', '--disable-gpu-sandbox',
         f'--use-angle={angle}', '--enable-unsafe-swiftshader',
         f'--user-data-dir={profile}', '--no-first-run',
         '--window-size=1280,900', f'http://127.0.0.1:{port}/'],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    deadline = time.time() + seconds + 40
    try:
        while time.time() < deadline and not Handler.report:
            time.sleep(0.25)
    finally:
        process.terminate()
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()

    if not Handler.report:
        print('no report: the page never got far enough to send one')
        return 1

    deltas = Handler.report[0]['deltas']
    # The window measured is what came after the key, so the title card's own
    # frames are not averaged into the race's.
    key_at = next((t for name, t in Handler.report[0]['marks'] if name == 'key'), 0)
    running = deltas[int(len(deltas) * 0.5):] if len(deltas) > 20 else deltas

    print(f'frames in {seconds:.0f}s: {len(deltas)}')
    print(f'mean fps:      {len(deltas) / seconds:.1f}')
    if running:
        print(f'median frame:  {percentile(running, 0.5):.1f} ms  '
              f'({1000 / max(percentile(running, 0.5), 1e-6):.1f} fps)')
        print(f'p90 frame:     {percentile(running, 0.9):.1f} ms')
        print(f'worst frame:   {max(running):.1f} ms')
    draws = Handler.report[0].get('draws') or []
    running_draws = draws[int(len(draws) * 0.5):] if len(draws) > 20 else draws
    if running_draws:
        print(f'draws/frame:   median {percentile(running_draws, 0.5):.0f}, '
              f'max {max(running_draws)}')
    targets = Handler.report[0].get('targets') or []
    busiest = max(targets, key=lambda t: sum(t.values())) if targets else {}
    if busiest:
        singles = sum(1 for c in busiest.values() if c == 1)
        print(f'targets on the busiest frame: {len(busiest)}, '
              f'{singles} of them taking a single draw')
        for name, count in sorted(busiest.items(), key=lambda kv: -kv[1])[:6]:
            print(f'  {name:<10} {count}')
    made = Handler.report[0].get('created') or []
    if made:
        for kind in ('framebuffer', 'texture', 'buffer', 'renderbuffer'):
            per = [m.get(kind, 0) for m in made]
            if max(per) > 0:
                print(f'{kind}s created per frame: median '
                      f'{percentile(per, 0.5):.0f}, max {max(per)}')
    print(f'key dispatched at {key_at:.0f} ms, angle={angle}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
