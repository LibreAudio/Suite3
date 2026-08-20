declare author "Klaus Scheuermann";
declare description "";
declare license "GPL-3.0-or-later";
declare name "Reverb";
declare unique_id "LArv";

// declare drywet "true";

import("stdfaust.lib");

// Musical hall reverb in the Lexicon 480L / Bricasti M7 lineage — a tuned
// machine, not a room model.
//
// Three stages. An early reflection section, then TWO late tails running in
// parallel — an 8x8 FDN in the Bricasti lineage and a Griesinger loop in the
// Lexicon one — crossfaded against each other by a single Tail Blend control.
// The two tails share one set of parameters: Decay, Size, Bass Multiply and
// the rest each drive both tanks at once, so Blend changes which machine you
// are listening to without changing what you asked it for.
//
//======================== early reflections ==================================
// Topology: sparse tap pattern -> allpass diffusion.
//
//   Neither the 480L nor the M7 computes a room. Both use a hand-tuned sparse
//   tap pattern followed by a diffusion network, and the character difference
//   between them is mostly how much diffusion sits after the taps. The 480L
//   lets you hear the individual reflections (its "Reflections" patterns are
//   literal tap tables); the M7's early section is smeared until the discrete
//   events disappear into a bloom. So the Diffusion control here is the main
//   character axis, and both ends of its travel have to sound good.
//
//   Taps are the pattern and the distance cue; diffusion is the texture. Doing
//   it in that order keeps the tap timing as the ER envelope, which is what
//   gives the sound a size. (Diffusing first and tapping after also works, but
//   the taps stop being audible as structure.)
//
// Stereo: a full 2x2 matrix. L->L, R->R, L->R and R->L each get their OWN tap
//   set, so a mono source arrives decorrelated at the two outputs and the image
//   opens up instead of collapsing to the centre. If the direct and cross sets
//   were mirror images the whole thing would sum to mono.
//
// Tap-time choice: irregular spacing, no small integer ratios, nothing closer
//   than ~6 ms inside one set. Regular spacing is what makes a multi-tap ER
//   ring metallically — it is a comb filter with extra steps. Tap polarity is
//   the other free variable, and it costs nothing: flipping a sign moves the
//   comb structure without touching the reflection envelope at all. Both are
//   fitted rather than chosen by ear; see the tap tables below.
//
// Damping: taps are summed in three time blocks, each with its own one-pole
//   lowpass, later blocks darker. Per-tap filters would be more correct and
//   cost 4x more; grouped in three the difference is inaudible. This
//   progressive darkening does more for "musical" than any tap-time tweak —
//   it is air absorption without modeling air.
//
// No modulation in this stage, deliberately. Modulated early taps smear the
//   pitch of transients. Both reference units modulate the tail, not the
//   early section.

process = reverb;

//======================== tap tables =========================================
// Times in ms, gains linear. Four independent sets, one per matrix path.
// Sets A and B (the direct paths) carry matched total energy, as do C and D
// (the cross paths), so the image stays balanced.
//
// The gain envelopes are hand-drawn — a smooth decay, which is what sets the
// shape of the reflection cloud. The tap TIMES and POLARITIES are not: they
// were fitted offline (scratch script, simulated annealing) to minimise the
// 1/12-octave-smoothed magnitude ripple of each output channel, evaluated at
// Spread 0, 0.7 and 1.0 at once so the flatness survives the whole knob.
//
// This is the part of the design worth being careful about. Allpass diffusion
// is magnitude-flat by construction — measured, the ripple is identical at
// Diffusion 0 and Diffusion 1 — so nothing downstream can undo tap-pattern
// coloration. It has to be fixed here or not at all. The two sets that share
// an output are fitted jointly; flattening each one alone just leaves them
// interfering with each other, which was measured too.
//
// What the fit actually bought, measured on the built DSP with the damping
// tilt detrended out: broadband ripple barely moved, 1.1-1.4 dB down to
// 1.0-1.2 dB, but the deep narrow notches — the part that reads as metallic —
// went from -7 to -12 dB down to -2 to -3 dB. The notches were the point.
//
// First and last tap of each set are pinned: the first is the onset, and the
// L/R offset between them is a deliberate image cue; the last sets how long
// the early section runs before the tail takes over.

NTAP = 12;

// L -> L
tA(i) = ba.take(i+1, (11.30, 20.29, 30.94, 40.99, 49.83, 58.69,
                      68.94, 83.48, 90.01, 96.63, 104.40, 111.10));
gA(i) = ba.take(i+1, (1.00,  0.82,  0.71, -0.63,  0.55, -0.48,
                     -0.41,  0.35, -0.30, -0.25,  0.21, -0.17));

// R -> R
tB(i) = ba.take(i+1, (13.10, 20.64, 26.84, 34.37, 46.77, 58.72,
                      67.62, 76.93, 90.38, 98.53, 105.65, 116.90));
gB(i) = ba.take(i+1, (1.00,  0.79,  0.74, -0.60, -0.57,  0.46,
                      0.43, -0.33,  0.31, -0.24, -0.22,  0.16));

// L -> R
tC(i) = ba.take(i+1, (15.70, 24.63, 43.66, 54.61, 61.06, 67.41,
                      74.07, 88.99, 95.18, 101.76, 112.30, 121.30));
gC(i) = ba.take(i+1, (0.88, -0.76, -0.68,  0.58, -0.52,  0.44,
                     -0.38, -0.33, -0.28, -0.23,  0.19, -0.15));

// R -> L
tD(i) = ba.take(i+1, (14.30, 28.62, 44.68, 53.87, 60.61, 68.48,
                      74.89, 81.22, 95.85, 103.41, 112.03, 119.70));
