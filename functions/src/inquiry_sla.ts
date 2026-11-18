// Pure validation for inquiry replies and the response target. No Firebase
// imports. The response target is a super-admin setting chosen from PACC's
// options; nothing here schedules, escalates or decides policy on its own.

export const SLA_HOUR_OPTIONS = [24, 48, 72] as const;
export type SlaHours = typeof SLA_HOUR_OPTIONS[number];

export type InquirySlaErrorCode = "invalid-sla" | "invalid-message" | "invalid-request";

export class InquirySlaError extends Error {
  constructor(public readonly code: InquirySlaErrorCode, message: string) {
    super(message);
    this.name = "InquirySlaError";
  }
}

export const MAX_REPLY_LENGTH = 2000;
const REQUEST_ID = /^[A-Za-z0-9_-]{8,128}$/;

export function parseSlaHours(value: unknown): SlaHours {
  if (typeof value !== "number" || !(SLA_HOUR_OPTIONS as readonly number[]).includes(value)) {
    throw new InquirySlaError("invalid-sla", `Choose a response target of ${SLA_HOUR_OPTIONS.join(", ")} hours.`);
  }
  return value as SlaHours;
}

export function replyMessage(value: unknown): string {
  const text = typeof value === "string" ? value.trim() : "";
  if (text.length < 1 || text.length > MAX_REPLY_LENGTH) {
    throw new InquirySlaError("invalid-message", `Write a reply of 1-${MAX_REPLY_LENGTH} characters.`);
  }
  return text;
}

/** Client-generated key so a retried reply finds the reply it already created. */
export function requestIdFrom(value: unknown): string {
  if (typeof value !== "string" || !REQUEST_ID.test(value)) {
    throw new InquirySlaError("invalid-request", "A valid request ID is required.");
  }
  return value;
}
