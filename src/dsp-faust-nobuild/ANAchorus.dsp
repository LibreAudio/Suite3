declare author "Klaus Scheuermann";
declare description "";
declare license "GPL-3.0-or-later";
declare name "LA Chorus";
declare unique_id "ANcs";

// declare drywet "true";

import("stdfaust.lib");

// Roland Juno-60 Stereo Chorus
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

                              I    II   I+II
    Stage Bottom Left [1]
      [11] dctr               o    o    o
      [12] ddepth             o    o    o
      [13] rate1              o    o    o
      [14] rate2              .    o    o
    Stage Bottom Right [1]
      [22] hp_freq            o    o    o
      [23] lp_freq            o    o    o
      [24] width              o    o    o
      [25] drywet             o    o    o

   rate2 is the only mode-dependent row: Chorus I runs off lfo1 alone, so the
   second LFO rate has nothing to reach there.

   drywet at 0 mutes the wet path outright and every row above goes dead — the
   plugin is a dry pass-through there. Unlike the Vocal Doubler's Dry-Wet this
   knob is not smoothed, so that holds sample-for-sample rather than only once
   the knob has settled.
*/


uiTop(x)    = hgroup("[0]Stage Top", x);
uiBottom(x) = hgroup("[8]Stage Bottom", x);
uiBottomLeft(x) = uiBottom(hgroup("[1]Stage Bottom Left", x));
uiBottomRight(x) = uiBottom(hgroup("[1]Stage Bottom Right", x));

uiMode(x)   = uiTop((hgroup("[0]Mode",  x)));
uiDelay(x)  = uiBottom(hgroup("[1]Delay", x));
uiLFO(x)    = uiBottom(hgroup("[2]LFO",   x));
uiMix(x)    = uiBottom(hgroup("[3]Mix",   x));
uiTone(x)   = uiBottom(hgroup("[4]Tone",  x));

// Pills
mode        = uiMode(nentry("[01]mode[style:radio{'I':0;'II':1;'I+II':2}][symbol:mode]", 0, 0, 2, 1)) : int;

// Parameters
dctr        = uiBottomLeft(hslider("[11]Center [style:knob][unit:ms][symbol:dctr][label:Center][accentcolor:02][bracket:DELAY]",       6.0,   1.0,  20.0,  0.1))  / 1000;
ddepth      = uiBottomLeft(hslider("[12]Depth [style:knob][unit:ms][symbol:ddepth][label:Depth][accentcolor:02][bracket:DELAY]",     3.0,   0.0,  10.0,  0.01)) / 1000;
rate1       = uiBottomLeft(hslider("[13]Rate 1[style:knob][unit:Hz][scale:log][symbol:rate1][label:Rate 1][accentcolor:03][bracket:LFO]",  0.513, 0.05, 5.0,    0.001));  // primary LFO (Hz)
rate2       = uiBottomLeft(hslider("[14]Rate 2[style:knob][unit:Hz][scale:log][symbol:rate2][label:Rate 2][accentcolor:03][bracket:LFO]",  0.863, 0.05, 5.0,    0.001));  // secondary LFO, modes II and I+II only (Hz)

hp_freq     = uiBottomRight(hslider("[22]HighPass [style:knob][unit:Hz][scale:log][symbol:hp_freq][label:HighPass][accentcolor:06][bracket:TONE]",    1,    1,   20000,  1));
lp_freq     = uiBottomRight(hslider("[23]LowPass [style:knob][unit:Hz][scale:log][symbol:lp_freq][label:LowPass][accentcolor:06][bracket:TONE]",    20000, 1,  20000, 1));

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

dryWetMixerUnity(dw, X) = _,_ <: (*(dG),*(dG)), (X : *(wG),*(wG)) :> _,_
with { dG = min(1.0, 2.0*(1.0-dw)); wG = min(1.0, 2.0*dw); };

// equal-power crossfade: both channels at -3 dB at mid position
dryWetMixer3dB(dw, X) = _,_ <: (*(dG),*(dG)), (X : *(wG),*(wG)) :> _,_
with { dG = cos(dw * ma.PI/2.0); wG = sin(dw * ma.PI/2.0); };

process = dryWetMixer3dB(drywet, chorus);

chorus(L, R) = outL, outR
with {
    mono    = L + R;

    // --- Juno modes I / II / I+II ---
    // One delay pair fed from the summed input, delay time picked per mode
    dtL     = select3(mode, dtI_L, dtII_L, dtB_L);
    dtR     = select3(mode, dtI_R, dtII_R, dtB_R);
    wL_raw  = de.fdelay(MAXN, dtL, mono);
    wR_raw  = de.fdelay(MAXN, dtR, mono);

    wL     = wL_raw : fi.svf.hp(hp_freq,0.707) : fi.svf.lp(lp_freq,0.707);
    wR     = wR_raw : fi.svf.hp(hp_freq,0.707) : fi.svf.lp(lp_freq,0.707);
    // Stereo spread: mid/side widening applied to the wet signal.
    mid    = (wL + wR) * 0.25;
    side   = (wL - wR) * 0.25;
    outL   = mid + side * width;
    outR   = mid - side * width;
};
