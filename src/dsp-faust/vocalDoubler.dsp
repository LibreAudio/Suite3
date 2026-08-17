declare author "Klaus Scheuermann";
declare description "Libre Audio Vocal Doubler";
declare license "GPL-3.0-or-later";
declare name "Vocal Doubler";
declare unique_id "LAvd";

import("stdfaust.lib");

/* Grey-out list — which controls actually reach the output, per mode.
   Verified by measurement, not by reading: '.' means the rendered output is
   bit-identical with the control at either end of its range, so the UI can
   disable it there with no audible consequence.

   Rows follow the order the controls appear in the UI, listed with the [n]
   index each one declares, groups themselves in index order. Note that Stage
   Bottom Left and Stage Bottom Right both declare [1], so their indices do not
   decide which comes first; the order below is the one the generated UI
   actually produces, with Left ahead of Right.

                                 ADT   1/3 Doubler   Human
    Adt [0]
      [01] adt_delay              o         .         .
      [02] adt_2voice             o         .         .
      [03] adt_wow_rate           o         .         .
      [04] adt_wow_depth          o         .         .
      [05] adt_pan               1v         .         .
      [06] adt_width             2v         .         .
    Doubler [1]
      [11] doubler_base_delay     .         o         .
      [12] doubler_detune         .         o         .
      [13] doubler_wander_rate    .         o         .
      [14] doubler_wander_depth   .         o         .
      [15] doubler_width          .         o         .
    Human [2]
      [21] take_base_delay        .         .         o
      [22] take_timing            .         .         o
      [23] take_pitch             .         .         o
      [24] take_character         .         .         o
      [25] take_width             .         .         o
    Stage Bottom Right [1] — global
      [31] deess_amount           o         o         o
      [32] eq_hp                  o         o         o
      [33] eq_lp                  o         o         o
      [34] presence               o         o         o
      [35] mix                    o         o         o

   Each mode's section is dead in the other two: the select3 at the end of
   process discards the unselected branches whole. The five global rows are
   live everywhere, because the de-esser and the wet EQ sit in the shared wet
   feed rather than inside any one mode.

   1v / 2v  adt_pan and adt_width are mutually exclusive on the Voices knob:
      at 1 only pan is live (it places the double), at 2 only width is (it
      spreads the pair). The other one is fully inert, not just subtle.
   

   mix at -100 mutes the wet path outright: with the knob settled there every
   row above goes bit-identical and the plugin is a dry pass-through. mix is
   smoothed, so a move to -100 leaks a short wet tail on the way — the row is a
   steady-state statement, not an instantaneous one. The other end is not
   symmetric: +100 mutes the dry but leaves the whole wet side, de-esser and EQ
   included, still live.

   Caveat for the Human rows: take_timing and take_pitch only reach the output
   after a syllable onset has fired, since both scale a per-onset held value
   that starts at zero. They measure dead on steady or metronomic material and
   need a syllabic signal with real gaps between phrases to show up at all —
   which is a property of the test signal, not a grey-out condition the UI can
   act on.
*/

// UI
uiTop(x)    = hgroup("[0]Stage Top", x);
uiBottom(x) = hgroup("[8]Stage Bottom", x);
uiBottomLeft(x) = uiBottom(vgroup("[1]Stage Bottom Left", x));
uiBottomRight(x) = uiBottom(hgroup("[1]Stage Bottom Right", x));

uiAdt(x) = uiBottomLeft(hgroup("[0]Adt", x));
uiDoubler(x) = uiBottomLeft(hgroup("[1]Doubler", x));
uiHuman(x) = uiBottomLeft(hgroup("[2]Human", x));

uiMeters(x) = hgroup("[9]", x);

uiDelay(x)  = uiBottom(hgroup("[1]Delay", x));
uiLFO(x)    = uiBottom(hgroup("[2]LFO",   x));
uiWow(x)    = uiBottom(hgroup("[3]Wow",   x));
uiWander(x) = uiBottom(hgroup("[4]Wander",   x));
uiVariation(x) = uiBottom(hgroup("[5]Variation",   x));

uiMix(x)    = uiBottom(hgroup("[8]Mix",   x));
uiTone(x)   = uiBottom(hgroup("[9]Tone",  x));

//======================= Mode & global controls =======================

mode = uiTop(nentry("[0]Mode[symbol:mode][style:radio{'ADT':0;'1/3 Doubler':1;'Human':2}]", 0, 0, 2, 1));

