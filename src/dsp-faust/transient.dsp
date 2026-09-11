declare author "Klaus Scheuermann";
declare description "";
declare license "GPL-3.0-or-later";
declare name "Transient";
declare unique_id "LAtd";

declare drywet "true";


// For some parts of this file, a large language model was involved as a coding assistant.
// The ideas, the design decisions and the listening behind it are purely human.

import("stdfaust.lib");


Nch = 2;                    // stereo    

maxSR = 192000;
maxLookaheadMs = 10;
maxLookaheadSamples = int(maxLookaheadMs * maxSR / 1000);   // 1920

process = si.bus(Nch) : transient : makeup : clipper;

// --- UI structure ---

uiMain(x) = hgroup("[8]Transient Control", x);
uiShape(x)   = uiMain(hgroup("[1]Shape", x));
uiTime(x) = uiMain(hgroup("[2]Time", x));
uiSidechain(x)  = uiMain(hgroup("[3]Sidechain", x));
uiOutput(x) = uiMain(hgroup("[4]Output", x));
uiMeters(x) = hgroup("[9]Meters", x);

// --- Parameters ---


attack = uiShape(hslider("[01]Attack[style:knob][unit:%][symbol:attack][label:Attack][accentcolor:01][easy]
      [tooltip: Emphasises (positive) or softens (negative) the leading edge of every hit. Acts only while the level is rising]",
      0, -100, 100, 1)) / 100 : si.smoo;

sustain = uiShape(hslider("[02]Sustain[style:knob][unit:%][symbol:sustain][label:Sustain][accentcolor:02][easy]
      [tooltip: Lifts (positive) or shortens (negative) the tail of every hit. Acts only while the level is falling]",
      0, -100, 100, 1)) / 100 : si.smoo;


maxRange = 24;

range = uiShape(hslider("[03]Range[style:knob][unit:dB][symbol:range][label:Range][accentcolor:04]
      [tooltip: Ceiling on how far Attack and Sustain may push the gain, in either direction. The gain approaches it smoothly rather than clipping to it]",
      12, 1, maxRange, 0.1)) : si.smoo : max(1.0);

// makeup
makeup_dB = uiOutput(hslider("[03]makeup[style:knob][unit:dB][symbol:makeup][label:Makeup][accentcolor:05]", 0, -12, 12, 0.1)) : si.smoo : ba.db2linear;
makeup = par(i,Nch, _ * makeup_dB);

// hard clipper
// The threshold is the ceiling: no sample leaves above it. A quadratic knee
// bends the signal into it from clipKneeDb below, so the corner is rounded but
// the ceiling is exact. At 0 dB it is switched out and the signal passes bit-exact.
clipThreshDb = uiOutput(hslider("[04]Clip Threshold[style:knob][unit:dB][symbol:clip_threshold][label:Clip][accentcolor:05]
      [tooltip: Ceiling of the output clipper. No sample leaves above it; a small knee rounds off the corner just below. 0 dB = off]",
      0, -6, 0, 0.1));

clipKneeDb = 1;
clipKnee   = ba.db2linear(0 - clipKneeDb);

// Not a plain si.smoo: a smoothed ceiling lags the knob, and on the way down
// that lag is time spent above the threshold. The ceiling drops with the knob
// and only glides on the way up. Smoothing 1 - T instead of T boots it at
// 0 dBFS, so min() hands over the knob's value from the first sample.
clipTRaw = ba.db2linear(clipThreshDb);
clipT    = min(clipTRaw, 1 - ((1 - clipTRaw) : si.smoo));

// Linear to the knee start s, a parabola from s to e = T + (T - s) that meets
// T with zero slope, flat at T beyond. The min() only catches float rounding
// at the top of the parabola.
hardClip(x) = ma.signum(x) * min(clipT, y)
with {
    a = abs(x);
    s = clipT * clipKnee;
    w = clipT - s;
    y = ba.if(a <= s, a, ba.if(a >= clipT + w, clipT, a - (a - s) * (a - s) / (4 * w)));
};

// Engaged and bypassed instantly: a crossfade would leak unclipped peaks for
// as long as it ran, including at every plugin start.
clipOn = clipThreshDb < 0;

// Meters whichever channel is pulled down harder, as positive dB of reduction.
// Peak-held with a 0.3 s decay, as in clipper.dsp: the UI reads the value once
// per block, so an instantaneous gain would show whichever sample the block
// happened to end on.
clipper(l, r) = attach(yl, clipDb : clipHold : clip_meter), yr
with {
    clip1(x) = ba.if(clipOn, hardClip(x), x);
    yl = clip1(l);
    yr = clip1(r);

    // 1 below the knee, where the clipper passes the sample untouched
    gainOf(x, y) = ba.if(abs(x) > clipT * clipKnee, abs(y) / max(abs(x), 1e-9), 1);
    clipDb = 0 - ba.linear2db(max(ba.db2linear(0 - maxClipDb), min(gainOf(l, yl), gainOf(r, yr))));
};

