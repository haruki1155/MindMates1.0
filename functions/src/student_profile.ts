import {FieldValue, Timestamp} from "firebase-admin/firestore";

import {defaultActivityFields} from "./account_integrity";

/**
 * The profile created for a roster student, copied from the official roster row. Shared by code activation and
 * no-code account setup so both always produce the same record. `email` is the student's real contact email (the
 * Firebase Auth email is an internal alias and is never stored here).
 */
export function rosterStudentProfile(
  live: FirebaseFirestore.DocumentData,
  args: {uid: string; email: string; studentNo: string; emailVerified: boolean; claimMethod?: string},
): Record<string, unknown> {
  return {
    id: args.uid, email: args.email, emailVerified: args.emailVerified, studentIdLogin: true, schoolId: args.studentNo,
    firstName: String(live.firstName ?? ""), middleName: String(live.middleName ?? ""), lastName: String(live.surname ?? ""),
    name: [live.firstName, live.middleName, live.surname].map((v) => String(v ?? "")).filter(Boolean).join(" "),
    populationRole: "student", declaredRole: "student", role: "student",
    collegeId: String(live.collegeId ?? ""), college: String(live.college ?? ""),
    courseId: String(live.courseId ?? ""), course: String(live.course ?? ""),
    departmentId: String(live.departmentId ?? ""), department: String(live.department ?? ""),
    yearLevel: String(live.yearLevel ?? ""),
    dateOfBirth: live.dateOfBirth ?? Timestamp.fromDate(new Date(`${live.dateOfBirthKey}T00:00:00Z`)),
    dateOfBirthKey: String(live.dateOfBirthKey ?? ""),
    gender: "", sector: "", position: "", employeeId: "",
    accessRole: "appUser", verificationStatus: "verified", profileVersion: 3,
    verifiedAt: FieldValue.serverTimestamp(), verifiedBy: "roster-activation",
    ...(args.claimMethod ? {claimMethod: args.claimMethod} : {}),
    personalInfoRequired: true, rosterLinked: true,
    ...defaultActivityFields(),
  };
}
