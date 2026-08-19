declare author "Klaus Scheuermann";
declare description "";
declare license "GPL-3.0-or-later";
declare name "De-Esser";
declare unique_id "LAes";

// declare drywet "true";

import("stdfaust.lib");

process = hfLimit;

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

hflim_amount = uiBottomRight(hslider("[21]De-Ess[style:knob][unit:%][symbol:deess_amount][label:De-Ess][accentcolor:02]", 0, 0, 100, 1)) / 100;
hflim_meter  = uiMeters(hbargraph("[1]HFlim Reduction[unit:dB][symbol:deess_meter]", 0, 30));


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