declare author "Klaus Scheuermann";
declare description "";
declare license "GPL-3.0-or-later";
declare name "Chorus";
declare unique_id "LAcs";

// declare drywet "true";

import("stdfaust.lib");

// Roland Juno-60 Stereo Chorus / Roland SDD-320 Dimension D / string ensemble
//
// Emulates the MN3009 BBD (256-stage bucket-brigade) chorus circuit.
//
// Chorus I:   single LFO at ~0.513 Hz — warm, subtle stereo widening
// Chorus II:  two LFOs (~0.513 + 0.863 Hz) summed — richer, shimmering
// Chorus I+II: both switches engaged. On the hardware this puts the two
//   rate-setting networks in parallel, so the LFO jumps to ~9.75 Hz while
//   the modulation depth drops to roughly a fifth — the fast, "seasick"
//   wobble the Juno is known for, rather than a deeper version of II.
//
// Dimension D: Roland SDD-320, driven by its own four-button switch (dim).
//   Different topology from the Juno modes: one modulated copy is sent
//   anti-phase to L and R, so the wet signal sits entirely in the side
//   channel — very wide, no audible pitch wobble, and it cancels exactly
//   on a mono sum. The four buttons step modulation depth and chorus
//   amount together, 1 being barely-there widening and 4 the full effect.
//   Delay, rate and depth are fixed to the hardware, so dctr, rate1, rate2
//   and ddepth all do nothing in this mode, and neither does spread — the
//   wet is already pure side. The dim switch does nothing outside it.
//
// Ensemble: the string-machine chorus of the ARP/Solina lineage. Three BBD
//   lines driven by one three-phase LFO network 120 degrees apart, panned
//   left / right / centre. The LFO is a slow sweep with a fast shimmer summed
//   on top — that pairing is what makes an ensemble sound like several
//   detuned players rather than one doubled source, and it sweeps far wider
//   than either Juno mode: 23 cents per tap against 17. Its constants are
//   fixed to the machine as well, so dctr, ddepth, rate1 and rate2 are all
//   dead here too; spread stays live, since unlike Dimension D there is real
//   mid content to widen.
//
// Stereo spread: L and R receive opposite-polarity LFO modulation so
// the pitch drifts up on one side while it drifts down on the other,
// matching the Juno-60 circuit topology.

// --- UI ---
// Five sections side by side, each stacked vertically. The plugin's own GUI
// lays its knobs out itself and ignores this; the grouping drives the generic
// Faust UIs and, via the [n] prefixes, the order of the generated parameter
// list — which is why the sections follow the signal flow rather than the
// alphabetical order Faust falls back to for an ungrouped DSP.

/* Grey-out list — which controls actually reach the output, per mode.
   Verified by measurement, not by reading: '.' means the rendered output is
   bit-identical with the control at either end of its range, so the UI can
   disable it there with no audible consequence.

   Rows follow the order the controls appear in the UI, listed with the [n]
   index each one declares, groups themselves in index order. One tie means the
   indices alone do not settle that order: Stage Bottom Left and Stage Bottom
   Right both declare [1]. The order below is the one the generated UI actually
   produces, with Left ahead of Right.

                              I    II   I+II  Dim D  Ens
    Mode [0]
      [02] stereo             o    o    o     o      o
    Stage Bottom Left [1]
      [11] dctr               o    o    o     .      .
      [12] ddepth             o    o    o     .      .
      [13] rate1              o    o    o     .      .
      [14] rate2              .    o    o     .      .
      [15] dim                .    .    .     o      .
      [16] detune            ts   ts   ts    ts     ts
    Stage Bottom Right [1]
      [21] deess_amount       o    o    o     o      o
      [22] hp_freq            o    o    o     o      o
      [23] lp_freq            o    o    o     o      o
      [24] width              o    o    o     .      o
      [25] drywet             o    o    o     o      o

   Dimension D and Ensemble are fixed-constant machine emulations, which is why
   both DELAY controls and both LFO rates go dead in them — of the whole Stage
   Bottom Left group only dim and detune reach the output there.
   width survives in Ensemble but not Dimension D: the latter's wet signal
   is already pure side, so widening has nothing to act on.

   ts  detune is the one control whose condition is not the mode at all: it
      reaches only the true-stereo signal paths, so it is live in all five modes
      with Stereo on True Stereo and inert in all five on Mono.

   deess_amount is live in every mode because it sits in the shared wet feed
   ahead of the mode select rather than inside any one mode.

   drywet at 0 mutes the wet path outright and every row above goes dead — the
   plugin is a dry pass-through there. Unlike the Vocal Doubler's Dry-Wet this
   knob is not smoothed, so that holds sample-for-sample rather than only once
   the knob has settled.
*/


