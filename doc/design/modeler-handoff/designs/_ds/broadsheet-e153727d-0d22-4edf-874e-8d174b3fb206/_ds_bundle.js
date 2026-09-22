/* @ds-bundle: {"format":4,"namespace":"Broadsheet_broads","components":[],"sourceHashes":{"print-plates.js":"00209245728b"},"inlinedExternals":[],"unexposedExports":[]} */

(() => {

const __ds_ns = (window.Broadsheet_broads = window.Broadsheet_broads || {});

const __ds_scope = {};

(__ds_ns.__errors = __ds_ns.__errors || []);

// print-plates.js
try { (() => {
// print-plates.js — the Broadsheet separation filters, shipped with the
// system. Each single-plate filter extracts one process plate from a
// photograph, rendered as that ink on the sheet — cyan from R, magenta
// from G, yellow from B, and a 60%-strength luminance K printed in the
// text ink (#201e1d). Values are the system's own inks (accent, accent-2,
// process-yellow, text). #sep-all chains the four into ONE compound
// filter for a single swappable image (see .cmyk .print in styles.css):
// each stage re-extracts a plate from SourceGraphic, clips it to the
// source's own silhouette (feComposite operator="in" against
// SourceAlpha), and offsets the clipped sheet by the registered
// misregistration (C 0,0 / M 5,3 / Y -5,-3 / K 3,6); the sheets multiply
// where they cross and show alone where they don't. The clip is why
// there is no paper flood here anymore (divergence round 3, Barron: "it
// crops the effect"): an unclipped feColorMatrix lays its constant-term
// ink across the whole filter region, which forced overflow:hidden on
// the figure and guillotined the misregistration flat at the box edge.
// Clipped sheets paint nothing outside themselves, so the figure can let
// them overhang and the offsets read at the edges, the films askew on
// the stack. Each sheet carries its own white (the matrices print ink
// on the SOURCE's whites now, not the paper token), so the multiply
// needs no backdrop — and dropping the flood's #f3f2f2 multiply
// brightens every #sep-all composite by that factor (~5%, measured
// before/after on the landing split's interior) as part of the same
// goal the ink purification below finishes: the resting print sits
// closer to the photograph, and the hover resolve lands on it exactly.
//
// The offsets live on feOffset primitives tagged data-plate, because the
// press driver below animates them: hover gathers the plates into
// register (the films squared on the light table — the deck's
// pulled-apart slide established the move, from the Catalogue Three
// reference) while the same eased value purifies the plate inks — each
// feColorMatrix (tagged data-plate-mat) lerps from its brand separation
// to the pure-process factorization whose four plates multiply back to
// SourceGraphic exactly — so the converged MERGE is the photograph: the
// brand inks and the K plate are what make the resting print denser
// than the source, which is why the earlier films-lift end-swap read
// as a brightness pop (divergence round 4, Barron: the merged plates
// "should look normal"). The screen never shows anything but the
// four-plate multiply; nothing is swapped in at any point.
// The pointer leans the moving plates a breath toward the cursor as it
// roams the page (divergence round 3, Barron: "slightly adjust the
// offsets based on your mouse position"). The driver also
// publishes the pointer as bare -1..1 factors (--press-nx/--press-ny)
// on the root, which the text-plate treatments (.cmyk-num, .cmyk-head
// in styles.css) multiply into their own em spreads. One set of defs serves the
// document, so a hover on any one .print figure drives them all — pages
// show one compound-filter figure at a time (the landing's split, one
// deck slide), which keeps that a non-event (the deck edit rail's live
// thumbnails resolve the same defs and move in sympathy — previews,
// previewing). The driver stands down
// wholesale under prefers-reduced-motion or without a fine hover
// pointer; styles.css carries the matching media-gated :hover cut as
// the fallback, so the reduced-motion experience is exactly the old
// one.
//
// This file exists because the defs must be IN the document: a data-URI
// filter reference does not survive Chromium (probed, review round 3),
// and external-file references are unreliable across engines — script
// injection puts the defs in the document itself, the one mechanism the
// inline block already proved. The compiled bundle (_ds_bundle.js)
// inlines this file, so every template page gets the defs through
// ds-base.js's bundle load (ds-base.js itself stays identical across
// the six systems — a repo-wide invariant); a page that links
// styles.css directly instead adds
// <script src="print-plates.js"></script> (path relative to the
// system root, as for styles.css). Injected at the end of <body>, outside
// any component tree, so no single section's deletion can strand the
// references — filter references resolve document-wide.
(() => {
  const ID = 'broadsheet-print-plates';
  const mount = () => {
    if (document.getElementById(ID)) return; // idempotent — load twice, inject once
    const host = document.createElement('div');
    host.innerHTML = `<svg width="0" height="0" style="position:absolute" aria-hidden="true"><defs>
  <filter id="sep-c" color-interpolation-filters="sRGB"><feColorMatrix type="matrix" values="1 0 0 0 0  0.467 0 0 0 0.533  0.310 0 0 0 0.690  0 0 0 0 1"/></filter>
  <filter id="sep-m" color-interpolation-filters="sRGB"><feColorMatrix type="matrix" values="0 0.161 0 0 0.839  0 1 0 0 0  0 0.576 0 0 0.424  0 0 0 0 1"/></filter>
  <filter id="sep-y" color-interpolation-filters="sRGB"><feColorMatrix type="matrix" values="0 0 0.071 0 0.929  0 0 0.267 0 0.733  0 0 1 0 0  0 0 0 0 1"/></filter>
  <filter id="sep-k" color-interpolation-filters="sRGB"><feColorMatrix type="matrix" values="0.112 0.375 0.038 0 0.475  0.113 0.379 0.038 0 0.471  0.113 0.380 0.038 0 0.468  0 0 0 0 1"/></filter>
  <filter id="sep-all" color-interpolation-filters="sRGB">
    <feColorMatrix in="SourceGraphic" type="matrix" values="1 0 0 0 0  0.467 0 0 0 0.533  0.310 0 0 0 0.690  0 0 0 0 1" data-plate-mat="c" result="c0"/>
    <feComposite in="c0" in2="SourceAlpha" operator="in" result="c"/>
    <feColorMatrix in="SourceGraphic" type="matrix" values="0 0.161 0 0 0.839  0 1 0 0 0  0 0.576 0 0 0.424  0 0 0 0 1" data-plate-mat="m" result="m0"/>
    <feComposite in="m0" in2="SourceAlpha" operator="in" result="m1"/>
    <feOffset in="m1" dx="5" dy="3" data-plate="m" result="m"/>
    <feColorMatrix in="SourceGraphic" type="matrix" values="0 0 0.071 0 0.929  0 0 0.267 0 0.733  0 0 1 0 0  0 0 0 0 1" data-plate-mat="y" result="y0"/>
    <feComposite in="y0" in2="SourceAlpha" operator="in" result="y1"/>
    <feOffset in="y1" dx="-5" dy="-3" data-plate="y" result="y"/>
    <feColorMatrix in="SourceGraphic" type="matrix" values="0.112 0.375 0.038 0 0.475  0.113 0.379 0.038 0 0.471  0.113 0.380 0.038 0 0.468  0 0 0 0 1" data-plate-mat="k" result="k0"/>
    <feComposite in="k0" in2="SourceAlpha" operator="in" result="k1"/>
    <feOffset in="k1" dx="3" dy="6" data-plate="k" result="k"/>
    <feBlend in="m" in2="c" mode="multiply" result="s1"/>
    <feBlend in="y" in2="s1" mode="multiply" result="s2"/>
    <feBlend in="k" in2="s2" mode="multiply"/>
  </filter>
</defs></svg>`;
    const svg = host.firstChild;
    svg.id = ID;
    document.body.appendChild(svg);
    press(svg);
  };

  // The press driver — hover registration and the pointer lean. All
  // numbers are the measured design values, not tunables-in-waiting:
  // LEAN is ±2.5px x / ±2px y at the viewport edges (half the M/Y
  // x-offset, two-thirds of its y — a breath, per "slightly"); the
  // text plates take the
  // same gesture at glyph scale, so the driver publishes the bare
  // pointer factors (--press-nx/--press-ny, -1..1) and each text
  // construction multiplies them into its own em spread in styles.css;
  // REGISTER_MS matches the deck's gather without its theatre (the
  // 1.4s slide move reads as a scene, a hover should answer).
  const press = svg => {
    if (matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    if (!matchMedia('(hover: hover) and (pointer: fine)').matches) return;
    const BASE = {
      m: [5, 3],
      y: [-5, -3],
      k: [3, 6]
    };
    const LEAN_PX = [2.5, 2],
      REGISTER_MS = 450;
    const nodes = {};
    svg.querySelectorAll('feOffset[data-plate]').forEach(n => {
      nodes[n.dataset.plate] = n;
    });
    // The plate matrices' two endpoints. INK is the brand separation the
    // sheet prints at rest (the values in the defs above). TRUE is the
    // pure-process factorization — C passes R and floods G,B to 1, M and
    // Y likewise for their channels, K goes to white (the multiply
    // identity) — chosen because the four TRUE plates multiply back to
    // SourceGraphic EXACTLY: (R,1,1)·(1,G,1)·(1,1,B)·(1,1,1) = (R,G,B).
    // The brand inks and the K plate are exactly what makes the resting
    // print denser than the photograph, so easing each matrix INK→TRUE
    // as the plates converge lands the merged print ON the photograph —
    // the image on screen is a four-plate multiply at every instant, and
    // the converged merge "looks normal" by algebra, not by swapping
    // anything in at the end (divergence round 4, Barron: the old
    // films-lift end-swap read as a brightness pop).
    const mats = {};
    svg.querySelectorAll('feColorMatrix[data-plate-mat]').forEach(n => {
      mats[n.dataset.plateMat] = n;
    });
    const INK = {
      c: [1, 0, 0, 0, 0, 0.467, 0, 0, 0, 0.533, 0.310, 0, 0, 0, 0.690, 0, 0, 0, 0, 1],
      m: [0, 0.161, 0, 0, 0.839, 0, 1, 0, 0, 0, 0, 0.576, 0, 0, 0.424, 0, 0, 0, 0, 1],
      y: [0, 0, 0.071, 0, 0.929, 0, 0, 0.267, 0, 0.733, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1],
      k: [0.112, 0.375, 0.038, 0, 0.475, 0.113, 0.379, 0.038, 0, 0.471, 0.113, 0.380, 0.038, 0, 0.468, 0, 0, 0, 0, 1]
    };
    const TRUE_ = {
      c: [1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
      m: [0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
      y: [0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1],
      k: [0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
    };
    const root = document.documentElement;
    let nx = 0,
      ny = 0; // smoothed pointer, -1..1 from viewport center
    let tx = 0,
      ty = 0; // raw pointer target
    let reg = 1; // 1 = misregistered (rest), 0 = in register
    let regFrom = 1,
      regTo = 1,
      regT0 = 0;
    let raf = 0,
      lastOffs = '',
      lastReg = -1,
      lastProps = '';
    const ease = t => 1 - Math.pow(1 - t, 3); // cubic out
    const tick = now => {
      raf = 0;
      nx += (tx - nx) * 0.22;
      ny += (ty - ny) * 0.22; // soften the hand
      if (regTo !== reg || regT0) {
        const t = Math.min(1, (now - regT0) / REGISTER_MS);
        reg = regFrom + (regTo - regFrom) * ease(t);
        if (t >= 1) {
          reg = regTo;
          regT0 = 0;
        }
      }
      // every write below is guarded on its COMPUTED output, not its
      // inputs — an equal-value setAttribute still dirties the filter,
      // and at full register the offsets are 0.00 whatever the lean, so
      // a pointer roaming over a converged figure must not recompute
      // the compound filter every frame
      const lx = LEAN_PX[0] * nx,
        ly = LEAN_PX[1] * ny;
      const vals = {};
      let offsKey = '';
      for (const p in BASE) {
        const dx = ((BASE[p][0] + lx) * reg).toFixed(2);
        const dy = ((BASE[p][1] + ly) * reg).toFixed(2);
        vals[p] = [dx, dy];
        offsKey += dx + ',' + dy + ';';
      }
      if (offsKey !== lastOffs) {
        lastOffs = offsKey;
        for (const p in BASE) {
          nodes[p].setAttribute('dx', vals[p][0]);
          nodes[p].setAttribute('dy', vals[p][1]);
        }
      }
      // the ink purification rides the same eased value — INK at rest
      // (reg 1), TRUE at register (reg 0); see the endpoint tables above
      if (reg !== lastReg) {
        lastReg = reg;
        for (const p in mats) {
          const a = INK[p],
            b = TRUE_[p],
            v = new Array(20);
          for (let i = 0; i < 20; i++) v[i] = (b[i] + (a[i] - b[i]) * reg).toFixed(3);
          mats[p].setAttribute('values', v.join(' '));
        }
      }
      // the text plates lean whatever the photo's register state — the
      // props move with the pointer alone
      const pk = nx.toFixed(3) + ',' + ny.toFixed(3);
      if (pk !== lastProps) {
        lastProps = pk;
        root.style.setProperty('--press-nx', nx.toFixed(3));
        root.style.setProperty('--press-ny', ny.toFixed(3));
      }
      if (regT0 || Math.abs(tx - nx) > 0.002 || Math.abs(ty - ny) > 0.002) schedule();
    };
    const schedule = () => {
      if (!raf) raf = requestAnimationFrame(tick);
    };
    addEventListener('pointermove', e => {
      tx = 2 * e.clientX / innerWidth - 1;
      ty = 2 * e.clientY / innerHeight - 1;
      schedule();
    }, {
      passive: true
    });
    const retarget = to => {
      regFrom = reg;
      regTo = to;
      regT0 = performance.now();
      schedule();
    };
    document.addEventListener('pointerover', e => {
      const p = e.target.closest && e.target.closest('.cmyk .print');
      if (p && !(e.relatedTarget && p.contains(e.relatedTarget))) retarget(0);
    });
    document.addEventListener('pointerout', e => {
      const p = e.target.closest && e.target.closest('.cmyk .print');
      if (p && !(e.relatedTarget && p.contains(e.relatedTarget))) retarget(1);
    });
  };
  if (document.body) mount();else addEventListener('DOMContentLoaded', mount);
})();
})(); } catch (e) { __ds_ns.__errors.push({ path: "print-plates.js", error: String((e && e.message) || e) }); }

})();