gD(i) = ba.take(i+1, (0.85,  0.78,  0.66, -0.61,  0.50,  0.45,
                     -0.37, -0.34,  0.29, -0.22,  0.20,  0.14));

// Diffuser delays in ms. Kept short on purpose: a Schroeder
// allpass with its coefficient at 0 degenerates into a plain delay, so a long
// chain would shove the whole reflection pattern later as Diffusion is turned
// down — measured at 30 ms with Dattorro's tank values, which is a distance
// change, not a texture change. With a ~10 ms chain the reflection pattern
// starts at its tabulated time everywhere except the knob's extreme zero,
// where it runs 10 ms late and the reflections are bare anyway. Left and right
// sums are close but not equal, so the two channels stay decorrelated without
// the image leaning to one side.
apL(i) = ba.take(i+1, (0.71, 1.39, 2.87, 4.61));
apR(i) = ba.take(i+1, (0.79, 1.51, 3.07, 4.87));
NAP = 4;

// Ceiling on the allpass coefficient. Measured, not guessed: sweeping it and
// watching the crest factor of the reflection cloud, smearing improves up to
// about 0.62 and then reverses — past that the chain's feedforward term is
// loud enough to re-concentrate the energy into a bright slap at the front of
// the cloud, so "more diffusion" starts sounding like less. The knob is scaled
// so its top end sits at the measured smoothest point.
GMAX = 0.62;

//======================== tail: the tank =====================================
// An 8x8 feedback delay network — the Jot/Stautner-Puckette structure, which is
// the Bricasti lineage. Eight delay lines, an orthogonal (Hadamard) feedback
// matrix, and one loss filter per line. Topology gets you maybe 40% of the way
// to sounding like a hall; the other 60% is in the four blocks below.
//
// Line lengths: mutually irregular, spanning about 1:3 shortest to longest.
// The mean sets echo density and the spread stops the network having strong
// eigenmodes. Too short and the tail rings metallic; too long and it turns
// grainy and gated on percussion.
tdel(i)   = ba.take(i+1, (23.31, 29.83, 34.61, 41.17, 47.53, 55.09, 63.71, 72.89));

// Independent modulation rate per line. Independence is the whole point: a
// correlated wobble across all eight lines just detunes the tail as a block,
// whereas independent drift keeps the eigenmodes from ever settling, which is
// what stops a sustained note ringing. This is the single biggest difference
// between a good FDN and one that sounds like very tidy convolution. Lexicon
// modulates deep enough to hear as chorus, Bricasti far more subtly; the depth
// control spans both.
tmrate(i) = ba.take(i+1, (0.113, 0.171, 0.229, 0.283, 0.347, 0.419, 0.487, 0.571));

// Tried and rejected: an allpass inside each delay line, the usual remedy for
// a sparse FDN. Measured with Abel-Huang normalised echo density, this network
// already reaches fully diffuse (Gaussian) at 75 ms, and adding the in-loop
// allpasses moved that curve by nothing at all — while folding their delay
// into the T60 gain cost 5 points of decay-time accuracy. Eight lines over a
// 23-73 ms spread are enough on their own. For scale, re.dattorro_rev measured
// on the same metric does not reach that density until 331 ms.

// Input diffuser for the tail feed. At Tail Feed 0 the tank is fed raw input,
// which an FDN alone does not make dense fast enough — the first ~40 ms would
// be audibly sparse. This fills it in. At Tail Feed 1 the ER stage has already
// done the job, so the diffuser is mostly redundant there.
tdifL(i)  = ba.take(i+1, (1.13, 2.31, 4.79, 7.53));
tdifR(i)  = ba.take(i+1, (1.27, 2.63, 5.31, 8.17));
NTDIF = 4;
NLINE = 8;

// Injection and output patterns. Rather than feeding L into some lines and R
// into others, every line gets both channels at a different balance — line i
// sits at its own angle in the stereo field. The two patterns are orthogonal
// (sum of cos*sin over the eight angles is zero), so L and R stay decorrelated,
// and unlike a pair of Hadamard rows no line is ever left unfed by a centred
// source. The output angles run in the opposite order, so which line dominates
// the left output is unrelated to which one the left input drove hardest.
inA(i)  = cos(ma.PI/NLINE * (i + 0.5));
inB(i)  = sin(ma.PI/NLINE * (i + 0.5));
outA(i) = cos(ma.PI/NLINE * (NLINE-1-i + 0.5));
outB(i) = sin(ma.PI/NLINE * (NLINE-1-i + 0.5));

// Sum of cos^2 over the eight angles is NLINE/2, so both patterns normalise by
// the same factor to keep the tank at unity.
IONORM = 1.0 / sqrt(NLINE/2.0);

// Shape/Spread, the Lexicon pair. Spread sets how long the reverb takes to
// build; Shape sets the contour of that build, from an explosive attack that
// decays immediately to a slow bloom that sustains for the Spread period.
//
// The mechanism is input-side: it shapes the injection into the tank, not the
// tank, so the output envelope is the injection envelope convolved with the
// tank's own response. That is why one idea serves both tails.
//
// The obvious implementation — a tapped delay summed into one injection point,
// with the tap GAINS forming the contour — is a trap. Summing N delayed copies
// of one signal is a comb filter, which is the same coloration the early
// reflection tables were fitted to avoid, and no amount of downstream
// diffusion removes it. So instead each injection point gets exactly ONE
// arrival, and Shape warps the arrival TIMES rather than weighting gains.
// Nothing is ever summed with a delayed copy of itself, the injected energy is
// identical at every Shape setting, and the level cannot move.
//
// The warp is t = Spread * u^p over u in [0,1]. Because the u values span the
// closed interval, the first arrival is always at 0 and the last always at
// Spread, whatever p does: the reverb never fails to start, and Spread always
// means what it says. Shape only redistributes what happens in between. At p
// large everything crowds to the front, which is the explosive attack; at p = 1
// arrivals are evenly spaced, a linear build to a plateau; below 1 they bunch
// toward the end and the reverb blooms late.
//
// The first u is a hair above zero rather than zero itself, so that log(u) in
// the warp stays finite.
SHAPEP(sh) = pow(6.0, 1.0 - 1.5*sh);   // Shape 0 -> 6, 0.67 -> 1, 1 -> 0.41

