declare author "Klaus Scheuermann";
declare description "Pseudo-stereo widener — Haas or comb from one mono-sum delay";
declare license "GPL-3.0-or-later";
declare name "Pseudo Stereo";
declare unique_id "LAps";

// Port of Liteon's (Lubomir I. Ivanov) "MDA Pseudo-Stereo" JSFX, 2008-2009,
// itself based on Paul Kellett's mdaStereo. Original released under GPL.
//
// One delay line, fed the mono sum of the two inputs, and two different ways of
// mixing that sum and its delayed copy back into L and R:
//
//   Amount < 0 — Haas. The delayed tap reaches the right channel only (ld = 0),
//     and it is subtracted, so what the right side gets is an inverted late
//     copy of the mono sum while the left gets an early one. Turning the knob
//     down fades the right channel's dry share out (ri falls to 0 at -100)
//     as the delayed one comes up, so the image both decorrelates and leans
//     left — level and arrival time move together, as in the original.
//
//   Amount > 0 — comb. Both channels take the same dry coefficient and equal
//     and *opposite* delayed coefficients (rd = -ld). Since only the sign of
//     the delayed tap differs, everything the effect adds lives in the side
//     channel: the comb filtering is complementary between the two sides
//     (a notch on the left is a peak on the right) and cancels exactly on a
//     mono sum, which is what makes this the mono-safe half of the control.
//
// The two halves meet at Amount = 0, where the delayed tap drops out entirely
// (ld = rd = 0) and both channels get the same 0.5 of the dry mono sum — not a
// bypass: an ordinary mono-ish blend with a +0.4 dB bump on centred material.
//
// Amount is scaled by a different divisor on each side (200 negative, 115
// positive), so the two directions are not symmetric — the comb side is pushed
// past the point where the delayed tap outweighs the dry one, the Haas side is
// not. The knob is a type switch with a depth built into it, not a balance.

import("stdfaust.lib");

MAXDEL = 1 << 17;   // delay line size in samples — covers the longest delay up to 192 kHz

//----------------------------------------------------------------- UI
uiBottom(x)      = hgroup("[8]Stage Bottom", x);
uiBottomLeft(x)  = uiBottom(hgroup("[1]Stage Bottom Left", x));
uiBottomRight(x) = uiBottom(hgroup("[1]Stage Bottom Right", x));

amount  = uiBottomLeft(hslider("[01]Amount[style:knob][unit:%][symbol:amount][label:Amount][accentcolor:01][bracket:WIDTH][easy]", 0, -100, 100, 0.01));
delayms = uiBottomLeft(hslider("[02]Delay[style:knob][unit:ms][symbol:delay][label:Delay][accentcolor:02][bracket:WIDTH]", 20, 1, 50, 0.01));
balance = uiBottomRight(hslider("[03]Balance[style:knob][unit:%][symbol:balance][label:Balance][accentcolor:04][bracket:OUTPUT]", 0, -100, 100, 0.01));
out_db  = uiBottomRight(hslider("[04]Output[style:knob][unit:dB][symbol:output][label:Output][accentcolor:06][bracket:OUTPUT]", 0, -20, 20, 0.01));

//----------------------------------------------------------------- coefficients
// Everything below is control-rate in the original too: JSFX recomputes it in
// @slider and ramps to the new value across one block. si.smoo is the same idea
// with a one-pole instead of a linear ramp, and it is applied to the four mix
// coefficients and to the delay time rather than to the knobs, so the ramp
// happens where the original's did.

fxk      = select2(amount > 0, 200.0, 115.0);
fxamount = 0.5 + amount / fxk;      // 0 .. 1.37, and *not* centred at 0.5 in travel
comb     = fxamount >= 0.5;

// Haas half: dry rises on the left, the delayed tap only ever appears on the right.
haas_li = 0.25 + 1.5 * fxamount;
haas_ld = 0.0;
haas_ri = 2.0 * fxamount;
haas_rd = 1.0 - haas_ri;

// Comb half: identical dry coefficients, mirrored delayed coefficients.
comb_li = 1.5 - fxamount;
comb_ld = fxamount - 0.5;
comb_ri = comb_li;
comb_rd = 0.0 - comb_ld;

// Depth trim: unity at the centre, growing towards either end of the knob, so
// the far ends of both halves keep their level up as the dry coefficient falls.
depth = 0.5 + abs(fxamount - 0.5);

li = select2(comb, haas_li, comb_li) * depth : si.smoo;
ld = select2(comb, haas_ld, comb_ld) * depth : si.smoo;
ri = select2(comb, haas_ri, comb_ri) * depth : si.smoo;
rd = select2(comb, haas_rd, comb_rd) * depth : si.smoo;

// The original's delay curve, kept as-is: quadratic in the knob and dependent
// on the sample rate, so the knob is calibrated in milliseconds only near the
// top of its range (1 ms reads as ~0.47 ms at 44.1 kHz, 50 ms as ~48 ms).
// Its buffer was fixed at SR/10 samples and wrapped when the delay exceeded it,
// which folded the longer settings back to a short delay from 96 kHz upwards
// (44.1/48/88.2 kHz always fit). MAXDEL is large enough that this one does not
// wrap at any rate a host will run.
del = max(0.0, min(MAXDEL - 2, sq((ma.SR * (22.0 + 4.0 * delayms) - 200000.0) / 208000.0))) : si.smoo
with { sq(x) = x * x; };

//----------------------------------------------------------------- output stage
// Balance attenuates one side rather than panning: min(...,1) keeps the other
// side at unity instead of lifting it. 0.7 is the original's fixed makeup trim.
bal     = balance / 100.0;
outgain = out_db : ba.db2linear;
bl      = min(1.0 - bal, 1.0) * outgain * 0.7 : si.smoo;
br      = min(1.0 + bal, 1.0) * outgain * 0.7 : si.smoo;

//----------------------------------------------------------------- process
process(l, r) = chl * bl, chr * br
with {
    a   = (l + r) * 0.5;                    // mono sum feeding the delay line
    b   = a : de.fdelay(MAXDEL, del);       // fractional here; the original truncated
    chl = l + a * li - b * ld;
    chr = r + a * ri - b * rd;
};
