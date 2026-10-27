import Foundation

/// The scripts that take a running three.js page apart (X1 step 3): the page plays in the web sandbox on the piece's
/// clock, and these find its scene through the hook three.js itself calls for its devtools (every `Scene` and
/// `WebGLRenderer` announces itself to `__THREE_DEVTOOLS__`), write it with three.js's own `toJSON`, and sample how
/// everything moves into keys. Nothing in the page has to know about Maquette.
public enum ThreeRecorder {
    /// Added before the page's own code: remembers every scene, and which scene and camera each render draws.
    public static let hook = #"""
    (() => {
      if (window.__maquetteThree) return;
      const scenes = [], drawn = new Map();
      const hook = window.__THREE_DEVTOOLS__ || new EventTarget();
      const state = { scenes, drawn, onRender: null };
      hook.addEventListener('observe', (event) => {
        const found = event.detail;
        if (!found) return;
        if (found.isScene) { scenes.push(found); return; }
        if (typeof found.render !== 'function' || found.__maquette) return;
        const render = found.render;
        found.__maquette = true;
        found.render = function (scene, camera, ...rest) {
          if (scene && scene.isScene) {
            drawn.set(scene, camera);
            const swapped = state.onRender && state.onRender(scene, camera, this);
            if (swapped) camera = swapped;
          }
          return render.call(this, scene, camera, ...rest);
        };
      });
      window.__THREE_DEVTOOLS__ = hook;
      const size = (root) => { let count = 0; root.traverse(() => { count += 1; }); return count; };
      // The page's scene: the biggest one it draws (a post-processing quad is a mesh, not a scene), else the biggest made.
      state.pick = () => {
        const pool = drawn.size ? [...drawn.keys()] : scenes;
        let best = null;
        for (const scene of pool) if (!best || size(scene) > size(best)) best = scene;
        return best ? { scene: best, camera: drawn.get(best) || null } : null;
      };
      state.count = () => { const picked = state.pick(); return picked ? size(picked.scene) : 0; };
      // A child-index path from the scene: the same on every run of the same page (three's uuids come from the seeded
      // Math.random, but a path doesn't depend on it).
      state.path = (scene, object) => {
        const path = [];
        for (let node = object; node && node !== scene; node = node.parent) {
          if (!node.parent) return null;
          path.unshift(node.parent.children.indexOf(node));
        }
        return path;
      };
      state.at = (scene, path) => path.reduce((node, index) => node && node.children[index], scene);
      window.__maquetteThree = state;
    })();
    """#

    /// The body of an async function that records the page: steps to `from` seconds, writes the scene as it is then,
    /// samples `seconds` of motion `rate` times a second, and returns one JSON string (`ThreeRecording.read` takes it).
    public static func record(from: Double, seconds: Double, rate: Int) -> String {
        let rate = [1, 2, 3, 4, 5, 6, 10, 12, 15, 20, 30, 60].last { $0 <= max(rate, 1) } ?? 30
        let fromFrames = max(Int((from * 60).rounded()), 0)
        let samples = max(Int((seconds * Double(rate)).rounded()), 0)
        return "const fromFrames = \(fromFrames), samples = \(samples), rate = \(rate);\n" + recordBody
    }

    private static let recordBody = #"""
    const three = window.__maquetteThree;
    if (!three || !window.__hmm) return JSON.stringify({ error: 'noHook' });
    for (let left = fromFrames; left > 0; left -= 120) window.__hmm.step(Math.min(left, 120));
    const picked = three.pick();
    if (!picked) return JSON.stringify({ error: 'noScene' });
    const { scene } = picked;
    const camera = picked.camera && picked.camera.isCamera ? picked.camera : null;
    scene.updateMatrixWorld(true);
    if (camera) camera.updateMatrixWorld(true);
    const isShader = (m) => !!m && (m.isShaderMaterial === true || m.isRawShaderMaterial === true);
    const shaded = (o) => Array.isArray(o.material) ? o.material.some(isShader) : isShader(o.material);
    const notes = [];

    // Surfaces drawn by their own shader can't become ours: they stay playing as a web piece (a stand-in each).
    const standIns = [], hidden = new Set();
    scene.traverse((o) => {
      if (!o.isMesh || !shaded(o) || !o.geometry) return;
      o.geometry.computeBoundingBox();
      const box = o.geometry.boundingBox;
      if (!box || box.isEmpty()) return;
      const center = [0, 1, 2].map((i) => (box.min.getComponent(i) + box.max.getComponent(i)) / 2);
      const size = [0, 1, 2].map((i) => box.max.getComponent(i) - box.min.getComponent(i));
      standIns.push({ uuid: o.uuid, name: o.name || 'Shader', path: three.path(scene, o), center, size });
      hidden.add(o.uuid);
    });

