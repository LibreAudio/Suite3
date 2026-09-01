// -*-Faust-*-

declare author "Klaus Scheuermann";
declare description "";
declare license "GPL-3.0-or-later";
declare name "5-Band M-S Compressor";
declare unique_id "LAm5";

// Dry/wet is built here rather than taken from the host wrapper, for the same
// reason compressor.dsp gives: leaving the flag on would stack the wrapper's
// common "Dry / Wet" on top of this one, and the two tap the dry from
// different places. The control below taps the audio as this DSP receives it,
// and delays it to match Lookahead, so the parallel path stays phase aligned.
// declare drywet "true";

import("stdfaust.lib");

// The compressor works in mid/side, always - there is no L/R mode. The encode
// and decode sit around the wet path only, so the dry side of Dry/Wet stays
// the audio exactly as this DSP received it. See the Mid/side section near the
// bottom.
//
// What this changes about the controls: Channel Link now links mid against
// side rather than left against right, and the two gain reduction meters per
// band read mid and side, not left and right.

// number of channels, and number of bands. The mid/side path assumes exactly 2.
Nch = 2;
Nba = 5;

maxGR    = -60;  // meter floor, also the widest Range setting
maxMeter = -24;  // per-band gain reduction meter floor

maxLookaheadSamples = 9600; // 50 ms at 192 kHz

//======================= GUI =======================
// Band groups are numbered 1..5 and use their own number as the group index,
// so the globals sit at 0 and everything else after 5. The %n substitution
// only works on an integer bound as a function parameter or a par/seq index,
// which is why every per-band widget lives behind a function of n.

main_group(x)   = vgroup("5-Band Compressor", x);
row1_group(x)   = main_group(hgroup("Row 1", x));
row2_group(x)   = main_group(hgroup("Row 2", x));
glob_group(x)   = row1_group(hgroup("[0]Global", x));
band_group(n,x) = row2_group(hgroup("[%n]Band %n", x));
xo_group(x)     = row1_group(hgroup("[6]Crossovers", x));
meter_group(x)  = row1_group(vgroup("[7]Meters", x));
mid_meters(x)   = meter_group(hgroup("[0]Mid", x));
side_meters(x)  = meter_group(hgroup("[1]Side", x));

//======================= Global controls =======================

// ---- gain computer ----

knee = glob_group(vslider("[0]Knee[unit:dB][symbol:knee]
      [tooltip: Width of the soft transition around each band's threshold. The
       ratio reaches its full value knee/2 dB above the threshold and is 1:1
       knee/2 dB below it. Shared by all five bands]",
                          6, 0, 24, 0.1));

range = glob_group(vslider("[1]Range[unit:dB][symbol:range]
      [tooltip: Ceiling on the gain reduction any one band may reach. The
       compressor never pulls a band down by more than this, no matter how far
       over its threshold the signal goes]",
                           60, 0, 0 - maxGR, 0.1));

// The Range ceiling is eased into with the same knee that eases into the
// threshold, exactly as in compressor.dsp - one less control for the same
// behaviour, since a hard Range with a soft threshold is not a combination
// anyone reaches for.
rangeKnee = knee;

// ---- detector ----

rmsTime = glob_group(vslider("[2]RMS Time[unit:ms][symbol:rms_time]
      [tooltip: Averaging window of the level detector. 0 ms is peak detection:
       the average collapses to the rectified signal, so the two meet
       continuously and there is no mode switch to click. Turning it up makes
       every band follow loudness instead of transients]",
                             10, 0, 250, 0.1)) * 0.001;

// ---- envelope shape ----

shape = glob_group(vslider("[3]Shape[unit:%][symbol:shape]
      [tooltip: Shape of the release ramp, shared by all bands. 0% = a straight
       line in dB, constant dB per second, which lets go of a long reduction
       as fast as a short one. 100% = exponential, the analog-style curve where
       Release reads as a 1/e time constant: quick at first, then a long tail]",
                           100, 0, 100, 1)) / 100;

