declare author "Klaus Scheuermann";
declare description "";
declare license "GPL-3.0-or-later";
declare name "Flanger";
declare unique_id "LAfl";

// declare drywet "true";

import("stdfaust.lib");

// Two flangers behind one Mode switch, sharing the tone controls, the width
// control and the mix at the end.
//
// Clean: the standard pf.flanger_stereo — one delay line per channel, both
//   swept by a quadrature LFO pair (sine left, cosine right). Ninety degrees
//   apart is what makes it a stereo flanger rather than two mono ones: the
//   comb notches walk across the image instead of sitting in the same place on
//   both sides. Delay time is Offset + Delay * (1 + lfo)/2, so Offset sets
//   where the sweep starts and Delay how far it travels, and the sweep is
//   linear in milliseconds.
//
//   Depth and Dry-Wet are not the same control here. pf.flanger_mono is itself
//   a dry+wet sum — it mixes the delayed copy back against its input at ±depth
//   and halves the result — so Depth sets how deep the comb notches cut, i.e.
//   the character of the comb. Dry-Wet is the ordinary mix wrapped around the
//   whole effect, and only changes how much of that character you hear.
//
// BBD: a bucket-brigade stompbox flanger in the MXR M117 / Electric Mistress /
//   A/DA lineage. Not the same topology with different numbers — a separate
//   comb, hand-written because the analog character all lives *inside* the
//   delay path and inside the feedback loop, where pf.flanger_stereo has no
//   room for it. See the section comment down at the engine for what is
//   modelled and why each piece is audible.
//
//   Where the two modes differ in how they are driven: the BBD engine is pure
//   wet and has no internal dry leg, so Dry-Wet *is* its flange depth and the
//   comb is deepest at the 50% detent. Clean cannot work that way —
//   pf.flanger_stereo sums its own dry inside, so Clean still combs at Dry-Wet
//   100% and Depth is what sets its ratio. One consequence worth knowing about
//   before switching modes mid-mix: at the same Dry-Wet setting BBD is quieter,
//   by about 4 dB at the 50% detent (4.3 on white noise, 4.0 on pink-weighted),
//   because only 0.707 of the dry signal reaches its output where Clean
//   passes 1.22.
//
// Barberpole: Shepard-tone flanging, where the notches climb (or fall) forever
//   without ever arriving. Not a swept comb at all but a stack of four of them,
//   staggered and crossfaded so that each one only ever reaches the end of its
//   travel while silent. Pure wet like BBD, and inverted like both the others.
//   Its Dry-Wet does behave slightly differently from BBD's at the top of the
//   travel: with no dry leg there is still a comb, because the four taps sit at
//   different delays and interfere with each other, so 100% is a thinner
//   version of the effect rather than the plain vibrato BBD gives you there.
//
//   All three modes comb *subtractively* — see the note at bbdEngine for why
//   that is what Clean does and why the other two invert their wet legs to
//   match it.

/* Grey-out list — which controls actually reach the output, per mode.
   Verified by measurement, not by reading: '.' means the rendered output is
   bit-identical with the control at either end of its range, so the UI can
   disable it there with no audible consequence.

   Rows follow the order the controls appear in the UI, listed with the [n]
   index each one declares, groups themselves in index order. As in the Vocal
   Doubler and the Chorus, Stage Bottom Left and Stage Bottom Right both
   declare [1], so their indices do not decide which comes first; the order
   below is the one the generated UI actually produces, with Left ahead of
   Right.

                                Clean    BBD   Barber
    Mode [0]
    Clean [0]
      [01] delay                  o       .       .
      [02] delay_offset           o       .       .
      [03] speed                  o       .       .
      [04] depth                  o       .       .
      [05] feedback               o       .       .
    BBD [1]
      [11] bbd_manual             .       o       .
      [12] bbd_width              .       o       .
      [13] bbd_rate               .       o       .
      [14] bbd_regen              .       o       .
      [15] bbd_color              .       o       .
      [16] bbd_drive              .       o       .
    Barberpole [2]
      [21] bp_low                 .       .       o
      [22] bp_span                .       .       o
      [23] bp_rate                .       .       o
      [24] bp_direction           .       .       o
      [25] bp_resonance           .       .       o
    Stage Bottom Right [1] — global
      [31] hp_freq                o       o       o
      [32] lp_freq                o       o       o
      [33] stereo_width           o       o       o
      [34] drywet                 o       o       o

   Each mode's section is dead in the other two: the select3 after the three
   engines discards the unselected branches whole. The four global rows are
   live everywhere, because the tone filters, Width and the mixer sit after
   that select rather than inside any one engine.

   Two grey-out rules that are not the mode:

   Depth at 0 kills the whole Clean delay section. pf.flanger_mono multiplies
      its delayed leg by ±depth before the sum, so at Depth 0 delay,
      delay_offset, speed and feedback are all measurably inert — the delay
      line cannot reach the output at all, and feedback has nothing to feed
      back into it however hard it is driven. Clean at Depth 0 is a highpass, a
      lowpass and a width control on the dry signal.

   Sweep Width at 0 kills bbd_rate, and nothing else. The LFO still runs, it
      just has nothing to scale, so the BBD comb stands still at whatever
      Manual asks for — the Electric Mistress "filter matrix" sound, a static
      comb you tune by hand. Manual, Regen, Color and Drive all stay live.

   Barberpole has no such rule — every one of its five controls was measured
      live at every setting of the other four. Rate at its minimum comes
      closest, but a near-stationary stack of four combs an octave apart is
      still four combs, and Direction still decides which way the crawl goes.

   Both tables assume Dry-Wet above 0. At 0 the wet branch is muted outright
   and every row above goes dead, the plugin being a dry pass-through there.
   Dry-Wet is smoothed, so a move to 0 leaks a short flanged tail on the way —
   that is a steady-state statement, not an instantaneous one.

   The other end of that knob is not symmetric, and differs per mode. At 100%
   the dry branch is muted, and what that costs depends on where the mode keeps
   its dry. BBD has none of its own, so its comb disappears entirely and the
   effect becomes a vibrato. Clean carries its dry inside pf.flanger_stereo and
   still combs. Barberpole has no dry either, but its four taps sit at
   different delays and comb against *each other*, so it keeps a shallower
   version of the effect rather than losing it. Nothing greys out in any of the
   three — every control still shapes what is left.
*/

