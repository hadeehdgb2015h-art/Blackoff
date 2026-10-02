/** Seeded PRNG (sfc32). The server never uses Math.random() inside the sim. */
export class Rng {
  private a: number;
  private b: number;
  private c: number;
  private d: number;

  constructor(seed: number) {
    this.a = 0x9e3779b9;
    this.b = 0x243f6a88;
    this.c = 0xb7e15162;
    this.d = seed >>> 0;
    for (let i = 0; i < 12; i++) this.next();
  }

  /** Uniform 32-bit unsigned integer. */
  next(): number {
    const t = (((this.a + this.b) >>> 0) + this.d) >>> 0;
    this.d = (this.d + 1) >>> 0;
    this.a = this.b ^ (this.b >>> 9);
    this.b = (this.c + (this.c << 3)) >>> 0;
    this.c = ((this.c << 21) | (this.c >>> 11)) >>> 0;
    this.c = (this.c + t) >>> 0;
    return t;
  }

  /** [0, 1) */
  randf(): number {
    return this.next() / 4294967296;
  }

  range(lo: number, hi: number): number {
    return lo + (hi - lo) * this.randf();
  }

  shuffle<T>(arr: T[]): T[] {
    for (let i = arr.length - 1; i > 0; i--) {
      const j = this.next() % (i + 1);
      [arr[i], arr[j]] = [arr[j] as T, arr[i] as T];
    }
    return arr;
  }
}
