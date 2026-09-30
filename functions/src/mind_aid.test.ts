import assert from "node:assert/strict";
import test from "node:test";

import {classifyMindAidSafety, dialogflowModeEvent, effectiveConversationMode, isSafeMindAidOutput} from "./mind_aid";

test("classifies English and Taglish crisis messages before Dialogflow", () => {
  assert.equal(classifyMindAidSafety("I want to kill myself"), "crisisOrImmediateRisk");
  assert.equal(classifyMindAidSafety("Ayoko nang mabuhay"), "crisisOrImmediateRisk");
  assert.equal(classifyMindAidSafety("Hindi ako safe right now"), "highDistress");
  assert.equal(classifyMindAidSafety("I feel stressed about finals"), "safeSupport");
  assert.equal(classifyMindAidSafety("I cannot go on anymore"), "crisisOrImmediateRisk");
  assert.equal(classifyMindAidSafety("kms"), "crisisOrImmediateRisk");
});

test("rejects diagnostic and prescription-like generated output", () => {
  assert.equal(isSafeMindAidOutput("You have depression and should isolate."), false);
  assert.equal(isSafeMindAidOutput("Stop taking your medicine today."), false);
  assert.equal(isSafeMindAidOutput("That sounds difficult. A short pause could help."), true);
});

test("normalizes conversation mode as behavioral metadata", () => {
  assert.equal(effectiveConversationMode("listening"), "listening");
  assert.equal(effectiveConversationMode("admin"), "supportive");
  assert.equal(effectiveConversationMode(null), "supportive");
});

test("maps validated conversation modes to CX routing events", () => {
  assert.equal(dialogflowModeEvent("listening"), "mind_aid_mode_listening");
  assert.equal(dialogflowModeEvent("navigation"), "mind_aid_mode_navigation");
});