    let json;
    try { json = scene.toJSON(); } catch (error) { return JSON.stringify({ error: 'toJSON', message: String(error) }); }
    // The stand-ins' meshes become plain groups (their children and their place kept), so nothing tries to read the shader.
    const swap = (node) => {
      if (hidden.has(node.uuid)) {
        for (const key of ['geometry', 'material', 'castShadow', 'receiveShadow']) delete node[key];
        node.type = 'Group';
      }
      (node.children || []).forEach(swap);
    };
    swap(json.object);
    // The camera it draws with, when it isn't in the scene (the usual way): added at the top, where it stands.
    let inScene = false;
    if (camera) scene.traverse((o) => { if (o === camera) inScene = true; });
    if (camera && !inScene) {
      const own = camera.toJSON().object;
      own.matrix = camera.matrixWorld.toArray();
      own.name = own.name || 'Camera';
      delete own.children;
      json.object.children = (json.object.children || []).concat([own]);
    }

    // Everything that can move, sampled.
    const watched = [];
    const watch = (o) => { if (!hidden.has(o.uuid)) watched.push(o); };
    scene.traverse(watch);
    if (camera && !inScene) watched.push(camera);
    const reads = (o) => {
      const list = [
        ['position', 'vector', () => o.position.toArray()],
        ['quaternion', 'quaternion', () => o.quaternion.toArray()],
        ['scale', 'vector', () => o.scale.toArray()],
        ['visible', 'bool', () => [o.visible ? 1 : 0]],
      ];
      if (o === camera && !inScene) {
        list[0][2] = () => o.getWorldPosition(o.position.clone()).toArray();
        list[1][2] = () => o.getWorldQuaternion(o.quaternion.clone()).toArray();
        list[2][2] = () => o.getWorldScale(o.scale.clone()).toArray();
      }
      const m = Array.isArray(o.material) ? o.material[0] : o.material;
      if (o.isMesh && m && !isShader(m)) {
        if (m.color) list.push(['material.color', 'color', () => m.color.toArray()]);
        if (m.emissive) list.push(['material.emissive', 'color', () => m.emissive.toArray()]);
        if (typeof m.emissiveIntensity === 'number') list.push(['material.emissiveIntensity', 'number', () => [m.emissiveIntensity]]);
        list.push(['material.opacity', 'number', () => [m.transparent ? m.opacity : 1]]);
        if (typeof m.roughness === 'number') list.push(['material.roughness', 'number', () => [m.roughness]]);
        if (typeof m.metalness === 'number') list.push(['material.metalness', 'number', () => [m.metalness]]);
      }
      if (o.isLight) {
        list.push(['color', 'color', () => o.color.toArray()], ['intensity', 'number', () => [o.intensity]]);
        if (o.isSpotLight) list.push(['angle', 'number', () => [o.angle]]);
      }
      if (o.isPerspectiveCamera) list.push(['fov', 'number', () => [o.fov]]);
      if (o.isMesh && o.morphTargetInfluences && o.morphTargetInfluences.length) {
        notes.push('morph');
      }
      return list;
    };
    const channels = [];
    for (const o of watched) for (const [property, type, read] of reads(o)) channels.push({ o, property, type, read, values: [] });
    const instanced = watched.filter((o) => o.isInstancedMesh);
    const firstInstances = instanced.map((o) => Array.from(o.instanceMatrix.array));
    const times = [];
    for (let i = 0; i <= samples; i++) {
      if (i > 0) window.__hmm.step(60 / rate);
      scene.updateMatrixWorld(true);
      if (camera) camera.updateMatrixWorld(true);
      times.push(i / rate);
      for (const channel of channels) {
        const value = channel.read();
        const previous = channel.values[channel.values.length - 1];
        // q and −q are the same turn: keep each key on the side of the last, so the keys don't spin the long way.
        if (channel.type === 'quaternion' && previous && value.reduce((s, v, k) => s + v * previous[k], 0) < 0) {
          for (let k = 0; k < 4; k++) value[k] = -value[k];
        }
        channel.values.push(value);
      }
    }
    if (instanced.some((o, n) => Array.from(o.instanceMatrix.array).some((v, k) => Math.abs(v - firstInstances[n][k]) > 1e-5))) {
      notes.push('instances');
    }

