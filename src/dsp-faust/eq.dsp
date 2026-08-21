import("stdfaust.lib");

declare author "Klaus Scheuermann";
declare description "Mid/side parametric EQ modelled on x42-eq (fil4.lv2)";
declare license "GPL-3.0-or-later";
declare name "EQ42";
declare unique_id "LAeq";

//=============================================================================
// Faust port of x42-eq / fil4.lv2 — https://github.com/x42/fil4.lv2
//   (C) Robin Gareus, filter sections (C) Fons Adriaensen, GPL-2+.
//
// Signal chain, in the order the original runs it (src/lv2.c process_channel):
//   input gain -> highpass -> lowpass -> 4x parametric -> lowshelf -> highshelf
//
// Stereo throughout, and mid/side throughout: L/R is encoded once on the way in
// and decoded once on the way out, and every section carries a Stereo/Mid/Side
// selector saying which half it acts on. See the process section at the bottom.
//
// Each filter is transcribed *structurally*, not merely by transfer function,
// because the realisation is a good part of why this EQ sounds the way it does:
//   * parametric sections  = Fons Adriaensen's normalised 2nd-order allpass
//                            ladder, Fil4Paramsect (src/filters.h). Very low
//                            coefficient sensitivity at low frequencies.
//   * shelves              = RBJ shelving biquads in transposed direct form II,
//                            coefficients and topology per src/iir.h.
//   * highpass             = two cascaded one-pole DC blockers with resonance
//                            feedback (src/hip.h).
//   * lowpass              = four one-poles with feedback around the first two
//                            (src/lop.h), plus the fixed -6 dB high shelf at
//                            SR/3 that keeps the slope at -12 dB/oct all the
//                            way to Nyquist (LP_EXTRA_SHELF).
// All parameter maps (RESLP/RESHP resonance curves, the shelf-Q remap, the
// bandwidth-times-7*f/sqrt(g) rule, every clamp) are taken verbatim.
//
// Deliberate differences from the C original:
//   * parameters are smoothed per sample instead of per 32-sample block with
//     0.5x..2x slew limits — same audible result, no zipper noise;
//   * highpass/lowpass on-off crossfades to dry instead of morphing the
//     coefficients toward the identity (which parks poles on the unit circle).
//     Band and shelf on-off still work the original way, by interpolating gain
//     to 1.0, which is an exact bypass for those two forms;
//   * only the parametric sections keep their anti-denormal offset (it is part
//     of Fons' design); elsewhere denormals are left to the host's FTZ/DAZ.
//
// Verified against the C original: 105 single-filter cases across the parameter
// space agree to a median of 4e-5 dB, and with every section set to Stereo a
// full chain of all eight filters agrees to 0.003 dB / 0.03 deg over
// 20 Hz - 22 kHz, with exactly zero L-to-R crosstalk. The residual is
// coefficient rounding - Faust computes the design equations in the sample
// format, the C computes them in double and rounds once - and it shows up as a
// static ~0.003 dB response offset at the very bottom, not as distortion: the
// broadband error floor of the two is the same (-86 vs -88 dBFS in float32).
//=============================================================================

TWOPI = 2.0 * ma.PI;
DN    = 1e-10;   // Fil4Paramsect anti-denormal offset

clip(lo, hi, x) = max(lo, min(hi, x));

// One-pole parameter smoother, adapted from si.smoo in two ways that both
// mirror what iir_interpolate() does in the original C:
//   * it starts *at* the parameter value rather than ramping up from zero.
//     Faust's smoothers are zero-initialised, which would sweep every frequency
//     up from DC and every gain up from silence for the first second after load
//     - and a gain near zero makes the 1/sqrt(g) bandwidth rule in paramsect
//     explode. Holding the pole at 0 for the first sample latches instead.
//   * it snaps to the target once within SMOOTOL, so a parked parameter sits on
//     exactly its set value instead of dithering by an ulp forever. That is what
//     makes a band at 0 dB a bit-exact bypass rather than an almost-bypass.
// The pole is si.smoo's, so the time constant is unchanged.
SMOOTOL = 1e-6;
smoo = step ~ _
with {
    c = (1.0 - 44.1 / ma.SR) * (ba.time > 0);
    step(y, x) = select2(abs(x - y) <= SMOOTOL * max(1.0, abs(x)),
                         (1.0 - c) * x + c * y,
                         x);
};

