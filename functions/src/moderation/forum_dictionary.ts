/**
 * Server-only restricted-language dictionary for the Forum. Never ship this to
 * the app. Bump FORUM_DICTIONARY_VERSION on every change and add a case to
 * forum_moderation_cases.json for each new entry.
 *
 * Mental-health words (suicide, self-harm, abuse, trauma, depression...) must
 * never be entries: they are disclosures, handled by the crisis path.
 */

export const FORUM_DICTIONARY_VERSION = "2026-11-26.1";

export type ModerationCategory =
  | "profanity" | "vulgar" | "sexual" | "discriminatory" | "harassment";
export type ModerationSeverity = "low" | "high";
export type ModerationLanguage = "en" | "tl" | "taglish";

export interface TermEntry {
  /** Spellings of one word; Filipino entries list stem changes (gago, gagu). */
  stems: string[];
  language: ModerationLanguage;
  category: ModerationCategory;
  severity: ModerationSeverity;
  /** Also match Filipino prefixes and suffixes (kagaguhan, putanginamo). */
  affixes?: boolean;
  /** Next words that make this an innocent phrase ("leche flan"). */
  exceptNext?: string[];
}

export interface PhraseEntry {
  words: string[];
  language: ModerationLanguage;
  category: ModerationCategory;
  severity: ModerationSeverity;
}

export const FILIPINO_PREFIXES = ["", "ka", "pinaka", "naka", "nakaka", "mag", "pag", "i"];
export const FILIPINO_SUFFIXES = ["", "mo", "ka", "ng", "han", "an", "in", "ito", "yan", "nyo"];

const en = (category: ModerationCategory, severity: ModerationSeverity, ...stems: string[]): TermEntry =>
  ({stems, language: "en", category, severity});
const tl = (category: ModerationCategory, severity: ModerationSeverity, ...stems: string[]): TermEntry =>
  ({stems, language: "tl", category, severity, affixes: true});

export const TERM_ENTRIES: TermEntry[] = [
  // English profanity and abbreviations.
  en("profanity", "high", "fuck", "fucking", "fucker", "fucked", "fucks", "fck", "fk", "fuk", "fking",
    "fcking", "fukin", "fuking", "motherfucker", "motherfucking", "mofo", "fml", "fuq"),
  en("profanity", "high", "shit", "shitty", "shits", "bullshit", "sht", "shithead", "shite"),
  en("profanity", "high", "bitch", "bitches", "bitchy", "btch", "biatch"),
  en("profanity", "high", "asshole", "assholes", "asshat", "jackass", "dumbass", "arse", "arsehole"),
  en("profanity", "high", "bastard", "bastards", "prick", "twat", "wanker", "douche", "douchebag"),
  en("profanity", "low", "damn", "goddamn", "dammit", "crap", "crappy"),
  en("profanity", "high", "stfu", "wtf", "gtfo", "omfg", "lmfao"),
  // English vulgar and sexual.
  en("vulgar", "high", "dick", "dickhead", "cock", "cunt", "pussy", "tits", "titties", "boner"),
  en("sexual", "high", "whore", "slut", "slutty", "hoe", "jizz", "blowjob", "handjob",
    "dildo", "horny", "porn", "porno", "nudes"),
  // Discriminatory slurs.
  en("discriminatory", "high", "retard", "retarded", "faggot", "fag", "nigger", "nigga", "tranny",
    "spastic", "chink", "gook", "dyke", "mongoloid"),
  // Harassment abbreviations ("kms" is a crisis disclosure, not here).
  en("harassment", "high", "kys"),
  {stems: ["cum"], language: "en", category: "sexual", severity: "high", exceptNext: ["laude"]},
  // Filipino profanity (with affix variants).
  tl("profanity", "high", "putangina", "putanginamo", "potangina", "putanginang", "tangina",
    "tanginamo", "tngina", "ptngina", "tangna", "pota", "puta", "putragis", "pucha", "punyeta",
    "pakshet", "pakingshet", "pakyu", "pakyo", "lintik", "hinayupak",
    "tarantado", "tarantada"),
  tl("profanity", "high", "gago", "gagu", "gaga", "ulol", "ulul", "olol", "kupal", "ungas",
    "inutil", "engot", "siraulo"),
  tl("harassment", "high", "tanga", "tangatanga", "bobo", "boba", "bubu"),
  {stems: ["leche", "letse"], language: "tl", category: "profanity", severity: "low",
    affixes: true, exceptNext: ["flan", "plan"]},
  // Filipino vulgar and sexual.
  tl("vulgar", "high", "puke", "pekpek", "titi", "tite", "burat", "bayag", "jakol", "kantot",
    "kantut", "chupa", "tamod"),
  tl("sexual", "high", "pokpok", "malandi"),
  // Filipino discriminatory.
  tl("discriminatory", "high", "abnoy", "mongoloyd"),
];

export const PHRASE_ENTRIES: PhraseEntry[] = [
  {words: ["putang", "ina"], language: "tl", category: "profanity", severity: "high"},
  {words: ["puta", "ng", "ina"], language: "tl", category: "profanity", severity: "high"},
  {words: ["tang", "ina"], language: "tl", category: "profanity", severity: "high"},
  {words: ["anak", "ng", "puta"], language: "tl", category: "profanity", severity: "high"},
  {words: ["hayop", "ka"], language: "tl", category: "harassment", severity: "high"},
  {words: ["animal", "ka"], language: "taglish", category: "harassment", severity: "high"},
  {words: ["mamatay", "ka", "na"], language: "tl", category: "harassment", severity: "high"},
  {words: ["magpakamatay", "ka"], language: "tl", category: "harassment", severity: "high"},
  {words: ["patayin", "kita"], language: "tl", category: "harassment", severity: "high"},
  {words: ["kill", "yourself"], language: "en", category: "harassment", severity: "high"},
  {words: ["kill", "urself"], language: "en", category: "harassment", severity: "high"},
  {words: ["go", "die"], language: "en", category: "harassment", severity: "high"},
  {words: ["you", "should", "die"], language: "en", category: "harassment", severity: "high"},
  {words: ["son", "of", "a", "bitch"], language: "en", category: "profanity", severity: "high"},
  {words: ["piece", "of", "shit"], language: "en", category: "profanity", severity: "high"},
  {words: ["shut", "the", "fuck", "up"], language: "en", category: "profanity", severity: "high"},
  {words: ["go", "to", "hell"], language: "en", category: "profanity", severity: "low"},
  {words: ["kalapating", "mababa", "ang", "lipad"], language: "tl", category: "sexual", severity: "high"},
];
