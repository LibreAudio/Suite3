// -*-Faust-*-

declare author "Klaus Scheuermann after Daniel Leonov and faust standard library";
declare description "";
declare license "GPL-3.0-or-later";
declare name "Spring Reverb";
declare unique_id "LAsr";

import("stdfaust.lib");


// UI

ui_main(x) = hgroup("main",x);

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

predelay_time = uiBottomLeft(vslider("[0] Predelay [style:knob][unit:ms][symbol:predelay][label:Predelay][accentcolor:05]",0,0,500,1) * ma.SR /1000);

dwell   = uiBottomLeft(vslider("[1] Dwell [style:knob][unit:%][symbol:dwell][label:Dwell][accentcolor:01][bracket:SPRING]", 50, 0, 100, 1)) /100;
tension = uiBottomLeft(vslider("[2] Tension [style:knob][unit:%][symbol:tension][label:Tension][accentcolor:02][bracket:SPRING]", 50, 0, 100, 1)) /100;
tone    = uiBottomLeft(vslider("[3] Tone [style:knob][unit:%][symbol:tone][label:Tone][accentcolor:03]", 0.4, 0, 1, 0.01));

// One knob, driving threshold/ratio/range/attack/release together. See the
// ducker section at the foot of the file for what each endpoint pair does.
duck_amount = uiBottomRight(vslider("[6] Duck [style:knob][unit:%][symbol:duck_amount][label:Duck][accentcolor:04][bracket:DUCK]", 0, 0, 100, 1)) / 100;
duck_meter  = uiMeters(hbargraph("[0] Duck GR [unit:dB][symbol:duck_meter][label:Duck GR][accentcolor:04][bracket:DUCK]", 0, 18));

volL = 1; //uiBottomRight(vslider("[5]Spring L [style:knob][unit:dB][symbol:Left][label:volL][accentcolor:04][bracket:SPRINGS]",0,-60,0,1)) : ba.db2linear;
volC = uiBottomLeft(vslider("[4]Spring C [style:knob][unit:dB][symbol:Center][label:volC][accentcolor:04][bracket:SPRINGS]",-60,-60,0,1)) : ba.db2linear;
volR = 1; //uiBottomRight(vslider("[7]Spring R [style:knob][unit:dB][symbol:Right][label:volR][accentcolor:04][bracket:SPRINGS]",0,-60,0,1)) : ba.db2linear;

// Mid/side trim on the wet signal only, applied after the springs and the
// pre-delay. Smoothed off its own default so the 100% start-up value does not
// ramp in from zero.
width = uiBottomRight(vslider("[8]Width [style:knob][unit:%][symbol:stereo_width][label:Width][accentcolor:05][bracket:MIXER]", 100, 0, 200, 1)) / 100 : smoo(1.0);

// Ported from vocalDoubler.dsp. Feeds the wet path only — see the de-esser
// section at the foot of the file.
hflim_amount = uiBottomRight(vslider("[7] De-Ess [style:knob][unit:%][symbol:deess_amount][label:De-Ess][accentcolor:02][bracket:DE-ESS]", 0, 0, 100, 1)) / 100;
hflim_meter  = uiMeters(hbargraph("[1] De-Ess GR [unit:dB][symbol:deess_meter][label:De-Ess GR][accentcolor:02][bracket:DE-ESS]", 0, 18));


crossfeed = uiBottomRight(vslider("[5]crossfeed [style:knob][unit:%][symbol:crossLR][label:Crossfeed][accentcolor:05][bracket:MIXER]", 0,0,100,1)) / 100;
// Dry/wet balance on one knob, ported from vocalDoubler.dsp. At 0 both paths
// pass at unity; turning toward Wet pulls the dry down, toward Dry pulls the
// wet down. Only one side ever moves — this is a dry-kill fade, not a
// crossfade, so the sum runs up to ~6 dB hotter at centre than at either end.
//
// The taper is linear in *amplitude* — the usual mix-knob feel — so half travel
// is -6 dB on the receding path rather than half of some dB range, which would
// already be inaudible well before the knob got there. The floor keeps
// linear2db out of -inf; at -120 dB it sits below faderMinDb, so both ends of
// the travel trip the mute test and silence that path outright instead of
// leaving a residue.
faderMinDb = -70;
faderGain(db) = ba.db2linear(db) * (db > faderMinDb);

mix = uiBottomRight(vslider("[9]Dry-Wet[style:knob][unit:%][symbol:mix][label:Dry-Wet][accentcolor:06][bracket:MIXER][easy]", 0, -100, 100, 0.1)) / 100 : si.smoo;

