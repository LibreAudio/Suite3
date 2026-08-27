declare author "Klaus Scheuermann";
declare description "";
declare license "GPL-3.0-or-later";
declare name "Gate";
declare unique_id "LAga";

// declare drywet "true";

import("stdfaust.lib");

// Noise gate. The detector below is ef.gate_gain_mono (Julius O. Smith III,
// STK-4.3, misceffects.lib) with one change -- see gateGain. Below Threshold
// the signal is muted; Attack, Hold and Release shape how the gate opens and
// closes.
//
// Hysteresis gives the open and close decisions two different thresholds: the
// gate opens at Threshold but will not let go until the level has fallen a
// further Hysteresis dB. A signal hovering at the threshold would otherwise
// cross it over and over and chatter the gate open and shut. Hold fixes the
// same problem from the time axis by keeping the gate open for a minimum
// spell; Hysteresis fixes it on the level axis, with no minimum imposed, so a
// note that sustains around the threshold for seconds stays open without
// needing a Hold long enough to swallow real gaps.
//
// Range caps how far the gate is allowed to pull the signal down, so a closed
// gate ducks rather than mutes -- room tone and spill stay present instead of
// the track dropping into holes. At the top of its travel it is a true mute.
//
// Detection is *linked*: one gain, derived from |L| + |R|, drives both
// channels. Two independent detectors would open the channels by different
// amounts on the same transient and swing the stereo image with it.
//
// The sidechain filters shape what the detector hears and never the audio:
// a high pass keeps the kick from holding the gate open, a low pass keeps
// hiss and cymbal spill from doing the same, and the tilt weights the whole
// detector towards one end of the spectrum. Listen monitors that filtered
// signal so they can be set by ear.
//
// S-Curve rounds the release: a second switching one-pole in series with the
// gate's own. A plain exponential is steepest the instant it starts and only
// ever slows down; the pair leaves gently, reaches its fastest partway down and
// then eases into silence, so it cannot chop the front off a tail. The S is on
// the gain axis -- on a dB meter it reads as a ramp that gets steeper, because
// a straight dB ramp *is* the plain exponential.
//
// Lookahead delays the audio while the detector keeps reading it undelayed, so
// the gate is already open by the time the transient arrives at the output.
// Without it the attack always eats the leading edge of the note.
//
// No Bypass control here: the host wrapper provides one (see
// LibreAudioPlugin.cpp), and input/output trim, phase and M/S come from
// common/input.dsp and common/output.dsp.

Nch = 2;                            // gate is stereo

maxSR = 192000;
maxLookaheadMs = 10;
maxLookaheadSamples = int(maxLookaheadMs * maxSR / 1000);   // 1920

process = si.bus(Nch) : gate;

// --- UI structure ---

uiTop(x)    = hgroup("[0]Stage Top", x);
uiBottom(x) = hgroup("[8]Stage Bottom", x);
uiBottomLeft(x)  = uiBottom(hgroup("[1]Stage Bottom Left", x));
uiBottomRight(x) = uiBottom(hgroup("[1]Stage Bottom Right", x));
uiMeters(x) = hgroup("[9]", x);

uiMonitor(x) = uiTop(hgroup("[0]Monitor", x));

// --- Parameters ---

