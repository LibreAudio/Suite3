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
sat_group(x)   = knob_group(hgroup("[4]Saturation", x));
out_group(x)   = knob_group(hgroup("[5]Output", x));

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

holdSamples    = hold * ma.SR;

lookaheadDelay = int(lookaheadMs * ma.SR / 1000);

// What the wet path actually costs, and what the host is told. Lookahead is
// the audio delay inside the engine; the oversampler adds its own fixed group
// delay on top whenever it is switched in, and nothing at all when it is not.
// The dry side of the Dry / Wet mix is delayed by the same total, so the blend
// stays phase aligned however the two are set.
totalLatency   = lookaheadDelay + osLatency;

// Widest either half can be, which is what the meter has to be able to show
// and how long the delay lines have to be.
maxLatency     = maxLookaheadSamples + OSTAPS;

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

//---- saturation ----

// The output stage's own controls. Drive sets how much, the rest set what
// kind; the audio path they describe is Colour -> curve -> Colour undone, all
// of it inside the band split. See the Output colour section.

satDepth = sat_group(vslider("[0]Drive[unit:%][symbol:drive]
      [tooltip: How much harmonic colour the output stage adds, scaled by how
       hard the compressor is working. At 0% it is an exact bypass, and it
       stays one at any setting while the compressor is idle - the drive is
       tied to gain reduction, so a passage that is not being compressed is
       not being coloured either. Only the low band is saturated, so the top
       end stays clean - Colour below moves where that boundary effectively
       sits]",
                             0, 0, 100, 1)) / 100 : si.smoo;

// Two entries, so a radio rather than the clipper's menu.
satCurveSel = sat_group(nentry("[1]Curve[symbol:curve]
      [style:radio{'Tanh':0;'Smootherstep':1}]
      [tooltip: Shape of the saturating curve. Tanh is asymptotic - it
       approaches the ceiling and never reaches it, so it stays soft however
       hard it is driven. Smootherstep reaches full saturation at a finite
       level and is flat beyond it, which is a firmer, more clipper-like knee
       and a faster rise in harmonics as the drive comes up]",
                               0, 0, 1, 1)) : int;

satColourDb = sat_group(vslider("[2]Colour[unit:dB][symbol:colour]
      [tooltip: Tilts the spectrum into the saturator and untilts it after, so
       the tone is unchanged and only the distortion moves. Up = the low mids
       reach the curve as well as the bass, and the harmonics come out darker;
       down = the bass alone drives it and the grit lands higher. Pivots at
       630 Hz; the span end to end is twice this. 0 dB is an exact bypass]",
                                0, -12, 12, 0.1));

satAsym = sat_group(vslider("[3]Asymmetry[unit:%][symbol:asymmetry]
      [tooltip: How far off centre the signal sits on the curve. 0% is
       symmetric and gives odd harmonics only, which is the hard, console-ish
       sound; away from it the curve is lopsided and even harmonics come in,
       which read as warmth. The sign picks which half of the waveform gets
       squashed. Defaults to 50%, which is the fixed asymmetry this stage used
       to have and the reason it sounded the way it did]",
                            50, -100, 100, 1)) / 100 : si.smoo;

// checkbox always initialises to 0, so a switch that defaults on is a radio.
satDcOn = sat_group(nentry("[4]DC Filter[symbol:dc_filter]
      [style:radio{'Off':0;'On':1}]
      [tooltip: Removes the offset asymmetric saturation leaves behind. It is
       taken off the harmonics the curve generates rather than off the audio,
       so the signal itself is not high-passed and turning the Drive up cannot
       thin out the bottom end]",
                           1, 0, 1, 1)) : si.smoo;

// named satOsFactor, not os -- `os` is the oscillators library's prefix
satOsFactor = sat_group(nentry("[5]Oversampling[symbol:oversampling]
      [style:radio{'Off':0;'2x':1;'4x':2;'8x':3}]
      [tooltip: Suppresses the aliasing the curve generates. Off adds no
       latency at all; every other setting costs 40 samples, reported to the
       host and compensated]",
                               0, 0, 3, 1)) : int;

//---- output ----

// Ordered to follow the audio path: makeup, then the blend. The colour that
// used to head this list is upstream of both, in Saturation above.

makeupDb = out_group(vslider("[0]Makeup[unit:dB][symbol:makeup]
      [tooltip: Output trim, to put back the level the compressor took away.
       Applied after the gain stage and after the colour, so it lifts the whole
       signal and does not feed back into the detector, change where the
       threshold sits, or change how hard the output stage is driven]",
                             0, -12, 24, 0.1));

