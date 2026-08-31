/* flutter3d docs — theme, diagrams, navigation. No framework, no build step. */
(function () {
  'use strict';

  // --- theme ---------------------------------------------------------------
  // Dark is the default. The choice is remembered because a reader who wants
  // the light one wants it on every page, not on the one they toggled.
  var STORE = 'flutter3d-theme';
  var root = document.documentElement;

  function currentTheme() {
    return root.getAttribute('data-theme') === 'light' ? 'light' : 'dark';
  }

  function applyTheme(name) {
    if (name === 'light') root.setAttribute('data-theme', 'light');
    else root.removeAttribute('data-theme');
    try { localStorage.setItem(STORE, name); } catch (e) { /* private mode */ }
    var button = document.querySelector('.theme');
    if (button) {
      button.textContent = name === 'light' ? 'Dark' : 'Light';
      button.setAttribute('aria-label', 'Switch to the ' + (name === 'light' ? 'dark' : 'light') + ' theme');
    }
    drawDiagrams();
  }

  try {
    var saved = localStorage.getItem(STORE);
    if (saved === 'light') root.setAttribute('data-theme', 'light');
  } catch (e) { /* private mode */ }

  var meta = document.querySelector('.topbar-meta');
  if (meta) {
    var toggle = document.createElement('button');
    toggle.className = 'theme';
    toggle.type = 'button';
    toggle.textContent = currentTheme() === 'light' ? 'Dark' : 'Light';
    toggle.addEventListener('click', function () {
      applyTheme(currentTheme() === 'light' ? 'dark' : 'light');
    });
    meta.appendChild(toggle);
  }

  // --- diagrams ------------------------------------------------------------
  // Mermaid is themed from the same tokens as the page, so a diagram never
  // arrives as a white rectangle in a dark document.
  var sources = [];
  document.querySelectorAll('pre.mermaid').forEach(function (node) {
    sources.push({ node: node, text: node.textContent });
  });

  function themeVariables() {
    var light = currentTheme() === 'light';
    return {
      darkMode: !light,
      background: light ? '#ffffff' : '#131a22',
      primaryColor: light ? '#eef1f4' : '#0e141b',
      primaryTextColor: light ? '#10161c' : '#e6edf3',
      primaryBorderColor: light ? '#b8530e' : '#ff8a3d',
      secondaryColor: light ? '#e4edf0' : '#16222b',
      tertiaryColor: light ? '#f4f6f8' : '#111820',
      lineColor: light ? '#5c6c7a' : '#4dd0e1',
      textColor: light ? '#10161c' : '#e6edf3',
      mainBkg: light ? '#eef1f4' : '#0e141b',
      nodeBorder: light ? '#b8530e' : '#ff8a3d',
      clusterBkg: light ? '#f4f6f8' : '#111820',
      clusterBorder: light ? '#d8dfe6' : '#22303c',
      edgeLabelBackground: light ? '#ffffff' : '#131a22',
      fontFamily: 'ui-monospace, SFMono-Regular, Menlo, Consolas, monospace',
      fontSize: '13px',
      actorBkg: light ? '#eef1f4' : '#0e141b',
      actorBorder: light ? '#b8530e' : '#ff8a3d',
      actorTextColor: light ? '#10161c' : '#e6edf3',
      signalColor: light ? '#5c6c7a' : '#8a9ba8',
      signalTextColor: light ? '#10161c' : '#e6edf3',
      labelBoxBkgColor: light ? '#eef1f4' : '#0e141b',
      labelBoxBorderColor: light ? '#b8530e' : '#ff8a3d',
      labelTextColor: light ? '#10161c' : '#e6edf3',
      loopTextColor: light ? '#10161c' : '#e6edf3',
      noteBkgColor: light ? '#fdf3e7' : '#1b2129',
      noteBorderColor: light ? '#b8530e' : '#b35d21',
      noteTextColor: light ? '#10161c' : '#e6edf3',
      sequenceNumberColor: light ? '#ffffff' : '#0b0f14'
    };
  }

  var drawing = false;
  function drawDiagrams() {
    if (!window.mermaid || !sources.length || drawing) return;
    drawing = true;
    sources.forEach(function (item) {
      item.node.removeAttribute('data-processed');
      item.node.textContent = item.text;
    });
    window.mermaid.initialize({
      startOnLoad: false,
      securityLevel: 'strict',
      theme: 'base',
      themeVariables: themeVariables(),
      flowchart: { curve: 'basis', padding: 12, useMaxWidth: true },
      sequence: { useMaxWidth: true, wrap: true }
    });
    window.mermaid.run({ nodes: sources.map(function (i) { return i.node; }) })
      .catch(function (error) { console.error('mermaid:', error); })
      .finally(function () { drawing = false; });
  }
  drawDiagrams();

  // --- mobile navigation ---------------------------------------------------
  var railToggle = document.querySelector('.rail-toggle');
  var rail = document.getElementById('rail');
  if (railToggle && rail) {
    railToggle.addEventListener('click', function () {
      var open = rail.classList.toggle('open');
      railToggle.setAttribute('aria-expanded', String(open));
    });
  }

  // --- table of contents ---------------------------------------------------
  // Marks the section the reader is actually in, not the last one they passed:
  // the heading nearest the top of the viewport wins.
  var links = Array.prototype.slice.call(document.querySelectorAll('.toc a'));
  if (links.length) {
    var targets = links
      .map(function (a) { return document.getElementById(decodeURIComponent(a.hash.slice(1))); })
      .filter(Boolean);

    var mark = function () {
      var best = 0;
      for (var i = 0; i < targets.length; i++) {
        if (targets[i].getBoundingClientRect().top - 96 <= 0) best = i;
      }
      links.forEach(function (a, i) { a.classList.toggle('on', i === best); });
    };

    var pending = false;
    window.addEventListener('scroll', function () {
      if (pending) return;
      pending = true;
      window.requestAnimationFrame(function () { mark(); pending = false; });
    }, { passive: true });
    mark();
  }
})();
