import { describe, expect, it } from "vitest";
import { loadEnv } from "../src/config/env.js";

describe("env", () => {
  it("applies defaults", () => {
    const env = loadEnv({});
    expect(env.PORT).toBe(8787);
    expect(env.HOST).toBe("127.0.0.1");
    expect(env.ALLOW_DEV_AUTH).toBe(false);
  });
  it("refuses dev auth in production", () => {
    expect(() => loadEnv({ NODE_ENV: "production", ALLOW_DEV_AUTH: "1" })).toThrow();
  });
  it("rejects bad port", () => {
    expect(() => loadEnv({ PORT: "99999" })).toThrow(/PORT/);
  });
});
