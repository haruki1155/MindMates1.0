import assert from "node:assert/strict";
import {test} from "node:test";
import {appointmentSlotId} from "./index";

test("shared PACC capacity locks an identical start timestamp", () => {
  const tenAm = {toMillis: () => 1_800_000};
  assert.equal(appointmentSlotId(tenAm), appointmentSlotId(tenAm));
});

test("shared PACC capacity does not imply duration-aware overlap protection", () => {
  const tenAm = {toMillis: () => 1_800_000};
  const elevenAm = {toMillis: () => 5_400_000};
  assert.notEqual(appointmentSlotId(tenAm), appointmentSlotId(elevenAm));
});
