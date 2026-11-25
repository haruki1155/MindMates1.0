/**
 * Server-only restricted-language dictionary for the Forum. Never ship this to
 * the app. Bump FORUM_DICTIONARY_VERSION on every change and add a case to
 * forum_moderation_cases.json for each new entry.
 *
 * Mental-health words (suicide, self-harm, abuse, trauma, depression...) must
 * never be entries: they are disclosures, handled by the crisis path.
 */

export const FORUM_DICTIONARY_VERSION = "2026-11-27.1";

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
  /** Also match affix forms: Filipino (kagaguhan) or English (fuckers). */
  affixes?: "tl" | "en";
  /**
   * An insult the speaker may use about themselves ("ang tanga ko", "I feel
   * stupid"): allowed only when a self-reference is nearby and nobody else is.
   */
  selfAllowed?: boolean;
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
export const FILIPINO_SUFFIXES = ["", "mo", "ka", "ng", "han", "an", "in", "ito", "yan", "nyo", "ako", "kayo"];
export const ENGLISH_SUFFIXES = ["", "s", "es", "er", "ers", "in", "ing", "ed", "y"];
/** Self-description, not an insult: "tanga ko", "inutil ako", "nakakatanga". */
export const SELF_REFERENCE_WORDS = [
  "i", "im", "ive", "id", "me", "my", "myself", "mine", "ako", "ko", "kong", "akin", "sarili", "akong",
];
/** Words that aim a remark at someone else; they override a self-reference. */
export const ADDRESSEE_WORDS = [
  "you", "u", "ur", "your", "youre", "yourself", "ya", "ka", "mo", "kayo", "nyo", "niyo", "kang",
  "ikaw", "nila", "siya", "sya", "sila", "he", "she", "they", "him", "her", "them",
];
/** How many words either side count as "nearby". */
export const SELF_REFERENCE_WINDOW = 5;
export const SELF_REFERENCE_PREFIXES = ["nakaka"];

const en = (category: ModerationCategory, severity: ModerationSeverity, ...stems: string[]): TermEntry =>
  ({stems, language: "en", category, severity, affixes: "en"});
const tl = (category: ModerationCategory, severity: ModerationSeverity, ...stems: string[]): TermEntry =>
  ({stems, language: "tl", category, severity, affixes: "tl"});