drywet = out_group(vslider("[1]Dry / Wet[unit:%][symbol:drywet]
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
// src/templates/dsp.cpp.in), so the host delay-compensates Lookahead and the
// oversampler together. It hangs off the finished output rather than off the
// delay amount, because the number it has to report is no longer the same one
// any single delay line is using.
latency_meter = attach(_, totalLatency :
    meter_group(hbargraph("[2]latency_samples[symbol:latency_samples]", 0, maxLatency)));

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

//======================= Oversampling =======================
//
// Same polyphase oversampler as clipper.dsp, and the coefficient tables at the
// bottom of this file are a copy of the ones at the bottom of that one. The
// two have to stay in step if either is ever regenerated; they are duplicated
// rather than shared because every .dsp here is a self-contained compilation
// unit and this repo has no .lib of its own to put them in.
//
// Faust is single-rate, so the L-times oversampled signal is carried as L
// parallel streams that each tick once per host sample -- the polyphase
// decomposition of the interpolator, written out longhand:
//
//   up:    u_p[k] = sum_i h[iL+p] x[k-i]                          p = 0..L-1
//   down:  y[k]   = sum_i d[iL] v_0[k-i]
//                 + sum_{j=1..L-1} sum_i d[iL+L-j] v_j[k-i-1]     d = h/L
//
// The waveshaper is memoryless, so applying it to each stream independently is
// exactly equivalent to applying it to the interleaved L*fs waveform.
//
// h is a Kaiser lowpass (beta 8.68) cut at the host Nyquist, sized N = 40L+1
// so every factor lands on ONE host-rate group delay of exactly 40 samples.
// That shared delay is what lets 2x, 4x and 8x be switched between without the
// output jumping or the reported latency moving.
//
// What it actually buys, and it is not what it buys in the clipper. Total
// non-harmonic energy relative to the fundamental, single tone at -6 dBFS,
// Drive 100%, about 10 dB of reduction, Asymmetry 50%. The detector is put on
// RMS with its longest window for these, because the peak detector's own
// ripple modulates the gain and puts inharmonic sidebands at -55 to -75 dB
// over everything - that is the compressor working, not the shaper aliasing,
// but it sits far above what is being measured here and would hide all of it:
//
//   tone     Colour      off     2x     4x     8x
//    110 Hz     0      -119.5 -119.8 -119.8 -119.8
//   1099 Hz     0      -120.7 -120.9 -121.0 -121.0
//   2197 Hz     0      -117.7 -117.7 -117.7 -117.8
//   4394 Hz     0      -109.2 -112.3 -112.3 -112.3
//   7324 Hz     0       -86.4 -108.0 -108.0 -108.0
//   2197 Hz   +12       -72.7  -80.3  -80.3  -80.3
//   4394 Hz   +12       -57.7  -96.3  -96.3  -96.3
//   7324 Hz   +12       -54.0 -107.9 -108.0 -108.0
//
// Two things fall out of that. Below about 2 kHz the band split really was
// enough and the oversampler is doing nothing measurable, exactly as the
// section above claimed. Above it, and especially with Colour up - which is
// the setting that sends the top end into the curve on purpose - the split
// alone leaves aliasing at -54 dB, and switching the oversampler on takes 54
// of those dB away.
//
// The other thing is that 4x and 8x are indistinguishable from 2x here, to the
// last tenth of a dB in every row. That is not true in the clipper, where the
// curve sees full-bandwidth material and each doubling is worth 10 to 15 dB;
// it is true here because the split has already thrown away most of what would
// have folded. They are kept anyway, so the two plugins offer the same menu,
// but 2x is the setting to reach for and the higher ones cost real time for
// nothing - see the note on cost below.
//
// Off is the exception, and deliberately so: it is a plain 1x shaper with no
// padding, so switching the oversampler off gives back its 40 samples instead
// of spending them on a delay line that does nothing. The cost is that Off is
// the one transition that is not seamless -- the latency changes, so the host
// re-reports it and the audio steps by 40 samples. Every other plugin control
// here is free to move at any time; this one is a setup decision, which is
// what the clipper's constant-latency arrangement buys instead and why the two
// files differ on it.
//
// Cost note, and it is the expensive part of this file. All four branches run
// all the time (~880 multiply-adds per channel per sample), because their FIRs
// carry state that has to be advanced every sample whether or not the radio is
// pointing at them. That is what buys the click-free switching between 2x, 4x
// and 8x, and it is paid whatever the Oversampling setting says - including
// Off, and including Drive 0, where this stage is not in circuit at all.
// Measured with faust2bench at 44.1 kHz on default parameters, i.e. with the
// shaper bypassed, the same file built three ways:
//
//   no oversampler at all         0.64% CPU
//   Off / 2x                      0.82%
//   Off / 2x / 4x / 8x            3.90%
//
// Given the table above says 4x and 8x measure identically to 2x on this
// stage, dropping them is a 4.8x saving for nothing audible: the change is to
// offer `(satShape(d), sh(2))` with ba.selectn(2, ...) below and cut the radio
// down to two entries. Left as four for parity with the clipper - but this is
// the wrong end of the trade if the compressor is ever the thing running out
// of headroom on a session, and it is worth knowing that the cost is fixed
// rather than paid only by whoever turns the Drive up.
//
// Unlike the clipper, there is no lacing step: the drive is shared between the
// channels but the curve itself is per-channel and memoryless, so left and
// right never need to meet inside the oversampler.

OSTAPS  = 40;   // taps per phase; also the oversampler's host-rate latency
OSDELAY = 20;   // phase 0 is an exact pure delay of OSTAPS/2 samples

// Phase 0 needs no multiplies at all: with the cutoff at 1/(2L) the ideal
// interpolator reproduces the input samples untouched on that phase, so
// h[c + kL] = 0 for every k != 0. Each remaining phase is normalised to unity
// DC gain, so a constant comes out constant across all L streams.
// The coefficient tables are looked up as hp(L, phase) rather than passed in
// as an argument: Faust binds parameters as signals, so handing a
// pattern-matched list function to a function is a pattern-match failure.
up(L)   = _ <: (@(OSDELAY), par(p, L - 1, fi.fir(hp(L, p + 1))));
down(L) = (@(OSDELAY), par(j, L - 1, fi.fir(hp(L, L - 1 - j)) : mem)) :> /(L);

osLatency = int(OSTAPS * (satOsFactor > 0));

// Everything that runs beside the oversampled path has to be moved back by the
// same amount, or the band split would recombine two signals 40 samples apart.
osAlign = de.delay(OSTAPS, osLatency);

// The drive is held constant across the L subsamples of a host sample rather
// than being interpolated. It is derived from the gain reduction, so it moves
// at attack and release rates - milliseconds against the ~20 microseconds a
// subsample step spans at 8x - and the staircase that leaves is far below the
// curve's own harmonics.
osShape(d) = _ <: (satShape(d), sh(2), sh(4), sh(8))
           : ba.selectn(4, satOsFactor)
with {
    sh(L) = up(L) : par(p, L, satShape(d)) : down(L);
};

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
// so it stays usable with the oversampler off. It is also what the hardware
// being imitated actually does: transformers and tubes saturate in the low
// and low-mid range and leave the top comparatively alone.
//
// "Mostly" is doing real work in that sentence, which is what the Oversampling
// radio is for. The split is a first-order lowpass, so it is 6 dB/octave, not
// a wall: content well above the crossover still reaches the curve at a usable
// level, and Colour below deliberately feeds it higher still. Measured, and it
// says plainly where the split is enough and where it is not - see the table
// over the Oversampling section.
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
// Drive 100% and a constant 10 dB of reduction, total distortion runs 25.4% at
// -6 dBFS, 23.5% at -12, 13.5% at -20, 4.6% at -30, 1.5% at -40 and 0.5% at
// -50. The gain reduction sets how far the drive is turned up; the level still
// decides how much of that drive the signal actually meets, exactly as an
// output stage does.
// Referencing the drive to Threshold instead would make it level-independent,
// at the cost of tying the colour to a control that is nominally about when
// the compressor starts working.
satXover    = 800;   // Hz - crossover; only what is below this gets shaped
satOrder    = 1;      // lowpass order for the split
satRefDb    = 12;     // gain reduction at which the drive reaches full

// Shaper drive at Drive 100% and satRefDb of reduction. 21 rather than the 64
// it read while there was a Bias control, because that 64 was divided by three
// on its way in as bias compensation. 64/3 is what the drive actually reached,
// and it is what this now says directly.
satDriveMax = 21;

// How far the operating point sits up the curve, in curve units. This is what
// the Asymmetry control sets, and 0.7 - Asymmetry 50%, the default - is the
// fixed value the stage used to be hard-wired to.
//
// Measured *in curve units* is the whole point. The oldest version of this was
// an offset on the shaper's input, which the drive then multiplied, so the
// operating point crawled further up the curve the harder the stage was
// driven: 0.9 at Drive 25%, 3.7 at 50%, 8.4 at 75%. Past about 9 the curve is
// flat enough that tanh returns exactly 1.0 in single precision, 1 - tanh^2 is
// exactly 0, and the gain restoration below divides by it. That is not a
// rounding problem, it is a 0/0: the plugin emitted NaN over 78 to 90 percent
// of its samples anywhere above Drive 90%, and up to 20 dB of level jump just
// below that. Adding the offset after the drive instead pins it here whatever
// the drive does - no runaway, and the same flavour at every drive setting.
//
// So the range of the knob is bounded by the same division, and now has to
// stay well conditioned for both curves rather than one. At the ceiling below:
// tanh's normalising slope is 1 - tanh(1.4)^2 = 0.216, and smootherstep's is
// 0.150. Smootherstep is the binding one, because unlike tanh it reaches full
// saturation at a finite input - sqrt(pi) = 1.772 - where its slope really is
// zero and the divisor really would vanish. 1.4 leaves 21% of that span in
// hand, which is enough that single precision never gets close.
SATBIASMAX = 1.4;

satBias = SATBIASMAX * satAsym;

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
// Measured with Link 0% and the Scale trims at 100/40, about as lopsided as
// this compressor can be asked to be, turning Drive from 0 to 100% moves the
// left/right balance of the fundamental by 0.23 dB.
//
// The two channels still end up with slightly different harmonic content -
// 18.6% against 20.9% in that same test - because they arrive at the output
// stage at different levels and the shaper acts on level. That is a timbre
// difference rather than a pan shift, and it is what a pair of output stages
// fed at different levels would do anyway.
satDriveOf(grDb) = satDriveCurve(satDepth) * satDriveMax * min(1, (0 - grDb) / satRefDb);

//---- the curves ----
//
// Two odd sigmoids, both normalised the same way LSP's dspu::sigmoid normalises
// its eleven: f(0) = 0, f'(0) = 1, |f| <= 1. Smootherstep is a direct port of
// clipper.dsp's cSmoor, constants and all, so the two plugins offer the same
// curve rather than two things with the same name.
//
// What separates them is the far end. Tanh is asymptotic - it never quite
// reaches 1, so however hard it is driven there is always a little slope left
// and the knee stays soft. Smootherstep is a quintic that goes flat at
// x = sqrt(pi) and stays flat, so past that point it is a hard clipper with a
// rounded approach.
//
// That crossing is what the choice is, and it is visible in the numbers.
// Total distortion of a 220 Hz tone at -6 dBFS with 10 dB of reduction and
// Asymmetry 50%, as Drive comes up:
//
//   Drive        0    10     25     50     75    100
//   Tanh      0.01  0.77   4.79  16.87  25.14  27.26  %
//   Smoorstep 0.01  0.68   4.21  16.31  28.36  30.29  %
//
// - i.e. smootherstep is the *cleaner* of the two up to about half travel,
// because a quintic leaves the origin flatter than a tanh does, and the harder
// of the two past it, once the signal starts spending time on the flat. Tanh
// is already levelling off at the top of the knob; smootherstep is still
// climbing. Harmonic by harmonic at Drive 100%, dB below the fundamental:
//
//               H2     H3     H4     H5     H6     H7
//   Tanh     -13.7  -16.7  -20.4  -34.2  -29.3  -51.4
//   Smoorstep-13.0  -15.8  -18.7  -33.6  -28.8  -57.7
//
// Close relatives rather than two different effects, which is what two members
// of the same normalised family should be.
//
// LSP's port is not quite unity-slope at 0 - smootherstep measures 1.058 - and
// that is kept rather than corrected, so the curve matches theirs and the
// clipper's. It means switching from Tanh to Smootherstep at low drive is
// worth about +0.49 dB, which the gain restoration below does not remove
// because it normalises against the slope at the operating point, not at 0.
INVSQPI = 0.564189583547756;    // 1/sqrt(pi) -- smootherstep input scale

clamp1(x) = max(0 - 1.0, min(1.0, x));

fTanh(x)  = ma.tanh(x);
fSmoor(x) = 2.0 * s * s * s * (10.0 + s * (0 - 15.0 + 6.0 * s)) - 1.0
with { t = clamp1(x * INVSQPI); s = 0.5 * (t + 1.0); };

// Derivatives, in closed form rather than by difference quotient. The shaper
// divides by one of these, so an approximation here is a level error there.
//
// For tanh, sech^2 = 1 - tanh^2. For smootherstep, writing the polynomial in s
// as 20s^3 - 30s^4 + 12s^5 - 1 gives df/ds = 60 s^2 (1-s)^2, and with
// s = (t+1)/2 and t = x/sqrt(pi) that collapses to 1.875/sqrt(pi) * (1-t^2)^2.
// It reads 1.0578 at x = 0, which is exactly the 1.058 slope noted above, so
// the two agree and neither is guessed.
dTanh(x)  = 1.0 - th * th with { th = ma.tanh(x); };
dSmoor(x) = 1.875 * INVSQPI * u * u with { t = clamp1(x * INVSQPI); u = 1.0 - t * t; };

NCURVES = 2;

satCurve(x)  = (fTanh(x), fSmoor(x)) : ba.selectn(NCURVES, satCurveSel);
satCurveD(x) = (dTanh(x), dSmoor(x)) : ba.selectn(NCURVES, satCurveSel);

// The shaper: the signal is driven, offset up the curve by satBias, and the
// offset's own output subtracted back off.
//
// The asymmetry is the flavour. A symmetric curve produces odd harmonics only,
// which is the hard, console-ish sound; sitting off-centre on the bend brings
// in even harmonics, which read as warmth. That is what Asymmetry now sets,
// and it is why the control defaults to 50% rather than to 0 - the symmetric
// end is available, but it is not what this stage is for. Measured on a 110 Hz
// tone at -6 dBFS, Drive 100%, 10 dB of reduction, dB below the fundamental:
//
//   Asym      H2     H3     H4     H5    total
//     0%   -92.0  -13.5  -95.6  -23.4   22.4%
//    25%   -19.7  -14.0  -25.0  -25.1   24.1%
//    50%   -13.6  -15.9  -19.9  -32.5   28.6%
//    75%   -10.1  -20.5  -18.2  -34.9   35.3%
//   100%    -7.7  -42.5  -18.8  -25.4   43.3%
//
// At 0% the even harmonics are gone entirely - 92 dB down is the arithmetic's
// noise floor, not a residue - which is the check that the mechanism is doing
// what it says. Note H3 does not fall off a cliff at 100% so much as pass
// through a null there; the third harmonic of an offset tanh changes sign on
// the way out, and the deep reading is that crossing rather than an absence of
// odd content. Negative settings mirror the curve and measure identically,
// harmonic for harmonic; what changes is which half of the waveform is the one
// getting squashed, which matters on anything with an asymmetric waveform of
// its own, brass and voice especially.
//
// Note this is a different mechanism from the clipper's Asymmetry, which moves
// the positive and negative thresholds apart. Both produce even harmonics; the
// difference is what they do below saturation. Threshold splitting is scale
// invariant - sc*f(x/sc) is x to first AND second order - so its evens vanish
// as x^3 and a signal that never reaches the knee is not coloured at all. An
// offset sits on a curved part of the curve at every level, so its evens
// vanish only as x^2. This stage spends most of its time well below saturation
// (measured: 4.6% total distortion at -30 dBFS against 25% at -6), so the
// mechanism that still colours down there is the one worth having here. The
// clipper, which by definition is at its knee whenever it is doing anything,
// has no such problem to solve.
//
// The subtraction is what makes an offset usable: it shifts the output as well
// as the harmonics, and a waveshaper with a DC step on its output clicks every
// time the drive moves. Subtracting f(satBias) analytically pins the curve
// through the origin, so the static transfer has no offset at any setting.
// That is not the same as the *signal* coming out free of DC - an asymmetric
// curve rectifies, and a symmetric input through it averages to something
// other than zero. See dcStage.
//
// Dividing by dd*f'(satBias) restores unity small-signal gain: the slope at the
// operating point is dd*f'(satBias). Bounding satBias is what keeps that
// divisor away from zero - see the note over SATBIASMAX.
satShape(d, x) = (satCurve(dd * x + satBias) - fb) / (dd * max(1e-6, satCurveD(satBias)))
with {
    dd = max(1e-6, d);   // 1e-6 only keeps the division defined;
    fb = satCurve(satBias);                         // d = 0 is handled below
};

//---- Colour (pre/de-emphasis) ----
//
// A tilt in front of the shaper and its inverse behind it, ported from
// clipper.dsp. The signal comes out spectrally untouched, because the two
// cancel; what changes is which part of the spectrum was loud enough to bend
// the curve, and therefore what got distorted.
//
// Worth being precise about the direction, because the obvious reading is
// backwards. Writing P for the tilt and C for the shaper, the chain computes
// P^-1(C(P.s)) = P^-1(P.s + d) = s + P^-1.d, where d is the distortion. So the
// signal is restored exactly and the DISTORTION is shaped by the inverse.
//
// It does one more thing here than it does in the clipper, because here it
// sits outside the band split rather than in front of a full-range clipper.
// The split is only 6 dB/octave, so lifting the top of the spectrum by up to
// 12 dB on the way in largely cancels what the lowpass takes off an octave or
// two above the crossover: Colour up effectively raises the 800 Hz boundary
// and lets the low mids and above reach the curve, Colour down lowers it until
// the bass has the stage to itself. The clearest evidence is not tonal, it is
// the aliasing table over the Oversampling section - at 7 kHz, Colour 0 leaves
// 86 dB of headroom under the fundamental and Colour +12 leaves 54, which is
// 32 dB more high content arriving at the curve.
//
// What that does to the harmonics of a 220 Hz tone at Drive 100%, dB below the
// fundamental:
//
//   Colour     H2     H3     H4     H5     H6     H7   total
//     -12   -16.2   -4.8  -12.3   -7.8  -11.6  -12.0   92.7%
//      -6   -14.9   -8.4  -14.1  -15.0  -16.3  -23.9   53.6%
//       0   -13.7  -16.7  -20.4  -34.2  -29.3  -51.4   27.3%
//      +6   -14.9  -29.9  -32.0  -55.0  -50.7  -60.5   18.5%
//     +12   -17.4  -42.2  -42.0  -60.3  -69.1  -78.1   13.5%
//
// Read that as the tone, not as the control: 220 Hz is below the 630 Hz pivot,
// so Colour up cuts it on the way in and the whole series thins out, while
// Colour down drives it 12 dB harder and the series fills in and stretches. A
// tone above the pivot moves the other way. The total is roughly conserved for
// tones near the pivot, because the de-emphasis takes back on the way out
// whatever the pre-emphasis added on the way in; what does not come back is
// the *distribution*, which is the whole point.
//
// So the useful way to think about this control on a compressor is not
// "brighter" or "darker" - the signal is unchanged either way - but which part
// of the spectrum is allowed to bend the curve, with the artefacts tilted back
// the other way. Down is the bass-driven, thick setting; up is the one that
// lets a busy mix drive it and keeps the grit out of the top.
//
// The inverse has to be exact or the "spectrally untouched" claim is a lie.
// It is not enough to negate a shelf's gain: fi.lowshelf(1,g,f) followed by
// fi.lowshelf(1,-g,f) leaves a residual only 8.5 dB below full scale at g = 6,
// because that design does not put the +g and -g corners in the same place.
// So the section is written out as an explicit first-order transfer function
// and the inverse is the same one with numerator and denominator swapped,
// which is exact by construction. The zero sits at -(K-r)/(K+r), inside the
// unit circle for every K, r > 0, so the inverse is always stable, and at
// Colour 0 the numerator and denominator are identical term for term, so both
// filters are bit-exact pass-throughs rather than merely close ones.

SATCOLORFC = 630;                                 // pivot, Hz -- tiltEQ's default
satColorK  = tan(ma.PI * SATCOLORFC / ma.SR);
satColorR  = ba.db2linear(satColourDb) : si.smoo; // Nyquist gain; DC gets 1/r

// LF -> 1/r, HF -> r, unity at SATCOLORFC. Same convention as tiltEQ's Tilt,
// so the span end to end is twice the number on the knob.
satColorPre  = fi.tf1((satColorK + satColorR) / d, (satColorK - satColorR) / d,
                      (satColorK * satColorR - 1) / d)
with { d = satColorK * satColorR + 1; };

satColorPost = fi.tf1((satColorK * satColorR + 1) / d, (satColorK * satColorR - 1) / d,
                      (satColorK - satColorR) / d)
with { d = satColorK + satColorR; };

//---- DC ----
//
// An asymmetric curve rectifies, so a symmetric input through it comes out
// with an average that is not zero. The comment over satShape is right that
// subtracting f(satBias) pins the *transfer* through the origin; it is wrong,
// and was wrong before this control existed, to conclude from that that no
// blocker is needed. Measured on a 110 Hz tone at -6 dBFS with Drive 100% and
// 10 dB of reduction:
//
//   Asym        0%     25%     50%     75%    100%
//   filter off  -141   -35.9   -28.3   -22.5   -17.3  dBFS of offset
//   filter on   -133  -131.8  -120.8  -114.0  -108.4
//
// The 50% column is the setting this stage shipped with, so the old fixed bias
// was leaving DC 28 dB below full scale on the output whenever the Drive was
// up. Inaudible on its own and mostly harmless into a converter, but it eats
// headroom off one side of the waveform, it moves with the gain reduction so
// it is not a constant an upstream stage could trim out, and at Asymmetry 100%
// it would reach -17 dBFS. Hence the default of On.
//
// What is filtered is the harmonics the curve generated, not the audio. The
// two differ in the one case that matters: with the blocker across the band
// instead, every setting of Drive above zero would also high-pass the signal
// at 20 Hz, so turning the colour up would quietly thin the bottom end and
// the crossing from Drive 0 to Drive 0+ would step. Taking the residual
// instead leaves the linear path untouched, and because the residual goes to
// zero with the drive, so does everything this filter can do - the boundary
// stays continuous.
satDcStage = _ <: (_, fi.dcblockerat(20)) : si.interpolate(satDcOn);

// The select is what makes Drive 0 - and an idle compressor at any Drive - a
// bit-exact bypass rather than merely a quiet one. It matters because neither
// the band split nor the Colour pair reconstructs exactly in floating point:
// low + (x - low) is within an ulp of x, not equal to it, so leaving them in
// circuit at zero drive would leave a residue that no setting could null.
// Nothing clicks at the boundary because the shaper tends to the identity as d
// tends to 0, and the DC blocker sees nothing but that vanishing residual.
//
// Everything that bypasses the oversampler - the high band, and the low band
// where it is added back - goes through osAlign, so the sum still lines up
// when the oversampler is contributing its 40 samples of group delay. At
// Oversampling Off that delay is zero and osAlign is a pass-through.
satColour(d, x) = select2(d > 0, x : osAlign, coloured)
with {
    pre      = x : satColorPre;
    low      = fi.lowpass(satOrder, satXover, pre);
    lowD     = low : osAlign;
    high     = pre - low : osAlign;
    resid    = osShape(d, low) - lowD;
    coloured = lowD + (resid : satDcStage) + high : satColorPost;
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
                 (par(i, Nch, de.delay(maxLookaheadSamples, lookaheadDelay)), par(i, Nch, !)))
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
// The dry is delayed to match the wet's lookahead *and* whatever the
// oversampler is costing. Without it the blend is a comb filter with up to
// 50 ms of offset — the one thing parallel compression must not do, and the
// reason the wrapper keeps a latency buffer for its version of this control.

dryWetMix = (par(i, Nch, de.delay(maxLatency, totalLatency)), si.bus(Nch))
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

process = si.bus(Nch) <: (si.bus(Nch), (si.bus(Nch) <: compressorSC))
        : dryWetMix
        : par(i, Nch, latency_meter);

//======================= polyphase coefficients =======================
// Generated: Kaiser lowpass, beta 8.68, cutoff at the host Nyquist,
// N = 40L+1 taps split into L phases each normalised to unity DC gain.
// Phase 0 is the pure delay handled by @(OSDELAY) above and is not listed.
// 2x: 81 taps -> 2 phases of [41, 40] (phase 0 is the pure delay above)
hp(2, 1) = (
      -4.37797177881e-05,  1.32549617198e-04, -3.02781836516e-04,  5.96906681537e-04,
      -1.06950572975e-03,  1.78856600971e-03, -2.83678365476e-03,  4.31330283769e-03,
      -6.33662513756e-03,  9.05001914332e-03, -1.26318474443e-02,  1.73153852784e-02,
      -2.34273674458e-02,  3.14655455896e-02, -4.22646132617e-02,  5.73870875127e-02,
      -8.01873632972e-02,  1.19430867794e-01, -2.07386721498e-01,  6.35007158559e-01,
       6.35007158559e-01, -2.07386721498e-01,  1.19430867794e-01, -8.01873632972e-02,
       5.73870875127e-02, -4.22646132617e-02,  3.14655455896e-02, -2.34273674458e-02,
       1.73153852784e-02, -1.26318474443e-02,  9.05001914332e-03, -6.33662513756e-03,
       4.31330283769e-03, -2.83678365476e-03,  1.78856600971e-03, -1.06950572975e-03,
       5.96906681537e-04, -3.02781836516e-04,  1.32549617198e-04, -4.37797177881e-05);

// 4x: 161 taps -> 4 phases of [41, 40, 40, 40] (phase 0 is the pure delay above)
hp(4, 1) = (
      -2.14894508149e-05,  7.36303681592e-05, -1.77104100382e-04,  3.59912708193e-04,
      -6.58417687801e-04,  1.11824137361e-03, -1.79516162624e-03,  2.75622755283e-03,
      -4.08154220788e-03,  5.86752411159e-03, -8.23311572781e-03,  1.13316821683e-02,
      -1.53740399632e-02,  2.06742936260e-02, -2.77461215241e-02,  3.75233567197e-02,
      -5.19358470099e-02,  7.57431173569e-02, -1.24653814479e-01,  2.98390647561e-01,
       8.99752645352e-01, -1.77214487865e-01,  9.49850571143e-02, -6.21375712475e-02,
       4.39582300018e-02, -3.22105465844e-02,  2.39442875389e-02, -1.78411885619e-02,
       1.32184544300e-02, -9.67933121573e-03,  6.96928675184e-03, -4.91014613971e-03,
       3.36776353522e-03, -2.23550422633e-03,  1.42565417993e-03, -8.64927793521e-04,
       4.92078946753e-04, -2.56525808975e-04,  1.17385276571e-04, -4.25934528967e-05);
hp(4, 2) = (
      -4.37797177881e-05,  1.32549617198e-04, -3.02781836516e-04,  5.96906681537e-04,
      -1.06950572975e-03,  1.78856600971e-03, -2.83678365476e-03,  4.31330283769e-03,
      -6.33662513756e-03,  9.05001914332e-03, -1.26318474443e-02,  1.73153852784e-02,
      -2.34273674458e-02,  3.14655455896e-02, -4.22646132617e-02,  5.73870875127e-02,
      -8.01873632972e-02,  1.19430867794e-01, -2.07386721498e-01,  6.35007158559e-01,
       6.35007158559e-01, -2.07386721498e-01,  1.19430867794e-01, -8.01873632972e-02,
       5.73870875127e-02, -4.22646132617e-02,  3.14655455896e-02, -2.34273674458e-02,
       1.73153852784e-02, -1.26318474443e-02,  9.05001914332e-03, -6.33662513756e-03,
       4.31330283769e-03, -2.83678365476e-03,  1.78856600971e-03, -1.06950572975e-03,
       5.96906681537e-04, -3.02781836516e-04,  1.32549617198e-04, -4.37797177881e-05);
hp(4, 3) = (
      -4.25934528967e-05,  1.17385276571e-04, -2.56525808975e-04,  4.92078946753e-04,
      -8.64927793521e-04,  1.42565417993e-03, -2.23550422633e-03,  3.36776353522e-03,
      -4.91014613971e-03,  6.96928675184e-03, -9.67933121573e-03,  1.32184544300e-02,
      -1.78411885619e-02,  2.39442875389e-02, -3.22105465844e-02,  4.39582300018e-02,
      -6.21375712475e-02,  9.49850571143e-02, -1.77214487865e-01,  8.99752645352e-01,
       2.98390647561e-01, -1.24653814479e-01,  7.57431173569e-02, -5.19358470099e-02,
       3.75233567197e-02, -2.77461215241e-02,  2.06742936260e-02, -1.53740399632e-02,
       1.13316821683e-02, -8.23311572781e-03,  5.86752411159e-03, -4.08154220788e-03,
       2.75622755283e-03, -1.79516162624e-03,  1.11824137361e-03, -6.58417687801e-04,
       3.59912708193e-04, -1.77104100382e-04,  7.36303681592e-05, -2.14894508149e-05);

// 8x: 321 taps -> 8 phases of [41, 40, 40, 40, 40, 40, 40, 40] (phase 0 is the pure delay above)
hp(8, 1) = (
      -9.46018969446e-06,  3.50667645661e-05, -8.68518308623e-05,  1.79441191382e-04,
      -3.31920416670e-04,  5.68327793787e-04, -9.18134081817e-04,  1.41682117445e-03,
      -2.10678287128e-03,  3.03895597505e-03, -4.27591871362e-03,  5.89782570319e-03,
      -8.01387129876e-03,  1.07849973115e-02, -1.44711959951e-02,  1.95384830781e-02,
      -2.69328147536e-02,  3.89264988873e-02, -6.26727946549e-02,  1.38130670659e-01,
       9.74346591165e-01, -1.06887558318e-01,  5.47354558721e-02, -3.52626087754e-02,
       2.47796605618e-02, -1.81031168114e-02,  1.34435206354e-02, -1.00189613626e-02,
       7.43093536138e-03, -5.45094264796e-03,  3.93410179344e-03, -2.78002422638e-03,
       1.91374287709e-03, -1.27600323913e-03,  8.18220418792e-04, -4.99843619673e-04,
       2.86960393526e-04, -1.51505715063e-04,  7.07236996204e-05, -2.66917952592e-05);
hp(8, 2) = (
      -2.14894508149e-05,  7.36303681592e-05, -1.77104100382e-04,  3.59912708193e-04,
      -6.58417687801e-04,  1.11824137361e-03, -1.79516162624e-03,  2.75622755283e-03,
      -4.08154220788e-03,  5.86752411159e-03, -8.23311572781e-03,  1.13316821683e-02,
      -1.53740399632e-02,  2.06742936260e-02, -2.77461215241e-02,  3.75233567197e-02,
      -5.19358470099e-02,  7.57431173569e-02, -1.24653814479e-01,  2.98390647561e-01,
       8.99752645352e-01, -1.77214487865e-01,  9.49850571143e-02, -6.21375712475e-02,
       4.39582300018e-02, -3.22105465844e-02,  2.39442875389e-02, -1.78411885619e-02,
       1.32184544300e-02, -9.67933121573e-03,  6.96928675184e-03, -4.91014613971e-03,
       3.36776353522e-03, -2.23550422633e-03,  1.42565417993e-03, -8.64927793521e-04,
       4.92078946753e-04, -2.56525808975e-04,  1.17385276571e-04, -4.25934528967e-05);
hp(8, 3) = (
      -3.39317592273e-05,  1.08782275504e-04, -2.54721756160e-04,  5.09633651278e-04,
      -9.22476661180e-04,  1.55445192627e-03, -2.48018724302e-03,  3.78926443624e-03,
      -5.58871924642e-03,  8.00765529090e-03, -1.12060412008e-02,  1.53915809851e-02,
      -2.08524405949e-02,  2.80227261651e-02, -3.76212565021e-02,  5.09738332570e-02,
      -7.08718931553e-02,  1.04395343349e-01, -1.76156100794e-01,  4.68662408851e-01,
       7.83099856745e-01, -2.09788162540e-01,  1.16876574472e-01, -7.75135066887e-02,
       5.51692746017e-02, -4.05340673391e-02,  3.01570454258e-02, -2.24630877120e-02,
       1.66234805642e-02, -1.21503471941e-02,  8.72705867906e-03, -6.12974822752e-03,
       4.18853766467e-03, -2.76766100721e-03,  1.75511644625e-03, -1.05725093279e-03,
       5.95865602680e-04, -3.06519678793e-04,  1.37300431835e-04, -4.76705866007e-05);
hp(8, 4) = (
      -4.37797177881e-05,  1.32549617198e-04, -3.02781836516e-04,  5.96906681537e-04,
      -1.06950572975e-03,  1.78856600971e-03, -2.83678365476e-03,  4.31330283769e-03,
      -6.33662513756e-03,  9.05001914332e-03, -1.26318474443e-02,  1.73153852784e-02,
      -2.34273674458e-02,  3.14655455896e-02, -4.22646132617e-02,  5.73870875127e-02,
      -8.01873632972e-02,  1.19430867794e-01, -2.07386721498e-01,  6.35007158559e-01,
       6.35007158559e-01, -2.07386721498e-01,  1.19430867794e-01, -8.01873632972e-02,
       5.73870875127e-02, -4.22646132617e-02,  3.14655455896e-02, -2.34273674458e-02,
       1.73153852784e-02, -1.26318474443e-02,  9.05001914332e-03, -6.33662513756e-03,
       4.31330283769e-03, -2.83678365476e-03,  1.78856600971e-03, -1.06950572975e-03,
       5.96906681537e-04, -3.02781836516e-04,  1.32549617198e-04, -4.37797177881e-05);
hp(8, 5) = (
      -4.76705866007e-05,  1.37300431835e-04, -3.06519678793e-04,  5.95865602680e-04,
      -1.05725093279e-03,  1.75511644625e-03, -2.76766100721e-03,  4.18853766467e-03,
      -6.12974822752e-03,  8.72705867906e-03, -1.21503471941e-02,  1.66234805642e-02,
      -2.24630877120e-02,  3.01570454258e-02, -4.05340673391e-02,  5.51692746017e-02,
      -7.75135066887e-02,  1.16876574472e-01, -2.09788162540e-01,  7.83099856745e-01,
       4.68662408851e-01, -1.76156100794e-01,  1.04395343349e-01, -7.08718931553e-02,
       5.09738332570e-02, -3.76212565021e-02,  2.80227261651e-02, -2.08524405949e-02,
       1.53915809851e-02, -1.12060412008e-02,  8.00765529090e-03, -5.58871924642e-03,
       3.78926443624e-03, -2.48018724302e-03,  1.55445192627e-03, -9.22476661180e-04,
       5.09633651278e-04, -2.54721756160e-04,  1.08782275504e-04, -3.39317592273e-05);
hp(8, 6) = (
      -4.25934528967e-05,  1.17385276571e-04, -2.56525808975e-04,  4.92078946753e-04,
      -8.64927793521e-04,  1.42565417993e-03, -2.23550422633e-03,  3.36776353522e-03,
      -4.91014613971e-03,  6.96928675184e-03, -9.67933121573e-03,  1.32184544300e-02,
      -1.78411885619e-02,  2.39442875389e-02, -3.22105465844e-02,  4.39582300018e-02,
      -6.21375712475e-02,  9.49850571143e-02, -1.77214487865e-01,  8.99752645352e-01,
       2.98390647561e-01, -1.24653814479e-01,  7.57431173569e-02, -5.19358470099e-02,
       3.75233567197e-02, -2.77461215241e-02,  2.06742936260e-02, -1.53740399632e-02,
       1.13316821683e-02, -8.23311572781e-03,  5.86752411159e-03, -4.08154220788e-03,
       2.75622755283e-03, -1.79516162624e-03,  1.11824137361e-03, -6.58417687801e-04,
       3.59912708193e-04, -1.77104100382e-04,  7.36303681592e-05, -2.14894508149e-05);
hp(8, 7) = (
      -2.66917952592e-05,  7.07236996204e-05, -1.51505715063e-04,  2.86960393526e-04,
      -4.99843619673e-04,  8.18220418792e-04, -1.27600323913e-03,  1.91374287709e-03,
      -2.78002422638e-03,  3.93410179344e-03, -5.45094264796e-03,  7.43093536138e-03,
      -1.00189613626e-02,  1.34435206354e-02, -1.81031168114e-02,  2.47796605618e-02,
      -3.52626087754e-02,  5.47354558721e-02, -1.06887558318e-01,  9.74346591165e-01,
       1.38130670659e-01, -6.26727946549e-02,  3.89264988873e-02, -2.69328147536e-02,
       1.95384830781e-02, -1.44711959951e-02,  1.07849973115e-02, -8.01387129876e-03,
       5.89782570319e-03, -4.27591871362e-03,  3.03895597505e-03, -2.10678287128e-03,
       1.41682117445e-03, -9.18134081817e-04,  5.68327793787e-04, -3.31920416670e-04,
       1.79441191382e-04, -8.68518308623e-05,  3.50667645661e-05, -9.46018969446e-06);

