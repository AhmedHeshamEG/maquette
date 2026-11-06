// The site's world: the Keeper's Tower from Maquette's samples, eleven stops around it, and a camera on the scroll.
// Drawn in Maquette's own Ink Look (maquette/look.js, from the app's three.js export). No motion → the still image.
import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { applyLook } from './maquette/look.js';

const INK = { model: 'toon', name: 'Ink', bands: 2, threshold: 0.5, midThreshold: 0.78, shadowValue: 0.35, edgeSoftness: 0.03,
  faceted: false, halftone: null, pixel: null, lines: { color: 0x120f17, width: 1.6 } };
const RING = 15;
const TOP = 0.24; // the top of a stop's plinth
// How far each section pushes the subject away from its card (0 = centred): opening, 11 stops, road, wall, end, questions.
const FRAMING = [0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 1, 0.6];

const query = new URLSearchParams(location.search);
const pinned = query.has('s') ? Number(query.get('s')) : null; // ?s=3 holds the camera on a stop (screenshots)
const framingScale = query.has('f') ? Number(query.get('f')) : 1; // ?f=-1 frames the other way (the social preview)
const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches && pinned === null;
const holder = document.getElementById('world');
const canvasOK = (() => { try { return !!document.createElement('canvas').getContext('webgl2'); } catch { return false; } })();

setUpTheBar();
if (query.has('bare')) document.documentElement.classList.add('bare'); // the world alone (the still, the preview)
if (!reduced && canvasOK) start().catch((error) => console.warn('The world stays a picture:', error));

async function start() {
  const renderer = new THREE.WebGLRenderer({ antialias: true, powerPreference: 'high-performance', preserveDrawingBuffer: pinned !== null });
  const small = Math.min(innerWidth, innerHeight) < 700;
  renderer.setPixelRatio(Math.min(devicePixelRatio, small ? 1.5 : 2));
  renderer.setSize(innerWidth, innerHeight);
  renderer.shadowMap.enabled = !small;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  holder.prepend(renderer.domElement);

  const scene = new THREE.Scene();
  scene.background = sky('#0b1028', '#2a3156');
  scene.fog = new THREE.Fog('#1b2240', 34, 95);
  scene.add(new THREE.HemisphereLight('#c3c9dc', '#3a3440', 1.25));
  const moon = new THREE.DirectionalLight('#eef1ff', 2.3);
  moon.position.set(-18, 30, 14);
  moon.castShadow = true;
  moon.shadow.mapSize.set(2048, 2048);
  Object.assign(moon.shadow.camera, { left: -30, right: 30, top: 30, bottom: -30, far: 90 });
  scene.add(moon);
  scene.add(stars());

  const ground = new THREE.Mesh(new THREE.CircleGeometry(48, 96), standard('#3a3d4a', { roughness: 1 }));
  ground.rotation.x = -Math.PI / 2;
  ground.receiveShadow = true;
  scene.add(ground);
  const path = new THREE.Mesh(new THREE.RingGeometry(RING - 0.9, RING + 0.9, 128), standard('#55515f', { roughness: 1 }));
  path.rotation.x = -Math.PI / 2;
  path.position.y = 0.02;
  path.receiveShadow = true;
  scene.add(path);

  scene.add(tower());
  const stops = buildStops(scene);
  const load = loadModels(scene, stops);

  const camera = new THREE.PerspectiveCamera(42, innerWidth / innerHeight, 0.1, 300);
  await load; // the Look turns every material to Ink once, so the Kit models come first (they're tiny)
  const look = applyLook(renderer, scene, INK);
  const keys = keyframes(stops);
  const posCurve = new THREE.CatmullRomCurve3(keys.map((k) => k.pos), false, 'centripetal');
  const lookCurve = new THREE.CatmullRomCurve3(keys.map((k) => k.target), false, 'centripetal');
  const sections = [...document.querySelectorAll('[data-key]')];
  let centres = [];
  const measure = () => { centres = sections.map((el) => el.offsetTop + el.offsetHeight / 2); };

  function wanted() {
    if (pinned !== null) return pinned;
    const y = scrollY + innerHeight / 2;
    if (y <= centres[0]) return 0;
    for (let k = 0; k < centres.length - 1; k++) {
      if (y < centres[k + 1]) return k + (y - centres[k]) / (centres[k + 1] - centres[k]);
    }
    return centres.length - 1;
  }

  function resize() {
    renderer.setSize(innerWidth, innerHeight);
    look.setSize(innerWidth, innerHeight);
    camera.aspect = innerWidth / innerHeight;
    measure();
  }
  addEventListener('resize', resize);
  resize();

  let s = wanted();
  let last = performance.now();
  const clock = { t: query.has('t') ? Number(query.get('t')) : 0 };
  const point = new THREE.Vector3();
  const target = new THREE.Vector3();

  function frame(now) {
    // The first frame's timestamp can be a little before `last`, so time never runs backwards.
    const dt = THREE.MathUtils.clamp((now - last) / 1000, 0, 0.1);
    last = now;
    if (!query.has('t')) clock.t += dt;
    s += (wanted() - s) * (pinned !== null ? 1 : 1 - Math.exp(-dt * 3.2));
    const u = THREE.MathUtils.clamp(s / (keys.length - 1), 0, 1);
    posCurve.getPoint(u, point);
    lookCurve.getPoint(u, target);
    // A tall screen sees less from side to side, so the camera steps back to keep the same things in frame.
    const back = camera.aspect < 1 ? Math.pow(1 / camera.aspect, 0.62) : 1;
    camera.position.copy(target).addScaledVector(point.sub(target), back);
    camera.lookAt(target);
    // On a stop the card covers one side, so the camera frames the stop on the other.
    const i = THREE.MathUtils.clamp(Math.floor(s), 0, FRAMING.length - 2);
    const weight = THREE.MathUtils.lerp(FRAMING[i], FRAMING[i + 1], THREE.MathUtils.clamp(s - i, 0, 1)) * framingScale;
    const wide = innerWidth >= 900;
    camera.setViewOffset(innerWidth, innerHeight, wide ? -innerWidth * 0.17 * weight : 0, wide ? 0 : innerHeight * 0.14 * weight, innerWidth, innerHeight);
    camera.updateProjectionMatrix();
    for (const stop of stops) stop.update?.(clock.t);
    look.render(scene, camera);
  }

  renderer.setAnimationLoop(frame);
  document.documentElement.classList.add('live');
  requestAnimationFrame(() => requestAnimationFrame(() => { window.worldReady = true; }));
}

