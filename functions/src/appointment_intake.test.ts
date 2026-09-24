import assert from "node:assert/strict";
import {test} from "node:test";
import {appointmentEmail, appointmentPhone, boundedText} from "./appointment_intake";

test("appointment intake trims and bounds text", () => {
  assert.equal(boundedText("  concern  ", "Concern", 10, {required: true}), "concern");
  assert.throws(() => boundedText("x".repeat(11), "Concern", 10), /too long/);
});

test("appointment intake validates contact formats", () => {
  assert.equal(appointmentEmail("person@example.com"), "person@example.com");
  assert.equal(appointmentPhone("+63 912-345-6789"), "+63 912-345-6789");
  assert.throws(() => appointmentEmail("not-an-email"), /valid email/);
  assert.throws(() => appointmentPhone("abc"), /valid contact/);
});
