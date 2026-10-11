// Two small three.js scenes, rendered at low resolution and ordered-dithered
// to the brand palette: the studio monitor in the hero and the "c," mark in
// the footer. Both lean toward the pointer on a spring and pause off screen.

import * as THREE from "three";
import { RoundedBoxGeometry } from "three/addons/geometries/RoundedBoxGeometry.js";

const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;

/* dictation state comes from main.js */

let listening = false;
addEventListener("listen:state", (event) => { listening = event.detail === "listening"; });

/* pointer, normalised to the viewport */

const pointer = new THREE.Vector2();
addEventListener("pointermove", (event) => {
  pointer.set((event.clientX / innerWidth) * 2 - 1, (event.clientY / innerHeight) * 2 - 1);
});

/* dither pass: luminance against an 8x8 Bayer matrix, two inks */

const ditherMaterial = () => new THREE.ShaderMaterial({
  transparent: true,
  uniforms: {
    tScene: { value: null },
    gain: { value: 1.0 },
    ink: { value: new THREE.Color(0xedf1e8).convertLinearToSRGB() },
    lime: { value: new THREE.Color(0xd5f66b).convertLinearToSRGB() },
  },
  vertexShader: /* glsl */ `
    varying vec2 vUv;
    void main() { vUv = uv; gl_Position = vec4(position.xy, 0.0, 1.0); }
  `,
  fragmentShader: /* glsl */ `
    uniform sampler2D tScene;
    uniform float gain;
    uniform vec3 ink;
    uniform vec3 lime;
    varying vec2 vUv;

    float bayer2(vec2 a) { a = floor(a); return fract(a.x / 2.0 + a.y * a.y * 0.75); }
    float bayer4(vec2 a) { return bayer2(0.5 * a) * 0.25 + bayer2(a); }
    float bayer8(vec2 a) { return bayer4(0.5 * a) * 0.25 + bayer2(a); }

    void main() {
      vec4 src = texture2D(tScene, vUv);
      float lum = dot(src.rgb, vec3(0.299, 0.587, 0.114));
      float on = step(bayer8(gl_FragCoord.xy) + 0.004, pow(lum, 0.7) * gain * src.a);
      // lime surfaces keep a strong green-over-blue ratio at every light level
      float limeish = step(0.32, (src.g - src.b) / max(src.g, 0.001));
      gl_FragColor = vec4(mix(ink, lime, limeish) * on, on);
    }
  `,
});

function createDitheredView(canvas, { pixel, build, gain = 1, fov = 28, distance = 6 }) {
  let renderer;
  try {
    renderer = new THREE.WebGLRenderer({ canvas, alpha: true, antialias: false, premultipliedAlpha: true });
  } catch {
    canvas.hidden = true;
    return null;
  }
  renderer.setPixelRatio(1);
  renderer.setClearColor(0x000000, 0);

  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(fov, 1, 0.1, 50);
  camera.position.set(0, 0, distance);

  const target = new THREE.WebGLRenderTarget(1, 1, { type: THREE.HalfFloatType });
  const post = new THREE.Mesh(new THREE.PlaneGeometry(2, 2), ditherMaterial());
  post.material.uniforms.tScene.value = target.texture;
  post.material.uniforms.gain.value = gain;
  const postScene = new THREE.Scene();
  postScene.add(post);
  const postCamera = new THREE.OrthographicCamera();

  const update = build(scene, camera);

  function resize() {
    const w = Math.max(1, Math.round(canvas.clientWidth / pixel));
    const h = Math.max(1, Math.round(canvas.clientHeight / pixel));
    renderer.setSize(w, h, false);
    target.setSize(w, h);
    camera.aspect = w / h;
    camera.updateProjectionMatrix();
  }
  new ResizeObserver(resize).observe(canvas);
  resize();

  let visible = false;
  new IntersectionObserver(([entry]) => { visible = entry.isIntersecting; }).observe(canvas);

  return {
    frame(time, dt) {
      if (!visible) return;
      update(time, dt);
      renderer.setRenderTarget(target);
      renderer.render(scene, camera);
      renderer.setRenderTarget(null);
      renderer.render(postScene, postCamera);
    },
  };
}

/* a damped spring per axis; decorative, so it can overshoot a little */

