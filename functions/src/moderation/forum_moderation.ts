import {
  ENGLISH_SUFFIXES,
  FILIPINO_PREFIXES,
  FILIPINO_SUFFIXES,
  FORUM_DICTIONARY_VERSION,
  ModerationCategory,
  ModerationSeverity,
  PHRASE_ENTRIES,
  PhraseEntry,
  SELF_REFERENCE_NEXT,
  SELF_REFERENCE_PREFIXES,
  TERM_ENTRIES,
  TermEntry,
} from "./forum_dictionary";
import {canonicalText, collapseRepeats, lettersText, normalizeForModeration} from "./normalize";

export {FORUM_DICTIONARY_VERSION};

export interface ForumModerationResult {
  allowed: boolean;
  categories: ModerationCategory[];
  severity: "none" | ModerationSeverity;
}

interface IndexedTerm {
  entry: TermEntry;
  prefix: string;
}

function buildTermIndex(): Map<string, IndexedTerm> {
  const index = new Map<string, IndexedTerm>();
  const add = (variant: string, entry: TermEntry, prefix: string) => {
    if (!index.has(variant)) index.set(variant, {entry, prefix});
  };
  for (const entry of TERM_ENTRIES) {
    const prefixes = entry.affixes === "tl" ? FILIPINO_PREFIXES : [""];
    const suffixes = entry.affixes === "tl" ? FILIPINO_SUFFIXES :
      entry.affixes === "en" ? ENGLISH_SUFFIXES : [""];
    for (const stem of entry.stems) {
      add(collapseRepeats(stem), entry, "");
      for (const prefix of prefixes) {
        for (const suffix of suffixes) {
          const variant = collapseRepeats(`${prefix}${stem}${suffix}`);
          // "tanga" + "an" collapses to "tangan" (holding): skip boundary merges.
          const separate = collapseRepeats(prefix) + collapseRepeats(stem) + collapseRepeats(suffix);
          if (variant === separate) add(variant, entry, prefix);
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

/** True when this match is innocent in context ("leche flan", "ang tanga ko"). */
function excused(match: IndexedTerm, next: string): boolean {
  if (match.entry.exceptNext?.includes(next)) return true;
  return Boolean(match.entry.selfAllowed) &&
    (SELF_REFERENCE_NEXT.includes(next) || SELF_REFERENCE_PREFIXES.includes(match.prefix));
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

  const check = (candidates: string[], next: string) => {
    for (const candidate of candidates) {
      const match = TERMS.get(candidate);
      if (match && !excused(match, next)) record(match.entry.category, match.entry.severity);
    }
  };
  const {spaced, forms, split, joined} = normalized;
  for (let i = 0; i < spaced.length; i++) {
    check(forms[i], spaced[i + 1] ?? "");
    for (const phrase of PHRASES_BY_FIRST.get(spaced[i]) ?? []) {
      if (phrase.words.every((word, offset) => spaced[i + offset] === word)) {
        record(phrase.entry.category, phrase.entry.severity);
      }
    }
  }
  for (let i = 0; i < split.length; i++) check([split[i]], split[i + 1] ?? "");
  for (const token of joined) {
    const match = TERMS.get(token);
    if (match) record(match.entry.category, match.entry.severity);
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
  /\bwant\s+to\s+die\b/,
  /\b(?:do not|don't|dont|not)\s+want\s+to\s+live\b/,
  /\bkms\b/,
  /\bgusto\s+ko\s+(?:nang|na)\s+(?:lang\s+)?mamatay\b/,
  /\bgusto\s+kong\s+magpakamatay\b/,
  /\bmagpapakamatay\s+ako\b/,
  /\bayoko\s+(?:nang|na)\s+mabuhay\b/,
  /\bpatayin\s+ko\s+(?:ang\s+)?sarili\s+ko\b/,
];

/** True for language that needs the crisis redirect instead of a public post. */
export function isCrisisDisclosure(text: string): boolean {
  const variants = [canonicalText(text), lettersText(text)]
    .map((value) => value.replace(/\s+/g, " "));
  return variants.some((value) => CRISIS_PATTERNS.some((pattern) => pattern.test(value)));
}