// Dry/wet balance on one knob. At 0 both paths pass at unity; turning toward
// Wet pulls the dry down, toward Dry pulls the wet down. Only one side ever
// moves — this is a dry-kill fade, not a crossfade, so the sum runs up to
// ~6 dB hotter at center than at either end.
//
// The taper is linear in *amplitude* — the usual mix-knob feel — so half
// travel is -6 dB on the receding path rather than half of some dB range,
// which would already be inaudible well before the knob got there. The floor
// keeps linear2db out of -inf; at -120 dB it sits below faderMinDb, so both
// ends of the travel trip the mute test and silence that path outright
// instead of leaving a residue.
faderMinDb = -70;
faderGain(db) = ba.db2linear(db) * (db > faderMinDb);

mix = uiBottomRight(hslider("[35]Dry-Wet[unit:%][style:knob][symbol:mix][label:Dry-Wet][accentcolor:01][easy]", 0, -100, 100, 0.1)) / 100 : si.smoo;

mixAttenDb(amount) = ba.linear2db(max(0.000001, 1 - amount));

mixDry = faderGain(mixAttenDb(max(0, mix)));
mixWet = faderGain(mixAttenDb(max(0, 0 - mix)));

//======================= High Frequency Limiter =======================
// Feeds the wet path only — the dry half of the dry/wet mix always passes
// through untouched, so this can never dull the original signal.
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

// Level independence cuts both ways: a ratio detector fires on near-silence
// just as happily as on a sibilant, because room tone, hiss and denormals are
// spectrally flat — i.e. brighter than voice — so their high/low ratio looks
// exactly like an "s". An absolute gate settles it: below the floor nothing is
// touched at all, and reduction fades in over the knee above it. Not amount-
// dependent; these are "is there signal here" numbers, not taste.
hfLimGateDb   = -60;  // dBFS - floor; below this the limiter idles
hfLimGateKnee =  12;  // dB   - fade-in range above the floor (full effect at -48)

lerp(a, b, t) = a + (b - a) * t;

hflim_amount = uiBottomRight(hslider("[31]De-Ess[style:knob][unit:%][symbol:deess_amount][label:De-Ess][accentcolor:02]", 50, 0, 100, 1)) / 100;
hflim_meter  = uiMeters(hbargraph("[1]HFlim Reduction[unit:dB][symbol:deess_meter]", 0, 30));

hflim_split  = lerp(hfLimSplitAt0,  hfLimSplitAt100,  hflim_amount);
hflim_thresh = lerp(hfLimThreshAt0, hfLimThreshAt100, hflim_amount);
hflim_ratio  = lerp(hfLimRatioAt0,  hfLimRatioAt100,  hflim_amount);
hflim_range  = lerp(hfLimRangeAt0,  hfLimRangeAt100,  hflim_amount);

hfLimit(x) = (low + high * gr) : attach(_, (reductionDb) : hflim_meter)
with {
    low  = fi.lowpass(4, hflim_split, x);
    high = x - low; // complementary split: low+high reconstructs x exactly at unity gain

    // The EPSILON floor is not cosmetic: on a truly silent input both envelopes
    // are 0, log10(0) is -inf, and diff comes out NaN.
    envDb(att, rel) = an.amp_follower_ar(att, rel) : max(ma.EPSILON) : ba.linear2db;

    hiDb  = high : envDb(0.001, 0.03);
    refDb = low  : envDb(0.001, 0.03);

    // Broadband level, for the gate only. Released slower than the ratio
    // detector so the gate stays open through the tail of a word instead of
    // chattering across the threshold.
    inDb = x : envDb(0.001, 0.1);
    gate = min(1, max(0, (inDb - hfLimGateDb) / hfLimGateKnee));

    // dB the high band sticks out above the body band, relative to normal
    // voice spectral tilt; only the excess over threshold is limited
    diff   = hiDb - refDb;
    excess = max(0, diff - hflim_thresh);

    // Gating the reduction rather than the detector keeps the meter honest: it
    // reads 0 when nothing is being done.
    reductionDb = min(excess * (1 - 1 / hflim_ratio), hflim_range) * gate;
    gr = ba.db2linear(0 - reductionDb);
};

//======================= Wet EQ =======================
// Shapes the double only, never the dry — the usual move is to roll off
// lows and top so the double sits behind the lead instead of thickening
// it, plus one band to duck or lift whatever frequency the double
// exaggerates. Applies in every mode.

