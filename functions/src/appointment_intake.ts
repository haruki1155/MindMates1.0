import {HttpsError} from "firebase-functions/v2/https";

export function boundedText(value: unknown, label: string, max: number, {required = false}: {required?: boolean} = {}): string {
  if (typeof value !== "string") {
    if (required) throw new HttpsError("invalid-argument", `${label} is required.`);
    return "";
  }
  const text = value.trim();
  if (required && !text) throw new HttpsError("invalid-argument", `${label} is required.`);
  if (text.length > max) throw new HttpsError("invalid-argument", `${label} is too long.`);
  return text;
}

export function appointmentEmail(value: unknown): string {
  const email = boundedText(value, "Email", 254);
  if (email && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
    throw new HttpsError("invalid-argument", "Enter a valid email address.");
  }
  return email;
}

export function appointmentPhone(value: unknown): string {
  const phone = boundedText(value, "Contact number", 32);
  if (phone && !/^[+()\-\s0-9]{7,32}$/.test(phone)) {
    throw new HttpsError("invalid-argument", "Enter a valid contact number.");
  }
  return phone;
}
