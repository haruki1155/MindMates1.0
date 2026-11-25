/**
 * Turns user text into comparable token lists for moderation. Every step is a
 * single linear pass; nothing here builds a regular expression from input.
 */

/** Longest text the engine reads; callers enforce far smaller limits. */
export const MAX_MODERATED_LENGTH = 20_000;

// Zero-width, joiners, bidi controls, soft hyphen, variation selectors, fillers.
const INVISIBLE =
  /[­͏؜ᅟᅠ឴឵᠋-᠏​-‏‪-‮⁠-⁯ㅤ︀-️﻿ﾠ]/g;
const COMBINING_MARKS = /\p{M}/gu;

/** Letters from other scripts that look like Latin ones. */
const CONFUSABLES: Record<string, string> = {
  "а": "a", "е": "e", "о": "o", "р": "p", "с": "c",
  "у": "y", "х": "x", "і": "i", "ј": "j", "ѕ": "s",
  "һ": "h", "ԁ": "d", "ԛ": "q", "ԝ": "w", "ɡ": "g",
  "ı": "i", "ӏ": "l", "α": "a", "ο": "o", "ν": "v",
  "ρ": "p", "τ": "t", "κ": "k", "ι": "i", "υ": "u",
  "ε": "e", "ς": "s", "в": "b", "к": "k", "м": "m",
  "н": "h", "т": "t",
};

/** Digits and symbols commonly used in place of letters. */
const LEET: Record<string, string> = {
  "0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "8": "b",
  "9": "g", "@": "a", "$": "s", "!": "i", "|": "l", "+": "t", "€": "e",
};

export interface NormalizedText {
  /** Tokens split on whitespace, symbols inside a token removed ("f.u.c.k"). */
  spaced: string[];
  /** Tokens split on anything that is not a letter or letter substitute. */
  split: string[];
  /** Extra joined forms: spaced-out letters and short adjacent pairs. */
  joined: string[];
}

function mapChar(char: string): string {
  return CONFUSABLES[char] ?? LEET[char] ?? char;
}

/** Collapses repeated letters ("fuuuck" to "fuck"); linear, no backtracking. */
export function collapseRepeats(token: string): string {
  let out = "";
  for (const char of token) {
    if (out[out.length - 1] !== char) out += char;
  }
  return out;
}

function lettersOnly(token: string): string {
  let out = "";
  for (const char of token) {
    const mapped = mapChar(char);
    if (mapped >= "a" && mapped <= "z") out += mapped;
  }
  return collapseRepeats(out);
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

export function normalizeForModeration(text: string): NormalizedText {
  const canonical = canonicalText(text);
  const rawTokens = canonical.split(/\s+/).filter((token) => token.length > 0);
  const spaced = rawTokens.map(lettersOnly).filter((token) => token.length > 0);

  const split: string[] = [];
  let current = "";
  for (const char of canonical) {
    const mapped = mapChar(char);
    if (mapped >= "a" && mapped <= "z") {
      current += mapped;
    } else if (current) {
      split.push(collapseRepeats(current));
      current = "";
    }
  }
  if (current) split.push(collapseRepeats(current));

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
  // "fu ck": two short neighbours written apart.
  for (let i = 0; i + 1 < spaced.length; i++) {
    const a = spaced[i];
    const b = spaced[i + 1];
    if (a.length >= 2 && a.length <= 4 && b.length >= 2 && b.length <= 4) {
      joined.push(collapseRepeats(a + b));
    }
  }
  return {spaced, split, joined};
}