mixAttenDb(amount) = ba.linear2db(max(0.000001, 1 - amount));

mixDry = faderGain(mixAttenDb(max(0, mix)));
mixWet = faderGain(mixAttenDb(max(0, 0 - mix)));


// in --+------------------------- dry ------> * mixDry --+--> out
//      |                                                   |
//      +--> deess --+--> springs --> width --> duck --> * mixWet
//                   |                           ^
//                   +-------- key (mono) -------+
//
// The de-esser sits at the head of the WET path only, so the dry half always
// passes through untouched and this can never dull the original signal.
//
// The ducker makes TWO PLACEMENT DECISIONS, pointing in opposite directions
// on purpose.
//
// The KEY is tapped straight after the de-esser and ahead of everything else —
// including the pre-delay inside springreverb_stereo — so the duck follows the
// source rather than a delayed copy of it. Being after the de-esser means a
// tamed sibilant no longer triggers the duck as hard, which is the point of
// keying post-filter.
//
// The REDUCTION is applied as late as possible, on the finished wet signal
// after Width. Ducking the delay lines' input instead would not work: the
// feedback loop integrates what it was fed over seconds, so it would go on
// ringing with material from before the duck began and the gain change would
// arrive smeared across the whole tail rather than on it.
//
// The dry path hangs off the plugin input, upstream of all of this, so the
// source never ducks itself.
process = _,_ <: (dryside, wetside) :> _,_
with {
    dryside = par(i, 2, *(mixDry));
    wetside = hfLimit : wetpath : par(i, 2, *(mixWet));
};

wetpath = _,_ <: (springreverb_stereo : stereoWidth(width)), keymono : duckapply;

keymono(a, b) = (a + b) * 0.5;

// predelay
predelay = par(i,2,de.sdelay(192000,1024,predelay_time));


springreverb_stereo(l,r) = 
                            (l + (r*crossfeed) : (_ * ((-6 * crossfeed) : ba.db2linear)) : (spring(dwell, 10, tone, tension, 0) * volL)), 
                            (r + (l*crossfeed) : (_ * ((-6 * crossfeed) : ba.db2linear)) : (spring(dwell, 10, tone, tension, 1)* volR)),
                            (((l+r)*0.5) : (spring(dwell, 10, tone, tension, 2) * volC <: _,_))
                            :> _,_ : predelay
;


spring(dwell_aux, blend_aux, tone_aux, tension_aux, springs) =
    reverb
