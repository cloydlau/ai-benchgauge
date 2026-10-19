export class OSSStore {
  constructor(client, prefix = 'benchgauge/') { this.client = client; this.prefix = prefix; }
  key(kind, suffix) { return `${this.prefix}${kind}/${suffix}`; }
  async readModelsDev() {
    try { return JSON.parse((await this.client.get(this.key('models-dev', 'latest.json'), { timeout: 3000 })).content.toString('utf8')); }
    catch (error) { if (error.code === 'NoSuchKey') return null; throw error; }
  }
  async writeModelsDev(value) { await this.writeBoard('models-dev', value); }
  async readBoard(kind) {
    try {
      const result = await this.client.get(this.key(kind, 'latest.json'));
      return JSON.parse(result.content.toString('utf8'));
    } catch (error) {
      if (error.code === 'NoSuchKey') return null;
      throw error;
    }
  }
  async writeBoard(kind, board) {
    await this.client.put(this.key(kind, 'latest.json'), Buffer.from(JSON.stringify(board)), {
      headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-cache' }, timeout: 8000,
    });
  }
  async readCountry(key) {
    try { return JSON.parse((await this.client.get(`${this.prefix}countries/${encodeURIComponent(key)}.json`, { timeout: 1500 })).content.toString('utf8')); }
    catch (error) { if (error.code === 'NoSuchKey') return null; throw error; }
  }
  async writeCountry(key, record) {
    await this.client.put(`${this.prefix}countries/${encodeURIComponent(key)}.json`, Buffer.from(JSON.stringify(record)), {
      headers: { 'Content-Type': 'application/json' }, timeout: 1500,
    });
  }
  async readBrand(key) {
    try { return JSON.parse((await this.client.get(`${this.prefix}brands/${encodeURIComponent(key)}.json`, { timeout: 2500 })).content.toString('utf8')); }
    catch (error) { if (error.code === 'NoSuchKey') return null; throw error; }
  }
  async writeBrand(key, record) {
    await this.client.put(`${this.prefix}brands/${encodeURIComponent(key)}.json`, Buffer.from(JSON.stringify(record)), {
      headers: { 'Content-Type': 'application/json' }, timeout: 2500,
    });
  }
  async readBrandPNG(hash) {
    if (!/^[a-f0-9]{64}$/.test(hash)) return null;
    try { return (await this.client.get(`${this.prefix}brand-assets/${hash}.png`, { timeout: 2500 })).content; }
    catch (error) { if (error.code === 'NoSuchKey') return null; throw error; }
  }
  async writeBrandPNG(hash, bytes) {
    if (!/^[a-f0-9]{64}$/.test(hash)) throw new Error('Invalid asset hash');
    await this.client.put(`${this.prefix}brand-assets/${hash}.png`, bytes, {
      headers: { 'Content-Type': 'image/png', 'Cache-Control': 'public, max-age=31536000, immutable' }, timeout: 2500,
    });
  }
  async readState(kind, timeout = 8000) {
    const key = this.key(kind, 'coordination.log');
    let head;
    try { head = await this.client.head(key, { timeout }); }
    catch (error) { if (error.code === 'NoSuchKey') return { position: 0, state: null }; throw error; }
    const position = Number(head.res.headers['content-length']);
    if (!Number.isSafeInteger(position) || position < 1) throw new Error('Invalid coordination object');
    // Read only the tail, not the ever-growing grant metadata journal. Fix the
    // range to the HEAD position; a concurrent append makes our CAS fail later.
    const result = await this.client.get(key, { timeout, headers: { Range: `bytes=${Math.max(0, position - 2048)}-${position - 1}` } });
    const last = result.content.toString('utf8').trimEnd().split('\n').at(-1);
    return { position, state: JSON.parse(last) };
  }
  async appendState(kind, position, state, timeout = 8000) {
    try {
      await this.client.append(this.key(kind, 'coordination.log'), Buffer.from(JSON.stringify(state) + '\n'), {
        position, timeout,
      });
      return true;
    } catch (error) {
      if (error.code === 'PositionNotEqualToLength') return false;
      throw error;
    }
  }
}