uiTop(x)    = hgroup("[0]Stage Top", x);
uiBottom(x) = hgroup("[8]Stage Bottom", x);
uiBottomLeft(x) = uiBottom(hgroup("[1]Stage Bottom Left", x));
uiBottomRight(x) = uiBottom(hgroup("[1]Stage Bottom Right", x));
uiMeters(x) = hgroup("[9]", x);

uiMode(x)   = uiTop((hgroup("[0]Mode",  x)));
uiDelay(x)  = uiBottom(hgroup("[1]Delay", x));
uiLFO(x)    = uiBottom(hgroup("[2]LFO",   x));
uiMix(x)    = uiBottom(hgroup("[3]Mix",   x));
uiTone(x)   = uiBottom(hgroup("[4]Tone",  x));
uiDeEss(x)  = uiBottom(hgroup("[5]De-Esser", x));

// Pills
mode        = uiMode(nentry("[01]mode[style:radio{'Juno I':0;'Juno II':1;'Juno I+II':2;'Dimension D':3;'Ensemble':4}][symbol:mode]", 0, 0, 4, 1)) : int;
true_stereo = uiMode(nentry("[02]stereo[style:radio{'Mono':0;'True Stereo':1}][symbol:stereo]", 0, 0, 1, 1)) : int;

// Parameters
dctr        = uiBottomLeft(hslider("[11]Center [style:knob][unit:ms][symbol:dctr][label:Center][accentcolor:02][bracket:DELAY]",       6.0,   1.0,  20.0,  0.1))  / 1000;
ddepth      = uiBottomLeft(hslider("[12]Depth [style:knob][unit:ms][symbol:ddepth][label:Depth][accentcolor:02][bracket:DELAY]",     3.0,   0.0,  10.0,  0.01)) / 1000;
rate1       = uiBottomLeft(hslider("[13]Rate 1[style:knob][unit:Hz][scale:log][symbol:rate1][label:Rate 1][accentcolor:03][bracket:LFO]",  0.513, 0.05, 5.0,    0.001));  // primary LFO (Hz)
rate2       = uiBottomLeft(hslider("[14]Rate 2[style:knob][unit:Hz][scale:log][symbol:rate2][label:Rate 2][accentcolor:03][bracket:LFO]",  0.863, 0.05, 5.0,    0.001));  // secondary LFO, modes II and I+II only (Hz)

dim         = uiBottomLeft(hslider("[15]Dim-D[style:knob][symbol:dim][label:Dimension][accentcolor:02]", 1, 1, 4, 1)) -1 : int; // SDD-320 four-button switch, Dimension D mode only

detune      = uiBottomLeft(hslider("[16]Detune [style:knob][unit:%][symbol:detune][label:Detune][accentcolor:02]",      5.0,   0.0,  50.0,  0.1))  / 100;   // LFO rate detune between L/R instances (true stereo)

hflim_amount = uiBottomRight(hslider("[21]De-Ess[style:knob][unit:%][symbol:deess_amount][label:De-Ess][accentcolor:02]", 0, 0, 100, 1)) / 100;
hflim_meter  = uiMeters(hbargraph("[1]HFlim Reduction[unit:dB][symbol:deess_meter]", 0, 30));

