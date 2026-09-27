// The pieces of showcase.mjs that can be wrong without a page looking wrong.
//
//     node --test tool/showcase.test.mjs
import assert from 'node:assert/strict';
import test from 'node:test';

import { changelogMarkdown, compareVersions, indexMarkdown, splitLines } from './showcase.mjs';

test('a span left open across a newline is closed and reopened', () => {
  // Mutation: split on newlines without tracking what is open. A block comment
  // would leave an unclosed tag at the end of its first line and the rest of
  // the file would be drawn inside it.
  assert.deepEqual(
    splitLines('<span class="a">one\ntwo</span>\nthree'),
    ['<span class="a">one</span>', '<span class="a">two</span>', 'three'],
  );
});

test('nested spans are all reopened', () => {
  assert.deepEqual(
    splitLines('<span class="a"><span class="b">x\ny</span></span>'),
    [
      '<span class="a"><span class="b">x</span></span>',
      '<span class="a"><span class="b">y</span></span>',
    ],
  );
});

test('a file with no newline is one line', () => {
  assert.deepEqual(splitLines('plain'), ['plain']);
});

test('the index says how to generate the bundle when there is none', () => {
  assert.match(indexMarkdown(null), /showcase_bundle/);
});

test('the index lists each page under its category with its version', () => {
  const md = indexMarkdown({
    manifest: {
      categories: [{ dir: 'post', title: 'Post-processing' }, { dir: 'empty', title: 'Nothing' }],
      features: [{
        id: 'bloom', title: 'Bloom', category: 'post', since: '0.1.0',
        approximate: false, summary: 'Glow.',
      }],
    },
  });
  assert.match(md, /## Post-processing/);
  assert.match(md, /\[Bloom\]\(\/showcase\/learn\/bloom\/\) \(since 0\.1\.0\): Glow\./);
  assert.doesNotMatch(md, /Nothing/);
});

test('versions compare as numbers, not as text', () => {
  // Mutation: compare the strings. 0.10.0 would sort before 0.9.0 and the
  // changelog would put a release in the middle of the page.
  assert.ok(compareVersions('0.10.0', '0.9.0') > 0);
  assert.ok(compareVersions('0.7.4', '0.7.4+1') === 0);
  assert.ok(compareVersions('0.7.3', '0.7.4') < 0);
});

test('the changelog lists releases newest first, changed pages before new ones', () => {
  const md = changelogMarkdown({
    manifest: {
      categories: [],
      features: [
        {
          id: 'light-shafts', title: 'Light shafts', since: '0.7.0', approximate: false,
          summary: 'Beams.',
          changes: [{ version: '0.7.4', note: 'They scatter now.' }],
        },
        { id: 'fog', title: 'Fog', since: '0.5.1', approximate: true, summary: 'Haze.' },
      ],
    },
  });
  const at = (text) => md.indexOf(text);
  assert.ok(at('## 0.7.4') < at('## 0.7.0'));
  assert.ok(at('## 0.7.0') < at('## 0.5.1'));
  assert.match(md, /\[Light shafts\]\(\/showcase\/learn\/light-shafts\/\): They scatter now\. \(\[live demo\]\(\/showcase\/#\/p\/light-shafts\)\)/);
  // The page is new under the release it arrived in, and not again later.
  assert.ok(at('**New in the showcase**') > at('## 0.7.0'));
  assert.match(md, /\[Fog\]\(\/showcase\/learn\/fog\/\) \(here or earlier\): Haze\./);
});

test('the changelog says how to generate the bundle when there is none', () => {
  assert.match(changelogMarkdown(null), /showcase_bundle/);
});

test('an approximate tag says or earlier', () => {
  const md = indexMarkdown({
    manifest: {
      categories: [{ dir: 'environment', title: 'Light' }],
      features: [{
        id: 'fog', title: 'Fog', category: 'environment', since: '0.5.1',
        approximate: true, summary: 'Haze.',
      }],
    },
  });
  assert.match(md, /since 0\.5\.1 or earlier/);
});
