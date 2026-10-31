// The 3D view of a technique in the gallery (tools/gallery.py inlines this file).
//
// The figures are glTF models at rest (tools/export_viewer.gd, tools/slim_glb.py) and the motion
// is every frame the film shows, read after Kamae's solve: per figure its skeleton's transform and
// every bone's rotation in its parent. Nothing is solved here; between two frames the bones are
// slerped, so a technique can be played as slowly as anyone likes and still move smoothly.
import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';

const SPEEDS = [1, 0.5, 0.25, 0.1];
const loader = new GLTFLoader();
const figureCache = new Map();   // file -> Promise<{scene, bones: Map}>
let ui = null;                   // the one stage and control bar, moved into whichever technique is open
let current = null;              // {media, slug, meta, data, figures: [{root, bones, stride offset}]}
let state = { t: 0, playing: false, speed: 1, follow: true };
let last = performance.now();
let running = false;

function el(tag, attrs = {}, children = []) {
  const n = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === 'text') n.textContent = v;
    else if (k.startsWith('on')) n.addEventListener(k.slice(2), v);
    else n.setAttribute(k, v);
  }
  for (const c of children) n.append(c);
  return n;
}

function buildUI() {
  const canvas = el('canvas', { tabindex: '0', 'aria-label': '3D view of the technique: drag to turn, scroll to zoom, right-drag to move' });
  const loading = el('div', { class: 'loading', text: 'Loading the figures…' });
  const note = el('div', { class: 'note', text: 'drag: turn · scroll: zoom · right-drag: move' });
  const label = el('div', { class: 'phase-label', 'aria-live': 'polite' });
  const stage = el('div', { class: 'stage' }, [canvas, loading, note, label]);
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  const scene = new THREE.Scene();
  scene.background = new THREE.Color(0xdcdcd8);
  const hemi = new THREE.HemisphereLight(0xffffff, 0x8b947f, 1.6);
  scene.add(hemi);
  const sun = new THREE.DirectionalLight(0xffffff, 2.2);
  sun.position.set(3, 6, 4);
  sun.castShadow = true;
  sun.shadow.mapSize.set(2048, 2048);
  Object.assign(sun.shadow.camera, { left: -4, right: 4, top: 4, bottom: -4, near: 0.5, far: 20 });
  sun.shadow.bias = -0.0005;
  scene.add(sun, sun.target);
  const floor = new THREE.Mesh(new THREE.PlaneGeometry(16, 16),
    new THREE.MeshStandardMaterial({ color: 0xd7eac4, roughness: 0.95 }));
  floor.rotation.x = -Math.PI / 2;
  floor.receiveShadow = true;
  scene.add(floor);
  const grid = new THREE.GridHelper(16, 16, 0x9db497, 0xa9bfa3);
  grid.position.y = 0.002;
  scene.add(grid);
  const camera = new THREE.PerspectiveCamera(35, 16 / 9, 0.05, 100);
  const controls = new OrbitControls(camera, canvas);
  controls.enableDamping = true;
  controls.minDistance = 0.4;
  controls.maxDistance = 14;
  controls.maxPolarAngle = Math.PI * 0.495;

  const btn = (label, title, fn) => el('button', { type: 'button', title, 'aria-label': title, text: label, onclick: fn });
  const play = btn('▶', 'Play / pause (space)', () => togglePlay());
  const back = btn('◀︎|', 'One frame back (←)', () => step(-1));
  const fwd = btn('|▶︎', 'One frame on (→)', () => step(1));
  const prevPhase = btn('⏮', 'Previous phase (shift ←)', () => jumpPhase(-1));
  const nextPhase = btn('⏭', 'Next phase (shift →)', () => jumpPhase(1));
  const speed = el('select', { 'aria-label': 'Speed', title: 'Speed (− / +)', onchange: e => { state.speed = parseFloat(e.target.value); } },
    SPEEDS.map(s => el('option', { value: String(s), text: s === 1 ? '1×' : (s === 0.5 ? '½×' : (s === 0.25 ? '¼×' : '⅒×')) })));
  const scrub = el('input', { type: 'range', min: '0', max: '1', step: 'any', value: '0', 'aria-label': 'Time',
    oninput: e => { state.playing = false; setTime(parseFloat(e.target.value)); } });
  const time = el('span', { class: 'time', text: '0.00 s' });
  const views = el('span', { class: 'group' }, [
    btn('Side', 'Side view', () => frameView('side')),
    btn('Other side', 'Side view from the other side', () => frameView('other')),
    btn('End-on', 'Along the line between them', () => frameView('end')),
    btn('Above', 'From above', () => frameView('top')),
  ]);
  const follow = btn('Follow', 'Keep the figures in the middle as they move (F)', () => { state.follow = !state.follow; follow.classList.toggle('on', state.follow); });
  follow.classList.add('on');
  const full = btn('⤢', 'Full screen', () => { (stage.requestFullscreen || stage.webkitRequestFullscreen || (() => {})).call(stage); });
  const bar = el('div', { class: 'vbar' }, [prevPhase, back, play, fwd, nextPhase, speed, scrub, time, views, follow, full]);

  canvas.addEventListener('keydown', e => {
    if (e.key === ' ') { togglePlay(); e.preventDefault(); }
    else if (e.key === 'ArrowLeft') { e.shiftKey ? jumpPhase(-1) : step(-1); e.preventDefault(); }
    else if (e.key === 'ArrowRight') { e.shiftKey ? jumpPhase(1) : step(1); e.preventDefault(); }
    else if (e.key === '-' || e.key === '+' || e.key === '=') {
      const i = SPEEDS.indexOf(state.speed) + (e.key === '-' ? 1 : -1);
      state.speed = SPEEDS[Math.max(0, Math.min(SPEEDS.length - 1, i))];
      speed.value = String(state.speed);
    } else if (e.key === 'f' || e.key === 'F') follow.click();
  });
  new ResizeObserver(() => {
    const w = stage.clientWidth, h = stage.clientHeight;
    if (w && h) { renderer.setSize(w, h, false); camera.aspect = w / h; camera.updateProjectionMatrix(); }
  }).observe(stage);
  return { stage, bar, canvas, renderer, scene, camera, controls, play, scrub, time, loading, speed, label };
}

