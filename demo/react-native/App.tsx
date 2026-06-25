// Golden Krill RN demo: three screens (banner / interstitial / rewarded), house-ads-only
// (no paid network is wired, so a paid no-fill -> a house ad always shows). A "Rotate"
// button advances the banner immediately so you don't wait for the rotation timer.
import React, { useEffect, useRef, useState } from 'react';
import { Button, Modal, Pressable, SafeAreaView, StyleSheet, Text, View } from 'react-native';
import { StatusBar } from 'expo-status-bar';
import {
  GoldenKrillAds,
  GoldenKrillBanner,
  GoldenKrillDebug,
  GoldenKrillInterstitial,
  GoldenKrillRewarded,
} from '@goldenkrill/react-native';

GoldenKrillDebug.enabled = true; // see [GoldenKrill] lines in the console

// An unknown caller id gets house-studio ads (we never send an advertising id).
const gk = new GoldenKrillAds('com.goldenkrilltest.rnshowcase');

type Tab = 'banner' | 'mrec' | 'interstitial' | 'rewarded';

export default function App() {
  const [tab, setTab] = useState<Tab>('banner');
  const [noFill, setNoFill] = useState(false);

  useEffect(() => {
    gk.ensureReady('banner');
    gk.ensureReady('mrec');
    gk.ensureReady('interstitial'); // also serves rewarded
  }, []);

  return (
    <SafeAreaView style={styles.app}>
      <StatusBar style="dark" />
      <Text style={styles.h1}>Golden Krill demo</Text>
      <View style={styles.toggleRow}>
        <Button
          title={noFill ? 'Paid: NO-FILL (house fallback)' : 'Paid: fill'}
          color={noFill ? '#b85c00' : '#1E88E5'}
          onPress={() => { demoNoFill = !demoNoFill; setNoFill(demoNoFill); }}
        />
      </View>
      <View style={styles.body}>
        {tab === 'banner' && <BannerScreen />}
        {tab === 'mrec' && <MrecScreen />}
        {tab === 'interstitial' && <InterstitialScreen />}
        {tab === 'rewarded' && <RewardedScreen />}
      </View>
      <View style={styles.tabs}>
        <Button title="Banner" onPress={() => setTab('banner')} />
        <Button title="MREC" onPress={() => setTab('mrec')} />
        <Button title="Interstitial" onPress={() => setTab('interstitial')} />
        <Button title="Rewarded" onPress={() => setTab('rewarded')} />
      </View>
    </SafeAreaView>
  );
}

// Demo toggle: when true, the simulated paid network returns no fill, so the SDK fills with
// a house ad (the fallback path). Read at tick/tap time, so no re-render is needed.
let demoNoFill = false;

// Simulated paid banner. A real app returns its AdMob banner (or null on no-fill); the SDK
// shows it on paid units and a house ad on ~1-in-N reserve units / no-fill.
async function fakePaidBanner(): Promise<React.ReactElement | null> {
  if (demoNoFill) return null; // paid no-fill -> SDK fallback (house)
  return (
    <View style={{ flex: 1, backgroundColor: '#1b2b2b', alignItems: 'center', justifyContent: 'center' }}>
      <Text style={{ color: '#9fb3b3', fontWeight: '700' }}>Paid network ad (simulated)</Text>
    </View>
  );
}

function BannerScreen() {
  const [sig, setSig] = useState(0);
  return (
    <View style={styles.screen}>
      <Text style={styles.p}>Banner rotates paid (simulated) and house ads. ~1 in {gk.config.reserveOneIn || 4} units is a house ad (reserve, from config); the gold "GK" mark shows only on those. Tap Rotate to advance now.</Text>
      <GoldenKrillBanner ads={gk} slot="banner" height={100} rotateSignal={sig} showBadge paidBuilder={fakePaidBanner} />
      <View style={styles.spacer} />
      <Button title="Rotate" onPress={() => setSig((s) => s + 1)} />
    </View>
  );
}

function MrecScreen() {
  const [sig, setSig] = useState(0);
  return (
    <View style={styles.screen}>
      <Text style={styles.p}>MREC (300x250). Same paid/house rotation as the banner; being bigger, its house unit shows a tappable "Powered by Golden Krill" pill (-> /about), not just the "GK" mark.</Text>
      <GoldenKrillBanner ads={gk} slot="mrec" width={300} height={250} rotateSignal={sig} showBadge paidBuilder={fakePaidBanner} />
      <View style={styles.spacer} />
      <Button title="Rotate" onPress={() => setSig((s) => s + 1)} />
    </View>
  );
}

