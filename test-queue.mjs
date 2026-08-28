// The one thing worth a test in the upload queue: a single bad entry must not
// hold up the good ones behind it. Runs the real source out of index.html —
// no build step, no framework, in keeping with the rest of the project.
//   node test-queue.mjs
import { readFileSync } from 'node:fs';
import assert from 'node:assert';

const src = readFileSync(new URL('index.html', import.meta.url), 'utf8');
const cut = (from, to) => {
  const a = src.indexOf(from), b = src.indexOf(to, a);
  assert.ok(a > -1 && b > a, `index.html no longer contains ${from}`);
  return src.slice(a, b);
};
const code = cut('// One item\'s trip to the server.', 'addEventListener(\'online\'');

let queue, badgeCalls;
const bad = { message: 'Payload too large' };
const run = async items => {
  queue = [...items];
  badgeCalls = 0;
  const sb = {
    from: () => ({
      upsert: async () => ({ error: null }),
        insert: async row => ({ error: queue.find(i => i.id === row.id).fails ? bad : null }),
    }),
    storage: { from: () => ({ upload: async () => ({ error: null }) }) },
  };
  const scope = {
    sb, user: { id: 'u' }, navigator: { onLine: true },
    queued: async () => [...queue],
    idb: async (_mode, fn) => { const s = { delete: id => (queue = queue.filter(i => i.id !== id)) }; fn(s); },
    queueBadge: () => badgeCalls++,
    flushErr: '',
  };
  const keys = Object.keys(scope);
  const fn = new Function(...keys, `${code}\nreturn (async () => { await flushQueue(); return [flushErr, dropped]; })();`);
  const [err, gone] = await fn(...keys.map(k => scope[k]));
  return { left: queue.map(i => i.id), err, gone };
};

const entry = (id, fails = false) => ({ id, kind: 'entry', fails, blob: null, list: 'l' });
// The iOS failure: the File went into IndexedDB and came back with no bytes.
const emptied = id => ({ id, kind: 'entry', blob: { size: 0 }, list: 'l', ext: '.mov' });

// A bad item in the middle: the ones after it still go up, only it is left.
let r = await run([entry('a'), entry('b', true), entry('c')]);
assert.deepStrictEqual(r.left, ['b'], `expected only b stuck, got ${r.left}`);
assert.match(r.err, /Payload too large/);

// Everything good: the queue empties and the badge has nothing to say.
r = await run([entry('a'), entry('b')]);
assert.deepStrictEqual(r.left, []);
assert.strictEqual(r.err, '');

// Two bad ones: both kept, the badge counts them.
r = await run([entry('a', true), entry('b'), entry('c', true)]);
assert.deepStrictEqual(r.left, ['a', 'c']);
assert.match(r.err, /^2 stuck, first: /);

// An entry whose bytes the browser lost can never upload: dropped, not retried
// forever, and the good ones around it are untouched.
r = await run([entry('a'), emptied('b'), entry('c'), emptied('d')]);
assert.deepStrictEqual(r.left, [], `dead entries should not linger, got ${r.left}`);
assert.strictEqual(r.gone, 2);

console.log('ok — bad entries do not block the queue, dead ones are dropped');
