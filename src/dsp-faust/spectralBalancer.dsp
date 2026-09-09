import("stdfaust.lib");

declare author "Klaus Scheuermann";
declare description "Adaptive spectral balancer - 20 band K-weighted tonal-balance correction";
declare license "GPL-3.0-or-later";
declare name "Spectral Balancer";
declare unique_id "LAsb";

//=============================================================================
// SPECTRAL BALANCER
//
// Stereo in, stereo out, fully linked: the whole analysis runs on the mono sum
// of both channels, so L and R always receive the identical correction and the
// stereo image is never moved.
//
// How it works, in the order the signal flows:
//
//   1. ANALYSIS. The detector signal (the mono sum) is split into Nbands
//      constant-Q bandpasses, spaced logarithmically between fLo and fHi. Each
//      band and the unfiltered fullrange signal get the same envelope detector
//      (RMS with independent attack/release). The band levels are K-weighted -
//      see weightDb, which folds the shelf in as a constant per band.
//
//   2. NORMALISED CURVE. Every band level is expressed relative to a fullrange
//      envelope built with that band's own time constants. That makes the curve
//      independent of how loud the programme is - it is the *shape* of the
//      spectrum, not its level. The bands are constant-Q (equal width on a log
//      axis), so before weighting a pink spectrum reads flat; with the
//      K-weighting shelf in, pink reads as the shelf itself, rising to +4 dB
//      above ~3 kHz, and a flat target therefore asks for a spectrum that is
//      flat to a loudness meter rather than flat to an energy meter.
//
//   3. TARGET. Nbands target sliders, plus a global Tilt in dB/octave, define
//      the wanted shape. Curve and target are compared band by band.
//
//   4. LEVEL NEUTRALITY. The band-weighted mean is removed from the deviation
//      before it becomes gain, so the corrections always sum to zero: the
//      balancer changes tonal balance only, never overall loudness. A uniform
//      offset between curve and target is a level difference, not a balance
//      problem, and is ignored.
//
//   5. GATING. Two gates keep the correction out of silence and out of empty
//      parts of the spectrum:
//        - Threshold: fullrange level below it -> correction fades to nothing.
//          It scales the gains after the ballistics, so it does not have to
//          wait for Release to be heard.
//        - Band Range: a band sitting more than that far below the average
//          band carries no usable programme (a band-limited source, air above
//          16 kHz on an MP3). It is neither corrected nor counted in the mean,
//          which stops the balancer from boosting hiss into existence.
//
//   6. CORRECTION. One svf bell per band, in series, on each channel. Bell
//      gains follow the deviation through the Attack/Release ballistics - tilted
//      across the spectrum by Band Speed, so the top tracks faster than the
//      bottom, which needs the long window its cycles ask for - scaled
//      by Strength and clipped to +-Range. Because neighbouring bells overlap,
//      the wanted curve is first run through the inverse of the bank's overlap
//      (see kern), so a correction lands at the size it was asked for instead of
//      being piled up by its neighbours.
//
// Kinship: Voxengo TEOTE works from the same idea (a level-normalised spectrum
// steered towards a target curve); nothing here is taken from it.
//=============================================================================

process = balancer;

//----------------------------------------------------------------- constants
Nbands = 20;        // analysis bands = correction bells = target sliders
fLo    = 30.0;      // Hz, centre of the lowest band
fHi    = 16000.0;   // Hz, centre of the highest band

// Log-spaced band centres. Clamped below Nyquist so a 32 kHz session cannot
// park a filter on the unit circle. ma.SR is fixed at init, so every one of
// these coefficients is still computed once, not per sample.
bandRatio  = pow(fHi/fLo, 1.0/(Nbands - 1));            // ~1.392, i.e. 0.477 oct
fc(i)      = min(fLo * pow(bandRatio, i), 0.45*ma.SR);
fRef       = sqrt(fLo*fHi);                             // tilt pivot, ~693 Hz
octSpacing = log(bandRatio)/log(2.0);                   // band spacing in octaves