// Arrival order across the eight lines. Deliberately NOT monotonic in the line
// index: line i also carries stereo angle i, so ordering arrivals by index
// would make the early part of the build come from the left and the late part
// from the right. Pairing each line with its mirror — 0 with 7, 3 with 4 —
// keeps every moment of the buildup centred.
shu(i) = ba.take(i+1, (0.000001, 0.285714, 0.571429, 0.857143,
                       1.0,      0.714286, 0.428571, 0.142857));

// The loop version, four injection points paired the same way.
gtu(k)  = ba.take(k+1, (0.000001, 0.666667, 1.0, 0.333333));
gcos(k) = cos(ma.PI/4 * (k + 0.5));
gsin(k) = sin(ma.PI/4 * (k + 0.5));
GIONORM = 1.0 / sqrt(2.0);

//======================== tail: the loop =====================================
// A second, completely independent tail running in parallel with the FDN: the
// Griesinger loop, which is the Lexicon 480L/224 lineage rather than the
// Bricasti one. Where the FDN scatters energy across eight lines and reads the
// ends, this circulates one signal around a single long path built from series
// allpasses and delays, and reads the output from SEVEN TAPS INSIDE the loop.
// That last part is the whole trick: taking the output from within the
// circulation rather than from its end is why a 480L seems to arrive from
// every direction at once instead of from a point. It flatters everything,
// which is exactly its reputation.
//
// Figure-of-eight: half A feeds half B feeds half A, one circulating path, but
// the left input is injected at A's entry and the right at B's, so the tank is
// not simply fed a mono sum — the two halves stay tilted toward their own
// channel while still sharing one loop.
//
// Both halves: a modulated allpass, a delay, loss, a second allpass, a delay,
// loss. The modulation sits on the first allpass of each half rather than on
// the delays, which is where Lexicon put it and is the source of the shimmer.

gapA1  = 16.31; gdelA1 = 82.43; gapA2 = 38.71; gdelA2 = 67.53;
gapB1  = 21.17; gdelB1 = 76.19; gapB2 = 47.23; gdelB2 = 59.87;
GLOOPMS = 409.44;                        // the two halves summed, for the T60 maths

// Input diffuser for the loop, its own, irregular against the ER stage's.
gdifL(i) = ba.take(i+1, (0.97, 2.11, 4.13, 6.89));
gdifR(i) = ba.take(i+1, (1.09, 2.47, 4.61, 7.31));

// Seven taps per output, read from inside the loop. Each offset is shorter
// than the delay it reads from, so all of them share that delay's buffer and
// the tap count is free. Left leans on half B and right on half A, with a
// couple of crossed taps each so neither output is simply one half of the
// tank; the alternating signs break up the comb structure the same way the
// early reflection tables do.
NGTAP = 7;
// The 1/sqrt(N) is the arithmetic; the second factor is measured, and trims
// the loop to the same output level as the FDN. That match is what lets Tail
// Blend crossfade between the two tanks without the level moving.
GTAPNORM = 1.0 / sqrt(NGTAP) * 0.69;

//======================== sizing =============================================
// Faust needs literal max delay lengths, so they are budgeted for the worst
// case: longest tap * largest Size at 192 kHz. All taps read the same source
// signal, so the compiler allocates one ring buffer per input channel and
// reads it at 24 offsets — the tap count costs no extra memory.

MAXSR    = 192000;
MAXSIZE  = 2.0;
MAXTAPMS = 130;
MAXPDMS  = 250;
MAXAPMS  = 16;

MAXTLINEMS = 80;
MAXMODMS   = 3;

MAXTAPD   = int(MAXTAPMS * MAXSIZE * MAXSR / 1000.0) + 2;
MAXPDD    = int(MAXPDMS  * MAXSR / 1000.0) + 2;
MAXAPD    = int(MAXAPMS  * MAXSIZE * MAXSR / 1000.0) + 2;
MAXTLINED = int((MAXTLINEMS * MAXSIZE + MAXMODMS + 4) * MAXSR / 1000.0) + 2;
MAXTDIFD  = int(10 * MAXSR / 1000.0) + 2;
MAXGDELD  = int(90 * MAXSIZE * MAXSR / 1000.0) + 2;
MAXGAPD   = int((50 * MAXSIZE + MAXMODMS + 4) * MAXSR / 1000.0) + 2;
MAXSHPD   = int(500 * MAXSR / 1000.0) + 2;

// 3*ln(10): converts a T60 in seconds into a per-pass loop gain.
LN1000 = 6.9077553;

ms2samp(t) = t * ma.SR / 1000.0;

// si.smooth's state starts at zero, so a plain `: si.smoo` ramps a control up
// from 0 over the first ~20 ms. Harmless on a gain, but on Size it collapses
// every tap to zero delay and slaps, and on Damping it starts the lowpass at
// 0 Hz and mutes. Smoothing the offset from the default value instead leaves
// the smoother at rest when nothing has been touched.
smoo(dflt, x) = (x - dflt) : si.smoo : +(dflt);

