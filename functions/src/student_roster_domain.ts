import {randomBytes, randomInt, scrypt, timingSafeEqual} from "node:crypto";
import {canonicalLoginId} from "./account_recovery";

// Pure roster domain logic: no Firestore access.

export type AcademicIndex = {
  colleges: {id: string; name: string; code: string}[];
  courses: {id: string; name: string; code: string; collegeId: string; departmentId: string; departmentName: string}[];
};
export type RosterRowInput = {studentNo?: unknown; surname?: unknown; firstName?: unknown; middleName?: unknown;
  dateOfBirth?: unknown; college?: unknown; course?: unknown; yearLevel?: unknown};
export type OfficialFields = {studentNo: string; studentKey: string; surname: string; firstName: string; middleName: string;
  dateOfBirthKey: string; collegeId: string; college: string; courseId: string; course: string;
  departmentId: string; department: string; yearLevel: string};
export type RowResult = {index: number; ok: true; value: OfficialFields} | {index: number; ok: false; errors: string[]};

const MAX_TEXT = 160;

export function normalizeName(value: string): string {
  return String(value ?? "")
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/[\s.\-']/g, "");
}

const YEAR_WORDS: Record<string, number> = {first: 1, second: 2, third: 3, fourth: 4, fifth: 5};
const YEAR_LABELS = ["", "1st Year", "2nd Year", "3rd Year", "4th Year", "5th Year"];

export function normalizeYearLevel(value: unknown): string | null {
  if (typeof value === "number") {
    return Number.isInteger(value) && value >= 1 && value <= 5 ? YEAR_LABELS[value] : null;
  }
  if (typeof value !== "string") return null;
  const text = value.trim().toLowerCase().replace(/\s+/g, " ");
  const word = /^(first|second|third|fourth|fifth)(?: year)?$/.exec(text);
  if (word) return YEAR_LABELS[YEAR_WORDS[word[1]]];
  const m = /^(?:year ?)?([1-5])(?:st|nd|rd|th)?(?: ?year)?$/.exec(text);
  return m ? YEAR_LABELS[Number(m[1])] : null;
}

export function parseDateKey(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!m) return null;
  const [year, month, day] = [Number(m[1]), Number(m[2]), Number(m[3])];
  if (year < 1900) return null;
  const date = new Date(Date.UTC(year, month - 1, day));
  if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month - 1 || date.getUTCDate() !== day) return null;
  if (value > new Date().toISOString().slice(0, 10)) return null;
  return value;
}

function cleanText(value: unknown): string {
  return typeof value === "string" ? value.trim().replace(/\s+/g, " ") : "";
}

export function validateRosterRows(rows: RosterRowInput[], index: AcademicIndex): RowResult[] {
  const results: RowResult[] = rows.map((row, i) => {
    const errors: string[] = [];
    const studentNo = cleanText(row.studentNo);
    let studentKey = "";
    try {
      studentKey = canonicalLoginId(studentNo);
    } catch {
      errors.push("Student No. is missing or invalid.");
    }
    const surname = cleanText(row.surname);
    const firstName = cleanText(row.firstName);
    const middleName = cleanText(row.middleName);
    if (!surname) errors.push("Surname is required.");
    if (!firstName) errors.push("First name is required.");
    for (const [label, v] of [["Surname", surname], ["First name", firstName], ["Middle name", middleName]] as const) {
      if (v.length > MAX_TEXT) errors.push(`${label} is too long.`);
    }
    const dateOfBirthKey = parseDateKey(row.dateOfBirth);
    if (!dateOfBirthKey) errors.push("Date of birth is missing or invalid.");
    const yearLevel = normalizeYearLevel(row.yearLevel);
    if (!yearLevel) errors.push("Year level must be 1 to 5.");

    const collegeText = normalizeName(cleanText(row.college));
    const college = collegeText ?
      index.colleges.find((c) => normalizeName(c.name) === collegeText || normalizeName(c.code) === collegeText) :
      undefined;
    if (!college) errors.push("College was not found.");
    const courseText = normalizeName(cleanText(row.course));
    const matches = courseText ?
      index.courses.filter((c) => normalizeName(c.name) === courseText || normalizeName(c.code) === courseText) :
      [];
    // Course names are unique per college, so one candidate is expected. Should bad data ever put two
    // in one college, the row is refused rather than filed under an arbitrary one of them.
    const inCollege = matches.filter((c) => c.collegeId === college?.id);
    let course = inCollege.length === 1 ? inCollege[0] : undefined;
    if (!matches.length) {
      errors.push("Course was not found.");
    } else if (college && inCollege.length > 1) {
      errors.push(`Course “${cleanText(row.course)}” matches more than one course in this college. ` +
        "Ask the registrar to merge the duplicates first.");
    } else if (college && !course) {
      errors.push("Course is not under the selected college.");
    } else if (!college) {
      course = undefined;
    }

    if (errors.length || !college || !course || !dateOfBirthKey || !yearLevel) {
      return {index: i, ok: false, errors};
    }
    return {index: i, ok: true, value: {
      studentNo, studentKey, surname, firstName, middleName, dateOfBirthKey,
      collegeId: college.id, college: college.name, courseId: course.id, course: course.name,
      departmentId: course.departmentId, department: course.departmentName, yearLevel,
    }};
  });

  const seen = new Map<string, number[]>();
  results.forEach((r, i) => {
    const key = r.ok ? r.value.studentKey : (() => {
      try {
        return canonicalLoginId(cleanText(rows[i].studentNo));
      } catch {
        return "";
      }
    })();
    if (!key) return;
    seen.set(key, [...(seen.get(key) ?? []), i]);
  });
  for (const indexes of seen.values()) {
    if (indexes.length < 2) continue;
    for (const i of indexes) {
      const r = results[i];
      results[i] = r.ok ?
        {index: i, ok: false, errors: ["Duplicate Student No. in file."]} :
        {index: i, ok: false, errors: [...r.errors, "Duplicate Student No. in file."]};
    }
  }
  return results;
}

