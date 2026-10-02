// Blackoff voice chat (phase 12). Runs in the page next to the Godot engine;
// the game (scripts/core/platform.gd) talks to window.BlackoffVoice.
//
//   capture:  getUserMedia (echo cancellation, noise suppression, auto gain)
//             -> AudioWorklet (ScriptProcessor fallback) -> 16 kHz mono
//             -> 40 ms frames -> voice activity gate -> IMA ADPCM (4 bits/sample)
//             -> take() hands the frames to the game, which sends them on its
//                WebSocket (the server relays them to the zone, never decodes)
//   playback: play(entityId, seq, base64) -> decode -> one short jitter buffer
//             per speaker -> speaker gain (speaker off = gain 0 and the game
//             tells the server to stop sending)
//
// Frame: 4-byte header (predictor i16 LE, step index u8, version u8) + 320
// bytes of nibbles = 324 bytes for 640 samples. The header carries the coder
// state at the start of the frame, so every frame decodes on its own and a
// lost frame costs 40 ms of audio, nothing more.
//
// The codec part has no browser dependencies: server/tools/voiceBot.ts and
// server/test/voice.test.ts load this file with require().
(function (root) {
  'use strict';
  const RATE = 16000;
  const FRAME_MS = 40;
  const FRAME = (RATE * FRAME_MS) / 1000; // 640 samples
  const HEADER = 4;
  const FRAME_BYTES = HEADER + FRAME / 2;  // 324
  const VERSION = 1;
  const STEP = [7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45, 50, 55, 60, 66, 73, 80, 88, 97, 107, 118,
    130, 143, 157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494, 544, 598, 658, 724, 796, 876, 963, 1060, 1166, 1282,
    1411, 1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428, 4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493,
    10442, 11487, 12635, 13899, 15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767];
  const INDEX = [-1, -1, -1, -1, 2, 4, 6, 8];

  // ------------------------------------------------------------------ codec
  function Coder() { this.pred = 0; this.idx = 0; }

  /** Float32 samples in [-1, 1] -> one frame. The coder keeps its state across
   *  frames (smoother), the header lets a decoder start from any frame. */
  Coder.prototype.encode = function (samples) {
    const out = new Uint8Array(HEADER + (samples.length >> 1));
    out[0] = this.pred & 0xff; out[1] = (this.pred >> 8) & 0xff; out[2] = this.idx; out[3] = VERSION;
    let pred = this.pred, idx = this.idx;
    for (let i = 0; i < samples.length; i++) {
      let s = Math.round(samples[i] * 32767);
      if (s > 32767) s = 32767; else if (s < -32768) s = -32768;
      let step = STEP[idx];
      let diff = s - pred;
      let nib = 0;
      if (diff < 0) { nib = 8; diff = -diff; }
      let vp = step >> 3;
      if (diff >= step) { nib |= 4; diff -= step; vp += step; }
      step >>= 1;
      if (diff >= step) { nib |= 2; diff -= step; vp += step; }
      step >>= 1;
      if (diff >= step) { nib |= 1; vp += step; }
      pred += (nib & 8) ? -vp : vp;
      if (pred > 32767) pred = 32767; else if (pred < -32768) pred = -32768;
      idx += INDEX[nib & 7];
      if (idx < 0) idx = 0; else if (idx > 88) idx = 88;
      if (i & 1) out[HEADER + (i >> 1)] |= nib << 4; else out[HEADER + (i >> 1)] = nib;
    }
    this.pred = pred; this.idx = idx;
    return out;
  };

  /** One frame -> Float32Array of samples in [-1, 1]. */
  function decodeFrame(bytes) {
    const n = (bytes.length - HEADER) * 2;
    const out = new Float32Array(n);
    let pred = (bytes[0] | (bytes[1] << 8)) << 16 >> 16; // sign-extend i16
    let idx = Math.min(88, bytes[2]);
    for (let i = 0; i < n; i++) {
      const nib = (i & 1) ? bytes[HEADER + (i >> 1)] >> 4 : bytes[HEADER + (i >> 1)] & 15;
      const step = STEP[idx];
      let vp = step >> 3;
      if (nib & 4) vp += step;
      if (nib & 2) vp += step >> 1;
      if (nib & 1) vp += step >> 2;
      pred += (nib & 8) ? -vp : vp;
      if (pred > 32767) pred = 32767; else if (pred < -32768) pred = -32768;
      idx += INDEX[nib & 7];
      if (idx < 0) idx = 0; else if (idx > 88) idx = 88;
      out[i] = pred / 32768;
    }
    return out;
  }

  function rms(samples) {
    let acc = 0;
    for (let i = 0; i < samples.length; i++) acc += samples[i] * samples[i];
    return Math.sqrt(acc / Math.max(1, samples.length));
  }

  const codec = { RATE, FRAME_MS, FRAME, HEADER, FRAME_BYTES, Coder, decodeFrame, rms };
  if (typeof module !== 'undefined' && module.exports) module.exports = codec;
  if (typeof window === 'undefined') return;

  // --------------------------------------------------------------- browser
  const cfg = { vadThreshold: 0.012, vadHoldFrames: 8, jitterMs: 80, speakingHoldMs: 350 };
  const state = { mic: 'off', speaker: 'on', error: '', talking: false };
  const stats = { sent: 0, received: 0, played: 0, dropped: 0 };
  let ctx = null, outGain = null, silent = null;
  let stream = null, source = null, node = null;
  let wantMic = false, wantSpeaker = true;
  const coder = new Coder();
  let hold = 0;
  const outQueue = [];
  const speakers = {};  // entityId -> {next, last}

  function ensureCtx() {
    if (ctx) return ctx;
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return null;
    ctx = new AC({ latencyHint: 'interactive' });
    outGain = ctx.createGain();
    outGain.gain.value = wantSpeaker ? 1 : 0;
    outGain.connect(ctx.destination);
    silent = ctx.createGain();
    silent.gain.value = 0;
    silent.connect(ctx.destination);
    return ctx;
  }

  // Browsers start audio only inside a user gesture; Godot handles taps a frame
  // later, so the context is created and resumed on any tap on the page.
  function unlock() {
    const c = ensureCtx();
    if (c && c.state !== 'running') c.resume().catch(function () {});
  }
  document.addEventListener('pointerup', unlock, true);
  document.addEventListener('touchend', unlock, true);
  document.addEventListener('keydown', unlock, true);

  const WORKLET = `
class BlackoffCapture extends AudioWorkletProcessor {
  constructor() { super(); this.ratio = sampleRate / ${RATE}; this.pos = 0; this.prev = 0; this.buf = new Float32Array(${FRAME}); this.n = 0; }
  process(inputs) {
    const ch = inputs[0] && inputs[0][0];
    if (!ch || ch.length === 0) return true;
    let i = this.pos;
    while (i + 1 < ch.length) {
      const i0 = Math.floor(i), f = i - i0;
      const a = i0 < 0 ? this.prev : ch[i0];
      const b = ch[i0 + 1];
      this.buf[this.n++] = a + (b - a) * f;
      if (this.n === ${FRAME}) { this.port.postMessage(this.buf); this.buf = new Float32Array(${FRAME}); this.n = 0; }
      i += this.ratio;
    }
    this.pos = i - ch.length;
    this.prev = ch[ch.length - 1];
    return true;
  }
}
registerProcessor('blackoff-capture', BlackoffCapture);`;
  let workletUrl = null;

  // ScriptProcessor fallback: the same resampler on the main thread.
  const fallback = { pos: 0, prev: 0, buf: new Float32Array(FRAME), n: 0 };
  function resampleBlock(ch, inRate) {
    const ratio = inRate / RATE;
    let i = fallback.pos;
    while (i + 1 < ch.length) {
      const i0 = Math.floor(i), f = i - i0;
      const a = i0 < 0 ? fallback.prev : ch[i0];
      const b = ch[i0 + 1];
      fallback.buf[fallback.n++] = a + (b - a) * f;
      if (fallback.n === FRAME) { onCaptured(fallback.buf); fallback.buf = new Float32Array(FRAME); fallback.n = 0; }
      i += ratio;
    }
    fallback.pos = i - ch.length;
    fallback.prev = ch[ch.length - 1];
  }

  /** 640 samples at 16 kHz from the microphone: gate on voice activity, encode, queue. */
  function onCaptured(samples) {
    if (!wantMic) return;
    const level = rms(samples);
    if (level > cfg.vadThreshold) hold = cfg.vadHoldFrames;
    else if (hold > 0) hold -= 1;
    state.talking = hold > 0;
    if (!state.talking) { coder.pred = 0; coder.idx = 0; return; }
    outQueue.push(coder.encode(samples));
    if (outQueue.length > 12) { outQueue.shift(); stats.dropped += 1; }  // the game stopped taking frames
  }

  async function startMic() {
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) { state.mic = 'unsupported'; return; }
    state.mic = 'starting';
    state.error = '';
    try {
      stream = await navigator.mediaDevices.getUserMedia({
        audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true, channelCount: 1 }, video: false,
      });
    } catch (e) {
      state.mic = (e && (e.name === 'NotAllowedError' || e.name === 'SecurityError' || e.name === 'PermissionDeniedError')) ? 'denied' : 'unsupported';
      state.error = e && e.name ? e.name : String(e);
      console.warn('[voice] microphone: ' + state.error);
      return;
    }
    if (!wantMic) { stopTracks(); return; }  // switched off while the permission dialog was open
    const c = ensureCtx();
    if (!c) { state.mic = 'unsupported'; stopTracks(); return; }
    await c.resume().catch(function () {});
    source = c.createMediaStreamSource(stream);
    try {
      if (c.audioWorklet) {
        if (!workletUrl) workletUrl = URL.createObjectURL(new Blob([WORKLET], { type: 'text/javascript' }));
        await c.audioWorklet.addModule(workletUrl);
        node = new AudioWorkletNode(c, 'blackoff-capture', { numberOfInputs: 1, numberOfOutputs: 1, outputChannelCount: [1] });
        node.port.onmessage = function (e) { onCaptured(e.data); };
      } else {
        node = c.createScriptProcessor(2048, 1, 1);
        node.onaudioprocess = function (e) { resampleBlock(e.inputBuffer.getChannelData(0), c.sampleRate); };
      }
    } catch (e) {
      state.mic = 'unsupported'; state.error = String(e); stopTracks(); return;
    }
    source.connect(node);
    node.connect(silent);  // a node processes only while it leads to the destination
    if (!wantMic) { stopMic(); return; }
    state.mic = 'on';
    console.log('[voice] microphone on (' + (c.audioWorklet ? 'worklet' : 'script processor') + ', ' + c.sampleRate + ' Hz)');
  }

  function stopTracks() {
    if (stream) stream.getTracks().forEach(function (t) { t.stop(); });
    stream = null;
  }

  function stopMic() {
    try { if (source) source.disconnect(); } catch (e) {}
    try { if (node) { node.disconnect(); if (node.port) node.port.onmessage = null; node.onaudioprocess = null; } } catch (e) {}
    source = null; node = null;
    stopTracks();
    outQueue.length = 0;
    hold = 0;
    state.talking = false;
    if (state.mic === 'on' || state.mic === 'starting') state.mic = 'off';
  }

  function b64decode(s) {
    const bin = atob(s);
    const out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  }

  root.BlackoffVoice = {
    /** Tunables from shared/constants.json (voice), set by the game at start. */
    configure: function (o) { for (const k in o) if (k in cfg && typeof o[k] === 'number') cfg[k] = o[k]; },
    supported: function () { return !!(navigator.mediaDevices && navigator.mediaDevices.getUserMedia && (window.AudioContext || window.webkitAudioContext)); },
    setMic: function (on) {
      wantMic = !!on;
      if (wantMic) { if (state.mic !== 'on' && state.mic !== 'starting') startMic(); }
      else stopMic();
    },
    setSpeaker: function (on) {
      wantSpeaker = !!on;
      state.speaker = wantSpeaker ? 'on' : 'off';
      if (outGain) outGain.gain.value = wantSpeaker ? 1 : 0;
      if (wantSpeaker) unlock();
    },
    /** Next encoded frame to send (Uint8Array), or null. */
    take: function () {
      const f = outQueue.shift();
      if (!f) return null;
      stats.sent += 1;
      return f;
    },
    /** A frame from another player, base64 (from the game's WebSocket). */
    play: function (entityId, seq, b64) {
      stats.received += 1;
      if (!wantSpeaker) return;
      const c = ensureCtx();
      if (!c) return;
      if (c.state !== 'running') { c.resume().catch(function () {}); return; }
      let bytes;
      try { bytes = b64decode(b64); } catch (e) { return; }
      if (bytes.length !== FRAME_BYTES || bytes[3] !== VERSION) return;
      const pcm = decodeFrame(bytes);
      const buf = c.createBuffer(1, pcm.length, RATE);
      buf.getChannelData(0).set(pcm);
      const src = c.createBufferSource();
      src.buffer = buf;
      src.connect(outGain);
      const sp = speakers[entityId] || (speakers[entityId] = { next: 0, last: 0 });
      const now = c.currentTime;
      // under-run (first frame or a gap): restart behind the clock by the jitter margin
      if (sp.next < now + 0.005 || sp.next > now + 0.4) sp.next = now + cfg.jitterMs / 1000;
      src.start(sp.next);
      sp.next += FRAME_MS / 1000;
      sp.last = performance.now();
      stats.played += 1;
    },
    /** Entity ids heard in the last speakingHoldMs, as a JSON array. */
    speaking: function () {
      const now = performance.now(), out = [];
      for (const id in speakers) if (now - speakers[id].last < cfg.speakingHoldMs) out.push(Number(id));
      return JSON.stringify(out);
    },
    /** State for the game's buttons and for tests, as JSON. */
    status: function () {
      return JSON.stringify({ mic: state.mic, speaker: state.speaker, talking: state.talking, error: state.error,
        sent: stats.sent, received: stats.received, played: stats.played, dropped: stats.dropped,
        context: ctx ? ctx.state : 'none' });
    },
    codec: codec,
  };
})(typeof window !== 'undefined' ? window : globalThis);
