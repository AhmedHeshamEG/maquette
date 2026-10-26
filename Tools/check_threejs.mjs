// X1's three.js check. Run from a folder with `three@0.170.0` (and `playwright` for `render`) installed:
//   node check_threejs.mjs structure <web folder>   GLTFLoader and ObjectLoader read the folder's two scene files and
//                                                   agree with each other and with what Maquette wrote (expected.json).
//   node check_threejs.mjs render <web folder>      Chromium plays the folder's index.html at a moment; what it draws
//                                                   must cover Maquette's own silhouette of that moment (expected-mask.pgm).
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const [mode, folder] = process.argv.slice(2);
const expected = JSON.parse(fs.readFileSync(path.join(folder, 'expected.json'), 'utf8'));
const failures = [];
const check = (ok, message) => { if (!ok) failures.push(message); };

if (mode === 'structure') await structure();
else if (mode === 'render') await render();
else throw new Error(`unknown mode ${mode}`);

if (failures.length) {
  console.error(`THREEJS: ${failures.length} problem(s)\n - ` + failures.join('\n - '));
  process.exit(1);
}

async function structure() {
  const THREE = await import('three');
  const { GLTFLoader } = await import('three/examples/jsm/loaders/GLTFLoader.js');
  // The folder's pointer plugin, resolved against this folder's `three`.
  const plugin = path.resolve('pointer.mjs');
  fs.copyFileSync(path.join(folder, 'maquette/pointer.js'), plugin);
  const { withPointerTracks } = await import(pathToFileURL(plugin).href);

  const glb = fs.readFileSync(path.join(folder, 'scene.glb'));
  const gltf = await new GLTFLoader().parseAsync(glb.buffer.slice(glb.byteOffset, glb.byteOffset + glb.byteLength), '');
  const fromJSON = new THREE.ObjectLoader().parse(JSON.parse(fs.readFileSync(path.join(folder, 'scene.json'), 'utf8')));
  const glbClips = await withPointerTracks(gltf);

  const named = (root) => {
    const result = new Map();
    root.traverse((object) => { if (object.name && !object.name.endsWith('_target')) result.set(object.name, object); });
    return result;
  };
  const a = named(gltf.scene), b = named(fromJSON);
  check([...a.keys()].sort().join() === [...b.keys()].sort().join(), `names differ: glb ${[...a.keys()]} json ${[...b.keys()]}`);
  for (const name of expected.meshes) check(a.get(name)?.isMesh && b.get(name)?.isMesh, `${name} is a mesh in both`);
  for (const name of expected.cameras) check(a.get(name)?.isCamera && b.get(name)?.isCamera, `${name} is a camera in both`);
  for (const name of expected.lights) check(a.get(name)?.isLight && b.get(name)?.isLight, `${name} is a light in both`);
  gltf.scene.updateMatrixWorld(true);
  fromJSON.updateMatrixWorld(true);
  for (const [name, position] of Object.entries(expected.worldAtZero)) {
    for (const [label, object] of [['glb', a.get(name)], ['json', b.get(name)]]) {
      const world = object ? new THREE.Vector3().setFromMatrixPosition(object.matrixWorld).toArray() : [NaN];
      check(world.every((v, i) => Math.abs(v - position[i]) < 1e-4), `${name} (${label}) is at ${world}, Maquette has ${position}`);
    }
  }

  // The clips: the same names, the same tracks on the same things, the same values.
  const describe = (clips, root) => new Map(clips.flatMap((clip) => clip.tracks.map((track) => {
    const parsed = THREE.PropertyBinding.parseTrackName(track.name);
    const target = THREE.PropertyBinding.findNode(root, parsed.nodeName);
    const property = [parsed.objectName, parsed.propertyName].filter(Boolean).join('.');
    return [`${clip.name}/${target?.name ?? '?' + parsed.nodeName}.${property}`, track];
  })));
  check(glbClips.map((c) => c.name).join() === expected.clips.join(), `clips ${glbClips.map((c) => c.name)} (expected ${expected.clips})`);
  check(fromJSON.animations.map((c) => c.name).join() === expected.clips.join(), `scene.json clips ${fromJSON.animations.map((c) => c.name)}`);
  const ta = describe(glbClips, gltf.scene), tb = describe(fromJSON.animations, fromJSON);
  check([...ta.keys()].sort().join() === [...tb.keys()].sort().join(), `tracks differ:\n   glb  ${[...ta.keys()].sort()}\n   json ${[...tb.keys()].sort()}`);
  for (const [key, track] of ta) {
    const other = tb.get(key);
    if (!other) continue;
    const same = (x, y) => x.length === y.length && Array.from(x).every((v, i) => Math.abs(v - y[i]) < 1e-4);
    check(same(track.times, other.times) && same(track.values, other.values), `${key} has different keys`);
    check(!key.includes('?'), `${key} points at nothing`);
  }

  // Both play the same moment the same way.
  const moment = expected.renderAt;
  const play = (root, clips) => {
    const mixer = new THREE.AnimationMixer(root);
    for (const clip of clips) mixer.clipAction(clip).play();
    mixer.setTime(moment);
    root.updateMatrixWorld(true);
  };
  play(gltf.scene, glbClips);
  play(fromJSON, fromJSON.animations);
  for (const [name, object] of a) {
    const other = b.get(name);
    const same = object.matrixWorld.elements.every((v, i) => Math.abs(v - other.matrixWorld.elements[i]) < 1e-4);
    check(same, `${name} isn't in the same place at ${moment} s`);
    // scene.json keeps a still colour as an 8-bit sRGB number, as three.js's own toJSON does.
    if (object.isMesh) check(object.material.color.getHex() === other.material.color.getHex(), `${name}'s colour differs at ${moment} s`);
    if (object.isCamera) check(Math.abs(object.fov - other.fov) < 1e-3, `${name}'s lens differs at ${moment} s`);
  }
  console.log(`THREEJS: structure ok: ${a.size} named things, ${ta.size} tracks, the GLB and scene.json agree`);
}

