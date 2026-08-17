// -*-Faust-*-

declare author "Klaus Scheuermann";
declare description "Oversampled stereo clipper";
declare license "GPL-3.0-or-later";
declare name "Clipper";
declare unique_id "LAcl";

// Dry/wet is built here rather than taken from the wrapper, so the flag stays
// off — leaving it on would stack the wrapper's common "Dry / Wet" on top of
// this one and give the plugin two controls that do the same thing.
//
// The wrapper's version crossfades against the plugin input through the same
// buffer it uses for delay compensation, so it gets phase alignment for free.
// The control below has to earn that: the dry tap is delayed by LATENCY to
// meet the clipped path, which carries the oversampler's fixed 40 samples plus
// the guard's lookahead. Without it the blend would be a comb filter, which is
// the one thing a parallel clipper must not be. See dryWetMix and `process`.
// declare drywet "true";

import("stdfaust.lib");

// number of channels. The mid/side path below assumes exactly 2.
Nch = 2;

//======================= oversampling =======================
//
// Faust is single-rate, so the L-times oversampled signal is carried as L
// parallel streams that each tick once per host sample -- the polyphase
// decomposition of the interpolator, written out longhand:
//
//   up:    u_p[k] = sum_i h[iL+p] x[k-i]                          p = 0..L-1
//   down:  y[k]   = sum_i d[iL] v_0[k-i]
//                 + sum_{j=1..L-1} sum_i d[iL+L-j] v_j[k-i-1]     d = h/L
//
// Clipping is memoryless, so applying it to each stream independently is
// exactly equivalent to applying it to the interleaved L*fs waveform. (The
// tempting shortcut of nesting 2x stages -- oversampling the two streams of a
// 2x pair again -- is NOT equivalent: a single polyphase stream is not a
// band-limited signal in its own right, it is one phase of a faster one.)
//
// h is a Kaiser lowpass (beta 8.68) cut at the host Nyquist, sized N = 40L+1
// so every factor lands on ONE host-rate group delay of exactly 40 samples.
// That shared delay is what lets the factor be switched without the output
// jumping, and keeps the reported latency constant. Measured at 44.1 kHz:
// passband +/-0.0005 dB to 19 kHz, stopband -86 dB, round-trip delay exactly
// 40.0000 samples at every factor. Hard-clipping a 0.9 FS 6 kHz sine 10 dB
// into the ceiling leaves total aliasing 17.7 dB (off), 33.1 (2x), 48.0 (4x),
// 57.6 (8x) below the fundamental, summed over every folded harmonic out to
// the 399th. The metric has to run that far to converge: stopping at the 39th
// reports -116.6 dB for 8x, which is wrong by nearly 60 dB. The size of each
// step depends on the tone and how hard it is driven; what holds generally is
// the ordering. The Ceiling Guard costs 0.5 dB of this when the clipper is
// being driven hard and about 10 dB when it is barely clipping -- see guard.
//
// Cost note: all four factors really do run all the time (~1100 multiply-adds
// per channel per sample), because their FIRs carry state that has to be
// advanced every sample whether or not the menu is pointing at them. That is
// what buys click-free switching. If this ever needs to be cheaper, the
// standard move is a cascade of half-band stages with a proper cross-connected
// polyphase network between them, which shares work across the factors at
// roughly a third the multiplies -- and considerably more routing.
//
// Selecting between *memoryless* things is a different matter, and the reason
// ten clipping curves are affordable: Faust lowers ba.selectn to a nested C
// ternary, and a ternary short-circuits, so only the selected curve is
// evaluated. Measured, whole plugin, 44.1 kHz, every factor live:
//
//   Hard 3.02%   Quadratic 3.06   Sine 3.80   Arctan 4.19   Tanh 4.33
//   Error 3.60   Smoothstep 3.09   Smootherstep 3.15   Circle 3.11
//   Cubic 3.02
//
// -- i.e. the curve costs at most 1.3 points, not ten times anything. Note
// this makes benchmarks parameter-dependent: a default-parameter run measures
// Hard and tells you nothing about Tanh.

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