eq_hpHz = uiBottomRight(hslider("[32]HighPass[style:knob][unit:Hz][scale:log][symbol:eq_hp][label:HighPass][accentcolor:06]", 20, 20, 20000, 1)) : si.smoo;
eq_lpHz = uiBottomRight(hslider("[33]LowPass[style:knob][unit:Hz][scale:log][symbol:eq_lp][label:LowPass][accentcolor:06]", 20000, 20, 20000, 1)) : si.smoo;
eq_freq = 5000; //hgroup("[5]Wet EQ", hslider("[2]Presence Freq[unit:Hz][symbol:presence_freq]", 2000, 100, 12000, 1));
eq_gain = uiBottomRight(hslider("[34]Prensence[style:knob][unit:dB][symbol:presence][label:Presence][accentcolor:06]", 0, -12, 12, 0.1)) : si.smoo;
eq_q    = 0.28; //hgroup("[5]Wet EQ", hslider("[4]Presence Q[symbol:presence_q]", 1, 0.2, 8, 0.01));

wetEq = fi.highpass(2, eq_hpHz)
      : fi.lowpass(2, eq_lpHz)
      : fi.peak_eq_cq(eq_gain, eq_freq, eq_q);

//======================= Mode 1: ADT (tape-style) =======================
// Delayed voice, delay time wobbled by a slow LFO to emulate varispeed
// "wow" from a second tape machine (Abbey Road ADT). The 2nd Voice switch
// adds a second machine: longer-delayed, with a slower and unrelated wow
// rate so the two never lock into one audible wobble.
//
// Stereo placement is Pan with one voice (where the double sits) and Width
// with two (how far apart they sit); the unused one is simply ignored.


adt_delayMs = uiAdt(hslider("[01]ADT Delay[style:knob][unit:ms][symbol:adt_delay][label:Delay][requires:mode:0][accentcolor:02]", 18, 5, 40, 0.1)) : si.smoo;
adt_2voice  = uiAdt(hslider("[02]ADT Voices[style:knob][symbol:adt_2voice][label:Voices][requires:mode:0][accentcolor:02]",1,1,2,1)) -1;
adt_rateHz  = uiAdt(hslider("[03]ADT Rate[style:knob][unit:Hz][symbol:adt_wow_rate][label:Rate][requires:mode:0][accentcolor:03][bracket:WOW]", 0.6, 0.05, 5, 0.01));
adt_depthMs = uiAdt(hslider("[04]ADT Depth[style:knob][unit:ms][symbol:adt_wow_depth][label:Depth][requires:mode:0][accentcolor:03][bracket:WOW]", 2.5, 0, 10, 0.1)) :si.smoo;
adt_pan     = uiAdt(hslider("[05]ADT Pan[style:knob][symbol:adt_pan][label:Pan][requires:mode:0][accentcolor:04]", 0, -1, 1, 0.01));
adt_width   = uiAdt(hslider("[06]ADT Width[style:knob][symbol:adt_width][label:Width][requires:mode:0_FIXME][accentcolor:04]", 1, 0, 1, 0.01));

// second machine, derived from the single-voice settings
adt_delay2  = adt_delayMs * 1.6 + 4;
adt_rate2   = adt_rateHz * 0.73;

adt_voice(delayMs, rateHz, x) = x : de.fdelay(maxDel, delaySamp)
with {
    maxDel    = 65536;
    baseDelay = delayMs * ma.SR / 1000;
    depthSamp = adt_depthMs * ma.SR / 1000;
    delaySamp = max(1, baseDelay + os.osc(rateHz) * depthSamp);
};

// constant-power pan, p in 0..1 (0 = hard left, 0.5 = center, 1 = hard right)
panL(p) = cos(p * ma.PI / 2);
panR(p) = sin(p * ma.PI / 2);

// dry = untouched input, src = limiter output the voices are built from
adt_mode(dry, src) = outL, outR
with {
    voiceA = src : adt_voice(adt_delayMs, adt_rateHz);
    voiceB = src : adt_voice(adt_delay2,  adt_rate2);

    // one voice: pan places it. 0 = centered (classic mono ADT),
    // -1/+1 = hard left/right, dry stays centered so the double
    // reads as stereo spread.
    p     = 0.5 + adt_pan * 0.5;
    oneL  = voiceA * panL(p);
    oneR  = voiceA * panR(p);

    // two voices: width spreads them to mirrored positions, 0 stacks them
    // centered. Halved so the pair sits at the same loudness as one voice.
    pA    = 0.5 - adt_width * 0.5;
    pB    = 0.5 + adt_width * 0.5;
    twoL  = (voiceA * panL(pA) + voiceB * panL(pB)) * 0.5;
    twoR  = (voiceA * panR(pA) + voiceB * panR(pB)) * 0.5;

    // select before the EQ so it stays one instance per channel either way
    wetL = select2(adt_2voice, oneL, twoL) : wetEq;
    wetR = select2(adt_2voice, oneR, twoR) : wetEq;

    outL = dry * mixDry + wetL * mixWet;
    outR = dry * mixDry + wetR * mixWet;
};