with {
    sample_rate_hz = ma.SR;  // For plugins 

    // Parameter remapping from external [0..1] to internal [0..10]
    dwell = dwell_aux * 10;
    //blend = blend_aux * 10;
    tone = tone_aux * 10;
    tension = tension_aux * 10;

    clamp(x, lo, hi) = max(lo, min(hi, x));  // Enforce UI-style parameter limits when called from the library

    dwell_ctrl = clamp(dwell, 0, 10);
    //blend_ctrl = clamp(blend, 0, 10);
    tone_ctrl = clamp(tone, 0, 10);
    tension_ctrl = clamp(tension, 0, 10);
    springs_index = clamp(round(springs), 0, 2);  // Mirror original UI bounds to keep fits/stability safe

    // Quadratic fit from original dwell sweep measurements.
    // Sweep: ({0.0, 0.26}, {5.0, 0.31}, {10.0, 0.33})
    // https://www.wolframalpha.com/input?i=quadratic+fit+calculator&assumption=%7B%22F%22%2C+%22QuadraticFitCalculator%22%2C+%22data%22%7D+-%3E%22%28%7B0.0%2C+0.26%7D%2C+%7B5.0%2C+0.31%7D%2C+%7B10.0%2C+0.33%7D%29%22
    feedback_gain_linear = dwell_ctrl * (-0.0006 * dwell_ctrl + 0.013) + 0.26;
    //wet_gain_linear = blend_ctrl * 0.08;  // Kept linear to save CPU

    // "Tone"
    // Affects only wet signal, aplies some makeup gain to compensate for lost HF energy
    // Sweep: ({0.0, 1500}, {5.0, 6000}, {10.0, 20000})
    // https://www.wolframalpha.com/input?i=quadratic+fit+calculator&assumption=%7B%22F%22%2C+%22QuadraticFitCalculator%22%2C+%22data%22%7D+-%3E%22%28%7B0.0%2C+1500%7D%2C+%7B5.0%2C+6000%7D%2C+%7B10.0%2C+20000%7D%29%22
    lowpass_freq_hz = tone_ctrl * (190 * tone_ctrl + 50) + 1500;
    makeup_gain = 0.5 * min(5, 1 + 2000 / lowpass_freq_hz);  // Protect against extreme HF loss

    // "Tension"
    // Affects base delay time of main delay lines. Higher delays result in more lush sound, but with noticeable predelay.
    // Lower values result in less diffused sound. This control feels like changing tightness of the springs, although I have no idea if real world spring reverbs would react to tension this way. But who cares.
    // It affects the tail length, along with "Dwell" control.
    // Sweep: ({0.0, 0.07}, {5.0, 0.042}, {10.0, 0.03})
    // https://www.wolframalpha.com/input?i=quadratic+fit+calculator&assumption=%7B%22F%22%2C+%22QuadraticFitCalculator%22%2C+%22data%22%7D+-%3E%22%28%7B0.0%2C+0.07%7D%2C+%7B5.0%2C+0.042%7D%2C+%7B10.0%2C+0.03%7D%29%22
    base_spring_delay_s = tension_ctrl * (0.00032 * tension_ctrl - 0.0072) + 0.07;
    spread = spread_choice(springs_index);

    diffusion_delay_max_samples = 0.035 * sample_rate_hz : round;  // Should be large enough to accomodate largest delay length returned by diffusion_delay_samples()
    spring_delay_max_samples = 0.08 * sample_rate_hz : round;  // Should be >= than largest value returned by spring_delay_samples()
    spring_comb_filter_delay_max_samples = 0.13 * sample_rate_hz : round;  // Should be >= than largest value returned by spring_comb_filter_delay_samples()
    
    N = 8;  // Number of diffusion and delay lines

    // Calculates delay time in samples for each delay line
    // min_..max_ - target delay time range in seconds
    // bins - number of bins (intervals) in that delay range, each parallel bus line is working on it its own bin
    // bin - number of the bin
    diffusion_delay_samples(min_, max_, bin, bins) =
        abs(min_ + ((max_ - min_) / bins) * bin) * sample_rate_hz : round;

    // Initial diffusion. Long enough to sound like a reverb instead of slapback delay,
    // but short enough to not smear the "springiness" of the reverb that comes after it.
    // The delay lengths are pretty arbitrary here.
    diffusion =
        par(i, N, de.delay(diffusion_delay_samples(0.05, 0.020, i, 8), diffusion_delay_max_samples))
        : ro.hadamard(N)
        : polarity_flips_a
        : par(i, N, de.delay(diffusion_delay_samples(0.009, 0.030, i, N), diffusion_delay_max_samples))
        : ro.hadamard(N)
        : polarity_flips_b
        : par(i, N, de.delay(diffusion_delay_samples(0.010, 0.025, i, N), diffusion_delay_max_samples))
        : ro.hadamard(N)
        : polarity_flips_c
        : par(i, N, de.delay(diffusion_delay_samples(0.009, 0.032, i, N), diffusion_delay_max_samples))
    with {
        // Polarity flips add subtle decorrelation between parallel paths (optional in original).
        polarity_flips_a = _, *(-1), _, _, *(-1), _, *(-1), *(-1);  // 2 5 6 7
        polarity_flips_b = *(-1), _, _, *(-1), _, _, _, *(-1);      // 1 4 8
        polarity_flips_c = _, *(-1), *(-1), _, _, _, *(-1), _;      // 2 3 7
    };

    // Basic building block for delay lines
    // Replacing generic LPF with a ve.lowpassLadder4(1, lp) sounds cool, but hard to dial in for the entire "Tone" knob range
    // and more CPU intensive (extra 5% CPU or so), but worth exploring in the future.
    spring(d, lp) = de.delay(spring_delay_max_samples, d) : fi.lowpass(1, lp);

    spring_delay_samples(i) =
        (base_spring_delay_s + ba.take(i + 1, offsets) * spread) * sample_rate_hz : round
    with {
        // Prime offsets give a lively set of inharmonic spring modes.
        // String-mode-ish detuned sets also worked but were less springy (e.g. 1, 1.002, 1.003, 1.00, 2, 2.0001, 1.50002, 3.00).
        offsets = 1, 2, 3, 5, 7, 11, 13, 17;
    };

    // This is meat and potatoes of this reverb. I've found this design with those timings to have the best "springy" character.
    // fi.fb_comb() before clipper (but after feedback loops) adds some extra funkiness on top, with similar delays to the main feedback delays.
    // Like this: fi.fb_comb (spring_comb_filter_delay_max_samples, spring_comb_filter_delay_samples (i), 0.9, 0.1).
    delay_lines = par(i, N, spring(spring_delay_samples(i), lowpass_freq_hz) : aa.hardclip);

    // Introduces crosstalk between indicidual channels, so instead of
    // having N individual feedback loops, we have one multi-channel loop.
    feedback_lines = ro.hadamard(N) : par(i, N, *(feedback_gain_linear));

    // Diffuse -> Delay lines with feedback loop.
    reverb = *(0.01) <: diffusion
        : (si.bus(N * 2) :> delay_lines) ~ (feedback_lines)
        :> fi.highpass(1, 150) : *(makeup_gain);

    spread_choice(idx) = ba.if(idx == 0, 0.2e-5, ba.if(idx == 1, 5.0e-4, 2.8e-5));
};


