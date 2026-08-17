// -*-Faust-*-

declare author "Klaus Scheuermann";
declare description "";
declare license "GPL-3.0-or-later";
declare name "Compressor";
declare unique_id "LAco";

// Dry/wet is built here rather than taken from the host wrapper, so the flag
// stays off — leaving it on would stack the wrapper's common "Dry / Wet" on
// top of this one and give the plugin two controls that do the same thing.
//
// The difference between the two is where the dry is tapped. The wrapper
// crossfades against the plugin's *input*, upstream of the common Input
// section; the control below taps the audio as this DSP receives it, so the
// parallel path is the signal the compressor itself was handed. See the
// Output section and `process` at the bottom.
// declare drywet "true";

import("stdfaust.lib");

// number of channels. The mid/side path below assumes exactly 2.
Nch = 2;

// The compressor engine takes 4 inputs: 1-2 audio, 3-4 external sidechain.
// src/DistrhoPluginInfo.h #errors on anything but 2 inputs, and config.h.in
// takes DISTRHO_PLUGIN_NUM_INPUTS straight from this DSP's input count, so
// until the DPF side grows a sidechain port group `process` presents 2 inputs
// and feeds the engine's sidechain pair from a copy of the audio. See the
// bottom of the file for the one-line change that opens the real inputs.

maxGR = -60; // meter floor, also the widest Range setting
maxMeter = -20;

maxLookaheadSamples = 9600; // 50 ms at 192 kHz

//======================= GUI =======================

comp_group(x)  = vgroup("Compressor", x);
meter_group(x) = comp_group(vgroup("[1]Meters", x));
knob_group(x)  = comp_group(hgroup("[0]Controls", x));

ctl_group(x)   = knob_group(hgroup("[0]Compression Control", x));
env_group(x)   = knob_group(hgroup("[1]Compression Response", x));
det_group(x)   = knob_group(hgroup("[2]Detector", x));
sc_group(x)    = knob_group(hgroup("[3]Sidechain Filter", x));
out_group(x)   = knob_group(hgroup("[4]Output", x));

//---- gain computer ----

threshold = ctl_group(vslider("[0]Threshold[unit:dB][symbol:threshold]
      [tooltip: Level above which the signal is compressed]",
                              -18, maxGR, 0, 0.1));

ratio = ctl_group(vslider("[1]Ratio[scale:log][symbol:ratio]
      [tooltip: dB in per dB out above the threshold. 1 = no compression]",
                          4, 1, 20, 0.01));

// slope = the fraction of every dB of overshoot that gets removed
slope = 1 - 1 / max(1, ratio);

knee = ctl_group(vslider("[2]Knee[unit:dB][symbol:knee]
      [tooltip: Width of the soft transition around the threshold. The ratio
       reaches its full value knee/2 dB above the threshold and is 1:1
       knee/2 dB below it]",
                         6, 0, 24, 0.1));

range = ctl_group(vslider("[3]Range[unit:dB][symbol:range]
      [tooltip: Ceiling on total gain reduction. The compressor never pulls
       the signal down by more than this, no matter how far over threshold]",
                          60, 0, 0 - maxGR, 0.1));
rangeKnee = knee; 

// rangeKnee = ctl_group(vslider("[4]Range Knee[unit:dB][symbol:range_knee]
//       [tooltip: Softens the approach to the Range ceiling the same way Knee
//        softens the approach to the threshold. 0 = hard clamp]",
//                               6, 0, 24, 0.1));

// Per-channel depth trims. Channel 1 is left or mid and channel 2 is right or
// side, depending on the Mid / Side switch, hence the paired labels.
//
// These are applied after linking, so they still separate the two channels at
// Link 100%: linking decides what the pair *detects* together, Scale decides
// how much of that each one acts on. Turning Side down to 40% while Mid stays
// at 100% is the point of having them, and it would be flattened by the
// parallelMin if it happened before the link.

scaleLM = ctl_group(vslider("[5]Scale L/M[unit:%][symbol:scale_lm]
      [tooltip: Multiplies the gain reduction on channel 1 - left, or mid when
       Mid / Side is on. 0% = that channel is not compressed at all whatever
       the other settings say, 100% = as computed, 200% = twice as many dB of
       reduction. Applied before Range, so the Range ceiling still holds]",
                            100, 0, 200, 1)) / 100;

scaleRS = ctl_group(vslider("[6]Scale R/S[unit:%][symbol:scale_rs]
      [tooltip: Multiplies the gain reduction on channel 2 - right, or side when
       Mid / Side is on. Pulling this below Scale L/M compresses the centre
       harder than the edges of the image, which is the usual mid/side move]",
                            100, 0, 200, 1)) / 100;

chanScale(0) = scaleLM;
chanScale(1) = scaleRS;

//---- ballistics ----