// L and R are upsampled independently, then the phases are re-paired so each
// (L_p, R_p) subsample pair reaches the linked clipper together.
lace(L)   = route(2 * L, 2 * L, par(p, L, (p + 1, 2 * p + 1, L + p + 1, 2 * p + 2)));
unlace(L) = route(2 * L, 2 * L, par(p, L, (2 * p + 1, p + 1, 2 * p + 2, L + p + 1)));

osClip(L) = (up(L), up(L))
          : lace(L)
          : par(p, L, clipPair)
          : unlace(L)
          : (down(L), down(L));

// The un-oversampled branch is padded to the same latency as the other three.
noClip = clipPair : par(i, Nch, @(OSTAPS));

// All four factors run; the menu picks one. Left candidates are gathered into
// slots 1..4 and right into 5..8 so one selectn can serve each channel.
clipSelect = _, _ <: (noClip, osClip(2), osClip(4), osClip(8))
           : route(8, 8, par(k, 4, (2 * k + 1, k + 1, 2 * k + 2, k + 5)))
           : (ba.selectn(4, osFactor), ba.selectn(4, osFactor));

//======================= clipping curves =======================
//
// Nine of the eleven sigmoids from LSP's dspu::sigmoid (lsp-dsp-units,
// misc/sigmoid.h, GPL/LGPL-3), plus this file's own Cubic. LSP's relative
// order is kept so the menu still reads like theirs, but two entries are gone
// and the indices therefore no longer line up with theirs.
//
// Dropped as duplicates. Distance below is the worst difference in odd
// harmonic level (H3..H15, floored at -80 dB, above which nothing here is
// audible) at matched gain reduction of 1, 3, 6 and 12 dB. Matched GR rather
// than matched drive, deliberately: how wide a curve's knee is relative to its
// saturation point is already what the Ceiling knob controls, so comparing at
// equal drive would only re-measure that.
//
//   Logistic      0.00 dB from Tanh. 1 - 2/(1+e^2x) IS tanh(x) rearranged; the
//                 two ports differed by 1.4e-6, all of it Tanh's +/-7 clamp.
//                 A duplicate menu entry rather than a curve.
//   Gudermannian  1.85 dB from Circle -- not tellable apart on a level-matched
//                 audition -- and the most expensive curve in the set, being a
//                 tanh and an atan where Circle is one sqrt (4.59% vs 3.11%).
//
// Of what is left nothing sits closer than 5.87 dB (Arctan to Circle) and the
// median nearest-neighbour distance is 17.6 dB.
//
// LSP's header states the contract: odd, f(0) = 0, f'(0) = 1, |f| <= 1. That
// third clause is what makes Drive and Ceiling mean the same thing from one
// curve to the next, so it is worth knowing that three of them miss it.
// Measured on a direct port of their C:
//
//                    f(1)   slope at 0   saturates
//   Hard            1.000     1.000      at x = 1
//   Quadratic       0.750     1.000      at x = 2
//   Sine            0.841     1.000      at x = pi/2
//   Arctan          0.639     1.000      asymptotic, 0.980 at x = 8
//   Tanh            0.762     1.000      asymptotic
//   Error           0.805     1.129      at x = 2.61
//   Smoothstep      0.884     1.061      at x = sqrt(2)
//   Smootherstep    0.855     1.058      at x = sqrt(pi)
//   Circle          0.707     1.000      asymptotic, 0.999 at x = 8
//   Cubic           0.852     1.000      at x = 1.5
//
// So Error runs +1.05 dB against the others at low level, Smoothstep +0.51 and
// Smootherstep +0.49. Left as LSP has them rather than normalised, because
// sounding like theirs is the point -- but written down so it is not a
// surprise when those three come up louder on a level-matched audition.
//
// One more, measured rather than assumed: Error is not quite an error
// function. Its Abramowitz-Stegun 7.1.26 approximation builds t from x but the
// exponential from nx = sqrt(pi)/2*x where the formula wants nx for both. That
// is worth up to 2.5e-2 against a true erf, and is where its 1.129 slope comes
// from. Ported as-is.