// ———————————————————————————————————————— the Look and the materials


function standard(color, extra = {}) {
  return new THREE.MeshStandardMaterial({ color, roughness: 0.85, ...extra });
}
function glow(color, strength) {
  return standard(color, { emissive: new THREE.Color(color), emissiveIntensity: strength });
}
function noLines(material) {
  material.userData.outlineParameters = { visible: false };
  return material;
}
function shadows(object) {
  object.traverse((o) => { if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; } });
  return object;
}

/** A Scene Script shape with its origin at the bottom centre, sized like the app sizes it. */
function shape(kind, [w, h, d], material) {
  let geometry;
  if (kind === 'cylinder') geometry = new THREE.CylinderGeometry(0.5, 0.5, 1, 40);
  else if (kind === 'cone') geometry = new THREE.ConeGeometry(0.5, 1, 40);
  else if (kind === 'sphere') geometry = new THREE.SphereGeometry(0.5, 32, 20);
  else geometry = new THREE.BoxGeometry(1, 1, 1);
  geometry.translate(0, 0.5, 0);
  const mesh = new THREE.Mesh(geometry, material);
  mesh.scale.set(w, h, d);
  return mesh;
}

// ———————————————————————————————————————— the Keeper's Tower (KeepersTowerSample.swift, the same script)