//======================== the reverb =========================================

uiBottom(x) = hgroup("[8]Stage Bottom", x);
uiBottomRight(x) = uiBottom(hgroup("[1]Stage Bottom Right", x));

uiDeEss(x)  = uiBottom(hgroup("[5]De-Esser", x));
uiMeters(x) = hgroup("[9]", x);



reverb = _,_ <: dry, wet :> _,_
with {
    rev_group(x)  = vgroup("REVERB", x);
    er_group(x)   = rev_group(hgroup("[0] Early Reflections", x));
    tail_group(x) = rev_group(hgroup("[1] Tail", x));
    out_group(x)  = rev_group(hgroup("[2] Output", x));

    // --- early reflection controls ---
    predelay = er_group(hslider("[0] Pre-delay [unit:ms] [style:knob] [symbol:predelay]",
                                0, 0, 250, 0.1)) : si.smoo;

    // Scales every tap time and every diffuser delay. This is the distance
    // cue: the first tap moves from ~6 ms (intimate) to ~23 ms (large hall).
    size = er_group(hslider("[1] ER Size [style:knob] [symbol:er_size]",
                            1.0, 0.5, MAXSIZE, 0.001)) : smoo(1.0);

    // 0 = bare taps, 480L-style discrete reflections, good on drums.
    // 1 = fully smeared bloom, M7-style, good on vocals and strings.
    diffusion = er_group(hslider("[2] ER Diffusion [style:knob] [symbol:er_diffusion]",
                                 0.6, 0, 1, 0.001)) : smoo(0.6) : *(GMAX);

    // Cutoff of the first tap block; later blocks are darker by fixed ratios.
    damp = er_group(hslider("[3] ER Damping [unit:Hz] [scale:log] [style:knob] [symbol:er_damping]",
                            7000, 800, 20000, 1)) : smoo(7000) : min(0.45 * ma.SR);

    // How much of each input reaches the opposite output. At 0 a hard-panned
    // source keeps its reflections on its own side; turning it up spreads the
    // pattern across the image.
    spread = er_group(hslider("[4] ER Spread [unit:%] [style:knob] [symbol:er_spread]",
                              70, 0, 100, 1)) / 100 : smoo(0.70);

    erlevel = er_group(hslider("[5] ER Level [unit:dB] [style:knob] [symbol:er_level]",
                               0, -60, 12, 0.1)) : ba.db2linear : si.smoo;

    // --- tail controls ---
    // What the tank listens to. At 0 the tail is driven by the (pre-delayed,
    // tone-shaped) input directly and is independent of the ER stage — 480L-ish
    // separation, and ER Level no longer affects tail level. At 1 it is driven
    // by the ER output, so the tail inherits the tap pattern and the diffusion
    // and the two sections read as one continuous event, which is the more
    // M7-like behaviour. The coupling is the point of the control, but it does
    // mean that at high Feed the ER knobs colour the tail as well.
    tailfeed = tail_group(hslider("[0] Tail Feed [unit:%] [style:knob] [symbol:tail_feed]",
                                  50, 0, 100, 1)) / 100 : smoo(0.5);

    // Which of the two tanks you are hearing. 0% is the FDN alone, 100% the
    // loop alone, and everything between is an equal-power crossfade — the two
    // tails are decorrelated and trimmed to the same output level, so this
    // changes character without changing loudness. It replaces what used to be
    // a Level knob per tail; ER Level now carries the early/late balance on its
    // own, with the tails as the reference at unity.
    tblend = tail_group(hslider("[1] Tail Blend [unit:%] [style:knob] [symbol:tail_blend]",
                                100, 0, 100, 1)) / 100 : smoo(0.0);

    decay = tail_group(hslider("[2] Decay [unit:s] [scale:log] [style:knob] [symbol:decay]",
                               2.2, 0.2, 20, 0.01)) : smoo(2.2);

    tsize = tail_group(hslider("[3] Size [style:knob] [symbol:tail_size]",
                               1.0, 0.5, MAXSIZE, 0.001)) : smoo(1.0);

    // Decay time below Bass Freq, as a multiple of Decay. Above 1 the low end
    // rings on after the mids have gone, which is most of what "large hall"
    // means to a listener — it is the 480L's Bass Multiply, and one of the two
    // or three controls that actually earn the word musical.
    bassmult = tail_group(hslider("[4] Bass Multiply [style:knob] [symbol:bass_mult]",
                                  1.4, 0.25, 2.5, 0.01)) : smoo(1.4);
    bassfreq = tail_group(hslider("[5] Bass Freq [unit:Hz] [scale:log] [style:knob] [symbol:bass_freq]",
                                  350, 100, 1000, 1)) : smoo(350);

    // Air absorption: the loop loses treble on every pass, so HF decay is
    // always shorter than mid decay, never longer.
    hfdamp = tail_group(hslider("[6] HF Damping [unit:Hz] [scale:log] [style:knob] [symbol:hf_damp]",
                                5500, 1000, 20000, 1)) : smoo(5500) : min(0.45 * ma.SR);

    modrate = tail_group(hslider("[7] Mod Rate [style:knob] [symbol:mod_rate]",
                                 1.0, 0.1, 3, 0.01)) : smoo(1.0);
    moddepth = tail_group(hslider("[8] Mod Depth [unit:%] [style:knob] [symbol:mod_depth]",
                                  35, 0, 100, 1)) / 100 * MAXMODMS : smoo(0.35 * MAXMODMS);

    // How smeared each tank is. One knob, but it does rather more to the loop
    // than to the FDN: in the FDN it drives only the input diffuser, whereas in
    // the loop it also sets the coefficient of all four allpasses inside the
    // circulation. Sweeping it and measuring both, the FDN bottoms out at 0.70
    // and improves only slightly above; the loop keeps improving, and needs
    // 0.75 before its echo density reaches the fast regime. So the shared
    // default sits at the loop's requirement, which costs the FDN nothing.
    density = tail_group(hslider("[9] Density [style:knob] [symbol:density]",
                                 0.75, 0, 1, 0.001)) : smoo(0.75) : *(GMAX);

    // Spread is the time scale and Shape the contour; Shape does nothing at all
    // with Spread at 0, which is exactly the relationship the pair has on a
    // 480L, and is why 0 is the default — it leaves the tank's own onset alone.
    tshape = tail_group(hslider("[10] Shape [style:knob] [symbol:tail_shape]",
                                0.5, 0, 1, 0.001)) : smoo(0.5) : SHAPEP;
    tspread = tail_group(hslider("[11] Spread [unit:ms] [style:knob] [symbol:tail_spread]",
                                 0, 0, 500, 1)) : si.smoo;

    // --- output ---
    // The cuts sit on the wet path only, ahead of everything, so they shape
    // what both the taps and the tanks are fed rather than only what comes out.
    lowcut = out_group(hslider("[0] Low Cut [unit:Hz] [scale:log] [style:knob] [symbol:lowcut]",
                               60, 20, 1000, 1));
    highcut = out_group(hslider("[1] High Cut [unit:Hz] [scale:log] [style:knob] [symbol:highcut]",
                                18000, 1000, 20000, 1)) : min(0.45 * ma.SR);

    // Mid/side trim on the wet signal only.
    width = out_group(hslider("[2] Stereo Width [unit:%] [style:knob] [symbol:stereo_width]",
                              100, 0, 200, 1)) / 100 : smoo(1.0);

    level = out_group(hslider("[3] Reverb Level [unit:dB] [symbol:level]",
                              0, -60, 10, 0.1)) : ba.db2linear : si.smoo;

    drywet = out_group(hslider("[4] dry/wet [unit:%] [symbol:drywet]",
                               35, 0, 100, 1)) / 100 : smoo(0.35);

    // --- signal path ---
    // src is shared: all three stages hang off the same pre-delayed, cut input,
    // so Pre-delay and the two cuts move the whole reverb at once.
    //
    //   src --+--> erstage --+--> ER out ---------------------------+ * erlevel
    //         |      |       |                                      |
    //         |      |       +--> feedmix ----> tdiffuse --> tank ---+ * kf
    //         |      |       |                                      |
    //         |      |       +--> loopfeedmix -> gdiffuse -> gtank --+ * kg
    //         +------+-------+                                      |
    //                                                    width, level, dry/wet
    //
    // Both tails read the same Feed knob and the same parameter set; kf and kg
    // are the two halves of the Tail Blend crossfade. The bus arithmetic below
    // carries ten signals at its widest: three copies of the ER output (one for
    // the output sum, one per tank feed) and two of src.
    dry = par(i, 2, *(1 - drywet));

    src = par(i, 2, incut : de.fdelay(MAXPDD, ms2samp(predelay)));

    wet = src : hfLimit <: (erstage, si.bus(2))
        : fanout
        : si.bus(2), feedmix, loopfeedmix
        : si.bus(2), (tdiffuse(tdifL), tdiffuse(tdifR) : tank)
                   , (gdiffuse(gdifL), gdiffuse(gdifR) : gtank)
        : sumthree
        : stereoWidth(width)
        : par(i, 2, *(level * drywet));

    // erL,erR,srcL,srcR -> one copy of the ER for the output, and one (ER,src)
    // pair for each tail to crossfade between. The ER stage itself is computed
    // once, upstream of here.
    fanout(e1, e2, s1, s2) = e1, e2, e1, e2, s1, s2, e1, e2, s1, s2;

    // Equal-power, because the two tails are mutually decorrelated: summing
    // them at sqrt weights holds the total energy flat across the knob.
    sumthree(e1, e2, t1, t2, g1, g2) = e1*erlevel + t1*kf + g1*kg,
                                       e2*erlevel + t2*kf + g2*kg
    with {
        kf = sqrt(max(0, 1 - tblend));
        kg = sqrt(tblend);
    };

    incut = fi.highpass(2, lowcut) : fi.lowpass(2, highcut);

    // Equal-power crossfade between the two things the tank can listen to. The
    // ER leg sits below the source leg for the same input — it carries ernorm,
    // the tone filters and the damping tilt — so it is made up here, otherwise
    // the Feed knob would act as a tail volume control. The figure is measured
    // rather than derived, at the ER stage's default settings; pushing ER Size
    // or Damping hard will shift it a little, since those change how much of
    // the source survives the tap stage.
    ERFEEDNORM = 1.29;
    feedmix(el, er2, sl, sr) = el*ke + sl*ks, er2*ke + sr*ks
    with {
        ke = sqrt(tailfeed) * ERFEEDNORM;
        ks = sqrt(max(0, 1 - tailfeed));
    };

    tdiffuse(d) = seq(i, NTDIF, fi.allpass_fcomb(MAXTDIFD, ms2samp(d(i)), -density));

    // The Feed knob is shared, but each tank needs its own match constant: the
    // two tanks weight the same two source signals differently — the
    // loop puts two shelves and two lowpasses in every trip against the FDN's
    // one of each, so it is darker per pass and the darker ER leg lands on it
    // differently. Measured separately for that reason.
    LOOPFEEDNORM = 1.43;
    loopfeedmix(el, er2, sl, sr) = el*ke + sl*ks, er2*ke + sr*ks
    with {
        ke = sqrt(tailfeed) * LOOPFEEDNORM;
        ks = sqrt(max(0, 1 - tailfeed));
    };

    gdiffuse(d) = seq(i, NTDIF, fi.allpass_fcomb(MAXTDIFD, ms2samp(d(i)), -density));

    //---- early reflections ----
    erstage = ermatrix : diffuse(apL), diffuse(apR) : par(i, 2, *(ernorm));

    // Sum of tap gains squared is ~3.6 per direct set and ~3.05 per cross set;
    // worst case (Spread at 100%) is sqrt(6.7) of voltage gain on a correlated
    // input, so trim it back to unity here rather than in the Level knob.
    ernorm = 0.39;

    // 2x2 matrix. Each input feeds its own direct set and its own cross set.
    ermatrix(l, r) = erpath(tA, gA, l) + erpath(tD, gD, r) * spread,
                     erpath(tB, gB, r) + erpath(tC, gC, l) * spread;

    // One path: taps split into three time blocks, each block summed and then
    // damped, later blocks progressively darker.
    erpath(t, g, x) = tapblock(t, g,  0, damp)
                    + tapblock(t, g,  4, damp * 0.72)
                    + tapblock(t, g,  8, damp * 0.5)
    with {
        tapblock(t, g, i0, fc) =
            sum(k, 4, tap(i0 + k)) : fi.lowpass(1, fc);
        tap(i) = de.fdelay(MAXTAPD, ms2samp(t(i) * size), x) * g(i);
    };

    // Series allpass chain: turns each discrete tap into an exponentially
    // densifying cloud without colouring the magnitude response.
    diffuse(d) = seq(i, NAP, ap(d(i)))
    with {
        ap(msec) = fi.allpass_fcomb(MAXAPD, ms2samp(msec * size), -diffusion);
    };

    //---- the tank ----
    tank(l, r) = (par(i, NLINE, +(inj(i)) : line(i)) : mixmatrix) ~ si.bus(NLINE)
               : outmix
    with {
        // One arrival per line. Both channels are read from the same two delay
        // buffers at eight different offsets, so the whole Shape section costs
        // two delay lines rather than eight.
        inj(i) = (de.fdelay(MAXSHPD, ti, l) * inA(i)
                + de.fdelay(MAXSHPD, ti, r) * inB(i)) * IONORM
        with {
            // log of a literal folds at compile time, so this is one exp per
            // line rather than a pow.
            ti = ms2samp(tspread * exp(tshape * log(shu(i))));
        };

        // Delay, then the loss filter that sets how long this pass survives.
        line(i) = de.fdelay5(MAXTLINED, dlen) : loss
        with {
            dsec = tdel(i) * tsize / 1000.0;
            dlen = ms2samp(tdel(i) * tsize
                           + moddepth * os.osci(tmrate(i) * modrate));

            // Per-pass loop gain: mid band from the T60, then a low shelf that
            // raises the DC gain to whatever gives Decay * Bass Multiply down
            // there, then a one-pole for treble absorption.
            gmid = exp(-LN1000 * dsec / decay);
            lfb  = exp(-LN1000 * dsec / decay * (1.0/bassmult - 1.0));
            loss = fi.lowpass(1, hfdamp)
                 : fi.low_shelf1_l(lfb, bassfreq)
                 : *(gmid);

            // Stability is structural here, not tuned: the lowpass never
            // exceeds unity and a first-order shelf's maximum gain is exactly
            // its DC gain, so the loop magnitude is bounded by
            // max(gmid * lfb, gmid) — that is gmid^(1/bassmult) or gmid, both
            // below 1 for any positive Decay and any positive Bass Multiply.
            // No combination of knob positions can run away.
        };

        mixmatrix = ro.hadamard(NLINE) : par(i, NLINE, *(1.0 / sqrt(NLINE)));

        // Both output channels are drawn from all eight lines. Taking L and R
        // from one line each is the cheap option and sounds narrow.
        outmix = par(i, NLINE, _ <: *(outA(i) * IONORM), *(outB(i) * IONORM))
               :> _,_;
    };

    //---- the loop ----
    gtank(l, r) = ((body ~ project) : keep : taps)
    with {
        // Four injection points round the loop rather than two, so Shape has
        // four arrival times to work with instead of a useless two. Each point
        // takes both channels at its own angle in the stereo field — the same
        // scheme the FDN uses — rather than L into one half and R into the
        // other, which would tie the buildup order to the stereo image.
        ginj(k) = (de.fdelay(MAXSHPD, gti, l) * gcos(k)
                 + de.fdelay(MAXSHPD, gti, r) * gsin(k)) * GIONORM
        with {
            gti = ms2samp(tspread * exp(tshape * log(gtu(k))));
        };

        // One trip round: A's allpass, A's delay and loss, A's second allpass,
        // A's second delay and gain, then the same again through B, and B's
        // output is what closes the loop. The body hands back the four node
        // signals alongside the feedback signal so the taps can read from
        // inside the circulation; `project` throws the four away again before
        // they reach the feedback input.
        body(fb) = fbout, sA1, sA2, sB1, sB2
        with {
            sA1   = (fb + ginj(0)) : gap(gapA1, mod1, density);
            sA2   = sA1 : gdel(gdelA1) : loss(gapA1 + gdelA1) : +(ginj(1)) : gap(gapA2, 0, density*0.72);
            za    = sA2 : gdel(gdelA2) : *(ggain(gapA2 + gdelA2));
            sB1   = (za + ginj(2)) : gap(gapB1, mod2, density);
            sB2   = sB1 : gdel(gdelB1) : loss(gapB1 + gdelB1) : +(ginj(3)) : gap(gapB2, 0, density*0.72);
            fbout = sB2 : gdel(gdelB2) : *(ggain(gapB2 + gdelB2));
        };
        project = _, !, !, !, !;
        keep    = !, si.bus(4);

        gdel(msec)        = de.fdelay5(MAXGDELD, ms2samp(msec * tsize));
        gap(msec, m, g)   = fi.allpass_fcomb5(MAXGAPD, ms2samp(msec * tsize) + m, -g);

        // Modulation goes on the first allpass of each half, at two unrelated
        // rates so the halves never drift together.
        mod1 = ms2samp(moddepth * os.osci(0.93 * modrate));
        mod2 = ms2samp(moddepth * os.osci(1.31 * modrate));

        // Per-segment loop gain, so the four gains multiply out to exactly the
        // T60 the knob asks for. Same structural stability argument as the FDN:
        // every factor round the loop is below unity at every frequency.
        ggain(msec) = exp(-LN1000 * msec * tsize / 1000.0 / decay);

        // Two shelves per trip, so each supplies half the total bass boost.
        glfb = exp(-LN1000 * GLOOPMS * tsize / 1000.0 / decay
                   * (1.0/bassmult - 1.0) / 2.0);
        loss(msec) = fi.lowpass(1, hfdamp)
                   : fi.low_shelf1_l(glfb, bassfreq)
                   : *(ggain(msec));

        taps(a1, a2, b1, b2) = tl, tr
        with {
            tp(sig, msec) = de.fdelay(MAXGDELD, ms2samp(msec * tsize), sig);
            tl = ( tp(b1,  8.9) + tp(b1, 31.7) - tp(b2, 12.3) + tp(b2, 41.1)
                 + tp(a1, 22.6) - tp(a2, 17.9) + tp(a1, 61.3) ) * GTAPNORM;
            tr = ( tp(a1, 11.3) + tp(a1, 37.9) - tp(a2,  9.7) + tp(a2, 48.7)
                 + tp(b1, 26.9) - tp(b2, 21.3) + tp(b1, 63.7) ) * GTAPNORM;
        };
    };

    stereoWidth(w) = _,_ <: (*(a),*(b) :> _), (*(b),*(a) :> _)
    with {
        a = 0.5 * (1 + w);
        b = 0.5 * (1 - w);
    };
};