//======================= Mode 2: 1/3 pitch-shift doubler =======================
// Two detuned, independently-delayed voices panned apart, each with its
// own slow random ("humanized") wander in pitch and level so they don't
// read as a static chorus but as two separate takes.

db_delayMs  = uiDoubler(hslider("[11]DOUBLER Base Delay[style:knob][unit:ms][symbol:doubler_base_delay][label:Delay][requires:mode:1][accentcolor:02]", 20, 5, 50, 0.1)) : si.smoo;
db_detune   = uiDoubler(hslider("[12]DOUBLER Detune[style:knob][unit:cents][symbol:doubler_detune][label:Detune][requires:mode:1][accentcolor:05]", 14, 0, 40, 0.1));
db_wanderHz = uiDoubler(hslider("[13]DOUBLER Wander Rate[style:knob][unit:Hz][symbol:doubler_wander_rate][label:Rate][requires:mode:1][accentcolor:03][bracket:WANDER]", 0.25, 0.02, 2, 0.01));
db_wanderCt = uiDoubler(hslider("[14]DOUBLER Wander Depth[style:knob][unit:cents][symbol:doubler_wander_depth][label:Depth][requires:mode:1][accentcolor:03][bracket:WANDER]", 6, 0, 25, 0.1));
db_width    = uiDoubler(hslider("[15]DOUBLER Width[style:knob][symbol:doubler_width][label:Width][requires:mode:1][accentcolor:04]", 1, 0, 1, 0.01));

db_voice(centsShift, delayMs, wanderFreq, x) = out
with {
    maxDel         = 65536;
    winSamp        = 0.03 * ma.SR;
    xfadeSamp      = winSamp * 0.25;
    ampWanderFreq  = wanderFreq * 1.7;
    ampWanderDepth = 0.08;

    wanderCents = no.lfnoise(wanderFreq) * db_wanderCt;
    shiftSemi   = (centsShift + wanderCents) / 100;
    delaySamp   = delayMs * ma.SR / 1000;
    ampMod      = 1 + no.lfnoise(ampWanderFreq) * ampWanderDepth;

    out = x : ef.transpose(winSamp, xfadeSamp, shiftSemi) : de.fdelay(maxDel, delaySamp) : *(ampMod);
};

// dry = untouched input, src = limiter output the voices are built from
db_mode(dry, src) = outL, outR
with {
    voiceA = src : db_voice(0 - db_detune, db_delayMs,           db_wanderHz);
    voiceB = src : db_voice(db_detune,     db_delayMs * 1.15 + 3, db_wanderHz * 1.21);

    pA = 0.5 - db_width * 0.5;
    pB = 0.5 + db_width * 0.5;

    wetL = voiceA * panL(pA) + voiceB * panL(pB) : wetEq;
    wetR = voiceA * panR(pA) + voiceB * panR(pB) : wetEq;

    // two voices summed into each channel: halve to keep loudness in
    // line with the single-voice ADT mode at the same mix setting.
    outL = dry * mixDry + wetL * mixWet * 0.5;
    outR = dry * mixDry + wetR * mixWet * 0.5;
};

//======================= Mode 3: Take (human double) =======================
// Where the other two modes give the double a *constant* offset, this one
// re-rolls timing, tuning and level at every syllable onset and holds them
// until the next one. Offsets stay put within a phrase and differ between
// phrases, which is how a real second pass differs from the first — the
// thing continuous wander can't imitate. A small formant offset on top
// makes each voice read as a different throat rather than the same voice
// detuned.