//-------------------------------------------------------------------------- UI
// One vertical section per filter, sections stacked left to right in frequency
// order: input, highpass, low shelf, the four parametric bands, high shelf,
// lowpass. Every continuous control is a knob; the per-section enable stays a
// checkbox and the Stereo/Mid/Side selector a radio, since neither is a dial.
// Both switches bracket the knobs: enable at the head of the section, channel
// selector at the foot.
eqUI(x)      = hgroup("EQ42", x);
inGroup(x)   = eqUI(vgroup("[10] Input", x));
hpGroup(x)   = eqUI(vgroup("[20] Highpass", x));
lsGroup(x)   = eqUI(vgroup("[30] Low Shelf", x));
bGroup(k, x) = eqUI(vgroup("[4%k] Band %k", x));
hsGroup(x)   = eqUI(vgroup("[50] High Shelf", x));
lpGroup(x)   = eqUI(vgroup("[60] Lowpass", x));

// accent colours by role: 01 gain, 02 frequency, 03 bandwidth/resonance,
// 04 input trim - so the same kind of control reads the same across sections.
bypass = inGroup(checkbox("[0] Bypass [symbol:bypass][label:Bypass]"));
gaindb = inGroup(hslider("[1] Gain [style:knob][unit:dB][symbol:gain][label:Gain][accentcolor:04]", 0, -18, 18, 0.1));

hpOn   = hpGroup(checkbox("[0] Highpass [symbol:hp_on][label:On]"));
hpFreq = hpGroup(hslider("[1] Highpass Frequency [style:knob][unit:Hz][scale:log][symbol:hp_freq][label:Freq][accentcolor:02]", 20, 5, 1250, 1));
hpQ    = hpGroup(hslider("[2] Highpass Resonance [style:knob][symbol:hp_q][label:Res][accentcolor:03]", 0.7, 0, 1.4, 0.01));
hpMode = hpGroup(nentry("[3] Highpass Channel [style:radio{'Stereo':0;'Mid':1;'Side':2}][symbol:hp_ms][label:Channel]", 0, 0, 2, 1)) : int;

lsOn   = lsGroup(checkbox("[0] Lowshelf [symbol:ls_on][label:On]"));
lsFreq = lsGroup(hslider("[1] Lowshelf Frequency [style:knob][unit:Hz][scale:log][symbol:ls_freq][label:Freq][accentcolor:02]", 80, 25, 400, 1));
lsQ    = lsGroup(hslider("[2] Lowshelf Bandwidth [style:knob][symbol:ls_q][label:BW][accentcolor:03]", 1.0, 0.0625, 4, 0.01));
lsGain = lsGroup(hslider("[3] Lowshelf Gain [style:knob][unit:dB][symbol:ls_gain][label:Gain][accentcolor:01]", 0, -18, 18, 0.1));
lsMode = lsGroup(nentry("[4] Lowshelf Channel [style:radio{'Stereo':0;'Mid':1;'Side':2}][symbol:ls_ms][label:Channel]", 0, 0, 2, 1)) : int;

// four parametric bands, each free to roam the full 20 Hz - 20 kHz range
// (fil4 boxes every section into its own narrower window; these do not)
bOn(k)   = bGroup(k, checkbox("[0] Band %k [symbol:band_on%k][label:On]"));
bFreq(k) = bGroup(k, hslider("[1] Band %k Frequency [style:knob][unit:Hz][scale:log][symbol:band_freq%k][label:Freq][accentcolor:02]",
                             bDefF(k), bMinF(k), bMaxF(k), 1));
bQ(k)    = bGroup(k, hslider("[2] Band %k Bandwidth [style:knob][symbol:band_q%k][label:BW][accentcolor:03]", 0.5, 0.0625, 4, 0.01));
bGain(k) = bGroup(k, hslider("[3] Band %k Gain [style:knob][unit:dB][symbol:band_gain%k][label:Gain][accentcolor:01]", 0, -18, 18, 0.1));
bMode(k) = bGroup(k, nentry("[4] Band %k Channel [style:radio{'Stereo':0;'Mid':1;'Side':2}][symbol:band_ms%k][label:Channel]", 0, 0, 2, 1)) : int;