// hfLimit

hflim_amount = uiBottomRight(hslider("[21]De-Ess[style:knob][unit:%][symbol:deess_amount][label:De-Ess][accentcolor:02]", 0, 0, 100, 1)) / 100;
hflim_meter  = uiMeters(hbargraph("[1]HFlim Reduction[unit:dB][symbol:deess_meter]", 0, 30));


// --- High Frequency Limiter ---
// Ported from vocalDoubler.dsp. Feeds the wet path only — it sits inside the
// dry/wet mixer's wet branch, so the dry half always passes through
// untouched and this can never dull the original signal.
//
// Level-independent: splits the input into a low ("body") band and a
// high band, then compares their envelopes as a ratio (dB difference)
// instead of the high band's absolute level. A quiet "s" in a quiet
// passage still spikes that ratio, so detection doesn't depend on overall
// loudness the way a plain high-band compressor does.

// One macro control drives all four parameters. To retune the feel, edit
// the endpoint pairs below: the first value is what the parameter is at
// Intensity 0%, the second at 100%, interpolated linearly in between.
// Nothing else needs touching.
hfLimSplitAt0  = 5000;  hfLimSplitAt100  = 4500;  // Hz   - crossover; lower reaches further down into the "sh" range
hfLimThreshAt0 =   -2;  hfLimThreshAt100 =   -14; // dB   - how far the high band must stick out before it counts
hfLimRatioAt0  =    2;  hfLimRatioAt100  =     8; //      - how hard the excess is squeezed
hfLimRangeAt0  =    0;  hfLimRangeAt100  =    18; // dB   - ceiling on total reduction; 0 at the bottom makes 0% a true bypass