function tower() {
  const world = new THREE.Group();
  world.name = "The Keeper's Tower";
  const add = (parent, kind, at, size, color, light = 0) => {
    const mesh = shape(kind, size, light ? glow(color, light) : standard(color));
    mesh.position.set(...at);
    parent.add(mesh);
    return mesh;
  };
  add(world, 'cone', [0, 0, 0], [10, 0.7, 9], '#3C3A40');
  add(world, 'sphere', [-3.6, 0, 2.2], [1.1, 0.8, 1], '#45434B');
  add(world, 'sphere', [3.9, 0, -1.6], [0.7, 0.5, 0.6], '#45434B');
  const body = new THREE.Group();
  body.position.set(0, 0.6, 0);
  body.rotation.z = THREE.MathUtils.degToRad(-6);
  world.add(body);
  const courses = [
    ['cylinder', [0, 0, 0], [3, 1.6, 3], '#6E6A73'], ['cylinder', [0, 1.6, 0], [3.15, 0.15, 3.15], '#4B4852'],
    ['cylinder', [0.05, 1.75, 0], [2.85, 1.6, 2.85], '#716D76'], ['cylinder', [0.05, 3.35, 0], [3, 0.15, 3], '#4B4852'],
    ['cylinder', [0, 3.5, 0], [2.7, 1.6, 2.7], '#6A6670'], ['cylinder', [0, 5.1, 0], [2.85, 0.15, 2.85], '#4B4852'],
    ['cylinder', [-0.04, 5.25, 0], [2.55, 1.6, 2.55], '#726E78'], ['cylinder', [-0.04, 6.85, 0], [2.7, 0.15, 2.7], '#4B4852'],
    ['cylinder', [0, 7, 0], [2.4, 1.6, 2.4], '#6E6A73'], ['cylinder', [0, 8.6, 0], [3.2, 0.18, 3.2], '#2E2B33'],
    ['cylinder', [0, 8.78, 0], [1.7, 1.3, 1.7], '#2E2B33'],
  ];
  for (const [kind, at, size, color] of courses) add(body, kind, at, size, color);
  add(body, 'cylinder', [0, 8.88, 0], [1.78, 1.1, 1.78], '#FFB347', 2.2);
  add(body, 'cone', [0, 10.08, 0], [2.1, 1.2, 2.1], '#3A2F35');
  add(body, 'sphere', [0, 11.22, 0], [0.25, 0.25, 0.25], '#3A2F35');
  add(body, 'cube', [0, 0, 1.47], [0.7, 1.1, 0.12], '#3B2A20');
  add(body, 'cube', [0.05, 2.35, 1.4], [0.32, 0.55, 0.1], '#1B1A22');
  add(body, 'cube', [-0.04, 5.8, 1.25], [0.3, 0.5, 0.1], '#FFB347', 1.5);
  const lamp = new THREE.PointLight('#FFB347', 60, 40, 1.6);
  lamp.position.set(0.98, 9.95, 0);
  world.add(lamp);

  const keeper = new THREE.Group();
  keeper.position.set(2.3, 0.62, 3.1);
  keeper.rotation.y = THREE.MathUtils.degToRad(-25);
  world.add(keeper);
  add(keeper, 'cylinder', [0, 0, 0], [0.3, 0.5, 0.3], '#2F3E5C');
  add(keeper, 'sphere', [0, 0.5, 0], [0.22, 0.22, 0.22], '#F2C9A0');
  add(keeper, 'cone', [0, 0.66, 0], [0.28, 0.2, 0.28], '#1E1A1C');
  add(keeper, 'cube', [0.21, 0.2, 0.05], [0.09, 0.12, 0.09], '#FFB347', 4);
  const lantern = new THREE.PointLight('#FFB347', 3, 4, 1.5);
  lantern.position.set(2.5, 0.95, 3.2);
  world.add(lantern);
  return shadows(world);
}

// ———————————————————————————————————————— the stops

/** Where stop i stands: on the path around the tower, the first one facing the opening camera. */
function placeOf(i) {
  const angle = Math.PI * 0.62 - (i * Math.PI * 2) / 11;
  return new THREE.Vector3(Math.cos(angle) * RING, 0, Math.sin(angle) * RING);
}

function buildStops(scene) {
  const makers = [draw, shapeStop, build, paint, characters, talk, physics, film, looks, out, yours];
  return makers.map((make, i) => {
    const group = new THREE.Group();
    const at = placeOf(i);
    group.position.copy(at);
    group.lookAt(0, 0, 0); // +z faces the tower; the camera stands outside, looking in
    group.rotateY(Math.PI);
    const plinth = shape('cylinder', [5.2, 0.24, 5.2], standard('#4b4852'));
    group.add(plinth);
    const stop = { group, at, index: i, models: [] };
    make(group, stop);
    scene.add(shadows(group));
    return stop;
  });
}


