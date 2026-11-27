import { strict as assert } from "node:assert";
import test from "node:test";
import { handleRealtimeWebSocketProxy } from "../src/admin-ops-works.js";

class Socket extends EventTarget {
  sent = [];
  closes = [];
  failWrites = false;
  accept() {}
  send(data) {
    if (this.failWrites) throw new Error("closed");
    this.sent.push(data);
  }
  close(code, reason) { this.closes.push({ code, reason }); }
  message(data) { this.dispatchEvent(new MessageEvent("message", { data })); }
}

test("realtime forwards in both directions and ends both sockets on write failure", async (t) => {
  const upstream = new Socket(), client = new Socket(), server = new Socket();
  let upgrades = 0;
  t.mock.method(globalThis, "fetch", async (url, options) => {
    upgrades++;
    assert.equal(new URL(url).searchParams.get("model"), "gpt-realtime");
    assert.equal(options.headers.Authorization, "Bearer offline-upstream");
    return { status: 101, webSocket: upstream };
  });
  const savedPair = globalThis.WebSocketPair;
  globalThis.WebSocketPair = class { constructor() { return [client, server]; } };
  t.after(() => { if (savedPair) globalThis.WebSocketPair = savedPair; else delete globalThis.WebSocketPair; });
  // Node's Response rejects HTTP 101; capture the Cloudflare upgrade result.
  t.mock.method(globalThis, "Response", function (_body, init) { return init; });
  const result = await handleRealtimeWebSocketProxy(
    new Request("https://local.test/v1/realtime?model=gpt-realtime", { headers: { Upgrade: "websocket" } }),
    { AIHUBMIX_API_KEY: "offline-upstream" },
    { authenticateUser: async () => ({ id: "offline-user", balance_micros: 2_000_000 }) }
  );
  assert.equal(result.status, 101);
  assert.equal(result.webSocket, client);
  server.message("audio-in");
  upstream.message("audio-out");
  assert.deepEqual(upstream.sent, ["audio-in"]);
  assert.deepEqual(server.sent, ["audio-out"]);
  upstream.failWrites = true;
  server.message("audio-in-2");
  assert.equal(server.closes[0].code, 1011);
  assert.equal(upstream.closes.length, 1);
  server.dispatchEvent(new Event("error"));
  assert.equal(server.closes.length, 1);
  assert.equal(upgrades, 1);
});