//======================= UI groups =======================

uiTop(x)         = hgroup("[0]Stage Top", x);
uiBottom(x)      = hgroup("[8]Stage Bottom", x);
uiBottomLeft(x)  = uiBottom(vgroup("[1]Stage Bottom Left", x));
uiBottomRight(x) = uiBottom(hgroup("[1]Stage Bottom Right", x));
uiMeters(x)      = hgroup("[9]", x);

uiClean(x) = uiBottomLeft(hgroup("[0]Clean", x));
uiBbd(x)   = uiBottomLeft(hgroup("[1]BBD", x));
uiBarber(x)= uiBottomLeft(hgroup("[2]Barberpole", x));

//======================= Mode =======================

mode = uiTop(nentry("[0]Mode[symbol:mode][style:radio{'Clean':0;'BBD':1;'Barberpole':2}]", 0, 0, 2, 1)) : int;

//======================= Clean controls =======================

delayMs  = uiClean(hslider("[01]Flange Delay[style:knob][unit:ms][symbol:delay][label:Delay][requires:mode:0][accentcolor:02][bracket:DELAY]", 10, 0, 20, 0.001)) : si.smoo;
offsetMs = uiClean(hslider("[02]Delay Offset[style:knob][unit:ms][symbol:delay_offset][label:Offset][requires:mode:0][accentcolor:02][bracket:DELAY]", 1, 0, 20, 0.001)) : si.smoo;
speed    = uiClean(hslider("[03]Speed[style:knob][unit:Hz][symbol:speed][label:Speed][requires:mode:0][accentcolor:03][bracket:LFO]", 0.5, 0.01, 5, 0.0001));
depth    = uiClean(hslider("[04]Depth[style:knob][symbol:depth][label:Depth][requires:mode:0][accentcolor:03]", 0.5, 0, 1, 0.001)) : si.smoo;
fb       = uiClean(hslider("[05]Feedback[style:knob][symbol:feedback][label:Feedback][requires:mode:0][accentcolor:05]", 0, -0.999, 0.999, 0.001)) : si.smoo;

//======================= BBD controls =======================

// Manual is the *bottom* of the sweep, as on the hardware, where it sets the
// BBD clock and the sweep only ever climbs from there.
bbd_manual = uiBbd(hslider("[11]BBD Manual[style:knob][unit:ms][scale:log][symbol:bbd_manual][label:Manual][requires:mode:1][accentcolor:02]", 0.5, 0.1, 10, 0.01)) : si.smoo;
bbd_width  = uiBbd(hslider("[12]BBD Sweep Width[style:knob][unit:%][symbol:bbd_width][label:Sweep][requires:mode:1][accentcolor:03][bracket:SWEEP]", 70, 0, 100, 1)) / 100 : si.smoo;
bbd_rate   = uiBbd(hslider("[13]BBD Rate[style:knob][unit:Hz][scale:log][symbol:bbd_rate][label:Rate][requires:mode:1][accentcolor:03][bracket:SWEEP]", 0.3, 0.02, 8, 0.001));
bbd_regen  = uiBbd(hslider("[14]BBD Regen[style:knob][symbol:bbd_regen][label:Regen][requires:mode:1][accentcolor:05]", 0.3, -0.95, 0.95, 0.001)) : si.smoo;
bbd_color  = uiBbd(hslider("[15]BBD Color[style:knob][unit:Hz][scale:log][symbol:bbd_color][label:Color][requires:mode:1][accentcolor:06]", 6000, 1000, 16000, 1)) : si.smoo;
bbd_drive  = uiBbd(hslider("[16]BBD Drive[style:knob][unit:%][symbol:bbd_drive][label:Drive][requires:mode:1][accentcolor:05]", 25, 0, 100, 1)) / 100 : si.smoo;

