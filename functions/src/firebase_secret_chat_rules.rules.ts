import {readFileSync} from "node:fs";
import {resolve} from "node:path";
import {after, before, beforeEach, test} from "node:test";

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  limit,
  orderBy,
  query,
  serverTimestamp,
  setDoc,
  Timestamp,
  updateDoc,
  where,
} from "firebase/firestore";

const projectId = "mind-mates-secret-chat-rules-test";
let environment: RulesTestEnvironment;

before(async () => {
  environment = await initializeTestEnvironment({
    projectId,
    firestore: {
      rules: readFileSync(resolve(__dirname, "../../firestore.rules"), "utf8"),
    },
    storage: {
      rules: readFileSync(resolve(__dirname, "../../storage.rules"), "utf8"),
    },
  });
});

beforeEach(async () => {
  await Promise.all([environment.clearFirestore(), environment.clearStorage()]);
});
after(async () => environment.cleanup());

async function seedProfileData() {
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "secret_chat_profiles/owner"), {
      userId: "owner",
      alias: "Calm Owl",
      aliasKey: "calm owl",
      createdAt: Timestamp.now(),
      updatedAt: Timestamp.now(),
    });
    await setDoc(doc(context.firestore(), "secret_chat_aliases/calm owl"), {
      userId: "owner",
      alias: "Calm Owl",
      updatedAt: Timestamp.now(),
    });
    await setDoc(doc(context.firestore(), "secret_chat_profile_stats/owner"), {
      userId: "owner",
      reads: 2,
      reactions: 1,
      comments: 1,
      updatedAt: Timestamp.now(),
    });
  });
}

test("signed-in users can resolve profiles but unauthenticated users cannot", async () => {
  await seedProfileData();
  const profilePath = "secret_chat_profiles/owner";
  await assertSucceeds(
    getDoc(doc(environment.authenticatedContext("owner").firestore(), profilePath)),
  );
  await assertSucceeds(
    getDoc(doc(environment.authenticatedContext("other").firestore(), profilePath)),
  );
  await assertFails(
    getDoc(doc(environment.unauthenticatedContext().firestore(), profilePath)),
  );
});

test("clients cannot mutate profiles or alias reservations, including admins", async () => {
  await seedProfileData();
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "users/admin"), {role: "admin"});
  });
  for (const userId of ["owner", "other", "admin"]) {
    const db = environment.authenticatedContext(userId).firestore();
    await assertFails(setDoc(doc(db, "secret_chat_profiles/owner"), {
      userId: "owner",
      alias: "Changed Name",
      aliasKey: "changed name",
      createdAt: Timestamp.now(),
      updatedAt: Timestamp.now(),
    }));
    await assertFails(setDoc(doc(db, "secret_chat_aliases/changed name"), {
      userId: "owner",
      alias: "Changed Name",
      updatedAt: Timestamp.now(),
    }));
  }
});

test("profile statistics are owner-only and backend-write-only", async () => {
  await seedProfileData();
  const statsPath = "secret_chat_profile_stats/owner";
  await assertSucceeds(
    getDoc(doc(environment.authenticatedContext("owner").firestore(), statsPath)),
  );
  await assertFails(
    getDoc(doc(environment.authenticatedContext("other").firestore(), statsPath)),
  );
  await assertFails(
    setDoc(doc(environment.authenticatedContext("owner").firestore(), statsPath), {
      userId: "owner",
      reads: 999,
    }),
  );
});

