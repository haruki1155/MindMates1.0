import {lookup} from "node:dns/promises";
import {isIP} from "node:net";
import * as http from "node:http";
import * as https from "node:https";
import ipaddr from "ipaddr.js";
import {Parser} from "htmlparser2";
import {HttpsError} from "firebase-functions/v2/https";
import {Firestore} from "firebase-admin/firestore";
import {announcementUrl, canManageAnnouncements} from "./announcements";

type Address = {address: string; family: number};
type Response = {status: number; type: string; body: Buffer; location?: string};
type Preview = {sourceUrl: string; title: string; description: string; imageUrl?: string; available: boolean};
type Dependencies = {resolve: (host: string) => Promise<Address[]>; request: (url: URL, address: Address, signal: AbortSignal) => Promise<Response>};
const MAX_BYTES = 512 * 1024;

export function isPublicAddress(address: string): boolean {
  try { return ipaddr.parse(address).range() === "unicast"; } catch { return false; }
}
function publicUrl(value: string): URL {
  const url = new URL(announcementUrl(value, true));
  const host = url.hostname.replace(/^\[|\]$/g, "").toLowerCase();
  if (url.port || host === "localhost" || /\.(localhost|local|internal)$/.test(host) || (isIP(host) && !isPublicAddress(host))) throw new Error("Unavailable destination");
  return url;
}
export function parseLinkMetadata(html: string, sourceUrl: string): Preview {
  const values: Record<string, string> = {};
  let inTitle = false;
  let title = "";
  const parser = new Parser({
    onopentag(name, attrs) {
      if (name === "title") inTitle = true;
      if (name === "meta") { const key = (attrs.property ?? attrs.name ?? "").toLowerCase(); if (!values[key]) values[key] = attrs.content ?? ""; }
    },
    ontext(text) { if (inTitle) title += text; },
    onclosetag(name) { if (name === "title") inTitle = false; },
  }, {decodeEntities: true});
  parser.end(html);
  const plain = (text: string, max: number) => text.replace(/<[^>]*>/g, "").replace(/\s+/g, " ").trim().slice(0, max);
  const result: Preview = {sourceUrl, title: plain(values["og:title"] || title, 160), description: plain(values["og:description"] || values.description || "", 10000), available: false};
  try { if (values["og:image"]) result.imageUrl = publicUrl(new URL(values["og:image"], sourceUrl).href).href; } catch { /* Image is optional. */ }
  result.available = Boolean(result.title || result.description || result.imageUrl);
  return result;
}

/** Original hostname controls Host and TLS/SNI; lookup returns only the previously validated address. */
export function requestPinned(url: URL, address: Address, signal: AbortSignal): Promise<Response> {
  return new Promise((resolve, reject) => {
    const transport = url.protocol === "https:" ? https : http;
    const req = transport.request(url, {
      method: "GET", agent: false, signal, family: address.family,
      lookup: (_hostname, options, callback) => {
        // Node may ask for an array when auto-selecting address families.
        if (options.all) callback(null, [address] as never);
        else callback(null, address.address, address.family);
      },
      headers: {"Accept": "text/html,application/xhtml+xml", "Accept-Encoding": "identity", "User-Agent": "MindMate-LinkPreview/1.0"},
    }, (res) => {
      const status = res.statusCode ?? 0;
      const type = String(res.headers["content-type"] ?? "");
      if ([301,302,303,307,308].includes(status) || !/^(text\/html|application\/xhtml\+xml)(;|$)/i.test(type) || Number(res.headers["content-length"] ?? 0) > MAX_BYTES) {
        resolve({status, type, location: res.headers.location, body: Buffer.alloc(0)}); res.destroy(); return;
      }
      const chunks: Buffer[] = []; let bytes = 0;
      res.on("data", (chunk: Buffer) => { bytes += chunk.length; if (bytes > MAX_BYTES) { res.destroy(new Error("Response too large")); req.destroy(); } else chunks.push(chunk); });
      res.on("error", reject);
      res.on("end", () => resolve({status, type, body: Buffer.concat(chunks)}));
    });
    req.on("error", reject); req.end();
  });
}
export async function getAnnouncementLinkPreview(value: string, dependencies: Dependencies = {resolve: (host) => lookup(host, {all: true}), request: requestPinned}): Promise<Preview> {
  const sourceUrl = announcementUrl(value, true);
  const fallback: Preview = {sourceUrl, title: "", description: "", available: false};
  const controller = new AbortController();
  let timer: ReturnType<typeof setTimeout>|undefined;
  const timeout = new Promise<never>((_, reject) => { timer = setTimeout(() => { controller.abort(); reject(new Error("Preview timed out")); }, 8000); });
  try {
    return await Promise.race([timeout, (async () => {
      let url = publicUrl(sourceUrl);
      for (let redirects = 0; redirects <= 3; redirects++) {
        const host = url.hostname.replace(/^\[|\]$/g, "");
        const addresses = isIP(host) ? [{address: host, family: isIP(host)}] : await dependencies.resolve(host);
        if (controller.signal.aborted || !addresses.length || addresses.some((ip) => !isPublicAddress(ip.address))) return fallback;
        const response = await dependencies.request(url, addresses[0], controller.signal);
        if ([301,302,303,307,308].includes(response.status)) { if (!response.location || redirects === 3) return fallback; url = publicUrl(new URL(response.location, url).href); continue; }
        if (response.status !== 200 || !/^(text\/html|application\/xhtml\+xml)(;|$)/i.test(response.type) || response.body.length > MAX_BYTES) return fallback;
        return {...parseLinkMetadata(response.body.toString("utf8"), url.href), sourceUrl};
      }
      return fallback;
    })()]);
  } catch { return fallback; } finally { clearTimeout(timer); controller.abort(); }
}

export function nextPreviewUsage(previous: {start?: number; count?: number}, now: number): {start: number; count: number} {
  const usage = previous.start != null && now - previous.start < 60000 ? {start: previous.start, count: Number(previous.count ?? 0)} : {start: now, count: 0};
  if (usage.count >= 10) throw new HttpsError("resource-exhausted", "Please wait a minute before loading another preview.");
  return {...usage, count: usage.count + 1};
}
export async function admitAnnouncementPreview(db: Firestore, uid: string): Promise<void> {
  await db.runTransaction(async (tx) => {
    const ref = db.doc(`_announcement_preview_limits/${uid}`);
    const [actor, previous] = await Promise.all([tx.get(db.doc(`users/${uid}`)), tx.get(ref)]);
    if (!canManageAnnouncements(actor.data() ?? {})) throw new HttpsError("permission-denied", "Staff or administrator access is required.");
    tx.set(ref, nextPreviewUsage(previous.data() ?? {}, Date.now()));
  });
}