// Q of a filter whose -3 dB bandwidth is bw octaves:  Q = 1/(2 sinh(ln2/2 bw))
qOct(bw) = 1.0/(2.0*sh(0.5*log(2.0)*bw)) with { sh(x) = 0.5*(exp(x) - exp(0.0-x)); };

qAnalysis = qOct(octSpacing);               // analysis bandpasses: one spacing wide
bellWidth = 1.0;                            // correction bells, in band spacings
qBell     = qOct(octSpacing*bellWidth);

// De-overlap kernel. The bells overlap, so the correction the cascade actually
// produces at a band centre is not that band's bell gain but the sum of every
// bell's response there: applied = W . g, with W(i,j) = bellW(|i-j|) (a peaking
// filter's small-signal dB response follows the normalised bandpass magnitude
// of its own shape). Left uncompensated, a broad correction comes out ~3x too
// big and a narrow one about right - the bank is a lowpass across band index.
//
// So the wanted curve is run through the inverse, g = W^-1 . want, which for
// this bank is a short symmetric FIR across the band index: a mild sharpener.
// The taps are the centre row of inv(W) for the geometry below, computed with
//
//   import numpy as np, math
//   N, fLo, fHi = 20, 30., 16000.
//   r = (fHi/fLo)**(1/(N-1)); Q = 1/(2*math.sinh(math.log(2)/2*math.log2(r)))
//   w = lambda d: 1/math.sqrt(1 + (Q*(r**abs(d) - r**-abs(d)))**2)
//   print(np.linalg.inv([[w(i-j) for j in range(N)] for i in range(N)])[N//2])
//
// Regenerate them if Nbands, fLo, fHi or bellWidth change - the shape barely
// moves (the bank is self-similar on a log axis) but the tails need more taps
// the closer the bands sit. With these six a single band out of line lands
// within 0.1%, a one-octave feature within 0.2%, a three-octave one within 1%.
// A curve that ramps across the whole range (a full-scale Tilt) is the hard
// case for any finite bank: it comes out at about two thirds, the shortfall
// sitting at the outermost bands, which have nothing beyond the ends to lean
// on.
kTaps    = 5;                 // kernel half-width, in bands
kern(0)  =  1.4719;
kern(1)  = -0.5128;
kern(2)  = -0.0162;
kern(3)  = -0.0249;
kern(4)  = -0.0119;
kern(5)  = -0.0070;
bandIdx(k) = max(0, min(Nbands - 1, k));   // edge bands repeat, folded at compile time

// Nyquist warping compensation. The bilinear map squeezes a constant-Q band as
// it nears Nyquist: the SVF peak still sits exactly on fc, but the skirt above
// it is compressed, so the band collects less energy than the same filter would
// in the analog domain and reads low - about 4 dB at 16 kHz / 44.1 kHz. On pink
// programme that looks like a droop at the top of the spectrum, and the
// balancer would dutifully boost it. warpDb puts it back. It is the shortfall
// in -3 dB bandwidth, BW = g*SR/(pi*(1+g^2)) against the unwarped fc/Q, plus a
// small quadratic term that brings it in line with the exact pink-weighted
// integral of the warped response (within 0.1 dB up to 16 kHz at 44.1 kHz).
// Runs on ma.SR, so it is computed once at init, not per sample.
gTan(i)   = tan(ma.PI*fc(i)/ma.SR);
relBW(i)  = gTan(i)*ma.SR / (ma.PI*(1.0 + gTan(i)*gTan(i))*fc(i));
warpDb(i) = x - 0.03*x*x with { x = min(8.0, 0.0 - 10.0*log10(relBW(i))); };

// The correction bells are squeezed by the same warping, and what suffers
// there is coverage rather than level: a 16 kHz bell at 44.1 kHz spans a third
// of the octave range it was meant to, leaving a hole between it and its
// neighbour, so a broad correction at the top never reaches the size it was
// asked for. Widening the bell by the same factor puts its skirts back where
// the band spacing expects them - worth about 0.5 dB on a full-scale Tilt at
// 16 kHz. Capped at twice nominal width, past which the low skirt reaches
// further down than it repairs.
qBellOf(i) = max(qBell*relBW(i), 0.5*qBell);

