import assert from "node:assert/strict";
import {test} from "node:test";
import {protobuf} from "google-gax";
import {v1 as firestoreAdmin} from "@google-cloud/firestore";

import {
  decodeExportOperation,
  findOperationForPrefix,
  listExportOperations,
  OperationListingUnavailableError,
  RawOperation,
} from "./backup_operations";

// Adapter contract: real google.longrunning.Operation shapes whose `metadata`
// is a google.protobuf.Any wrapping encoded ExportDocumentsMetadata bytes.
const root = protobuf.Root.fromJSON(require("@google-cloud/firestore/build/protos/admin_v1.json"));
const Metadata = root.lookupType("google.firestore.admin.v1.ExportDocumentsMetadata");
const TYPE_URL = "type.googleapis.com/google.firestore.admin.v1.ExportDocumentsMetadata";
const PROCESSING = 3;
const SUCCESSFUL = 5;
const FAILED = 6;

function anyFor(prefix: string, state: number, typeUrl = TYPE_URL): {type_url: string; value: Uint8Array} {
  return {type_url: typeUrl, value: Metadata.encode(Metadata.create({outputUriPrefix: prefix, operationState: state})).finish()};
}

// The production decoder is the admin client's own long-running metadata decoder.
const client = new firestoreAdmin.FirestoreAdminClient();
const decode = (bytes: Uint8Array) => client.descriptors.longrunning.exportDocuments.metadataDecoder(bytes) as unknown;

test("decodeExportOperation decodes Any-wrapped ExportDocumentsMetadata from a running operation", () => {
  const op: RawOperation = {name: "projects/p/databases/(default)/operations/abc", done: false, metadata: anyFor("gs://b/firestore-exports/x", PROCESSING)};
  assert.deepEqual(decodeExportOperation(op, decode), {
    name: "projects/p/databases/(default)/operations/abc",
    outputUriPrefix: "gs://b/firestore-exports/x",
    done: false,
    failed: false,
    state: "PROCESSING",
  });
});

test("decodeExportOperation reports completed and failed operations", () => {
  const ok = decodeExportOperation({name: "ops/1", done: true, metadata: anyFor("gs://b/p", SUCCESSFUL)}, decode);
  assert.equal(ok?.done, true); assert.equal(ok?.failed, false); assert.equal(ok?.state, "SUCCESSFUL");
  const failed = decodeExportOperation({name: "ops/2", done: true, error: {code: 7, message: "denied"}, metadata: anyFor("gs://b/p", FAILED)}, decode);
  assert.equal(failed?.done, true); assert.equal(failed?.failed, true);
});

test("decodeExportOperation accepts base64 Any values and rejects foreign or empty metadata", () => {
  const any = anyFor("gs://b/p", PROCESSING);
  const base64: RawOperation = {name: "ops/3", done: false, metadata: {type_url: any.type_url, value: Buffer.from(any.value).toString("base64")}};
  assert.equal(decodeExportOperation(base64, decode)?.outputUriPrefix, "gs://b/p");
  assert.equal(decodeExportOperation({name: "ops/4", done: false, metadata: anyFor("gs://b/p", PROCESSING, "type.googleapis.com/google.firestore.admin.v1.ImportDocumentsMetadata")}, decode), null);
  assert.equal(decodeExportOperation({name: "ops/5", done: false, metadata: anyFor("", PROCESSING)}, decode), null);
  assert.equal(decodeExportOperation({name: "ops/6", done: false, metadata: null}, decode), null);
  assert.equal(decodeExportOperation({done: false, metadata: anyFor("gs://b/p", PROCESSING)}, decode), null);
  assert.equal(decodeExportOperation({name: "ops/7", done: false, metadata: {type_url: TYPE_URL, value: new Uint8Array([0xff, 0xff, 0xff])}}, () => { throw new Error("corrupt"); }), null);
});

test("listExportOperations queries both the default (running/failed) and done:true listings and de-duplicates", async () => {
  const filters: string[] = [];
  const pages: Record<string, RawOperation[]> = {
    "": [{name: "ops/running", done: false, metadata: anyFor("gs://b/a", PROCESSING)}, {name: "ops/other", done: false, metadata: anyFor("gs://b/a", PROCESSING, "type.googleapis.com/x.Other")}],
    "done: true": [{name: "ops/done", done: true, metadata: anyFor("gs://b/c", SUCCESSFUL)}, {name: "ops/running", done: true, metadata: anyFor("gs://b/a", SUCCESSFUL)}],
  };
  const pager = async function* (filter: string) { filters.push(filter); yield* pages[filter] ?? []; };
  const ops = await listExportOperations(pager, decode);
  assert.deepEqual(filters, ["", "done: true"]);
  assert.deepEqual(ops.map((op) => [op.name, op.outputUriPrefix, op.done]), [["ops/running", "gs://b/a", true], ["ops/done", "gs://b/c", true]]);
});

test("listExportOperations is conservative: any listing error is surfaced as unavailable, never as an empty list", async () => {
  const pager = async function* (filter: string): AsyncGenerator<RawOperation> {
    if (filter === "done: true") throw new Error("PERMISSION_DENIED");
    yield {name: "ops/running", done: false, metadata: anyFor("gs://b/a", PROCESSING)};
  };
  await assert.rejects(listExportOperations(pager, decode), (e: unknown) => e instanceof OperationListingUnavailableError);
});

test("findOperationForPrefix matches the exact prefix only", () => {
  const ops = [
    {name: "ops/1", outputUriPrefix: "gs://b/firestore-exports/20261115-023000-job", done: false, failed: false, state: "PROCESSING"},
    {name: "ops/2", outputUriPrefix: "gs://b/firestore-exports/20261115-023000-job-2", done: true, failed: false, state: "SUCCESSFUL"},
  ];
  assert.equal(findOperationForPrefix(ops, "gs://b/firestore-exports/20261115-023000-job")?.name, "ops/1");
  assert.equal(findOperationForPrefix(ops, "gs://b/firestore-exports/20261115-023000-jo"), undefined);
  assert.equal(findOperationForPrefix(ops, "gs://b/firestore-exports/20261115-023000-job/"), undefined);
});