bDefF(k) = ba.take(k, (150.0,  400.0,   1000.0,  2500.0));
bMinF(k) = ba.take(k, ( 20.0,   20.0,    20.0,   20.0));
bMaxF(k) = ba.take(k, (20000.0, 20000.0, 20000.0, 20000.0));

hsOn   = hsGroup(checkbox("[0] Highshelf [symbol:hs_on][label:On]"));
hsFreq = hsGroup(hslider("[1] Highshelf Frequency [style:knob][unit:Hz][scale:log][symbol:hs_freq][label:Freq][accentcolor:02]", 8000, 1000, 16000, 1));
hsQ    = hsGroup(hslider("[2] Highshelf Bandwidth [style:knob][symbol:hs_q][label:BW][accentcolor:03]", 1.0, 0.0625, 4, 0.01));
hsGain = hsGroup(hslider("[3] Highshelf Gain [style:knob][unit:dB][symbol:hs_gain][label:Gain][accentcolor:01]", 0, -18, 18, 0.1));
hsMode = hsGroup(nentry("[4] Highshelf Channel [style:radio{'Stereo':0;'Mid':1;'Side':2}][symbol:hs_ms][label:Channel]", 0, 0, 2, 1)) : int;

lpOn   = lpGroup(checkbox("[0] Lowpass [symbol:lp_on][label:On]"));
lpFreq = lpGroup(hslider("[1] Lowpass Frequency [style:knob][unit:Hz][scale:log][symbol:lp_freq][label:Freq][accentcolor:02]", 20000, 500, 20000, 1));
lpQ    = lpGroup(hslider("[2] Lowpass Resonance [style:knob][symbol:lp_q][label:Res][accentcolor:03]", 1.0, 0, 1.4, 0.01));
lpMode = lpGroup(nentry("[3] Lowpass Channel [style:radio{'Stereo':0;'Mid':1;'Side':2}][symbol:lp_ms][label:Channel]", 0, 0, 2, 1)) : int;

//----------------------------------------------------------- Fil4Paramsect
// src/filters.h. Transfer function of the realisation below:
//   H(z) = [D(z) + G(1 - z^-2)] / D(z),  D(z) = 1 + s1(1+s2)z^-1 + s2 z^-2
//   G = 0.5(g-1)(1-s2)
// Bandwidth is scaled by 7*f/sqrt(g): the section widens with frequency and
// narrows with gain, which is what gives fil4 its musical boost/cut shapes.
paramsect(freq, band, gdb, on) = (step ~ (_, _)) : (!, !, _)
with {
    g  = ba.db2linear(on * gdb) : smoo;
    f  = clip(0.0002, 0.4998, freq / ma.SR) : smoo;
    b  = (band : smoo) * 7.0 * f / sqrt(g);
    s1 = 0 - cos(TWOPI * f);
    s2 = (1.0 - b) / (1.0 + b);
    a  = 0.5 * (g - 1.0);

    step(z1, z2, x) = z1n, z2n, out
    with {
        y0  = x - s2 * z2;
        out = x - a * (z2 + s2 * y0 - x);
        y   = y0 - s1 * z1;
        z2n = z1 + s1 * y;
        z1n = y + DN;
    };
};

//--------------------------------------------------------------- RBJ shelves
// Transposed direct form II, exactly as iir_compute (src/iir.h) runs it.
tdf2(b0, b1, b2, a1, a2) = (biq ~ (_, _)) : (!, !, _)
with {
    biq(y1, y2, x) = y1n, y2n, y
    with {
        y   = b0 * x + y1;
        y1n = b1 * x - a1 * y + y2;
        y2n = b2 * x - a2 * y;
    };
};