//======================== helpers ============================================
// si.smoo ramps from zero, which is audible on a control whose default is not
// zero. Smoothing the offset from the default instead starts the filter where
// the knob already is.
smoo(dflt, x) = (x - dflt) : si.smoo : +(dflt);
lerp(a, b, t) = a + (b - a) * t;


//======================== stereo width =======================================
// Mid/side trim: 0% collapses to mono, 100% passes through untouched, 200%
// cancels the centre. Sits on the wet signal only.
stereoWidth(w) = _,_ <: (*(a),*(b) :> _), (*(b),*(a) :> _)
with {
    a = 0.5 * (1 + w);
    b = 0.5 * (1 - w);
};


//======================== ducker =============================================
// One knob. It pushes the finished reverb down while the source is playing and
// lets it swell back in the gaps — the oldest trick for keeping a long tail
// from burying the thing that caused it.
//
// To retune the feel, edit the endpoint pairs below: the first value is what
// the parameter is at Duck 0%, the second at 100%, interpolated linearly in
// between.
duckThreshAt0 = -12;    duckThreshAt100 = -40;    // dB
duckRatioAt0  = 1.0;    duckRatioAt100  = 8.0;
duckRangeAt0  = 0;      duckRangeAt100  = 18;     // dB, ceiling on the duck
duckAttAt0    = 0.005;  duckAttAt100    = 0.002;  // s, fast: catch the onset
// Release SHORTENS as the knob advances, which is the opposite of the obvious
// choice. Lengthening it with Amount seems natural — deeper duck, gentler
// return — but it compounds: at 18 dB of duck with a 400 ms release the tail is
// still most of the way down half a second into a silent gap, so the reverb
// never actually comes back and the effect reads as a mute rather than a duck.
// 150 ms at the top recovers inside a normal gap between phrases while still
// being far too slow to chatter.
duckRelAt0    = 0.300;  duckRelAt100    = 0.150;  // s

duck_thresh = lerp(duckThreshAt0, duckThreshAt100, duck_amount);
duck_ratio  = lerp(duckRatioAt0,  duckRatioAt100,  duck_amount);
duck_range  = lerp(duckRangeAt0,  duckRangeAt100,  duck_amount);
duck_att    = lerp(duckAttAt0,    duckAttAt100,    duck_amount);
duck_rel    = lerp(duckRelAt0,    duckRelAt100,    duck_amount);

// Ratio starts at exactly 1.0, so at 0% the (1 - 1/ratio) term is zero, no
// reduction is computed, and the gain is exactly unity — the stage is a bypass
// rather than something that merely settles near one.
//
// The key arrives already mono-summed, so there is only one detector and one
// gain for both channels. A ducker with per-channel detectors would move the
// image every time the source moved in it.
duckapply(l, r, k) = attach(l * g, redDb : duck_meter), r * g
with {
    envDb = an.amp_follower_ar(duck_att, duck_rel, k)
          : max(ba.db2linear(-120)) : ba.linear2db;

    redDb = min(max(0, envDb - duck_thresh) * (1 - 1 / duck_ratio), duck_range);
    g     = ba.db2linear(0 - redDb);
};


//======================== de-esser ===========================================
// A high frequency limiter, ported from vocalDoubler.dsp. It sits at the head
// of the wet path — before the springs and the pre-delay — so the dry half
// always passes through untouched and this can never dull the original signal.
//
// Detection is level-independent, and relative rather than absolute: the input
// is split into a low ("body") band and a high band, and their envelopes are
// compared as a ratio — a dB difference — instead of the high band being
// measured against a fixed level. A quiet "s" in a quiet passage spikes that
// ratio just as hard as a loud one, so detection does not follow overall
// loudness the way a plain high-band compressor would.
//
// One macro control drives all four parameters. To retune the feel, edit the
// endpoint pairs below: the first value is what the parameter is at De-Ess 0%,
// the second at 100%, interpolated linearly in between. Nothing else needs
// touching. Range being 0 dB at the bottom is what makes 0% a true bypass.
hfLimSplitAt0  = 5000;  hfLimSplitAt100  = 4500;  // Hz - crossover; lower reaches further down into the "sh" range
hfLimThreshAt0 =   -2;  hfLimThreshAt100 =   -14; // dB - how far the high band must stick out before it counts
hfLimRatioAt0  =    2;  hfLimRatioAt100  =     8; //    - how hard the excess is squeezed
hfLimRangeAt0  =    0;  hfLimRangeAt100  =    18; // dB - ceiling on total reduction