// Attack keeps compressor.dsp's default shape. Exposing it would have meant a
// fourth envelope control for a knob that is left at +1 in practice, and the
// exponential attack is the one that makes Attack read as a time constant.
attackCurve = 1;

// ---- linking ----

chanLink = glob_group(vslider("[4]Channel Link[unit:%][symbol:chan_link]
      [tooltip: How much the mid and side of a band share their gain reduction.
       0% = each gets its own, so the band's width moves with the programme -
       the side compressing on its own is what widens a loud passage.
       100% = both follow the more reduced one, so the image never shifts.
       Applied within a band, across mid and side]",
                              100, 0, 100, 1)) / 100;

bandLink = glob_group(vslider("[5]Band Link[unit:%][symbol:band_link]
      [tooltip: How much the five bands share their gain reduction. 0% =
       independent multiband behaviour, 100% = every band follows the
       most-reduced one and the plugin acts as a wideband compressor that still
       has five thresholds feeding it. Applied within a channel, across bands]",
                              0, 0, 100, 1)) / 100;

// ---- crossover slope ----

// Menu rather than a slider: the three settings are the three filter orders
// the detector can be built at, not points on a continuum. See the Shelf
// section for how the same number reshapes the gain application.
slopeSel = glob_group(nentry("[6]Slope[symbol:slope]
      [style:menu{'6 dB/oct':0;'12 dB/oct':1;'24 dB/oct':2}]
      [tooltip: Steepness of the band split. Applies to both halves of the
       crossover: how selectively each band listens, and how sharply the gain
       it computes is applied. Shallow settings overlap and behave more like a
       broadband compressor with tilt; steep settings isolate the bands]",
                             1, 0, 2, 1));

// ---- output ----

lookaheadMs = glob_group(vslider("[7]Lookahead[unit:ms][symbol:lookahead]
      [tooltip: Delays the audio so the gain is already down when the transient
       arrives. Reported to the host as latency and compensated. 0 = off]",
                                 0, 0, 50, 0.1));

drywet = glob_group(vslider("[8]Dry / Wet[unit:%][symbol:drywet]
      [tooltip: Blend of the compressed signal against the untouched input, for
       parallel compression. 100% = compressor only, 0% = bypassed. The dry
       side is delayed to match Lookahead, so the blend never combs]",
                            100, 0, 100, 1)) / 100 : si.smoo;

// Listen is a shelf setting, not a band split - the audio is never actually
// cut apart - so how deep a rejection is reachable is fixed by the Slope, and
// asking for more than that costs level in the band being auditioned rather
// than buying more rejection. A shelf of order N covers 6N dB per octave at
// its steepest, the bands here are two to three octaves wide, and the cascade
// has to make the step twice: down into the muted band and back up out of it.
// Measured at 1 kHz with the default crossovers, band 3 on Listen, as
// (level of the auditioned band / rejection of a muted one):
//
//            floor -60      floor -36      floor -24      floor -18
//   6 dB/oct  -1.9/-20.1     -1.9/-19.9     -1.9/-18.6     -1.9/-16.0
//   12        -36.0/-59.6   -13.8/-36.0     -5.9/-24.0     -3.4/-18.0
//   24        -13.7/-60.0    -1.9/-36.0     -0.5/-24.0     -0.3/-18.0
//
// -18 is the deepest setting that stays honest at every slope, hence the
// default; the range stops at -48 because nothing past it is reachable even
// at 24 dB/oct without gutting the band you are trying to hear. At 6 dB/oct
// the rejection saturates around -20 dB whatever this says, because that shelf
// is built as a complementary split and its high half passes at unity.
listenFloorDb = -18; /*glob_group(vslider("[9]Listen Floor[unit:dB][symbol:listen_floor]
      [tooltip: How far the bands you are not listening to are pushed down.
       Listen auditions a band through the same shelves that apply the
       compression rather than splitting the audio, so it is a steep tilt
       rather than a clean isolation: the steeper the Slope, the deeper this
       can usefully go. Past about -18 dB at 12 dB/oct the band you are
       listening to starts losing level of its own instead of the others
       losing more]",
                                   -18, -48, -6, 1));*/