function loadFigure(file) {
  if (!figureCache.has(file)) {
    figureCache.set(file, loader.loadAsync('media/' + file).then(gltf => {
      const bones = new Map();
      gltf.scene.traverse(o => {
        if (o.isBone) bones.set(o.name, o);
        if (o.isMesh) {
          o.castShadow = true;
          o.receiveShadow = true;
          o.frustumCulled = false;
          const mats = Array.isArray(o.material) ? o.material : [o.material];
          for (const m of mats) m.side = THREE.DoubleSide;
        }
      });
      gltf.scene.matrixAutoUpdate = true;
      return { scene: gltf.scene, bones };
    }));
  }
  return figureCache.get(file);
}

async function open(media) {
  if (!ui) ui = buildUI();
  if (current && current.media !== media) close();
  const slug = media.dataset.slug;
  const video = media.querySelector('video');
  video.pause();
  video.style.display = 'none';
  media.dataset.mode = '3d';
  media.querySelectorAll('.mode').forEach(b => b.classList.toggle('on', b.dataset.mode === '3d'));
  media.insertBefore(ui.stage, media.querySelector('.modes'));
  media.append(ui.bar);
  ui.loading.style.display = '';
  for (const child of [...ui.scene.children]) if (child.userData.figure) ui.scene.remove(child);
  const figuresByChar = JSON.parse(media.dataset.figures);
  const [meta, buf] = await Promise.all([
    fetch(`media/${slug}.motion.json`).then(r => r.json()),
    fetch(`media/${slug}.motion.bin`).then(r => r.arrayBuffer()),
  ]);
  const data = new Float32Array(buf);
  const nb = meta.bones.length, nm = meta.moving.length;
  const perChar = 7 + 4 * nb + 3 * nm;
  const figures = [];
  for (let c = 0; c < meta.characters.length; c++) {
    const fig = await loadFigure(figuresByChar[meta.characters[c]]);
    fig.scene.userData.figure = true;
    ui.scene.add(fig.scene);
    figures.push({ ...fig, offset: c * perChar,
      boneObjs: meta.bones.map(n => fig.bones.get(n) || null),
      movingObjs: meta.moving.map(n => fig.bones.get(n) || null) });
  }
  current = { media, slug, meta, data, figures, stride: perChar * meta.characters.length, nb, nm,
    phases: meta.phases.map(p => p.t) };
  ui.loading.style.display = 'none';
  ui.scrub.max = String(meta.duration);
  state.t = 0; state.playing = false;
  setTime(0);
  frameView('side');
  ui.canvas.focus({ preventScroll: true });
  if (!running) { running = true; last = performance.now(); requestAnimationFrame(loop); }
}