// Detector weighting: the high shelf of ITU-R BS.1770 K-weighting, with the
// standard's own parameters, as a per-band constant added to the measurement.
// The standard's RLB high-pass is deliberately left out - the 30-60 Hz bands
// should stay fully visible to the balancer rather than be discounted.
//
// It is an offset rather than a filter in the detector path because after the
// curve's mean is removed the two are identical, and the offset costs nothing,
// keeps the meters reading in weighted dB, and leaves the fullrange envelope
// unweighted so that Threshold stays a plain broadband gate. Consequence worth
// knowing: with the sliders flat the balancer now aims for a spectrum that is
// flat *weighted*, i.e. about 4 dB below pink above 3 kHz.
//
// Magnitude of the RBJ analog high-shelf prototype at each band centre:
//   |H|^2 = A^2 * ((1 - A x^2)^2 + A x^2/Q^2) / ((A - x^2)^2 + A x^2/Q^2)
kwGain = 3.999843853973347;   // dB, BS.1770 stage 2
kwFreq = 1681.974450955533;   // Hz
kwQ    = 0.7071752369554196;
kwA    = pow(10.0, kwGain/40.0);
weightDb(i) = 10.0*log10(kwA*kwA*num/den)
with {
    x2  = (fc(i)/kwFreq)*(fc(i)/kwFreq);
    im2 = kwA*x2/(kwQ*kwQ);
    num = (1.0 - kwA*x2)*(1.0 - kwA*x2) + im2;
    den = (kwA - x2)*(kwA - x2) + im2;
};

// One-pole coefficient for a tau in seconds. ba.tau2pole is exp(-1/(tau*SR)),
// and this graph would ask for about a hundred of those per sample - two per
// detector plus one per gain smoother. Over the range these knobs cover
// 1/(tau*SR) never exceeds ~0.02, where the first term of the series is within
// 1% on tau, so a divide does the job the exponential was doing.
pole(tau) = 1.0 - 1.0/max(1.0, tau*ma.SR);

gateKnee   = 6.0;   // dB, soft knee of both gates

maxLookaheadSamples = 9600;   // 50 ms at 192 kHz; also sizes the host's
                              // latency buffer (see src/templates/config.h.in)

//----------------------------------------------------------------- UI groups
// Two rows.
//
// CONTROLS is three knob groups side by side, reading left to right in the
// order the signal is thought about: how it is measured, how much to act on
// it, how the acting moves.
//
// BANDS underneath is the per-band display: three strips of Nbands stacked so
// the columns line up under each other - what you asked for, what the balancer
// measured, what it did about it.
//
// Faust orders a group's children by comparing the [n] prefix as text rather
// than as a number, so every index here stays a single digit and each group
// counts from 0.
uiControls(x)   = hgroup("[0]CONTROLS", x);
uiAnalysis(x)   = uiControls(hgroup("[0]ANALYSIS", x));
uiAmount(x)     = uiControls(hgroup("[1]AMOUNT", x));
uiCorrection(x) = uiControls(hgroup("[2]CORRECTION", x));

uiBands(x)    = vgroup("[1]BANDS", x);
uiTarget(x)   = uiBands(hgroup("[0]Target", x));
uiSpectrum(x) = uiBands(hgroup("[1]Spectrum", x));
uiGain(x)     = uiBands(hgroup("[2]Gain", x));

//----------------------------------------------------------------- controls
// Amount of the measured deviation that is actually corrected.
strength = uiAmount(hslider("[0]Strength[unit:%][style:knob][symbol:strength]
      [label:Strength][accentcolor:01][easy]
      [tooltip: How much of the difference between the measured spectrum and
       the target curve is corrected. 0% = analysis only, 100% = the balancer
       tries to hit the target exactly]",
                                  50, 0, 100, 1)) / 100;

// Ceiling on any single band's correction.
range = uiAmount(hslider("[1]Range[unit:dB][style:knob][symbol:range]
      [label:Range][accentcolor:01][easy]
      [tooltip: Maximum boost or cut per band]",
                               12, 0, 24, 0.5));