tk_baseMs   = uiHuman(hslider("[21]TAKE Base Delay[style:knob][unit:ms][symbol:take_base_delay][label:Delay][requires:mode:2][accentcolor:02]", 25, 5, 60, 0.1)) : si.smoo;
tk_timingMs = uiHuman(hslider("[22]TAKE Timing Variation[style:knob][unit:ms][symbol:take_timing][label:Timing][requires:mode:2][accentcolor:03][bracket:VARIATION]", 15, 0, 40, 0.1));
tk_pitchCt  = uiHuman(hslider("[23]TAKE Pitch Variation[style:knob][unit:cents][symbol:take_pitch][label:Pitch][requires:mode:2][accentcolor:03][bracket:VARIATION]", 10, 0, 30, 0.1));
tk_charact  = uiHuman(hslider("[24]TAKE Character[style:knob][unit:%][symbol:take_character][label:Character][requires:mode:2][accentcolor:03][bracket:VARIATION]", 40, 0, 100, 1)) / 100;
tk_sens     = 50; //hgroup("[6]Take", hslider("[4]TAKE Onset Sensitivity[unit:%][symbol:take_sensitivity]", 50, 0, 100, 1)) / 100;
tk_width    = uiHuman(hslider("[25]TAKE Width[style:knob][symbol:take_width][label:Width][requires:mode:2][accentcolor:04]", 1, 0, 1, 0.01));

// Onset detection watches the consonant band rather than overall level: a
// syllable in legato singing barely moves the total envelope, but its
// consonant lands hard above 5 kHz — the same region the HF limiter splits
// at, for the same reason. Measured on synthetic material, a 5 kHz corner separates
// real articulation from a sustained vibrato note by ~1.75x, where 1.5 kHz
// only managed 1.12x.
tkOnsetHP    = 5000;
tkOnsetRatio = lerp(2.6, 1.15, tk_sens);
tkOnsetFloor = ba.db2linear(-50);
tkRefractory = 0.12 * ma.SR;

