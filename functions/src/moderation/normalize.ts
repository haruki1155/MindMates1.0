/**
 * Turns user text into comparable token lists for moderation. Every step is a
 * bounded linear pass; nothing here builds a regular expression from input.
 */

/** Longest text the engine reads; callers enforce far smaller limits. */
export const MAX_MODERATED_LENGTH = 20_000;

// Zero-width, joiners, bidi controls, soft hyphen, variation selectors, fillers.
const INVISIBLE =
  /[­͏؜ᅟᅠ឴឵᠋-᠏​-‏‪-‮⁠-⁯ㅤ︀-️﻿ﾠ]/g;
const COMBINING_MARKS = /\p{M}/gu;

/** Letters from other scripts, small capitals and slashed letters that read as Latin. */
const CONFUSABLES: Record<string, string> = {
  "а": "a", "е": "e", "о": "o", "р": "p", "с": "c",
  "у": "y", "х": "x", "і": "i", "ј": "j", "ѕ": "s",
  "һ": "h", "ԁ": "d", "ԛ": "q", "ԝ": "w", "ɡ": "g",
  "ı": "i", "ӏ": "l", "α": "a", "ο": "o", "ν": "v",
  "ρ": "p", "τ": "t", "κ": "k", "ι": "i", "υ": "u",
  "ε": "e", "ς": "s", "в": "b", "к": "k", "м": "m",
  "н": "h", "т": "t",
  // Small capitals.
  "ᴀ": "a", "ʙ": "b", "ᴄ": "c", "ᴅ": "d", "ᴇ": "e",
  "ғ": "f", "ɢ": "g", "ʜ": "h", "ɪ": "i", "ᴊ": "j",
  "ᴋ": "k", "ʟ": "l", "ᴍ": "m", "ɴ": "n", "ᴏ": "o",
  "ᴘ": "p", "ʀ": "r", "ꜱ": "s", "ᴛ": "t", "ᴜ": "u",
  "ᴠ": "v", "ᴡ": "w", "ʏ": "y", "ᴢ": "z",
  // Letters that do not decompose to a base letter.
  "ƒ": "f", "ø": "o", "ł": "l", "đ": "d", "ħ": "h",
  "ð": "d", "ŧ": "t", "ß": "s", "ƀ": "b", "ɨ": "i",
};

/** Digits and symbols commonly used in place of letters. */
const LEET: Record<string, string> = {
  "0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "8": "b",
  "9": "g", "@": "a", "$": "s", "!": "i", "|": "l", "+": "t", "€": "e",
};

/** Short everyday words that must not be glued into a match ("go ok", "put ang"). */
const JOIN_STOPWORDS = new Set([
  "a", "i", "an", "as", "at", "ay", "be", "by", "do", "go", "he", "hi", "if", "in", "is", "it",
  "me", "my", "no", "of", "oh", "ok", "on", "or", "so", "to", "up", "us", "we", "ya", "am",
  "the", "and", "for", "are", "was", "you", "yes", "not", "but", "can", "get", "got", "has",
  "had", "her", "him", "his", "how", "its", "let", "may", "our", "out", "see", "she", "too",
  "put", "all", "any", "new", "now", "old", "one", "own", "say", "try", "who", "why", "did",
  "ako", "ang", "ka", "ko", "mo", "na", "ng", "sa", "si", "ni", "yan", "ito", "kay", "mga",
  "pa", "po", "din", "rin", "lang", "daw", "nga", "ba", "nang", "pag", "may", "wag", "di",
]);

export interface NormalizedText {
  /** One primary spelling per whitespace token (edge symbols trimmed). */
  spaced: string[];
  /** Every candidate spelling per whitespace token, aligned with [spaced]. */
  forms: string[][];
  /** Tokens split on anything that is not a letter or letter substitute. */
  split: string[];
  /** Joined forms: spaced-out letters and short fragments written apart. */
  joined: string[];
}

function confusable(char: string): string {
  return CONFUSABLES[char] ?? char;
}

function isLetter(char: string): boolean {
  return char >= "a" && char <= "z";
}

/** Collapses repeated letters ("fuuuck" to "fuck"); linear, no backtracking. */
export function collapseRepeats(token: string): string {
  let out = "";
  for (const char of token) {
    if (out[out.length - 1] !== char) out += char;
  }
  return out;
}