// ---------------------------------------------------------------- personal info

export type Address = {number: string; street: string; barangay: string; cityTown: string; province: string; zipCode: string};
export type PersonalInfo = {sex: "Male" | "Female"; civilStatus: string; spouse: string; nationality: string; placeOfBirth: string;
  cityAddress: Address | null; homeAddress: Address; father: string; fatherOccupation: string; mother: string;
  motherOccupation: string; guardian: string; guardianRelationship: string; guardianAddress: string;
  telephone: string; cellphone: string};

const CIVIL_STATUSES = ["Single", "Married", "Widowed", "Separated"];

export function normalizeCellphone(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const digits = value.replace(/[\s-]/g, "");
  const m = /^(?:\+63|63|0)(9\d{9})$/.exec(digits);
  return m ? `0${m[1]}` : null;
}

export function validatePersonalInfo(input: unknown): {ok: true; value: PersonalInfo} | {ok: false; errors: Record<string, string>} {
  const errors: Record<string, string> = {};
  const src = (input && typeof input === "object" && !Array.isArray(input) ? input : {}) as Record<string, unknown>;

  const text = (key: string, required: boolean, label: string, obj: Record<string, unknown> = src, path = key): string => {
    const raw = obj[key];
    const v = typeof raw === "string" ? raw.trim() : "";
    if (v.length > MAX_TEXT) errors[path] = `${label} must be at most ${MAX_TEXT} characters.`;
    else if (required && !v) errors[path] = `${label} is required.`;
    return v;
  };

  const sex = src.sex === "Male" || src.sex === "Female" ? src.sex : null;
  if (!sex) errors.sex = "Select Male or Female.";
  const civilStatus = typeof src.civilStatus === "string" ? src.civilStatus.trim() : "";
  if (!CIVIL_STATUSES.includes(civilStatus)) errors.civilStatus = "Select a valid civil status.";
  const married = civilStatus === "Married";
  const spouseRaw = text("spouse", married, "Spouse");
  const spouse = married ? spouseRaw : "";
  const nationality = text("nationality", true, "Nationality");
  const placeOfBirth = text("placeOfBirth", true, "Place of birth");

  const readAddress = (key: string, label: string, optional: boolean): Address | null => {
    const raw = (src[key] && typeof src[key] === "object" ? src[key] : {}) as Record<string, unknown>;
    const fields = ["number", "street", "barangay", "cityTown", "province", "zipCode"] as const;
    const out = {} as Address;
    for (const f of fields) out[f] = typeof raw[f] === "string" ? (raw[f] as string).trim() : "";
    if (optional && fields.every((f) => !out[f])) return null;
    const required: Record<string, string> = {barangay: "Barangay", cityTown: "City / Town", province: "Province"};
    for (const f of fields) {
      const path = `${key}.${f}`;
      if (out[f].length > MAX_TEXT) errors[path] = `${label} ${f} must be at most ${MAX_TEXT} characters.`;
      else if (required[f] && !out[f]) errors[path] = `${required[f]} is required.`;
    }
    if (out.zipCode && !/^\d{4}$/.test(out.zipCode)) errors[`${key}.zipCode`] = "Zip code must be 4 digits.";
    return out;
  };
  const cityAddress = readAddress("cityAddress", "City address", true);
  const homeAddress = readAddress("homeAddress", "Home address", false) as Address;

  const father = text("father", false, "Father");
  const fatherOccupation = text("fatherOccupation", false, "Father's occupation");
  const mother = text("mother", false, "Mother");
  const motherOccupation = text("motherOccupation", false, "Mother's occupation");
  const guardian = text("guardian", true, "Guardian");
  const guardianRelationship = text("guardianRelationship", true, "Guardian relationship");
  const guardianAddress = text("guardianAddress", true, "Guardian address");
  const telephone = text("telephone", false, "Telephone");

  const cellRaw = typeof src.cellphone === "string" ? src.cellphone.trim() : "";
  let cellphone = "";
  if (!cellRaw) errors.cellphone = "Cellphone is required.";
  else {
    const n = normalizeCellphone(cellRaw);
    if (!n) errors.cellphone = "Enter a valid Philippine mobile number.";
    else cellphone = n;
  }

  if (Object.keys(errors).length) return {ok: false, errors};
  return {ok: true, value: {
    sex: sex as "Male" | "Female", civilStatus, spouse, nationality, placeOfBirth, cityAddress, homeAddress,
    father, fatherOccupation, mother, motherOccupation, guardian, guardianRelationship, guardianAddress,
    telephone, cellphone,
  }};
}

