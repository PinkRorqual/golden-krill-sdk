import React from 'react';
import TestRenderer, { act } from 'react-test-renderer';
import { Linking } from 'react-native';
import { GoldenKrillBanner } from '../src/components/GoldenKrillBanner';
import { makeAds } from './_helpers';

const flushAll = async () => { for (let i = 0; i < 25; i++) await Promise.resolve(); };
const texts = (r: TestRenderer.ReactTestRenderer) =>
  r.root.findAll((n) => n.type === 'Text').map((n) => String(n.children)).join('|');
// Big rotation unit so the (real) rotation timer never fires mid-test; unmount clears it.
const SLOW = { banner_rotation_sec: 99999 };

describe('GoldenKrillBanner', () => {
  it('shows a house ad + GK mark when there is no paid network', async () => {
    const ads = makeAds({ a: [[1, 'i', 's']], o: [] }, { reserve_share: false, ad_badge_chance: 1, ...SLOW });
    let r!: TestRenderer.ReactTestRenderer;
    await act(async () => { r = TestRenderer.create(<GoldenKrillBanner ads={ads} slot="banner" showBadge />); });
    await act(async () => { await flushAll(); });
    expect(r.root.findAll((n) => n.type === 'Image').length).toBe(1); // house Creative
    expect(texts(r)).toContain('GK');
    act(() => r.unmount());
  });

  it('mounts the paid banner (no GK mark) when paidBuilder fills', async () => {
    const ads = makeAds({ a: [[1, 'i', 's']], o: [] }, { reserve_share: false, ...SLOW });
    let r!: TestRenderer.ReactTestRenderer;
    await act(async () => {
      r = TestRenderer.create(
        <GoldenKrillBanner ads={ads} slot="banner" showBadge paidBuilder={async () => React.createElement('PaidAd')} />,
      );
    });
    await act(async () => { await flushAll(); });
    expect(r.root.findAll((n) => n.type === 'PaidAd').length).toBe(1); // paid shown
    expect(texts(r)).not.toContain('GK'); // never a GK mark on paid
    act(() => r.unmount());
  });

  it('collapses to nothing on no-fill when reserveSpace is false', async () => {
    const ads = makeAds({ a: [], o: [] }, { reserve_share: false, ...SLOW });
    let r!: TestRenderer.ReactTestRenderer;
    await act(async () => { r = TestRenderer.create(<GoldenKrillBanner ads={ads} slot="banner" reserveSpace={false} />); });
    await act(async () => { await flushAll(); });
    expect(r.toJSON()).toBeNull();
    act(() => r.unmount());
  });

  it('mrec shows the tappable Powered-by pill', async () => {
    const ads = makeAds({ a: [[1, 'i', 's']], o: [] }, { reserve_share: false, ad_badge_chance: 1, ...SLOW });
    let r!: TestRenderer.ReactTestRenderer;
    await act(async () => { r = TestRenderer.create(<GoldenKrillBanner ads={ads} slot="mrec" showBadge />); });
    await act(async () => { await flushAll(); });
    expect(texts(r)).toContain('Powered by Golden Krill');
    act(() => r.unmount());
  });

  it('Model A (sdkControlsRefresh) renders a unit via the tick loop', async () => {
    const ads = makeAds({ a: [[1, 'i', 's']], o: [] }, { reserve_share: true, reserve_one_in: 1, ...SLOW });
    let r!: TestRenderer.ReactTestRenderer;
    await act(async () => { r = TestRenderer.create(<GoldenKrillBanner ads={ads} slot="banner" sdkControlsRefresh />); });
    await act(async () => { await flushAll(); });
    expect(r.root.findAll((n) => n.type === 'Image').length).toBe(1);
    act(() => r.unmount());
  });

  it('rotateSignal forces a tick', async () => {
    const ads = makeAds({ a: [[1, 'i', 's']], o: [] }, { reserve_share: false, ...SLOW });
    let r!: TestRenderer.ReactTestRenderer;
    await act(async () => { r = TestRenderer.create(<GoldenKrillBanner ads={ads} slot="banner" rotateSignal={0} />); });
    await act(async () => { await flushAll(); });
    await act(async () => { r.update(<GoldenKrillBanner ads={ads} slot="banner" rotateSignal={1} />); });
    await act(async () => { await flushAll(); });
    expect(r.root.findAll((n) => n.type === 'Image').length).toBe(1);
    act(() => r.unmount());
  });

  it('mrec pill opens the about url on tap', async () => {
    const ads = makeAds({ a: [[1, 'i', 's']], o: [] }, { reserve_share: false, ad_badge_chance: 1, ...SLOW });
    let r!: TestRenderer.ReactTestRenderer;
    await act(async () => { r = TestRenderer.create(<GoldenKrillBanner ads={ads} slot="mrec" showBadge />); });
    await act(async () => { await flushAll(); });
    const pill = r.root.find((n) => n.type === 'Pressable');
    act(() => pill.props.onPress());
    expect(Linking.openURL).toHaveBeenCalled();
    act(() => r.unmount());
  });

  it('Model A with a paidBuilder shows paid on a non-reserve unit', async () => {
    const ads = makeAds({ a: [[1, 'i', 's']], o: [] }, { reserve_share: false, ...SLOW });
    let r!: TestRenderer.ReactTestRenderer;
    await act(async () => {
      r = TestRenderer.create(<GoldenKrillBanner ads={ads} slot="banner" sdkControlsRefresh paidBuilder={async () => React.createElement('PaidAd')} />);
    });
    await act(async () => { await flushAll(); });
    expect(r.root.findAll((n) => n.type === 'PaidAd').length).toBe(1);
    act(() => r.unmount());
  });

  it('Model A treats a throwing paidBuilder as no-fill -> house', async () => {
    const ads = makeAds({ a: [[1, 'i', 's']], o: [] }, { reserve_share: false, ...SLOW });
    let r!: TestRenderer.ReactTestRenderer;
    await act(async () => {
      r = TestRenderer.create(<GoldenKrillBanner ads={ads} slot="banner" sdkControlsRefresh paidBuilder={async () => { throw new Error('x'); }} />);
    });
    await act(async () => { await flushAll(); });
    expect(r.root.findAll((n) => n.type === 'Image').length).toBe(1);
    act(() => r.unmount());
  });
});