tk_onset(x) = raw * (cnt' >= tkRefractory)
with {
    hf   = x : fi.highpass(2, tkOnsetHP);
    env  = hf : an.amp_follower_ar(0.0005, 0.030);
    // The reference chases env instead of being followed independently off
    // the input. That matters: with two independent followers a low
    // threshold leaves the comparator latched high forever and the rising
    // edge never fires again, so sensitivity behaves non-monotonically.
    // Chasing guarantees env/ref settles back to 1 on any steady signal, so
    // the comparator can only exceed the ratio on an actual attack.
    ref  = env : an.amp_follower_ar(0.150, 0.300);
    live = x  : an.amp_follower_ar(0.005, 0.100);

    over = (env > ref * tkOnsetRatio) * (live > tkOnsetFloor);
    raw  = over > over';

    // Refractory window, so one syllable can't re-roll the voices twice
    // mid-word. The counter resets on the *accepted* trigger, not on every
    // raw edge — resetting on raw edges lets a dense burst starve the gate
    // and never let anything through at all.
    cnt  = advance ~ _;
    advance(c) = select2(raw * (c >= tkRefractory), min(tkRefractory, c + 1), 1);
};

// Cheap formant offset: notch each formant region and put it back a few
// percent away. peak_eq at +L and -L is an exact reciprocal (the numerator
// and denominator coefficients simply swap), so at ratio 1 the cut and the
// boost land on the same frequency and cancel — Character at 0% measures
// ~-90 dBFS residual, i.e. transparent up to single-precision rounding
// through the six biquads.
tkFormantBand(f, r) = fi.peak_eq_cq(0 - g, f, q) : fi.peak_eq_cq(g, f * r, q)
with {
    q = 1.2;
    g = 5; // dB
};

// rough neutral-vowel F1/F2/F3
tkFormant(r) = tkFormantBand(700, r) : tkFormantBand(1220, r) : tkFormantBand(2600, r);

tkThroatA = 1 + tk_charact * 0.10;
tkThroatB = 1 - tk_charact * 0.09;

// A delay line's read position can only be moved while nothing is coming
// out of it. Two ways of moving it that both fail, measured on a steady
// 220 Hz tone:
//
//   * gliding the delay time IS varispeed — swinging 30 ms of delay across
//     a 25 ms glide moves the read pointer faster than real time, and bent
//     the tone by -957..+577 cents. This was the audible "fast speed
//     up/down".
//   * crossfading between two taps fails the same way in kind, because
//     blending two coherent copies rotates the resultant phase, and a
//     moving phase is a frequency deviation. A 12 ms crossfade still bent
//     3-4 consecutive periods by up to 600 cents; stretching it to 200 ms
//     only got to +/-150 cents and added a -20 dB comb notch on the way.
//
// So instead the voice is ducked to silence for a few ms at each onset,
// the delay jumps inside that window, and the voice returns at its new
// timing. Steady-state pitch error is then +/-0.02 cents, and all that is
// left is a single splice period at the edge of the gap, softened by the
// ramp. The duck lands at the *dry* onset, while the double is still
// playing the previous syllable's tail — its own new attack is a base
// delay away and arrives after the gap has closed.

// linear ramp toward the target at a fixed slope (one-pole tails would
// never reach hard zero, and the delay may only move at hard zero)
tkRamp(step) = loop ~ _
with {
    loop(prev, target) = prev + max(0 - step, min(step, target - prev));
};

tkDuckRampMs = 8;
// Keep the gap shorter than the base delay so it closes before the
// double's own attack lands; short base delays get a shorter duck.
tkDuckMs(baseMs) = max(4, min(14, baseMs * 0.55));

// rnd is the *unheld* noise stream — it is sampled inside the gap
tk_retime(trig, rnd, baseMs, x) = tap * g
with {
    maxDel = 65536;
    down   = trig : ba.peakholder(tkDuckMs(baseMs) * ma.SR / 1000);
    g      = (1 - down) : tkRamp(1000 / (tkDuckRampMs * ma.SR));

    // While g is hard zero the delay is free to move; it freezes the moment
    // audio comes back, so the jump itself is never heard. Held value
    // starts at 0, i.e. plain baseMs, until the first onset re-rolls it.
    d   = max(1, (baseMs + (rnd : ba.sAndH(g <= 0)) * tk_timingMs) * ma.SR / 1000);
    tap = x : de.fdelay(maxDel, d);
};

// rndTime is raw noise (latched per tap inside tk_retime); rTune/rLevel are
// the per-onset held values, each in -1..1
tk_voice(trig, rndTime, rTune, rLevel, throat, delayMs, x) = out
with {
    winSamp   = 0.03 * ma.SR;
    xfadeSamp = winSamp * 0.25;

    // Pitch and level may glide — changing the transposition ratio just
    // moves the pitch itself, so this reads as a short scoop into the new
    // note rather than as an artifact. Only the delay line can't be moved.
    glide     = si.smooth(ba.tau2pole(0.025));
    shiftSemi = rTune * tk_pitchCt / 100 : glide;
    ampMod    = ba.db2linear(rLevel * 1.5) : glide;

    out = x : ef.transpose(winSamp, xfadeSamp, shiftSemi)
            : tk_retime(trig, rndTime, delayMs)
            : tkFormant(throat)
            : *(ampMod);
};

// dry = untouched input, src = limiter output the voices are built from
tk_mode(dry, src) = outL, outR
with {
    // one shared trigger: both takes react to the same syllable, but each
    // draws its own offsets from a decorrelated noise stream
    trig    = tk_onset(src);
    hold(n) = no.noises(6, n) : ba.sAndH(trig);

    // Voice B re-times 35 ms after voice A rather than at the same instant,
    // so the two duck windows never overlap and the double is never fully
    // absent — at worst it drops to one voice for a few ms.
    trigB = trig : de.delay(32768, int(0.035 * ma.SR));

    // staggered base delays so the two aren't coherent before the first
    // onset has re-rolled anything
    voiceA = src : tk_voice(trig,  no.noises(6, 0), hold(1), hold(2), tkThroatA, tk_baseMs);
    voiceB = src : tk_voice(trigB, no.noises(6, 3), hold(4), hold(5), tkThroatB, tk_baseMs * 1.2 + 4);

    pA = 0.5 - tk_width * 0.5;
    pB = 0.5 + tk_width * 0.5;

    wetL = voiceA * panL(pA) + voiceB * panL(pB) : wetEq;
    wetR = voiceA * panR(pA) + voiceB * panR(pB) : wetEq;

    // two voices summed into each channel: halve to match the single-voice
    // ADT mode at the same mix setting, as in 1/3 Doubler
    outL = dry * mixDry + wetL * mixWet * 0.5;
    outR = dry * mixDry + wetR * mixWet * 0.5;
};

//======================= Mode select =======================

// The limiter sits on the wet feed only: each mode gets the untouched sum
// as its dry, and the limited sum as the source its voices are built from.
process = _,_ :> _*0.5 <: (_, hfLimit) <: (adt_mode, db_mode, tk_mode) : selectOut
with {
    selectOut(aL, aR, bL, bR, cL, cR) =
        select3(mode, aL, bL, cL), select3(mode, aR, bR, cR);
};
