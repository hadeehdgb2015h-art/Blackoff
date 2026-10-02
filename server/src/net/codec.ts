/**
 * Binary codec interpreted from shared/protocol.json (the client's
 * scripts/net/codec.gd interprets the same file). Little-endian, one message
 * per frame: u8 id, then fields in declared order.
 * Decoding is strict: unknown ids, short frames, bad UTF-8 lengths and
 * trailing bytes throw CodecError (the session answers `badMessage`).
 */
import type { ProtocolDef } from "../shared/schemas.js";

export type Dir = "C2S" | "S2C";
export type Msg = Record<string, unknown>;

export class CodecError extends Error {}

type Field = readonly [string, string];
interface MsgSpec { name: string; id: number; fields: readonly Field[] }

const TWO_PI = Math.PI * 2;
const enc = new TextEncoder();
const dec = new TextDecoder("utf-8", { fatal: true });

export class Codec {
  private readonly byName: Record<Dir, Map<string, MsgSpec>> = { C2S: new Map(), S2C: new Map() };
  private readonly byId: Record<Dir, Map<number, MsgSpec>> = { C2S: new Map(), S2C: new Map() };
  private readonly structs = new Map<string, readonly Field[]>();
  private readonly posScale: number;

  constructor(protocol: ProtocolDef) {
    this.posScale = protocol.quantization.posScale;
    for (const [name, t] of Object.entries(protocol.types)) if (Array.isArray(t)) this.structs.set(name, t as Field[]);
    for (const dir of ["C2S", "S2C"] as const) {
      for (const [name, m] of Object.entries(protocol.messages[dir])) {
        const spec = { name, id: m.id, fields: m.fields as Field[] };
        this.byName[dir].set(name, spec);
        this.byId[dir].set(m.id, spec);
      }
    }
  }

  messageNames(dir: Dir): string[] {
    return [...this.byName[dir].keys()];
  }

  encode(dir: Dir, name: string, msg: Msg): Uint8Array {
    const spec = this.byName[dir].get(name);
    if (!spec) throw new CodecError(`unknown ${dir} message ${name}`);
    const w = new Writer();
    w.u8(spec.id);
    this.writeFields(w, spec.fields, msg);
    return w.bytes();
  }

  decode(dir: Dir, data: Uint8Array): { name: string; msg: Msg } {
    const r = new Reader(data);
    const id = r.u8();
    const spec = this.byId[dir].get(id);
    if (!spec) throw new CodecError(`unknown ${dir} message id ${id}`);
    const msg = this.readFields(r, spec.fields);
    if (r.remaining() !== 0) throw new CodecError(`${spec.name}: ${r.remaining()} trailing bytes`);
    return { name: spec.name, msg };
  }

  private writeFields(w: Writer, fields: readonly Field[], msg: Msg): void {
    for (const [fname, type] of fields) {
      if (!(fname in msg)) throw new CodecError(`missing field ${fname}`);
      this.writeValue(w, type, msg[fname], fname);
    }
  }

  private readFields(r: Reader, fields: readonly Field[]): Msg {
    const out: Msg = {};
    for (const [fname, type] of fields) out[fname] = this.readValue(r, type);
    return out;
  }

  private writeValue(w: Writer, type: string, v: unknown, fname: string): void {
    const arr = /^array(8|16):(.+)$/.exec(type);
    if (arr) {
      if (!Array.isArray(v)) throw new CodecError(`${fname}: expected array`);
      const max = arr[1] === "8" ? 255 : 65535;
      if (v.length > max) throw new CodecError(`${fname}: array too long (${v.length})`);
      if (arr[1] === "8") w.u8(v.length);
      else w.u16(v.length);
      for (const item of v) this.writeValue(w, arr[2]!, item, fname);
      return;
    }
    const struct = this.structs.get(type);
    if (struct) {
      this.writeFields(w, struct, v as Msg);
      return;
    }
    switch (type) {
      case "u8": return w.u8(int(v, 0, 0xff, fname));
      case "u16": return w.u16(int(v, 0, 0xffff, fname));
      case "u32": return w.u32(int(v, 0, 0xffffffff, fname));
      case "i8": return w.i8(int(v, -0x80, 0x7f, fname));
      case "i16": return w.i16(int(v, -0x8000, 0x7fff, fname));
      case "f32": return w.f32(num(v, fname));
      case "bool": return w.u8(v ? 1 : 0);
      case "varuint": return w.varuint(int(v, 0, 0xffffffff, fname));
      case "str8": return w.str(String(v), 8, fname);
      case "str16": return w.str(String(v), 16, fname);
      case "bytes16": return w.raw(v, fname);
      case "pos": return w.i16(clampInt(Math.round(num(v, fname) * this.posScale), -0x8000, 0x7fff));
      case "angle": {
        const a = num(v, fname);
        const turns = a / TWO_PI - Math.floor(a / TWO_PI);
        return w.u16(Math.round(turns * 65536) & 0xffff);
      }
      case "pitch": return w.i16(clampInt(Math.round((num(v, fname) / (Math.PI / 2)) * 32767), -32767, 32767));
      default: throw new CodecError(`unknown type ${type}`);
    }
  }