//======================= Barberpole controls =======================

// Low and Span are the two ends of the sweep the taps march through: the
// shortest delay any tap ever reaches, and how many octaves above it the
// longest one sits. Span is what sets the *pitch spacing* of the notch
// families, since with NBP taps evenly spread they end up Span/NBP octaves
// apart; at the default 4 octaves over 4 taps that is exactly one octave.
bp_low  = uiBarber(hslider("[21]BARBER Low[style:knob][unit:ms][scale:log][symbol:bp_low][label:Low][requires:mode:2][accentcolor:02][bracket:RANGE]", 0.4, 0.2, 2, 0.01)) : si.smoo;
bp_span = uiBarber(hslider("[22]BARBER Span[style:knob][unit:oct][symbol:bp_span][label:Span][requires:mode:2][accentcolor:02][bracket:RANGE]", 4, 1, 5, 0.1)) : si.smoo;
bp_rate = uiBarber(hslider("[23]BARBER Rate[style:knob][unit:Hz][scale:log][symbol:bp_rate][label:Rate][requires:mode:2][accentcolor:03][bracket:SWEEP]", 0.25, 0.02, 4, 0.001));
bp_dir  = uiBarber(hslider("[24]BARBER Direction[style:knob][symbol:bp_direction][label:Direction][requires:mode:2][accentcolor:03][bracket:SWEEP]", 1, 0, 1, 1)) : int;
bp_fb   = uiBarber(hslider("[25]BARBER Resonance[style:knob][symbol:bp_resonance][label:Resonance][requires:mode:2][accentcolor:05]", 0.2, -0.85, 0.85, 0.001)) : si.smoo;

//======================= Global controls =======================

hp_freq  = uiBottomRight(hslider("[31]HighPass[style:knob][unit:Hz][scale:log][symbol:hp_freq][label:HighPass][accentcolor:06][bracket:TONE]", 20, 20, 20000, 1)) : si.smoo;
lp_freq  = uiBottomRight(hslider("[32]LowPass[style:knob][unit:Hz][scale:log][symbol:lp_freq][label:LowPass][accentcolor:06][bracket:TONE]", 20000, 20, 20000, 1)) : si.smoo;
width    = uiBottomRight(hslider("[33]Stereo Width[style:knob][unit:%][symbol:stereo_width][label:Width][accentcolor:04]", 100, 0, 200, 1)) / 100;
drywet   = uiBottomRight(hslider("[34]Dry-Wet[style:knob][unit:%][symbol:drywet][label:Dry-Wet][accentcolor:01][easy]", 50, 0, 100, 1)) / 100 : si.smoo;

// FIXME: this should be an amplitude-response display, i.e. where the comb
// notches currently sit, not what the LFO is doing. Until then it is at least
// a movement indicator, following whichever mode is selected: the two LFOs are
// in quadrature, so their sum traces a sine of amplitude sqrt(2) — hence the
// +/-1.5 range rather than +/-1.
flangeview = select3(mode, lfoR(speed) + lfoL(speed),
                           lfoR(bbd_rate) + lfoL(bbd_rate),
                           (bpDirPhase * 2 - 1) * 1.4)
           : uiMeters(hbargraph("[1]Flange LFO[symbol:lfo_meter]", -1.5, +1.5));

//======================= Shared =======================

// Quadrature pair from one oscillator: oscrs is the sine output, oscrc the
// cosine, both from the same recursive resonator and therefore rate-locked.
lfoL = os.oscrs;
lfoR = os.oscrc;

// Delay buffer, in samples. Clean's Offset and Delay reach 20 ms each, so the
// read pointer can ask for 40 ms — 7680 samples at 192 kHz. The old 2048
// covered that only up to 48 kHz and silently wrapped the line above it. BBD
// is capped well below this.
dmax = 8192;

//======================= Clean engine =======================