lerp(a, b, t) = a + (b - a) * t;

// Defaults to 0, i.e. a true bypass, because a chorus is not a vocal-only
// box — every existing patch keeps sounding exactly as it did until this is
// turned up. (vocalDoubler ships it at 50.)


hflim_split  = lerp(hfLimSplitAt0,  hfLimSplitAt100,  hflim_amount);
hflim_thresh = lerp(hfLimThreshAt0, hfLimThreshAt100, hflim_amount);
hflim_ratio  = lerp(hfLimRatioAt0,  hfLimRatioAt100,  hflim_amount);
hflim_range  = lerp(hfLimRangeAt0,  hfLimRangeAt100,  hflim_amount);

//hflim_split = uiDeEss(hslider("[01]Crossover Frequency[style:knob][unit:Hz][scale:log][symbol:crossover_frequency][label:Crossover][accentcolor:02]", 5000,3000,8000,1));

// Relative (100%) vs. absolute (0%) detection, continuously blendable.
// Relative: the high band is measured against the body band, so the threshold
//   is a spectral-tilt difference and detection is level-independent — a quiet
//   "s" in a quiet passage trips it just as readily as a loud one.
// Absolute: the high band is measured against 0 dBFS, so the threshold is a
//   plain level — a level-dependent high-band compressor, which follows the
//   singer's dynamics instead of ignoring them.
// In between, the reference and the threshold are mixed by the same amount, so
// the knob sweeps without a jump at either end.
hflim_mode = 1; //uiDeEss(hslider("[02]Mode[style:knob][unit:%][symbol:mode][label:Abs/Rel][accentcolor:05]", 100, 0, 100, 1)) / 100;

