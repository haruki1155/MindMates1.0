import {test} from "node:test";
import assert from "node:assert/strict";
import {getAnnouncementLinkPreview, isPublicAddress, parseLinkMetadata, nextPreviewUsage, requestPinned} from "./announcement_link_preview";
import {createServer} from "node:http";
import {AddressInfo} from "node:net";
test("reserved, mapped, loopback, private and documentation addresses are rejected", () => {
  for (const ip of ["127.0.0.1", "10.0.0.1", "169.254.169.254", "100.64.0.1", "192.168.1.1", "192.0.2.1", "::1", "fc00::1", "fe80::1", "::ffff:127.0.0.1", "2001:db8::1", "2002:7f00:1::"]) assert.equal(isPublicAddress(ip), false, ip);
  assert.equal(isPublicAddress("8.8.8.8"), true);
  assert.equal(isPublicAddress("2606:4700:4700::1111"), true);
});
test("metadata uses Open Graph precedence, entities, plain text and relative images", () => {
  const preview = parseLinkMetadata('<title>Fallback</title><meta property="og:title" content="Career &amp; jobs"><meta name="description" content="Details"><meta property="og:image" content="/image.jpg"><script>alert(1)</script>', "https://example.com/post");
  assert.equal(preview.title, "Career & jobs"); assert.equal(preview.description, "Details"); assert.equal(preview.imageUrl, "https://example.com/image.jpg");
  assert.equal(parseLinkMetadata('<title></title><script>bad</script>', "https://example.com").available, false);
});
test("fetch pins the resolved address, validates redirect destinations and blocks rebinding", async () => {
  const connected: string[] = [];
  const result = await getAnnouncementLinkPreview("https://example.com/post", {resolve: async () => [{address: "8.8.8.8", family: 4}], request: async (url, ip) => { connected.push(ip.address); return {status: 200, type: "text/html", body: Buffer.from('<title>Jobs</title>')}; }});
  assert.equal(result.title, "Jobs"); assert.deepEqual(connected, ["8.8.8.8"]);
  let calls = 0;
  const blocked = await getAnnouncementLinkPreview("https://example.com", {resolve: async (host) => [{address: host === "example.com" ? "8.8.8.8" : "127.0.0.1", family: 4}], request: async () => { calls++; return {status: 302, location: "http://private.test/", type: "", body: Buffer.alloc(0)}; }});
  assert.equal(blocked.available, false); assert.equal(calls, 1);
});
test("unsafe URLs never connect and oversized, non-HTML and excessive redirects fall back", async () => {
  for (const url of ["file:///etc/passwd", "http://localhost", "https://user:secret@example.com", "http://example.com:8080", "http://127.0.0.1"]) {
    let connected = false;
    await getAnnouncementLinkPreview(url, {resolve: async () => [{address: "127.0.0.1", family: 4}], request: async () => { connected = true; throw new Error(); }}).catch(() => undefined);
    assert.equal(connected, false);
  }
  for (const response of [{status: 200, type: "application/json", body: Buffer.from('{}')}, {status: 200, type: "text/html", body: Buffer.alloc(524289)}, {status: 302, type: "", location: "/again", body: Buffer.alloc(0)}]) {
    const result = await getAnnouncementLinkPreview("https://example.com", {resolve: async () => [{address: "8.8.8.8", family: 4}], request: async () => response});
    assert.equal(result.available, false);
  }
});
test("preview usage is bounded per minute", () => {
  assert.deepEqual(nextPreviewUsage({start:1000,count:9}, 2000), {start:1000,count:10});
  assert.throws(() => nextPreviewUsage({start:1000,count:10}, 2000));
  assert.deepEqual(nextPreviewUsage({start:1000,count:10}, 61000), {start:61000,count:1});
});
test("real pinned transport uses approved address, bounds bytes and aborts hanging responses", async () => {
  const server = createServer((req,res) => {
    if (req.url === "/hang") return;
    res.setHeader("Content-Type", "text/html");
    if (req.url === "/large") { res.write(Buffer.alloc(524288)); res.end(Buffer.alloc(1)); }
    else res.end(`<title>${req.headers.host}</title>`);
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const port = (server.address() as AddressInfo).port;
  const address = {address:"127.0.0.1",family:4};
  try {
    // No external lookup: the unresolvable hostname must connect via the supplied address.
    const response = await requestPinned(new URL(`http://does-not-resolve.invalid:${port}/`), address, new AbortController().signal);
    assert.match(response.body.toString(), /does-not-resolve.invalid/);
    await assert.rejects(requestPinned(new URL(`http://does-not-resolve.invalid:${port}/large`), address, new AbortController().signal));
    const abort = new AbortController();
    const pending = requestPinned(new URL(`http://does-not-resolve.invalid:${port}/hang`), address, abort.signal);
    setTimeout(() => abort.abort(), 25);
    await assert.rejects(pending);
  } finally { server.closeAllConnections(); await new Promise<void>((resolve) => server.close(() => resolve())); }
});
