import {
  FILIPINO_PREFIXES,
  FILIPINO_SUFFIXES,
  FORUM_DICTIONARY_VERSION,
  ModerationCategory,
  ModerationSeverity,
  PHRASE_ENTRIES,
  PhraseEntry,
  TERM_ENTRIES,
  TermEntry,
} from "./forum_dictionary";
import {canonicalText, collapseRepeats, normalizeForModeration} from "./normalize";

export {FORUM_DICTIONARY_VERSION};

export interface ForumModerationResult {
  allowed: boolean;
  categories: ModerationCategory[];
  severity: "none" | ModerationSeverity;
}

function buildTermIndex(): Map<string, TermEntry> {
  const index = new Map<string, TermEntry>();
  for (const entry of TERM_ENTRIES) {
    for (const stem of entry.stems) {
      index.set(collapseRepeats(stem), entry);
      if (!entry.affixes) continue;
      for (const prefix of FILIPINO_PREFIXES) {
        for (const suffix of FILIPINO_SUFFIXES) {
          const variant = `${prefix}${stem}${suffix}`;
          // "tanga" + "an" collapses to "tangan" (holding): skip such merges.
          if (variant !== stem && collapseRepeats(variant) === variant && !index.has(variant)) {
            index.set(variant, entry);
          }
        }
      }
    }
  }
  return index;
}

const TERMS = buildTermIndex();
const PHRASES_BY_FIRST = new Map<string, {words: string[]; entry: PhraseEntry}[]>();
for (const entry of PHRASE_ENTRIES) {
  const words = entry.words.map(collapseRepeats);
  const list = PHRASES_BY_FIRST.get(words[0]) ?? [];
  list.push({words, entry});
  PHRASES_BY_FIRST.set(words[0], list);
}

/**
 * Decides whether Forum text may be published. Reports categories and a
 * severity only; never the matched words.
 */
export function moderateForumText(text: string): ForumModerationResult {
  const hits = new Map<ModerationCategory, ModerationSeverity>();
  const record = (category: ModerationCategory, severity: ModerationSeverity) => {
    if (hits.get(category) !== "high") hits.set(category, severity);
  };
  const normalized = normalizeForModeration(text);

  for (const tokens of [normalized.spaced, normalized.split]) {
    for (let i = 0; i < tokens.length; i++) {
      const entry = TERMS.get(tokens[i]);
      if (entry && !(entry.exceptNext?.includes(tokens[i + 1] ?? ""))) {
        record(entry.category, entry.severity);
      }
      for (const phrase of PHRASES_BY_FIRST.get(tokens[i]) ?? []) {
        if (phrase.words.every((word, offset) => tokens[i + offset] === word)) {
          record(phrase.entry.category, phrase.entry.severity);
        }
      }
    }
  }
  for (const token of normalized.joined) {
    const entry = TERMS.get(token);
    if (entry) record(entry.category, entry.severity);
  }

  const categories = [...hits.keys()].sort();
  const severity = categories.length === 0 ? "none" :
    [...hits.values()].includes("high") ? "high" : "low";
  return {allowed: categories.length === 0, categories, severity};
}

// First-person disclosures of crisis; matched on canonical text, all bounded.
const CRISIS_PATTERNS = [
  /\bkill\s+myself\b/,
  /\bend\s+my\s+life\b/,
  /\bsuicid(?:e|al)\b/,
  /\bself[ -]?harm\b/,
  /\bhurt\s+myself\b/,
  /\bcut(?:ting)?\s+myself\b/,
  /\b(?:do not|don't|dont|not)\s+want\s+to\s+live\b/,
  /\bkms\b/,
  /\bgusto\s+ko\s+(?:nang|na)\s+mamatay\b/,
  /\bgusto\s+kong\s+magpakamatay\b/,
  /\bmagpapakamatay\s+ako\b/,
  /\bayoko\s+(?:nang|na)\s+mabuhay\b/,
  /\bpatayin\s+ko\s+(?:ang\s+)?sarili\s+ko\b/,
];

/** True for language that needs the crisis redirect instead of a public post. */
export function isCrisisDisclosure(text: string): boolean {
  const canonical = canonicalText(text).replace(/\s+/g, " ");
  return CRISIS_PATTERNS.some((pattern) => pattern.test(canonical));
}
