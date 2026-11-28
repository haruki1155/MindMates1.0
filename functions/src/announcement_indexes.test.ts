import {test} from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {resolve} from "node:path";
type Field = {fieldPath: string; order?: string; arrayConfig?: string};
type Index = {collectionGroup: string; queryScope: string; fields: Field[]};
const shape = (fields: Field[]) => fields.map((field) => `${field.fieldPath}:${field.order ?? field.arrayConfig}`).join(",");
test("index configuration parses and keeps composite indexes outside TTL overrides", () => {
  const config = JSON.parse(readFileSync(resolve(__dirname,"../../firestore.indexes.json"),"utf8"));
  const announcements = (config.indexes as Index[]).filter((index) => index.collectionGroup === "announcements");
  assert.deepEqual(announcements.map((index) => shape(index.fields)).sort(), [
    "status:ASCENDING,audienceRoles:CONTAINS,publishedAt:DESCENDING,__name__:DESCENDING",
    "status:ASCENDING,category:ASCENDING,publishedAt:DESCENDING,__name__:DESCENDING",
    "status:ASCENDING,postType:ASCENDING,audienceRoles:CONTAINS,publishedAt:DESCENDING,__name__:DESCENDING",
    "status:ASCENDING,publishedAt:DESCENDING,__name__:DESCENDING",
    "status:ASCENDING,updatedAt:DESCENDING,__name__:DESCENDING",
  ]);
  for (const index of announcements) assert.equal(index.queryScope, "COLLECTION");
  for (const override of config.fieldOverrides) assert.deepEqual(override.indexes,[]);
});
