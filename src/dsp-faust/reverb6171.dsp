declare author "Klaus Scheuermann";
declare description "";
declare license "GPL-3.0-or-later";
declare name "6171 Reverb";
declare unique_id "LA61";

// declare drywet "true";

import("stdfaust.lib");

// declare author "Evermind";
// declare license "BSD 3-clause";

//Constants
// Longest delay one allpass can hold. Delay * Delay Scale saturates here --
// de.delay clamps rather than wrapping -- so this is the real ceiling on the
// Timings knobs, not their 400 ms range. Raising it costs 4 bytes per sample
// per allpass, eight allpasses deep, sized for the highest supported rate.
MAXDELAY = ba.sec2samp(1.0);

// Coefficient of the two allpasses inside the feedback loop. Must stay below
// 1: see gerzon_delays.
loop_diffusion = 0.7;

// si.smooth's state starts at zero, so a plain `: si.smoo` ramps a control up
// from 0 over the first ~20 ms -- on HF Damping that starts the loop lowpass
// at 0 Hz and mutes the tail. Smoothing the offset from the default value
// instead leaves the smoother at rest when nothing has been touched.
smoo(dflt, x) = (x - dflt) : si.smoo : +(dflt);

//Parameters
// Two top-level groups, Main and Timings, so every control is on one page.
// No tab box: the suite's UI stub (src/FaustDSP.hpp) implements only
// openHorizontalBox and openVerticalBox, so a t: group fails to compile with
// "no member named 'openTabBox'". None of the other plugins here use one.
//
// Every control carries an explicit [symbol:...]. The build derives the
// FaustParameterList enumerator from the slider *label* alone and ignores the
// enclosing group, so the eight "Delay 1".."Delay 4" knobs collided into four
// duplicate enumerators and the generated header would not compile. Symbols
// are also the plugin's public parameter ids (LV2 ports, CLAP/VST3 ids), so
// they are fixed here rather than left to be derived and drift later.
feedback_amount = vslider("h:[0]Main/[0]Feedback %[symbol:feedback]", 70, 0, 90, 0.1) / 100;
crosstalk = vslider("h:[0]Main/[1]Crosstalk[symbol:crosstalk]", 30, 0, 100, 1) / 100;
wet_level = vslider("h:[0]Main/[2]Wet %[symbol:wet]", 25, 0, 100, 1) / 100;
outgain = vslider("h:[0]Main/[3]Out Gain[symbol:out_gain]", 0, -24, 24, .1) : ba.db2linear : si.smoo;

ldelay1 = hslider("v:[1]Timings/h:Left Channel/Delay 1[unit:ms][style:knob][symbol:ldelay1]", 100, 1, 400, 0.1) * delay_scale / 1000 : ba.sec2samp;
ldelay2 = hslider("v:[1]Timings/h:Left Channel/Delay 2[unit:ms][style:knob][symbol:ldelay2]", 68, 1, 400, 0.1) * delay_scale / 1000 : ba.sec2samp;
ldelay3 = hslider("v:[1]Timings/h:Left Channel/Delay 3[unit:ms][style:knob][symbol:ldelay3]", 19.7, 1, 400, 0.1) * delay_scale / 1000 : ba.sec2samp;
ldelay4 = hslider("v:[1]Timings/h:Left Channel/Delay 4[unit:ms][style:knob][symbol:ldelay4]", 5.9, 1, 400, 0.1) * delay_scale / 1000 : ba.sec2samp;
rdelay1 = hslider("v:[1]Timings/h:Right Channel/Delay 1[unit:ms][style:knob][symbol:rdelay1]", 112, 1, 400, 0.1) * delay_scale / 1000 : ba.sec2samp;
rdelay2 = hslider("v:[1]Timings/h:Right Channel/Delay 2[unit:ms][style:knob][symbol:rdelay2]", 53, 1, 400, 0.1) * delay_scale / 1000 : ba.sec2samp;
rdelay3 = hslider("v:[1]Timings/h:Right Channel/Delay 3[unit:ms][style:knob][symbol:rdelay3]", 21.7, 1, 400, 0.1) * delay_scale / 1000 : ba.sec2samp;
rdelay4 = hslider("v:[1]Timings/h:Right Channel/Delay 4[unit:ms][style:knob][symbol:rdelay4]", 7, 1, 400, 0.1) * delay_scale / 1000 : ba.sec2samp;

delay_scale = vslider("h:[0]Main/[4]Delay Scale[symbol:delay_scale]", 1,0.01,10,0.01);

