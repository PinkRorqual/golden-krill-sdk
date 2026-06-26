import React, { useEffect, useRef, useState } from 'react';
import { Linking, Pressable, StyleSheet, Text, View } from 'react-native';
import { GoldenKrillAds } from '../ads';
import { BADGE_INFO_URL } from '../endpoints';
import { bannerRotationMs, rollAdBadge } from '../models';
import { Creative } from './Creative';

export interface GoldenKrillBannerProps {
  ads: GoldenKrillAds;
  slot?: string;
  width?: number;
  height?: number;
  /** Change this number to force an immediate rotation (manual refresh / demo). */
  rotateSignal?: number;
  /** Load your paid banner; resolve an element if it filled, or null on no-fill. Omit
   *  for "no paid network" (ours every unit). Reserve units never call this. */
  paidBuilder?: () => Promise<React.ReactElement | null>;
  /** Draw a tiny GK corner mark. Defaults to the portal's show_ad_badge config. */
  showBadge?: boolean;
  /** Hold the slot's space even before/without an ad so the host layout never shifts when
   *  an ad arrives (AdMob-style, default true). Set false to collapse to nothing on no-fill. */
  reserveSpace?: boolean;
  /** Refresh strategy. false (DEFAULT, Model B passive): leave your paid network's auto-refresh
   *  ON; GK mounts paid for (N-1) units then shows one house ad uninterrupted for 1 unit. true
   *  (ADVANCED, Model A): GK drives rotation every unit - turn your paid auto-refresh OFF. The
   *  rotation unit (config bannerRotationMs) must match your paid refresh interval T. */
  sdkControlsRefresh?: boolean;
}

/** Owns the rotation loop: time-based reserve (ours ~1-in-N) + fallback + refresh.
 *  Reserve units never request paid (policy-safe: no load-and-discard). */
