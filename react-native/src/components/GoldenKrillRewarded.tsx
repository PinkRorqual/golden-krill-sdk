import React, { useEffect, useRef, useState } from 'react';
import { ActivityIndicator, BackHandler, Image, Linking, Modal, Pressable, StyleSheet, Text, TouchableOpacity, View } from 'react-native';
import { GoldenKrillAds } from '../ads';
import { BADGE_INFO_URL } from '../endpoints';
import { AdItem, rewardedMs, rollAdBadge } from '../models';

export interface GoldenKrillRewardedProps {
  ads: GoldenKrillAds;
  visible: boolean;
  onClose: (earned: boolean) => void;
  /** Override the countdown; defaults to the portal's rewarded_seconds (else 10s). */
  durationMs?: number;
  /** Draw an "Ad" disclosure badge. Defaults to the portal's show_ad_badge config. */
  showBadge?: boolean;
}

/** Full-screen rewarded Modal. Picks reserve -> house (the host tries paid first, before
 *  setting visible). The countdown starts only after the image loads, blocks dismissal
 *  until complete, then the reward is earned. onClose(true) = earned, onClose(false) = none. */
export function GoldenKrillRewarded({ ads, visible, onClose, durationMs, showBadge }: GoldenKrillRewardedProps) {
  const [ad, setAd] = useState<AdItem | null>(null);
  const [badge, setBadge] = useState(false);
  const [loaded, setLoaded] = useState(false);
  const [progress, setProgress] = useState(0);
  const [done, setDone] = useState(false);
  const handled = useRef(false);
  const timer = useRef<ReturnType<typeof setInterval> | null>(null);

  useEffect(() => {
    if (!visible) {
      handled.current = false;
      setAd(null);
      setLoaded(false);
      setProgress(0);
      setDone(false);
      if (timer.current) clearInterval(timer.current);
      return;
    }
    if (handled.current) return;
    handled.current = true;
    // Per-display fetch is async: reserve (1-in-N) first, else the user-initiated house reward.
    (async () => {
      const picked = (await ads.rewardedReserve()) ?? (await ads.rewardedHouse());
      if (!picked) {
        onClose(false);
        return;
      }
      setAd(picked);
      setBadge(showBadge ?? rollAdBadge(ads.config));
    })();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [visible]);

  // Block the Android back button until the reward is earned.
  useEffect(() => {
    if (!visible) return;
    const sub = BackHandler.addEventListener('hardwareBackPress', () => !done);
    return () => sub.remove();
  }, [visible, done]);

  const startCountdown = () => {
    if (loaded) return;
    setLoaded(true);
    const total = durationMs ?? rewardedMs(ads.config);
    const tick = 100;
    let elapsed = 0;
    timer.current = setInterval(() => {
      elapsed += tick;
      const p = Math.min(1, elapsed / total);
      setProgress(p);
      if (p >= 1) {
        setDone(true);
        if (timer.current) clearInterval(timer.current);
      }
    }, tick);
  };

  if (!visible || !ad) return null;
  const openStore = () => {
    if (ad.store) Linking.openURL(ad.store).catch(() => {});
  };
  return (
    <Modal visible transparent animationType="fade" onRequestClose={() => done && onClose(true)}>
      <View style={styles.bg}>
        {!loaded && <ActivityIndicator color="white" size="large" />}
        <View style={[styles.fill, !loaded && styles.hidden]}>
          {/* Blurred copy fills behind the letterboxed creative (no crop, no dead bars). Scaled past
              cover so the gap shows only the abstract zoomed center, not recognizable cropped edges. */}
          <Image source={{ uri: ad.image }} style={[StyleSheet.absoluteFill, { transform: [{ scale: 1.3 }] }]} resizeMode="cover" blurRadius={32} />
          <View style={styles.bar}>
            <View style={[styles.barFill, { width: `${Math.round(progress * 100)}%` }]} />
          </View>
          <TouchableOpacity style={styles.center} activeOpacity={0.9} onPress={openStore} disabled={!ad.store}>
            <Image
              source={{ uri: ad.image }}
              style={styles.img}
              resizeMode="contain"
              onLoad={startCountdown}
              onError={startCountdown}
            />
          </TouchableOpacity>
          {done && (
            <Pressable style={styles.close} onPress={() => onClose(true)} accessibilityLabel="Close">
              <Text style={styles.closeTxt}>✕</Text>
            </Pressable>
          )}
          {/* Rendered last = on top, so the pill owns its tap (-> /about), not the creative below. */}
          {badge && (
            <Pressable style={styles.badge} onPress={() => Linking.openURL(ads.config.badgeUrl || BADGE_INFO_URL).catch(() => {})}>
              <Text style={styles.badgeTxt}>Powered by Golden Krill</Text>
            </Pressable>
          )}
        </View>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  bg: { flex: 1, backgroundColor: 'black', alignItems: 'center', justifyContent: 'center' },
  fill: { position: 'absolute', top: 0, left: 0, right: 0, bottom: 0 },
  hidden: { opacity: 0 },
  bar: { height: 4, backgroundColor: '#333' },
  barFill: { height: 4, backgroundColor: '#f4bd4b' },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  img: { width: '100%', height: '100%' },
  close: { position: 'absolute', top: 40, right: 20, width: 40, height: 40, borderRadius: 20, backgroundColor: 'rgba(0,0,0,0.45)', alignItems: 'center', justifyContent: 'center' }, // visible on any bg
  closeTxt: { color: 'white', fontSize: 24 },
  badge: { position: 'absolute', top: 8, left: 4, backgroundColor: '#e7ad34', borderWidth: 0.5, borderColor: 'rgba(0,0,0,0.4)', paddingHorizontal: 6, paddingVertical: 2, borderRadius: 3 },
  badgeTxt: { color: '#12363a', fontSize: 11, fontWeight: '700' },
});
