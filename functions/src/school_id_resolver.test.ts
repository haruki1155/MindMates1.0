import assert from "node:assert/strict";
import {randomUUID} from "node:crypto";
import test from "node:test";
import {resolveSchoolIdAuthEmail, resolveSchoolIdAuthEmailDev} from "./account_recovery";

type Callable = {run(request: unknown): Promise<unknown>};
const dev = resolveSchoolIdAuthEmailDev as unknown as Callable;
const protectedResolver = resolveSchoolIdAuthEmail as unknown as Callable;

async function inProject<T>(project: string | undefined, fn: () => Promise<T>): Promise<T> {
  const previous = [process.env.GCLOUD_PROJECT, process.env.GOOGLE_CLOUD_PROJECT];
  for (const key of ["GCLOUD_PROJECT", "GOOGLE_CLOUD_PROJECT"]) {
    if (project === undefined) delete process.env[key];
    else process.env[key] = project;
  }
  try {
    return await fn();
  } finally {
    for (const [key, value] of [["GCLOUD_PROJECT", previous[0]], ["GOOGLE_CLOUD_PROJECT", previous[1]]] as const) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  }
}

const call = (resolver: Callable, schoolId: unknown) => resolver.run({auth: null, data: {schoolId}});

test("the Dev School-ID resolver refuses production and unknown projects", async () => {
  for (const project of ["mind-mates-cd2cf", "some-other-project", undefined]) {
    await inProject(project, () => assert.rejects(call(dev, "2021-12345"), {code: "permission-denied"}, String(project)));
  }
});

test("on Staging and Dev every valid ID resolves to its derived alias, whether or not an account exists", async () => {
  for (const project of ["mindmate-staging", "mindmate-dev-4e91c"]) {
    await inProject(project, async () => {
      assert.deepEqual(await call(dev, "2021-12345"), {email: "2021.12345@mindmate.local"});
      // A random ID that no account can have answers in exactly the same shape.
      const unknown = `X${randomUUID().slice(0, 8)}`;
      assert.deepEqual(await call(dev, unknown), {email: `${unknown.toLowerCase()}@mindmate.local`});
      await assert.rejects(call(dev, "ab"), {code: "invalid-argument"});
      await assert.rejects(call(dev, 12345), {code: "invalid-argument"});
    });
  }
});

test("the App Check resolver keeps the same pure answer in every project", async () => {
  await inProject("mind-mates-cd2cf", async () => {
    assert.deepEqual(await call(protectedResolver, " 2021-12345 "), {email: "2021.12345@mindmate.local"});
  });
});