function spring(stiffness = 60, damping = 9) {
  const s = { value: 0, velocity: 0, target: 0 };
  s.step = (dt) => {
    const force = (s.target - s.value) * stiffness - s.velocity * damping;
    s.velocity += force * dt;
    s.value += s.velocity * dt;
    return s.value;
  };
  return s;
}

function addStudioLights(scene) {
  scene.add(new THREE.AmbientLight(0xffffff, 0.06));
  const key = new THREE.DirectionalLight(0xffffff, 1.3);
  key.position.set(-3, 4, 5);
  scene.add(key);
  const rim = new THREE.DirectionalLight(0xffffff, 0.9);
  rim.position.set(4, 1, -3);
  scene.add(rim);
}

/* hero: a near-field studio monitor; the woofer pumps while you talk */

function buildSpeaker(scene, camera) {
  addStudioLights(scene);
  const fill = new THREE.DirectionalLight(0xffffff, 0.9);
  fill.position.set(1, 0, 6);
  scene.add(fill);
  camera.position.set(0, 0, 5.2);

  const rig = new THREE.Group();
  scene.add(rig);

  const cabinetMat = new THREE.MeshStandardMaterial({ color: 0x4a4e48, roughness: 0.5 });
  const coneMat = new THREE.MeshStandardMaterial({ color: 0xd5f66b, emissive: 0x1c2408, roughness: 0.75, side: THREE.DoubleSide });
  const trimMat = new THREE.MeshStandardMaterial({ color: 0x9a9d96, roughness: 0.4, metalness: 0.3 });

  const cabinet = new THREE.Mesh(new RoundedBoxGeometry(1.5, 2.2, 1.5, 4, 0.12), cabinetMat);
  rig.add(cabinet);

  const front = 0.76;

  // woofer: surround, cone, dust cap
  const woofer = new THREE.Group();
  // drivers sit proud of the baffle so the cones read at this size
  woofer.position.set(0, -0.32, front + 0.2);
  rig.add(woofer);
  const surround = new THREE.Mesh(new THREE.TorusGeometry(0.56, 0.06, 12, 48), trimMat);
  woofer.add(surround);
  const basket = new THREE.Mesh(new THREE.CylinderGeometry(0.62, 0.62, 0.2, 48, 1, true), trimMat);
  basket.rotation.x = Math.PI / 2;
  basket.position.z = -0.1;
  woofer.add(basket);
  const coneProfile = [
    new THREE.Vector2(0.14, -0.2),
    new THREE.Vector2(0.3, -0.12),
    new THREE.Vector2(0.52, 0.0),
  ];
  const cone = new THREE.Mesh(new THREE.LatheGeometry(coneProfile, 48), coneMat);
  cone.rotation.x = Math.PI / 2;
  woofer.add(cone);
  const cap = new THREE.Mesh(new THREE.SphereGeometry(0.16, 24, 12, 0, Math.PI * 2, 0, Math.PI / 2), coneMat);
  cap.rotation.x = Math.PI / 2;
  cap.position.z = -0.2;
  cap.scale.y = 0.6;
  woofer.add(cap);

  // tweeter
  const tweeter = new THREE.Group();
  tweeter.position.set(0, 0.62, front + 0.02);
  rig.add(tweeter);
  tweeter.add(new THREE.Mesh(new THREE.TorusGeometry(0.2, 0.04, 10, 36), trimMat));
  const dome = new THREE.Mesh(new THREE.SphereGeometry(0.13, 20, 10, 0, Math.PI * 2, 0, Math.PI / 2), coneMat);
  dome.rotation.x = Math.PI / 2;
  dome.scale.y = 0.55;
  tweeter.add(dome);

  // bass port
  const port = new THREE.Mesh(new THREE.TorusGeometry(0.07, 0.025, 8, 24), trimMat);
  port.position.set(0.48, -0.92, front);
  rig.add(port);

  const yaw = spring();
  const pitch = spring();
  let energy = 0;

  return (time, dt) => {
    energy += ((listening ? 1 : 0) - energy) * Math.min(1, dt * 5);
    const idle = reduceMotion ? 0 : Math.sin(time * 0.6) * 0.06;
    yaw.target = -0.32 + pointer.x * 0.3 + idle;
    pitch.target = 0.08 + pointer.y * 0.16;
    rig.rotation.y = reduceMotion ? yaw.target : yaw.step(dt);
    rig.rotation.x = reduceMotion ? pitch.target : pitch.step(dt);

    // excursion: a syllable-ish wobble, only while listening
    const beat = Math.sin(time * 19) * 0.5 + Math.sin(time * 7.3) * 0.5;
    const push = reduceMotion ? 0 : energy * beat * 0.07;
    cone.position.z = push;
    cap.position.z = -0.2 + push;
    dome.scale.y = 0.55 + (reduceMotion ? 0 : energy * Math.sin(time * 31) * 0.08);
  };
}