// Level independence cuts both ways: a ratio detector fires on near-silence
// just as happily as on a sibilant, because room tone, hiss and denormals are
// spectrally flat — i.e. brighter than voice — so their high/low ratio looks
// exactly like an "s". An absolute gate settles it: below the floor nothing is
// touched at all, and reduction fades in over the knee above it. Not amount-
// dependent; these are "is there signal here" numbers, not taste.
hfLimGateDb   = -60;  // dBFS - floor; below this the limiter idles
hfLimGateKnee =  12;  // dB   - fade-in range above the floor (full effect at -48)

hflim_split  = lerp(hfLimSplitAt0,  hfLimSplitAt100,  hflim_amount);
hflim_thresh = lerp(hfLimThreshAt0, hfLimThreshAt100, hflim_amount);
hflim_ratio  = lerp(hfLimRatioAt0,  hfLimRatioAt100,  hflim_amount);
hflim_range  = lerp(hfLimRangeAt0,  hfLimRangeAt100,  hflim_amount);

// Stereo, unlike the mono original in vocalDoubler.dsp, and the detection is
// *linked*: one gain, derived from the mono sum, drives both channels. Two
// independent detectors would duck the channels by different amounts on the
// same sibilant and swing the stereo image with every "s".
hfLimit(l, r) = attach(l : shelf, reductionDb : hflim_meter), (r : shelf)
with {
    // A real highpass, not `mono - lowpass`. Subtracting a Butterworth lowpass
    // does not give a Butterworth highpass: B(s)-1 has a single zero at DC, so
    // the complement rolls off at 6 dB/oct no matter what order the lowpass is,
    // and it overshoots at the corner. Measured against a 5 kHz split, that
    // "high band" was only -6 dB at 1 kHz, -0.1 dB at 2 kHz and +4.7 dB at
    // 5 kHz -- i.e. the detector was fed most of the vowel range plus a
    // resonant bump. The two bands need not be complementary: nothing
    // reconstructs the signal from them, they only feed the followers.
    mono = (l + r) * 0.5;
    low  = fi.lowpass(4, hflim_split, mono);
    high = fi.highpass(4, hflim_split, mono);

    // The floor is not cosmetic: on digital silence the follower reaches
    // exactly 0, ba.linear2db(0) is -inf, and the subtraction below would come
    // out NaN (-inf - -inf).
    envDb(att, rel, x) = an.amp_follower_ar(att, rel, x)
                       : max(ba.db2linear(-120)) : ba.linear2db;

    hiDb  = envDb(0.001, 0.03, high);
    refDb = envDb(0.001, 0.03, low);

    // Broadband level, for the gate only. Released slower than the ratio
    // detector so the gate stays open through the tail of a word instead of
    // chattering across the threshold.
    inDb = envDb(0.001, 0.1, mono);
    gate = min(1, max(0, (inDb - hfLimGateDb) / hfLimGateKnee));

    // dB the high band sticks out above the body band, relative to normal voice
    // spectral tilt; only the excess over threshold is limited.
    excess = max(0, hiDb - refDb - hflim_thresh);

    // Gating the reduction rather than the detector keeps the meter honest: it
    // reads 0 when nothing is being done.
    reductionDb = min(excess * (1 - 1 / hflim_ratio), hflim_range) * gate;

    // The reduction is applied as a real high shelf on the full-band signal,
    // not by re-summing the split -- low + high*gr is a shelf too, but an
    // accidental one: the lowpass and its complement differ in phase, so away
    // from unity gain they stop summing flat and the response ripples around
    // the corner.
    //
    // A TPT state variable filter, which is stable under coefficient
    // modulation, and whose shelf mix collapses to (1,0,0) at 0 dB -- so an
    // idle de-esser passes the signal through untouched. That matters here: it
    // feeds the wet branch only, and a wet path that was merely magnitude-flat
    // rather than identical would comb against the dry half.
    shelf = fi.svf.hs(hflim_split, 0.7, 0 - reductionDb);
};
