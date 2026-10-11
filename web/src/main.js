import * as THREE from 'three';
import { sweep, slide, Round } from './physics.js';
import './style.css';

const $ = id => document.getElementById(id);
const canvas = $('world');
const renderer = new THREE.WebGLRenderer({ canvas, antialias: true });
renderer.setPixelRatio(Math.min(devicePixelRatio, 1.8));
renderer.setSize(innerWidth, innerHeight);
renderer.xr.enabled = true;
renderer.xr.setReferenceSpaceType('local-floor');
renderer.outputColorSpace = THREE.SRGBColorSpace;
const scene = new THREE.Scene();
scene.background = new THREE.Color('#8aa798');
scene.fog = new THREE.Fog('#8aa798', 15, 48);
scene.add(new THREE.HemisphereLight(0xdceac0, 0x314c3c, 2.5));
const sun = new THREE.DirectionalLight(0xffe7b4, 3);
sun.position.set(-6, 16, 8); scene.add(sun);
const rig = new THREE.Group(); scene.add(rig);
const camera = new THREE.PerspectiveCamera(72, innerWidth / innerHeight, .03, 80);
camera.position.set(0, 1.65, 0); rig.add(camera);
const materials = {};
function material(color) { return materials[color] ??= new THREE.MeshStandardMaterial({ color, roughness: .95 }); }
const obstacles = [];
function box(name, position, size, color, solid = true) {
  const mesh = new THREE.Mesh(new THREE.BoxGeometry(...size), material(color));
  mesh.name = name; mesh.position.set(...position); scene.add(mesh);
  if (solid) obstacles.push({ min: position.map((v, i) => v - size[i] / 2), max: position.map((v, i) => v + size[i] / 2) });
  return mesh;
}
function sphere(parent, position, size, color) {
  const mesh = new THREE.Mesh(new THREE.SphereGeometry(1, 12, 8), material(color));
  mesh.position.set(...position); mesh.scale.set(...size); parent.add(mesh); return mesh;
}
box('Moss floor', [0, -.5, 0], [32, 1, 32], '#47613a');
box('North cliff', [0, 3, 16], [34, 7, 1], '#566451');
box('South cliff', [0, 3, -16], [34, 7, 1], '#566451');
box('East cliff', [16, 3, 0], [1, 7, 32], '#566451');
box('West cliff', [-16, 3, 0], [1, 7, 32], '#566451');
for (let i = 0; i < 16; i++) {
  const angle = i * Math.PI * 2 / 16, radius = i % 3 === 0 ? 12 : 10;
  const x = Math.cos(angle) * radius, z = Math.sin(angle) * radius;
  box('Climbable trunk', [x, 3, z], [1.05, 6, 1.05], '#684930');
  box('Branch', [x, 2.5, z], [3.2, .3, .8], '#785738');
  sphere(scene, [x, 6.8, z], [2.9, 2.1, 2.5], i % 2 ? '#2f6540' : '#3c7344');
}
box('Low rock', [-3, .5, 1], [3, 1, 2], '#81876b');
box('High rock', [-4, 1.25, 3], [2, 2.5, 2], '#6f7861');
box('Fallen log', [5, .35, -2], [3, .7, .9], '#785738');
// Seeded decorative mushrooms never affect collision or require downloads.
for (let i = 0; i < 26; i++) {
  const x = Math.sin(i * 17.3) * 13, z = Math.cos(i * 8.9) * 13;
  sphere(scene, [x, .1, z], [.06, .13, .06], '#cfbf8c');
  sphere(scene, [x, .22, z], [.17, .08, .17], '#ba6744');
}

