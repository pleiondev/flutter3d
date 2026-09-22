// The pieces of showcase.mjs that can be wrong without a page looking wrong.
//
//     node --test tool/showcase.test.mjs
import assert from 'node:assert/strict';
import test from 'node:test';

import { indexMarkdown, splitLines } from './showcase.mjs';

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