function draw(group, stop) {
  const points = [];
  for (let k = 0; k <= 40; k++) {
    const t = k / 40;
    points.push(new THREE.Vector3(Math.sin(t * Math.PI * 2.2) * 1.4, 0.9 + t * 2.1 + Math.sin(t * 9) * 0.2, Math.cos(t * Math.PI * 2.2) * 0.9));
  }
  const curve = new THREE.CatmullRomCurve3(points);
  const geometry = new THREE.TubeGeometry(curve, 240, 0.07, 10, false);
  const line = new THREE.Mesh(geometry, glow('#ffb347', 0.9));
  group.add(line);
  const pencil = new THREE.Group();
  const shaft = shape('cylinder', [0.12, 1.1, 0.12], standard('#f4efe6'));
  shaft.position.y = 0.12;
  const tip = shape('cone', [0.12, 0.14, 0.12], standard('#2b2833'));
  tip.rotation.x = Math.PI;
  tip.position.y = 0.14;
  pencil.add(shaft, tip);
  pencil.rotation.z = 0.5;
  group.add(pencil);
  const total = geometry.index.count;
  stop.update = (t) => {
    const p = (t % 5) / 3.6;
    const shown = THREE.MathUtils.clamp(p, 0, 1);
    geometry.setDrawRange(0, Math.floor(total * shown / 6) * 6);
    curve.getPoint(Math.max(shown, 0.001), pencil.position);
  };
}

function shapeStop(group, stop) {
  const outline = new THREE.Shape();
  for (let k = 0; k < 10; k++) {
    const r = k % 2 ? 0.55 : 1.25;
    const a = (k / 10) * Math.PI * 2;
    outline[k ? 'lineTo' : 'moveTo'](Math.cos(a) * r, Math.sin(a) * r);
  }
  const geometry = new THREE.ExtrudeGeometry(outline, { depth: 1, bevelEnabled: true, bevelSize: 0.06, bevelThickness: 0.06, bevelSegments: 2 });
  geometry.rotateX(-Math.PI / 2);
  const star = new THREE.Mesh(geometry, standard('#e9c46a'));
  star.position.y = TOP;
  group.add(star);
  const sketch = new THREE.LineLoop(new THREE.BufferGeometry().setFromPoints(outline.getPoints().map((p) => new THREE.Vector3(p.x, 0, -p.y))),
    noLines(new THREE.LineBasicMaterial({ color: '#ffb347' })));
  sketch.position.y = TOP + 0.03;
  group.add(sketch);
  stop.update = (t) => {
    const p = THREE.MathUtils.smoothstep((t % 4.5) / 2.2, 0, 1);
    star.scale.y = 0.02 + p * 1.5;
    star.rotation.y = t * 0.3;
    sketch.rotation.y = star.rotation.y;
  };
}

function build(group, stop) {
  stop.models.push(
    { id: 'room-floorfull', at: [-0.96, TOP, -0.96], s: 1 }, { id: 'room-floorfull', at: [0.96, TOP, -0.96], s: 1 },
    { id: 'room-floorfull', at: [-0.96, TOP, 0.96], s: 1 }, { id: 'room-floorfull', at: [0.96, TOP, 0.96], s: 1 },
    { id: 'room-wall', at: [-0.96, TOP, -1.9], s: 1 }, { id: 'room-wallwindow', at: [0.96, TOP, -1.9], s: 1 },
    { id: 'room-walldoorway', at: [-1.9, TOP, -0.96], s: 1, ry: Math.PI / 2 },
    { id: 'room-wall', at: [1.9, TOP, -0.96], s: 1, ry: -Math.PI / 2, name: 'drop' },
  );
  stop.update = (t) => {
    const drop = stop.loaded?.drop;
    if (!drop) return;
    const p = THREE.MathUtils.clamp(((t + 1.3) % 4) / 0.9, 0, 1);
    drop.position.y = TOP + (1 - p * p) * 3.2;
  };
}

function paint(group, stop) {
  stop.models.push({ id: 'nature-pot-large', at: [0, TOP, 0], s: 1.4, name: 'pot' });
  const brush = new THREE.Group();
  const handle = shape('cylinder', [0.1, 1.2, 0.1], standard('#8b5a3c'));
  const bristles = shape('cone', [0.2, 0.3, 0.2], standard('#ffb347'));
  bristles.rotation.x = Math.PI;
  bristles.position.y = 0.0;
  handle.position.y = 0.02;
  brush.add(handle, bristles);
  group.add(brush);
  const colours = ['#c8553d', '#e9c46a', '#4f9d8f', '#8e7dbe'].map((c) => new THREE.Color(c));
  const tint = new THREE.Color();
  stop.update = (t) => {
    const a = t * 1.2;
    brush.position.set(Math.cos(a) * 1.2, 1.2 + Math.sin(t * 3) * 0.08, Math.sin(a) * 1.0);
    brush.rotation.z = 0.5;
    const pot = stop.loaded?.pot;
    if (!pot) return;
    const k = (((t / 2) % colours.length) + colours.length) % colours.length;
    tint.copy(colours[Math.floor(k)]).lerp(colours[(Math.floor(k) + 1) % colours.length], THREE.MathUtils.smoothstep(k % 1, 0.6, 1));
    pot.traverse((o) => { if (o.isMesh) o.material.color.copy(tint); });
  };
}