export function GoldenKrillBanner({ ads, slot = 'banner', width, height = 50, rotateSignal, paidBuilder, showBadge, reserveSpace = true, sdkControlsRefresh }: GoldenKrillBannerProps) {
  const [content, setContent] = useState<React.ReactElement | null>(null);
  const [badge, setBadge] = useState(false); // rolled per rotation
  const unit = useRef(0);
  const ticking = useRef(false);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const houseEl = async (): Promise<React.ReactElement | null> => {
    const ad = await ads.bannerHouse(slot);
    // Back the contain-fit creative with an opaque neutral so a sub-pixel gap never bleeds the
    // host background through as a white hairline on iOS (parity with the Flutter SDK fix).
    return ad ? <Creative ad={ad} resizeMode="contain" background={BANNER_BACKDROP} /> : null;
  };

  const show = (next: React.ReactElement | null, isHouse: boolean) => {
    setContent(next);
    setBadge(isHouse && (showBadge ?? rollAdBadge(ads.config)));
  };
  const unitMs = () => bannerRotationMs(ads.config);
  // Reserve ratio N; <= 1 means no reserve (paid only, host auto-refreshes).
  const reserveN = () => (ads.config.reserveShare && ads.config.reserveOneIn >= 1 ? ads.config.reserveOneIn : 0);

  const tick = async () => {
    if (ticking.current) return;
    ticking.current = true;
    const reserveTurn = ads.bannerReserveTurn(unit.current);
    unit.current++;
    let next: React.ReactElement | null;
    let isHouse: boolean; // the GK mark is OURS-only: never drawn on/beside a paid ad
    if (reserveTurn || !paidBuilder) {
      next = await houseEl();
      isHouse = true;
    } else {
      let paid: React.ReactElement | null = null;
      try {
        paid = await paidBuilder();
      } catch {
        paid = null; // a throwing paidBuilder is treated as no-fill
      }
      if (paid != null) {
        next = paid;
        isHouse = false; // paid filled -> no GK mark
      } else {
        next = await houseEl();
        isHouse = true;
      }
    }
    setContent(next);
    setBadge(isHouse && (showBadge ?? rollAdBadge(ads.config)));
    ticking.current = false;
  };

  useEffect(() => {
    let cancelled = false;

    // Model B paid phase: mount paid once (host auto-refreshes it) for (N-1) units, then house.
    const enterPaid = async () => {
      if (cancelled) return;
      let paid: React.ReactElement | null = null;
      if (paidBuilder) {
        try { paid = await paidBuilder(); } catch { paid = null; }
      }
      if (cancelled) return;
      if (paid != null) show(paid, false);
      else show(await houseEl(), true);
      if (cancelled) return;
      const n = reserveN();
      timer.current = setTimeout(n <= 1 ? enterPaid : enterHouse, n <= 1 ? unitMs() : unitMs() * (n - 1));
    };
    // Model B house phase: one house ad, uninterrupted for a single unit, then back to paid.
    const enterHouse = async () => {
      if (cancelled) return;
      const house = await houseEl();
      if (cancelled) return;
      if (!house) { enterPaid(); return; }
      show(house, true);
      timer.current = setTimeout(enterPaid, unitMs());
    };

    (async () => {
      await ads.ensureReady(slot);
      if (cancelled) return;
      // Explicit prop wins; otherwise default from the host's portal setting (served config).
      const sdkControls = sdkControlsRefresh ?? ads.config.bannerSdkRefresh;
      if (sdkControls) {
        await tick(); // Advanced: GK drives rotation every unit
        timer.current = setInterval(tick, unitMs()) as unknown as ReturnType<typeof setTimeout>;
      } else {
        await enterPaid(); // Regular (default)
      }
    })();
    return () => {
      cancelled = true;
      if (timer.current) { clearTimeout(timer.current); clearInterval(timer.current as unknown as ReturnType<typeof setInterval>); }
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const first = useRef(true);
  useEffect(() => {
    if (first.current) {
      first.current = false;
      return;
    }
    tick();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [rotateSignal]);

  // Size the box to the slot's aspect (banner 6.4:1, mrec 1.2:1) so the creative fills it
  // exactly - no crop, no letterbox (mrec already proved this with its 300x250 box).
  const aspect = SLOT_ASPECT[slot];
  const boxStyle = aspect
    ? { width: width ?? '100%', aspectRatio: aspect }
    : { width: width ?? '100%', height };
  // Reserve the slot's space even before/without an ad so the host layout never shifts when
  // one arrives (AdMob-style). reserveSpace=false collapses to nothing on no-fill.
  if (!content) return reserveSpace ? <View style={boxStyle} /> : null;
  return (
    <View style={boxStyle}>
      {content}
      {badge && (slot === 'banner' ? (
        // Tiny banner: display-only "GK" (no tap target on a small surface).
        <View style={bannerStyles.badge}><Text style={bannerStyles.badgeTxt}>GK</Text></View>
      ) : (
        // Bigger slots (mrec): tappable "Powered by Golden Krill" -> /about.
        <Pressable style={bannerStyles.pill} onPress={() => Linking.openURL(ads.config.badgeUrl || BADGE_INFO_URL).catch(() => {})}>
          <Text style={bannerStyles.pillTxt}>Powered by Golden Krill</Text>
        </Pressable>
      ))}
    </View>
  );
}

// Slot aspect ratios (must match the server's creative dimensions).
const SLOT_ASPECT: Record<string, number> = { banner: 640 / 100, mrec: 600 / 500 };

// Neutral backdrop behind a house banner creative. The RN AdItem carries no sampled edge
// colours (unlike Flutter), so a neutral is used; a 1px sub-pixel gap shows this opaque
// colour instead of the white host background.
const BANNER_BACKDROP = '#000000';

const bannerStyles = StyleSheet.create({
  badge: { position: 'absolute', bottom: 2, right: 2, backgroundColor: '#e7ad34', borderWidth: 0.5, borderColor: 'rgba(0,0,0,0.4)', paddingHorizontal: 3, borderRadius: 2 },
  badgeTxt: { color: '#12363a', fontSize: 8, fontWeight: '700' },
  pill: { position: 'absolute', bottom: 2, right: 2, backgroundColor: '#e7ad34', borderWidth: 0.5, borderColor: 'rgba(0,0,0,0.4)', paddingHorizontal: 6, paddingVertical: 2, borderRadius: 3 },
  pillTxt: { color: '#12363a', fontSize: 9, fontWeight: '700' },
});