attack = env_group(vslider("[0]Attack[unit:ms][scale:log][symbol:attack]
      [tooltip: How fast the gain moves toward a deeper reduction. Read as a
       1/e time constant at Attack Curve +1, or as the time to cover 20 dB at
       Attack Curve 0 and below]",
                           10, 0.01, 100, 0.01)) * 0.001;

attackCurve = env_group(vslider("[1]Attack Curve[symbol:attack_curve]
      [tooltip: Shape of the attack ramp. +1 = exponential, analog-style: quick
       off the mark then easing in, and Attack reads as a time constant.
       0 = straight line in dB. -1 = creeps in then snaps shut at the end]",
                                1, -1, 1, 0.01));

hold = env_group(vslider("[2]Hold[unit:ms][symbol:hold]
      [tooltip: How long the gain reduction is frozen at its deepest point
       before release is allowed to start]",
                         0, 0, 100, 0.1)) * 0.001;

release = env_group(vslider("[3]Release[unit:ms][scale:log][symbol:release]
      [tooltip: How fast the gain moves back up toward a lighter reduction. Read
       as a 1/e time constant at Release Curve +1, or as the time to cover 20 dB
       at Release Curve 0 and below. With Release S-Curve on it is the time to
       cover 20 dB at every Release Curve setting, and shallower recoveries
       take proportionally less]",
                            150, 1, 2000, 0.1)) * 0.001;

releaseCurve = env_group(vslider("[4]Release Curve[symbol:release_curve]
      [tooltip: Shape of the release ramp. +1 = exponential, analog-style: lets
       go quickly then a long tail, and Release reads as a time constant.
       0 = straight line in dB. -1 = hangs, then lets go all at once.
       With Release S-Curve on this slides where the ramp is steepest instead]",
                                 1, -1, 1, 0.01));

