import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { loadShared } from "../src/shared/loadShared.js";

const sharedDir = path.resolve(__dirname, "../../shared");

describe("shared data", () => {
  it("loads and cross-validates the repository data", () => {
    const s = loadShared(sharedDir);
    expect(s.weapons.pistol).toBeDefined();
    expect(s.weapons.rifle).toBeDefined();
    expect(s.zombies.walker).toBeDefined();
    expect(s.zombies.runner).toBeDefined();
    expect(s.constants.sim.tickRate).toBe(20);
    expect(s.maps.facility_01?.zombieEntries.length).toBe(4);
  });

  it("rejects an unknown zombie referenced by waves", () => {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "shared-"));
    fs.cpSync(sharedDir, tmp, { recursive: true });
    const waves = JSON.parse(fs.readFileSync(path.join(tmp, "waves.json"), "utf8"));
    waves.mix[0].weights = { ghost: 1 };
    fs.writeFileSync(path.join(tmp, "waves.json"), JSON.stringify(waves));
    expect(() => loadShared(tmp)).toThrow(/unknown zombie 'ghost'/);
  });
});
