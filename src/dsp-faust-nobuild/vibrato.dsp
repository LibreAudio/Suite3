declare author "Klaus Scheuermann";
declare description "";
declare license "GPL-3.0-or-later";
declare name "Vibrato";
declare unique_id "LAvi";

// declare drywet "true";

import("stdfaust.lib");

// Stereo vibrato: pitch modulation produced by a sine-modulated fractional
// delay line, one per channel. 100% wet by design — blending dry back in
// would comb-filter the two against each other and turn this into a
// chorus/flanger rather than a clean pitch wobble.
//
// The two channels share one LFO frequency but can be offset in phase:
// at 0 deg they move together (mono-compatible, no width), at 180 deg one
// side pitches up while the other pitches down, which is what produces the
// sense of stereo movement.
//
// Depth is calibrated in cents and holds that deviation at any rate. The
// pitch shift a delay line produces is the *slope* of its delay time,
//
//     ratio - 1 = D * 2*PI*rate        (D = excursion in seconds)
//
// so holding the deviation fixed while the rate falls means widening the
// excursion in proportion. `excursion` below inverts that relationship.
//
// Depth names the *upward* peak. Because pitch is logarithmic in the
// delay slope, the downward swing of a sine sweep is always the deeper
// one — negligible when small (50 -> +50/-51 cents) but pronounced at the
// top of the range (500 -> +500/-706 cents). That asymmetry is intrinsic
// to varispeed, and is exactly what real tape wow does.

rate     = hslider("[0]Rate[unit:Hz][scale:log][symbol:rate]", 5, 0.1, 12, 0.01);
cents    = hslider("[1]Depth[unit:cents][symbol:depth]", 50, 0, 500, 0.1);
phaseDeg = hslider("[2]Stereo Phase[unit:deg][symbol:stereo_phase]", 90, 0, 180, 1);

// Seconds of delay swing needed for `cents` of peak deviation at `rate`.
//
// At the slow end this value is enormous, so it cannot simply be smoothed
// into place: nudging 0.1 -> 0.12 Hz at 500 cents moves the peak delay by
// 178 ms, and dropping that in over si.smoo's 21 ms is a delay slope of
// 8.5 — the read pointer running backwards at 8x speed, heard as a tear
// rather than a glide. Slew-limiting caps how fast the delay may travel,
// which turns a control move into a bounded glide, much like changing a
// tape machine's speed.
//
// maxSlope is in delay-samples per sample. The vibrato's own peak slope is
// (cent2ratio(depth) - 1) — 0.335 at 500 cents — so a ceiling of 0.15
// keeps any control move quieter than the effect that masks it. Raise for
// snappier response, lower for gentler glides.
maxSlope = 0.15;

// (1 + lfo) peaks at 2, so the delay travels at twice the excursion's rate.
slew(step, x) = fb ~ _
with {
    init  = 1 - 1';   // take the target as-is on sample 0, so no fade-in
    fb(y) = select2(init, y + max(0 - step, min(step, x - y)), x);
};

excursion = (ba.cent2ratio(cents) - 1) / (2 * ma.PI * rate)
          : slew(maxSlope / (2 * ma.SR));

// Worst case is max depth at min rate: 500 cents at 0.1 Hz is a 533 ms
// excursion, so a 1.07 s swing — ~205k samples at 192 kHz. 1<<18 covers
// that; the delaySamp clamp below keeps even higher rates in bounds
// (at the cost of under-delivering depth there) rather than overrunning.
maxDel = 1 << 18;

// lf_sawpos is a bare phase accumulator: changing `rate` only changes the
// increment, so the phase carries over rather than restarting. Taking sin()
// of it directly — rather than os.osc, which truncates into a wavetable —
// matters at the slow end: at 0.1 Hz the table index advances only every
// ~7 samples, and against a half-second excursion each of those steps is a
// 2.4-sample jump in delay time, which is audible as roughness.
// Both channels read the one accumulator, so their offset is exact.
lfoPhase = os.lf_sawpos(rate);                       // 0..1 ramp
lfoL     = sin(2 * ma.PI * lfoPhase);                // sine, -1..+1
lfoR     = sin(2 * ma.PI * lfoPhase + phaseDeg * ma.PI / 180);

// Centering the sweep on `excursion` keeps the delay in 0..2*excursion so
// it never goes negative; the clamps hold it to what the line can index.
// fdelay (not delay) — an integer delay would step audibly when modulated.
vibrato(lfo) = de.fdelay(maxDel, delaySamp)
with {
    delaySamp = min(maxDel - 2, max(1, excursion * (1 + lfo) * ma.SR));
};

process = os.osc(220) <: vibrato(lfoL), vibrato(lfoR);