// Floored at one sample: fdelay interpolates between two taps and needs a
// whole sample to interpolate across. Offset at 0 with the LFO at its trough
// asks for exactly zero delay, which is inside the range the UI allows.
curdelL = max(1, (offsetMs + delayMs * (1 + lfoL(speed)) / 2) * 0.001 * ma.SR);
curdelR = max(1, (offsetMs + delayMs * (1 + lfoR(speed)) / 2) * 0.001 * ma.SR);

// Not exposed: inverting the flange sum swaps which frequencies get the peaks
// and which get the notches. It is a real variation, but it reads as a tone
// change rather than a control, and one more switch is not worth it.
invert = 0;

// Summing a signal with a delayed copy of itself peaks at up to +6 dB where
// they align, and how much of that survives depends on Depth. This pulls the
// output back down by the amount Depth put in, so turning Depth up changes the
// comb without also changing the level.
comp      = 0.375;
levelComp = 1 / (1 + depth * comp);

// pf.flanger_mono halves its own dry+wet sum, so the input is doubled going in
// to bring the effect back to unity gain — measured at +0.003 dB on a 1 kHz
// tone at Depth 0 and Dry-Wet 100%, the residue being the 20 Hz highpass.
cleanEngine = (_*2, _*2)
            : pf.flanger_stereo(dmax, curdelL, curdelR, depth, fb, invert)
            : (*(levelComp), *(levelComp));

//======================= BBD engine =======================
// A bucket-brigade flanger, i.e. an analog delay line clocked by a VCO with a
// companding noise-reduction loop wrapped around it. Four things separate it
// from the Clean engine, and all four are inside the delay path or the
// feedback loop rather than around them:
//
//   Exponential sweep. A BBD's delay is stages / (2 * clock), so a VCO swept
//     over its range moves the delay in *ratio*, not in milliseconds. That is
//     why an analog flanger sounds even across its whole sweep where a linear
//     one bunches up at the long end and races through the short one. Manual
//     sets the bottom of the sweep and Sweep Width how many octaves it climbs.
//
//   Limited bandwidth. The anti-alias filter in front of the line and the
//     reconstruction filter after it are the reason the wet path of an analog
//     flanger is audibly duller than its dry. Color is their shared corner.
//     The front one is inside the feedback loop, so each regeneration comes
//     back darker than the last instead of piling up an ice-pick resonance —
//     which is also what keeps Regen usable near its ends.
//
//   Companding. An NE570-style 2:1 compressor in front of the line and a 1:2
//     expander after it, to keep the signal above the BBD's noise floor. Most
//     of what it contributes is dynamic, because the pair nearly cancels once
//     things settle: measured against a bypass, the residual sits 60 dB below
//     the signal on a steady 1 kHz tone and 69 dB at 5 kHz. On a +40 dB step
//     it is only 16 dB down — the expander is deriving its gain from a signal
//     that has already been through the delay line, so for one envelope's
//     worth of time it is still applying the previous moment's correction and
//     overshoots. That is the thump you hear when a snare goes through an
//     analog flanger.
//
//     Two things to know about it. The cancellation is worst low down — 41 dB
//     at 100 Hz — because the follower ripples at twice the signal frequency
//     and 3 ms of attack is not slow next to a 100 Hz period. Real companders
//     have that same failure for the same reason, though these time constants
//     are not fitted to any particular chip. And only half the real effect is
//     here: there is no noise floor to be pumped, so the "breathing hiss" side
//     of companding is absent. The transient behaviour is the part worth
//     having, and the part that survives into a mix.
//
//   Soft saturation. The BBD stages compress and then clip as they are driven
//     harder. Modelled symmetrically with a tanh, which the real thing is not
//     — the even-harmonic half of BBD grit is missing. Drive is the amount,
//     placed after the delay and inside the loop so regeneration compounds it.
//     At 0 it is bypassed exactly, not just gently.
//
//     Behind it and always on sits the supply rail, which is a separate thing
//     from the Drive trim and is not optional: without it Regen near its ends
//     rings the comb up far past the point of being usable. See softRail.
//
//     Note the interaction with the compander in front of it: the compressor
//     pulls everything toward full scale, so Drive bites about as hard on a
//     quiet passage as on a loud one. That is the circuit's behaviour, not an
//     oversight — it is why analog flangers sound grainy at any input level.

// How far the sweep climbs above Manual, at Sweep Width 100%. Four octaves is
// wide for a flanger and matches the A/DA end of the range rather than the
// tamer stompboxes; Sweep Width is what dials it back.
bbdOctaves = 4;

