// -*-Faust-*-

declare author "Klaus Scheuermann";
declare description "";
declare license "GPL-3.0-or-later";
declare name "Compresaturator";
declare unique_id "LAcp";

// Dry / Wet is built here rather than taken from the wrapper: leaving the flag
// on would stack the wrapper's common control on top of this one and give the
// plugin two knobs that do the same thing. Unlike clipper.dsp, which has to
// delay its dry tap to meet an oversampler, this plugin is zero-latency, so the
// blend below is a plain crossfade against the untouched input.
// declare drywet "true";

// Port of airwindows' Compresaturator (Chris Johnson, MIT licence,
// plugins/WinVST/Compresaturator). Translated from the double-precision
// processDoubleReplacing path, which is the one modern hosts run and the
// only one of the two that is free of the float path's copy-paste slips
// (there, targetWidth and overspill are shared between the channels and the
// buffer is read one sample past where it was written).
//
// The idea: saturate, then *pay for* the saturation with gain reduction.
//
// Every sample is pushed through a sin() waveshaper, and the difference
// between what went in and what came out -- the "overspill", the part of the
// waveform the shaper refused to pass -- is pushed into a delay line. The
// running sum of the last `lastWidth` overspills is `padFactor`, and that sum
// is what turns down the input gain on the next sample. So the compressor has
// no threshold, no ratio and no detector: the amount it ducks is exactly the
// amount of distortion it just produced. Clean material sums to nothing and
// passes through untouched; only material that is actually clipping the shaper
// generates any reduction at all.
//
// What makes it sound the way it does is that the window length is not fixed.
// Each sample the window is compared against a *randomly scaled* target width
// and grows or shrinks by one sample. Growing is done by simply not dropping
// the trailing sample, so the sum is never rewritten -- the release is smooth
// because the buffer is being subdivided more finely rather than recomputed.
// The randomness smears what would otherwise be a periodic window-length
// artefact into noise. And when the shaper is driven past pi/2, into outright
// distortion rather than saturation, the target width collapses from Expand to
// 8 samples, so the window sprints shorter and the reduction arrives fast.
// That is the whole attack mechanism: hard transients shorten the window,
// everything else lets it drift wide again.
//
// One deliberate deviation from the original: Expand is set in milliseconds,
// not samples. Airwindows sizes the window in samples, so the same setting
// covers half the time at 96k as it does at 48k and the plugin quietly gets
// faster as the session rate goes up. Converting at the control keeps the
// window the same *duration* everywhere, so a patch means the same thing at
// any rate.
//
// That conversion is not quite the whole job. satComp carries a `/3000` term
// which is calibrated in samples, and it ends up squared in the reduction --
// once scaling the overspill on the way into the buffer, once scaling the
// running mean on the way out. Feeding it the real sample count would make the
// amount of gain reduction climb with the session rate: measured at Expand
// 10 ms, Clamp 100%, Drive +12, it runs 8.1 dB at 44.1k against 11.1 dB at
// 192k. So satComp is fed the window length in samples *at a reference rate*
// instead, leaving Clamp meaning the same thing everywhere. Only the window
// itself follows the real rate. The same measurement then reads 8.2 dB against
// 7.6 dB.
//
// The ~0.6 dB left over is three constants that are still counted in samples
// and not converted: the 50-sample floor under widestRange, panicWidth, and
// minWidth. They are all the original's. They bite hardest at the bottom of the
// Expand range -- at 1 ms the floor alone is the difference between 44 and 50
// samples at 44.1k -- and converting them too would be a deeper change than
// this one. At the 3 ms default the reduction holds to 0.03 dB over
// 44.1k..192k, so this only shows up at the extremes.

import("stdfaust.lib");

Nch = 2;

// Expand is in milliseconds but the window is counted in samples, so the delay
// lines have to be sized for the worst case: the top of the Expand range at the
// highest sample rate we expect to see. Running above maxSR is not an error --
// the window simply stops widening past maxWidth, so the longest Expand
// settings quietly cover less time than the dial says.
maxSR = 192000;
maxMs = 10;
maxWidth = int(maxMs * maxSR / 1000);

// The rate airwindows calibrated the `/3000` term at. Only satComp is measured
// against this; the window itself is always in real samples.
refSR = 48000;