// Broad target shape on top of the sliders: dB per octave around fRef.
tilt = uiAmount(hslider("[2]Tilt[unit:dB/oct][style:knob][symbol:tilt]
      [label:Tilt][accentcolor:03][easy]
      [tooltip: Tilts the whole target curve. 0 = pink (equal energy per
       octave), negative = darker, positive = brighter]",
                              0, -3, 3, 0.05));

// Deviations smaller than this are left alone - keeps the balancer from
// chasing the last dB of a spectrum that is already close enough.
tolerance = uiAmount(hslider("[3]Tolerance[unit:dB][style:knob][symbol:tolerance]
      [label:Tolerance][accentcolor:04]
      [tooltip: Deadband. A band whose deviation from the target is smaller
       than this gets no correction at all]",
                                   1, 0, 6, 0.1));

//--- left: ANALYSIS - how the spectrum is measured, and when it counts at all.
//    Faust orders a group's knobs by comparing the [n] prefix as text, not as a
//    number, so each group counts from 0 rather than running 0..11 across all
//    three - "[10]" would sort ahead of "[8]".
envAttack = uiAnalysis(hslider("[0]Env Attack[unit:ms][scale:log][style:knob][symbol:env_attack]
      [label:Env Att][accentcolor:06][bracket:ANALYSIS]
      [tooltip: Integration time of the level detectors on the way up]",
                                 20, 1, 500, 1)) / 1000;

envRelease = uiAnalysis(hslider("[1]Env Release[unit:ms][scale:log][style:knob][symbol:env_release]
      [label:Env Rel][accentcolor:06][bracket:ANALYSIS]
      [tooltip: Integration time of the level detectors on the way down. Also
       sets how quickly the Threshold gate notices that the programme stopped]",
                                  200, 5, 2000, 1)) / 1000;

threshold = uiAnalysis(hslider("[2]Threshold[unit:dB][style:knob][symbol:threshold]
      [label:Threshold][accentcolor:05][bracket:ANALYSIS][easy]
      [tooltip: Fullrange level below which nothing is corrected, so pauses and
       fades are left alone. The measured curve freezes with it, so a pause is
       held rather than re-learned]",
                                 -50, -80, 0, 0.5));

bandRange = uiAnalysis(hslider("[3]Band Range[unit:dB][style:knob][symbol:band_range]
      [label:Band Rng][accentcolor:05][bracket:ANALYSIS]
      [tooltip: How far a band may sit below the average band and still count.
       Bands quieter than that hold no programme - a band-limited source, air
       above 16 kHz on an MP3 - and are neither corrected nor averaged, which
       stops the balancer boosting what is not there]",
                                 18, 6, 48, 1));

//--- right: CORRECTION - how the gains move once the deviation is known
attack = uiCorrection(hslider("[0]Attack[unit:ms][scale:log][style:knob][symbol:attack]
      [label:Attack][accentcolor:02][bracket:CORRECTION]
      [tooltip: How fast a correction grows]",
                               100, 5, 2000, 1)) / 1000;

release = uiCorrection(hslider("[1]Release[unit:ms][scale:log][style:knob][symbol:release]
      [label:Release][accentcolor:02][bracket:CORRECTION]
      [tooltip: How fast a correction falls back towards flat]",
                                500, 20, 5000, 1)) / 1000;

// Correction speed across the spectrum. Low bands need long windows - a 30 Hz
// cycle is 33 ms on its own - while the top of the spectrum can be tracked in
// a few milliseconds without the gain audibly moving.
bandSpeed = uiCorrection(hslider("[2]Band Speed[style:knob][scale:log][symbol:band_speed]
      [label:Speed][accentcolor:02][bracket:CORRECTION]
      [tooltip: How much faster the top of the spectrum corrects than the
       bottom. 1 = every band shares Attack and Release exactly. 8 = the
       highest band is eight times faster than the lowest, the two spread
       evenly around the middle band, so the overall pace stays put as this
       knob is turned. It tilts the measurement windows with them]",
                                  4, 1, 32, 0.1));