// Two thresholds, because the two modes measure different things and a single
// number cannot mean both. Each keeps its own value and its own useful range;
// the Mode knob lerps between them, so turning Mode never leaves the threshold
// in the wrong units and turning it back restores exactly what was dialled in.
hflim_threshAbs = uiDeEss(hslider("[03]Threshold Absolute[unit:dB][style:knob][symbol:threshold_abs][label:Thresh Abs][accentcolor:01]",-30,-60,0,1));
hflim_threshRel = uiDeEss(hslider("[04]Threshold Relative[unit:dB][style:knob][symbol:threshold][label:Thresh Rel][accentcolor:01]",-10,-30,0,1));
//hflim_thresh    = lerp(hflim_threshAbs, hflim_threshRel, hflim_mode);

//hflim_ratio = uiDeEss(hslider("[05]Ratio[symbol:ratio][style:knob][label:Ratio][accentcolor:03]", 1, 1, 20, 1));
//hflim_range = uiDeEss(hslider("[06]Range[unit:dB][style:knob][symbol:range][label:Range][accentcolor:04]",6, 0, 20,1));

// Solo the band the de-esser acts on, with the reduction applied, so the
// crossover and threshold can be set by ear: sweep Crossover until the "s"
// dominates what you hear and the vowels drop away, then set Threshold /
// Ratio until only the "s" ducks. Expect a large level drop when engaging --
// it is a monitoring switch, not a mix control. Smoothed to cross-fade rather
// than hard-switch, so toggling it while playing does not click.
hflim_listen = uiDeEss(checkbox("[07]Listen[symbol:listen][label:Listen]
      [tooltip: Monitors the high band alone, with the de-essing applied, for setting Crossover and Threshold by ear. Turn off before printing]")) : si.smoo;

// Stereo, unlike the mono original. Detection is *linked*: one gain, derived
// from the mono sum, drives both channels. Two independent detectors would
// duck the channels by different amounts on the same sibilant and swing the
// stereo image with every "s" — the one thing a widener must not do.
hfLimit(l, r) = attach(outL, reductionDb : hflim_meter), outR
with {
    // Detection runs on the mono sum only: the gain is linked, and since the
    // reduction is applied by a shelf rather than rebuilt from the bands, the
    // per-channel split is not needed at all.
    //
    // A real highpass, not `mono - lowpass`. Subtracting a Butterworth lowpass
    // does not give a Butterworth highpass: B(s)-1 has a single zero at DC, so
    // the complement rolls off at 6 dB/oct no matter what order the lowpass is,
    // and it overshoots at the corner. Measured against a 5 kHz split, that
    // "high band" was only -6 dB at 1 kHz, -0.1 dB at 2 kHz and +4.7 dB at
    // 5 kHz -- i.e. the detector was fed most of the vowel range plus a
    // resonant bump, so a plain 2.5 kHz tone pulled 1.9 dB of reduction. The
    // true 4th-order highpass is -33 dB at 2 kHz and -57 dB at 1 kHz.
    //
    // The two bands no longer need to be complementary: nothing reconstructs
    // the signal from them any more, they only feed the envelope followers.
    mono = (l + r) * 0.5;
    low  = fi.lowpass(4, hflim_split, mono);
    high = fi.highpass(4, hflim_split, mono);

    // Floored at -120 dB: on digital silence the follower reaches exactly 0,
    // and ba.linear2db(0) is -inf — which turns into NaN both in the relative
    // subtraction (-inf - -inf) and when the mode blend scales it by 0.
    env(x) = an.amp_follower_ar(0.001, 0.03, x) : max(ba.db2linear(-120)) : ba.linear2db;

    hiDb  = env(high);
    refDb = env(low);

    // dB the high band sticks out above its reference; only the excess over
    // threshold is limited. The reference is the body band scaled by the mode
    // blend: at 100% it is the full body level (relative — spectral tilt, level
    // independent), at 0% it is 0 dBFS (absolute — plain high-band level).
    // hflim_thresh is lerped by the same knob, so both sides of this comparison
    // cross-fade together.
    diff   = hiDb - refDb * hflim_mode;
    excess = max(0, diff - hflim_thresh);

    reductionDb = min(excess * (1 - 1 / hflim_ratio), hflim_range);
    gr = ba.db2linear(0 - reductionDb);

    // The reduction is applied as a real high shelf on the full-band signal,
    // not by re-summing a split. Rebuilding from a 4th-order split (low +
    // high*gr) is a shelf too, but an accidental one: the lowpass and its
    // complement differ in phase, so away from unity gain they no longer sum
    // flat and the response ripples around the corner.
    //
    // A TPT state variable filter: the structure is designed for exactly this,
    // coefficients that move every sample. At 0 dB the shelf mix collapses to
    // (1,0,0), so an idle de-esser passes the signal through untouched -- no
    // phase shift to comb against a dry path. The cost is one pow and one sqrt
    // per sample; tan(fc) depends only on hflim_split, so Faust hoists it out
    // of the sample loop.
    //
    // Second order, so gentler than a 3rd-order shelf: at a 5 kHz corner and
    // -12 dB it is -6.0 dB at the corner and still -1.6 dB down at 3 kHz.
    // Raise Q to confine the cut closer to the corner.
    //shelf = fi.highshelf(3, 0 - reductionDb, hflim_split);
    shelf = fi.svf.hs(hflim_split, 0.7, 0 - reductionDb );

    // Listen solos the detector's high band with the reduction applied. It is
    // mono because detection is mono-linked -- this is literally the signal the
    // detector measures, which is what makes it useful for setting Crossover.
    outL = lerp(l : shelf, high * gr, hflim_listen);
    outR = lerp(r : shelf, high * gr, hflim_listen);
};