async function render() {
  const { chromium } = await import('playwright');
  const types = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.json': 'application/json', '.glb': 'model/gltf-binary' };
  const server = http.createServer((request, response) => {
    const file = path.join(folder, decodeURIComponent(new URL(request.url, 'http://x').pathname));
    if (!file.startsWith(path.resolve(folder)) && !file.startsWith(folder)) { response.writeHead(403).end(); return; }
    fs.readFile(file, (error, data) => {
      if (error) { response.writeHead(404).end(); return; }
      response.writeHead(200, { 'content-type': types[path.extname(file)] ?? 'application/octet-stream' }).end(data);
    });
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const { width, height } = expected;
  const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const page = await browser.newPage({ viewport: { width, height }, deviceScaleFactor: 1 });
  const errors = [];
  page.on('pageerror', (error) => errors.push(error.message));
  page.on('console', (message) => { if (message.type() === 'error') errors.push(message.text()); });
  await page.goto(`http://127.0.0.1:${server.address().port}/index.html?t=${expected.renderAt}&transparent`);
  await page.waitForFunction(() => window.maquette?.ready === true, null, { timeout: 60000 });
  const { alpha, png } = await page.evaluate(() => {
    const source = window.maquette.renderer.domElement;
    const canvas = document.createElement('canvas');
    canvas.width = source.width; canvas.height = source.height;
    const context = canvas.getContext('2d');
    context.drawImage(source, 0, 0);
    const pixels = context.getImageData(0, 0, canvas.width, canvas.height).data;
    let bytes = '';
    for (let i = 3; i < pixels.length; i += 4) bytes += String.fromCharCode(pixels[i] > 16 ? 255 : 0);
    return { alpha: btoa(bytes), png: source.toDataURL('image/png') };
  });
  await browser.close();
  server.close();
  fs.writeFileSync(path.join(folder, 'rendered.png'), Buffer.from(png.split(',')[1], 'base64'));
  check(errors.length === 0, `the page reported: ${errors.join(' | ')}`);

  const drawn = Buffer.from(alpha, 'base64');
  const pgm = fs.readFileSync(path.join(folder, 'expected-mask.pgm'));
  const golden = pgm.subarray(pgm.length - width * height);
  let both = 0, either = 0, ours = 0, theirs = 0;
  for (let i = 0; i < width * height; i++) {
    const g = golden[i] > 0, d = drawn[i] > 0;
    if (g && d) both++;
    if (g || d) either++;
    if (g) ours++;
    if (d) theirs++;
  }
  const overlap = either ? both / either : 0;
  console.log(`THREEJS: render: Maquette's silhouette ${ours} px, three.js drew ${theirs} px, overlap ${(overlap * 100).toFixed(1)}%`);
  check(drawn.length === width * height, `the canvas is ${drawn.length} px, expected ${width * height}`);
  check(overlap >= 0.9, `three.js's picture covers Maquette's silhouette only ${(overlap * 100).toFixed(1)}% (needs 90%)`);
}