// Ceiling on the swept delay. Above roughly this the first notch has dropped
// below the fundamental of most material and it stops reading as flanging and
// starts reading as slapback. Manual and Sweep Width therefore interact, as
// they do on the hardware: turning Manual up eats into the sweep the ceiling
// leaves available.
bbdMaxMs = 20;

bbdDelaySamp(lfo) = max(1, min(bbdMaxMs, bbd_manual * (2.0 ^ (bbdOctaves * bbd_width * (1 + lfo) / 2)))
                           * 0.001 * ma.SR);

// Compander. Floored at -50 dB so the compressor's makeup gain tops out at
// +25 dB rather than running away on silence, and so the expander cannot pull
// a fade all the way down to nothing.
bbdEnvFloor = ba.db2linear(-50);
bbdEnv = an.amp_follower_ar(0.003, 0.060) : max(bbdEnvFloor);

// 2:1 in dB going in (gain = 1/sqrt(level)), 1:2 coming out (gain = level).
// The two multiply back to 1 on anything steady, to within the follower's own
// ripple; see the section comment for the measured residuals and for why they
// do not cancel at all on a transient.
bbdCompress(x) = x / sqrt(bbdEnv(x));
bbdExpand(x)   = x * bbdEnv(x);

// Crossfaded against the clean signal so that Drive 0 is a true bypass — a
// bare tanh is already ~0.7 dB down and slightly soft at half scale, which
// would make "no drive" a tone setting rather than an off position.
//
// The gain range is the whole design of this control. tanh(x*g)/g holds its
// small-signal gain at 1 but clamps everything above the knee at 1/g, so a
// large g is not "more saturation", it is a brickwall limiter: at the g = 16
// this originally used, full Drive measured 39.6% THD but cost 26 dB, which is
// why Drive read as a volume control with a tone side-effect. g = 4 was picked
// by measuring both together — 24.8% THD for 7.8 dB, still plainly gritty, and
// little enough loss that bbdDriveComp can put it back without the makeup
// becoming absurd. The steps either side were 12.0% THD at 2.9 dB (g = 2) and
// 35.0% at 16.0 dB (g = 8).
//
// Its slope never exceeds 1 anywhere, which is what keeps it legal inside the
// feedback loop; the makeup that undoes it has to live outside, and does.
bbdSat(x) = x * (1 - bbd_drive) + (ma.tanh(x * g) / g) * bbd_drive
with {
    g = 1 + bbd_drive * 3;
};

// Soft rail. Used by both feedback engines: the BBD loop needs it whatever the
// Drive trim is set to, and the Barberpole loop needs it for the same reason. Regen near its ends is a resonator: a comb peak
// rings up toward 1/(1 - regen), i.e. 20x at 0.95, and the expander on the way
// out then multiplies by the level it finds, so it squares that. Measured
// before this was added, percussive material at Regen 0.95 came out 29x the
// input peak — bounded, not a runaway, but still an unusable noise.
//
// Shaped so it does nothing until it has to: within 0.06 dB of unity below
// 0.7, which is where the compressed loop signal normally sits, and asymptotic
// to 1 above. The reconstruction lowpass sits after it and takes the edge off
// the harmonics it generates, which is the order the hardware has too.
//
// x^8 is guarded because it is evaluated in single precision: without the
// clamp an absurd input (beyond +240 dBFS at this point) overflows to inf and
// the divide silently mutes the line instead of limiting it.
softRail(x) = x / ((1 + min(1e30, s*s*s*s)) ^ 0.125)
with {
    s = x * x;
};

