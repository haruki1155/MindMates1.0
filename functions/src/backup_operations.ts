// Adapter between google.longrunning.Operation records returned by the
// Firestore Admin operations client and the small summary the backup
// reconciliation needs. Pure: the protobuf decoder is injected so the contract
// is testable with real Any-wrapped ExportDocumentsMetadata bytes.

export type RawOperation = {
  name?: string | null;
  done?: boolean | null;
  error?: {code?: number | null; message?: string | null} | null;
  metadata?: {type_url?: string | null; value?: Uint8Array | string | null} | null;
};

export type ExportOperationSummary = {
  name: string;
  outputUriPrefix: string;
  done: boolean;
  failed: boolean;
  state: string;
};

export type MetadataDecoder = (bytes: Uint8Array) => unknown;

const EXPORT_METADATA_TYPE = "google.firestore.admin.v1.ExportDocumentsMetadata";

// google.firestore.admin.v1.OperationState
const OPERATION_STATES: Record<number, string> = {
  0: "OPERATION_STATE_UNSPECIFIED",
  1: "INITIALIZING",
  2: "PROCESSING",
  3: "PROCESSING",
  4: "CANCELLING",
  5: "SUCCESSFUL",
  6: "FAILED",
  7: "CANCELLED",
};

/** Listing could not be completed; callers must treat export presence as unknown. */
export class OperationListingUnavailableError extends Error {
  constructor(message: string, public readonly cause?: unknown) {
    super(message);
    this.name = "OperationListingUnavailableError";
  }
}

function anyBytes(value: Uint8Array | string | null | undefined): Uint8Array | null {
  if (value instanceof Uint8Array) return value.length > 0 ? value : null;
  if (typeof value === "string" && value.length > 0) {
    try {
      return new Uint8Array(Buffer.from(value, "base64"));
    } catch {
      return null;
    }
  }
  return null;
}

/**
 * Decode one operation. Returns null for anything that is not a well-formed
 * export operation (foreign metadata type, undecodable bytes, no name, no
 * output prefix), so the caller never matches on a guess.
 */
export function decodeExportOperation(operation: RawOperation, decode: MetadataDecoder): ExportOperationSummary | null {
  const name = typeof operation.name === "string" ? operation.name.trim() : "";
  if (!name) return null;
  const typeUrl = String(operation.metadata?.type_url ?? "");
  if (!typeUrl.endsWith(`/${EXPORT_METADATA_TYPE}`) && typeUrl !== EXPORT_METADATA_TYPE) return null;
  const bytes = anyBytes(operation.metadata?.value);
  if (!bytes) return null;
  let decoded: {outputUriPrefix?: unknown; operationState?: unknown};
  try {
    decoded = (decode(bytes) ?? {}) as {outputUriPrefix?: unknown; operationState?: unknown};
  } catch {
    return null;
  }
  const outputUriPrefix = typeof decoded.outputUriPrefix === "string" ? decoded.outputUriPrefix.trim() : "";
  if (!outputUriPrefix) return null;
  const rawState = decoded.operationState;
  const state = typeof rawState === "number" ? OPERATION_STATES[rawState] ?? String(rawState)
    : typeof rawState === "string" && rawState ? rawState : "OPERATION_STATE_UNSPECIFIED";
  const done = operation.done === true;
  const failed = done && (operation.error != null || state === "FAILED" || state === "CANCELLED");
  return {name, outputUriPrefix, done, failed, state};
}

/**
 * List export operations across both listings the Firestore Admin API offers:
 * the default (in-progress and failed) and `done: true` (completed). Any
 * listing error is surfaced as unavailable rather than as "no operations",
 * because an empty answer would let a caller start a duplicate paid export.
 */
export async function listExportOperations(
  page: (filter: string) => AsyncIterable<RawOperation>,
  decode: MetadataDecoder,
): Promise<ExportOperationSummary[]> {
  const byName = new Map<string, ExportOperationSummary>();
  for (const filter of ["", "done: true"]) {
    try {
      for await (const raw of page(filter)) {
        const summary = decodeExportOperation(raw, decode);
        if (!summary) continue;
        const existing = byName.get(summary.name);
        // A record seen in the done listing wins over its running twin.
        if (!existing || (summary.done && !existing.done)) byName.set(summary.name, summary);
      }
    } catch (error) {
      throw new OperationListingUnavailableError(`Export operation listing failed (filter "${filter}").`, error);
    }
  }
  return [...byName.values()];
}

/** Exact prefix match only; a longer or shorter prefix is a different job. */
export function findOperationForPrefix(operations: ExportOperationSummary[], outputUriPrefix: string): ExportOperationSummary | undefined {
  return operations.find((operation) => operation.outputUriPrefix === outputUriPrefix);
}
