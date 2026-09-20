// -*-Faust-*-

// For some parts of this file, a large language model was involved as a coding assistant.
// The ideas, the design decisions and the listening behind it are purely human.

declare author "Klaus Scheuermann";
declare description "Lookahead brickwall limiter for mastering";
declare license "GPL-3.0-or-later";
declare name "Limiter";
declare unique_id "LAli";



import("stdfaust.lib");


Nch = 2;

//======================= GUI =======================

lim_group(x)   = vgroup("Limiter", x);
meter_group(x) = lim_group(vgroup("[1]Meters", x));
knob_group(x)  = lim_group(hgroup("[0]Controls", x));

gain_group(x)  = knob_group(hgroup("[0]Level", x));
time_group(x)  = knob_group(hgroup("[1]Timing", x));
out_group(x)   = knob_group(hgroup("[2]Dither", x));


threshold = gain_group(vslider("[0]Threshold[unit:dB][symbol:threshold][accentcolor:01][easy]
      [tooltip: Where limiting starts. Peaks above this are held down to the
       Ceiling, and everything below is lifted by the gap between the two, so
       lowering it makes the master louder. Read as true peak unless True Peak
       is off. Set it to the Ceiling to limit only what is already over]",
                               -1, -24, 0, 0.1));

ceiling = gain_group(vslider("[1]Ceiling[unit:dB][symbol:ceiling][accentcolor:06][bracket:CEILING]
      [tooltip: The level the output is held under. With True Peak on that
       includes the peaks a DAC reconstructs between the samples; with it off,
       only the samples themselves]",
                             -1, -24, 0, 0.1));

tpOn = gain_group(nentry("[2]True Peak[symbol:true_peak][accentcolor:06][bracket:CEILING]
      [style:radio{'Off':0;'On':1}]
      [tooltip: Limits the waveform between the samples too, not just the
       samples, so the Ceiling still holds after digital-to-analogue
       conversion or sample rate conversion. Costs a little more reduction
       on bright material. Latency is the same either way]",
                         1, 0, 1, 1));