    // Only what moved, with only the keys a straight line between its neighbours doesn't already give.
    const tolerance = (type) => (type === 'color' ? 1 / 512 : 1e-4);
    const close = (a, b, eps) => a.every((v, k) => Math.abs(v - b[k]) <= eps);
    const lerp = (a, b, t) => a.map((v, k) => v + (b[k] - v) * t);
    const tracks = [];
    for (const channel of channels) {
      const { values, type } = channel;
      const eps = tolerance(type);
      if (values.every((v) => close(v, values[0], eps))) continue;
      const kept = [0];
      if (type === 'bool') {
        for (let i = 1; i < values.length; i++) if (values[i][0] !== values[i - 1][0]) kept.push(i);
      } else {
        let anchor = 0;
        for (let i = 2; i < values.length; i++) {
          let straight = true;
          for (let j = anchor + 1; j < i && straight; j++) {
            const t = (times[j] - times[anchor]) / (times[i] - times[anchor]);
            straight = close(lerp(values[anchor], values[i], t), values[j], eps);
          }
          if (!straight) { kept.push(i - 1); anchor = i - 1; }
        }
        if (kept[kept.length - 1] !== values.length - 1) kept.push(values.length - 1);
      }
      const track = {
        name: `${channel.o.uuid}.${channel.property}`,
        type: type === 'bool' ? 'bool' : type,
        times: kept.map((i) => times[i]),
        values: kept.flatMap((i) => values[i]),
      };
      if (type === 'bool') track.interpolation = 2300;
      tracks.push(track);
    }
    json.animations = tracks.length ? [{ name: 'Recorded', uuid: 'maquette-recorded', duration: samples / rate, blendMode: 2500, tracks }] : [];
    json.object.animations = tracks.length ? ['maquette-recorded'] : [];
    return JSON.stringify({
      scene: json,
      recording: {
        from: fromFrames / 60, seconds: samples / rate, rate, camera: camera ? camera.uuid : null,
        standIns, notes: [...new Set(notes)],
        width: window.innerWidth, height: window.innerHeight,
      },
    });
    """#

    /// Added (after `hook`) to a copy of the page that plays one stand-in: everything else is hidden, and it is drawn
    /// straight on, flat (an orthographic view the size of its box), so the card that stands for it shows it as it was.
    public static func solo(_ standIn: ThreeRecording.StandIn) -> String {
        let path = standIn.path.map(String.init).joined(separator: ",")
        let frame = ThreeRecording.cardFrame(size: standIn.size)
        return """
        (() => {
          const path = [\(path)], center = [\(standIn.center.x), \(standIn.center.y), \(standIn.center.z)];
          const axis = '\(frame.axis)', width = \(frame.width), height = \(frame.height), depth = \(frame.depth);
        """ + soloBody
    }

    private static let soloBody = #"""
      const three = window.__maquetteThree;
      let stand = null;
      three.onRender = (scene, camera, renderer) => {
        const target = three.at(scene, path);
        if (!target || !target.isMesh) return null;
        const keep = new Set();
        for (let node = target; node; node = node.parent) keep.add(node);
        target.traverse((o) => keep.add(o));
        scene.traverse((o) => { if (!keep.has(o) && (o.isMesh || o.isPoints || o.isLine || o.isSprite)) o.visible = false; });
        scene.background = null;
        scene.fog = null;
        renderer.setClearAlpha && renderer.setClearAlpha(0);
        if (!stand) {
          stand = camera.clone();
          stand.matrixAutoUpdate = false;
          stand.matrixWorldAutoUpdate = false;
        }
        const Matrix4 = target.matrixWorld.constructor;
        const turn = new Matrix4();
        if (axis === 'x') turn.makeRotationY(Math.PI / 2);
        else if (axis === 'y') turn.makeRotationX(-Math.PI / 2);
        const away = Math.max(width, height, depth) + depth;
        const n = axis === 'x' ? [1, 0, 0] : axis === 'y' ? [0, 1, 0] : [0, 0, 1];
        turn.setPosition(center[0] + n[0] * away, center[1] + n[1] * away, center[2] + n[2] * away);
        target.updateWorldMatrix(true, false);
        stand.matrixWorld.multiplyMatrices(target.matrixWorld, turn);
        stand.matrixWorldInverse.copy(stand.matrixWorld).invert();
        stand.projectionMatrix.makeOrthographic(-width / 2, width / 2, height / 2, -height / 2, 0.001, away * 2);
        stand.projectionMatrixInverse.copy(stand.projectionMatrix).invert();
        return stand;
      };
    })();
    """#
}