//======================= Crossover frequencies =======================
// Four free sliders, forced into ascending order on the way out and kept
// clear of Nyquist. The 1.02 margin stops two sections from landing on the
// same frequency, which would leave a band with no bandwidth for its detector
// to look at and two shelves fighting over one corner.
//
// Clamping the *effective* frequency rather than the slider means dragging
// one crossover past another does not drag the other one's control with it -
// the neighbour is held until the first one moves back off it.

nyq   = 0.45 * ma.SR;
clamp(f) = max(20, min(f, nyq));

xoRaw(n) = xo_group(vslider("[%n]Crossover %n[unit:Hz][scale:log][symbol:xover%n]
      [tooltip: Split point between band %n and the band above it. Held above
       the crossover below it, so the four can never cross over each other]",
                            ba.take(n, (100, 500, 2000, 8000)), 20, 20000, 1))
         : si.smoo;

xf(1) = clamp(xoRaw(1));
xf(2) = clamp(max(xf(1) * 1.02, xoRaw(2)));
xf(3) = clamp(max(xf(2) * 1.02, xoRaw(3)));
xf(4) = clamp(max(xf(3) * 1.02, xoRaw(4)));

xoverFreqs = xf(1), xf(2), xf(3), xf(4);

//======================= Per-band controls =======================
// Each of these is instantiated once per band inside a par() and handed to the
// processing chain as a bus, in the same style as mbmsComp5.dsp's *_array
// definitions. Nothing here may be read as a scalar - a second call would
// declare a second widget with the same symbol - so anything that needs a
// band's setting takes it as a signal input.

threshOf(n) = band_group(n, vslider("[0]Threshold[unit:dB][symbol:band%{n}_threshold]
      [tooltip: Level in this band above which it is compressed]",
                                    -18, maxGR, 0, 0.1));

ratioOf(n) = band_group(n, vslider("[1]Ratio[scale:log][symbol:band%{n}_ratio]
      [tooltip: dB in per dB out above this band's threshold. 1 = that band is
       left alone]",
                                   2, 1, 20, 0.01));

// Per-band defaults, fast at the top and slow at the bottom, which is where
// anyone would end up setting them by hand: a 60 Hz cycle is 17 ms long, so a
// low band with a 4 ms attack tracks the waveform instead of its envelope.
attackOf(n) = band_group(n, vslider("[2]Attack[unit:ms][scale:log][symbol:band%{n}_attack]
      [tooltip: How fast this band's gain moves toward a deeper reduction. A
       1/e time constant, since the attack curve is exponential]",
                                    ba.take(n, (30, 20, 10, 6, 4)), 0.01, 100, 0.01))
            * 0.001;

releaseOf(n) = band_group(n, vslider("[3]Release[unit:ms][scale:log][symbol:band%{n}_release]
      [tooltip: How fast this band's gain moves back toward unity. Read as a
       1/e time constant at Shape 100%, or as the time to cover 20 dB at
       Shape 0%]",
                                     ba.take(n, (300, 250, 180, 120, 90)), 1, 2000, 0.1))
             * 0.001;

makeupOf(n) = band_group(n, vslider("[4]Makeup[unit:dB][symbol:band%{n}_makeup]
      [tooltip: Static trim for this band, to put back the level the band lost.
       It rides the same shelf cascade the gain reduction does, so it is a band
       gain in the exact same sense - the plugin doubles as a 5-band EQ with
       Ratio at 1]",
                                    0, -24, 24, 0.1));