/* footer: the "c," mark, extruded */

function cShape() {
  // proportions traced from assets/AppIcon.png: round bowl, narrow counter,
  // horizontal terminals just above and below the centre line
  const cutY = 0.2;
  const outer = { rx: 0.98, ry: 1 };
  const inner = { rx: 0.4, ry: 0.53 };
  const a = Math.asin(cutY / outer.ry);
  const b = Math.asin(cutY / inner.ry);
  const shape = new THREE.Shape();
  shape.absellipse(0, 0, outer.rx, outer.ry, a, Math.PI * 2 - a, false);
  shape.lineTo(inner.rx * Math.cos(b), -cutY);
  shape.absellipse(0, 0, inner.rx, inner.ry, Math.PI * 2 - b, b, true);
  shape.closePath();
  return shape;
}

function commaShape() {
  const shape = new THREE.Shape();
  shape.moveTo(0, 0.84);
  shape.lineTo(1, 0.84);
  shape.lineTo(1, 0.3);
  shape.quadraticCurveTo(1, -0.5, 0.2, -0.96);
  shape.lineTo(-0.26, -0.96);
  shape.lineTo(0.45, 0);
  shape.lineTo(0, 0);
  shape.closePath();
  return shape;
}

function buildMark(scene, camera) {
  addStudioLights(scene);
  const sweep = new THREE.PointLight(0xffffff, 10, 9, 1.4);
  sweep.position.set(0, 1.2, 2.6);
  scene.add(sweep);
  camera.position.set(0, 0, 7.4);

  const extrude = { depth: 0.42, bevelEnabled: true, bevelThickness: 0.05, bevelSize: 0.035, bevelSegments: 3, curveSegments: 48 };
  const ink = new THREE.MeshStandardMaterial({ color: 0xedf1e8, roughness: 0.45 });
  const lime = new THREE.MeshStandardMaterial({ color: 0xd5f66b, roughness: 0.5 });

  const mark = new THREE.Group();
  scene.add(mark);

  const c = new THREE.Mesh(new THREE.ExtrudeGeometry(cShape(), extrude), ink);
  mark.add(c);

  const comma = new THREE.Mesh(new THREE.ExtrudeGeometry(commaShape(), extrude), lime);
  comma.scale.setScalar(0.535);
  comma.position.set(1.04, -0.66, 0);
  mark.add(comma);

  const box = new THREE.Box3().setFromObject(mark);
  mark.position.sub(box.getCenter(new THREE.Vector3()));
  const pivot = new THREE.Group();
  pivot.add(mark);
  scene.add(pivot);

  const yaw = spring(40, 8);
  const pitch = spring(40, 8);

  return (time, dt) => {
    yaw.target = pointer.x * 0.45 + (reduceMotion ? 0 : Math.sin(time * 0.35) * 0.12);
    pitch.target = pointer.y * 0.25;
    pivot.rotation.y = reduceMotion ? yaw.target : yaw.step(dt);
    pivot.rotation.x = reduceMotion ? pitch.target : pitch.step(dt);
    sweep.position.x = reduceMotion ? -1 : Math.sin(time * 0.5) * 3.4;
  };
}

/* run */

const views = [
  createDitheredView(document.querySelector("[data-speaker]"), { pixel: 2, gain: 1.5, build: buildSpeaker }),
  createDitheredView(document.querySelector("[data-mark]"), { pixel: 4, build: buildMark }),
].filter(Boolean);

let last = performance.now();
function loop(now) {
  const dt = Math.min(0.05, (now - last) / 1000);
  last = now;
  for (const view of views) view.frame(now / 1000, dt);
  requestAnimationFrame(loop);
}
requestAnimationFrame(loop);