function lettersOnly(chars: string[]): string {
  let out = "";
  for (const char of chars) {
    const mapped = LEET[char] ?? char;
    if (isLetter(mapped)) out += mapped;
  }
  return collapseRepeats(out);
}

/** Drops leading and trailing non-letters, so "gago!" and "gago1" read as "gago". */
function trimEdges(chars: string[]): string[] {
  let start = 0;
  let end = chars.length;
  while (start < end && !isLetter(chars[start])) start++;
  while (end > start && !isLetter(chars[end - 1])) end--;
  return chars.slice(start, end);
}

/** Candidate spellings of one whitespace token. */
function tokenForms(raw: string): string[] {
  const chars = [...raw].map(confusable);
  const forms = new Set<string>();
  const trimmed = trimEdges(chars);
  forms.add(lettersOnly(trimmed));
  forms.add(lettersOnly(chars));
  // "p*ta", "g*go": an asterisk standing for a vowel (bounded to two).
  const stars = trimmed.filter((char) => char === "*").length;
  if (stars > 0 && stars <= 2) {
    let variants = [trimmed];
    for (let i = 0; i < stars; i++) {
      variants = variants.flatMap((variant) => {
        const at = variant.indexOf("*");
        return ["a", "e", "i", "o", "u"].map((vowel) =>
          [...variant.slice(0, at), vowel, ...variant.slice(at + 1)]);
      });
    }
    for (const variant of variants) forms.add(lettersOnly(variant));
  }
  forms.delete("");
  return [...forms];
}

/** Lower-cased, NFKC, invisible characters and accents removed. */
export function canonicalText(text: string): string {
  return text
    .slice(0, MAX_MODERATED_LENGTH)
    .normalize("NFKC")
    .replace(INVISIBLE, "")
    .toLowerCase()
    .normalize("NFD")
    .replace(COMBINING_MARKS, "")
    .normalize("NFC");
}

/** Canonical text with look-alikes and leetspeak mapped, spacing kept ("k1ll" to "kill"). */
export function lettersText(text: string): string {
  let out = "";
  for (const char of canonicalText(text)) {
    const mapped = LEET[confusable(char)] ?? confusable(char);
    out += mapped;
  }
  return out;
}

export function normalizeForModeration(text: string): NormalizedText {
  const canonical = canonicalText(text);
  const raw = canonical.split(/\s+/).filter((token) => token.length > 0);
  const forms: string[][] = [];
  const spaced: string[] = [];
  const split: string[] = [];
  for (const token of raw) {
    const candidates = tokenForms(token);
    if (candidates.length === 0) continue;
    forms.push(candidates);
    spaced.push(candidates[0]);
    // Words glued by punctuation ("hello,gago") split apart; symbols inside a
    // word that stand for letters stay part of it.
    let current: string[] = [];
    for (const char of trimEdges([...token].map(confusable))) {
      if (isLetter(char) || LEET[char] !== undefined || char === "*") {
        current.push(char);
      } else if (current.length) {
        split.push(lettersOnly(current));
        current = [];
      }
    }
    if (current.length) split.push(lettersOnly(current));
  }

  const joined: string[] = [];
  // "p u t a n g i n a": runs of three or more single letters.
  let run = "";
  let runLength = 0;
  const flushRun = () => {
    if (runLength >= 3) joined.push(collapseRepeats(run));
    run = "";
    runLength = 0;
  };
  for (const token of spaced) {
    if (token.length === 1) {
      run += token;
      runLength += 1;
    } else {
      flushRun();
    }
  }
  flushRun();
  // "fu ck", "f uc k", "putan gina": two to four short fragments.
  for (let i = 0; i < spaced.length; i++) {
    let glued = "";
    for (let size = 1; size <= 4 && i + size <= spaced.length; size++) {
      const part = spaced[i + size - 1];
      if (part.length > 5 || (part.length > 1 && JOIN_STOPWORDS.has(part))) break;
      glued += part;
      if (size >= 2 && glued.length <= 12) joined.push(collapseRepeats(glued));
    }
  }
  return {spaced, forms, split: split.filter((token) => token.length > 0), joined};
}