CUBLIM  = 1.5;                  // where the cubic goes tangent to +/-1
CUBK    = 4.0 / 27.0;           // makes it do so exactly
SQ1_2   = 0.707106781186548;    // 1/sqrt(2)      -- smoothstep input scale
INVSQPI = 0.564189583547756;    // 1/sqrt(pi)     -- smootherstep input scale
ERFN    = 0.886226925452758;    // sqrt(pi)/2     -- LSP's nx scale
ERFP    = 0.3275911;            // A&S 7.1.26 coefficients
ERFA1   = 0.254829592;
ERFA2   = 0 - 0.284496736;
ERFA3   = 1.421413741;
ERFA4   = 0 - 1.453152027;
ERFA5   = 1.061405429;

clamp1(x)  = max(0 - 1.0, min(1.0, x));

cHard(x)   = clamp1(x);

// LSP branches on the sign; folding |c| into one expression is the same curve
cQuad(x)   = c * (1.0 - 0.25 * abs(c)) with { c = max(0 - 2.0, min(2.0, x)); };

cSine(x)   = sin(max(0 - ma.PI / 2, min(ma.PI / 2, x)));

cAtan(x)   = (2.0 / ma.PI) * atan((ma.PI / 2) * x);

// LSP writes tanh out as (e^2x-1)/(e^2x+1); ma.tanh is the same function and
// better conditioned. The +/-7 clamp is theirs and is kept, so this tops out
// at 0.9999983 rather than 1. This also stands in for their Logistic.
cTanh(x)   = ma.tanh(max(0 - 7.0, min(7.0, x)));

cErf(x)    = sgn * (1.0 - t * ex * poly)
with {
    ax   = abs(x);
    sgn  = select2(x < 0.0, 1.0, 0 - 1.0);
    nx   = ax * ERFN;
    ex   = exp(0 - nx * nx);
    t    = 1.0 / (1.0 + ERFP * ax);
    poly = ERFA1 + t * (ERFA2 + t * (ERFA3 + t * (ERFA4 + t * ERFA5)));
};

cSmoo(x)   = 2.0 * s * s * (3.0 - 2.0 * s) - 1.0
with { t = clamp1(x * SQ1_2); s = 0.5 * (t + 1.0); };

cSmoor(x)  = 2.0 * s * s * s * (10.0 + s * (0 - 15.0 + 6.0 * s)) - 1.0
with { t = clamp1(x * INVSQPI); s = 0.5 * (t + 1.0); };

cCircle(x) = x / sqrt(1.0 + x * x);

// not LSP's -- a pure cubic below the knee, so it adds a 3rd harmonic and
// nothing else, which none of the eleven above do
cCubic(x)  = c - c * c * c * CUBK with { c = max(0 - CUBLIM, min(CUBLIM, x)); };

NCURVES = 10;

shape(x) = (cHard(x), cQuad(x), cSine(x), cAtan(x), cTanh(x),
            cErf(x), cSmoo(x), cSmoor(x), cCircle(x), cCubic(x))
         : ba.selectn(NCURVES, mode);

// Asymmetry moves the two thresholds apart -- +100% puts the positive one at
// 1.5 and the negative at 0.5. Scaling the input by the same factor the output
// is scaled back by keeps the curve's shape intact and only moves where it
// bends, and picking the factor from the sign first means shape() is still
// evaluated once. The even harmonics this produces come with a DC offset,
// which is what the DC filter downstream is for.
sPos = 1 + 0.5 * asym;
sNeg = 1 - 0.5 * asym;

shapeAsym(x) = sc * shape(x / sc) with { sc = select2(x < 0, sPos, sNeg); };