// Times are floored at one sample
oneSample = 1.0 / float(ma.SR);

// Attack
attackTime = uiTime(hslider("[10]Attack Time[style:knob][unit:ms][scale:log][symbol:attack_time][label:Atk Time][accentcolor:03][bracket:ENVELOPE][easy]
      [tooltip: How long a rise is followed as an attack. Short reads the stick alone, long reaches into the body of the note]",
      15, 1, 100, 0.1)) : *(0.001) : max(oneSample);

// Release
sustainTime = uiTime(hslider("[11]Sustain Time[style:knob][unit:ms][scale:log][symbol:sustain_time][label:Sus Time][accentcolor:03][bracket:ENVELOPE][easy]
      [tooltip: How long a decay is followed as sustain. Sets the stretch of tail the Sustain knob acts on]",
      200, 20, 1000, 1)) : *(0.001) : max(oneSample);

// Lookahead and latency
lookaheadMs = uiTime(hslider("[3]Lookahead[style:knob][unit:ms][symbol:lookahead][label:Lookahead][accentcolor:03][bracket:ENVELOPE]
      [tooltip: Delays the audio so the gain is fully up by the time the leading edge arrives, rather than still ramping through it. 1-2 ms is all it takes. Reported to the host as latency and compensated. 0 = off]",
      0, 0, maxLookaheadMs, 0.1));

lookaheadDelay = int(lookaheadMs * ma.SR / 1000);

//---- sidechain filter ----
scHp = uiSidechain(hslider("[20]SC High Pass[style:knob][unit:Hz][scale:log][symbol:sc_hp][label:SC HP][accentcolor:06][bracket:SIDECHAIN]
      [tooltip: Keeps bass out of the detector, so the kick stops deciding what counts as a transient and the snare and the picking hand drive the shaping instead. 20 Hz = effectively off]",
      20, 20, 500, 1));

scLp = uiSidechain(hslider("[21]SC Low Pass[style:knob][unit:Hz][scale:log][symbol:sc_lp][label:SC LP][accentcolor:06][bracket:SIDECHAIN]
      [tooltip: Keeps air, hiss and cymbal spill out of the detector, so the shaping follows the body of the kit rather than its top end. 20 kHz = effectively off]",
      20000, 1000, 20000, 1));

scFilter = fi.highpass(2, scHp) : fi.lowpass(2, scLp);

// --- Detector constants ---

// Floor for the detector
detFloorDb = -90;
detFloorLin = ba.db2linear(detFloorDb);

// Release of the peak follower
detRelease = 0.050;

// Gain smoothing
// gainSmoothTau = 0.0005;
gainSmoothTau = uiTime(hslider("[2]Smooth[style:knob][unit:ms][scale:log][symbol:gain_smooth][label:Smooth][accentcolor:03][bracket:ENVELOPE]", 5, 1, 50, 1)) / 10000;

// --- Meters ---
gain_meter = uiMeters(hbargraph("[1]Transient Gain[unit:dB][symbol:gain_meter]", 0 - maxRange, maxRange));

maxClipDb = 24;
clipHold = max ~ *(ba.tau2pole(0.3));
clip_meter = uiMeters(hbargraph("[3]Clip Reduction[unit:dB][symbol:clip_meter][label:Clip]", 0, maxClipDb));

// Latency report to DPF
latency_meter = _ <: attach(_, uiMeters(hbargraph("[2]latency_samples[symbol:latency_samples][unit:samples]",
                                                  0, maxLookaheadSamples + 1)));

lookaheadSamples = lookaheadDelay : latency_meter;

// --- Transient shaper ---


transient(l, r) = attach(outL, gainDb : gain_meter), outR
with {
    delayed = de.delay(maxLookaheadSamples, lookaheadSamples);

 
    levelDb = abs(l : scFilter) + abs(r : scFilter)
            : si.onePoleSwitching(oneSample, detRelease)
            : max(detFloorLin)
            : ba.linear2db
            : -(detFloorDb);


    lagAttack  = si.smooth(ba.tau2pole(attackTime));
    lagSustain = si.onePoleSwitching(oneSample, sustainTime);

    // Rising
    dAttack  = max(0, levelDb - (levelDb : lagAttack));
    dSustain = max(0, (levelDb : lagSustain) - levelDb);

    // Range
    raw    = attack * dAttack + sustain * dSustain;
    gainDb = range * ma.tanh(raw / range);

    // Smoothed in dB
    gain = gainDb : si.smooth(ba.tau2pole(gainSmoothTau)) : ba.db2linear;

    outL = delayed(l) * gain;
    outR = delayed(r) * gain;
};