unityGain = gain_group(checkbox("[3]Unity Gain[symbol:unity_gain][accentcolor:04]
      [tooltip: Takes the make-up gain back off at the output, so switching the
       limiter in and out compares its effect at matched level instead of
       rewarding the louder side]"));

lookaheadMs = time_group(vslider("[0]Lookahead[unit:ms][symbol:lookahead][accentcolor:03][bracket:ENVELOPE]
      [tooltip: How far ahead the limiter sees, and so how long it takes to
       reach full reduction. Longer is smoother and cleaner on low end, shorter
       keeps more punch. Reported to the host as latency]",
                                 2, 0.1, 5, 0.1));

releaseMs = time_group(vslider("[1]Release[unit:ms][scale:log][symbol:release][accentcolor:03][bracket:ENVELOPE]
      [tooltip: How quickly the gain recovers once the peaks have passed. With
       Auto Release on this is the recovery under sustained limiting, and short
       peaks let go several times faster]",
                               50, 1, 200, 1));

autoOn = time_group(nentry("[2]Auto Release[symbol:auto_release][accentcolor:03][bracket:ENVELOPE]
      [style:radio{'Off':0;'On':1}]
      [tooltip: Program dependent release. Isolated peaks recover quickly, dense
       passages recover at the Release time, so the limiter neither leaves
       holes after transients nor pumps on sustained material]",
                           1, 0, 1, 1));

ditherMode = out_group(nentry("[0]Dither[symbol:dither][accentcolor:02][bracket:DITHER]
      [style:menu{'Off':0;'16 bit':1;'24 bit':2}]
      [tooltip: Adds TPDF dither and rounds to the chosen word length. Use it
       only on the last plugin before the file is written at that word length,
       with the Output trim at 0 dB and Mid / Side off -- anything that touches
       the level afterwards undoes it]",
                             0, 0, 2, 1)) : int;

shapeMode = out_group(nentry("[1]Noise Shaping[symbol:noise_shaping][accentcolor:02][bracket:DITHER]
      [style:radio{'Off':0;'Simple':1;'Weighted':2}]
      [tooltip: Moves the dither noise away from where hearing is most sensitive.
       Simple tilts it towards the top octave at any sample rate. Weighted
       follows the ear's sensitivity curve and is designed for 44.1 and 48 kHz]",
                            0, 0, 2, 1)) : int;

//======================= meters =======================

MAXGR = 24;                 // meter top, dB of gain reduction
grRel = ba.tau2pole(0.02);

// Peak-hold with exponential decay: the UI reads the parameter once per block,
// so an instantaneous gain would show whichever sample the block happened to
// end on rather than what the limiter actually did.
grHold = max ~ *(grRel);

grMeter = _ <: attach(_, 0 - _ : grHold
        : ma.neg : meter_group(hbargraph("[0]gr[unit:dB][symbol:gr][label:Reduction]",
                                0 - MAXGR, 0)));

// BS.1770-4 short-term loudness of the output
//
// It reads the plugin's own output, upstream of the wrapper's Output trim. To be fixed!
METERMIN = -60;
LUFSWIN  = 3.0;        // s, the BS.1770 short-term window

meter_lufs_out = meter_group(hbargraph("[2]lufs_out[unit:dB][symbol:lufs_out]
      [label:LUFS-S]", METERMIN, 0));

lufsMeter(l, r) = attach(l, lvl), r
with {
    sq(x)   = x * x;
    kf      = fi.itu_r_bs_1770_4_kfilter;
    power   = sq(l : kf) + sq(r : kf);
    lufs(p) = 10.0 * log10(max(1e-12, p));
    lvl     = power : si.smooth(ba.tau2pole(LUFSWIN * 0.5))
            : lufs : meter_lufs_out;
};


// Latency
latency_meter = attach(_, LATENCY :
    meter_group(hbargraph("[1]latency_samples[symbol:latency_samples][label:Latency]",
                          0, MAXLA)));

//======================= true peak detector =======================
//
// Only the detector is oversampled. The audio never is -- the gain is worked
// out from the reconstructed waveform and applied to the plain samples, so
// the signal itself goes through nothing but the delay and the gain.
//
// The interpolator is a 4x Kaiser polyphase, coefficients below: 64 taps per
// phase, flat to 0.472 fs, 32 samples of group delay. The audio waits those 32
// on top of the lookahead. The sample-peak path taps the same delayed input,
// so latency does not change with the switch and flipping it does not click.


OSDELAY = 32;       // the interpolator's group delay, host samples
TPL     = 4;        // oversampling factor

// One channel's L-phase polyphase interpolation, as in clipper.dsp: phase 0
// is the input itself, delayed to match, and phase p the point p/L of the way
// to the next sample. So each host sample carries one inter-sample slot.
// Its L points go out with one neighbour either side -- the previous slot's
// last phase and the next sample -- so each can see whether it is a peak.
tpPoints(L) = _ <: (fi.fir(hp(L, L - 1)) : mem), @(OSDELAY),
                   par(p, L - 1, fi.fir(hp(L, p + 1))), @(OSDELAY - 1);

// Vertex of the parabola through three evenly spaced points, where the middle
// one is a local maximum; anything else passes the middle point through.
parab(a, b, c) = select2((b >= a) & (b >= c) & (den < 0),
                         b, b - (a - c) * (a - c) / (8 * den))
with { den = a - 2 * b + c; };

slotPeak(L) = tpPoints(L) : par(i, L + 2, abs)
            <: par(k, L, (ba.selector(k, L + 2), ba.selector(k + 1, L + 2),
                          ba.selector(k + 2, L + 2)) : parab)
            : ba.parallelMax(L);

detector(l, r) = select2(tpOn > 0.5, sp, tp)
with {
    sp = max(abs(l @ OSDELAY), abs(r @ OSDELAY));
    tp = max(slotPeak(TPL, l), slotPeak(TPL, r));
};

//======================= limiter =======================
//
// The gain the Ceiling calls for is worked out per sample, in dB, from the
// louder of the two channels -- one gain for the pair, so limiting never
// moves the image. It is held by a sliding minimum over LA + 1 samples,
// released, then smoothed by two moving averages whose spans add up to the
// same LA + 1. The audio is delayed by LA, on top of the OSDELAY the detector
// already runs behind it.
//
// That arrangement is what makes the Ceiling exact rather than close -- exact
// for whatever the detector reports, which is every sample with True Peak off
// and the interpolated waveform with it on (see above for how close that is
// to what a DAC reconstructs). The
// sample that needs gain r when the detector sees it at t leaves the delay at
// t + LA, and the smoothed gain at that moment is an average of held values
// from t to t + LA. Every one of those windows contained t, so every one is at
// most r, and an average of values that are all at most r is at most r. So no
// sample overshoots, for any signal and any Lookahead, and there is no clamp
// behind it adding distortion of its own. Release only ever pulls the held
// gain further down, so it cannot break this.
//
// Measured: noise, random impulses, a 20 Hz - 20 kHz sweep and 3 kHz tone
// bursts, all with 18 dB of make-up, at Lookahead 0.1, 2 and 5 ms, Auto
// Release and True Peak each on and off, at 44.1, 48, 96 and 192 kHz. The
// worst sample out of all of them is within 0.00001 dB of the Ceiling, from
// the first sample after the plugin starts.
//
// Two boxes rather than one turn the attack from a straight ramp, which has a
// corner at each end, into a piecewise-parabolic S with none. Averaging in dB
// means the ramp is even in dB, as heard, rather than in amplitude.

MAXLA = 1024;               // samples; 5 ms at 192 kHz is 960, plus OSDELAY
MAXBOX = MAXLA / 2 + 1;     // longest of the two smoothing boxes, see below
EPS = 0.000001;

LA = int(lookaheadMs * ma.SR / 1000 + 0.5) : max(1) : min(MAXLA - 1 - OSDELAY);

// The audio waits for the detector's interpolator as well as the lookahead.
LATENCY = LA + OSDELAY;

// Smoothed in dB, then converted. The other way round, si.smoo settles a hair
// short of 1 in single precision and the limiter would never be an exact
// pass-through; this way 0 dB stays exactly 0 and converts to exactly 1. With
// the Threshold on the Ceiling the difference is exactly zero whatever they
// are set to, so anything under the Ceiling comes out bit-identical, only
// delayed.
//
// Unity Gain takes off the same smoothed make-up, delayed to meet the audio it
// was applied to. Undelayed, the two disagree for as long as it is moving:
// a 12 dB jump at Lookahead 5 ms put an error only 16.4 dB under the
// signal's peak on the output. Delayed, what is left is float rounding, 142 dB
// under. A level-matched comparison should not depend on holding still.
//
// Neither may glide in from 0 when the plugin starts, though, which si.smoo
// does: its state starts at 0 on every activation. For the make-up that fades
// the first 100 ms of a bounce in from unity; for the Ceiling it was worse --
// the limiter faithfully followed a ceiling still on its way down from 0 dB,
// and a loud first bar came out up to 0.9 dB over it. So smooI below starts
// on its target and only smooths what changes after that, and the Ceiling is
// not smoothed at all: it only ever reaches the audio through the held gain,
// so a step in it is already ramped by the lookahead on the way down and by
// the release on the way up.
smooI(x) = loop ~ _
with {
    p        = 1 - 44.1 / ma.SR;     // si.smoo's pole
    first    = 1 - 1';
    loop(y1) = select2(first, y1 * p + x * (1 - p), x);
};

makeupDb = ceiling - threshold : smooI;
preGain  = makeupDb : ba.db2linear;
ceilDb   = ceiling;
postGain = 0 - de.delay(MAXLA, LATENCY, makeupDb) * (unityGain : smooI) : ba.db2linear;

//---- release ----
//
// Runs on the held gain, in dB, between the sliding minimum and the smoothing
// boxes. Attack is instant here -- the boxes and the lookahead are the attack
// -- and release is a one-pole towards whatever the held gain wants now. The
// output never sits above its input, so the no-overshoot argument above
// survives it untouched.
//
// Auto Release shortens the time constant by up to FASTDIV, and there are two
// separate reasons to:
//
//   density   Limiting has been rare lately, i.e. these are isolated peaks. A
//             one-pole tracking how often the limiter is engaged at all, over
//             DENST, scaled so that DREF of the time counts as dense.
//   depth     The gain is well below its own sustained level, i.e. a transient
//             has dug a hole into a passage that was already being limited.
//             Fades in from M0 to M0 + MDB below a slow average of the gain.
//
// Whichever asks for more speed wins. The two exist because each fails where
// the other works: density alone recovers isolated peaks as fast as the short
// release does but is no help once the whole passage is being limited, and
// depth alone fills those holes but leaves isolated peaks recovering at the
// slow rate for the last dB or so.
//
// Density is counted in time rather than in dB of reduction on purpose. The
// obvious measure -- average reduction, as the compressor's Auto Release uses
// -- reads 1-2 dB of limiting on a bass line as "not much", releases fast, and
// modulates the bass: 40 Hz at 2 dB of reduction, Release 100, measured 5 dB
// worse distortion than Auto off. Engaged-time reads that same bass as fully
// dense (every cycle trips the limiter), so it gets the slow release.
//
// The dead zone M0 is what keeps depth from doing the same thing. A sustained
// low note makes the gain ripple around its own average at the rate of the
// note. A first version switched to the fast rate anywhere below the average,
// so every trough counted as a hole and was released fast: 40 Hz at Release
// 200 came out 6 dB dirtier than Auto off. The ripple under any Release
// setting worth using stays inside half a dB, so past M0 it is not ripple.
//
// Measured, 48 kHz, Lookahead 2 ms, True Peak on. Bass THD is a sine held 2
// and 7 dB into the ceiling. Recovery is from a 3 ms burst taking 10 dB, on
// silence, to within 1 dB. Hole is the extra reduction a 60 Hz line (3 dB in)
// suffers after a burst taking about 13 dB every 400 ms, integrated, in dB*ms:
//
//                     THD 40Hz   THD 40Hz  THD 100Hz  recovery    hole
//                       2 dB       7 dB      7 dB      to 1 dB
//   Release 100, off   -44.0      -40.1     -61.1      237 ms     760
//   Release 12.5, off  -29.5      -26.1     -44.9       33 ms     130
//   Release 100, auto  -44.0      -40.1     -61.1       34 ms     154
//
// i.e. the distortion of the slow release and the recovery of the fast one.
// The same holds at Release 30 and 200.
FASTDIV = 8;        // most the release is ever shortened by
M0      = 0.5;      // dB below the sustained level before depth acts
MDB     = 1;        // ... and over how many further dB it fades in
AVGMUL  = 2;        // sustained level = average gain over Release * AVGMUL
DENST   = 0.5;      // s, how far back density looks
DREF    = 0.1;      // engaged this fraction of the time = dense

avgP  = ba.tau2pole(releaseMs / 1000 * AVGMUL);
densP = ba.tau2pole(DENST);

// f  the released gain, dB             s  its slow average, dB
// a  fraction of time engaged          h  the held gain coming in
releaseStep(f1, s1, a1, h) = f, s, a
with {
    wDepth = max(0, min(1, (s1 - f1 - M0) / MDB));
    wDens  = 1 - min(1, a1 / DREF);
    w      = max(wDepth, wDens) * (autoOn > 0.5);
    tau    = releaseMs / 1000 / (1 + (FASTDIV - 1) * w);
    p      = exp(0 - 1 / (tau * ma.SR));
    f      = select2(h < f1, f1 + (h - f1) * (1 - p), h);
    s      = s1 + (f - s1) * (1 - avgP);
    a      = a1 + ((h < 0) - a1) * (1 - densP);
};

releaseStage = releaseStep ~ (_, _, _) : (_, !, !);

// The two boxes are one sample longer between them than the lookahead, so the
// span they average over is exactly the held window.
B1 = int(LA / 2) + 1;
B2 = LA - int(LA / 2) + 1 : max(1) : min(MAXBOX);
box(n) = ba.slidingSump(float(n), MAXBOX) / n;

limiter(l, r) = (l : delayA) * g, (r : delayA) * g
with {
    delayA = de.delay(MAXLA, LATENCY);
    peak   = detector(l, r);
    reqDb  = min(0, ceilDb - ba.linear2db(max(EPS, peak)));
    gDb    = reqDb
           : ba.slidingMin(float(LA + 1), MAXLA)
           : releaseStage
           : box(B1) : box(B2)
           : grMeter;
    g      = ba.db2linear(gDb);
};

//======================= dither =======================
//
// TPDF dither, +/-1 LSB: two independent uniform noises of +/-0.5 LSB summed,
// fresh per channel. Then rounding to the word length, with the rounding
// error fed back through a filter so the noise lands where hearing is least
// sensitive. Writing v for what reaches the quantiser, y for what leaves it
// and e = y - v, the loop computes v = x - H.e, so y = x + (1 - H).e: the
// signal passes unchanged and the noise is shaped by 1 - H.
//
// Simple  H = z^-1. First-order highpass on the noise: -17 dB at 1 kHz, +6 dB
//         at Nyquist, +3 dB of total power, and the same shape at every rate.
// Weighted  The 5-tap E-weighted filter of Lipshitz, Vanderkooy and
//         Wannamaker ("Minimally audible noise shaping", JAES 1991), designed
//         at 44.1 kHz. Measured there: -16 dB up to 2 kHz, -27 dB at 4 kHz where
//         hearing is most acute, a second notch at 12 kHz, +19 dB at 20 kHz, and
//         +12 dB total power -- more noise overall, less of it audible.
//
// The loop cannot run away: e is bounded by the quantiser whatever the filter
// does, at most 1.5 LSB, so the most the Weighted feedback can add to a sample
// is 12.5 LSB. At 16 bit that is 0.003 dB, and matters only with the Ceiling
// at 0 dB, where it can round a peak up onto full scale.
//
// The rounding is done in two parts on purpose. At 24 bit an LSB is 2^-23, and
// a float near full scale resolves only 2^-24, so the obvious
// floor(v * q + d + 0.5) would round the dither itself to half an LSB before
// it could do its job. Splitting v * q into its integer part and its fraction,
// both exact, and adding the dither to the fraction alone keeps all of it.

NSWEIGHTED = (2.033, -2.165, 1.959, -1.590, 0.6149);

ditherQ = select2(ditherMode == 2, 32768.0, 8388608.0);   // 16 / 24 bit

tpdf(i) = (no.noises(2 * Nch, 2 * i) + no.noises(2 * Nch, 2 * i + 1)) * 0.5;

roundQ(v, d) = (vi + floor(fr + d + 0.5)) / ditherQ
with {
    vq = v * ditherQ;
    vi = floor(vq);
    fr = vq - vi;
};

// its input is already e[n-1]: the ~ below supplies the one-sample delay
nsFilter = _ <: (0, _, fi.fir(NSWEIGHTED)) : ba.selectn(3, shapeMode);

nsStep(efb, x, d) = e, y
with {
    v = x - efb;
    y = roundQ(v, d);
    e = y - v;
};

dither(i) = _ <: (_, ((_, tpdf(i)) : nsStep ~ nsFilter : (!, _)))
          : select2(ditherMode > 0);

//======================= process =======================

process = par(i, Nch, *(preGain))
        : limiter
        : par(i, Nch, *(postGain))
        : par(i, Nch, dither(i))
        : lufsMeter
        : (latency_meter, _);

//======================= polyphase coefficients =======================
// Generated: Kaiser lowpass, beta 5.65, cutoff at the host Nyquist,
// N = 64*4+1 taps split into 4 phases each normalised to unity DC gain.
// Phase 0 is the pure delay handled by @(OSDELAY) above and is not listed;
// phase 3 is phase 1 reversed. See the true peak detector section for why
// this is 64 taps per phase and not clipper.dsp's 40.
hp(4, 1) = (
      -1.63556133295e-04,  2.56178683205e-04, -3.73467018073e-04,  5.19113564668e-04,
      -6.97100485803e-04,  9.11717610327e-04, -1.16758858188e-03,  1.46970848752e-03,
      -1.82349723809e-03,  2.23487435845e-03, -2.71036278253e-03,  3.25723200424e-03,
      -3.88369492870e-03,  4.59917866407e-03, -5.41469836956e-03,  6.34337691454e-03,
      -7.40117453864e-03,  8.60792722531e-03, -9.98884963827e-03,  1.15767559644e-02,
      -1.34154242142e-02,  1.55648459602e-02, -1.81097120670e-02,  2.11737195840e-02,
      -2.49449534121e-02,  2.97238228345e-02, -3.60210053958e-02,  4.47790866324e-02,
      -5.79487868245e-02,  8.03223502786e-02, -1.27652733956e-01,  2.99726029893e-01,
       9.00303363155e-01, -1.79386205764e-01,  9.87892015977e-02, -6.74550295790e-02,
       5.06187456063e-02, -4.00053960476e-02,  3.26378879326e-02, -2.71831462786e-02,
       2.29555902544e-02, -1.95669868956e-02,  1.67812565185e-02, -1.44467070102e-02,
       1.24614545141e-02, -1.07545005388e-02,  9.27477691852e-03, -7.98450336487e-03,
       6.85500178911e-03, -5.86397213052e-03,  4.99367057095e-03, -4.22966321684e-03,
       3.55995730850e-03, -2.97438635101e-03,  2.46416981445e-03, -2.02159516653e-03,
       1.63978704952e-03, -1.31253938611e-03,  1.03419341454e-03, -7.99549494422e-04,
       6.03803834294e-04, -4.42503597221e-04,  3.11515475709e-04, -2.07004008000e-04);
hp(4, 2) = (
      -2.61065869006e-04,  4.00314817053e-04, -5.75716656635e-04,  7.92594129730e-04,
      -1.05668521009e-03,  1.37417099829e-03, -1.75171628183e-03,  2.19652769022e-03,
      -2.71643591891e-03,  3.32001062437e-03, -4.01671957867e-03,  4.81714794171e-03,
      -5.73329972343e-03,  6.77901272773e-03, -7.97053221750e-03,  9.32731009133e-03,
      -1.08731304323e-02,  1.26377175208e-02, -1.46590744835e-02,  1.69869591687e-02,
      -1.96881862910e-02,  2.28549695156e-02, -2.66185388802e-02,  3.11723726248e-02,
      -3.68140107009e-02,  4.40254538763e-02, -5.36412491359e-02,  6.72406526660e-02,
      -8.82120140723e-02,  1.25371586723e-01, -2.11057398337e-01,  6.36348972673e-01,
       6.36348972673e-01, -2.11057398337e-01,  1.25371586723e-01, -8.82120140723e-02,
       6.72406526660e-02, -5.36412491359e-02,  4.40254538763e-02, -3.68140107009e-02,
       3.11723726248e-02, -2.66185388802e-02,  2.28549695156e-02, -1.96881862910e-02,
       1.69869591687e-02, -1.46590744835e-02,  1.26377175208e-02, -1.08731304323e-02,
       9.32731009133e-03, -7.97053221750e-03,  6.77901272773e-03, -5.73329972343e-03,
       4.81714794171e-03, -4.01671957867e-03,  3.32001062437e-03, -2.71643591891e-03,
       2.19652769022e-03, -1.75171628183e-03,  1.37417099829e-03, -1.05668521009e-03,
       7.92594129730e-04, -5.75716656635e-04,  4.00314817053e-04, -2.61065869006e-04);
hp(4, 3) = (
      -2.07004008000e-04,  3.11515475709e-04, -4.42503597221e-04,  6.03803834294e-04,
      -7.99549494422e-04,  1.03419341454e-03, -1.31253938611e-03,  1.63978704952e-03,
      -2.02159516653e-03,  2.46416981445e-03, -2.97438635101e-03,  3.55995730850e-03,
      -4.22966321684e-03,  4.99367057095e-03, -5.86397213052e-03,  6.85500178911e-03,
      -7.98450336487e-03,  9.27477691852e-03, -1.07545005388e-02,  1.24614545141e-02,
      -1.44467070102e-02,  1.67812565185e-02, -1.95669868956e-02,  2.29555902544e-02,
      -2.71831462786e-02,  3.26378879326e-02, -4.00053960476e-02,  5.06187456063e-02,
      -6.74550295790e-02,  9.87892015977e-02, -1.79386205764e-01,  9.00303363155e-01,
       2.99726029893e-01, -1.27652733956e-01,  8.03223502786e-02, -5.79487868245e-02,
       4.47790866324e-02, -3.60210053958e-02,  2.97238228345e-02, -2.49449534121e-02,
       2.11737195840e-02, -1.81097120670e-02,  1.55648459602e-02, -1.34154242142e-02,
       1.15767559644e-02, -9.98884963827e-03,  8.60792722531e-03, -7.40117453864e-03,
       6.34337691454e-03, -5.41469836956e-03,  4.59917866407e-03, -3.88369492870e-03,
       3.25723200424e-03, -2.71036278253e-03,  2.23487435845e-03, -1.82349723809e-03,
       1.46970848752e-03, -1.16758858188e-03,  9.11717610327e-04, -6.97100485803e-04,
       5.19113564668e-04, -3.73467018073e-04,  2.56178683205e-04, -1.63556133295e-04);