// iir_interpolate clamps: freq to [0.0004,0.47]*SR, q to [0.25,2]
shelfF(freq) = clip(0.0004 * ma.SR, 0.4700 * ma.SR, freq) : smoo;
shelfQ(q)    = clip(0.25, 2.0, q) : smoo;
// user bandwidth [2^-4 .. 4] mapped to [2^-3/2 .. 2], per process_channel()
shelfQmap(q) = 0.2129 + q / 2.25;

// iir_calc_lowshelf (src/iir.h), `gain` linear
lowshelfL(freq, q, gain) = tdf2(b0/a0, b1/a0, b2/a0, a1/a0, a2/a0)
with {
    w0 = TWOPI * shelfF(freq) / ma.SR;
    cw = cos(w0);
    A  = sqrt(gain);
    As = sqrt(A);
    al = sin(w0) / 2.0 / shelfQ(q);
    b0 =      A * ((A+1) - (A-1)*cw + 2*As*al);
    b1 =  2 * A * ((A-1) - (A+1)*cw);
    b2 =      A * ((A+1) - (A-1)*cw - 2*As*al);
    a0 =          (A+1) + (A-1)*cw + 2*As*al;
    a1 =  0 - 2 * ((A-1) + (A+1)*cw);
    a2 =          (A+1) + (A-1)*cw - 2*As*al;
};

// iir_calc_highshelf (src/iir.h), `gain` linear
highshelfL(freq, q, gain) = tdf2(b0/a0, b1/a0, b2/a0, a1/a0, a2/a0)
with {
    w0 = TWOPI * shelfF(freq) / ma.SR;
    cw = cos(w0);
    A  = sqrt(gain);
    As = sqrt(A);
    al = sin(w0) / 2.0 / shelfQ(q);
    b0 =      A * ((A+1) + (A-1)*cw + 2*As*al);
    b1 = -2 * A * ((A-1) + (A+1)*cw);
    b2 =      A * ((A+1) + (A-1)*cw - 2*As*al);
    a0 =          (A+1) - (A-1)*cw + 2*As*al;
    a1 =  2 *     ((A-1) - (A+1)*cw);
    a2 =          (A+1) - (A-1)*cw - 2*As*al;
};

lowshelf (freq, q, gdb, on) = lowshelfL (freq, shelfQmap(q), ba.db2linear(on*gdb) : smoo);
highshelf(freq, q, gdb, on) = highshelfL(freq, shelfQmap(q), ba.db2linear(on*gdb) : smoo);

//-------------------------------------------------------------- highpass
// src/hip.h. Two cascaded one-pole DC blockers, pole `a`, with (y2 - z2) fed
// back into the input: the difference between the outputs of the two stages is
// the resonance signal. `g` compensates the passband droop the feedback causes.
//   RESHP(x) = 0.7 + 0.78*tanh(1.82*(x - 0.8)), clamped to [0, 1.6]
highpass42(freq, res) = (hp ~ si.bus(3)) : (!, !, _)
with {
    fr = clip(5.0, ma.SR / 12.0, freq) : smoo;
    w  = fr / ma.SR;
    a  = exp(0 - TWOPI * w);
    q  = clip(0.0, 1.6, 0.7 + 0.78 * ma.tanh(1.82 * (res - 0.8))) : smoo;
    g  = 1.0 + w + 2.0 * q * w;
    m1 = g / a;
    m2 = g * q;

    hp(z1, z2, y2, x) = z1n, z2n, y2n
    with {
        z1n = m1 * x - m2 * (y2 - z2);
        z2n = a * (z2 + z1n - z1);
        y2n = a * (y2 + z2n - z2);
    };
};

//--------------------------------------------------------------- lowpass
// src/lop.h. Four one-poles in series; the first pair (coefficient `a`, set to
// the corner) carries the resonance feedback, the second pair (coefficient `b`,
// set way up at 0.25*SR + 0.5*fs) supplies the extra slope. The corner is
// pulled down by sqrt(1+fb) so the resonant peak stays put, and `tg` tapers
// the feedback off as the corner approaches Nyquist.
//   RESLP(x) = 3 * x^3.20772, clamped to [0, 9]
lowpass42(freq, res) = ((lp ~ si.bus(4)) : (!, !, !, _))
                     : highshelfL(ma.SR / 3.0, 0.444, 0.5)