export const TERM_ENTRIES: TermEntry[] = [
  // English profanity and abbreviations.
  en("profanity", "high", "fuck", "fucking", "fucker", "fucked", "fucks", "fck", "fk", "fuk", "fking",
    "fcking", "fukin", "fuking", "motherfucker", "motherfucking", "mofo", "fml", "fuq", "fvck", "phuck",
    "phuk", "fuckyou", "fuckoff", "fuckface"),
  en("profanity", "high", "shit", "shitty", "shits", "bullshit", "sht", "shithead", "shite"),
  en("profanity", "high", "bitch", "bitches", "bitchy", "btch", "biatch", "bitchass"),
  en("profanity", "high", "asshole", "assholes", "asshat", "jackass", "dumbass", "arse", "arsehole"),
  en("profanity", "high", "bastard", "bastards", "prick", "twat", "wanker", "douche", "douchebag"),
  en("profanity", "low", "damn", "goddamn", "dammit", "crap", "crappy"),
  en("profanity", "high", "stfu", "wtf", "gtfo", "omfg", "lmfao"),
  // English vulgar and sexual.
  en("vulgar", "high", "dick", "dickhead", "cock", "cunt", "pussy", "tits", "titties", "boner"),
  en("sexual", "high", "whore", "slut", "slutty", "jizz", "blowjob", "handjob",
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
  tl("profanity", "high", "gago", "gagu", "ulol", "ulul", "olol", "kupal", "ungas", "siraulo"),
  {...tl("harassment", "high", "tangatanga", "bubu"), selfAllowed: true},
  {stems: ["leche", "letse"], language: "tl", category: "profanity", severity: "low",
    affixes: "tl", exceptNext: ["flan", "plan"]},
  // Filipino vulgar and sexual.
  tl("vulgar", "high", "pekpek", "titi", "tite", "burat", "bayag", "jakol", "kantot",
    "kantut", "chupa", "tamod"),
  tl("sexual", "high", "pokpok", "malandi"),
  // Filipino discriminatory.
  tl("discriminatory", "high", "abnoy", "mongoloyd"),
  // More slurs (always blocked).
  en("discriminatory", "high", "coon", "spic", "kike", "wetback", "raghead", "towelhead", "beaner",
    "shemale", "trannies", "lesbo", "cripple", "midget", "schizo"),
  // Insults: blocked unless the speaker clearly means themselves.
  {stems: ["stupid", "idiot", "idiots", "moron", "morons", "dumb", "dumbo", "loser", "losers", "ugly",
    "pathetic", "worthless", "useless", "disgusting", "trash", "garbage", "freak", "freaks", "weirdo",
    "jerk", "jerks", "clown", "psycho", "lunatic"],
  language: "en", category: "harassment", severity: "high", selfAllowed: true},
  {...tl("harassment", "high", "pangit", "epal", "gunggong", "timang", "ugok", "tangek", "tanga",
    "shunga", "tange", "bopols", "buang", "salot", "engot", "inutil", "bobo"), selfAllowed: true},
  // Visayan curses.
  tl("profanity", "high", "yawa", "piste", "pisti", "pastilan"),
  // Filipino sexual and vulgar.
  tl("vulgar", "high", "kepyas", "hindot", "jutay", "iyot", "tsupa", "salsal", "libog", "malibog"),
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
  {words: ["kill", "your", "self"], language: "en", category: "harassment", severity: "high"},
  {words: ["unalive", "yourself"], language: "en", category: "harassment", severity: "high"},
  {words: ["i", "will", "kill", "you"], language: "en", category: "harassment", severity: "high"},
  {words: ["ill", "kill", "you"], language: "en", category: "harassment", severity: "high"},
  {words: ["gonna", "kill", "you"], language: "en", category: "harassment", severity: "high"},
  {words: ["kiss", "my", "ass"], language: "en", category: "profanity", severity: "high"},
  {words: ["mamatay", "ka"], language: "tl", category: "harassment", severity: "high"},
  {words: ["patayin", "mo", "sarili", "mo"], language: "tl", category: "harassment", severity: "high"},
  {words: ["magbigti", "ka"], language: "tl", category: "harassment", severity: "high"},
  {words: ["papatayin", "kita"], language: "tl", category: "harassment", severity: "high"},
  {words: ["kill", "urself"], language: "en", category: "harassment", severity: "high"},
  {words: ["go", "die"], language: "en", category: "harassment", severity: "high"},
  {words: ["you", "should", "die"], language: "en", category: "harassment", severity: "high"},
  {words: ["son", "of", "a", "bitch"], language: "en", category: "profanity", severity: "high"},
  {words: ["piece", "of", "shit"], language: "en", category: "profanity", severity: "high"},
  {words: ["shut", "the", "fuck", "up"], language: "en", category: "profanity", severity: "high"},
  {words: ["go", "to", "hell"], language: "en", category: "profanity", severity: "low"},
  {words: ["kalapating", "mababa", "ang", "lipad"], language: "tl", category: "sexual", severity: "high"},
  {words: ["shut", "up"], language: "en", category: "harassment", severity: "high"},
  {words: ["i", "hate", "you"], language: "en", category: "harassment", severity: "high"},
  {words: ["nobody", "likes", "you"], language: "en", category: "harassment", severity: "high"},
  {words: ["no", "one", "likes", "you"], language: "en", category: "harassment", severity: "high"},
  {words: ["you", "suck"], language: "en", category: "harassment", severity: "high"},
  {words: ["go", "away"], language: "en", category: "harassment", severity: "high"},
  {words: ["fat", "pig"], language: "en", category: "harassment", severity: "high"},
  {words: ["baboy", "ka"], language: "tl", category: "harassment", severity: "high"},
  {words: ["walang", "kwenta", "ka"], language: "tl", category: "harassment", severity: "high"},
  {words: ["wala", "kang", "kwenta"], language: "tl", category: "harassment", severity: "high"},
  {words: ["demonyo", "ka"], language: "tl", category: "harassment", severity: "high"},
  {words: ["unggoy", "ka"], language: "tl", category: "harassment", severity: "high"},
  {words: ["itlog", "mo"], language: "tl", category: "vulgar", severity: "high"},
  {words: ["bakla", "ka"], language: "tl", category: "discriminatory", severity: "high"},
  {words: ["bading", "ka"], language: "tl", category: "discriminatory", severity: "high"},
  {words: ["tomboy", "ka"], language: "tl", category: "discriminatory", severity: "high"},
];
