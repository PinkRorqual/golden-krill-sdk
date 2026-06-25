import React from 'react';
import TestRenderer, { act } from 'react-test-renderer';
import { Linking } from 'react-native';
import { GoldenKrillInterstitial } from '../src/components/GoldenKrillInterstitial';
import { makeAds } from './_helpers';

const flushAll = async () => { for (let i = 0; i < 25; i++) await Promise.resolve(); };
const closeBtn = (r: TestRenderer.ReactTestRenderer) =>
  r.root.findAll((n) => n.type === 'Pressable' && n.props.accessibilityLabel === 'Close');

describe('GoldenKrillInterstitial', () => {
  beforeEach(() => (Linking.openURL as jest.Mock).mockClear());

  it('shows a house ad, reveals close after the delay, then closes earned', async () => {
    jest.useFakeTimers();
    const ads = makeAds({ a: [[1, 'i', 's']], o: [] }, { reserve_share: false });
    const onClose = jest.fn();
    let r!: TestRenderer.ReactTestRenderer;
    await act(async () => {
      r = TestRenderer.create(<GoldenKrillInterstitial ads={ads} visible onClose={onClose} closeAfterMs={100} showBadge={false} />);
    });
    await act(async () => { await flushAll(); }); // async fetch picks the ad
    expect(r.root.findAll((n) => n.type === 'Modal').length).toBe(1);
    expect(closeBtn(r).length).toBe(0); // not closable yet
    await act(async () => { jest.advanceTimersByTime(150); });
    expect(closeBtn(r).length).toBe(1);
    act(() => closeBtn(r)[0].props.onPress());
    expect(onClose).toHaveBeenCalledWith(true);
    jest.useRealTimers();
  });

  it('collapses with onClose(false) on no-fill', async () => {
    const ads = makeAds({ a: [], o: [] }, { reserve_share: false });
    const onClose = jest.fn();
    await act(async () => { TestRenderer.create(<GoldenKrillInterstitial ads={ads} visible onClose={onClose} />); });
    await act(async () => { await flushAll(); });
    expect(onClose).toHaveBeenCalledWith(false);
  });

  it('renders the badge and opens about on tap', async () => {
    jest.useFakeTimers();
    const ads = makeAds({ a: [[1, 'i', 's']], o: [] }, { reserve_share: false });
    const onClose = jest.fn();
    let r!: TestRenderer.ReactTestRenderer;
    await act(async () => { r = TestRenderer.create(<GoldenKrillInterstitial ads={ads} visible onClose={onClose} showBadge />); });
    await act(async () => { await flushAll(); });
    const badge = r.root.findAll((n) => n.type === 'Pressable' && n.props.accessibilityLabel !== 'Close')[0];
    act(() => badge.props.onPress());
    expect(Linking.openURL).toHaveBeenCalled();
    jest.useRealTimers();
  });

  it('resets and collapses when visible turns false', async () => {
    jest.useFakeTimers();
    const ads = makeAds({ a: [[1, 'i', 's']], o: [] }, { reserve_share: false });
    const onClose = jest.fn();
    let r!: TestRenderer.ReactTestRenderer;
    await act(async () => { r = TestRenderer.create(<GoldenKrillInterstitial ads={ads} visible onClose={onClose} />); });
    await act(async () => { await flushAll(); });
    await act(async () => { r.update(<GoldenKrillInterstitial ads={ads} visible={false} onClose={onClose} />); });
    expect(r.toJSON()).toBeNull();
    jest.useRealTimers();
  });
});