// Regen level compensation. A feedback comb is a resonator, so turning Regen
// up does not just deepen the effect, it makes the whole thing louder — with
// this off, pink noise through the wet path measured +11.4 dB at Regen 0.95
// against Regen 0, and dense music-like material +12.2 dB. That is a fader
// move disguised as a character control, which is the wrong thing for a knob
// to do.
//
// It has to be asymmetric, which is the part that is not obvious. Positive
// Regen puts a comb *peak* at DC and at every multiple of 1/T, right where
// program material keeps most of its energy; negative Regen puts a null there
// instead and only peaks in between. So the same |Regen| costs more level
// going up than going down: with the saturator idle, +15.1 dB at +0.95 against
// +11.9 dB at -0.95 on pink noise, and +17.5 / +13.2 on dense material.
// Scaling the negative side by 0.80 before the curve is applied lines the two
// halves up.
//
// The curve itself is a power law in dB, fitted by least squares to rendered
// output across thirteen Regen settings and three signals. Textbook comb
// normalisation, sqrt(1 - g^2), was fitted too and came out worse — it assumes
// a plain feedback comb, and this loop has a rail, a compander and a saturator
// in it. A plain parabola was tried as well and needed the extra 0.3 of
// exponent to follow the steep top of the range.
//
// Measured residual after compensation, at the default Drive: within 2.4 dB of
// flat across the whole knob on pink noise and 2.2 dB on dense material,
// against a 17 dB spread before. At the 50% Dry-Wet detent, where the dry leg
// dilutes it, within 0.8 dB.
//
// One caveat worth knowing. How much a comb rings up depends on how sustained
// the input is, so no static curve can serve every source. Sparse percussive
// material barely builds up at all (+1.5 dB at Regen 0.95 uncompensated), so
// it now ends up about 8 dB *down* at the top of the travel. That is the
// deliberate trade: the curve is fitted to the material that caused the
// problem, not to the material that never had it.
// Drive level compensation, which has to be solved together with the Regen one
// because the saturator sits inside the loop and therefore costs level twice.
// Once directly, on the way through — measured -6.9 dB at Drive 100% with
// Regen at 0, again a clean parabola in the knob. And once indirectly, by
// lowering the loop gain, which takes the resonance down with it: at Regen 0.9
// the same Drive move cost -18.7 dB rather than -6.9.
//
// The second half is what makes a plain makeup gain insufficient, and it has a
// tidy fix. The Regen compensation is told what the feedback has actually been
// reduced *to* — bbd_regen scaled by the saturator's measured gain — instead of
// what the knob says, so it stops over-compensating a resonance that the
// saturator already removed. Measured worst residual across Regen -0.6..+0.6
// then falls from 5.0 dB to 2.1 dB, and Regen 0.9 from -10.7 dB to -3.1 dB.
//
// The makeup constant is fitted jointly with that coupling in place, so it is
// slightly larger than the raw -6.9 dB through-loss.
//
// Measured residual after both, on pink noise at full Drive: +1.6 dB at Regen
// 0, +0.5 at the default 0.3, -0.1 at 0.6 and +1.2 at 0.9 — against -6.9 to
// -18.7 dB before.
//
// Same caveat as everywhere a saturator is compensated statically: how much
// level it costs depends on how hard it is hit, and the compressor in front
// only halves that dependence rather than removing it. A signal 20 dB below
// nominal barely reaches the knee, loses only 1.7 dB of its own, and so ends
// up +7.7 dB hot at full Drive; sparse percussive material goes the other way,
// -5.1 dB. Hardware has the same level dependence, and the knob is right there
// — but it is the one place the compensation cannot follow.
bbdRegenNegScale = 0.80;  //      how much less the negative side builds
bbdRegenCompDb   = 17.3;  // dB   cut at |Regen| = 1
bbdRegenExp      = 2.30;  //      curvature of that cut
bbdSatLossDb     = 6.9;   // dB   measured through-loss at Drive 100%, Regen 0
bbdDriveCompDb   = 8.5;   // dB   makeup at Drive 100%

// What the saturator is really doing to the loop, not what the knob says.
bbdSatGain   = ba.db2linear(0 - bbdSatLossDb * bbd_drive * bbd_drive);
bbdDriveComp = ba.db2linear(bbdDriveCompDb * bbd_drive * bbd_drive);

bbdRegenEff  = (max(bbd_regen, 0) - min(bbd_regen, 0) * bbdRegenNegScale) * bbdSatGain;
bbdRegenComp = ba.db2linear(0 - bbdRegenCompDb * (bbdRegenEff ^ bbdRegenExp));

// One bucket-brigade line: the regeneration loop, with the compander wrapped
// around the *outside* of it. fdelay's one-sample floor is what makes the loop
// legal for Faust; it is enforced up in bbdDelaySamp.
//
// The compander must not be inside the loop, and this is not a stylistic
// preference — it blows up. An expander's gain rises with level, so a 1:2
// expander in a feedback path is positive feedback in the level domain: a
// louder pass returns more gain, which makes the next pass louder still. It
// was measured running away to +300 dB and then to NaN on percussive material
// at Regen 0.9, with Drive sitting at zero the whole time. Drive was hiding
// it, not causing it: at high Drive the tanh clamps the loop level and holds
// the thing together, so *lowering* Drive was what set it off.
//
// With the loop containing only two lowpasses, a delay and a saturator — every
// one of them gain <= 1 — the loop gain cannot exceed |Regen|, and the engine
// is unconditionally stable. What it costs is that regeneration is no longer
// re-companded on each pass, only on the way in and out. The audible part of
// companding, the transient overshoot, is untouched: the expander is still
// deriving its gain from a signal that has been through the delay line.
bbdVoice(dsamp, x) = x : bbdCompress : (loop ~ *(bbd_regen)) : bbdExpand
with {
    loop = + : fi.lowpass(2, bbd_color)
             : de.fdelay(dmax, dsamp)
             : bbdSat
             : softRail
             : fi.lowpass(2, bbd_color);
};