// Above this the shaper is no longer saturating but folding the waveform over,
// so the window starts chasing `panicWidth` instead of the Expand setting.
satLimit = 1.57079633;  // pi/2, spelled as the original spells it
panicWidth = 8;

// Floor on the window. The random target can ask for zero, and a window of
// zero would divide padFactor by nothing in variSpeed.
minWidth = 2;

process = si.bus(Nch) <: (si.bus(Nch), wetChain) : dryWetMix;

wetChain = msEnc : satStereo : msDec : par(i, Nch, *(makeupGain));

// Mid / Side, as a smoothed crossfade between the two matrices rather than a
// switch, so toggling it does not click. Lifted from clipper.dsp.
//
// At msAmt 0 both are the identity and the pair passing through the saturator
// is L/R untouched. At 1 the encode is M = (L+R)/2, S = (L-R)/2 and the decode
// is its exact inverse, L = M+S, R = M-S. Mid-transition the round trip is not
// quite unity, but it is over in a few milliseconds.
//
// Makeup sits after the decode. It commutes with it either way -- the same
// scalar on both channels -- but it reads as an output trim in L/R there.
msAmt = msOn : si.smoo;

msEnc(l, r) = l + (0.5 * (l + r) - l) * msAmt,
              r + (0.5 * (l - r) - r) * msAmt;

msDec(m, s) = m + ((m + s) - m) * msAmt,
              s + ((m - s) - s) * msAmt;

// The dry tap is the plugin input and the whole wet chain -- Makeup and the
// Drive compensation included -- sits on the other side, mirroring what the
// wrapper's version would have blended.
dryWetMix = ro.interleave(Nch, 2) : par(i, Nch, blend)
with {
    // Straight from clipper.dsp: si.smoo is a one-pole whose fixed point,
    // evaluated in single precision, lands a hair short of 1 rather than on it.
    // Taken literally, Dry / Wet at 100% would leave the untouched input mixed
    // in around -95 dB for as long as the plugin runs. Scaling by a hair and
    // clamping puts the top of the travel exactly on 1; the bottom needs no
    // help, since the same one-pole decays to a true zero.
    dw = min(1, drywet * 1.0001);

    blend(d, w) = d * (1 - dw) + w * dw;
};

//---------------------------------- GUI --------------------------------------

comp_group(x) = vgroup("Compresaturator", x);
knob_group(x) = comp_group(hgroup("[0]Controls", x));
meter_group(x) = comp_group(vgroup("[1]Meters", x));

driveDb = knob_group(vslider("[0]Drive[unit:dB][symbol:drive]
      [tooltip: Input gain into the saturator. More Drive means more overspill, which means more compression -- the two are the same control here.]",
      0, -12, 12, 0.1));

drive = driveDb : ba.db2linear : si.smoo;

// The original's Clamp is B*2, then boosted by the window width: a wide window
// spreads the same overspill over more samples, so without this a long Expand
// would quietly mean less compression.
clamp = knob_group(vslider("[1]Clamp[unit:%][symbol:clamp]
      [tooltip: How hard the accumulated overspill pushes back on the input gain. 0% saturates without compressing at all.]",
      50, 0, 100, 0.1)) * 0.02;

// Smoothed here rather than on Clamp alone, so that dragging Expand -- which
// scales this too -- does not step the gain reduction either.
satComp = clamp * (1.0 + widestRangeRef / 3000.0) : si.smoo;

// Log-scaled because the bottom of this range is where the character lives:
// the step from 1 to 2 ms changes the sound far more than 8 to 10 does.
//
// The 50-sample floor is the original's, and it is what the bottom of this
// range is scaled against: 1 ms is 48 samples at 44.1/48k, so the dial bottoms
// out at very slightly over 1 ms there and reaches the full 1 ms from 50k up.
expandMs = knob_group(vslider("[2]Expand[unit:ms][scale:log][symbol:expand]
      [tooltip: Widest the overspill window is allowed to grow. Short is grabby and aggressive, long is a slow squash that mostly gets out of the way.]",
      3, 1, maxMs, 0.1));

// The window the buffer actually chases, in real samples...
widestRange = expandMs * ma.SR / 1000.0 : max(50) : min(maxWidth) : int;