  private readValue(r: Reader, type: string): unknown {
    const arr = /^array(8|16):(.+)$/.exec(type);
    if (arr) {
      const n = arr[1] === "8" ? r.u8() : r.u16();
      const out: unknown[] = [];
      for (let i = 0; i < n; i++) out.push(this.readValue(r, arr[2]!));
      return out;
    }
    const struct = this.structs.get(type);
    if (struct) return this.readFields(r, struct);
    switch (type) {
      case "u8": return r.u8();
      case "u16": return r.u16();
      case "u32": return r.u32();
      case "i8": return r.i8();
      case "i16": return r.i16();
      case "f32": return r.f32();
      case "bool": return r.u8() !== 0;
      case "varuint": return r.varuint();
      case "str8": return r.str(8);
      case "str16": return r.str(16);
      case "bytes16": return r.raw();
      case "pos": return r.i16() / this.posScale;
      case "angle": return (r.u16() / 65536) * TWO_PI;
      case "pitch": return (r.i16() / 32767) * (Math.PI / 2);
      default: throw new CodecError(`unknown type ${type}`);
    }
  }
}

function num(v: unknown, fname: string): number {
  if (typeof v !== "number" || !Number.isFinite(v)) throw new CodecError(`${fname}: expected a finite number`);
  return v;
}

function int(v: unknown, lo: number, hi: number, fname: string): number {
  const n = num(v, fname);
  if (!Number.isInteger(n) || n < lo || n > hi) throw new CodecError(`${fname}: ${n} outside [${lo}, ${hi}]`);
  return n;
}

const clampInt = (v: number, lo: number, hi: number): number => (v < lo ? lo : v > hi ? hi : v);

class Writer {
  private buf = new Uint8Array(128);
  private view = new DataView(this.buf.buffer);
  private n = 0;
  private ensure(k: number): void {
    if (this.n + k <= this.buf.length) return;
    const nb = new Uint8Array(Math.max(this.buf.length * 2, this.n + k));
    nb.set(this.buf);
    this.buf = nb;
    this.view = new DataView(nb.buffer);
  }
  u8(v: number): void { this.ensure(1); this.view.setUint8(this.n, v); this.n += 1; }
  i8(v: number): void { this.ensure(1); this.view.setInt8(this.n, v); this.n += 1; }
  u16(v: number): void { this.ensure(2); this.view.setUint16(this.n, v, true); this.n += 2; }
  i16(v: number): void { this.ensure(2); this.view.setInt16(this.n, v, true); this.n += 2; }
  u32(v: number): void { this.ensure(4); this.view.setUint32(this.n, v, true); this.n += 4; }
  f32(v: number): void { this.ensure(4); this.view.setFloat32(this.n, v, true); this.n += 4; }
  varuint(v: number): void {
    do {
      let b = v & 0x7f;
      v = Math.floor(v / 128);
      if (v > 0) b |= 0x80;
      this.u8(b);
    } while (v > 0);
  }
  str(s: string, bits: 8 | 16, fname: string): void {
    const b = enc.encode(s);
    const max = bits === 8 ? 255 : 65535;
    if (b.length > max) throw new CodecError(`${fname}: string too long (${b.length} bytes)`);
    if (bits === 8) this.u8(b.length);
    else this.u16(b.length);
    this.ensure(b.length);
    this.buf.set(b, this.n);
    this.n += b.length;
  }
  /** bytes16: u16 length + raw bytes (a Uint8Array or an array of byte values) */
  raw(v: unknown, fname: string): void {
    const b = v instanceof Uint8Array ? v : Array.isArray(v) ? Uint8Array.from(v as number[]) : null;
    if (!b) throw new CodecError(`${fname}: expected bytes`);
    if (b.length > 65535) throw new CodecError(`${fname}: too long (${b.length} bytes)`);
    this.u16(b.length);
    this.ensure(b.length);
    this.buf.set(b, this.n);
    this.n += b.length;
  }
  bytes(): Uint8Array { return this.buf.slice(0, this.n); }
}

class Reader {
  private view: DataView;
  private n = 0;
  constructor(private readonly data: Uint8Array) {
    this.view = new DataView(data.buffer, data.byteOffset, data.byteLength);
  }
  remaining(): number { return this.data.length - this.n; }
  private need(k: number): void {
    if (this.n + k > this.data.length) throw new CodecError("frame too short");
  }
  u8(): number { this.need(1); return this.view.getUint8(this.n++); }
  i8(): number { this.need(1); return this.view.getInt8(this.n++); }
  u16(): number { this.need(2); const v = this.view.getUint16(this.n, true); this.n += 2; return v; }
  i16(): number { this.need(2); const v = this.view.getInt16(this.n, true); this.n += 2; return v; }
  u32(): number { this.need(4); const v = this.view.getUint32(this.n, true); this.n += 4; return v; }
  f32(): number { this.need(4); const v = this.view.getFloat32(this.n, true); this.n += 4; return v; }
  varuint(): number {
    let v = 0;
    for (let i = 0; i < 5; i++) {
      const b = this.u8();
      v += (b & 0x7f) * 2 ** (7 * i);
      if ((b & 0x80) === 0) return v;
    }
    throw new CodecError("varuint too long");
  }
  raw(): Uint8Array {
    const len = this.u16();
    this.need(len);
    const out = this.data.slice(this.n, this.n + len);
    this.n += len;
    return out;
  }
  str(bits: 8 | 16): string {
    const len = bits === 8 ? this.u8() : this.u16();
    this.need(len);
    const s = this.data.subarray(this.n, this.n + len);
    this.n += len;
    try {
      return dec.decode(s);
    } catch {
      throw new CodecError("invalid UTF-8");
    }
  }
}