with {
    fb = clip(0.0, 9.0, 3.0 * pow(res, 3.20772)) : smoo;
    fr = clip(630.0, min(20000.0, 0.4998 * ma.SR), freq) : smoo;
    fs = fr / sqrt(1.0 + fb);
    a  = lopAlpha(fs);
    b  = lopAlpha(0.25 * ma.SR + 0.5 * fs);
    w2 = 4.0 * fr / ma.SR;
    w3 = fr / (0.25 * ma.SR + 0.5 + fr);
    r  = fb * (1.0 + w3*w3) / (1.0 + w2*w2);

    lp(z1, z2, z3, z4, x) = z1n, z2n, z3n, z4n
    with {
        in  = (1.0 + r) * x - z2 * r;
        z1n = z1 + a * (in  - z1);
        z2n = z2 + a * (z1n - z2);
        z3n = z3 + b * (z2n - z3);
        z4n = z4 + b * (z3n - z4);
    };
};

lopAlpha(f) = 1.0 - exp(0 - TWOPI * clip(0.0002, 0.4998, f / ma.SR));

//----------------------------------------------------------------- process
// The EQ is stereo and works in the mid/side domain end to end: L/R is encoded
// once on the way in, decoded once on the way out, and everything in between
// runs on mid and side. Stereo is not a special case in that world - it is the
// same filter engaged on both halves, which is identical to filtering L and R,
// because the encode is a linear rotation and the two filters are the same.
//
// Every section therefore holds two instances of its filter, one on mid and one
// on side, and the selector decides which of them is engaged. How a half gets
// disengaged differs by filter type, and deliberately so:
//   * bells and shelves disengage through their own gain, which is an exact
//     bypass at 0 dB. Morphing the gain is phase-coherent, where crossfading
//     the filtered signal against the dry one would comb on the way past;
//   * highpass and lowpass have no gain to morph, so they reuse the same
//     dry/wet crossfade their on-off already needs.
// Either way the disengaged instance keeps running on its half, so its state is
// warm and switching back is seamless.
//
// Encode/decode scaling matches common/input.dsp and common/output.dsp, so the
// suite's global mid/side switch and this one compose without surprises. Note
// the two do compound: with the global switch on, this EQ sees M/S as its L/R,
// and its own Mid becomes the mid of that pair.

msEnc(l, r) = (l + r) * 0.5, (l - r) * 0.5;
msDec(m, s) = m + s, m - s;

midSel (mode) = mode != 2;   // engaged for Stereo and Mid
sideSel(mode) = mode != 1;   // engaged for Stereo and Side

xfade(on, F) = _ <: (_, F) : si.interpolate(on : smoo);

hpPair = xfade(hpOn * midSel (hpMode), highpass42(hpFreq, hpQ)),
         xfade(hpOn * sideSel(hpMode), highpass42(hpFreq, hpQ));

lpPair = xfade(lpOn * midSel (lpMode), lowpass42(lpFreq, lpQ)),
         xfade(lpOn * sideSel(lpMode), lowpass42(lpFreq, lpQ));

lsPair = lowshelf(lsFreq, lsQ, lsGain, lsOn * midSel (lsMode)),
         lowshelf(lsFreq, lsQ, lsGain, lsOn * sideSel(lsMode));

hsPair = highshelf(hsFreq, hsQ, hsGain, hsOn * midSel (hsMode)),
         highshelf(hsFreq, hsQ, hsGain, hsOn * sideSel(hsMode));

bandPair(k) = paramsect(bFreq(k), bQ(k), bGain(k), bOn(k) * midSel (bMode(k))),
              paramsect(bFreq(k), bQ(k), bGain(k), bOn(k) * sideSel(bMode(k)));

eqMS = par(i, 2, *(ba.db2linear(gaindb) : smoo))
     : hpPair
     : lpPair
     : seq(k, 4, bandPair(k + 1))
     : lsPair
     : hsPair;

process = _, _ <: (_, _, (msEnc : eqMS : msDec)) : blend
with {
    active = 1.0 - bypass : smoo;
    blend(l, r, pl, pr) = si.interpolate(active, l, pl),
                          si.interpolate(active, r, pr);
};