function close() {
  if (!current) return;
  const media = current.media;
  media.dataset.mode = 'film';
  media.querySelector('video').style.display = '';
  media.querySelectorAll('.mode').forEach(b => b.classList.toggle('on', b.dataset.mode === 'film'));
  ui.stage.remove();
  ui.bar.remove();
  current = null;
  running = false;
  state.playing = false;
}

const qa = new THREE.Quaternion(), qb = new THREE.Quaternion();
const va = new THREE.Vector3(), vb = new THREE.Vector3();

// Puts every figure where the film has it at time t, slerping between the two frames around it.
function setTime(t) {
  if (!current) return;
  const { meta, data, stride, nb, nm } = current;
  state.t = Math.max(0, Math.min(meta.duration, t));
  const f = Math.min(state.t * meta.fps, meta.frames - 1);
  const i0 = Math.floor(f), i1 = Math.min(i0 + 1, meta.frames - 1), w = f - i0;
  const base0 = 4 + i0 * stride, base1 = 4 + i1 * stride;
  for (const fig of current.figures) {
    const o0 = base0 + fig.offset, o1 = base1 + fig.offset;
    va.set(data[o0], data[o0 + 1], data[o0 + 2]);
    vb.set(data[o1], data[o1 + 1], data[o1 + 2]);
    fig.scene.position.lerpVectors(va, vb, w);
    qa.fromArray(data, o0 + 3); qb.fromArray(data, o1 + 3);
    fig.scene.quaternion.slerpQuaternions(qa, qb, w);
    for (let b = 0; b < nb; b++) {
      const bone = fig.boneObjs[b];
      if (!bone) continue;
      qa.fromArray(data, o0 + 7 + 4 * b);
      qb.fromArray(data, o1 + 7 + 4 * b);
      bone.quaternion.slerpQuaternions(qa, qb, w);
    }
    for (let m = 0; m < nm; m++) {
      const bone = fig.movingObjs[m];
      if (!bone) continue;
      const k0 = o0 + 7 + 4 * nb + 3 * m, k1 = o1 + 7 + 4 * nb + 3 * m;
      bone.position.set(data[k0] + (data[k1] - data[k0]) * w, data[k0 + 1] + (data[k1 + 1] - data[k0 + 1]) * w,
        data[k0 + 2] + (data[k1 + 2] - data[k0 + 2]) * w);
    }
  }
  ui.scrub.value = String(state.t);
  ui.time.textContent = state.t.toFixed(2) + ' s';
  const chips = [...current.media.closest('.tech').querySelectorAll('.phase')];
  let on = 0;
  chips.forEach((b, k) => { if (state.t + 0.02 >= parseFloat(b.dataset.t)) on = k; });
  chips.forEach((b, k) => b.classList.toggle('on', k === on));
  const name = chips[on]?.querySelector('.pname')?.textContent || '';
  if (ui.label.textContent !== name) ui.label.textContent = name;
}

function centroid(out) {
  out.set(0, 0, 0);
  if (!current) return out;
  for (const fig of current.figures) out.add(fig.scene.position);
  out.multiplyScalar(1 / current.figures.length);
  out.y = 0.9;
  return out;
}