// Work in gain rather than in level, so the stereo link has something to link:
// a clipper's "gain reduction" is just shape(x)/x. The divisor is pushed off
// zero without changing sign, so the ratio is exact wherever it matters and
// tends to 1 at silence instead of dividing 0 by 0.
EPS = 0.000001;

gainOf(x) = shapeAsym(xg) / xg
with {
    xg = select2(x < 0, max(EPS, x), min(0 - EPS, x));
};

// Link pulls both channels toward the gain of whichever is clipping hardest,
// so at 100% the stereo image stays put instead of the louder side collapsing
// toward the centre. At 0% the two channels clip independently.
linkGains(l, r) = gl, gr
with {
    gl0 = gainOf(l);
    gr0 = gainOf(r);
    gm  = min(gl0, gr0);
    gl  = gl0 + link * (gm - gl0);
    gr  = gr0 + link * (gm - gr0);
};

clipPair = _, _ <: (_, _), linkGains
         : route(4, 4, 1,1, 3,2, 2,3, 4,4)
         : (*, *);

//======================= colour (pre/de-emphasis) =======================
//
// A tilt in front of the clipper and its inverse behind it. The signal comes
// out spectrally untouched, because the two cancel; what changes is which part
// of the spectrum was loud enough to reach the ceiling, and therefore what the
// clipper distorted.
//
// Worth being precise about the direction, because the obvious reading is
// backwards. Writing P for the tilt and C for the clipper, the chain computes
// P^-1(C(P.s)) = P^-1(P.s + d) = s + P^-1.d, where d is the distortion. So the
// signal is restored exactly and the DISTORTION is shaped by the inverse. Turn
// Colour up and the clipper is driven by the highs -- but the harmonics it
// makes then get the high cut applied on the way out. Bright trigger, darker
// artefacts. Down does the reverse: bass drives the clipping, and the grit
// that results lands in the mids and up.
//
// The inverse has to be exact or the "spectrally untouched" claim is a lie.
// It is not enough to negate a shelf's gain: fi.lowshelf(1,g,f) followed by
// fi.lowshelf(1,-g,f) leaves a residual only 8.5 dB below full scale at g = 6,
// because that design does not put the +g and -g corners in the same place.
// So the section is written out as an explicit first-order transfer function
// and the inverse is the same one with numerator and denominator swapped,
// which is exact by construction -- measured residual 1.7e-6 (-115 dB) at
// +/-24 dB of tilt, i.e. float rounding and nothing else.
//
// The zero sits at -(K-r)/(K+r), inside the unit circle for every K, r > 0, so
// the inverse is always stable. At Colour 0 the numerator and denominator are
// identical term for term, so both filters are bit-exact pass-throughs rather
// than merely close ones.
//
// Measured effect. Harmonics of a 1020 Hz tone, hard clip at 8x, Drive 12 into
// a -6 dB ceiling, in dB below the fundamental:
//
//   Colour     H3     H5     H7     H9    H11    H13
//    -12     -3.9   -8.1  -12.4  -17.1  -22.9  -31.6
//     -6     -6.9  -11.8  -15.9  -19.9  -24.3  -29.7
//      0     -9.8  -14.7  -18.3  -21.5  -24.6  -27.7
//     +6    -12.7  -17.8  -21.2  -24.0  -26.5  -28.8
//    +12    -15.8  -21.8  -25.4  -28.2  -30.6  -32.8
//
// -- a clean 12 dB swing on the third harmonic and a tilt across the whole
// series, in the direction the algebra above predicts rather than the one the
// name suggests.
//
// It is NOT free, though, and the two directions do not cost the same. The
// de-emphasis is the last thing to touch the signal before the guard, and
// wherever it boosts it can lift a peak that the clipper had just pinned to
// the ceiling. Negative Colour is the expensive one: it drives the clipper
// with bass, whose harmonics all land above the pivot, exactly where the
// inverse then boosts. Worst overshoot past the Ceiling, swept over tones from
// 60 Hz to 13 kHz at Drive 18:
//
//   Colour     -12    -9    -6    -3     0    +3    +6    +9   +12
//   guard off +15.5 +12.9 +10.0  +6.2  +3.2  +5.1  +7.6 +10.0 +12.4
//   guard on   +1.8  +1.3  +0.8  +0.4  +0.1  +0.2  +0.3  +0.2  +0.2
//
// The guard still takes the worst of it, but its residual grows with the
// correction it is asked to make -- a fixed time constant tuned for 2 dB of
// Gibbs overshoot cannot also swallow 15 dB. So at strong negative Colour the
// Ceiling wants a couple of dB more headroom than the number on the knob.