hp_freq     = uiBottomRight(hslider("[22]HighPass [style:knob][unit:Hz][scale:log][symbol:hp_freq][label:HighPass][accentcolor:06][bracket:TONE]",    20,    20,   20000,  1));
lp_freq     = uiBottomRight(hslider("[23]LowPass [style:knob][unit:Hz][scale:log][symbol:lp_freq][label:LowPass][accentcolor:06][bracket:TONE]",    20000, 20,  20000, 1));

width       = uiBottomRight(hslider("[24]Width [style:knob][unit:%][symbol:width][accentcolor:04][label:Width]",     100.0,   0.0, 200.0,  1.0))  / 100;  // stereo width: 0% mono, 100% unmodified, 200% double width
drywet      = uiBottomRight(hslider("[25]Dry-Wet [style:knob][unit:%][symbol:drywet][label:Dry-Wet][accentcolor:01][easy]",50,0,100,1)) / 100;


MAXN = 1 << 17;    // delay buffer size in samples

// Delay time in samples, clamped to >= 1
samp(t) = max(1.0, t * float(ma.SR));

// Both switches down: the rate networks end up in parallel, so the LFO
// frequencies add and the whole circuit speeds up dramatically while the
// swept depth shrinks. Scaled off the two rate controls so they stay live
// in this mode; with the stock rates this lands at ~9.75 Hz.
BOTH_RATE_SCALE  = 7.087;   // (0.513 + 0.863) * 7.087 ~= 9.75 Hz
BOTH_DEPTH_SCALE = 0.2;

rateB   = min(20.0, (rate1 + rate2) * BOTH_RATE_SCALE);
ddepthB = ddepth * BOTH_DEPTH_SCALE;

// --- LFOs ---
lfo1 = os.osc(rate1);
lfo2 = os.osc(rate2);
lfoB = os.osc(rateB);

// Chorus I: single LFO, L/R polarity inverted for stereo spread
dtI_L = samp(dctr + lfo1 * ddepth);
dtI_R = samp(dctr - lfo1 * ddepth);

// Chorus II: two-LFO sum, cross-mixed between channels for shimmer
// Left gets  (+lfo1 + lfo2), right gets (-lfo1 + lfo2)
// The 0.5 factor keeps total depth the same as Chorus I
dtII_L = samp(dctr + ( lfo1 + lfo2) * ddepth * 0.5);
dtII_R = samp(dctr + (-lfo1 + lfo2) * ddepth * 0.5);

// Chorus I+II: single fast LFO, shallow, opposite polarity per channel
dtB_L = samp(dctr + lfoB * ddepthB);
dtB_R = samp(dctr - lfoB * ddepthB);

// True stereo: two detuned instances, one per channel
// Instance A processes L (rates detuned down), instance B processes R (rates detuned up)
// Their stereo outputs are summed back to a stereo pair
lfo1_a = os.osc(rate1 * (1 - detune));
lfo1_b = os.osc(rate1 * (1 + detune));
lfo2_a = os.osc(rate2 * (1 - detune));
lfo2_b = os.osc(rate2 * (1 + detune));
lfoB_a = os.osc(rateB * (1 - detune));
lfoB_b = os.osc(rateB * (1 + detune));

tsI_LL = samp(dctr + lfo1_a * ddepth);
tsI_LR = samp(dctr - lfo1_a * ddepth);
tsI_RL = samp(dctr + lfo1_b * ddepth);
tsI_RR = samp(dctr - lfo1_b * ddepth);

tsII_LL = samp(dctr + ( lfo1_a + lfo2_a) * ddepth * 0.5);
tsII_LR = samp(dctr + (-lfo1_a + lfo2_a) * ddepth * 0.5);
tsII_RL = samp(dctr + ( lfo1_b + lfo2_b) * ddepth * 0.5);
tsII_RR = samp(dctr + (-lfo1_b + lfo2_b) * ddepth * 0.5);

tsB_LL = samp(dctr + lfoB_a * ddepthB);
tsB_LR = samp(dctr - lfoB_a * ddepthB);
tsB_RL = samp(dctr + lfoB_b * ddepthB);
tsB_RR = samp(dctr - lfoB_b * ddepthB);

