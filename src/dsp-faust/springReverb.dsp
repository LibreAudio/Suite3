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
tone    = uiBottomLeft(vslider("[3] Tone [style:knob][unit:%][symbol:tone][label:Tone][accentcolor:03]", 0.5, 0, 1, 0.01));

volL = uiBottomRight(vslider("[5]Spring L [style:knob][unit:dB][symbol:Left][label:volL][accentcolor:04][bracket:SPRINGS]",0,-60,0,1)) : ba.db2linear;
volC = uiBottomRight(vslider("[6]Spring C [style:knob][unit:dB][symbol:Center][label:volC][accentcolor:04][bracket:SPRINGS]",0,-60,0,1)) : ba.db2linear;
volR = uiBottomRight(vslider("[7]Spring R [style:knob][unit:dB][symbol:Right][label:volR][accentcolor:04][bracket:SPRINGS]",0,-60,0,1)) : ba.db2linear;

crossfeed = uiBottomRight(vslider("[8]crossfeed [style:knob][unit:%][symbol:crossLR][label:Crossfeed][accentcolor:05][bracket:MIXER]", 0,0,100,1)) / 100;
wetmix  = uiBottomRight(vslider("[9]Wet [style:knob][unit:%][symbol:DryWet][label:Dry-Wet][accentcolor:06][bracket:MIXER]", 0.5, 0, 1, 0.01));


process = ef.dryWetMixerConstantPower(wetmix,  springreverb_stereo);

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