// Stand-in for the host app's paid full-screen ad (the SDK never shows paid; the app does).
// Auto-dismisses after 1s so you can fast-forward and watch the 1-in-N reserve cadence.
function SimulatedPaidInterstitial({ visible, onClose }: { visible: boolean; onClose: () => void }) {
  useEffect(() => {
    if (!visible) return;
    const t = setTimeout(onClose, 1000);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [visible]);
  if (!visible) return null;
  return (
    <Modal visible transparent animationType="fade" onRequestClose={onClose}>
      <View style={styles.fsBg}>
        <Text style={styles.fsTxt}>Paid network ad (simulated, 1s)</Text>
        <Pressable style={styles.fsClose} onPress={onClose}><Text style={styles.fsCloseTxt}>✕</Text></Pressable>
      </View>
    </Modal>
  );
}

function InterstitialScreen() {
  const n = useRef(0);
  const [house, setHouse] = useState(false);
  const [paid, setPaid] = useState(false);
  const onShow = () => {
    const oneIn = gk.config.reserveOneIn || 4; // reserve frequency comes from portal config (per app)
    const reserve = n.current % oneIn === 0; // 1-in-N -> house, the rest -> paid
    n.current += 1;
    if (reserve || demoNoFill) { gk.resetSession(); setHouse(true); } else setPaid(true); // no-fill -> house (fallback)
  };
  return (
    <View style={styles.screen}>
      <Text style={styles.p}>~1 in {gk.config.reserveOneIn || 4} taps shows a house interstitial (reserve, from config); the rest are your paid network (simulated). Both close immediately.</Text>
      <Button title="Show interstitial" onPress={onShow} />
      <SimulatedPaidInterstitial visible={paid} onClose={() => setPaid(false)} />
      <GoldenKrillInterstitial ads={gk} visible={house} onClose={() => setHouse(false)} showBadge closeAfterMs={0} />
    </View>
  );
}

function RewardedScreen() {
  const n = useRef(0);
  const [house, setHouse] = useState(false);
  const [paid, setPaid] = useState(false);
  const [msg, setMsg] = useState('');
  const onShow = () => {
    setMsg('');
    const oneIn = gk.config.reserveOneIn || 4; // reserve frequency comes from portal config (per app)
    const reserve = n.current % oneIn === 0; // 1-in-N -> house rewarded, the rest -> paid
    n.current += 1;
    if (reserve || demoNoFill) { gk.resetSession(); setHouse(true); } else setPaid(true); // no-fill -> house (fallback)
  };
  return (
    <View style={styles.screen}>
      <Text style={styles.p}>~1 in {gk.config.reserveOneIn || 4} is a house rewarded (reserve, from config - countdown, then reward); the rest are your paid network (simulated, 1s). Tap fast to see the cadence.</Text>
      <Button title="Show rewarded" onPress={onShow} />
      {!!msg && <Text style={styles.result}>{msg}</Text>}
      <SimulatedPaidInterstitial visible={paid} onClose={() => { setPaid(false); setMsg('Reward earned (paid).'); }} />
      <GoldenKrillRewarded
        ads={gk}
        visible={house}
        showBadge
        onClose={(earned) => { setHouse(false); setMsg(earned ? 'Reward earned (house)!' : 'No reward.'); }}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  app: { flex: 1, backgroundColor: '#fbfaf6' },
  h1: { fontSize: 22, fontWeight: '700', textAlign: 'center', padding: 16, color: '#12363a' },
  body: { flex: 1 },
  screen: { flex: 1, padding: 20, alignItems: 'center', justifyContent: 'center' },
  p: { textAlign: 'center', color: '#444', marginBottom: 16 },
  result: { marginTop: 16, fontWeight: '700', color: '#12363a' },
  spacer: { height: 16 },
  tabs: { flexDirection: 'row', justifyContent: 'space-around', padding: 12, borderTopWidth: 1, borderTopColor: '#e5e2d8' },
  toggleRow: { alignItems: 'center', paddingBottom: 8 },
  fsBg: { flex: 1, backgroundColor: '#1b2b2b', alignItems: 'center', justifyContent: 'center' },
  fsTxt: { color: '#9fb3b3', fontWeight: '700', fontSize: 16 },
  fsClose: { position: 'absolute', top: 40, right: 20, padding: 8 },
  fsCloseTxt: { color: 'white', fontSize: 24 },
});