// --- Dimension D ---
// Delay, rate and depth are all fixed to the hardware rather than taken from
// the Juno controls: the SDD-320 has none of those knobs, only the four
// buttons, which step depth and chorus amount together. dctr, rate1, rate2
// and ddepth therefore do nothing in this mode, leaving it entirely
// self-contained.
//
// The sweep is far shallower than the Juno's. Measured on a 1 kHz tone the
// four buttons give a peak pitch deviation of 1.1 / 2.2 / 3.3 / 4.4 cents,
// against 17 cents for Chorus I at its defaults — that gap is what keeps
// the mode free of audible wobble.
DIM_DELAY      = 0.005;    // s, fixed delay centre (1024-stage BBD, ~100 kHz clock)
DIM_RATE       = 0.5;      // Hz, fixed LFO, same for all four buttons
DIM_DEPTH_BASE = 0.0002;   // 0.2 ms peak deviation on button 1
DIM_DEPTH_STEP = 0.0002;   // +0.2 ms per button, up to 0.8 ms on button 4

ddepthD  = DIM_DEPTH_BASE + dim * DIM_DEPTH_STEP;
dimMix   = 1; // (all dim 1-4 result in same volume. Old line: dimMix = 0.4 + dim * 0.2;  // 40 / 60 / 80 / 100 %

lfoD   = os.osc(DIM_RATE);
lfoD_a = os.osc(DIM_RATE * (1 - detune));
lfoD_b = os.osc(DIM_RATE * (1 + detune));

// True stereo gives each input channel its own BBD, the pair modulated in
// opposite phase as on the hardware and detuned against each other by the
// shared detune control. Both feed the same anti-phase output stage, so the
// mono cancellation survives either way.
dtD   = samp(DIM_DELAY + lfoD * ddepthD);
tsD_L = samp(DIM_DELAY + lfoD_a * ddepthD);
tsD_R = samp(DIM_DELAY - lfoD_b * ddepthD);

// --- Ensemble ---
// String-machine ensemble (ARP/Solina lineage): three BBD lines fed from one
// three-phase LFO network, 120 degrees apart. The LFO is a slow sweep plus a
// fast shimmer summed together — that pairing is what separates an ensemble
// from a chorus, and why it sounds like several detuned players rather than
// one doubled source.
//
// Like Dimension D this is a machine with no front-panel controls, so its
// constants are fixed here and dctr, ddepth, rate1 and rate2 do nothing.
ENS_DELAY      = 0.005;    // s, delay centre
ENS_RATE_SLOW  = 0.6;      // Hz, the slow sweep
ENS_RATE_FAST  = 6.0;      // Hz, the shimmer riding on top
ENS_DEPTH_SLOW = 0.0015;   // s peak, ~10 cents on its own
ENS_DEPTH_FAST = 0.0002;   // s peak, ~13 cents on its own
ENS_GAIN       = 1.03;     // level-matches the three summed taps to the Juno modes

// Tap j of 3. detune pulls the two outer taps apart in true stereo, which
// breaks the exact 120-degree lock and widens the swirl; with it off the three
// phases stay locked, as on the hardware. The sign follows the tap's
// destination — outer taps opposite, centre tap untouched — so the two output
// channels stay level-matched.
ensK(j)   = 1 + ba.take(j + 1, (-1.0, 1.0, 0.0)) * detune * true_stereo;
ensPh(j)  = j * 2.0 * ma.PI / 3.0;
ensMod(j) = os.oscp(ENS_RATE_SLOW * ensK(j), ensPh(j)) * ENS_DEPTH_SLOW
          + os.oscp(ENS_RATE_FAST * ensK(j), ensPh(j)) * ENS_DEPTH_FAST;
ensDt(j)  = samp(ENS_DELAY + ensMod(j));