// The times spread geometrically around the middle band: the bottom band is
// sqrt(bandSpeed) slower than the knobs say, the top band that much faster.
// Walked band to band as a running product, so the whole bank costs one pow
// and one sqrt per sample rather than an exponential each. The min() is a
// fence, not a limit: without it Faust's simplifier recognises the chain of
// multiplies and folds each rung back into pow(step, i), handing back the 32
// transcendentals the ladder exists to avoid. The bound is unreachable - the
// factor never leaves [1/6, 6].
speedStep  = pow(max(1.0, bandSpeed), 0.0 - 1.0/(Nbands - 1));
speedOf(0) = sqrt(max(1.0, bandSpeed));
speedOf(i) = min(1.0e30, speedOf(i - 1)*speedStep);

// Delays the audio while the detector keeps reading the signal as it arrives,
// so a correction is already in place by the time the sound reaches the bells.
lookaheadMs = uiCorrection(hslider("[3]Lookahead[unit:ms][style:knob][symbol:lookahead]
      [label:Lookahead][accentcolor:02][bracket:CORRECTION]
      [tooltip: Delays the audio so the correction is already in place when the
       sound arrives, instead of following it by an envelope's worth of time.
       Reported to the host as latency and compensated. 0 = off]",
                                    0, 0, 50, 0.1));

lookaheadSamples = int(lookaheadMs * ma.SR / 1000);

// A passive widget with this exact symbol is what the build turns into the
// plugin's reported latency (see the latency_samples cases in
// src/templates/dsp.cpp.in), so the host delay-compensates Lookahead. There
// must be exactly one of it, which is why it hangs off the detector below
// rather than off either channel's delay line.
latencyMeter = uiCorrection(hbargraph("[4]latency_samples[symbol:latency_samples][label:Latency]",
                                   0, maxLookaheadSamples));

// Target curve, one slider per band.
targetSlider(i) = uiTarget(vslider("[%2i]Band %2i[unit:dB][symbol:target_%{i}]
      [label:%{i}]
      [tooltip: Wanted level of this band relative to the overall balance]",
                                   0, -18, 18, 0.1));