// Air absorption, applied inside every allpass -- see allpass below. Capped
// below Nyquist so the one-pole stays well conditioned at any sample rate.
damping = vslider("h:[0]Main/[5]HF Damping[unit:Hz][scale:log][symbol:hf_damping]", 6000, 500, 20000, 1)
        : smoo(6000) : min(0.45 * ma.SR);

//Functions
// Absorbent Schroeder allpass. Undamped it is
//   s[n] = x[n] - g*s[n-dt],  y[n] = s[n-dt] + g*s[n]
// giving H(z) = (g + z^-dt) / (1 + g*z^-dt) -- unity magnitude at every
// frequency. The one-pole is what makes the tail lose treble as it decays;
// without it every stage here is magnitude-flat and the reverb stays exactly
// as bright as the input for as long as it rings.
//
// The filter goes *inside* the delay line, where the feedback path and the
// output tap both see it. That placement is what keeps this stable. Writing
// D(z) = z^-dt * L(z) for the damped delay, the response is
//   H(z) = (D + g) / (1 + g*D)
// and |D+g|^2 - |1+g*D|^2 = (|D|^2 - 1)(1 - g^2), which is <= 0 for any
// |D| <= 1 and any 0 <= g < 1. A one-pole lowpass never exceeds unity, so
// |H| <= 1 at every frequency and every knob position. Putting the same filter
// in the feedback path *only* breaks that: at HF the return vanishes while the
// feedforward g stays, |H| rises toward 1+g = 1.9, and the outer loop -- which
// multiplies by up to 0.9 -- runs away. Measured: NaN within a second.
//
// Damping the allpasses rather than only the feedback loop is deliberate: the
// diffuser chain sits *outside* the loop and generates most of the tail at the
// default timings, so loop-only damping measures as a near-flat gain there
// (87% of HF against 69% of broadband).
//
// The `~` contributes one sample of the loop delay, hence dt-1 in the delay
// line and the compensating mem on the way out.
allpass(dt,gain) = (+ <: (de.delay(MAXDELAY,dtc-1) : fi.lowpass(1, damping)),*(gain)) ~ *(-gain) : mem,_ : +
with {
    // de.delay already clamps to [0, MAXDELAY]; the max(1) is what keeps
    // dtc-1 off negative when Delay Scale pulls a short tap under one sample.
    dtc = dt : max(1) : min(MAXDELAY);
};
schroeder_verb(dt1, dt2, dt3, gain) = allpass(dt1,gain) : allpass(dt2, gain) : allpass(dt3, gain);
schroeder_delays(dt1, dt2, dt3, dt4, dt5, dt6, lgain, rgain) = schroeder_verb(dt1, dt2, dt3, lgain),
                                   schroeder_verb(dt4, dt5, dt6, rgain);

// Diffusion inside the recirculating loop.
//
// This used to be allpass(dt, 1). At a coefficient of exactly 1 the allpass
// zero cancels its own pole and the stage collapses to an algebraic identity:
// s[n] = x[n] - s[n-dt] and y[n] = s[n-dt] + s[n] = x[n], for any state. So it
// passed the signal through untouched, the Delay 4 knobs did nothing, and the
// only delay left in the feedback loop was the single sample from `~` -- which
// made the loop a one-pole lowpass with crossfeed rather than a tail. Below 1
// the pole sits inside the unit circle, the stage has real group delay again,
// and the loop recirculates.
gerzon_delays(dt1, dt2) = (allpass(dt1,loop_diffusion),
                           allpass(dt2,loop_diffusion));
routing(a,b,c,d) = (a+c), (b+d);
mix_channels(ct) = _,_ <: *(1-ct)+*(ct), *(ct)+*(1-ct);

// Per-pass loop loss. The damping lives inside the allpasses, so this is a
// plain gain; those allpasses never exceed unity magnitude (proved above),
// which leaves the loop bounded by feedback_amount -- capped at 0.90 by the
// slider. No knob combination can run away.
loop_gain = *(feedback_amount);

reverb = schroeder_delays(ldelay1, ldelay2, ldelay3, rdelay1, rdelay2, rdelay3, feedback_amount, feedback_amount) :
        (routing : gerzon_delays(ldelay4, rdelay4) : mix_channels(crosstalk)) ~ (loop_gain, loop_gain);

process = _,_ <: (_,_), reverb: ro.interleave(2,2) : it.interpolate_linear(wet_level), it.interpolate_linear(wet_level) : * (outgain), *(outgain);
