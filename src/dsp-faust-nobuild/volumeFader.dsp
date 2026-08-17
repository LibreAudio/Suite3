declare author "Klaus Scheuermann";
declare description "";
declare license "GPL-3.0-or-later";
declare name "Volume Fader";
declare unique_id "LAvf";

import("stdfaust.lib");

// N-channel volume fader, -inf .. +12 dB.
//
// The bottom of the fader travel is true silence — an exact 0.0 multiplier,
// not merely a very small one — while every position above it is an ordinary
// dB gain. Reconciling those two needs a little care, because a dB value can
// never *be* -inf and a one-pole smoother can never quite *reach* zero.
//
// So the gain is built from two smoothed parts:
//
//   level  the fader in dB, smoothed in the dB domain so that a move feels
//          perceptually even (a linear-domain glide would rush the loud end
//          of the travel and crawl through the quiet end);
//
//   open   0 at the bottom detent, 1 anywhere above it, smoothed in the
//          linear domain and snapped to exactly 0 once it falls below
//          `silence`. That snap is the only discontinuity in the signal
//          path. It cannot exceed -128 dBFS even in the worst case, and in
//          practice it lands near -212 dBFS, because by the time `open` has
//          decayed that far `level` has also travelled down to dBmin.
//
// Multiplying the two means muting fades out over the same ~20 ms as any
// other fader move, then lands on real zero instead of asymptotically
// approaching it.

Nch = 2;

// Bottom of the dial. The fader is at -inf here, not at -72 dB; the value
// only exists so the smoother has somewhere finite to travel to, and it
// sits low enough that db2linear(dBmin) is inaudible on its own.
dBmin = -60;
dBmax = 12;

// Below this the fade-out is finished, as far as anything downstream can
// tell: -140 dB is under one LSB of a 24-bit sample (2^-23). Raising it
// shortens the tail of a mute, lowering it shrinks the snap.
silence = 1e-7;

fader = hslider("[0][unit:dB]Volume[symbol:volume]", 0, dBmin, dBmax, 0.1);

level = fader : si.smoo;
open  = (fader > dBmin) : si.smoo : gate
with {
    gate(x) = x * (x > silence);
};

gain = ba.db2linear(level) * open;

process = par(i, Nch, *(gain));
