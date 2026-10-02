import path from "node:path";
import { loadShared, type SharedData } from "../src/shared/loadShared.js";
import { emptyIntent, type PlayerIntent } from "../src/sim/entities.js";

export const sharedDir = path.resolve(__dirname, "../../shared");
let cached: SharedData | null = null;
export function defs(): SharedData {
  return (cached ??= loadShared(sharedDir));
}

export function intent(buttons = 0, extra: Partial<PlayerIntent> = {}): PlayerIntent {
  return { ...emptyIntent(), buttons, ...extra };
}
