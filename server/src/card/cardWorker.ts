/** Worker thread entry: renders result cards off the game's event loop (a card
 *  takes about half a second of CPU). Bundled as card-worker.mjs. */
import { parentPort } from "node:worker_threads";
import { loadRenderer, type CardInput } from "./cardRender.js";

const renderer = loadRenderer();

parentPort!.on("message", async (m: { id: number; input: CardInput }) => {
  try {
    const { jpg, png } = (await renderer).render(m.input);
    parentPort!.postMessage({ id: m.id, jpg, png });
  } catch (err) {
    parentPort!.postMessage({ id: m.id, error: (err as Error).message });
  }
});
