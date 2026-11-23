# Admin portal staging cutover

PR #77 changes clinical evidence, counselor read receipts, and Activity Logs.

1. Confirm the staging deployment project, the `mindmate-staging.firebasestorage.app` clinical bucket, and the verified `SUPER_ADMIN_UID`. Verify that the Functions runtime service account can create and read clinical objects and write Firestore audit records.
2. Inventory historical clinical object metadata under separate authorization. Revoke any legacy Firebase download tokens while preserving object paths and bytes. Existing bearer URLs survive a change to Storage rules.
3. Deploy the changed Functions first, including both clinical callables, `getAuditLogPage`, and the changed inquiry, reporting, organization, and emergency handlers. Apply Firestore rules before the web release so new counselor receipts can carry `readThrough`. Existing `counselor_inbox_reads` documents need no migration.
4. Coordinate release of the admin web bundle with the clinical Storage rules cutover. Older bundles use direct Storage and need a refresh. Verify both new callables are live before restricting direct clinical creates and reads.
5. With synthetic staging records, verify upload, appointment completion, byte-for-byte download, and the audit row. Check denial for ordinary Admin, portal staff, students, and out-of-scope counselors. Verify the global feed and legacy per-user audit history with the configured Super-Administrator.

The global Activity Logs query uses the existing descending `createdAt` index with document ID as a tie-breaker. Keep the existing per-user audit indexes.
