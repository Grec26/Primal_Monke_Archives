// Sweep a sphere against the Minkowski-expanded boxes. Plain arrays keep this
// independent of rendering and allow collision regressions to run in Node.
export function sweep(start, end, radius, boxes) {
  let earliest = null;
  for (const box of boxes) {
    let near = 0, far = 1, normal = [0, 0, 0], valid = true;
    const inside = start.every((v, i) => v > box.min[i] - radius && v < box.max[i] + radius);
    // A resting contact may begin slightly inside the expanded volume. Allow
    // outward movement, but stop any movement deeper into its nearest face.
    if (inside) {
      let distance = Infinity, axis = 0, sign = 1;
      for (let i = 0; i < 3; i++) {
        for (const side of [-1, 1]) {
          const d = side < 0 ? start[i] - (box.min[i] - radius) : box.max[i] + radius - start[i];
          if (d < distance) { distance = d; axis = i; sign = side; }
        }
      }
      if ((end[axis] - start[axis]) * sign >= 0) continue;
      normal[axis] = sign;
      if (!earliest || earliest.t > 0) earliest = { t: 0, normal };
      continue;
    }
    for (let i = 0; i < 3; i++) {
      const delta = end[i] - start[i], min = box.min[i] - radius, max = box.max[i] + radius;
      if (Math.abs(delta) < 1e-8) { if (start[i] < min || start[i] > max) valid = false; continue; }
      let a = (min - start[i]) / delta, b = (max - start[i]) / delta;
      const sign = delta > 0 ? -1 : 1;
      if (a > b) [a, b] = [b, a];
      if (a >= near) { near = a; normal = [0, 0, 0]; normal[i] = sign; }
      far = Math.min(far, b);
      if (near > far) valid = false;
    }
    if (valid && near >= 0 && near <= 1 && far >= 0 && (!earliest || near < earliest.t)) earliest = { t: near, normal };
  }
  return earliest;
}

export function slide(start, delta, radius, boxes) {
  let position = [...start], movement = [...delta];
  for (let pass = 0; pass < 3; pass++) {
    const end = position.map((v, i) => v + movement[i]);
    const hit = sweep(position, end, radius, boxes);
    if (!hit) return end;
    const length = Math.hypot(...movement);
    const t = Math.max(0, hit.t - .002 / Math.max(length, .002));
    position = position.map((v, i) => v + movement[i] * t);
    movement = movement.map(v => v * (1 - t));
    const dot = movement.reduce((sum, v, i) => sum + v * hit.normal[i], 0);
    movement = movement.map((v, i) => v - Math.min(0, dot) * hit.normal[i]);
  }
  return position;
}

export class Round {
  constructor(count = 5, duration = 90) { this.count = count; this.duration = duration; this.restart(); }
  restart() { this.remaining = this.duration; this.tagged = new Set(); this.result = null; }
  tick(dt, active = true) {
    if (!active || this.result) return;
    this.remaining = Math.max(0, this.remaining - dt);
    if (!this.remaining) this.result = 'timeout';
  }
  tag(id) {
    if (this.result || id < 0 || id >= this.count) return false;
    const before = this.tagged.size;
    this.tagged.add(id);
    if (this.tagged.size === this.count) this.result = 'win';
    return this.tagged.size > before;
  }
}