function face(parent, { y, z, spread = 0.2, size = 0.16, mouth = true }) {
  const white = standard('#fbfaf7');
  const black = standard('#141018');
  const eyes = [];
  for (const side of [-1, 1]) {
    const eye = shape('sphere', [size, size * 1.15, size * 0.6], white);
    eye.position.set(side * spread, y, z);
    const pupil = shape('sphere', [size * 0.5, size * 0.6, size * 0.3], black);
    pupil.position.set(0, 0.25, 0.45);
    pupil.scale.set(0.5, 0.5, 0.5);
    eye.add(pupil);
    parent.add(eye);
    eyes.push(eye);
  }
  let lips = null;
  if (mouth) {
    lips = shape('sphere', [size * 1.4, size * 0.5, size * 0.4], black);
    lips.position.set(0, y - size * 1.3, z);
    parent.add(lips);
  }
  return { eyes, lips };
}

function characters(group, stop) {
  stop.models.push({ id: 'kitchen-toaster', at: [0, TOP, 0], s: 5.5, name: 'toaster' });
  const faceGroup = new THREE.Group();
  group.add(faceGroup);
  const { eyes, lips } = face(faceGroup, { y: TOP + 0.75, z: 0.55, spread: 0.32, size: 0.3 });
  lips.scale.y *= 0.6;
  stop.update = (t) => {
    const blink = (t % 3.1) < 0.12 ? 0.1 : 1;
    for (const eye of eyes) eye.scale.y = 0.345 * blink;
    faceGroup.position.y = Math.abs(Math.sin(t * 2.2)) * 0.12;
    const toaster = stop.loaded?.toaster;
    if (toaster) toaster.position.y = TOP + faceGroup.position.y;
  };
}

function talk(group, stop) {
  stop.models.push({ id: 'kitchen-apple', at: [0, TOP, 0], s: 20, name: 'apple' });
  const faceGroup = new THREE.Group();
  group.add(faceGroup);
  const { eyes, lips } = face(faceGroup, { y: TOP + 1.0, z: 0.78, spread: 0.3, size: 0.28 });
  const bubble = label('hi!', { w: 1.6, h: 1.0, font: 120, round: true });
  bubble.position.set(1.4, TOP + 2.6, 0.3);
  group.add(bubble);
  const lipsY = lips.scale.y;
  stop.update = (t) => {
    const syllable = Math.max(0, Math.sin(t * 11) * Math.sin(t * 2.3));
    lips.scale.y = lipsY * (0.35 + syllable * 1.6);
    bubble.position.y = TOP + 2.6 + Math.sin(t * 2) * 0.08;
    bubble.scale.setScalar(0.9 + Math.max(0, Math.sin(t * 2.3)) * 0.15);
    for (const eye of eyes) eye.scale.y = 0.322 * ((t % 2.7) < 0.1 ? 0.1 : 1);
  };
}

function physics(group, stop) {
  const boxes = [];
  const colours = ['#c8553d', '#e9c46a', '#4f9d8f', '#f4efe6', '#8e7dbe', '#d98c5f'];
  for (let k = 0; k < 6; k++) {
    const box = shape('cube', [0.7, 0.7, 0.7], standard(colours[k]));
    box.geometry = box.geometry.clone().translate(0, -0.5, 0);
    group.add(box);
    boxes.push({ mesh: box, x: (k % 3 - 1) * 0.75, z: Math.floor(k / 3) * 0.85 - 0.4, delay: k * 0.18, spin: (k % 2 ? 1 : -1) * (1 + k * 0.4) });
  }
  const ball = shape('sphere', [0.9, 0.9, 0.9], standard('#2f3e5c'));
  ball.geometry = ball.geometry.clone().translate(0, -0.5, 0);
  group.add(ball);
  stop.update = (t) => {
    const cycle = t % 5.5;
    for (const b of boxes) {
      const fall = Math.max(0, cycle - b.delay);
      let y = 4 + b.delay * 2 - 4.9 * fall * fall;
      let spin = b.spin * fall;
      const rest = TOP;
      if (y < rest) {
        const hit = Math.sqrt((4 + b.delay * 2 - rest) / 4.9);
        const after = fall - hit;
        const bounce = Math.abs(Math.sin(after * 7)) * Math.exp(-after * 5) * 0.6;
        y = rest + bounce;
        spin = b.spin * hit + b.spin * 0.3 * (1 - Math.exp(-after * 4));
      }
      b.mesh.position.set(b.x, y + 0.35, b.z);
      b.mesh.rotation.set(spin * 0.4, spin, spin * 0.2);
    }
    const roll = THREE.MathUtils.clamp((cycle - 3.2) / 1.4, 0, 1);
    ball.position.set(-2.2 + roll * 1.2, TOP + 0.45, 1.6 - roll * 0.8);
    ball.rotation.z = -roll * 4;
  };
}