//----------------------------------------------------------------- balancer
balancer(l, r) = (l : lookahead : correction), (r : lookahead : correction)
with {
    // Fully linked: one detector, one set of gains, both channels. The two
    // `correction` instances are structurally identical, so Faust shares the
    // whole analysis between them - it is built once, not once per channel.
    m          = attach(detector(l, r), lookaheadSamples : latencyMeter);
    correction = (gains, _) : bells;

    //---------------------------------------------------------- measurement
    // The detector taps the input ahead of the delay: that gap is the lookahead.
    detector(a, b) = 0.5*(a + b);
    lookahead      = de.delay(maxLookaheadSamples, lookaheadSamples);

    // Mean-square envelope with independent attack/release. It stays in the
    // power domain: the curve only ever uses ratios of these, and 10*log10 of
    // a power ratio is the same dB as 20*log10 of an amplitude ratio, so the
    // square root would only be undone again.
    envPow(att, rel) = _ <: * : loop ~ _
    with {
        loop(y, x) = x*(1.0 - p) + p*y
        with { p = pole(select2(x > y, rel, att)); };
    };
    powDb = max(ma.MIN) : log10 : *(10.0);

    bandpass(i) = fi.svf.bp(fc(i), qAnalysis) : /(qAnalysis);  // unity at centre

    // Band Speed tilts the measurement windows along with the correction: a
    // 30 Hz band cannot be measured through a 20 ms window - that is shorter
    // than one cycle - while the top of the spectrum has nothing to gain from
    // waiting.
    //
    // Which is why each band is normalised against a fullrange envelope built
    // with that band's own time constants, rather than against one shared
    // broadband reading. Compare a fast detector with a slow one and every
    // change in level tilts the curve while the two catch up - and when the
    // programme stops, the two free-fall at different rates and the curve
    // drifts tens of dB out of a decaying tail. Like against like, a decay
    // cancels exactly: both envelopes fall together and the ratio holds still.
    //
    // The plain fullrange envelope stays too, but only as the level watchdog
    // for the Threshold gate, which must keep reading while everything else
    // is frozen.
    fullDb = m : envPow(envAttack, envRelease) : powDb;

    bandPow(i)    = m : bandpass(i) : envPow(envAtt(i), envRel(i));
    refPow(i) = m : envPow(envAtt(i), envRel(i));
    envAtt(i)    = envAttack*speedOf(i);
    envRel(i)    = envRelease*speedOf(i);

    //---------------------------------------------------------- the curve
    // Level-normalised spectrum: each band relative to the fullrange level -
    // but only measured while there is programme to measure.
    //
    // On top of the matched references, the curve only updates while the level
    // gate is wide open. Under the threshold there is nothing left to measure
    // but the noise floor, so a pause holds the last confident reading and
    // playback resumes with the correction where it left off, rather than
    // re-learning it from whatever was decaying at the time.
    analysing  = gateRaw >= 1.0;
    specRaw(i) = 10.0*log10(max(ma.MIN, bandPow(i)) / max(ma.MIN, refPow(i)))
               + warpDb(i) + weightDb(i)
               : ba.sAndH(analysing);

    // Plain mean of the raw curve. It is the reference for "does this band
    // still carry programme", and it is deliberately unweighted: the gate must
    // not chase its own output. Note that normalising against fullDb cancels
    // here, so the gate reads pure spectral shape - no calibration constant.
    // From here the band values travel as a bus and every cross-band quantity
    // is a route over it. Written the obvious way - each band reaching for the
    // mean, the mean reaching for every band, all of it inside three more sums
    // - the compiler expands that measurement chain some three thousand times
    // and the build takes seven seconds instead of one. Same generated code.
    curveBus = par(i, Nbands, specRaw(i));

    // Lay a copy of one scalar beside every signal on an n-bus.
    withScalar(n) = route(n + 1, 2*n, (par(i, n, (i + 1, 2*i + 1)),
                                       par(i, n, (n + 1, 2*i + 2))));

    // Interleave two n-buses into n pairs.
    pairUp(n) = route(2*n, 2*n, par(i, n, ((i + 1, 2*i + 1), (n + i + 1, 2*i + 2))));

    // Global gate on the fullrange level. It multiplies the gains *after* the
    // ballistics, not the deviation before them: inside the smoother the gate
    // could only take effect as fast as Release let it, which meant the
    // correction carried on for seconds after the signal had dropped below the
    // threshold - a threshold that visibly did nothing. Out here it means what
    // it says. si.smoo keeps the transition itself from stepping.
    gateRaw   = (fullDb - threshold) / gateKnee : clamp01;
    levelGate = gateRaw : si.smoo;

    // Target curve: sliders plus the global tilt, in dB/octave around fRef.
    targetRaw(i) = targetSlider(i) + tilt*log(fc(i)/fRef)/log(2.0);

    // curve bus -> weight bus. 1 while the band sits within bandRange of the
    // average band, fading out below that: bands that fall out hold no
    // programme, so they are neither corrected nor counted in the mean. The
    // mean it is measured against is the plain one, deliberately unweighted -
    // the gate must not chase its own output. Normalising against the
    // fullrange level cancels here, so this reads pure spectral shape.
    weights = si.bus(Nbands) <: (si.bus(Nbands), (si.bus(Nbands) :> _ : /(Nbands)))
            : withScalar(Nbands)
            : par(i, Nbands, weightOf)
    with {
        weightOf(c, mean) = (c - mean + bandRange) / gateKnee : clamp01;
    };

    // (curve bus, weight bus) -> the two cross-band scalars the bands need:
    // the weighted mean of the deviation, which is taken out of every band so
    // the bells can never add up to a plain gain change, and the weighted mean
    // of the curve, which is what the spectrum meters are drawn against.
    stats = si.bus(2*Nbands) : pairUp(Nbands) <: (wSum, cSum, tSum) <: (devMean, specWMean)
    with {
        wSum = par(i, Nbands, (!, _))                              :> _ : max(ma.EPSILON);
        cSum = par(i, Nbands, *)                                   :> _;
        tSum = par(i, Nbands, ((!, _) : *(targetRaw(i))))          :> _;
        devMean(w, c, t)   = (t - c) / w;
        specWMean(w, c, t) = c / w;
    };

    // (curve bus, weight bus) -> want bus: the correction curve we want the
    // bank to produce, band by band.
    toWant = si.bus(2*Nbands) <: (si.bus(2*Nbands), stats) : spread : par(i, Nbands, wantOf(i))
    with {
        spread = route(2*Nbands + 2, 4*Nbands,
                   par(i, Nbands, ((i + 1,          4*i + 1),
                                   (Nbands + i + 1, 4*i + 2),
                                   (2*Nbands + 1,   4*i + 3),
                                   (2*Nbands + 2,   4*i + 4))));

        wantOf(i, c, w, dMean, sMean) = ((targetRaw(i) - c) - dMean)
                                      : deadband(tolerance)
                                      : *(strength)
                                      : clip(range)
                                      : *(w)
                                      : specMeter(i, c - sMean);
    };

    // The bell gains that produce it, once the overlap between neighbouring
    // bells is taken out (see kern).
    gains = curveBus <: (si.bus(Nbands), weights)
          : toWant
          : deconvolve
          : par(i, Nbands, ballistics(attack*speedOf(i), release*speedOf(i))
                          : *(levelGate) : gainMeter(i));

    // Fan each band out to the taps that need it, then sum each band's taps.
    deconvolve = route(Nbands, Nbands*taps,
                   par(i, Nbands, par(k, taps, (bandIdx(i + k - kTaps) + 1, i*taps + k + 1))))
               : par(i, Nbands, par(k, taps, *(kern(abs(k - kTaps)))) :> _)
    with { taps = 2*kTaps + 1; };

    // Nbands gains and the audio in, one channel of corrected audio out. The
    // gains arrive as a bus, so the cascade is peeled from the top band down,
    // each stage taking the gain sitting next to the signal.
    bells = bc(Nbands)
    with {
        bc(0) = _;
        bc(n) = (si.bus(n - 1), bellAt(n - 1)) : bc(n - 1);
    };
    bellAt(i, g, x) = x : bell(fc(i), qBellOf(i), g);

    // fi.svf.bell, transcribed with two changes: the dB gain is taken to linear
    // with an exp rather than a pow (10^(g/40) = e^(g*ln10/40)), and the tick's
    // divisor is formed once as a reciprocal. Both channels are handed the same
    // gain, so all of this coefficient work is shared between them - 32 of each
    // per sample rather than 64. Verified against fi.svf.bell to 1e-15.
    bell(f, q, gDb) = tick ~ (_,_) : !,!,si.dot(3, mix)
    with {
        a   = exp(gDb*(log(10.0)/40.0));
        g   = tan(ma.PI*f/ma.SR);        // f is constant, so this is init-time
        k   = 1.0/(q*a);
        d   = 1.0/(1.0 + g*(g + k));
        mix = 1.0, k*(a*a - 1.0), 0.0;
        tick(ic1eq, ic2eq, v0) = 2.0*v1 - ic1eq, 2.0*v2 - ic2eq, v0, v1, v2
        with {
            v1 = (ic1eq + g*(v0 - ic2eq))*d;
            v2 = ic2eq + g*v1;
        };
    };

    //---------------------------------------------------------- meters
    // The level-normalised spectrum, mean removed: what the balancer sees.
    specMeter(i, v, x) = attach(x, v
        : uiSpectrum(vbargraph("[%2i]Spectrum %2i[unit:dB][symbol:spec_%{i}][label:%{i}]", -30, 30)));

    // The gain this band's bell is applying right now.
    gainMeter(i) = _ <: attach(_, uiGain(vbargraph("[%2i]Gain %2i[unit:dB][symbol:gain_%{i}][label:%{i}]", -6, 6)));

    //---------------------------------------------------------- helpers
    clamp01      = max(0.0) : min(1.0);
    clip(lim)    = max(0.0 - lim) : min(lim);
    deadband(t, x) = ma.signum(x) * max(0.0, abs(x) - t);

    // One-pole on the dB gain, faster while the correction grows away from
    // flat (attack) than while it falls back towards it (release).
    ballistics(att, rel) = loop ~ _
    with {
        loop(prev, x) = prev*p + x*(1.0 - p)
        with { p = pole(select2(abs(x) > abs(prev), rel, att)); };
    };
};
