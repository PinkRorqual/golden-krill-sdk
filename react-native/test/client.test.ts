import { GoldenKrillClient } from '../src/client';
import { enc, resp, memStore, flush } from './_helpers';

describe('GoldenKrillClient', () => {
  it('loadConfig decodes a GK1 config', async () => {
    const c = new GoldenKrillClient('com.x', {
      fetchImpl: async () => resp(200, enc({ reserve_one_in: 5, max_per_session: 2 })),
      storage: memStore(), now: () => 0,
    });
    const cfg = await c.loadConfig();
    expect(cfg.reserveOneIn).toBe(5);
    expect(cfg.maxPerSession).toBe(2);
  });

  it('fetchAds: ok=false on HTTP failure, ok=true (empty) on a good empty response', async () => {
    const fail = new GoldenKrillClient('com.x', { fetchImpl: async () => resp(500, 'err'), storage: memStore() });
    const r1 = await fail.fetchAds('banner');
    expect(r1.ok).toBe(false);
    expect(r1.bundle.ads).toEqual([]);

    const empty = new GoldenKrillClient('com.x', { fetchImpl: async () => resp(200, enc({ a: [], o: [] })), storage: memStore() });
    const r2 = await empty.fetchAds('banner');
    expect(r2.ok).toBe(true); // empty is empty, not a failure
    expect(r2.bundle.ads).toEqual([]);
  });

  it('loadConfig serves the fresh cache within TTL without re-fetching', async () => {
    let calls = 0;
    const c = new GoldenKrillClient('com.x', {
      fetchImpl: async () => { calls++; return resp(200, enc({ reserve_one_in: 6 })); },
      storage: memStore(), now: () => 1000, configTtlMs: 100000,
    });
    expect((await c.loadConfig()).reserveOneIn).toBe(6); // fetch + cache
    expect((await c.loadConfig()).reserveOneIn).toBe(6); // within TTL -> cache
    expect(calls).toBe(1);
  });

  it('loadConfig reuses stale last-good when the fetch fails', async () => {
    let ok = true;
    const c = new GoldenKrillClient('com.x', {
      fetchImpl: async () => (ok ? resp(200, enc({ reserve_one_in: 3 })) : resp(500, 'x')),
      storage: memStore(), now: () => 0, configTtlMs: 1,
    });
    expect((await c.loadConfig()).reserveOneIn).toBe(3); // cache it
    ok = false;
    expect((await c.loadConfig()).reserveOneIn).toBe(3); // stale fetch fails -> last-good
  });

  it('postEvents sends the nonce + a device token that is stable within a week, then rotates', async () => {
    const store = memStore();
    const bodies: any[] = [];
    const mk = (now: number) => new GoldenKrillClient('com.x', {
      storage: store, now: () => now,
      fetchImpl: async (_u: any, init: any) => { if (init && init.body) bodies.push(JSON.parse(init.body)); return resp(200, ''); },
    });
    mk(0).postEvents([{ creative: 1, slot: 'banner', kind: 'view' }], 'n1');
    await flush();
    mk(1000).postEvents([{ creative: 1, slot: 'banner', kind: 'view' }], 'n1');
    await flush();
    mk(8 * 24 * 3600 * 1000).postEvents([{ creative: 1, slot: 'banner', kind: 'view' }], 'n1');
    await flush();
    expect(bodies.length).toBe(3);
    expect(bodies[0].nonce).toBe('n1');
    expect(bodies[1].device).toBe(bodies[0].device); // same week -> same token
    expect(bodies[2].device).not.toBe(bodies[0].device); // 8 days later -> rotated
  });

  it('falls back to an in-memory store when none is provided', async () => {
    const c = new GoldenKrillClient('com.x', { fetchImpl: async () => resp(200, enc({ reserve_one_in: 9 })) });
    expect((await c.loadConfig()).reserveOneIn).toBe(9); // default in-mem storage path
  });

  it('refresh() forces a re-fetch on the next load', async () => {
    let calls = 0;
    const store = memStore();
    const c = new GoldenKrillClient('com.x', {
      fetchImpl: async () => { calls++; return resp(200, enc({ reserve_one_in: 6 })); },
      storage: store, now: () => 1e12, configTtlMs: 1e9, // refresh stamps at=0 -> now-0 > ttl -> stale
    });
    await c.loadConfig();
    await c.loadConfig();
    expect(calls).toBe(1); // cached
    await c.refresh();
    await c.loadConfig();
    expect(calls).toBe(2); // refresh cleared the freshness stamp
  });

  it('fetchAds reports ok=false when the fetch throws', async () => {
    const c = new GoldenKrillClient('com.x', {
      fetchImpl: async () => { throw new Error('network down'); },
      storage: memStore(),
    });
    expect((await c.fetchAds('banner')).ok).toBe(false);
  });
});
