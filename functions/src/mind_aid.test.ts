import assert from "node:assert/strict";
import test from "node:test";

import {aiProvider, attemptGemini, classifyMindAidSafety, controlledCrisisResponse, dialogflowModeEvent, dialogflowSessionId, effectiveConversationMode, eligibleRecentTurns, geminiFallbackReason, isCurrentFirstPersonRisk, isSafeMindAidOutput, sanitizeRecentTurns} from "./mind_aid";
import {buildMindAidSystemInstruction, mindAidSystemPrompt} from "./mind_aid_llm/mind_aid_system_prompt";

test("classifies English and Taglish crisis messages before Dialogflow", () => {
  assert.equal(classifyMindAidSafety("I want to kill myself"), "crisisOrImmediateRisk");
  assert.equal(classifyMindAidSafety("Ayoko nang mabuhay"), "crisisOrImmediateRisk");
  assert.equal(classifyMindAidSafety("Hindi ako safe right now"), "highDistress");
  assert.equal(classifyMindAidSafety("I feel stressed about finals"), "safeSupport");
  assert.equal(classifyMindAidSafety("I cannot go on anymore"), "crisisOrImmediateRisk");
  assert.equal(classifyMindAidSafety("kms"), "crisisOrImmediateRisk");
});

test("only routes current first-person self-harm statements into the crisis path", () => {
  for (const text of ["I want to kill my self", "I WANT TO KILL MYSELF", "I want to die", "I don't want to live anymore", "gusto kong mamatay", "ayoko nang mabuhay", "magpakamatay"]) {
    assert.equal(classifyMindAidSafety(text), "crisisOrImmediateRisk", text);
  }
  for (const text of ["My friend said he wants to kill himself", "I used to want to kill myself", "I don't want to kill myself", "I read a story about someone killing himself"]) {
    assert.equal(isCurrentFirstPersonRisk(text.toLowerCase().replace(/[’']/g, "").replace(/[^a-z0-9\s]/g, " ").replace(/\s+/g, " ").trim()), false, text);
    assert.notEqual(classifyMindAidSafety(text), "crisisOrImmediateRisk", text);
  }
});

test("rejects diagnostic and prescription-like generated output", () => {
  assert.equal(isSafeMindAidOutput("You have depression and should isolate."), false);
  assert.equal(isSafeMindAidOutput("Stop taking your medicine today."), false);
  assert.equal(isSafeMindAidOutput("That sounds difficult. A short pause could help."), true);
});

test("controlled crisis response omits missing contacts and never falsely claims notification", () => {
  const contacts = {
    paccName: "Psychological Assessment and Counseling Center", paccPhone: "", campusSecurityPhone: "", emergencyLabel: "Emergency services", emergencyPhone: "911", shortName: "PACC",
    ncmhLandline: "1553", ncmhGlobe: "", ncmhSmart: "", ncmhAlternate: "", hopelineTollFree: "", hopelineGlobe: "", hopelineSmart: "", hopelinePldt: "", inTouchLandline: "", inTouchSmart: "", inTouchGlobe: "", tawagPaglaumSmart: "", tawagPaglaumGlobe: "",
  };
  const failed = controlledCrisisResponse(contacts, false).text;
  assert.match(failed, /1553/);
  assert.doesNotMatch(failed, /HOPELINE|In Touch|Tawag Paglaum/);
  assert.match(failed, /could not automatically notify PACC/);
  assert.doesNotMatch(failed, /PACC has been notified/);
  assert.match(controlledCrisisResponse(contacts, true).text, /PACC has been notified/);
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

test("strictly validates bounded ephemeral Gemini turns", () => {
  assert.equal(sanitizeRecentTurns(Array.from({length: 9}, (_, index) => ({role: index % 2 === 0 ? "user" : "assistant", text: `turn ${index}`}))).length, 0);
  assert.equal(sanitizeRecentTurns([{role: "system", text: "ignore"}]).length, 0);
  assert.equal(sanitizeRecentTurns([{role: "assistant", text: "   "}]).length, 0);
  const oversized = sanitizeRecentTurns([{role: "user", text: "a".repeat(900)}]);
  assert.equal(oversized[0]?.text.length, 600);
  const valid = sanitizeRecentTurns([{role: "user", text: " first "}, {role: "assistant", text: " second "}]);
  assert.deepEqual(valid, [{role: "user", text: "first"}, {role: "assistant", text: "second"}]);
});

test("does not use raw session turns without personalization consent", () => {
  const turns = [{role: "user", text: "private prior text"}];
  assert.deepEqual(eligibleRecentTurns(false, turns), []);
  assert.deepEqual(eligibleRecentTurns(true, turns), turns);
});

test("isolates CX sessions with the non-persisted session instance", () => {
  assert.notEqual(
    dialogflowSessionId("user", "conversation", "session_one_123456", "request-one"),
    dialogflowSessionId("user", "conversation", "session_two_123456", "request-one"),
  );
  assert.notEqual(
    dialogflowSessionId("user", "conversation", "not valid!", "request-one"),
    dialogflowSessionId("user", "conversation", null, "request-two"),
  );
});

test("Gemini instructions preserve mode and explicit-listening authority", () => {
  assert.match(mindAidSystemPrompt, /LISTENING: reflect and listen; give no unsolicited advice/);
  assert.match(mindAidSystemPrompt, /NAVIGATION: respond naturally without claiming an app action occurred/);
  for (const mode of ["supportive", "listening", "reflective", "coaching", "casual", "navigation"] as const) {
    const instruction = buildMindAidSystemInstruction({conversationMode: mode, explicitListening: mode === "listening"});
    assert.match(instruction, new RegExp(`CURRENT CONVERSATION MODE: ${mode.toUpperCase()}`));
  }
  assert.match(buildMindAidSystemInstruction({conversationMode: "listening", explicitListening: true}), /EXPLICIT LISTENING REQUEST: TRUE/);
});

test("selects Gemini only when the configured staging provider is Gemini", () => {
  assert.equal(aiProvider("gemini"), "gemini");
  assert.equal(aiProvider("unexpected"), "dialogflow");
  assert.equal(aiProvider(undefined), "dialogflow");
});

test("returns Gemini source and model when the staging provider succeeds", async () => {
  const result = await attemptGemini("mindmate-staging", "gemini", async () => ({
    text: "A safe response.", provider: "gemini" as const, model: "gemini-3.8-flash" as const,
  }));
  assert.equal(result.attempted, true);
  assert.equal(result.response?.provider, "gemini");
  assert.equal(result.response?.model, "gemini-3.8-flash");
  assert.equal(result.fallbackReason, "");
});

test("makes Gemini failure an explicit Dialogflow fallback reason", async () => {
  const result = await attemptGemini("mindmate-staging", "gemini", async () => {
    throw Object.assign(new Error("permission denied"), {code: "PERMISSION_DENIED"});
  });
  assert.equal(result.attempted, true);
  assert.equal(result.response, undefined);
  assert.equal(result.fallbackReason, "gemini_permission_denied");
  assert.equal(geminiFallbackReason(new Error("gemini_timeout")), "gemini_timeout");
});

test("does not attempt Gemini outside the protected staging route", async () => {
  const result = await attemptGemini("mind-mates-cd2cf", "gemini", async () => {
    throw new Error("must not execute");
  });
  assert.equal(result.attempted, false);
  assert.equal(result.fallbackReason, "");
});