// ...and the same window measured at refSR, which is what satComp is calibrated
// against. See the note at the top on why these two are not the same number.
widestRangeRef = expandMs * refSR / 1000.0 : max(50);

// Note Link ties together whatever pair reaches the saturator, so with Mid /
// Side engaged it ties mid to side rather than left to right. That is rarely
// what you want: the side channel is normally much the quieter of the two and
// saturates far less, so forcing the mid's reduction onto it just ducks the
// sides and narrows the image. Back Link off when working in M/S.
//
// Stereo link. 0% is the original -- airwindows keeps entirely separate L/R
// buffers and lets the two channels duck by different amounts. 100% is the
// convention the rest of this suite defaults to (see clipper.dsp and
// upwardCompressor.dsp): both channels take the larger of the two reductions,
// so a hit on one side cannot drag the image across. See satStereo for why the
// blend has to happen inside the loop rather than on the way out.
link = knob_group(vslider("[3]Link[unit:%][symbol:link]
      [tooltip: 0% lets each channel compress on its own, as the original does. 100% ducks both by the same amount, holding the stereo image still.]",
      100, 0, 100, 1)) / 100 : si.smoo;

msOn = knob_group(checkbox("[4]Mid / Side[symbol:mid_side]
      [tooltip: Saturate and compress mid and side instead of left and right. The two meters then read mid and side. Link ties whichever pair is being processed, so back it off in this mode.]"));

// A +/-12 dB trim, where the original had a 0..100% attenuator that could only
// cut (and could mute outright). Symmetrical around unity is the more useful
// shape given that it also has to be able to cancel the Drive compensation;
// muting is Dry / Wet's job or the host's.
makeupDb = knob_group(vslider("[5]Makeup[unit:dB][symbol:makeup]
      [tooltip: Output trim, to put back the level the saturator and the compressor took away. Applied to the wet path only, before the dry/wet mix.]",
      0, -12, 12, 0.1));

// Drive compensation, always on: the wet path is backed off by exactly the
// Drive, so Drive stops being a level control and becomes purely "how hard is
// the shaper hit". Whatever level change is left over is the saturation and the
// compression doing their job, which is the thing you actually want to hear
// when you reach for Drive.
//
// There is no switch for this. If you want the original's uncompensated
// behaviour, the two controls are arithmetically the same knob -- set Makeup
// equal to Drive and the exponent below is zero, i.e. unity. That is also why
// Makeup spans the same +/-12 as Drive rather than some other range.
//
// Where the compensation is exact and where it is not, measured on
// tone-plus-noise at 48k against the level at Drive 0:
//
//   * Anything not already saturating: exact. At -31 dBFS in it holds to 0.5 dB
//     across the whole -12..+12 range, at any Clamp, because the drive passes
//     1:1 and comes straight back out.
//   * Cutting: within 0.1 dB, except on material loud enough to have been
//     saturating at Drive 0 already, where it comes back up to 1.5 dB *louder*.
//     Backing the drive off unsaturates the signal, so it returns slightly more
//     than it took. Erring loud on a cut is the harmless direction.
//   * Boosting into saturation: over-compensates, and this is the real limit.
//     At -5 dBFS in, Clamp 50%, Drive +12 the plugin only gets 4.7 dB louder on
//     its own, so backing off the full 12 leaves it 7.3 dB down. That is the
//     worst case measured. With the compensation permanently in circuit this is
//     the one case that needs a hand on Makeup.
//
// That last case is the honest limit of a Drive-only correction: past the knee
// the gain that fails to come through is eaten partly by the compressor and
// partly by the sin() shaper, and neither is a function of Drive. Undoing the
// compressor's share would need makeup driven off variSpeed, which is a
// different control -- it would flatten the compression as well.
//
// Folded into the makeup gain rather than given its own multiplier, and applied
// to the wet path only, so a partial Dry / Wet does not attenuate the dry side.
makeupGain = ba.db2linear(makeupDb - driveDb) : si.smoo;

// 0% is an exact bypass, 100% is the saturator alone. See dryWetMix for why the
// top of the travel needs a nudge to be exact and the bottom does not.
drywet = knob_group(vslider("[6]Dry / Wet[unit:%][symbol:drywet]
      [tooltip: Blend of the saturated signal against the untouched input, for parallel compression. 100% = saturator only, 0% = bypassed.]",
      100, 0, 100, 1)) / 100 : si.smoo;

// The plugin takes level off the signal in two separate places, and they are
// worth seeing apart rather than as one number:
//
//   Reduction  -- what the compressor did, i.e. variSpeed. Slow, program
//                 dependent, driven by the accumulated overspill.
//   Saturation -- what the sin() shaper did to the sample in front of it,
//                 measured across the shaper alone (shaped against rect), so
//                 it is independent of whatever the compressor had already
//                 taken off. Fast, and it is the part the Drive compensation
//                 cannot undo.
//
// Read them as "which stage is eating the boost", not as a budget that adds up
// to the level change. Both are peak-held instantaneous figures while the level
// change is an average, so on peaky material Saturation reads well above the
// drop it actually causes: 11.8 dB on the bar against a 7.2 dB RMS drop, at
// -5 dBFS in, Clamp 0%, Drive +12. What they do report reliably is the split --
// at Clamp 0% Reduction sits at exactly zero and Saturation carries all of it;
// on quieter material at Clamp 100% it is the other way round (6.2 dB against
// 0.6 dB). That is the same split the Drive compensation note above describes,
// and it is what tells you whether that compensation is about to over-correct.
//
// Same top on both scales so the bars are directly comparable by eye.
maxRed = 24;

// Pins the bar instead of letting it run off the end.
satFloor = ba.db2linear(0 - maxRed);

// Peak-hold with exponential decay. The UI reads the parameter once per block,
// so an instantaneous value would show whichever sample the block happened to
// end on -- fine for the slow compressor figure, useless for the shaper, which
// swings from nothing at the zero crossings to its maximum at every peak.
meterHold = max ~ *(ba.tau2pole(0.3));

redMeter1 = meter_group(hbargraph("[0]Reduction 1[unit:dB][symbol:reduction_1]", 0, maxRed));
redMeter2 = meter_group(hbargraph("[1]Reduction 2[unit:dB][symbol:reduction_2]", 0, maxRed));

satMeter1 = meter_group(hbargraph("[2]Saturation 1[unit:dB][symbol:saturation_1]", 0, maxRed));
satMeter2 = meter_group(hbargraph("[3]Saturation 2[unit:dB][symbol:saturation_2]", 0, maxRed));

//---------------------------------- DSP --------------------------------------

// Both channels live in one recursion, carrying six fed-back signals
// (padFactor, lastWidth and the last overspill, twice) rather than two lots of
// three. That is what stereo linking costs here.
//
// The link cannot be done on the way out. variSpeed sets the gain going *into*
// the shaper, so it decides how much overspill the next sample generates and
// therefore what the detector integrates next. Applying a linked gain while
// each channel's detector went on integrating its own unlinked one would leave
// the two permanently disagreeing. So the blend happens before either channel
// is touched, and each detector then evolves from the gain that was actually
// applied to it.
//
// Doing it there is also what makes the link symmetrical: variSpeed depends
// only on the *previous* state, so both channels' figures are available before
// either is processed and neither has to see a one-sample-stale version of the
// other.
//
// Everything else stays per-channel and unlinked, exactly as the original has
// it: separate overspill, separate delay lines, and separate decorrelated noise
// driving the window walk. Even at Link 100% the two windows drift apart; what
// is shared is only how far the gain ducks.
//
// Assumes exactly 2 channels.
satStereo = (step ~ si.bus(6)) : (!, !, !, !, !, !, _, _)
with {
    step(pf0, lw0, sp0, pf1, lw1, sp1, x0, x1) =
        (chan(no.noises(2, 0), redMeter1, satMeter1, vsL(v0), pf0, lw0, sp0, x0),
         chan(no.noises(2, 1), redMeter2, satMeter2, vsL(v1), pf1, lw1, sp1, x1))
        // each chan gives (padFactor, lastWidth, s, out); regroup so the six
        // state signals lead, in the order the feedback bus expects, and the
        // two audio outputs trail
        : route(8, 8, 1,1, 2,2, 3,3, 5,4, 6,5, 7,6, 4,7, 8,8)
    with {
        // The reduction each channel would apply on its own. Never below 1:
        // this only ever turns down.
        vs(pf, lw) = max(1.0, 1.0 + (pf / max(minWidth, lw)) * satComp);

        v0 = vs(pf0, lw0);
        v1 = vs(pf1, lw1);

        // Blend each channel's own figure towards the larger of the two, which
        // is the same shape upwardCompressor.dsp and clipper.dsp use. Linking
        // can therefore only ever duck a channel further, never less.
        vsL(v) = v + link * (max(v0, v1) - v);
    };
};

// One channel, given the reduction it has been told to apply. `rnd` is this
// channel's decorrelated noise source, and redMeter / satMeter its two bargraphs.
//
// The three fed-back signals are padFactor, lastWidth and the overspill that
// was just written to the delay line. Overspill has to travel round the loop
// because it depends on padFactor, which depends on overspill: the delay line
// is therefore read as `sPrev` delayed a further lastWidth-1 samples, the
// recursion itself supplying the missing one.
chan(rnd, redMeter, satMeter, variSpeed, pf, lw, sPrev, x) =
    padFactor, lastWidth, s, out
with {
    // --- drive -------------------------------------------------------------
    // Faust has no way to give a feedback signal a start value, so lw arrives
    // as 0 on the very first sample; without this clamp the division in vs
    // above would be 0/0. Everywhere else it is a no-op, since lastWidth is
    // itself clamped to minWidth on the way out.
    lwc = max(minWidth, lw);

    totalgain = drive / variSpeed;
    driven = x * totalgain;

    // `temp` is what the overspill is measured against. Cuts are applied to
    // it, boosts are not -- the original's "no boosting beyond unity
    // please" -- so pushing Drive up past 0 dB does not by itself invent
    // overspill out of a signal that was not saturating before.
    temp = select2(totalgain < 1.0, x, driven);

    // --- shaper ------------------------------------------------------------
    rect = abs(driven);
    shaped = sin(min(rect, satLimit));

    // sign(driven) * shaped, with driven == 0 landing on 0 either way.
    // The reduction metered is the linked one, i.e. what was actually applied.
    out = select2(driven < 0.0, shaped, -shaped)
        : attach(_, ba.linear2db(variSpeed) : min(maxRed) : meterHold : redMeter)
        : attach(_, satGr : meterHold : satMeter);

    // How many dB the shaper is taking off this sample. Both sides are
    // floored before dividing so that a sample sitting at zero reads as no
    // saturation rather than 0/0: below the floor the ratio is 1 either way.
    // sin(y) <= y for y >= 0, so this can only ever be positive.
    satGr = 0 - ba.linear2db(max(satFloor, max(ma.EPSILON, shaped)
                                          / max(ma.EPSILON, rect)));

    // What the shaper would not pass. Goes negative when Drive is boosting
    // (temp is then the un-boosted input, smaller than the shaped output),
    // which is intended: padFactor is clamped at zero further down.
    s = (abs(temp) - shaped) * satComp;

    // --- window ------------------------------------------------------------
    // Past pi/2 we are distorting, not saturating: collapse the target so
    // the window shrinks fast and the gain reduction catches up.
    targetWidth = select2(rect > satLimit, widestRange, panicWidth);

    // Bleed padFactor away in near-silence, so a passage that ended in a
    // burst of overspill does not hold the gain down through the gap.
    pfDecayed = select2(rect < 0.01, pf, pf * 0.9999);

    // Running sum: add the newest overspill, drop the trailing one -- but
    // only when we are not growing. Growing means keeping the tail, which
    // is why release never steps.
    added = pfDecayed + s;
    tapOld = tap(lwc);
    tapNew = tap(shrunk);
    shrunk = max(minWidth, lwc - 1);

    // The random target: the window grows whenever a uniform draw scaled by
    // targetWidth lands above the current width, so the drift is stochastic
    // rather than a fixed ramp and leaves no periodic artefact behind.
    expanding = (targetWidth * uniform) > lwc;
    shrinking = targetWidth < lwc;

    lastWidth = select2(expanding, select2(shrinking, lwc, shrunk), lwc + 1)
              : min(maxWidth) : int;
    padFactor = select2(expanding, select2(shrinking, added - tapOld,
                                           added - tapOld - tapNew), added)
              : max(0.0);

    uniform = (rnd + 1.0) * 0.5;
    tap(w) = de.delay(maxWidth, int(w) - 1, sPrev);
};