COLORFC = 630;                              // pivot, Hz -- tiltEQ's default
colorK  = tan(ma.PI * COLORFC / ma.SR);
colorR  = ba.db2linear(color) : si.smoo;    // Nyquist gain; DC gets 1/r

// LF -> 1/r, HF -> r, unity at COLORFC. Same convention as tiltEQ's Tilt, so
// the span end to end is twice the number on the knob.
colorPre  = fi.tf1((colorK + colorR) / d, (colorK - colorR) / d,
                   (colorK * colorR - 1) / d)
with { d = colorK * colorR + 1; };

colorPost = fi.tf1((colorK * colorR + 1) / d, (colorK * colorR - 1) / d,
                   (colorK - colorR) / d)
with { d = colorK + colorR; };

//======================= mid/side =======================
//
// Crossfaded rather than switched, so engaging it does not click. At msAmt = 0
// both are the identity; at 1 they are the usual M/S matrix and its inverse.
// Clipping in M/S clips the sum and the difference at the Ceiling rather than
// the channels, so a hard-panned peak reaches the output louder than the
// Ceiling suggests -- the Ceiling Guard below is what catches that.
// Note Link operates on whatever pair reaches the clipper, so with M/S engaged
// it ties mid and side together rather than left and right. That is usually
// not what you want from M/S clipping: back Link off when using it.
msAmt = msOn : si.smoo;

msEnc(l, r) = l + (0.5 * (l + r) - l) * msAmt,
              r + (0.5 * (l - r) - r) * msAmt;

msDec(m, s) = m + ((m + s) - m) * msAmt,
              s + ((m - s) - s) * msAmt;

//======================= GUI =======================

clip_group(x)   = vgroup("Clipper", x);
meter_group(x)  = clip_group(vgroup("[1]Meters", x));
knob_group(x)   = clip_group(hgroup("[0]Controls", x));

gain_group(x)   = knob_group(hgroup("[0]Gain", x));
shape_group(x)  = knob_group(hgroup("[1]Shape", x));
stereo_group(x) = knob_group(hgroup("[2]Stereo", x));
qual_group(x)   = knob_group(hgroup("[3]Quality", x));

drive = gain_group(vslider("[0]Drive[unit:dB][symbol:drive]
      [tooltip: Gain into the clipper. More drive = more clipping]",
                           0, 0, 24, 0.1));

ceiling = gain_group(vslider("[1]Ceiling[unit:dB][symbol:ceiling]
      [tooltip: Level the curve saturates at]",
                             -0.3, -24, 0, 0.1));

output = gain_group(vslider("[2]Output[unit:dB][symbol:output]
      [tooltip: Trim after the ceiling. Above 0 dB it will exceed the Ceiling]",
                            0, -24, 24, 0.1));

