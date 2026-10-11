import test from 'node:test';
import assert from 'node:assert/strict';
import { sweep, slide, Round } from '../src/physics.js';
const wall = { min: [2, -5, -5], max: [3, 5, 5] };
test('fast hand movement cannot tunnel through a trunk', () => {
  const hit = sweep([0, 1, 0], [10, 1, 0], .1, [wall]);
  assert.ok(Math.abs(hit.t - .19) < 1e-8);
  assert.deepEqual(hit.normal, [-1, 0, 0]);
});
test('body slides along a cliff without crossing it', () => {
  const point = slide([0, 1, 0], [5, 0, 3], .25, [wall]);
  assert.ok(point[0] <= 1.75 && point[0] > 1.7);
  assert.ok(Math.abs(point[2] - 3) < .01);
});
test('resting hand can leave a surface, but cannot push farther inside', () => {
  assert.equal(sweep([1.91, 1, 0], [1, 1, 0], .1, [wall]), null);
  assert.equal(sweep([1.91, 1, 0], [2.5, 1, 0], .1, [wall]).t, 0);
});
test('floor prevents falling through the arena', () => {
  const point = slide([0, 1, 0], [0, -10, 0], .24, [{min:[-16,-1,-16],max:[16,0,16]}]);
  assert.ok(point[1] >= .24 && point[1] < .25);
});
test('tagging is unique, completes the round and restart resets it', () => {
  const round = new Round();
  assert.equal(round.tag(0), true); assert.equal(round.tag(0), false);
  for (let id = 1; id < 5; id++) round.tag(id);
  assert.equal(round.result, 'win');
  round.tick(100); assert.equal(round.remaining, 90);
  round.restart(); assert.equal(round.tagged.size, 0); assert.equal(round.result, null);
});
test('tracking loss pauses countdown and timeout blocks further tags', () => {
  const round = new Round(); round.tick(20, false); assert.equal(round.remaining, 90);
  round.tick(95); assert.equal(round.result, 'timeout'); assert.equal(round.remaining, 0);
  assert.equal(round.tag(0), false);
});