export const CORRECTABLE_FIELDS = ["surname", "firstName", "middleName", "dateOfBirth", "college", "course", "yearLevel"] as const;
export const PRIVACY_POLICY_VERSION = "2026-11-ra10173-v1";

// ---------------------------------------------------------------- activation codes

export const ACTIVATION_CODE_TTL_DAYS = 60;
export type StoredActivationCode = {hash: string; salt: string; issuedAt: Date; expiresAt: Date};

const CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
const CODE_LENGTH = 10;
const SCRYPT_PARAMS = {N: 16384, r: 8, p: 1};
const KEY_LENGTH = 32;

export function generateActivationCode(): string {
  let code = "";
  for (let i = 0; i < CODE_LENGTH; i++) code += CODE_ALPHABET[randomInt(CODE_ALPHABET.length)];
  return `${code.slice(0, 5)}-${code.slice(5)}`;
}

export function normalizeActivationCode(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const code = value.toUpperCase().replace(/[\s-]/g, "");
  if (code.length !== CODE_LENGTH) return null;
  for (const ch of code) if (!CODE_ALPHABET.includes(ch)) return null;
  return code;
}

function deriveKey(code: string, salt: Buffer): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    scrypt(code, salt, KEY_LENGTH, SCRYPT_PARAMS, (err, key) => (err ? reject(err) : resolve(key)));
  });
}

export async function hashActivationCode(code: string, now: Date = new Date()): Promise<StoredActivationCode> {
  const normalized = normalizeActivationCode(code);
  if (!normalized) throw new Error("Invalid activation code.");
  const salt = randomBytes(16);
  const hash = await deriveKey(normalized, salt);
  return {
    hash: hash.toString("base64"),
    salt: salt.toString("base64"),
    issuedAt: new Date(now.getTime()),
    expiresAt: new Date(now.getTime() + ACTIVATION_CODE_TTL_DAYS * 24 * 60 * 60 * 1000),
  };
}

export async function verifyActivationCode(input: unknown, stored: StoredActivationCode | null | undefined): Promise<boolean> {
  const normalized = normalizeActivationCode(input);
  if (!normalized || !stored || typeof stored.hash !== "string" || typeof stored.salt !== "string") return false;
  const expected = Buffer.from(stored.hash, "base64");
  if (expected.length !== KEY_LENGTH) return false;
  const actual = await deriveKey(normalized, Buffer.from(stored.salt, "base64"));
  return timingSafeEqual(actual, expected);
}