function film(group, stop) {
  const base = shape('cylinder', [0.8, 0.5, 0.8], standard('#2e2b33'));
  base.position.y = TOP;
  group.add(base);
  const mast = shape('cylinder', [0.18, 1.6, 0.18], standard('#4b4852'));
  mast.position.y = TOP + 0.5;
  group.add(mast);
  const arm = new THREE.Group();
  arm.position.y = TOP + 2.1;
  group.add(arm);
  const beam = shape('cube', [3.2, 0.14, 0.14], standard('#6e6a73'));
  beam.position.x = 0.8;
  beam.geometry = beam.geometry.clone().translate(0, -0.5, 0);
  arm.add(beam);
  const weight = shape('cube', [0.4, 0.4, 0.4], standard('#2e2b33'));
  weight.position.set(-0.8, -0.2, 0);
  arm.add(weight);
  const body = shape('cube', [0.55, 0.42, 0.75], standard('#1e1a1c'));
  body.position.set(2.4, -0.62, 0);
  arm.add(body);
  const lens = shape('cylinder', [0.3, 0.4, 0.3], standard('#2b2833'));
  lens.rotation.x = Math.PI / 2;
  lens.position.set(2.4, -0.42, 0.37);
  arm.add(lens);
  const tally = shape('sphere', [0.08, 0.08, 0.08], glow('#ff4d4d', 3));
  tally.position.set(2.4, -0.18, 0.2);
  arm.add(tally);
  const ticks = [];
  for (let k = 0; k < 7; k++) {
    const rail = shape('cube', [0.2, 0.06, 0.3], standard('#5d5866'));
    rail.position.set(-2 + k * 0.62, TOP, 1.9);
    group.add(rail);
    ticks.push(rail);
  }
  stop.update = (t) => {
    arm.rotation.y = Math.sin(t * 0.5) * 0.7;
    arm.rotation.z = Math.sin(t * 0.37) * 0.15;
    tally.visible = (t % 1) < 0.6;
  };
}

function looks(group) {
  const texture = new THREE.TextureLoader().load('img/looks-grid.jpg');
  texture.colorSpace = THREE.SRGBColorSpace;
  const board = new THREE.Mesh(new THREE.PlaneGeometry(4.6, 4.6 * 540 / 1280), noLines(new THREE.MeshBasicMaterial({ map: texture, fog: false })));
  board.position.set(0, TOP + 1.6, 0);
  group.add(board);
  const frame = shape('cube', [4.85, 4.6 * 540 / 1280 + 0.25, 0.12], standard('#2e2b33'));
  frame.position.set(0, TOP + 1.6 - (4.6 * 540 / 1280 + 0.25) / 2, -0.08);
  group.add(frame);
  for (const side of [-1, 1]) {
    const leg = shape('cube', [0.12, 1.1, 0.12], standard('#2e2b33'));
    leg.position.set(side * 1.9, TOP, -0.1);
    group.add(leg);
  }
}

function out(group, stop) {
  const formats = ['MP4', 'ProRes', 'glTF', 'USDZ', 'STL', 'Blender'];
  const cards = formats.map((name, k) => {
    const card = label(name, { w: 1.05, h: 0.65, font: 64 });
    group.add(card);
    return { card, phase: (k / formats.length) * Math.PI * 2 };
  });
  const box = shape('cube', [1.1, 0.8, 1.1], standard('#c49a6c'));
  box.position.y = TOP;
  group.add(box);
  stop.update = (t) => {
    for (const { card, phase } of cards) {
      const a = phase + t * 0.45;
      card.position.set(Math.cos(a) * 1.75, TOP + 1.7 + Math.sin(a * 2 + t) * 0.25, Math.sin(a) * 1.3);
      card.rotation.y = Math.sin(a) * 0.35;
    }
  };
}

