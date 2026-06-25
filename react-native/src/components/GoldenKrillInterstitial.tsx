import React, { useEffect, useRef, useState } from 'react';
import { Image, Linking, Modal, Pressable, StyleSheet, Text, View } from 'react-native';
import { GoldenKrillAds } from '../ads';
import { BADGE_INFO_URL } from '../endpoints';
import { AdItem, rollAdBadge } from '../models';
import { Creative } from './Creative';

export interface GoldenKrillInterstitialProps {
  ads: GoldenKrillAds;
  visible: boolean;
  onClose: (shown: boolean) => void;
  closeAfterMs?: number;
  /** Draw an "Ad" disclosure badge. Defaults to the portal's show_ad_badge config. */
  showBadge?: boolean;
}

/** Full-screen interstitial Modal. On show it runs reserve -> fallback (the host app
 *  tries its paid network first, before setting visible). A close button appears after
 *  closeAfterMs. Calls onClose(true) if a house ad was shown, else onClose(false). */
export function GoldenKrillInterstitial({ ads, visible, onClose, closeAfterMs = 3000, showBadge }: GoldenKrillInterstitialProps) {
  const [ad, setAd] = useState<AdItem | null>(null);
  const [badge, setBadge] = useState(false);
  const [canClose, setCanClose] = useState(false);
  const handled = useRef(false);

  useEffect(() => {
    if (!visible) {
      handled.current = false;
      setAd(null);
      setCanClose(false);
      return;
    }
    if (handled.current) return;
    handled.current = true;
    let timer: ReturnType<typeof setTimeout> | undefined;
    // Per-display fetch is async: reserve (1-in-N) first, else fallback on no-fill.
    (async () => {
      const picked = (await ads.reserveAd('interstitial')) ?? (await ads.fallbackAd('interstitial'));
      if (!picked) {
        onClose(false); // nothing to show -> collapse
        return;
      }
      setAd(picked);
      setBadge(showBadge ?? rollAdBadge(ads.config));
      timer = setTimeout(() => setCanClose(true), closeAfterMs);
    })();
    return () => {
      if (timer) clearTimeout(timer);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [visible]);

  if (!visible || !ad) return null;
  return (
    <Modal visible transparent animationType="fade" onRequestClose={() => canClose && onClose(true)}>
      <View style={styles.bg}>
        {/* Blurred copy fills behind the letterboxed creative (no crop, no dead bars). Scaled past
            cover so the gap shows only the abstract zoomed center, not recognizable cropped edges. */}
        <Image source={{ uri: ad.image }} style={[StyleSheet.absoluteFill, { transform: [{ scale: 1.3 }] }]} resizeMode="cover" blurRadius={32} />
        <Creative ad={ad} width={'100%'} height={'100%'} />
        {badge && (
          <Pressable style={styles.badge} onPress={() => Linking.openURL(ads.config.badgeUrl || BADGE_INFO_URL).catch(() => {})}>
            <Text style={styles.badgeTxt}>Powered by Golden Krill</Text>
          </Pressable>
        )}
        {canClose && (
          <Pressable style={styles.close} onPress={() => onClose(true)} accessibilityLabel="Close">
            <Text style={styles.closeTxt}>✕</Text>
          </Pressable>
        )}
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  bg: { flex: 1, backgroundColor: 'black', alignItems: 'center', justifyContent: 'center' },
  close: { position: 'absolute', top: 40, right: 20, width: 40, height: 40, borderRadius: 20, backgroundColor: 'rgba(0,0,0,0.45)', alignItems: 'center', justifyContent: 'center' }, // visible on any bg
  closeTxt: { color: 'white', fontSize: 24 },
  badge: { position: 'absolute', top: 4, left: 4, backgroundColor: '#e7ad34', borderWidth: 0.5, borderColor: 'rgba(0,0,0,0.4)', paddingHorizontal: 6, paddingVertical: 2, borderRadius: 3 },
  badgeTxt: { color: '#12363a', fontSize: 11, fontWeight: '700' },
});