releaseS = env_group(checkbox("[5]Release S-Curve[symbol:release_s]
      [tooltip: Eases the release out of the reduction and back into unity
       instead of running at full speed at one end. Release Curve still pushes
       and pulls it, sliding the steep part of the ramp between roughly 1 dB
       and 20 dB from the target - late and abrupt at -1, early and gentle at
       +1 - but both ends keep the soft landing. Affects release only]"));

autoRelease = env_group(vslider("[6]Auto Release[unit:%][symbol:auto_release]
      [tooltip: Program dependence. Stretches Release in proportion to how much
       reduction has been sustained recently, so isolated peaks let go quickly
       while a loud passage releases slowly and stops pumping. 0% = fixed]",
                                0, 0, 100, 1)) / 100;

lookaheadMs = env_group(vslider("[7]Lookahead[unit:ms][symbol:lookahead]
      [tooltip: Delays the audio so the gain is already down when the transient
       arrives. Reported to the host as latency and compensated. 0 = off]",
                                0, 0, 50, 0.1));

holdSamples      = hold * ma.SR;

// Two names for one number. The dry side of the Dry/Wet mix has to be delayed
// by the same lookahead as the wet, but it must not carry the meter with it:
// latency_meter is a widget, and reusing the metered version would declare a
// second bargraph with the same symbol, which is what the build reads the
// plugin's reported latency off.
lookaheadDelay   = int(lookaheadMs * ma.SR / 1000);
lookaheadSamples = lookaheadDelay : latency_meter;

// How far back Auto Release looks, and how much sustained reduction it takes
// to double the release time.
autoTau   = 0.5;
autoRefDb = 6;

// The dB span the time knobs are measured over at curve = 0. It only sets
// where the linear and exponential readings of the same knob agree; at
// curve = +1 the knob is a time constant and this drops out entirely.
curveRef = 20;

// How far the curve is allowed to scale the nominal rate, in either
// direction. Both ends need the cap: at curve = -1 the rate goes as 1/distance
// and would run away to thousands of dB/s in the last fraction of a dB (a peak
// detector's ripple then wipes out the release entirely), and at curve = +1 the
// exponential tail would asymptote forever instead of settling. Clamping the
// distance is equivalent and cheaper than clamping the result.
curveBound = 8;

// ---- S-curve release ----
// See the Ballistics section for the rate law.
//
// The one thing this shape needs that the power law does not is a sense of
// scale. An S has to be slow, then fast, then slow, and "then" only means
// something relative to the length of the ramp: an inflection point fixed at
// some number of dB from the target is either crossed or it is not, so the
// same setting that gives a clean S on a 20 dB release gives a plain
// exponential on a 4 dB one, which is most of what a compressor actually
// does. Measured: with the inflection pinned 5 dB out, excursions under about
// 3 dB came out with their steepest point at t = 0, i.e. no S at all.
//
// So the ramp is measured as a *fraction of its own span* instead, and the
// span is carried in the loop below as sp. That makes the curve self-similar:
// the same S at 2 dB as at 20 dB, only shorter.
//
// sPeakMid    where the ramp is steepest with Release Curve at 0, as a
//             fraction of the span. 0.45 is just short of halfway.
// sPeakSpread how far Release Curve slides that point. 1.8 spans 0.25 to 0.81
//             of the way through - late and abrupt at -1, early and gentle at
//             +1. It has to stay clear of both 0 and 1 or the S degenerates
//             into a one-sided curve at the ends of the knob.
// sBound      the same job curveBound does for the power law, but wider, and
//             for a different reason: here it truncates the soft landing
//             rather than stopping a runaway. At 8 the ramp is still at 80%
//             of full speed when the clamp takes over and the ease-out is
//             barely audible; 64 lets it get down to an eighth. The near
//             branch decays toward zero instead of blowing up, so widening it
//             is safe - the cost is only the last 1/64 of the span taking a
//             little longer.
// sSpanFloor  smallest span the shape is computed against, in dB. Keeps the
//             division honest when the gain is sitting still.
sPeakMid    = 0.45;
sPeakSpread = 1.8;
sBound      = 64;
sSpanFloor  = 0.5;

sPeak = sPeakMid * pow(sPeakSpread, releaseCurve);

// How long the remembered span takes to fade once nothing is renewing it.
// Tied to Release so it always outlasts the ramp it is measuring - a fixed
// time constant would either forget mid-release at the slow end of the knob
// or hold a stale span across separate events at the fast end.
sSpanTau  = max(0.05, 4 * release);
sSpanPole = ba.tau2pole(sSpanTau);

// Timing normalisation. sNorm is the closed form of the raw shape's transit
// time - the integral of 1/sShape from w = 1 down to the clamp, plus the
// clamped remainder - so dividing it back out fixes the total. Release then
// means the same thing it means at Release Curve 0 in the power law, the time
// to cover curveRef dB, and Release Curve reshapes the ramp without also
// retiming it. Because w is a fraction of the span, that scales: a 5 dB
// release takes a quarter as long as a 20 dB one, at constant dB per second.
sNorm = sPeak * (log(sBound) + 1) / 2 + (1 + 1 / (sBound * sBound)) / (4 * sPeak);

// Rate multiplier: a hump in the fraction of the span still to go, peaking at
// sPeak. It is the harmonic mean of the two power-law extremes - w^-1 far
// from the target, w^+1 near it - which is exactly why it inherits the slow
// start of Release Curve -1 and the slow finish of +1 in one ramp.
sShape(dist, span) = sNorm * 2 * sPeak * w / (sPeak * sPeak + w * w)
with {
    w = min(1, max(1 / sBound, dist / span));
};

//---- detector ----

peakRms = det_group(vslider("[0]Peak / RMS[unit:%][symbol:peak_rms]
      [tooltip: What the detector measures. 0% = peak, catches every transient.
       100% = RMS over the window below, follows loudness and ignores spikes]",
                            0, 0, 100, 1)) / 100;

rmsTime = det_group(vslider("[1]RMS Time[unit:ms][symbol:rms_time]
      [tooltip: Averaging window of the RMS half of the detector. Has no effect
       at Peak / RMS 0%]",
                            10, 0, 250, 0.1)) * 0.001;

feedback = det_group(vslider("[2]Feedback[unit:%][symbol:feedback]
      [tooltip: Where the detector listens. 0% = feed-forward (detector sees
       the input, exact ratio), 100% = feed-back (detector sees the compressed
       output, softer and more program dependent)]",
                             0, 0, 100, 1)) / 100;

link = det_group(vslider("[3]Link[unit:%][symbol:link]
      [tooltip: 0% = every channel gets its own gain reduction, 100% = all
       channels follow the most-reduced one, so the stereo image never shifts]",
                         100, 0, 100, 1)) / 100;

msOn = det_group(checkbox("[4]Mid / Side[symbol:mid_side]
      [tooltip: Compress mid and side separately instead of left and right.
       Note the common Input and Output sections already carry a global
       mid/side switch that wraps every plugin the same way]"));

//---- sidechain source and filter ----
// Shapes what the detector hears, never the audio.

scMix = sc_group(vslider("[0]SC Mix[unit:%][symbol:sc_mix]
      [tooltip: Crossfades the detector between the plugin's own audio (0%) and
       the external sidechain (100%). While the sidechain pair is fed from a
       copy of the audio it does little beyond bypassing Feedback, but the
       parameter is here so the layout does not change once the real inputs
       are wired up]",
                         0, 0, 100, 1)) / 100;

scHp = sc_group(vslider("[1]SC High Pass[unit:Hz][scale:log][symbol:sc_hp]
      [tooltip: Keeps bass out of the detector so kick and low end stop driving
       the whole gain envelope. 20 Hz = effectively off]",
                        20, 20, 500, 1));

scLp = sc_group(vslider("[2]SC Low Pass[unit:Hz][scale:log][symbol:sc_lp]
      [tooltip: Keeps air and hiss out of the detector. 20 kHz = effectively off]",
                        20000, 1000, 20000, 1));

scTilt = sc_group(vslider("[3]SC Tilt[unit:dB][symbol:sc_tilt]
      [tooltip: Broad weighting of the detector across the spectrum, pivoting at
       SC Freq. Positive makes it hear highs, so it reacts to sibilance and
       cymbals; negative makes it hear the low end]",
                          0, -12, 12, 0.1));

scFreq = 700;

scRes = 0.7; // shelf Q for the tilt pair — flat, no bump at the pivot

//---- output ----

// Ordered to follow the audio path: colour, then makeup, then the blend.

satDepth = out_group(vslider("[0]Drive[unit:%][symbol:drive]
      [tooltip: How much harmonic colour the output stage adds, scaled by how
       hard the compressor is working. At 0% it is an exact bypass, and it
       stays one at any setting while the compressor is idle - the drive is
       tied to gain reduction, so a passage that is not being compressed is
       not being coloured either. Only the low band is saturated, so the top
       end stays clean]",
                             0, 0, 50, 1)) / 100 : si.smoo;

satBias = 0.75;
      // out_group(vslider("[1]Bias[unit:%][symbol:bias]
      // [tooltip: Shifts the harmonic series the colour generates. 0% is a
      //  symmetric curve and gives odd harmonics only - the harder, more
      //  console-like sound. Turning it up makes the curve asymmetric and brings
      //  in even harmonics, which read as warmth rather than edge. No effect at
      //  Drive 0%]",
      //                       0, 0, 100, 1)) / 100 : si.smoo;

makeupDb = out_group(vslider("[2]Makeup[unit:dB][symbol:makeup]
      [tooltip: Output trim, to put back the level the compressor took away.
       Applied after the gain stage and after the colour, so it lifts the whole
       signal and does not feed back into the detector, change where the
       threshold sits, or change how hard the output stage is driven]",
                             0, -12, 24, 0.1));

drywet = out_group(vslider("[3]Dry / Wet[unit:%][symbol:drywet]
      [tooltip: Blend of the compressed signal against the untouched input, for
       parallel compression. 100% = compressor only, 0% = bypassed. The dry
       side is delayed to match Lookahead, so the two stay phase aligned and
       the blend never combs]",
                           100, 0, 100, 1)) / 100 : si.smoo;

// Smoothed because it multiplies the audio directly. The compression controls
// need no such treatment: they move the ballistics' *target*, and the attack
// and release ramps are already the smoothing.
makeupGain = makeupDb : si.smoo : ba.db2linear;

// Shelf pair pivoting at scFreq, same construction as the Shelf mode of
// tiltEQ.dsp: equal and opposite low and high shelves.
scFilter = fi.highpass(2, scHp)
         : fi.lowpass(2, scLp)
         : fi.svf.ls(scFreq, scRes, 0 - scTilt)
         : fi.svf.hs(scFreq, scRes, scTilt);

//---- meters ----

meter1 = _ <: (_, (max(maxMeter) : meter_group(hbargraph("[0]GR 1[unit:dB][symbol:gr_1]", maxMeter, 0)))) : attach;
meter2 = _ <: (_, (max(maxMeter) : meter_group(hbargraph("[1]GR 2[unit:dB][symbol:gr_2]", maxMeter, 0)))) : attach;

//meter1 = _ <: (_, ( ma.neg : min(maxMeter) : meter_group(hbargraph("[0]GR 1[unit:dB][symbol:gr_1]", 0, maxMeter)))) : attach;
//meter2 = _ <: (_, ( ma.neg : min(maxMeter) : meter_group(hbargraph("[1]GR 2[unit:dB][symbol:gr_2]", 0, maxMeter)))) : attach;

chanMeter(0) = meter1;
chanMeter(1) = meter2;

// A passive widget with this exact symbol is what the build turns into the
// plugin's reported latency (see the latency_samples cases in
// src/templates/dsp.cpp.in), so the host delay-compensates Lookahead.
latency_meter = _ <: attach(_, meter_group(hbargraph("[2]latency_samples[symbol:latency_samples]", 0, maxLookaheadSamples)));

//======================= Level detector =======================
// Peak and RMS are computed as two dB readings and crossfaded, rather than
// switched. The RMS half is a one-pole average of the squared signal; as
// rmsTime goes to 0 its pole goes to 0 and it collapses to |x|, so the two
// halves meet continuously and no setting of the pair can produce a jump.

levelDb(x) = it.interpolate_linear(peakRms, peakDb, rmsDb)
with {
    peakDb = abs(x)
           : max(ma.EPSILON)
           : ba.linear2db;

    rmsDb  = x * x
           : si.smooth(ba.tau2pole(max(rmsTime, 1e-6)))
           : sqrt
           : max(ma.EPSILON)
           : ba.linear2db;
};

//======================= Gain computer =======================
// Returns gain reduction in dB, always <= 0.
//
// Below thresh-knee/2 nothing happens, above thresh+knee/2 the full ratio
// applies, and in between a quadratic bridges the two. The quadratic is the
// unique parabola that matches both value and slope at each end, which is
// what makes the knee audibly smooth rather than merely continuous.

gainComputer(level) = select3(zone, 0, softPart, hardPart)
with {
    over     = level - threshold;
    zone     = (over > 0 - knee / 2) + (over > knee / 2);
    softPart = 0 - slope * pow(over + knee / 2, 2) / (2 * max(ma.EPSILON, knee));
    hardPart = 0 - slope * over;
};

//======================= Range ceiling =======================
// Same parabola trick as the knee, mirrored: instead of easing *into*
// compression it eases into the floor, so a signal that slams far past the
// Range setting doesn't hit a corner in the gain curve.

rangeLimit(gr) = select3(zone, lim, soft, gr)
with {
    lim  = 0 - range;
    d    = gr - lim;

    // The soft floor peaks at lim + rk/2, so a knee wider than twice the
    // Range would lift the "gain reduction" above 0 dB and the compressor
    // would quietly turn into a 3 dB boost (measured, with Range 0 and Range
    // Knee 24). Capping the knee at 2*range pins that peak to exactly 0 dB
    // and degrades to a hard clamp as Range approaches 0, which is what
    // Range 0 should mean anyway.
    rk   = min(rangeKnee, 2 * range);

    zone = (d > 0 - rk / 2) + (d > rk / 2);
    soft = lim + pow(d + rk / 2, 2) / (2 * max(ma.EPSILON, rk));
};

//======================= Ballistics =======================
// Curved attack/release with hold and program-dependent release.
//
// A one-pole lag can only ever be exponential, so the envelope is written as
// an explicit rate law instead. Each sample the gain moves toward the target
// by a step whose size depends on how far away the target still is:
//
//     step per sample = (curveRef / (time * SR)) * (|target - y| / curveRef)^m
//
// with m = the curve control:
//
//   m = +1  step proportional to the remaining distance -> exponential decay,
//           and `time` is exactly the 1/e time constant (curveRef cancels)
//   m =  0  step constant -> straight line in dB, curveRef dB per `time`
//   m = -1  step inversely proportional to the distance -> hangs back, then
//           accelerates into the target
//
// The step deliberately depends on the current distance and nothing else.
// The obvious alternative - interpolating s + (target-s)*p^k along a segment
// that restarts whenever the target reverses - deadlocks here: with peak
// detection the target reverses at every zero crossing, and any shape with
// zero initial slope gets its progress reset faster than it can move. Built
// that way, this compressor measurably froze at 0.0001 dB of reduction.
// Distance carries no progress, so there is nothing for a reversal to reset.
//
// Release S-Curve swaps that power of m for a different function of the same
// distance, and changes nothing else:
//
//     step per sample = (curveRef / (time * SR)) * sNorm * 2f w / (f^2 + w^2)
//
// with w = the fraction of the span still to go and f = where in that span
// the ramp is steepest, which is what Release Curve now sets. The shape is
// the harmonic mean of the m = -1 and m = +1 laws, so it starts slow like one
// and lands slow like the other, and Release Curve slides the fast part
// between them. Measured on a 20 dB release, the steepest point moves from
// 9% of the way through at +1 to 76% at -1, and holds that spread down to 5 dB
// excursions; total time stays within 15% of the knob across the whole range,
// where the power law's +1 setting takes three times its nominal.
//
// Because the switch is ANDed with the release half, an attack always takes
// the power law. Verified as bit-identical, though only once the detector is
// given a ripple-free signal - on ordinary material the level ripples, the
// envelope micro-releases inside the attack, and those samples do differ,
// which is the release law doing its job rather than a leak.
//
// Hold freezes the gain while the target is trying to release, until the
// counter runs out. Any renewed attack resets the counter, so hold always
// measures from the most recent deepest point.
//
// The S-curve release is the one shape that needs more than the current
// distance, because "halfway" is only meaningful against a total. sp carries
// that total: a peak-hold of the distance with a slow decay, which reads as
// the depth of the excursion currently being released. It is deliberately a
// peak-hold rather than a latch on the release edge - with peak detection the
// target reverses constantly, and a latch would re-arm on every one of those
// reversals and collapse the span to the ripple. Note this is still not
// progress: the rate stays strictly positive at every distance, so there is
// nothing here that a reversal can freeze.

ballistics = loop ~ si.bus(3) : (_, !, !)
with {
    loop(y, hc, sp, target) = ny, nhc, nsp
    with {
        diff = target - y;
        dist = abs(diff);
        atk  = diff < 0;        // target is lower: more gain reduction wanted

        nhc     = select2(atk, min(holdSamples, hc + 1), 0);
        holding = (diff > 0) * (nhc < holdSamples);

        nsp = max(sSpanFloor, max(dist, sp * sSpanPole));

        // Program dependence, read off the compressor's own recent history:
        // a slow average of how much reduction has been in effect. A lone
        // transient barely moves it and releases at the knob setting, while a
        // sustained loud passage stretches the release out.
        hist   = abs(y) : si.smooth(ba.tau2pole(autoTau));
        relEff = release * (1 + autoRelease * hist / autoRefDb);

        tSec = select2(atk, relEff, attack);
        m    = select2(atk, releaseCurve, attackCurve);

        // Integrating the rate law over a full curveRef-dB span gives a
        // transit time of tSec/(1-m), so without this the same knob setting
        // would run twice as fast at curve = -1 as at curve = 0. Only the
        // m <= 0 half is corrected; above it the knob is deliberately drifting
        // toward its time-constant meaning, which diverges at m = 1.
        norm = 1 / (1 - min(0, m));
        rate = norm * curveRef / max(ma.EPSILON, tSec * ma.SR);

        // The S-curve is an alternative shape for the same rate law, not an
        // alternative envelope: it swaps out the distance-to-step function and
        // nothing else, so hold, Auto Release and the never-overshoot clamp
        // below all keep working untouched. Release side only - the switch is
        // ANDed with the release half, so an attack always uses the power law
        // whatever the checkbox says.
        //
        // The two are selected as finished steps rather than as shapes sharing
        // one rate, so that the power-law branch stays the exact expression it
        // always was. Factoring norm out of rate to share it would reassociate
        // the multiply, and a last-bit change inside a recursive envelope does
        // not stay a last-bit change: measured over two seconds it random-walks
        // to about 1e-4 relative. Inaudible, but it would make this switch look
        // like it alters the sound when it is off.
        powStep = rate * pow(min(curveBound, max(1 / curveBound, dist / curveRef)), m);
        sStep   = curveRef / max(ma.EPSILON, tSec * ma.SR) * sShape(dist, nsp);

        step = select2(releaseS * (1 - atk), powStep, sStep);

        // never step past the target, so short times land exactly on it
        // instead of chattering around it
        delta = ma.signum(diff) * min(step, dist);

        ny  = select2(holding, y + delta, y);
    };
};

//======================= Gain reduction, N channels =======================
// The whole detector chain sits inside one feedback loop so that the
// detector can be fed from the *output* gain. Feedback at 0% multiplies the
// input by 0 dB, i.e. leaves it alone, so feed-forward is not a special
// case - it is the same code path with the loop gain turned off.
//
// Note the ratio knob is only literally true feed-forward. In feed-back the
// detector already sees the reduced signal, so the effective ratio rises
// with drive; that program dependence is the point of the mode, not a bug.
//
// Linking happens on the gain computer's *target*, before the ballistics,
// so linked channels share one envelope instead of two envelopes racing.
//
// The order of the last three stages is deliberate:
//
//   gain computer -> link -> Scale -> Range -> ballistics
//
// Link before Scale, so the per-channel Scale trims survive linking instead of
// being flattened by the parallelMin. Range after Scale, so the Range ceiling
// still caps the reduction that is actually applied at any Scale. And both
// before the ballistics, so what the envelope chases is the finished target.
// Moving Range past the link costs nothing: it is monotonic, so limiting each
// channel and then taking the minimum gives the same answer as taking the
// minimum and then limiting.
//
// Takes 2*Nch inputs - the audio, then the external sidechain - and returns
// Nch gain reductions in dB. ro.interleave(Nch,3) turns the loop's
// [gr.., audio.., sc..] into one (gr, audio, sc) triple per channel.

grComputeN = loop ~ si.bus(Nch)
with {
    loop = ro.interleave(Nch, 3)
         : par(i, Nch, detTarget)
         : linkN(Nch, link)
         : par(i, Nch, *(chanScale(i)) : rangeLimit)
         : par(i, Nch, ballistics);

    // SC Mix crossfades in the signal domain, ahead of the filter, so there is
    // only one filter instance per channel and a blend of two different
    // sources reads as their sum - which is what mixing a key into the program
    // should do. Only the internal side carries the feedback gain; the external
    // input is not the compressor's own output, so it is never fed back.
    detTarget(grPrev, x, sc) = it.interpolate_linear(scMix, internal, sc)
                             : scFilter : levelDb : gainComputer
    with {
        internal = x * ba.db2linear(grPrev * feedback);
    };
};

// crossfade each channel's own reduction against the deepest one of the set
linkN(N, l) = si.bus(N)
            <: (si.bus(N), (ba.parallelMin(N) <: si.bus(N)))
            :  ro.interleave(N, 2)
            :  par(i, N, it.interpolate_linear(l));

//======================= Mid/side =======================
// Same encode/decode as common/input.dsp and common/output.dsp, so the two
// agree on scaling and cancel exactly when both are engaged.

msEnc(l, r) = select2(msOn, l, (l + r) * 0.5),
              select2(msOn, r, (l - r) * 0.5);

msDec(m, s) = select2(msOn, m, m + s),
              select2(msOn, s, m - s);

//======================= Output colour =======================
// A saturating output stage, sitting after the gain and the mid/side decode
// and before makeup, driven by how hard the compressor is working rather than
// by a knob of its own.
//
// Band-limited on purpose, and not only for the reason it sounds like. A
// waveshaper generates harmonics at multiples of whatever it is fed, and any
// of those above Nyquist fold back down as inharmonic tones - the fizz that
// makes cheap saturation sound cheap. Restricting the shaper to the low band
// means the harmonics it can produce mostly land below Nyquist to begin with,
// so no oversampling is needed to keep it clean. It is also what the hardware
// being imitated actually does: transformers and tubes saturate in the low
// and low-mid range and leave the top comparatively alone.
//
// The obvious alternative was Faust's antialiased nonlinearities, aanl.lib.
// Measured at 48 kHz they cost 5 dB at 15 kHz and 12 dB at 20 kHz at every
// level, because first-order ADAA is a two-point average as well as a
// half-sample delay; and below about -50 dBFS the difference quotient loses
// conditioning in single precision and emits more junk than signal (119% of
// the fundamental at 1 kHz at -60 dBFS). The half-sample delay would also
// have broken the dry path's phase alignment. A band split has none of that.
// Known characteristic, not a defect: the shaper works on absolute level, so
// the same Drive colours a hot signal much more than a quiet one. Measured at
// a constant 9 dB of reduction and Bias 0, total distortion runs 7.3% at
// -6 dBFS, 2.2% at -12, 0.37% at -20 and 0.01% at -40. The gain reduction
// sets how far the drive is turned up; the level still decides how much of
// that drive the signal actually meets, exactly as an output stage does.
// Referencing the drive to Threshold instead would make it level-independent,
// at the cost of tying the colour to a control that is nominally about when
// the compressor starts working.
satXover    = 800;   // Hz - crossover; only what is below this gets shaped
satOrder    = 1;      // lowpass order for the split
satRefDb    = 12;     // gain reduction at which the drive reaches full
satDriveMax = 64;     // shaper drive at Drive 100% and satRefDb of reduction
satBiasMax  = 0.7;    // offset into the curve at Bias 100%

// The knob is squared on its way to that ceiling. Raising the ceiling alone
// would have made the control useless below about a tenth of its travel: the
// distortion a shaper produces goes with roughly the square of the drive, so
// a linear map to 64 puts everything from transparent to obvious inside the
// first 10% and spends the remaining 90% on degrees of destruction. Squaring
// spreads it out - the knob's midpoint lands on 16, twice the whole range
// this had before, and the bottom third stays fine enough to use as polish.
satDriveCurve(depth) = depth * depth;

// One drive for both channels, taken from the deeper of the two reductions.
// Per-channel drive would let left and right saturate by different amounts
// whenever Link is below 100% or the Scale trims are uneven, and a nonlinearity
// harder on one side than the other pulls the image toward the quieter one.
// Measured with Link 0% and the Scale trims 100/40, turning Drive from 0 to
// 100% moves the left/right balance of the fundamental by 0.002 dB.
//
// The two channels still end up with slightly different harmonic content -
// 3.9% against 5.2% in that same test - because they arrive at the output
// stage at different levels and the shaper acts on level. That is a timbre
// difference rather than a pan shift, and it is what a pair of output stages
// fed at different levels would do anyway.
satDriveOf(grDb) = satDriveCurve(satDepth) * satDriveMax * min(1, (0 - grDb) / satRefDb);

// tanh with an offset, and the offset's own output subtracted back off.
//
// That subtraction is what makes the asymmetry usable: shifting a signal into
// the bend of a curve is how even harmonics are produced, but it also shifts
// the output, and a waveshaper with a DC step on its output is a click every
// time the drive moves. Removing tanh(d*b) analytically pins the curve through
// the origin exactly, so there is no DC to filter off afterwards and no need
// for a blocker in the path.
//
// Dividing by d*(1 - tb^2) restores unity small-signal gain: the curve's slope
// at the origin is d*sech^2(d*b), and sech^2 = 1 - tanh^2. Without it, Bias
// would read as a volume drop as much as a change in flavour.
// Bias also has to give back some drive as it takes on asymmetry. Offsetting
// into the bend of the curve does not merely change which harmonics appear,
// it moves the signal onto a steeper part of the curve and produces more of
// everything: measured, turning Bias up at a fixed Drive multiplied total
// distortion by about fourteen. A control that is supposed to change flavour
// reading as a second, louder drive knob is not what was wanted. Backing the
// drive off in proportion holds the total roughly level, so Bias tips the
// balance from odd to even at a constant intensity.
satBiasComp = 2;

satShape(d, x) = (ma.tanh(dd * (x + b)) - tb) / (dd * (1 - tb * tb))
with {
    b  = satBias * satBiasMax;
    dd = max(1e-6, d / (1 + satBiasComp * satBias));   // 1e-6 only keeps the
    tb = ma.tanh(dd * b);                              // division defined;
};                                                     // d = 0 is handled below

// The select is what makes Drive 0 - and an idle compressor at any Drive - a
// bit-exact bypass rather than merely a quiet one. It matters because the
// band split does not reconstruct exactly in floating point: low + (x - low)
// is within an ulp of x, not equal to it, so leaving the split in circuit at
// zero drive would leave a residue that no setting could null. Nothing clicks
// at the boundary because the shaper tends to the identity as d tends to 0.
satColour(d, x) = select2(d > 0, x, coloured)
with {
    low      = fi.lowpass(satOrder, satXover, x);
    high     = x - low;
    coloured = satShape(d, low) + high;
};

satStage(l, r, gr0, gr1) = satColour(d, l), satColour(d, r)
with {
    d = satDriveOf(min(gr0, gr1));
};

//======================= compressor engine =======================
// 2*Nch in, Nch out: 1-2 audio, 3-4 external sidechain. Both pairs go through
// the same mid/side encode, so with M/S engaged the side band is detected
// against the sidechain's side band rather than against its mid.
//
// The detector reads the signal undelayed while the audio goes through the
// lookahead delay, which is the whole point: by the time a transient reaches
// the multiplier its gain reduction is already in place. The sidechain is not
// delayed either, and needs no delay line of its own - it is only ever looked
// at, never heard.

// The second split keeps the gain reductions alive past the point where they
// are applied, so the output stage can be driven by them: the left branch is
// the audio as before, the right branch drops each channel's audio and keeps
// its gr, giving satStage [L, R, gr0, gr1].
compressorSC = si.bus(2 * Nch)
             :  (msEnc, msEnc)
             <: (grComputeN,
                 (par(i, Nch, de.delay(maxLookaheadSamples, lookaheadSamples)), par(i, Nch, !)))
             :  ro.interleave(Nch, 2)
             <: ((par(i, Nch, applyGain(i)) : msDec), par(i, Nch, (_, !)))
             :  satStage
             :  par(i, Nch, *(makeupGain));

applyGain(i, grDb, x) = x * (grDb : chanMeter(i) : ba.db2linear);

//======================= Dry/wet =======================
// Sits at the very end of the audio path, after makeup, so Makeup trims the
// compressed signal on its way into the blend the way the fader on a parallel
// bus would. Everything upstream — mid/side, Scale, Range — stays on the wet
// side only; the dry is the audio exactly as this DSP received it.
//
// Linear crossfade, not equal-power. Dry and wet here are the *same* signal
// with different gain envelopes, so they sum coherently and a 3 dB law would
// bulge to +3 dB in the middle of the knob. The linear law holds unity for a
// compressor doing nothing and is also what the wrapper's own dry/wet uses.
//
// The dry is delayed to match the wet's lookahead. Without it the blend is a
// comb filter with up to 50 ms of offset — the one thing parallel compression
// must not do, and the reason the wrapper keeps a latency buffer for its
// version of this control.

dryWetMix = (par(i, Nch, de.delay(maxLookaheadSamples, lookaheadDelay)), si.bus(Nch))
          : ro.interleave(Nch, 2)
          : par(i, Nch, blend)
with {
    // si.smoo is a one-pole whose fixed point is 0.001/(1-0.999) evaluated in
    // single precision, and that lands 1.7e-5 short of 1 rather than on it.
    // Taken literally, Dry/Wet at 100% would leave the untouched input mixed
    // in at -95 dB for as long as the plugin runs. Inaudible, but "compressor
    // only" ought to mean it, and it is the kind of residue that shows up as
    // an unexplained null-test failure years later. Scaling the control by a
    // hair and clamping puts the top of the travel exactly on 1; the 0.01%
    // this shifts the middle of the knob by is far below the resolution of
    // the control itself. The bottom needs no such help - the same one-pole
    // decays to a true zero, so 0% is already an exact bypass.
    dw = min(1, drywet * 1.0001);

    blend(d, w) = d * (1 - dw) + w * dw;
};

//======================= process =======================
// Temporary 2-in front end. `_,_ <: si.bus(4)` fans out as [L, R, L, R], so
// the engine's sidechain pair receives a copy of the audio and the plugin
// still reports the 2 inputs src/DistrhoPluginInfo.h insists on. Every
// sidechain path stays live and testable; only the source is stubbed.
//
// To open the real inputs once DPF has a sidechain port group, replace the
// inner `si.bus(Nch) <: compressorSC` with `compressorSC` and widen the outer
// split to hand the dry tap the audio pair only.

process = si.bus(Nch) <: (si.bus(Nch), (si.bus(Nch) <: compressorSC)) : dryWetMix;