function yours(group, stop) {
  stop.models.push(
    { id: 'nature-tent-smallopen', at: [-0.6, TOP, -0.6], s: 1.4, ry: 0.4 },
    { id: 'nature-campfire-logs', at: [1.1, TOP, 0.8], s: 1.2 },
    { id: 'nature-log-stack', at: [1.6, TOP, -1.3], s: 0.9, ry: 1.2 },
  );
  const fire = new THREE.PointLight('#ff9a3c', 8, 8, 1.6);
  fire.position.set(1.1, TOP + 0.6, 0.8);
  group.add(fire);
  const flame = shape('cone', [0.4, 0.7, 0.4], glow('#ffb347', 2.5));
  flame.position.set(1.1, TOP + 0.12, 0.8);
  group.add(flame);
  stop.update = (t) => {
    const flicker = 0.75 + Math.sin(t * 13) * 0.12 + Math.sin(t * 7.3) * 0.1;
    fire.intensity = 8 * flicker;
    flame.scale.set(0.4, 0.7 * flicker, 0.4);
  };
}

function label(text, { w, h, font, round = false }) {
  const canvas = document.createElement('canvas');
  canvas.width = 512;
  canvas.height = Math.round(512 * h / w);
  const c = canvas.getContext('2d');
  c.fillStyle = '#f4efe6';
  c.strokeStyle = '#120f17';
  c.lineWidth = 14;
  const r = round ? canvas.height / 2.2 : 26;
  c.beginPath();
  c.roundRect(10, 10, canvas.width - 20, canvas.height - 20, r);
  c.fill();
  c.stroke();
  c.fillStyle = '#120f17';
  c.font = `700 ${font * 2}px Georgia, serif`;
  c.textAlign = 'center';
  c.textBaseline = 'middle';
  c.fillText(text, canvas.width / 2, canvas.height / 2 + 6);
  const texture = new THREE.CanvasTexture(canvas);
  texture.colorSpace = THREE.SRGBColorSpace;
  texture.anisotropy = 4;
  return new THREE.Mesh(new THREE.PlaneGeometry(w, h), noLines(new THREE.MeshBasicMaterial({ map: texture, transparent: true, fog: false })));
}

// ———————————————————————————————————————— the Kit models, and trees around the island

async function loadModels(scene, stops) {
  const loader = new GLTFLoader();
  const cache = new Map();
  const get = (id) => {
    if (!cache.has(id)) cache.set(id, loader.loadAsync(`models/${id}.glb`).then((gltf) => gltf.scene));
    return cache.get(id);
  };
  const place = async (parent, { id, at, s = 1, ry = 0 }) => {
    const model = (await get(id)).clone(true);
    model.traverse((o) => { if (o.isMesh) o.material = o.material.clone(); });
    if (id.includes('rock')) model.traverse((o) => { if (o.isMesh) o.material.color.set('#77737f'); });
    model.position.set(...at);
    model.scale.setScalar(s);
    model.rotation.y = ry;
    parent.add(shadows(model));
    return model;
  };
  const jobs = [];
  for (const stop of stops) {
    stop.loaded = {};
    for (const spec of stop.models) {
      jobs.push(place(stop.group, spec).then((model) => { if (spec.name) stop.loaded[spec.name] = model; }));
    }
  }
  // Trees and rocks between the stops and on the island's edge, the same every visit.
  const random = seeded(7);
  const trees = ['nature-tree-pinetalla', 'nature-tree-cone', 'nature-tree-default'];
  for (let k = 0; k < 11; k++) {
    const between = (Math.PI * 0.62 - ((k + 0.5) * Math.PI * 2) / 11);
    const r = RING + 4.5 + random() * 3;
    jobs.push(place(scene, { id: trees[k % 3], at: [Math.cos(between) * r, 0, Math.sin(between) * r], s: 0.9 + random() * 0.5, ry: random() * 6 }));
    const r2 = RING - 4.6 - random();
    jobs.push(place(scene, { id: k % 2 ? 'nature-plant-bush' : 'nature-rock-smalla', at: [Math.cos(between) * r2, 0, Math.sin(between) * r2], s: 0.9, ry: random() * 6 }));
  }
  for (let k = 0; k < 26; k++) {
    const a = random() * Math.PI * 2;
    const r = RING + 9 + random() * 16;
    jobs.push(place(scene, { id: trees[k % 3], at: [Math.cos(a) * r, 0, Math.sin(a) * r], s: 1 + random() * 0.8, ry: random() * 6 }));
  }
  for (let k = 0; k < 5; k++) {
    const a = random() * Math.PI * 2;
    jobs.push(place(scene, { id: 'nature-rock-largea', at: [Math.cos(a) * 7.5, 0, Math.sin(a) * 7.5], s: 0.8 + random() * 0.6, ry: random() * 6 }));
    jobs.push(place(scene, { id: 'nature-mushroom-red', at: [Math.cos(a + 0.4) * 9.5, 0, Math.sin(a + 0.4) * 9.5], s: 1.2, ry: random() * 6 }));
  }
  await Promise.all(jobs);
  return scene;
}

