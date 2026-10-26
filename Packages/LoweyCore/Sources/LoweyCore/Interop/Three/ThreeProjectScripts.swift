import Foundation

/// The scripts a three.js folder carries (X1). They're the same in every export; what changes per scene is
/// `maquette/scene.js` (`ThreeProject.sceneInfo`). Plain ES modules against the vendored `three`, no build step.
enum ThreeProjectScripts {
    static let indexHTML = """
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>{{TITLE}}</title>
      <style>
        html, body { margin: 0; height: 100%; overflow: hidden; background: #000; }
        canvas { display: block; width: 100%; height: 100%; touch-action: none; }
      </style>
      <script type="importmap">
        { "imports": { "three": "./lib/three/three.module.js", "three/addons/": "./lib/three/addons/" } }
      </script>
    </head>
    <body>
      <script type="module" src="./main.js"></script>
    </body>
    </html>

    """

    /// The player: the scene, its camera cuts and its timeline on an `AnimationMixer`, the Look, and `window.maquette`
    /// for code (and agents) to drive. `?t=1.5` holds a moment, `?orbit` looks around freely, `?transparent` drops the sky.
    static let mainJS = """
    // Made with Maquette. Plays scene.glb with its cameras, its timeline and its Look. Serve this folder
    // (for example `npx serve .` or `python3 -m http.server`) and open index.html. AGENTS.md says what's inside.
    import * as THREE from 'three';
    import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
    import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
    import { withPointerTracks } from './maquette/pointer.js';
    import { applyLook } from './maquette/look.js';
    import { MAQUETTE } from './maquette/scene.js';

    const query = new URLSearchParams(location.search);
    const transparent = query.has('transparent');
    const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: transparent, preserveDrawingBuffer: query.has('t') });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.setSize(window.innerWidth, window.innerHeight);
    renderer.shadowMap.enabled = true;
    document.body.appendChild(renderer.domElement);

    const scene = new THREE.Scene();
    if (!transparent) scene.background = sky(MAQUETTE.sky);
    scene.add(new THREE.HemisphereLight(MAQUETTE.sky.top, MAQUETTE.sky.ground, MAQUETTE.sky.ambient));
    const sun = new THREE.DirectionalLight(MAQUETTE.sun.color, MAQUETTE.sun.intensity);
    sun.name = 'Maquette_sun';
    sun.position.set(...MAQUETTE.sun.direction.map((value) => -value * 30));
    sun.castShadow = MAQUETTE.sun.shadows;
    sun.shadow.mapSize.set(2048, 2048);
    scene.add(sun);
    if (MAQUETTE.ground.visible && !transparent) {
      const floor = new THREE.Mesh(new THREE.CircleGeometry(MAQUETTE.ground.radius, 96),
        new THREE.MeshStandardMaterial({ color: MAQUETTE.ground.color, roughness: 1 }));
      floor.name = 'Maquette_ground';
      floor.rotation.x = -Math.PI / 2;
      floor.receiveShadow = true;
      scene.add(floor);
    }

    const gltf = await new GLTFLoader().loadAsync('./scene.glb');
    gltf.scene.traverse((object) => { if (object.isMesh) { object.castShadow = true; object.receiveShadow = true; } });
    scene.add(gltf.scene);
    // The Look first: keyed material tracks bind to the materials it puts in place.
    const look = applyLook(renderer, scene, MAQUETTE.look);
    const clips = await withPointerTracks(gltf);
    const mixer = new THREE.AnimationMixer(gltf.scene);
    const actions = Object.fromEntries(clips.map((clip) => [clip.name, mixer.clipAction(clip)]));
    const main = actions[MAQUETTE.clip] ?? Object.values(actions)[0];
    main?.play();

    const cameras = Object.fromEntries(gltf.cameras.map((camera) => [camera.name, camera]));
    const free = new THREE.PerspectiveCamera(50, 1, 0.01, 1000);
    const centre = frame(free, gltf.scene);
    const controls = query.has('orbit') || gltf.cameras.length === 0 ? new OrbitControls(free, renderer.domElement) : null;
    controls?.target.copy(centre);

    function cameraAt(time) {
      if (controls) return free;
      let shot = MAQUETTE.activeCamera;
      for (const cut of MAQUETTE.cuts) if (cut.time <= time + 1e-9) shot = cut.camera;
      return cameras[shot] ?? gltf.cameras[0] ?? free;
    }

    function resize() {
      renderer.setSize(window.innerWidth, window.innerHeight);
      look.setSize(window.innerWidth, window.innerHeight);
    }
    window.addEventListener('resize', resize);

    let time = query.has('t') ? Number(query.get('t')) : 0;
    let playing = !query.has('t');
    let last = performance.now();
    function draw() {
      const now = performance.now();
      if (playing) time = MAQUETTE.duration > 0 ? (time + (now - last) / 1000) % MAQUETTE.duration : 0;
      last = now;
      mixer.setTime(time);
      const camera = cameraAt(time);
      camera.aspect = window.innerWidth / window.innerHeight;
      camera.updateProjectionMatrix();
      controls?.update();
      look.render(scene, camera);
    }
    renderer.setAnimationLoop(draw);

    // For code and agents: everything is named as in AGENTS.md.
    window.maquette = {
      scene, gltf, mixer, actions, clips, renderer,
      get time() { return time; },
      setTime(seconds) { time = seconds; playing = false; draw(); },
      play(name = MAQUETTE.clip) { mixer.stopAllAction(); actions[name]?.play(); playing = true; },
      pause() { playing = false; },
      object(name) { return scene.getObjectByName(name); },
      ready: true,
    };
    draw();
    document.dispatchEvent(new Event('maquette-ready'));

    function sky({ top, horizon }) {
      const canvas = document.createElement('canvas');
      canvas.width = 2; canvas.height = 256;
      const context = canvas.getContext('2d');
      const gradient = context.createLinearGradient(0, 0, 0, 256);
      gradient.addColorStop(0, '#' + new THREE.Color(top).getHexString());
      gradient.addColorStop(1, '#' + new THREE.Color(horizon).getHexString());
      context.fillStyle = gradient;
      context.fillRect(0, 0, 2, 256);
      const texture = new THREE.CanvasTexture(canvas);
      texture.colorSpace = THREE.SRGBColorSpace;
      return texture;
    }

    function frame(camera, object) {
      const box = new THREE.Box3().setFromObject(object);
      const size = box.getSize(new THREE.Vector3()).length() || 1;
      const centre = box.getCenter(new THREE.Vector3());
      camera.position.copy(centre).add(new THREE.Vector3(0.6, 0.45, 1).normalize().multiplyScalar(size * 1.1));
      camera.lookAt(centre);
      return centre;
    }

    """
}