test("signed-in owners can query only their active recent posts", async () => {
  await environment.withSecurityRulesDisabled(async (context) => {
    const base = {
      authorId: "owner",
      message: "I feel stressed and need support.",
      category: "Stress",
      categories: ["Stress"],
      createdAt: Timestamp.now(),
      updatedAt: Timestamp.now(),
      likeCount: 0,
      commentCount: 0,
      readCount: 0,
      safetyLabels: ["stress"],
      isAnonymous: true,
    };
    await setDoc(doc(context.firestore(), "secret_chats/active_post"), {
      ...base,
      moderationStatus: "active",
    });
    await setDoc(doc(context.firestore(), "secret_chats/hidden_post"), {
      ...base,
      moderationStatus: "hidden",
    });
  });

  const ownerDb = environment.authenticatedContext("owner").firestore();
  const allowed = await assertSucceeds(getDocs(query(
    collection(ownerDb, "secret_chats"),
    where("authorId", "==", "owner"),
    where("moderationStatus", "==", "active"),
    orderBy("createdAt", "desc"),
    limit(3),
  )));
  if (allowed.size !== 1 || allowed.docs[0]?.id !== "active_post") {
    throw new Error("The active recent-post query returned unexpected documents.");
  }
  await assertFails(getDocs(query(
    collection(ownerDb, "secret_chats"),
    where("authorId", "==", "owner"),
    orderBy("createdAt", "desc"),
    limit(3),
  )));

  const unauthenticatedDb = environment.unauthenticatedContext().firestore();
  await assertFails(getDocs(query(
    collection(unauthenticatedDb, "secret_chats"),
    where("authorId", "==", "owner"),
    where("moderationStatus", "==", "active"),
    orderBy("createdAt", "desc"),
    limit(3),
  )));
});

test("post owners cannot bypass the trusted delete backend", async () => {
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "secret_chats/post_1"), {
      authorId: "owner",
      message: "I feel stressed and need support.",
      category: "Stress",
      categories: ["Stress"],
      createdAt: Timestamp.now(),
      updatedAt: Timestamp.now(),
      likeCount: 0,
      commentCount: 0,
      readCount: 0,
      moderationStatus: "active",
      safetyLabels: ["stress"],
      isAnonymous: true,
    });
  });
  await assertFails(
    deleteDoc(
      doc(environment.authenticatedContext("owner").firestore(), "secret_chats/post_1"),
    ),
  );
  await assertFails(
    deleteDoc(
      doc(environment.authenticatedContext("other").firestore(), "secret_chats/post_1"),
    ),
  );
});

const forumPost = (overrides: Record<string, unknown> = {}) => ({
  authorId: "owner",
  message: "I feel stressed and need support.",
  category: "Stress",
  categories: ["Stress"],
  createdAt: serverTimestamp(),
  updatedAt: serverTimestamp(),
  likeCount: 0,
  commentCount: 0,
  readCount: 0,
  moderationStatus: "active",
  safetyLabels: ["stress"],
  isAnonymous: true,
  ...overrides,
});

test("clients cannot publish posts or comments directly, bypassing moderation", async () => {
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "secret_chats/post_1"), {...forumPost(), createdAt: Timestamp.now()});
  });
  const ownerDb = environment.authenticatedContext("owner").firestore();
  await assertFails(setDoc(doc(ownerDb, "secret_chats/direct"), forumPost()));
  await assertFails(setDoc(doc(ownerDb, "secret_chat_comments/direct"), {
    postId: "post_1",
    authorId: "owner",
    message: "A direct comment",
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    moderationStatus: "active",
    safetyLabels: [],
    isAnonymous: true,
  }));
});

test("staff can change moderation status but never rewrite published text", async () => {
  await environment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, "users/admin"), {
      role: "admin", accessRole: "admin", accountStatus: "active",
    });
    await setDoc(doc(db, "secret_chats/post_1"), {...forumPost(), createdAt: Timestamp.now()});
    await setDoc(doc(db, "secret_chat_comments/comment_1"), {
      postId: "post_1", authorId: "owner", message: "Kaya mo yan!",
      createdAt: Timestamp.now(), updatedAt: Timestamp.now(),
      moderationStatus: "active", safetyLabels: [], isAnonymous: true,
    });
  });
  const adminDb = environment.authenticatedContext("admin", {email_verified: true}).firestore();
  await assertSucceeds(updateDoc(doc(adminDb, "secret_chats/post_1"), {
    moderationStatus: "hidden", updatedAt: serverTimestamp(),
  }));
  await assertFails(updateDoc(doc(adminDb, "secret_chats/post_1"), {message: "Rewritten by staff"}));
  await assertSucceeds(updateDoc(doc(adminDb, "secret_chat_comments/comment_1"), {
    moderationStatus: "hidden",
  }));
  await assertFails(updateDoc(doc(adminDb, "secret_chat_comments/comment_1"), {message: "Rewritten"}));
});