function seeded(seed) {
  let x = seed;
  return () => { x = (x * 16807) % 2147483647; return (x - 1) / 2147483646; };
}

// ———————————————————————————————————————— the camera's path: the opening, eleven stops, the road, the wall, the end

function keyframes(stops) {
  const keys = [{ pos: new THREE.Vector3(7, 33, 29), target: new THREE.Vector3(0, 1, 0) }];
  for (const stop of stops) {
    const out = stop.at.clone().normalize();
    const side = new THREE.Vector3(-out.z, 0, out.x);
    keys.push({
      pos: stop.at.clone().addScaledVector(out, 6.4).addScaledVector(side, 1.2).add(new THREE.Vector3(0, 2.9, 0)),
      target: stop.at.clone().add(new THREE.Vector3(0, 1.45, 0)),
    });
  }
  keys.push({ pos: new THREE.Vector3(-34, 26, -30), target: new THREE.Vector3(0, 4, 0) }); // the road
  keys.push({ pos: new THREE.Vector3(-8, 3, 12), target: new THREE.Vector3(0.6, 7.5, 0) }); // the wall: up at the lamp
  // The end: low between the first and last stops, looking up at the lamp, like the sample's own camera.
  const gap = Math.PI * 0.62 + Math.PI / 11;
  keys.push({ pos: new THREE.Vector3(Math.cos(gap) * 18, 2.2, Math.sin(gap) * 18), target: new THREE.Vector3(0.6, 5.2, 0) });
  keys.push({ pos: new THREE.Vector3(Math.cos(gap + 0.2) * 22, 4.5, Math.sin(gap + 0.2) * 22), target: new THREE.Vector3(0.6, 4.6, 0) });
  return keys;
}

// ———————————————————————————————————————— sky and stars

function sky(top, horizon) {
  const canvas = document.createElement('canvas');
  canvas.width = 2;
  canvas.height = 256;
  const c = canvas.getContext('2d');
  const gradient = c.createLinearGradient(0, 0, 0, 256);
  gradient.addColorStop(0, top);
  gradient.addColorStop(1, horizon);
  c.fillStyle = gradient;
  c.fillRect(0, 0, 2, 256);
  const texture = new THREE.CanvasTexture(canvas);
  texture.colorSpace = THREE.SRGBColorSpace;
  return texture;
}

function stars() {
  const random = seeded(3);
  const positions = [];
  for (let k = 0; k < 900; k++) {
    const a = random() * Math.PI * 2;
    const y = 0.12 + random() * 0.88;
    const r = Math.sqrt(1 - y * y);
    positions.push(Math.cos(a) * r * 160, y * 160, Math.sin(a) * r * 160);
  }
  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));
  const points = new THREE.Points(geometry, noLines(new THREE.PointsMaterial({ color: '#e8ecff', size: 1.4, sizeAttenuation: false, fog: false })));
  return points;
}

// ———————————————————————————————————————— the bar

function setUpTheBar() {
  const goal = document.querySelector('.goal');
  if (!goal) return;
  const raised = Number(goal.dataset.raised) || 0;
  const target = Number(goal.dataset.target) || 25000;
  goal.querySelector('.raised').textContent = `$${raised.toLocaleString('en-US')}`;
  const fill = goal.querySelector('.fill');
  const show = () => { fill.style.width = `${Math.min(100, (raised / target) * 100)}%`; };
  if (!('IntersectionObserver' in window)) return show();
  new IntersectionObserver((entries, observer) => {
    if (entries.some((e) => e.isIntersecting)) { show(); observer.disconnect(); }
  }).observe(goal);
}
