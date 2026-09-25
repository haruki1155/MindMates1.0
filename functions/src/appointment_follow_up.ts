import {HttpsError} from "firebase-functions/v2/https";

/** Validates text that is safe to display to the appointment client. */
export function validateRescheduleReason(value: unknown): string {
  if (typeof value !== "string" || !value.trim()) {
    throw new HttpsError("invalid-argument", "Reschedule reason is required.");
  }
  const reason = value.trim();
  if (reason.length < 3) {
    throw new HttpsError(
      "invalid-argument",
      "Reschedule reason must contain at least 3 characters.",
    );
  }
  if (reason.length > 500) {
    throw new HttpsError("invalid-argument", "Reschedule reason is too long.");
  }
  return reason;
}

export function validateCompletionInput(input: {
  summary: unknown;
  offerFollowUp: unknown;
  followUpMessage?: unknown;
}): {summary: string; offerFollowUp: boolean; followUpMessage: string} {
  if (typeof input.summary !== "string" || input.summary.trim().length < 3) {
    throw new HttpsError("invalid-argument", "Session summary must contain at least 3 characters.");
  }
  const summary = input.summary.trim();
  if (summary.length > 2_000) {
    throw new HttpsError("invalid-argument", "Session summary is too long.");
  }
  const offerFollowUp = input.offerFollowUp === true;
  const followUpMessage = typeof input.followUpMessage === "string" ? input.followUpMessage.trim() : "";
  if (offerFollowUp && !followUpMessage) {
    throw new HttpsError("invalid-argument", "Client message is required when offering a follow-up.");
  }
  if (followUpMessage.length > 1_000) {
    throw new HttpsError("invalid-argument", "Client message is too long.");
  }
  return {summary, offerFollowUp, followUpMessage};
}

export function isEligibleFollowUpParentStatus(value: unknown): boolean {
  return ["completed", "no_show", "noshow", "expired"].includes(
    String(value ?? "").trim().toLowerCase(),
  );
}