// Smoothed: the threshold is compared against the detector every sample, so
// stepping it while audio runs would otherwise snap the gate open or shut.
threshold = uiBottomLeft(hslider("[01]Threshold[style:knob][unit:dB][symbol:threshold][label:Threshold][accentcolor:01][easy]
      [tooltip: Level below which the signal is muted]", -30, -120, 0, 0.1)) : si.smoo;

// Not smoothed, unlike Threshold: taken straight from the slider it stays a
// per-block scalar, so the second threshold costs one multiply per sample
// rather than a second pow. A step in it can only flip the gate while the
// level sits between the two thresholds, and the flip is handed to the
// attack/release envelope, which ramps rather than clicks.
hysteresis = uiBottomLeft(hslider("[02]Hysteresis[style:knob][unit:dB][symbol:hysteresis][label:Hysteresis][accentcolor:01]
      [tooltip: How far below Threshold the level must fall before the gate closes. Stops it chattering on a signal that hovers at the threshold. 0 dB = off]",
      0, 0, 20, 0.1));

// The top of the knob is a true mute, not db2linear(-60): the multiply by
// (range < rangeMax) drops the floor to exactly zero there, so the default is
// bit-identical to a gate with no Range at all. The step it introduces at the
// very top of the travel is from -60 dB to silence, which is the "infinity"
// mark on a hardware Range control and is inaudible either way.
//
// Smoothed after the conversion, not before: db2linear of a bare slider stays
// a per-block scalar, and si.smoo on the result is a one-pole per sample
// rather than a pow per sample. It has to be smoothed at all because the floor
// scales the output gain directly -- turning Range while the gate is shut
// would otherwise step the audio.
rangeMax = 60;

range = uiBottomLeft(hslider("[03]Range[style:knob][unit:dB][symbol:range][label:Range][accentcolor:01]
      [tooltip: Ceiling on how far the gate pulls the signal down. Lower values duck instead of muting, so room tone stays. At maximum the gate mutes completely]",
      rangeMax, 0, rangeMax, 0.1));

grFloor = ba.db2linear(0 - range) * (range < rangeMax) : si.smoo;

//---- sidechain filter ----
// Shapes what the detector hears, never the audio. Both defaults are at the
// end of their range where the filter is effectively out of circuit.

scHp = uiBottomLeft(hslider("[04]SC High Pass[style:knob][unit:Hz][scale:log][symbol:sc_hp][label:SC HP][accentcolor:06][bracket:SIDECHAIN]
      [tooltip: Keeps bass out of the detector, so kick and rumble stop holding the gate open. 20 Hz = effectively off]",
      20, 20, 500, 1));

scLp = uiBottomLeft(hslider("[05]SC Low Pass[style:knob][unit:Hz][scale:log][symbol:sc_lp][label:SC LP][accentcolor:06][bracket:SIDECHAIN]
      [tooltip: Keeps air, hiss and cymbal spill out of the detector. 20 kHz = effectively off]",
      20000, 1000, 20000, 1));

// One knob instead of a bell's three: a shelf pair pivoting at a fixed
// frequency, weighting the detector towards the highs or towards the lows
// rather than picking out one band. The same tilt compressor.dsp puts on its
// sidechain. At 0 dB both shelves collapse to unity, so an idle tilt is an
// exact bypass.
scTilt = uiBottomLeft(hslider("[06]SC Tilt[style:knob][unit:dB][symbol:sc_tilt][label:SC Tilt][accentcolor:04][bracket:SIDECHAIN]
      [tooltip: Weights the detector across the spectrum, pivoting at 700 Hz. Positive makes it hear the highs, so it reacts to snare and sibilance; negative makes it hear the low end]",
      0, -12, 12, 0.1));

scTiltFreq = 700;   // pivot
scTiltRes  = 0.7;   // shelf Q -- flat, no bump at the pivot

// Monitors the filtered sidechain instead of the gated audio, so the filters
// can be set by ear: sweep until the trigger stands alone and everything else
// falls away, then set Threshold. It is a monitoring switch, not a mix
// control -- the level is whatever the filters leave behind. Smoothed so it
// cross-fades rather than hard-switches and does not click when toggled while
// playing.
scListen = uiMonitor(checkbox("[01]Listen[symbol:sc_listen][label:Listen]
      [tooltip: Monitors the filtered sidechain, ungated, for setting the sidechain filters by ear. Turn off before printing]")) : si.smoo;

// Both pivot constants, so the SVFs' tan() folds away at compile time and only
// the gain-dependent scalars are recomputed when the knob moves.
scFilter = fi.highpass(2, scHp)
         : fi.lowpass(2, scLp)
         : fi.svf.ls(scTiltFreq, scTiltRes, 0 - scTilt)
         : fi.svf.hs(scTiltFreq, scTiltRes, scTilt);

// Times are floored at one sample: an.amp_follower_ar turns a zero time
// constant into a division by zero.
oneSample = 1.0 / float(ma.SR);

// Reported to the host as latency and compensated, so raising it does not
// shift the plugin against the rest of the session. Not smoothed and stepped
// in whole samples: the delay has to be exactly the number the latency meter
// reports, or the host's compensation would be aligned to a different figure.
lookaheadMs = uiBottomRight(hslider("[10]Lookahead[style:knob][unit:ms][symbol:lookahead][label:Lookahead][accentcolor:03][bracket:ENVELOPE]
      [tooltip: Delays the audio so the gate is already open when the transient arrives. Reported to the host as latency and compensated. 0 = off]",
      0, 0, maxLookaheadMs, 0.1));

lookaheadDelay = int(lookaheadMs * ma.SR / 1000);

// In ms rather than the µs of the original, so all three envelope controls
// read in the same unit. 0.01 ms is the same default as the 10 µs it had.
attack = uiBottomRight(hslider("[11]Attack[style:knob][unit:ms][scale:log][symbol:attack][label:Attack][accentcolor:03][bracket:ENVELOPE]
      [tooltip: Time constant for the gate to open (exponentially) from muted to unmuted]",
      0.01, 0.01, 10, 0.001)) : *(0.001) : max(oneSample);

hold = uiBottomRight(hslider("[12]Hold[style:knob][unit:ms][scale:log][symbol:hold][label:Hold][accentcolor:03][bracket:ENVELOPE]
      [tooltip: Time the gate stays open after the level falls below the Threshold]",
      200, 1, 1000, 1)) : *(0.001) : max(oneSample);

release = uiBottomRight(hslider("[13]Release[style:knob][unit:ms][scale:log][symbol:release][label:Release][accentcolor:03][bracket:ENVELOPE]
      [tooltip: Time constant for the gate to close (exponentially) from unmuted to muted]",
      100, 1, 1000, 1)) : *(0.001) : max(oneSample);

// Cascading two one-poles of equal time constant stretches the 1/e point from
// one time constant to 2.146 of them -- the root of (1 + t/tau)*exp(-t/tau) =
// 1/e -- so both stages run at release/2.146 when the curve is engaged and the
// knob keeps meaning what it says. Measured at Release 100 ms: 96.0 ms to
// -8.686 dB either way.
sCurveStretch = 2.146;

sCurve = uiBottomRight(checkbox("[14]Release S-Curve[symbol:release_scurve][label:S-Curve][bracket:ENVELOPE]
      [tooltip: Rounds the release into an S: it leaves gently, falls fastest partway down and eases into silence, instead of being steepest the moment it starts]")) : si.smoo;

// Both the shaped and unshaped envelopes are computed and crossfaded, so
// toggling mid-note slides between them instead of jumping. At 0 the blend
// returns the unshaped envelope exactly and the release time is untouched.
releaseShaped = release / it.interpolate_linear(sCurve, 1.0, sCurveStretch) : max(oneSample);

// --- Meter ---

// Shown as reduction (positive dB down) like the other LAS meters, hence the
// sign flip. Floored before the log: a fully closed gate has a gain of exactly
// 0, and ba.linear2db(0) is -inf.
maxGR = 60;
gate_meter = uiMeters(hbargraph("[1]Gate Reduction[unit:dB][symbol:gate_meter]", 0, maxGR));

// A passive widget with this exact symbol is what the build turns into the
// plugin's reported latency (see the latency_samples cases in
// src/templates/dsp.cpp.in), so the host delay-compensates Lookahead. Its max
// also sizes the wrapper's latency buffer, and LibreAudioPlugin.cpp asserts
// latency < that max -- hence the spare sample, so 10 ms at 192 kHz still fits.
latency_meter = _ <: attach(_, uiMeters(hbargraph("[2]latency_samples[symbol:latency_samples][unit:samples]",
                                                  0, maxLookaheadSamples + 1)));

lookaheadSamples = lookaheadDelay : latency_meter;

// --- Gate gain ---


// ef.gate_gain_mono, with its one stateless comparison replaced by a Schmitt
// trigger so the threshold can differ on the way up and on the way down.
// Everything else -- the level follower, the hold counter, the attack/release
// envelope -- is the library's, kept as it stands.
//
// The comparison had to move in here rather than wrap the library call: the
// `>` inside gate_gain_mono is memoryless, so there is nowhere outside it to
// introduce a second threshold from.
//
// At Hysteresis 0 the two thresholds are equal, select2 returns the same value
// on both branches and the expression collapses to exactly the library's
// `inlevel > db2linear(thresh)` -- same sample, no added delay, bit-identical
// output. Verified against the library build over 120k samples.
gateGain(x) = x : extendedrawgate : si.onePoleSwitching(attack, releaseShaped)
with {
    // The library's detector, untouched.
    minrate = min(attack, releaseShaped);
    inlevel = an.amp_follower_ar(minrate, minrate);

    // One pow per sample for the open threshold, as before; the close
    // threshold is that scaled by a per-block constant.
    openAt  = ba.db2linear(threshold);
    closeAt = openAt * ba.db2linear(0 - hysteresis);

    holdsamps = int(hold * ma.SR);

    // What is fed back as the state is the *held* gate, not the bare
    // comparison, and that is what makes this work at audio rate. At the
    // default 0.01 ms attack the library's detector tracks the waveform rather
    // than its envelope, so the level returns to zero every cycle; a Schmitt
    // trigger on that bare comparison would cross both thresholds every period
    // however far apart they were, and hysteresis would do nothing at all.
    // Held, the state survives the dips between peaks, so each new peak is
    // judged against the lower threshold and the gate stays open until the
    // envelope itself has fallen Hysteresis dB. Hold therefore sets how long
    // the decision stays sticky -- at its 200 ms default, down to a 5 Hz
    // wobble; at its 1 ms minimum, only to about 1 kHz.
    extendedrawgate(x) = inlevel(x) : gateState;

    gateState = step ~ _
    with {
        step(wasOpen, lv) = extended
        with {
            // open while shut, close while open: the sticky comparison
            raw      = lv > select2(wasOpen > 0.5, openAt, closeAt);

            // hold, verbatim from the library: a down-counter reloaded
            // whenever the raw gate falls, holding the gate open while it runs
            reload   = raw < raw';
            counter  = (max(reload * holdsamps, _) ~ -(1));
            extended = max(float(raw), counter > 0);
        };
    };
};

// --- Gate ---

// The gain is computed once and applied to both channels, rather than calling
// ef.gate_stereo and re-deriving the same gain a second time for the meter.
//
// The detector reads l and r undelayed while the audio goes through the
// lookahead delay: that is the whole point, the gain is already up when the
// transient reaches the multiplier. Both channels share one delay length, so
// the two references to lookaheadSamples are the same signal and the latency
// bargraph is instantiated once.
gate(l, r) = attach(outL, reductionDb : gate_meter), outR
with {
    delayed = de.delay(maxLookaheadSamples, lookaheadSamples);

    // Filtered per channel and rectified afterwards, rather than filtering a
    // mono sum: |L| + |R| is the magnitude ef.gate_stereo feeds its detector,
    // so Threshold keeps meaning exactly what it did before the filters
    // existed. A mono sum would read 6 dB lower on correlated material and
    // silently move every stored Threshold with it.
    scL = l : scFilter;
    scR = r : scFilter;

    // Stage one is gateGain's own envelope; stage two is a second switching
    // one-pole whose attack is a single sample, so it passes the opening
    // through untouched and only shapes the way down. Two equal poles in
    // series give a step response with zero initial slope and an inflection --
    // an S -- while still decaying to true zero, which a warp of the gain into
    // a bounded dB range would not.
    grRaw  = gateGain(abs(scL) + abs(scR));
    grGate = it.interpolate_linear(sCurve, grRaw, grRaw : si.onePoleSwitching(oneSample, releaseShaped));

    // Range rescales the envelope's travel rather than clamping it: the gate
    // still moves over its whole range, it just runs between grFloor and 1
    // instead of between 0 and 1. A clamp would put a corner in the curve at
    // the moment the floor is reached, and would need the reduction in dB --
    // another pow per sample -- to find that moment.
    gr = grFloor + grGate * (1 - grFloor);

    // The meter reads what is actually applied, so it tops out at Range.
    reductionDb = 0 - (gr : max(ba.db2linear(0 - maxGR)) : ba.linear2db);

    // The monitored sidechain goes through the same delay as the audio, so
    // what is heard stays aligned with the latency the host is compensating
    // for. It is deliberately not gated: the point is to hear what the
    // detector is being fed, before the decision it drives.
    outL = it.interpolate_linear(scListen, delayed(l) * gr, delayed(scL));
    outR = it.interpolate_linear(scListen, delayed(r) * gr, delayed(scR));
};