const bots = Array.from({ length: 5 }, (_, id) => {
  const group = new THREE.Group(); scene.add(group);
  const body = sphere(group, [0, .64, 0], [.43, .52, .32], '#845634');
  sphere(group, [0, 1.12, .06], [.3, .29, .27], '#845634');
  sphere(group, [0, 1.02, .3], [.19, .13, .11], '#cdac75');
  for (const side of [-1, 1]) {
    sphere(group, [side * .13, 1.2, .3], [.045, .05, .04], '#17241c');
    sphere(group, [side * .34, 1.1, 0], [.1, .12, .08], '#cdac75');
    sphere(group, [side * .54, .48, .02], [.12, .43, .12], '#845634');
  }
  return { id, group, body, home: new THREE.Vector3((id - 2) * 2.8, .04, 5), target: new THREE.Vector3(), next: 0 };
});
const round = new Round();
let mode = 'menu', yaw = 0, pitch = 0, vertical = 0, elapsed = 0, lastScore = -1;
const velocity = new THREE.Vector3(), pushVelocity = new THREE.Vector3();
let previousContact = false, initialized = false, restartHeld = false;
const keys = new Set();
const controllers = [renderer.xr.getControllerGrip(0), renderer.xr.getControllerGrip(1)];
controllers.forEach(c => rig.add(c));
const handMeshes = [0, 1].map(() => { const mesh = sphere(scene, [0, 0, 0], [.09, .09, .09], '#d1a570'); mesh.visible = false; return mesh; });
const anchors = [new THREE.Vector3(), new THREE.Vector3()];
const viewer = new THREE.Vector3(), temp = new THREE.Vector3();