// The camera for a named view, framing where the figures go over the whole technique.
function frameView(kind) {
  if (!current) return;
  const { meta, data, stride } = current;
  const pts = [];
  for (let f = 0; f < meta.frames; f += 3)
    for (const fig of current.figures) {
      const o = 4 + f * stride + fig.offset;
      pts.push(new THREE.Vector3(data[o], 0, data[o + 2]));
    }
  const box = new THREE.Box3().setFromPoints(pts);
  const mid = box.getCenter(new THREE.Vector3());
  mid.y = 0.9;
  const radius = Math.max(1.2, box.getSize(new THREE.Vector3()).length() / 2 + 1.0);
  let along;
  const o = 4;
  if (current.figures.length > 1) {
    const a = current.figures[0].offset + o, b = current.figures[1].offset + o;
    along = new THREE.Vector3(data[b] - data[a], 0, data[b + 2] - data[a + 2]);
  } else {
    const q = new THREE.Quaternion().fromArray(data, current.figures[0].offset + o + 3);
    along = new THREE.Vector3(0, 0, 1).applyQuaternion(q).setY(0);
  }
  if (along.lengthSq() < 1e-6) along.set(0, 0, 1);
  along.normalize();
  const side = new THREE.Vector3(along.z, 0, -along.x);
  const dist = radius / Math.tan(THREE.MathUtils.degToRad(ui.camera.fov / 2)) * 0.85;
  let dir;
  if (kind === 'side') dir = side.clone();
  else if (kind === 'other') dir = side.clone().negate();
  else if (kind === 'end') dir = along.clone().negate();
  else dir = side.clone().multiplyScalar(0.05);
  const height = kind === 'top' ? dist * 0.95 : 0.55;
  ui.controls.target.copy(mid);
  ui.camera.position.copy(mid).addScaledVector(dir.normalize(), kind === 'top' ? dist * 0.25 : dist).add(new THREE.Vector3(0, height, 0));
  ui.controls.update();
  followFrom.copy(centroid(new THREE.Vector3()));
}

const followFrom = new THREE.Vector3();
const here = new THREE.Vector3();

function togglePlay() {
  if (!current) return;
  if (!state.playing && state.t >= current.meta.duration - 1e-3) setTime(0);
  state.playing = !state.playing;
}

function step(n) {
  if (!current) return;
  state.playing = false;
  const fps = current.meta.fps;
  setTime((Math.round(state.t * fps) + n) / fps);
}

function jumpPhase(dir) {
  if (!current) return;
  state.playing = false;
  const ts = current.phases;
  let t = dir > 0 ? ts.find(x => x > state.t + 1e-3) : [...ts].reverse().find(x => x < state.t - 1e-3);
  if (t === undefined) t = dir > 0 ? current.meta.duration : 0;
  setTime(t);
}

function loop(now) {
  if (!running) return;
  const dt = Math.min(0.1, (now - last) / 1000);
  last = now;
  if (current && state.playing) {
    setTime(state.t + dt * state.speed);
    if (state.t >= current.meta.duration) state.playing = false;
  }
  if (current && state.follow) {
    centroid(here);
    const d = here.clone().sub(followFrom);
    ui.controls.target.add(d);
    ui.camera.position.add(d);
    followFrom.copy(here);
  }
  if (ui) {
    ui.play.textContent = state.playing ? '❚❚' : '▶';
    ui.controls.update();
    ui.renderer.render(ui.scene, ui.camera);
  }
  requestAnimationFrame(loop);
}

window.kamaeViewer = { open, close, seek: t => { state.playing = false; setTime(t); } };

for (const media of document.querySelectorAll('.media[data-figures]')) {
  for (const b of media.querySelectorAll('.mode')) {
    b.addEventListener('click', () => {
      if (b.dataset.mode === '3d') open(media).catch(err => {
        console.error(err);
        if (ui) ui.loading.textContent = 'The 3D view could not be loaded.';
      });
      else if (current && current.media === media) close();
    });
  }
}