// The engine is pure wet: no internal dry leg, so the only place dry and
// delayed meet is the Dry-Wet mixer at the end. That makes Dry-Wet the flange
// depth control in this mode — the equal-power crossfade puts both legs at
// 0.707 at the 50% detent, which is where the comb is deepest, and either side
// of that it shallows out. Measured wet/dry against the dry leg: 0.40 at 25%,
// 0.89 at 50%, 0.41 at 75%, and 0.0002 at 100% — i.e. at the top of the travel
// there is no comb left at all, only the delayed signal, which reads as
// vibrato rather than as flanging. Those are at Regen 0; bbdRegenComp trims the
// wet leg as Regen comes up, so the comb shallows a little with it (about a dB
// at the default Regen 0.3, and 10 dB at the ends of that knob).
//
// The null at the 50% detent is 24.7 dB deep, against 73.4 dB for Clean at
// Depth 1. Clean cancels almost perfectly because its wet leg is a plain
// delay; this one has been through a compander, two filters and a rail, so it
// can never be the exact negative of the dry. Real hardware does not null
// perfectly either, and for the same reason.
//
// Two things follow from having no internal dry. The tone filters and Width
// now act on the delayed signal only, which is what the hardware does — a BBD
// flanger's dry path is a clean buffer and never sees the reconstruction
// filter. And there is nothing left to level-compensate, so the old
// bbdLevelComp is gone; the mixer sets the level on its own.
//
// The wet leg is inverted to match Clean's polarity. Clean is a *subtractive*
// comb and not by choice: pf.flanger_mono parses as `_, ((- : fdelay) ~ *(fb))`,
// so `-` takes the feedback on its first input and the signal on its second,
// and with feedback at zero the delayed leg comes out as -x delayed. That is
// what `invert = 0` actually selects, which is the opposite of what the name
// suggests. Measured: Clean at Depth 1 gives dry +0.5022 against delayed
// -0.5014, and its comb nulls at multiples of 1/T rather than peaking there.
// Without this negation BBD summed additively and the two modes emphasised
// opposite frequencies at the same delay setting.
bbdEngine(x, y) = (0 - wetL) * bbdComp, (0 - wetR) * bbdComp
with {
    bbdComp = bbdRegenComp * bbdDriveComp;
    wetL = x : bbdVoice(bbdDelaySamp(lfoL(bbd_rate)));
    wetR = y : bbdVoice(bbdDelaySamp(lfoR(bbd_rate)));
};

//======================= Barberpole engine =======================
// Shepard-tone flanging: the notches appear to climb forever (or fall forever)
// without ever arriving anywhere. Unlike the other two modes this is not a
// swept comb at all — a single delay line cannot do this, because whatever
// goes up has to come back down, and the way back down is audible.
//
// The construction is the Shepard tone's, moved from pitch to delay time.
// NBP delay lines sweep the *same* exponential range, staggered by 1/NBP of a
// cycle, and each is amplitude-windowed so it fades in at one end of its travel
// and out at the other. A tap therefore only ever reaches the end of its sweep
// while silent, which is where it jumps back to the start; the jump is real but
// inaudible. At any moment there are NBP combs sounding at different delays,
// one dying, one being born, and the ear joins them into one endless glide.
//
// The window is sin^2, for a reason worth stating: summed over NBP taps evenly
// spaced in phase it is exactly constant, NBP/2, for any NBP >= 2 — the cosine
// terms cancel. So the total amount of wet signal never fluctuates as the taps
// hand over, which is what stops the effect breathing at the cycle rate.
//
// Direction is not a parameter of the sweep but of the phase: running the
// phasor backwards makes the delays shorten instead of lengthen, and shortening
// delays push the notches up. Up (1, the default) is the classic "endlessly
// rising" sound; note that this is the *reversed* phasor, since a phase that
// advances lengthens the delays and therefore sends the notches down.
//
// Rate at its minimum is nearly a standstill, and that is a usable setting
// rather than a degenerate one: NBP static combs an octave apart is a fixed
// resonator stack, not silence.

NBP    = 4;      // taps. 4 gives one octave of spacing at the default Span
bpDmax = 16384;  // own delay buffers: Low * 2^Span reaches further than Clean
bpMaxMs = 50;    // ceiling, as for BBD — past this it reads as echo, not comb

sq(v) = v * v;
wrap01(x) = x - floor(x);

// One phasor drives every tap; the taps differ only in where they sit on it.
bpPhasor   = os.lf_sawpos(bp_rate);
bpDirPhase = select2(bp_dir, bpPhasor, 1 - bpPhasor);