// --- High Frequency Limiter ---
// Ported from vocalDoubler.dsp. Feeds the wet path only — it sits inside the
// dry/wet mixer's wet branch, so the dry half always passes through
// untouched and this can never dull the original signal.
//
// Level-independent: splits the input into a low ("body") band and a
// high band, then compares their envelopes as a ratio (dB difference)
// instead of the high band's absolute level. A quiet "s" in a quiet
// passage still spikes that ratio, so detection doesn't depend on overall
// loudness the way a plain high-band compressor does.

// One macro control drives all four parameters. To retune the feel, edit
// the endpoint pairs below: the first value is what the parameter is at
// Intensity 0%, the second at 100%, interpolated linearly in between.
// Nothing else needs touching.
hfLimSplitAt0  = 5000;  hfLimSplitAt100  = 4500;  // Hz   - crossover; lower reaches further down into the "sh" range
hfLimThreshAt0 =   -2;  hfLimThreshAt100 =   -14; // dB   - how far the high band must stick out before it counts
hfLimRatioAt0  =    2;  hfLimRatioAt100  =     8; //      - how hard the excess is squeezed
hfLimRangeAt0  =    0;  hfLimRangeAt100  =    18; // dB   - ceiling on total reduction; 0 at the bottom makes 0% a true bypass

lerp(a, b, t) = a + (b - a) * t;

// Defaults to 0, i.e. a true bypass, because a chorus is not a vocal-only
// box — every existing patch keeps sounding exactly as it did until this is
// turned up. (vocalDoubler ships it at 50.)


hflim_split  = lerp(hfLimSplitAt0,  hfLimSplitAt100,  hflim_amount);
hflim_thresh = lerp(hfLimThreshAt0, hfLimThreshAt100, hflim_amount);
hflim_ratio  = lerp(hfLimRatioAt0,  hfLimRatioAt100,  hflim_amount);
hflim_range  = lerp(hfLimRangeAt0,  hfLimRangeAt100,  hflim_amount);

// Stereo, unlike the mono original. Detection is *linked*: one gain, derived
// from the mono sum, drives both channels. Two independent detectors would
// duck the channels by different amounts on the same sibilant and swing the
// stereo image with every "s" — the one thing a widener must not do.
hfLimit(l, r) = attach(outL, reductionDb : hflim_meter), outR
with {
    lowL  = fi.lowpass(4, hflim_split, l);
    lowR  = fi.lowpass(4, hflim_split, r);
    highL = l - lowL; // complementary split: low+high reconstructs the input exactly at unity gain
    highR = r - lowR;

    // The split is linear, so summing the two channels' bands is identical to
    // running the filter on the mono sum — and one 4th-order pass cheaper.
    low  = (lowL  + lowR)  * 0.5;
    high = (highL + highR) * 0.5;

    hiDb  = high : an.amp_follower_ar(0.001, 0.03) : ba.linear2db;
    refDb = low  : an.amp_follower_ar(0.001, 0.03) : ba.linear2db;

    // dB the high band sticks out above the body band, relative to normal
    // voice spectral tilt; only the excess over threshold is limited
    diff   = hiDb - refDb;
    excess = max(0, diff - hflim_thresh);

    reductionDb = min(excess * (1 - 1 / hflim_ratio), hflim_range);
    gr = ba.db2linear(0 - reductionDb);

    outL = lowL + highL * gr;
    outR = lowR + highR * gr;
};

dryWetMixerUnity(dw, X) = _,_ <: (*(dG),*(dG)), (X : *(wG),*(wG)) :> _,_
with { dG = min(1.0, 2.0*(1.0-dw)); wG = min(1.0, 2.0*dw); };

// equal-power crossfade: both channels at -3 dB at mid position
dryWetMixer3dB(dw, X) = _,_ <: (*(dG),*(dG)), (X : *(wG),*(wG)) :> _,_
with { dG = cos(dw * ma.PI/2.0); wG = sin(dw * ma.PI/2.0); };