const boardCanvas = document.createElement('canvas'); boardCanvas.width = 1024; boardCanvas.height = 512;
const ctx = boardCanvas.getContext('2d');
const boardTexture = new THREE.CanvasTexture(boardCanvas);
boardTexture.colorSpace = THREE.SRGBColorSpace;
const board = new THREE.Mesh(new THREE.PlaneGeometry(3.8, 1.9), new THREE.MeshBasicMaterial({ map: boardTexture, side: THREE.DoubleSide }));
board.position.set(0, 2.4, -1.3); board.rotation.y = Math.PI; scene.add(board);
function updateBoard(tracked = true) {
  ctx.fillStyle = '#17372b'; ctx.fillRect(0, 0, 1024, 512);
  ctx.textAlign = 'center'; ctx.fillStyle = '#c6ec83'; ctx.font = 'bold 65px Arial';
  ctx.fillText('PRIMAL MONKE', 512, 100);
  ctx.fillStyle = '#f3f4e3'; ctx.font = '42px Arial';
  ctx.fillText(round.result === 'win' ? 'ALL MONKEYS TAGGED!' : round.result === 'timeout' ? "TIME’S UP!" : 'FOREST CHASE', 512, 185);
  ctx.font = 'bold 58px Arial'; ctx.fillText(`${round.tagged.size} / 5 TAGGED    ${Math.ceil(round.remaining)}s`, 512, 280);
  ctx.font = '28px Arial'; ctx.fillText(tracked ? 'Push surfaces • Touch monkeys • Right A to restart' : 'Tracking lost — round paused', 512, 370);
  ctx.fillText('An original forest playground', 512, 425); boardTexture.needsUpdate = true;
}
function restart() {
  round.restart(); rig.position.set(0, .03, -5); vertical = 0;
  velocity.set(0, 0, 0); pushVelocity.set(0, 0, 0); initialized = false; previousContact = false;
  for (const bot of bots) { bot.group.position.copy(bot.home); bot.body.material = material('#845634'); bot.next = 0; }
  $('message').hidden = true; lastScore = -1; updateBoard(); updateHud();
}
function updateHud() {
  $('score').textContent = `${round.tagged.size} / 5`; $('time').textContent = Math.ceil(round.remaining);
  if (round.result) { $('message').hidden = false; $('message').textContent = round.result === 'win' ? 'All five tagged! A perfect chase. Restart to play again.' : 'Time’s up! Restart for another chase.'; }
}
function beginDesktop() {
  mode = 'desktop'; restart(); $('welcome').hidden = true; $('hud').hidden = false;
  $('touch').hidden = !matchMedia('(pointer: coarse)').matches;
}
function returnToMenu() { mode = 'menu'; keys.clear(); $('welcome').hidden = false; $('hud').hidden = true; $('touch').hidden = true; $('message').hidden = true; }
$('play').onclick = beginDesktop; $('restart').onclick = restart; $('menu').onclick = returnToMenu;
function moveBody(delta, height = 1.65, headOffset = new THREE.Vector3()) {
  let allowed = delta.clone();
  // Three overlapping spheres approximate the capsule, including the player's
  // real room-scale head offset. Each further sweep can only restrict movement.
  for (const y of [.25, Math.max(.25, height / 2), Math.max(.25, height - .2)]) {
    const center = rig.position.clone().add(new THREE.Vector3(headOffset.x, y, headOffset.z));
    const next = slide(center.toArray(), allowed.toArray(), .24, obstacles);
    allowed.fromArray(next).sub(center);
  }
  rig.position.add(allowed); return allowed;
}
function tagAt(points, radius) {
  for (const bot of bots) {
    const center = bot.group.position.clone().add(new THREE.Vector3(0, .7, 0));
    if (points.some(p => p.distanceTo(center) < radius) && round.tag(bot.id)) {
      bot.body.material = material('#ed873d'); updateHud(); updateBoard();
    }
  }
}
function desktopTag() { if (mode === 'desktop') { camera.getWorldPosition(temp); tagAt([temp.clone().add(new THREE.Vector3(0, -.5, 0))], 1.7); } }
let pointer = null, dragDistance = 0;
canvas.addEventListener('pointerdown', e => { if (mode !== 'desktop') return; pointer = { x: e.clientX, y: e.clientY, id: e.pointerId }; dragDistance = 0; canvas.setPointerCapture(e.pointerId); });
canvas.addEventListener('pointermove', e => {
  if (!pointer || pointer.id !== e.pointerId) return;
  const dx = e.clientX - pointer.x, dy = e.clientY - pointer.y; dragDistance += Math.abs(dx) + Math.abs(dy);
  yaw -= dx * .005; pitch = THREE.MathUtils.clamp(pitch - dy * .004, -1.2, 1.2);
  pointer.x = e.clientX; pointer.y = e.clientY;
});
canvas.addEventListener('pointerup', () => { if (pointer && dragDistance < 8) desktopTag(); pointer = null; });
canvas.addEventListener('pointercancel', () => { pointer = null; });
window.addEventListener('keydown', e => {
  if (mode !== 'desktop') return;
  if (['Space', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight'].includes(e.code)) e.preventDefault();
  keys.add(e.code); if (e.code === 'KeyR') restart(); if (e.code === 'KeyE') desktopTag();
});
window.addEventListener('keyup', e => keys.delete(e.code));
window.addEventListener('blur', () => { keys.clear(); pointer = null; });
for (const button of document.querySelectorAll('[data-key]')) {
  button.onpointerdown = e => { button.setPointerCapture(e.pointerId); keys.add(button.dataset.key); };
  button.onpointerup = button.onpointercancel = () => keys.delete(button.dataset.key);
}
$('touch-jump').onpointerdown = () => keys.add('Space');
$('touch-jump').onpointerup = $('touch-jump').onpointercancel = () => keys.delete('Space');
$('touch-tag').onclick = desktopTag;

let xrSupported = false;
async function checkXR() {
  try { xrSupported = !!navigator.xr && await navigator.xr.isSessionSupported('immersive-vr'); } catch { xrSupported = false; }
  $('vr').disabled = !xrSupported; $('vr').textContent = xrSupported ? 'Enter VR ↗' : 'VR unavailable';
  $('xr-status').textContent = xrSupported ? 'Headset ready. Enter VR to play with your hands.' : 'For VR, open this page over HTTPS in a WebXR headset browser. You can still play on screen.';
}
$('vr').onclick = async () => {
  let session;
  try {
    session = await navigator.xr.requestSession('immersive-vr', { requiredFeatures: ['local-floor'] });
    await renderer.xr.setSession(session);
    mode = 'vr'; restart(); $('welcome').hidden = true; $('hud').hidden = true; $('touch').hidden = true;
    session.addEventListener('end', () => { initialized = false; handMeshes.forEach(h => h.visible = false); camera.position.set(0, 1.65, 0); camera.quaternion.identity(); returnToMenu(); });
  } catch (error) {
    if (session) await session.end().catch(() => {});
    $('xr-status').textContent = `Could not enter VR: ${error.message}. Check headset permissions and floor-tracking support.`;
  }
};
function vrMovement(dt, frame) {
  const session = renderer.xr.getSession();
  const sources = [...session.inputSources].filter(s => s.gripSpace && s.gamepad);
  const ref = renderer.xr.getReferenceSpace();
  const viewerPose = frame?.getViewerPose(ref);
  const tracked = session.visibilityState === 'visible' && !!viewerPose && sources.length >= 2 &&
    sources.slice(0, 2).every(source => !!frame.getPose(source.gripSpace, ref));
  const right = sources.find(s => s.handedness === 'right');
  const restartPressed = right?.gamepad.buttons[4]?.pressed ?? false;
  if (restartPressed && !restartHeld) restart(); restartHeld = restartPressed;
  if (!tracked) { initialized = false; previousContact = false; velocity.set(0, 0, 0); pushVelocity.set(0, 0, 0); handMeshes.forEach(h => h.visible = false); return false; }
  viewer.set(viewerPose.transform.position.x, viewerPose.transform.position.y, viewerPose.transform.position.z).add(rig.position);
  const headOffset = viewer.clone().sub(rig.position);
  // Use XRFrame poses directly, so tracking and input-source order are explicit.
  const desired = sources.slice(0, 2).map(source => {
    const pose = frame.getPose(source.gripSpace, ref);
    const p = new THREE.Vector3(pose.transform.position.x, pose.transform.position.y, pose.transform.position.z).add(rig.position);
    return viewer.clone().add(p.sub(viewer).clampLength(0, 1.5));
  });
  if (!initialized) { anchors.forEach((anchor, i) => anchor.copy(desired[i])); initialized = true; }
  let contacts = 0;
  const correction = new THREE.Vector3();
  const resolved = desired.map((point, i) => {
    const hit = sweep(anchors[i].toArray(), point.toArray(), .09, obstacles);
    if (!hit) return { point: point.clone(), contact: false };
    contacts++;
    const delta = point.clone().sub(anchors[i]);
    const t = Math.max(0, hit.t - .002 / Math.max(delta.length(), .002));
    const contact = anchors[i].clone().addScaledVector(delta, t);
    correction.add(contact.clone().sub(point));
    return { point: contact, contact: true };
  });
  const before = rig.position.clone();
  if (contacts) {
    moveBody(correction.divideScalar(contacts), headOffset.y, headOffset);
    pushVelocity.lerp(rig.position.clone().sub(before).divideScalar(dt), 1 - Math.exp(-18 * dt));
    velocity.set(0, 0, 0);
  } else {
    if (previousContact) velocity.copy(pushVelocity).multiplyScalar(1.15).clampLength(0, 7);
    velocity.y -= 9.81 * dt;
    const actual = moveBody(velocity.clone().multiplyScalar(dt), headOffset.y, headOffset);
    if (Math.abs(actual.y - velocity.y * dt) > .001) velocity.y = 0;
  }
  previousContact = contacts > 0;
  const movement = rig.position.clone().sub(before);
  resolved.forEach((result, i) => {
    anchors[i].copy(result.point); if (!result.contact) anchors[i].add(movement);
    handMeshes[i].visible = true; handMeshes[i].position.copy(anchors[i]);
  });
  tagAt(anchors, .65); return true;
}
function updateBots(dt) {
  for (const bot of bots) {
    if (round.tagged.has(bot.id)) continue;
    const away = bot.group.position.clone().sub(viewer); away.y = 0;
    if (elapsed > bot.next) {
      if (away.length() < 4) bot.target.copy(bot.group.position).add(away.normalize().multiplyScalar(5));
      else bot.target.set(Math.sin(elapsed * 1.1 + bot.id * 3) * 11, 0, Math.cos(elapsed * .7 + bot.id * 5) * 11);
      bot.target.x = THREE.MathUtils.clamp(bot.target.x, -12, 12); bot.target.z = THREE.MathUtils.clamp(bot.target.z, -12, 12);
      bot.next = elapsed + 1.5;
    }
    const direction = bot.target.clone().sub(bot.group.position); direction.y = 0;
    if (direction.length() < .4) { bot.next = 0; continue; }
    direction.normalize();
    const center = bot.group.position.clone(); center.y = .6;
    const next = new THREE.Vector3().fromArray(slide(center.toArray(), direction.clone().multiplyScalar(2.1 * dt).toArray(), .4, obstacles));
    if (next.distanceTo(center) < dt * .3) bot.next = 0;
    bot.group.position.x = next.x; bot.group.position.z = next.z;
    bot.group.position.y = .04 + Math.abs(Math.sin(elapsed * 8 + bot.id)) * .06;
    bot.group.rotation.y = Math.atan2(direction.x, direction.z);
  }
}
let previousTime = null, lastBoardTime = -1, lastTracked = null;
renderer.setAnimationLoop((time, frame) => {
  const dt = Math.min(.04, previousTime === null ? 0 : (time - previousTime) / 1000); previousTime = time; elapsed += dt;
  let active = false;
  if (mode === 'menu') {
    rig.position.set(0, 0, 0); camera.position.set(7, 4.4, -9); camera.lookAt(1, 1.3, 3);
  } else if (mode === 'desktop') {
    camera.position.set(0, 1.65, 0); camera.rotation.set(pitch, yaw, 0, 'YXZ'); camera.getWorldPosition(viewer);
    const right = Number(keys.has('KeyD') || keys.has('ArrowRight')) - Number(keys.has('KeyA') || keys.has('ArrowLeft'));
    const forward = Number(keys.has('KeyS') || keys.has('ArrowDown')) - Number(keys.has('KeyW') || keys.has('ArrowUp'));
    const movement = new THREE.Vector3(right, 0, forward).normalize().applyAxisAngle(new THREE.Vector3(0, 1, 0), yaw).multiplyScalar(4 * dt);
    const grounded = !!sweep(rig.position.clone().add(new THREE.Vector3(0, .25, 0)).toArray(), rig.position.clone().add(new THREE.Vector3(0, .21, 0)).toArray(), .24, obstacles);
    if (grounded && keys.has('Space')) { vertical = 4.6; keys.delete('Space'); }
    vertical = Math.max(-12, vertical - 9.81 * dt); movement.y = vertical * dt;
    const actual = moveBody(movement); if (Math.abs(actual.y - movement.y) > .001) vertical = 0;
    active = true;
  } else if (dt > 0) active = vrMovement(dt, frame);
  if (mode !== 'menu') {
    round.tick(dt, active);
    if (active && !round.result) updateBots(dt);
    updateHud();
    const second = Math.ceil(round.remaining);
    if (second !== lastBoardTime || round.tagged.size !== lastScore || active !== lastTracked) { updateBoard(active); lastBoardTime = second; lastScore = round.tagged.size; lastTracked = active; }
  }
  renderer.render(scene, camera);
});
window.addEventListener('resize', () => { camera.aspect = innerWidth / innerHeight; camera.updateProjectionMatrix(); renderer.setSize(innerWidth, innerHeight); });
restart(); checkXR();
