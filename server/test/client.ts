/** Minimal protocol client for integration tests and the load-test bots. */
import WebSocket from "ws";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { Codec, type Msg } from "../src/net/codec.js";

/** The protocol version in shared/protocol.json (tests speak the current one). */
const PROTOCOL_VERSION = (JSON.parse(fs.readFileSync(path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../shared/protocol.json"), "utf8")) as { protocolVersion: number }).protocolVersion;

export class TestClient {
  readonly inbox: { name: string; msg: Msg }[] = [];
  closed: number | null = null;
  private waiters: (() => void)[] = [];

  private constructor(readonly ws: WebSocket, readonly codec: Codec) {
    ws.on("message", (data: Buffer) => {
      const d = codec.decode("S2C", new Uint8Array(data.buffer, data.byteOffset, data.byteLength));
      this.inbox.push(d);
      this.wake();
    });
    ws.on("close", (code) => {
      this.closed = code;
      this.wake();
    });
  }

  static connect(url: string, codec: Codec): Promise<TestClient> {
    const ws = new WebSocket(url);
    return new Promise((resolve, reject) => {
      ws.once("open", () => resolve(new TestClient(ws, codec)));
      ws.once("error", reject);
    });
  }

  send(name: string, msg: Msg = {}): void {
    if (name === "quickPlay") msg = { mode: 0, friend: "", ...msg }; // classic, alone, unless a test says otherwise
    this.ws.send(this.codec.encode("C2S", name, msg));
  }

  hello(initData: string, resumeToken = "", protocolVersion = PROTOCOL_VERSION): void {
    this.send("hello", { protocolVersion, initData, resumeToken });
  }

  /** Waits for a message (searching from `since`); returns it. */
  async waitFor(name: string, pred: (m: Msg) => boolean = () => true, timeoutMs = 4000, since = 0): Promise<Msg> {
    const deadline = Date.now() + timeoutMs;
    for (;;) {
      const hit = this.inbox.slice(since).find((m) => m.name === name && pred(m.msg));
      if (hit) return hit.msg;
      if (this.closed !== null) throw new Error(`closed (${this.closed}) while waiting for ${name}`);
      const left = deadline - Date.now();
      if (left <= 0) throw new Error(`timeout waiting for ${name}`);
      await new Promise<void>((r) => {
        const t = setTimeout(r, left);
        this.waiters.push(() => {
          clearTimeout(t);
          r();
        });
      });
    }
  }

  async waitClosed(timeoutMs = 3000): Promise<number> {
    const deadline = Date.now() + timeoutMs;
    while (this.closed === null && Date.now() < deadline) await new Promise((r) => setTimeout(r, 20));
    if (this.closed === null) throw new Error("not closed");
    return this.closed;
  }

  close(): void {
    this.ws.close();
  }

  private wake(): void {
    const w = this.waiters;
    this.waiters = [];
    for (const f of w) f();
  }
}