bypassOf(n) = band_group(n, checkbox("[5]Bypass[symbol:band%{n}_bypass]
      [tooltip: Leaves this band at 0 dB - no gain reduction and no makeup -
       while the other four keep working]"));

listenOf(n) = band_group(n, checkbox("[6]Listen[symbol:band%{n}_listen]
      [tooltip: Auditions this band by pushing every other band down to Listen
       Floor. More than one band may be on Listen at a time]"));

thresh_array  = par(b, Nba, threshOf(b+1));
ratio_array   = par(b, Nba, ratioOf(b+1));
attack_array  = par(b, Nba, attackOf(b+1));
release_array = par(b, Nba, releaseOf(b+1));
listen_array  = par(b, Nba, listenOf(b+1));

//======================= Meters =======================

// A passive widget with this exact symbol is what the build turns into the
// plugin's reported latency (see the latency_samples cases in
// src/templates/dsp.cpp.in), so the host delay-compensates Lookahead.
latency_meter = _ <: attach(_, meter_group(hbargraph("[9]latency_samples[symbol:latency_samples]",
                                                     0, maxLookaheadSamples)));

// Two names for one number: the dry path needs the same delay as the wet, but
// it must not carry the meter with it - that would declare a second bargraph
// with the same symbol.
lookaheadDelay   = int(lookaheadMs * ma.SR / 1000);
lookaheadSamples = lookaheadDelay : latency_meter;

// One meter per band per channel, ten in all. They sit in two rows because
// the pair is only readable side by side: mid and side pulling apart is the
// thing worth seeing here, and it is invisible in a single merged reading.
// Both are the reduction actually applied - after Bypass and Listen have
// scaled it, before Makeup adds back - so a bypassed or muted band reads 0.
bandMeterM(n) = max(maxMeter) : mid_meters(hbargraph("[%n]Band %n M[unit:dB][symbol:gr_band%{n}_mid]",
                                                     maxMeter, 0));
bandMeterS(n) = max(maxMeter) : side_meters(hbargraph("[%n]Band %n S[unit:dB][symbol:gr_band%{n}_side]",
                                                      maxMeter, 0));

//======================= Level detector =======================
// One reading rather than compressor.dsp's peak/RMS crossfade, because RMS
// Time already spans both: si.smooth's pole goes to 0 as the time constant
// does, at which point the average of the squared signal collapses to x*x and
// the sqrt gives |x| - peak detection exactly, not an approximation of it. So
// the knob runs continuously from peak at 0 ms to a long average, and there is
// no setting of it that can produce a jump.

levelDb(x) = x * x
           : si.smooth(ba.tau2pole(max(rmsTime, 1e-6)))
           : sqrt
           : max(ma.EPSILON)
           : ba.linear2db;

//======================= Gain computer =======================
// Returns gain reduction in dB, always <= 0. Straight from compressor.dsp,
// with the threshold and ratio taken as signals so one instance can serve
// whichever band it is wired into.
//
// Below thresh-knee/2 nothing happens, above thresh+knee/2 the full ratio
// applies, and in between a quadratic bridges the two. The quadratic is the
// unique parabola that matches both value and slope at each end, which is what
// makes the knee audibly smooth rather than merely continuous.

gainComputer(thresh, ratio, level) = select3(zone, 0, softPart, hardPart)
with {
    // slope = the fraction of every dB of overshoot that gets removed
    slope    = 1 - 1 / max(1, ratio);
    over     = level - thresh;
    zone     = (over > 0 - knee / 2) + (over > knee / 2);
    softPart = 0 - slope * pow(over + knee / 2, 2) / (2 * max(ma.EPSILON, knee));
    hardPart = 0 - slope * over;
};

//======================= Range ceiling =======================
// Same parabola trick as the knee, mirrored: instead of easing into
// compression it eases into the floor.

rangeLimit(gr) = select3(zone, lim, soft, gr)
with {
    lim  = 0 - range;
    d    = gr - lim;

    // The soft floor peaks at lim + rk/2, so a knee wider than twice the Range
    // would lift the "gain reduction" above 0 dB and the band would quietly
    // turn into a boost. Capping the knee at 2*range pins that peak to exactly
    // 0 dB and degrades to a hard clamp as Range approaches 0.
    rk   = min(rangeKnee, 2 * range);

    zone = (d > 0 - rk / 2) + (d > rk / 2);
    soft = lim + pow(d + rk / 2, 2) / (2 * max(ma.EPSILON, rk));
};

//======================= Ballistics =======================
// compressor.dsp's rate law, with hold, auto-release and the S-curve dropped -
// they were not asked for here, and five bands' worth of them would have been
// thirty more parameters.
//
// A one-pole lag can only ever be exponential, so the envelope is written as
// an explicit rate law instead. Each sample the gain moves toward the target
// by a step whose size depends on how far away the target still is:
//
//     step per sample = (curveRef / (time * SR)) * (|target - y| / curveRef)^m
//
// with m = the curve control: +1 gives a step proportional to the remaining
// distance, i.e. exponential decay with `time` as the 1/e time constant, and
// 0 gives a constant step, i.e. a straight line in dB covering curveRef dB in
// `time`. Attack is fixed at +1; Shape sets m for the release.
//
// The step deliberately depends on the current distance and nothing else. The
// obvious alternative - interpolating along a segment that restarts whenever
// the target reverses - deadlocks with a fast detector, because the target
// reverses at every zero crossing and any shape with zero initial slope gets
// its progress reset faster than it can move. Distance carries no progress, so
// there is nothing for a reversal to reset.

// The dB span the time knobs are measured over at m = 0. It only sets where
// the linear and exponential readings of the same knob agree; at m = 1 the
// knob is a time constant and this drops out entirely.
curveRef = 20;

// How far the curve is allowed to scale the nominal rate. At m = 1 the
// exponential tail would asymptote forever instead of settling; clamping the
// distance is equivalent to clamping the result, and cheaper.
curveBound = 8;

ballistics(attack, release) = loop ~ _
with {
    loop(y, target) = y + delta
    with {
        diff = target - y;
        dist = abs(diff);
        atk  = diff < 0;        // target is lower: more gain reduction wanted

        tSec = select2(atk, release, attack);
        m    = select2(atk, shape, attackCurve);

        // Integrating the rate law over a full curveRef-dB span gives a
        // transit time of tSec/(1-m), so without this the same knob setting
        // would run faster at low Shape than at 0. Only the m <= 0 half is
        // corrected; above it the knob is deliberately drifting toward its
        // time-constant meaning, which diverges at m = 1.
        norm = 1 / (1 - min(0, m));
        rate = norm * curveRef / max(ma.EPSILON, tSec * ma.SR);

        step = rate * pow(min(curveBound, max(1 / curveBound, dist / curveRef)), m);

        // never step past the target, so short times land exactly on it
        // instead of chattering around it
        delta = ma.signum(diff) * min(step, dist);
    };
};

// One band's pair of envelopes. Attack and Release arrive as signals and are
// shared by both channels, which is what makes a band a band.
ballBand(attack, release) = ballistics(attack, release), ballistics(attack, release);

//======================= Linking =======================
// Crossfade each member's own reduction against the deepest one of the set.
// Used twice with different N: across channels within a band, then across
// bands within a channel.

linkN(N, l) = si.bus(N)
            <: (si.bus(N), (ba.parallelMin(N) <: si.bus(N)))
            :  ro.interleave(N, 2)
            :  par(i, N, it.interpolate_linear(l));

//======================= Detector band split =======================
// an.analyzer emits its bands high-first, hence the ro.cross.
//
// The order has to be a constant, so all three are instantiated and the band
// signals selected between. Only the detector pays for this - the gain
// application handles the same switch without triplicating anything, see
// below. The three analyzers share nothing, but they are cheap next to the
// shelf cascade and this is the only place a runtime filter order can come
// from.
//
// Unlike a filterbank these outputs are never summed, so the even orders'
// imperfect reconstruction costs nothing: what matters is what each band
// hears, not whether the pieces add back up to the input.
//
// The select is not smoothed, unlike the shelf weights: a slope change steps
// the level each band sees, and therefore the gain computer's target. Nothing
// clicks, because the ballistics are downstream of it - the step arrives as a
// target the envelope then ramps to at the band's Attack or Release. Smoothing
// here would only be crossfading two detectors, which is not a signal anyone
// wants a compressor to track.

bandSplit = _ <: (splitAt(1), splitAt(2), splitAt(4))
          :  ro.interleave(Nba, 3)
          :  par(b, Nba, select3(slopeSel))
with {
    splitAt(o) = an.analyzer(o, xoverFreqs) : ro.cross(Nba);
};

//======================= Shelf gain application =======================
// The audio is never split. Five band gains are applied to the full-range
// signal by a cascade of low shelves, one per crossover, each carrying the
// *difference* between the bands on either side of it, plus a broadband trim
// for the top band:
//
//   y = x : ls(f1, g0-g1) : ls(f2, g1-g2) : ls(f3, g2-g3) : ls(f4, g3-g4) : *(g4)
//
// Shelf gains add in dB, so below f1 the total is (g0-g1)+(g1-g2)+...+g4 = g0,
// between f1 and f2 it is g1, and so on: every band lands on exactly its own
// gain and the sum telescopes. mbmsComp5.dsp reaches the same response with a
// low shelf, three band shelves and a high shelf - eight shelf groups where
// this needs four sections and a multiply, because a band shelf is itself two
// shelves and the middle bands' inner edges cancel against their neighbours'.
//
// ---- the slope switch ----
//
// Each shelf is three sections whose gains are weighted by a smoothed
// indicator of the Slope setting:
//
//   6 dB/oct   a 1st-order shelf,  the svf pair idle
//   12 dB/oct  one svf at Q .707,  the others idle
//   24 dB/oct  two svf at the 4th-order Butterworth Q pair, g/2 each
//
// An idle section is an exact bypass rather than a quiet one: at G = 0 the svf
// gain A is 1, its mix vector collapses to (1,0,0), and the output is the
// input sample unchanged. So this costs three sections where a fixed order
// would cost one or two, but it never needs a select and it never needs three
// whole cascades.
//
// The weights sum to 1 - si.smoo is linear and exactly one indicator is 1 at
// any moment - so the *total* dB the three sections apply is g at every point
// of a slope change, including halfway through one. Switching slope therefore
// never moves a band's gain, only the sharpness of the transition into it, and
// it morphs there instead of jumping.

w6  = (slopeSel < 0.5) : si.smoo;
w12 = (slopeSel >= 0.5) * (slopeSel < 1.5) : si.smoo;
w24 = (slopeSel >= 1.5) : si.smoo;

// Q of the first svf section. The w6 term only keeps the value away from 0
// while that section is idle; its gain is zero there, so it is never heard.
shelfQB = 0.5 * w6 + 0.70710678 * w12 + 0.54119610 * w24;
shelfQC = 1.30656296;   // second half of the 4th-order Butterworth pair

// First-order low shelf, built as a complementary split with the low half
// scaled. fi.lowpass(1) and fi.highpass(1) share a denominator and their
// numerators sum to it, so at 0 dB this is the identity and there is no
// residue for the cascade to accumulate. It is also the cheap section: the
// gain is a plain multiplier, not a coefficient recomputation.
ls1(f, g) = _ <: (fi.lowpass(1, f) : *(g : ba.db2linear)), fi.highpass(1, f) :> _;

lowShelf(f, g) = ls1(f, g * w6)
               : fi.svf.ls(f, shelfQB, g * (w12 + 0.5 * w24))
               : fi.svf.ls(f, shelfQC, g * (0.5 * w24));

// (g0..g4, x) -> y, band gains low first.
shelfCascade(g0, g1, g2, g3, g4, x) =
    x : lowShelf(xf(1), g0 - g1)
      : lowShelf(xf(2), g1 - g2)
      : lowShelf(xf(3), g2 - g3)
      : lowShelf(xf(4), g3 - g4)
      : *(g4 : ba.db2linear);

//======================= Bypass, listen and makeup =======================
// Everything static about a band collapses into two numbers: an offset in dB
// and a scale on the gain reduction.
//
//   audible, not bypassed     ->  offset = Makeup,       scale = 1
//   bypassed                  ->  offset = 0,            scale = 0
//   muted by another Listen   ->  offset = Listen Floor, scale = 0
//
// Both are smoothed, and the gain reduction is not: the ballistics are already
// the smoothing on that half, and running si.smoo over the sum would drag the
// attack out. Scaling rather than gating the reduction means Bypass fades it
// out over the smoother's time constant instead of dropping it.
//
// Listen is read as a bus and its sum broadcast back, rather than each band
// asking "is anything on Listen" for itself - calling listenOf twice would
// declare the widget twice.

bandStatic(n, listen, anyListen) = offset, scale
with {
    byp     = bypassOf(n);
    audible = select2(anyListen > 0, 1, listen);
    active  = audible * (1 - byp);
    offset  = select2(audible, listenFloorDb, makeupOf(n) * active) : si.smoo;
    scale   = active : si.smoo;
};

bandStatics = listen_array
            <: (si.bus(Nba), (si.bus(Nba) :> _ <: si.bus(Nba)))
            :  ro.interleave(Nba, 2)
            :  par(b, Nba, bandStatic(b+1));

// (offset, scale, gr per channel) -> the band's dB gain per channel, with each
// channel's own reduction metered on the way past.
bandGains(n, offset, scale, y0, y1) = attach(g0, m0), attach(g1, m1)
with {
    r0 = y0 * scale;
    r1 = y1 * scale;
    m0 = r0 : bandMeterM(n);
    m1 = r1 : bandMeterS(n);
    g0 = r0 + offset;
    g1 = r1 + offset;
};

//======================= Routing =======================
// Two layouts are used throughout and swapped with ro.interleave, which reads
// C groups of R and writes R groups of C:
//
//   band-major     Nba groups of Nch   (b0c0 b0c1 b1c0 ...)
//   channel-major  Nch groups of Nba   (c0b0 c0b1 ... c1b0 ...)
//
// The two routes below are the ones interleave cannot express, because they
// merge buses of different group sizes.

// (offset,scale per band) ++ (gr, band-major) -> Nba groups of (2 + Nch)
zipStatics = route(Nba * (2 + Nch), Nba * (2 + Nch),
    par(b, Nba, (2*b + 1, (2+Nch)*b + 1,
                 2*b + 2, (2+Nch)*b + 2)),
    par(b, Nba, par(c, Nch, (2*Nba + Nch*b + c + 1, (2+Nch)*b + 2 + c + 1))));

// (gains, channel-major) ++ (audio) -> Nch groups of (Nba + 1)
mergeAudio = route(Nch*Nba + Nch, Nch*(Nba + 1),
    par(c, Nch, par(b, Nba, (c*Nba + b + 1, c*(Nba+1) + b + 1))),
    par(c, Nch, (Nch*Nba + c + 1, c*(Nba+1) + Nba + 1)));

//======================= Gain reduction, all bands =======================
// Nch audio in, Nba*Nch band gains out in channel-major order.
//
// No feedback loop: the detector is fed forward only, so unlike compressor.dsp
// this whole chain is a straight line.
//
// The order of the stages is deliberate:
//
//   level -> gain computer -> channel link -> band link -> Range -> ballistics
//
// Both links act on the gain computer's *target*, before the ballistics, so
// linked members share one envelope instead of several racing. Channel link
// runs first so that Band Link at 100% collapses onto an already stereo-linked
// target rather than the other way round; the two commute anyway, since both
// are a crossfade toward a minimum over disjoint axes. Range sits after both
// and before the ballistics, so what each envelope chases is the finished
// target, and it costs nothing to move past the links because a monotonic
// limit commutes with a minimum.

grCompute = par(c, Nch, bandSplit : par(b, Nba, levelDb))   // channel-major
          : (thresh_array, ratio_array, si.bus(Nba * Nch))
          : ro.interleave(Nba, 2 + Nch)                     // (th, ratio, x..) per band
          : par(b, Nba, gcBand)                             // band-major
          : ro.interleave(Nch, Nba)                         // channel-major
          : par(c, Nch, linkN(Nba, bandLink))
          : par(i, Nba * Nch, rangeLimit)
          : (attack_array, release_array, si.bus(Nba * Nch))
          : ro.interleave(Nba, 2 + Nch)                     // (att, rel, gr..) per band
          : par(b, Nba, ballBand)                           // band-major
          : (bandStatics, si.bus(Nba * Nch))
          : zipStatics
          : par(b, Nba, bandGains(b+1))                     // band-major
          : ro.interleave(Nch, Nba)                         // channel-major
with {
    gcBand(thresh, ratio) = gainComputer(thresh, ratio), gainComputer(thresh, ratio)
                          : linkN(Nch, chanLink);
};

//======================= Mid/side =======================
// Same encode and decode as common/input.dsp and common/output.dsp, so the two
// agree on scaling and cancel exactly when the common section's own mid/side
// switch is also engaged.
//
// Unconditional here - this compressor has no L/R mode - so there is no select
// in the path and nothing to smooth. The pair is an exact algebraic inverse:
// (m+s) = (l+r)/2 + (l-r)/2 = l. In single precision it is not quite: measured
// against noise with every band idle, the wet path nulls against its input to
// 5.8e-7 peak, -125 dBFS, and the figure is the same at all three slopes, so it
// is the round trip and the first-order shelves' complementary sum rather than
// anything that varies with the settings. Read every "exact bypass" claim
// elsewhere in this file as exact to that rather than to the bit - except
// Dry/Wet at 0%, which nulls to a true zero because the dry tap goes nowhere
// near any of this.

msEnc(l, r) = (l + r) * 0.5, (l - r) * 0.5;
msDec(m, s) = m + s, m - s;

//======================= Wet path =======================
// The detector reads the signal undelayed while the audio goes through the
// lookahead delay, which is the whole point: by the time a transient reaches
// the shelves their gains are already in place.
//
// Everything between the encode and the decode is mid/side: the band split,
// the detector, the linking and the shelves all see mid on channel 0 and side
// on channel 1. The decode is the last thing in the wet path, so Dry/Wet still
// blends two left/right signals.

wetChain = msEnc
         <: (grCompute,
             par(c, Nch, de.delay(maxLookaheadSamples, lookaheadSamples)))
         :  mergeAudio
         :  par(c, Nch, shelfCascade)
         :  msDec;

//======================= Dry/wet =======================
// Linear crossfade, not equal-power: dry and wet are the same signal with
// different gain envelopes, so they sum coherently and a 3 dB law would bulge
// to +3 dB in the middle of the knob.
//
// The dry is delayed to match the wet's lookahead. Without it the blend is a
// comb filter with up to 50 ms of offset - the one thing parallel compression
// must not do.

dryWetMix = (par(c, Nch, de.delay(maxLookaheadSamples, lookaheadDelay)), si.bus(Nch))
          : ro.interleave(Nch, 2)
          : par(c, Nch, blend)
with {
    // si.smoo is a one-pole whose fixed point lands 1.7e-5 short of 1 in
    // single precision, so Dry/Wet at 100% would leave the untouched input
    // mixed in at -95 dB for as long as the plugin runs. Scaling by a hair and
    // clamping puts the top of the travel exactly on 1. The bottom needs no
    // such help - the same one-pole decays to a true zero.
    dw = min(1, drywet * 1.0001);

    blend(d, w) = d * (1 - dw) + w * dw;
};

//======================= process =======================

process = si.bus(Nch) <: (si.bus(Nch), wetChain) : dryWetMix;
