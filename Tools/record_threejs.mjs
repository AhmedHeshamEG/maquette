// X1's three.js project check: a page an agent wrote plays in Chromium the way it plays in Maquette's web sandbox (the
// piece's clock, three.js from the kit's carried copy, no network), and Maquette's recorder takes its scene and motion.
// Run from a folder with `playwright` installed:
//   node record_threejs.mjs <recorder folder> <page folder> <out.json> [expected.json]
// The recorder folder holds `clock.js`, `hook.js` and `record.js` (written by ThreeRecordingTests). With an expected
// recording (the fixture Maquette's own tests read), the new one must say the same: the same things, the same tracks,
// keys within 1e-3.
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';

const [recorder, folder, out, expectedFile] = process.argv.slice(2);
const read = (name) => fs.readFileSync(path.join(recorder, name), 'utf8');
const three = fs.readFileSync(path.join(recorder, 'three.module.js'));
const failures = [];
const check = (ok, message) => { if (!ok) failures.push(message); };

const server = http.createServer((request, response) => {
  const file = path.join(folder, decodeURIComponent(new URL(request.url, 'http://x').pathname));
  fs.readFile(file, (error, data) => {
    if (error) { response.writeHead(404).end(); return; }
    response.writeHead(200, { 'content-type': file.endsWith('.html') ? 'text/html' : 'text/javascript' }).end(data);
  });
});
await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
const { chromium } = await import('playwright');
const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
const page = await browser.newPage({ viewport: { width: 640, height: 360 }, deviceScaleFactor: 1 });
const errors = [];
page.on('pageerror', (error) => errors.push(error.message));
// As in the sandbox: three.js from a CDN is the carried copy, and nothing else leaves the machine.
await page.route(/^https?:\/\/(?!127\.0\.0\.1)/, (route) => {
  if (/three@[^/]*\/build\/three\.module(\.min)?\.js/.test(route.request().url())) {
    route.fulfill({ status: 200, contentType: 'text/javascript', body: three });
  } else {
    route.abort();
  }
});
await page.addInitScript({ content: read('clock.js') });
await page.addInitScript({ content: read('hook.js') });
await page.goto(`http://127.0.0.1:${server.address().port}/index.html`);
await page.evaluate(async () => {
  if (document.readyState !== 'complete') await new Promise((r) => window.addEventListener('load', r, { once: true }));
  window.__hmm.prime();
});
// The page's modules load on real time; the clock waits until the scene stops growing.
let last = -1;
for (let round = 0; round < 40; round++) {
  const count = await page.evaluate(() => window.__maquetteThree.count());
  if (count > 0 && count === last) break;
  last = count;
  await new Promise((r) => setTimeout(r, 100));
}
const output = await page.evaluate(`(async () => { ${read('record.js')} })()`);
await browser.close();
server.close();
fs.writeFileSync(out, output);
const recording = JSON.parse(output);
check(!recording.error, `the recorder said ${output.slice(0, 200)}`);
check(errors.length === 0, `the page reported: ${errors.join(' | ')}`);

if (expectedFile && !recording.error) {
  const expected = JSON.parse(fs.readFileSync(expectedFile, 'utf8'));
  const names = (r) => {
    const byUUID = new Map();
    const walk = (node) => { byUUID.set(node.uuid, node.name || node.type); (node.children || []).forEach(walk); };
    walk(r.scene.object);
    return byUUID;
  };
  const describe = (r) => {
    const byUUID = names(r);
    return new Map((r.scene.animations[0]?.tracks ?? []).map((track) => {
      const dot = track.name.indexOf('.');
      return [`${byUUID.get(track.name.slice(0, dot)) ?? '?'}${track.name.slice(dot)}`, track];
    }));
  };
  const a = describe(recording), b = describe(expected);
  check([...names(recording).values()].sort().join() === [...names(expected).values()].sort().join(), 'the scene has different things');
  check([...a.keys()].sort().join() === [...b.keys()].sort().join(), `tracks differ:\n   now ${[...a.keys()].sort()}\n   was ${[...b.keys()].sort()}`);
  for (const [key, track] of a) {
    const other = b.get(key);
    if (!other) continue;
    // Compare where the motion is at a few moments, not the kept keys (a key's place can shift by a sample).
    const at = (t, time) => {
      const width = t.values.length / t.times.length;
      let i = t.times.findIndex((x) => x >= time);
      if (i < 0) i = t.times.length - 1;
      if (i === 0 || t.times[i] === time) return t.values.slice(i * width, i * width + width);
      const f = (time - t.times[i - 1]) / (t.times[i] - t.times[i - 1]);
      return t.values.slice((i - 1) * width, i * width).map((v, k) => v + (t.values[i * width + k] - v) * f);
    };
    for (const time of [0, 0.5, 1.25, 2, 3.5]) {
      const x = at(track, time), y = at(other, time);
      check(x.every((v, k) => Math.abs(v - y[k]) < 1e-3), `${key} at ${time} s is ${x}, was ${y}`);
    }
  }
  check(JSON.stringify(recording.recording.standIns.map((s) => [s.name, s.path])) === JSON.stringify(expected.recording.standIns.map((s) => [s.name, s.path])),
    'the stand-ins differ');
}

if (failures.length) {
  console.error(`RECORD: ${failures.length} problem(s)\n - ` + failures.join('\n - '));
  process.exit(1);
}
const tracks = recording.scene.animations[0]?.tracks.length ?? 0;
console.log(`RECORD: ok: ${recording.recording.seconds} s recorded, ${tracks} tracks, ${recording.recording.standIns.length} stand-in(s)`);