test("Storage accepts only owned valid profile images", async () => {
  const image = new Uint8Array([0xff, 0xd8, 0xff, 0xd9]);
  const ownerStorage = environment.authenticatedContext("owner").storage();
  await assertSucceeds(
    upload(
      ownerStorage.ref("secret_chat_profiles/owner/avatar_123.jpg"),
      image,
      "image/jpeg",
    ),
  );
  await assertFails(
    upload(
      environment.authenticatedContext("other").storage()
        .ref("secret_chat_profiles/owner/avatar_456.jpg"),
      image,
      "image/jpeg",
    ),
  );
  await assertFails(
    upload(
      ownerStorage.ref("secret_chat_profiles/owner/avatar_456.gif"),
      image,
      "image/gif",
    ),
  );
  await assertFails(
    upload(
      ownerStorage.ref("secret_chat_profiles/owner/avatar_456.png"),
      new Uint8Array(5 * 1024 * 1024 + 1),
      "image/png",
    ),
  );
});

function upload(
  reference: unknown,
  bytes: Uint8Array,
  contentType: string,
): Promise<unknown> {
  const uploadReference = reference as {
    put: (
      data: Uint8Array,
      metadata: {contentType: string},
    ) => {then: (resolve: (value: unknown) => void, reject: (reason: unknown) => void) => unknown};
  };
  return new Promise((resolveUpload, rejectUpload) => {
    uploadReference.put(bytes, {contentType}).then(resolveUpload, rejectUpload);
  });
}

test("profile images are signed-in readable and owner deletable", async () => {
  const path = "secret_chat_profiles/owner/avatar_123.png";
  await environment.withSecurityRulesDisabled(async (context) => {
    await context.storage().ref(path)
      .put(new Uint8Array([1, 2, 3]), {contentType: "image/png"});
  });
  await assertSucceeds(
    environment.authenticatedContext("other").storage().ref(path).getDownloadURL(),
  );
  await assertFails(environment.unauthenticatedContext().storage().ref(path).getDownloadURL());
  await assertFails(environment.authenticatedContext("other").storage().ref(path).delete());
  await assertSucceeds(environment.authenticatedContext("owner").storage().ref(path).delete());
});

test("Storage profile_images rules preserve owner-only upload/delete and signed-in read", async () => {
  const image = new Uint8Array([0xff, 0xd8, 0xff, 0xd9]);
  const ownerStorage = environment.authenticatedContext("owner").storage();
  const otherStorage = environment.authenticatedContext("other").storage();
  const path = "profile_images/owner/avatar.jpg";

  await assertSucceeds(upload(ownerStorage.ref(path), image, "image/jpeg"));
  await assertSucceeds(otherStorage.ref(path).getDownloadURL());
  await assertFails(environment.unauthenticatedContext().storage().ref(path).getDownloadURL());
  await assertFails(upload(otherStorage.ref("profile_images/owner/avatar.png"), image, "image/png"));
  await assertFails(upload(ownerStorage.ref("profile_images/owner/custom.jpg"), image, "image/jpeg"));
  await assertFails(upload(ownerStorage.ref("profile_images/owner/avatar.png"), new Uint8Array(5 * 1024 * 1024 + 1), "image/png"));
  await assertFails(otherStorage.ref(path).delete());
  await assertSucceeds(ownerStorage.ref(path).delete());
});
