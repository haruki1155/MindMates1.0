// Pure rules for optional counselor transcript / remarks on a case
// (evaluator requirement #10). No Firebase reads: the callables load the
// records, this decides who may use them, validates text and plans writes.
import {Timestamp} from "firebase-admin/firestore";

import {CaseHistoryError, decideCaseHistoryAccess} from "./student_case_history";

type Doc = Record<string, unknown>;

export type CaseRemarksErrorCode = "permission-denied" | "invalid-argument" | "aborted" | "failed-precondition";
export class CaseRemarksError extends Error {
  constructor(public readonly code: CaseRemarksErrorCode, message: string) {
    super(message);
    this.name = "CaseRemarksError";
  }
}

export const MAX_REMARKS_LENGTH = 10000;
export const MAX_VERSIONS_RETURNED = 20;
export const NOT_AUTHORIZED_REMARKS = "You are not authorized to view or edit remarks for this case.";

// Anything below U+0020 except tab and line feed, plus DEL.
// eslint-disable-next-line no-control-regex
const CONTROL = /[\u0000-\u0008\u000B-\u001F\u007F]/;

/** Omitted, null and blank all mean "no remarks" (""). */
export function normalizeRemarks(value: unknown): string {
  if (value == null) return "";
  if (typeof value !== "string") throw new CaseRemarksError("invalid-argument", "Remarks must be text.");
  const text = value.replace(/\r\n?/g, "\n").trim();
  if (text.length > MAX_REMARKS_LENGTH) {
    throw new CaseRemarksError("invalid-argument", `Remarks can be at most ${MAX_REMARKS_LENGTH} characters.`);
  }
  if (CONTROL.test(text)) throw new CaseRemarksError("invalid-argument", "Remarks contain characters that cannot be saved.");
  return text;
}

export function expectedRevisionOf(value: unknown): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 0) {
    throw new CaseRemarksError("invalid-argument", "Reload the remarks before saving.");
  }
  return value;
}

/**
 * Only a counselor entitled to the student's case history (verified-college
 * assignment or an assigned case) may read or write remarks. The
 * super-administrator's history access does not extend to remark text.
 */
export function decideCaseRemarksAccess(input: Parameters<typeof decideCaseHistoryAccess>[0]): "college" | "assigned" {
  let basis: string;
  try {
    basis = decideCaseHistoryAccess(input);
  } catch (error) {
    if (error instanceof CaseHistoryError) throw new CaseRemarksError("permission-denied", NOT_AUTHORIZED_REMARKS);
    throw error;
  }
  if (basis !== "college" && basis !== "assigned") throw new CaseRemarksError("permission-denied", NOT_AUTHORIZED_REMARKS);
  return basis;
}

function revisionOf(current: Doc | null): number {
  const revision = current?.revision;
  return typeof revision === "number" && Number.isSafeInteger(revision) && revision >= 0 ? revision : 0;
}

/** Optimistic concurrency: the caller must have seen the current revision. */
export function planRemarksSave(input: {current: Doc | null; text: string; expectedRevision: number}):
  {kind: "write" | "unchanged"; revision: number} {
  const revision = revisionOf(input.current);
  if (input.expectedRevision !== revision) {
    throw new CaseRemarksError("aborted", "These remarks were changed by someone else. Reload them before saving.");
  }
  const currentText = typeof input.current?.text === "string" ? input.current.text : "";
  if (currentText === input.text) return {kind: "unchanged", revision};
  return {kind: "write", revision: revision + 1};
}

function iso(value: unknown): string | null {
  return value instanceof Timestamp ? value.toDate().toISOString() : null;
}

function text(value: unknown): string {
  return typeof value === "string" ? value : "";
}

/** The only remark fields that leave the server. Author IDs stay internal. */
export function remarksView(appointmentId: string, current: Doc | null, versions: Doc[]) {
  return {
    appointmentId,
    text: text(current?.text),
    revision: revisionOf(current),
    updatedAt: iso(current?.updatedAt),
    authorName: text(current?.authorNameSnapshot),
    versions: [...versions]
      .sort((a, b) => revisionOf(b) - revisionOf(a))
      .slice(0, MAX_VERSIONS_RETURNED)
      .map((version) => ({
        revision: revisionOf(version),
        text: text(version.text),
        authorName: text(version.authorNameSnapshot),
        savedAt: iso(version.createdAt),
      })),
  };
}

export type CaseRemarksView = ReturnType<typeof remarksView>;