// Auto Gain backs the output off by exactly the Drive, which makes Drive +
// Auto Gain identical to lowering the Ceiling by the same amount: anything
// that stays below the clip point comes out bit-identical to the input, and
// only the peaks get shaved. Note this is deliberately NOT loudness matching
// -- a clipper's output gets denser as it clips, so holding the peak still
// means the loudness rises. With Auto Gain off, Drive raises both.
autoGain = gain_group(checkbox("[3]Auto Gain[symbol:auto_gain]
      [tooltip: Backs the output off by the Drive, so more Drive shaves more off the peaks without lifting the rest]"));

drywet = gain_group(vslider("[4]Dry / Wet[unit:%][symbol:drywet]
      [tooltip: Blend of the clipped signal against the untouched input, for
       parallel clipping. 100% = clipper only, 0% = bypassed. The dry side is
       delayed to match the oversampler, so the blend never combs. Note the
       Ceiling only bounds the wet path: blending dry back in puts the peaks
       back, which is what parallel clipping is for]",
                            100, 0, 100, 1)) / 100 : si.smoo;

// A menu rather than a radio: ten entries is too many to sit in a row.
// LSP's relative order, minus the two duplicates -- see the curves section.
mode = shape_group(nentry("[0]Mode[symbol:mode]
      [style:menu{'Hard':0;'Quadratic':1;'Sine':2;'Arctan':3;'Tanh':4;
                  'Error':5;'Smoothstep':6;'Smootherstep':7;'Circle':8;
                  'Cubic':9}]
      [tooltip: Clipping curve, from a brickwall to progressively rounder knees]",
                          0, 0, NCURVES - 1, 1)) : int;

color = shape_group(vslider("[1]Colour[unit:dB][symbol:colour]
      [tooltip: Tilts the spectrum into the clipper and untilts it after, so the
       tone is unchanged and only the distortion moves. Up = highs drive the
       clipping and the artefacts come out darker; down = bass drives it and the
       grit lands higher. Pivots at 630 Hz; the span end to end is twice this.
       Strong negative settings push peaks past the Ceiling, so leave a couple
       of dB more headroom there]",
                            0, -12, 12, 0.1));

asym = shape_group(vslider("[2]Asymmetry[unit:%][symbol:asymmetry]
      [tooltip: Splits the positive and negative thresholds apart, for even harmonics]",
                           0, -100, 100, 1)) / 100 : si.smoo;

// checkbox always initialises to 0, so the two defaults-on switches are radios.
dcOn = shape_group(nentry("[3]DC Filter[symbol:dc_filter]
      [style:radio{'Off':0;'On':1}]
      [tooltip: Removes the offset asymmetric clipping leaves behind]",
                          1, 0, 1, 1)) : si.smoo;

link = stereo_group(vslider("[0]Link[unit:%][symbol:link]
      [tooltip: 100% clips both channels by the same amount, holding the image]",
                            100, 0, 100, 1)) / 100 : si.smoo;

msOn = stereo_group(checkbox("[1]Mid / Side[symbol:mid_side]
      [tooltip: Clip mid and side instead of left and right]"));

// named osFactor, not os -- `os` is the oscillators library's prefix
osFactor = qual_group(nentry("[0]Oversampling[symbol:oversampling]
      [style:radio{'Off':0;'2x':1;'4x':2;'8x':3}]
      [tooltip: Suppresses the aliasing clipping generates. Latency is the same either way]",
                       2, 0, 3, 1)) : int;

safeOn = qual_group(nentry("[1]Ceiling Guard[symbol:ceiling_guard]
      [style:radio{'Off':0;'On':1}]
      [tooltip: Pulls back the overshoot that band-limited clipping leaves above
       the Ceiling, and the much larger one M/S decoding can leave. A smoothed
       gain rather than a clamp, so it adds almost no aliasing of its own, at
       the cost of 16 samples of lookahead and a close rather than absolute
       bound]",
                           1, 0, 1, 1)) : si.smoo;

//---- meters ----

MAXGR = 24;         // meter top, in dB of clipping
GRFLOOR = 0.0631;   // MAXGR as a gain, so the bar pins instead of running off
// Everything downstream of the clipper is aligned to this: the dry tap in
// dryWetMix, and the number handed to the host.
LATENCY    = OSTAPS + GUARDLA;
MAXLATENCY = 96;   // headroom; the wrapper asserts LATENCY < this

grRel = ba.tau2pole(0.3);

// Peak-hold with exponential decay: the UI reads the parameter once per block,
// so an instantaneous gain would show whichever sample the block happened to
// end on rather than what the clipper actually did.
grHold = max ~ *(grRel);

grBar(i) = 0 - ba.linear2db(max(GRFLOOR, _)) : grHold : gr_meter(i);

gr_meter(0) = meter_group(hbargraph("[0]gain 1[unit:dB][symbol:gain_1][label:Clip L]", 0, MAXGR));
gr_meter(1) = meter_group(hbargraph("[1]gain 2[unit:dB][symbol:gain_2][label:Clip R]", 0, MAXGR));

// Metering runs a 1x-rate shadow of the same gain computation, so it follows
// the curve, the asymmetry and the link exactly. What it cannot see are the
// intersample peaks the oversampled path catches, so at high drive on 4x/8x it
// reads slightly under what is really happening.
meterTap = _, _ <: (_, _), (linkGains : par(i, Nch, grBar(i)))
         : route(4, 4, 1,1, 3,2, 2,3, 4,4)
         : (attach, attach);

// Latency is the same for every oversampling factor by construction, so this
// is a constant -- it is here because config.h.in keys DISTRHO_PLUGIN_WANT_LATENCY
// off a passive widget with this symbol, and the wrapper needs the number to
// delay-compensate the dry path.
latency_meter = attach(_, LATENCY :
    meter_group(hbargraph("[2]latency_samples[symbol:latency_samples][label:Latency]",
                          0, MAXLATENCY)));

//======================= process =======================
//
// Drive and Ceiling are folded into one pre-gain so the curves can be written
// against a fixed +/-1 threshold; the Ceiling is put back on after clipping.
preGain  = ba.db2linear(drive - ceiling) : si.smoo;
ceilLin  = ba.db2linear(ceiling) : si.smoo;
postGain = ba.db2linear(output - drive * autoGain) : si.smoo;

dcStage = _ <: (_, fi.dcblockerat(20)) : si.interpolate(dcOn);

// Reconstruction after downsampling overshoots the clip level, and M/S
// decoding can overshoot it a lot; this is the last thing that bounds the wet
// path to the Ceiling. Output and Dry / Wet are both applied after it,
// deliberately: the Ceiling is where the curve saturates, not a guarantee
// about the plugin's final output.
//
// The overshoot is not an artefact to be cleaned up -- it is what band-limited
// clipping looks like. A signal whose flat top sits exactly on the ceiling and
// whose bandwidth stops at Nyquist MUST ring past it around the corners; this
// measures +1.1 dB at Drive 0 rising to +1.7 dB at Drive 24, close to the 9%
// Gibbs overshoot of a band-limited square.
//
// So this is a gain, not a clamp. A clamp was the obvious thing and it was
// measurably wrong: cutting the overshoot off leaves full-bandwidth corners,
// which is a second un-oversampled clip, and it pinned total aliasing at about
// -26 dB whatever the Oversampling menu said -- 8x bought 8 dB over no
// oversampling instead of 40. A gain that moves smoothly has no corners to
// splatter, so it composes with the oversampler instead of fighting it.
//
// The cost of that is an attack time, paid for with GUARDLA samples of
// lookahead: the sliding minimum starts pulling the gain down GUARDLA samples
// before the peak arrives, and the one-pole is set to be most of the way there
// by the time it does. It is therefore a small true-peak limiter, and like any
// limiter it bounds the ceiling closely rather than absolutely.
//
// Both constants were swept rather than guessed. Aliasing on the 6 kHz tone at
// 8x, against how far the peak still gets past the ceiling -- worst case over
// tones from 110 Hz to 13 kHz, since the residual is strongly tone dependent
// and picking on one tone alone had chosen a config 6x looser:
//
//                     D0 alias   D18 alias   worst over
//     guard off         -57.6       -40.1       +2.10
//     clamp (was)       -25.9       -23.1        0.00
//     LA 16, tau 5      -46.2       -39.4       +0.13
//     LA 24, tau 8      -47.9       -39.6       +0.02
//     LA 32, tau 10     -50.3       -39.8       +0.01
//
// LA 24 is the knee. Where it matters -- actually driving the thing -- the
// guard costs 0.5 dB of aliasing rather than the clamp's 17, and still pulls
// a +2.1 dB overshoot back to +0.02. Going to 32 buys another 0.01 dB of bound
// for 8 more samples of latency, which is not a trade worth taking.
//
// Those overshoot figures are with the DC Filter off. With it on -- the
// default -- both get worse, because a highpass tilts the flat tops of a
// clipped wave and its step response rings at each corner: unguarded worst
// case rises to +3.04 dB, and what the guard leaves rises to +0.11 dB, all of
// it below 500 Hz where the tilt is largest. Still a factor of 27, and the
// reason the guard sits after dcStage rather than before it.
GUARDLA  = 24;                          // lookahead, samples
GUARDTAU = 8.0;                         // envelope time constant, samples

// Both are in samples, not seconds, deliberately: what this is tracking is
// ringing around clipped corners, whose period scales with the sample rate.
guardPole = exp(0 - 1.0 / GUARDTAU);

// Linked across the pair, so a correction can never shift the image. It sits
// after msDec, so "the pair" is always L/R even when the clipper ran in M/S.
guardStage(l, r) = (l : @(GUARDLA)) * gEff, (r : @(GUARDLA)) * gEff
with {
    peak = max(abs(l), abs(r));
    greq = min(1.0, ceilLin / max(EPS, peak));   // 1 whenever already under
    g    = greq : ba.slidingMin(GUARDLA, GUARDLA) : si.smooth(guardPole);
    // interpolating the gain toward 1 is an exact bypass and cheaper than
    // crossfading two copies of the audio; the delay stays either way, since
    // it is part of the reported latency.
    gEff = 1 + safeOn * (g - 1);
};

wetChain = par(i, Nch, *(preGain))
         : msEnc
         : par(i, Nch, colorPre)
         : meterTap
         : clipSelect
         : par(i, Nch, colorPost)
         : msDec
         : par(i, Nch, *(ceilLin))
         : par(i, Nch, dcStage)
         : guardStage
         : par(i, Nch, *(postGain));

// Linear, not equal-power. The two sides of this blend are the same signal
// with and without its peaks shaved, so they sum coherently and a 3 dB law
// would bulge to +3 dB in the middle of the knob. The linear law holds unity
// for a clipper doing nothing, and matches the wrapper's own dry/wet.
//
// The dry tap is the plugin input, and the whole wet chain -- Output and Auto
// Gain included -- sits on the other side, so this mirrors what the wrapper's
// version blends. That is also what keeps Auto Gain honest at partial mixes:
// with it engaged the wet path is unity below the clip point, so both sides
// are identical there and the knob has nothing to do.
dryWetMix = (par(i, Nch, @(LATENCY)), si.bus(Nch))
          : ro.interleave(Nch, 2)
          : par(i, Nch, blend)
with {
    // si.smoo is a one-pole whose fixed point, evaluated in single precision,
    // lands a hair short of 1 rather than on it. Taken literally, Dry / Wet at
    // 100% would leave the untouched input mixed in around -95 dB for as long
    // as the plugin runs -- inaudible, but "clipper only" ought to mean it.
    // Scaling by a hair and clamping puts the top of the travel exactly on 1.
    // The bottom needs no help: the same one-pole decays to a true zero, so 0%
    // is already an exact bypass.
    dw = min(1, drywet * 1.0001);

    blend(d, w) = d * (1 - dw) + w * dw;
};

process = si.bus(Nch) <: (si.bus(Nch), wetChain)
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