// The limiter sits ahead of the chorus inside the wet branch, so the delay
// lines are fed already-tamed material rather than de-essing the swirl after
// the fact — a sibilant smeared across three BBD taps is much harder to catch.
process = dryWetMixer3dB(drywet, hfLimit : chorus);

chorus(L, R) = outL, outR
with {
    mono    = L + R;
    juno    = mode < 3;
    dimD    = mode == 3;
    jmode   = min(mode, 2);   // clamp so the Juno selects stay in range

    // --- Juno modes I / II / I+II ---
    // Mono path: single delay pair, delay time picked per mode
    dtL_m   = select3(jmode, dtI_L, dtII_L, dtB_L);
    dtR_m   = select3(jmode, dtI_R, dtII_R, dtB_R);
    wL_m    = de.fdelay(MAXN, dtL_m, mono);
    wR_m    = de.fdelay(MAXN, dtR_m, mono);

    // True stereo path: same topology in every mode, so select the delay
    // times first and run a single set of four delay lines
    dt_LL   = select3(jmode, tsI_LL, tsII_LL, tsB_LL);
    dt_LR   = select3(jmode, tsI_LR, tsII_LR, tsB_LR);
    dt_RL   = select3(jmode, tsI_RL, tsII_RL, tsB_RL);
    dt_RR   = select3(jmode, tsI_RR, tsII_RR, tsB_RR);
    wL_ts   = de.fdelay(MAXN, dt_LL, L) + de.fdelay(MAXN, dt_RL, R);
    wR_ts   = de.fdelay(MAXN, dt_LR, L) + de.fdelay(MAXN, dt_RR, R);

    wL_juno = select2(true_stereo, wL_m, wL_ts);
    wR_juno = select2(true_stereo, wR_m, wR_ts);

    // --- Dimension D ---
    // A single modulated copy sent anti-phase to L and R, so the wet ends
    // up purely in the side channel and cancels exactly on a mono sum.
    // Mono path takes the summed input, true stereo takes one BBD per
    // channel; both feed the same amount of signal into the output stage.
    wD_m    = de.fdelay(MAXN, dtD, mono);
    wD_ts   = de.fdelay(MAXN, tsD_L, L) + de.fdelay(MAXN, tsD_R, R);
    wD      = select2(true_stereo, wD_m, wD_ts) * dimMix;

    wL_dim  = wD;
    wR_dim  = 0.0 - wD;

    // --- Ensemble ---
    // Three taps panned left / right / centre. In true stereo the outer taps
    // take one input channel each and the centre tap the sum, which keeps the
    // line count at three either way.
    ensIn0  = select2(true_stereo, mono, L);
    ensIn1  = select2(true_stereo, mono, R);
    e0      = de.fdelay(MAXN, ensDt(0), ensIn0);
    e1      = de.fdelay(MAXN, ensDt(1), ensIn1);
    e2      = de.fdelay(MAXN, ensDt(2), mono);
    wL_ens  = (e0 + e2 * 0.5) * ENS_GAIN;
    wR_ens  = (e1 + e2 * 0.5) * ENS_GAIN;

    wL_raw = select2(juno, select2(dimD, wL_ens, wL_dim), wL_juno);
    wR_raw = select2(juno, select2(dimD, wR_ens, wR_dim), wR_juno);
    wL     = wL_raw : fi.svf.hp(hp_freq,0.707) : fi.svf.lp(lp_freq,0.707);
    wR     = wR_raw : fi.svf.hp(hp_freq,0.707) : fi.svf.lp(lp_freq,0.707);
    // outL   = L * dry + wL * wet;
    // outR   = R * dry + wR * wet;
    // Stereo spread: mid/side widening applied to the wet signal.
    // Dimension D puts its whole wet signal in the side channel, so spread
    // would not widen it — it would just ride its level, and mute it at 0%.
    // Pinned to unity there; every other mode has real mid content to widen.
    width_eff = select2(dimD, width, 1.0);
    mid    = (wL + wR) * 0.25;
    side   = (wL - wR) * 0.25;
    outL   = mid + side * width_eff;
    outR   = mid - side * width_eff;
};

