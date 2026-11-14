import {test} from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {resolve} from "node:path";
test("index configuration parses and keeps composite indexes outside TTL overrides", () => {
  const config = JSON.parse(readFileSync(resolve(__dirname,"../../firestore.indexes.json"),"utf8"));
  assert.equal(config.indexes.filter((index: {collectionGroup:string}) => index.collectionGroup === "announcements").length,3);
  for (const override of config.fieldOverrides) assert.deepEqual(override.indexes,[]);
});