// ph0 is where this channel sits on the phasor — the two channels are a
// quarter cycle apart, the same quadrature trick the other two modes use, so
// the glide crosses the image instead of moving in lockstep.
bpTaps(ph0) = _ <: sum(i, NBP, tap(i)) : *(bpNorm)
with {
    p(i)   = wrap01(ph0 + i / NBP);
    dms(i) = min(bpMaxMs, bp_low * (2.0 ^ (bp_span * p(i))));
    dsm(i) = max(1, dms(i) * 0.001 * ma.SR);
    win(i) = sq(sin(ma.PI * p(i)));
    tap(i) = de.fdelay(bpDmax, dsm(i)) : *(win(i));
};

// The windows sum to NBP/2, so this brings the stack back to the level of a
// single tap. bpLevel is then the trim against the other two modes, and it
// measured out at unity: at the defaults on pink noise Barberpole sits 0.02 dB
// from BBD at Dry-Wet 25% and 0.28 dB at the 50% detent, widening to 1.0 dB at
// 75% and 1.4 dB at 100% as the dry leg both modes lean on drops away. Left as
// an explicit constant because it is a measured result, not an identity —
// change the tap count or the window and it stops being 1.
bpNorm  = 2.0 / NBP;
bpLevel = 1.0;

// Resonance level compensation, fitted the same way as the BBD one but a
// different shape, because this loop behaves differently. It wraps the whole
// windowed tap stack rather than a single delay, and the taps are mutually
// incoherent, so the feedback never builds the sharp resonance a plain comb
// does: measured rise is only +4.8 dB at +0.85, against the 15 dB the BBD comb
// managed. The negative side does not merely build less, it goes the other
// way and loses 1.3 dB, so the fit is a signed polynomial rather than the
// even-symmetric one Regen needed — this compensation cuts above zero and
// gives a little back below it.
//
// Measured residual afterwards: within 1.0 dB of flat on pink and dense
// material across the whole knob, and within 1.8 dB on sparse percussive
// material and at the 50% Dry-Wet detent.
bpFbCompA = 2.80;   // dB per unit of Resonance
bpFbCompB = 2.15;   // dB per unit squared
bpFbComp  = ba.db2linear(0 - (bpFbCompA * bp_fb + bpFbCompB * bp_fb * bp_fb));

// Resonance, with the rail inside the loop for the same reason the BBD engine
// has one: every element in here is gain <= 1, so the loop gain cannot exceed
// |Resonance| and the engine is unconditionally stable.
bpVoice(ph0) = (loop ~ *(bp_fb))
with {
    loop = + : bpTaps(ph0) : softRail;
};

bpEngine(x, y) = (0 - wetL) * bpComp, (0 - wetR) * bpComp
with {
    bpComp = bpLevel * bpFbComp;
    wetL = x : bpVoice(bpDirPhase);
    wetR = y : bpVoice(wrap01(bpDirPhase + 0.25));
};

//======================= Output stage =======================

// Tone filters sit inside the wet branch of the mixer, so the mixer's dry half
// always passes through untouched. What that means differs by mode: in BBD the
// engine is pure wet, so these shape the delayed signal alone, which is where a
// BBD flanger's reconstruction filter sits too. In Clean, pf.flanger_stereo has
// already summed its own dry leg by this point, so they shape that as well.
tone = fi.svf.hp(hp_freq, 0.707) : fi.svf.lp(lp_freq, 0.707);

// Mid/side widening. At 100% both coefficients are 0.5 and the pair passes
// through unchanged; 0% collapses to mono, 200% doubles the side content.
stereoWidth(w) = _,_ <: (*(a),*(b):>_),(*(b),*(a):>_)
with {
    a = 0.5 * (1 + w);
    b = 0.5 * (1 - w);
};

// Both engines run all the time and the select throws one away, as in the
// Vocal Doubler. Switching modes therefore lands on an engine whose delay
// lines and LFOs are already running rather than on a cold one.
engines = _,_ <: (cleanEngine, bbdEngine, bpEngine) : selectOut
with {
    selectOut(aL, aR, bL, bR, cL, cR) =
        select3(mode, aL, bL, cL), select3(mode, aR, bR, cR);
};

wetPath = engines : par(i, 2, tone) : stereoWidth(width);

//======================= Mix =======================

// Equal-power crossfade: both branches at -3 dB at the centre position.
dryWetMixer3dB(dw, X) = _,_ <: (*(dG),*(dG)), (X : *(wG),*(wG)) :> _,_
with {
    dG = cos(dw * ma.PI/2.0);
    wG = sin(dw * ma.PI/2.0);
};

process = dryWetMixer3dB(drywet, wetPath) : attach(_, flangeview), _;
