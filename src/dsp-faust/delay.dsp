declare author "Klaus Scheuermann";
declare description "";
declare license "GPL-3.0-or-later";
declare name "Delay";
declare unique_id "LAdl";

// declare drywet "true";

import("stdfaust.lib");

// Stereo delay with three character modes, tempo-synced or free times, an
// optional ping-pong topology, a de-esser at the head of the wet path, tone
// shaping inside the feedback loop, and ducking driven by the dry signal.
//
// De-Ess: vocalDoubler.dsp's high-frequency limiter, lifted whole and placed
//   ahead of the delay lines rather than inside the loop -- see deEss for why
//   that distinction is the entire point of where it sits.
//
// Digital: the delay line and nothing else. Repeats are bandwidth-flat and
//   decay only by the feedback gain and whatever the Tone filters take out.
//   At Drive 0 the only nonlinearity is softRail, which is inaudible below
//   +12 dBFS and exists so a loop gain of 1.0 cannot run away -- see softRail.
//   Drive adds a second one, shared with the other two modes -- see driveSat.
//
// Tape: a 45 Hz high pass and a 6.5 kHz low pass per pass, a +3 dB head bump
//   at 90 Hz, gentle saturation, and wow and flutter on the delay time. The
//   two modulators matter more than the filters: a tape echo's repeats do not
//   merely darken, they drift, and a tail of six identical-pitch repeats is
//   the giveaway that a "tape" delay is a low pass in a costume.
//
// BBD: much narrower -- 120 Hz to 3 kHz -- with harder saturation and a slow
//   clock drift. The repeats go dark fast, which is the whole sound of a
//   bucket-brigade echo.
//
//   No compander here, and that is deliberate rather than an omission.
//   flanger.dsp measured an expander inside a regeneration loop running away
//   to +300 dB and then to NaN, because an expander's gain rises with level
//   and so a feedback path containing one is positive feedback in the level
//   domain. Putting the compander outside the loop, as flanger.dsp does, is
//   only possible when the mode owns the whole loop. Here all three modes
//   share one delay line and switch only the colour block inside it, so there
//   is no "outside" to put it. The filters and the saturator carry the
//   character; every element in the loop has gain <= 1 and the engine is
//   unconditionally stable at any Feedback setting.
//
// Sync: the BPM knob is set by hand. Nothing in the suite reads host tempo --
//   DISTRHO_PLUGIN_WANT_TIMEPOS is not defined in DistrhoPluginInfo.h and
//   LibreAudioPlugin.cpp never calls getTimePosition(). When that plumbing
//   lands, the host BPM replaces this knob's value and nothing else here
//   changes: everything downstream reads `bpm` as a plain signal.
//
// Glide: the delay time is always slewed rather than crossfaded, in every
//   mode, so moving Time pitch-bends the repeats the way moving a tape head
//   does. See timeGlide.
//
// No Bypass control here: the host wrapper provides one (see
// LibreAudioPlugin.cpp), and input/output trim, phase and M/S come from
// common/input.dsp and common/output.dsp.

Nch = 2;                            // delay is stereo

maxSR      = 192000;
maxDelayMs = 4000;

// The allocated buffer, and the largest index the tap is allowed to reach.
//
// Faust rounds a delay line up to a power of two, and de.fdelay4 needs a few
// samples above the maximum it is handed for its interpolator to read across.
// Ask it for DLEN exactly and those extra samples tip it over, so it allocates
// 2 * DLEN and half the memory is never addressed -- measured at 16.2 MB per
// instance before this was noticed, against the 8.4 MB below. The 16 samples
// of headroom cost 0.08 ms off the top of a 4 s delay.
DLEN   = 1 << 20;                   // 1048576 >= 4000 ms * 192 kHz = 768000
MAXTAP = DLEN - 16;

process = si.bus(Nch) : delayFx;

// --- UI structure ---

// Four groups, flat, named for what they contain. The nested Stage Top /
// Stage Bottom Left / Stage Bottom Right arrangement the rest of the suite
// uses is gone from this file: it described a screen layout, and no screen
// layout reads it. Nothing in the C++ ever sees these names -- FaustParameter
// carries a bracket and no group (see FaustParameters.hpp) -- so their only
// consumers are the generic Faust UIs and, through the [n] prefixes, the order
// of the generated parameter list.
//
// Since that order is the one thing they do decide, the groups are made to
// agree with the brackets rather than cut across them. Same names, same
// members, same sequence, so there is one structure to keep straight instead
// of two that have to be reconciled.
uiMode(x)    = hgroup("[0]MODE", x);
uiTime(x)    = hgroup("[1]TIME", x);
uiRepeats(x) = hgroup("[2]REPEATS", x);
uiOutput(x)  = hgroup("[3]OUTPUT", x);

// Left unnamed and at [9], as in gate.dsp and chorus.dsp: the meters are not a
// control group and the suite's UIs find them by symbol.
uiMeters(x)  = hgroup("[9]", x);

// What the four groups mean:
//
//   MODE     what the engine *is*: which machine it emulates, and whether the
//            two delay lines run independently or as a ring.
//   TIME     everything that decides *when* a repeat arrives -- Sync and Link
//            included, since neither changes the sound, they only change how
//            the five time controls below them are read.
//   REPEATS  everything that decides what a repeat *sounds like* once it is
//            in flight: how many (Feedback), how driven, how much they wobble,
//            how sibilant, how bright. De-Ess sits here rather than with the
//            filters it resembles because it belongs to the same question.
//   OUTPUT   what leaves the plugin: Duck, Width, Dry-Wet.
//
// Every control also carries a [bracket:] naming its group. That is the half
// the plugin's own GUI reads, and it is the half that has to stay contiguous:
// the GUI builds a bracket out of a *run* of consecutive parameters sharing a
// label (ui/widgets-todo/knob-group.hpp), so a bracket split across the [n]
// indices would be drawn as two separate boxes with the same name. Keeping the
// groups aligned with the brackets is what makes that hard to get wrong -- a
// control in the right group is contiguous with its bracket by construction.

/* Grey-out list -- which controls actually reach the output.

   [requires:symbol:value] carries one condition per control, and two of these
   controls genuinely have two. Time R and Div R are live only when Link is
   Free *and* the matching Sync state holds; they declare the Link condition,
   which is the one a user actually reaches for, and stay lit but inert in the
   wrong Sync state. Noted here rather than worked around, since the
   alternative is a second radio's worth of UI to express it.

                              Free        Tempo
    MODE [0]
      [01] mode               o           o
      [02] pingpong           o           o     Normal / Ping-Pong L / Ping-Pong R
    TIME [1]
      [11] sync               o           o
      [12] link               o           o
      [13] time_l             o           .     requires sync:0
      [14] time_r             lk          .     requires link:1
      [15] bpm                .           o     requires sync:1
      [16] div_l              .           o     requires sync:1
      [17] div_r              .           lk    requires link:1
      [18] offset_l           o           o
      [19] offset_r           o           o
    REPEATS [2]
      [21] feedback           o           o
      [22] cross              o           o     requires pingpong:0
      [23] drive              o           o
      [24] mod_rate           o           o
      [25] mod_depth          o           o
      [26] mod_stereo_phase   o           o
      [27] deess_amount       o           o
      [28] hp_freq            o           o
      [29] lp_freq            o           o
    OUTPUT [3]
      [31] duck               o           o
      [32] width              o           o
      [33] drywet             o           o

   lk  live only with Link on Free; with Link on Linked the right channel
      takes the left channel's time and the control does not reach the output.

   offset_l and offset_r carry no requires: condition of any kind, which is the
   one thing that distinguishes them from the four rows above. They trim
   whichever time their channel ended up with, so they stay live in Tempo as
   well as Free and with Link on Linked as well as Free -- the only route to a
   left/right time difference that survives every other setting.

   drywet at -100 mutes the wet path outright and every row above goes dead --
   the plugin is a bit-exact dry pass-through there, because the dry leg is
   multiplied by exactly 1.0 and the wet by exactly 0.0. The other end is not
   symmetric: +100 mutes the dry but leaves the whole wet side live. Unlike the
   0-to-100 knob this replaced, it is smoothed, so both statements are about
   where the knob has settled rather than the instant it is moved -- a fast
   move to -100 leaks a short wet tail on the way, as the Vocal Doubler's does.
   Anything at or below -99.97 mutes, so the settling has 0.03% of margin.

   mod_rate and mod_stereo_phase are both inert at Depth 0, and mod_depth is
   inert in the sense that the LFO still runs -- it is multiplied by zero, not
   switched off, so there is no discontinuity when any of the three leaves
   zero.

   drive is live in all three modes and at every Feedback setting including 0,
   where it still shapes the single repeat that does get through.

   deess_amount at 0 is a true bypass rather than merely a gentle setting: the
   reduction ceiling is one of the four parameters the macro drives, and it
   lerps to exactly 0 dB there, so the shelf is asked for 0 dB and collapses to
   a straight wire. Same property it has in vocalDoubler.dsp and chorus.dsp.
*/

// --- Mode pills ---

mode = uiMode(nentry("[01]mode[style:radio{'Digital':0;'Tape':1;'BBD':2}][symbol:mode][bracket:MODE][integer]", 0, 0, 2, 1)) : int;

// Three states, and the letter names which side the first repeat lands on:
// Ping-Pong L bounces L, R, L, R and Ping-Pong R is its mirror image, R first.
// Which one you want depends entirely on what else is in the arrangement, so
// it is a setting rather than a fixed handedness.
//
// The selector is an int, but nothing downstream reads it directly. It is
// decomposed into two crossfade coefficients instead, so every topology change
// morphs rather than switches. A hard switch would step the feedback path --
// swapping which channel's tail feeds which line mid-tail is a discontinuity
// in the audio, not just in a gain -- and would click on every toggle.
//
// smooInit rather than si.smoo, and this is the control that requires it.
// This is not a level being faded in over 20 ms, it is which line feeds which:
// with a plain si.smoo the plugin starts in Normal for 20 ms no matter what
// the session saved, and anything arriving in that window is committed to the
// wrong topology for the whole length of its tail. Measured before the fix: an
// impulse at sample 0 with Ping-Pong selected came out of both channels at
// once, which is precisely the thing ping-pong is not.
ppSel = uiMode(nentry("[02]pingpong[style:radio{'Normal':0;'Ping-Pong L':1;'Ping-Pong R':2}][symbol:pingpong][bracket:MODE][integer]", 0, 0, 2, 1)) : int;

// One coefficient per handed topology, and their sum is how ping-pong the
// engine is at all.
//
// Going straight from one handedness to the other is the case worth checking,
// because both coefficients move at once. ppL falls as a^n while ppR rises as
// 1 - a^n through the same pole, so in exact arithmetic the sum would be 1
// throughout and the engine would never pass through a partly-Normal state.
//
// In float32 it does not quite hold: (1-a) + a is not exactly 1 at this pole,
// and simulating the switch sample by sample the sum ranges over
// [0.99997139, 1.00000358]. Two consequences, both measured rather than
// assumed:
//
//   * Below 1 the engine is momentarily a hair Normal, so a trace of the dry
//     stereo reaches the lines directly. At 2.9e-5 that is -91 dB, for the
//     20 ms the ramp lasts. Rendered, a switch mid-tail produces no click at
//     all -- the largest sample-to-sample step across it measured 0.983 of the
//     steady-state maximum, i.e. below the signal's own slew.
//
//   * Above 1 it would push the spectral radius in crossL / crossR to
//     1.0000072, marginally outside the <= 1 the stability argument there
//     claims. Rather than weaken that claim for seven parts in a million, the
//     sum is clamped. One min per sample buys an invariant the reasoning
//     downstream can actually rely on; the clamp never fires in any steady
//     state, only inside the ramp.
ppL   = float(ppSel == 1) : smooInit;
ppR   = float(ppSel == 2) : smooInit;
ppAmt = min(1.0, ppL + ppR);

// Sync and Link live in TIME rather than up in the mode pills, because that is
// what they are: neither changes the character of the delay, they only change
// how the five time controls beneath them are read. Mode and Ping-Pong stay at
// the top, where they do change what the engine is.
sync = uiTime(nentry("[11]sync[style:radio{'Free':0;'Tempo':1}][symbol:sync][bracket:TIME][integer]", 0, 0, 1, 1)) : int;
link = uiTime(nentry("[12]link[style:radio{'Linked':0;'Free':1}][symbol:link][bracket:TIME][integer]", 0, 0, 1, 1)) : int;

// --- Time ---

// Logarithmic, because the musically useful part of a 1-4000 ms range is all
// in its bottom decade: slap at 80 ms and a quarter note at 500 ms are two
// thirds of the way apart on a linear knob and a comfortable distance apart on
// this one.
timeLms = uiTime(hslider("[13]Time L[style:knob][unit:ms][scale:log][symbol:time_l][label:Time L][accentcolor:02][bracket:TIME][easy][requires:sync:0]
      [tooltip: Left channel delay time. In Tempo sync this is replaced by Div L]",
      375, 1, maxDelayMs, 0.1));

timeRms = uiTime(hslider("[14]Time R[style:knob][unit:ms][scale:log][symbol:time_r][label:Time R][accentcolor:02][bracket:TIME][requires:link:1]
      [tooltip: Right channel delay time. Only reaches the output with Link on Free]",
      500, 1, maxDelayMs, 0.1));

// Set by hand until the host-tempo plumbing exists. Deliberately not smoothed:
// it is read once per block into a time in ms which is then handed to the
// glide, so the glide is what removes the steps -- smoothing here would put a
// second one-pole in series with it and make the same knob's response depend
// on which of Free or Tempo produced the number.
bpm = uiTime(hslider("[15]BPM[style:knob][unit:bpm][symbol:dpf_bpm][label:BPM][accentcolor:02][bracket:TIME][requires:sync:1]
      [tooltip: Tempo for the note divisions. Set by hand -- the host tempo is not read yet]",
      120, 20, 300, 0.01)) : meter_bpm;

meter_bpm = _ <: attach(_, hbargraph("meter bpm",50,300));

// Eleven divisions relative to a quarter note, ordered long to short with the
// dotted value ahead of its straight partner and the triplet behind it, so
// turning the knob one way always shortens the delay. That ordering is what
// makes the menu read as one continuous scale rather than a grouped list.
NDIV = 11;
divTable = (4.0, 2.0, 1.5, 1.0, 2.0/3.0, 0.75, 0.5, 1.0/3.0, 0.375, 0.25, 1.0/6.0);
divIdxL = uiTime(nentry("[16]Div L[style:menu{'1/1':0;'1/2':1;'1/4.':2;'1/4':3;'1/4T':4;'1/8.':5;'1/8':6;'1/8T':7;'1/16.':8;'1/16':9;'1/16T':10}][symbol:div_l][label:Div L][accentcolor:02][bracket:TIME][requires:sync:1]
      [tooltip: Left channel note division. A dot lengthens by half, a T shortens to two thirds]", 6, 0, NDIV - 1, 1)) : int;

divIdxR = uiTime(nentry("[17]Div R[style:menu{'1/1':0;'1/2':1;'1/4.':2;'1/4':3;'1/4T':4;'1/8.':5;'1/8':6;'1/8T':7;'1/16.':8;'1/16':9;'1/16T':10}][symbol:div_r][label:Div R][accentcolor:02][bracket:TIME][requires:link:1]
      [tooltip: Right channel note division. Only reaches the output with Link on Free]", 6, 0, NDIV - 1, 1)) : int;

// Multiplier for a division index, as a signal rather than a compile-time
// lookup: ba.take needs a constant index and this one comes from a knob.
divMult(idx) = divTable : ba.selectn(NDIV, idx);

// Beat length in ms. bpm is floored well above zero by the slider's own range,
// so no guard is needed here.
beatMs = 60000.0 / bpm;

// The two sources of a delay time, picked by Sync. Not clamped here any more
// -- the offsets below can push a time past the buffer, so there is one clamp
// at the end of the chain rather than two that would have to agree.
timeMs(freeMs, idx) = select2(sync, freeMs, divMult(idx) * beatMs);

// --- Per-channel offsets ---

// A percentage trim on each channel's delay time, live in every combination of
// Sync and Link. That independence is the point: with Link on Linked both
// lines run the identical time and the wet collapses toward the centre, which
// is exactly the state a tempo-synced delay is usually in. A few percent on
// one side pulls the repeats apart again without giving up the grid, and it
// stays correct when the tempo or the division changes, which a fixed offset
// in milliseconds would not.
//
// Multiplicative rather than additive, so the trim keeps the same musical
// weight at 20 ms as at 2 s -- and so it cannot invert the sign of a short
// delay the way subtracting a fixed number of ms could.
//
// Not smoothed, and deliberately: the offset lands on baseMs, which is handed
// to timeGlide like every other route into the delay time. Smoothing here
// would put a second one-pole in series with the glide, for the same reason
// bpm is left alone. A move on these knobs therefore pitch-bends the repeats
// exactly as a move on Time does.
offsetPctMax = 20;

offsetLpct = uiTime(hslider("[18]Offset L[style:knob][unit:%][symbol:offset_l][label:Offset L][accentcolor:02][bracket:TIME]
      [tooltip: Trims the left delay time by a percentage. Works in every Sync and Link setting, so a Linked pair can still be pulled apart. 0 = off]",
      0, 0 - offsetPctMax, offsetPctMax, 0.1));

offsetRpct = uiTime(hslider("[19]Offset R[style:knob][unit:%][symbol:offset_r][label:Offset R][accentcolor:02][bracket:TIME]
      [tooltip: Trims the right delay time by a percentage. Works in every Sync and Link setting, so a Linked pair can still be pulled apart. 0 = off]",
      0, 0 - offsetPctMax, offsetPctMax, 0.1));

offsetL = 1.0 + offsetLpct / 100.0;
offsetR = 1.0 + offsetRpct / 100.0;

// The clamp both channels end on. A whole note at 20 BPM is 12 seconds, and
// +20% on a 4 s free time is 4.8 -- either would wrap the buffer.
clampMs = max(1.0) : min(maxDelayMs);

// Link resolves first and the offsets are applied after it, which is what
// makes them independent of it: Link decides the *shared* time, each offset
// then trims its own channel away from that. Take L's already-offset value
// instead and the two trims would compound on the right, so Offset R would
// mean something different depending on where Offset L was standing.
//
// With Link on Linked the right channel is handed the *left* channel's value,
// not its own -- both lines then read the identical signal, so a linked pair
// at equal offsets is sample-for-sample a single delay time and cannot drift
// by a rounding step the way two separately-computed equal numbers could.
rawMsL = timeMs(timeLms, divIdxL);
rawMsR = select2(link, rawMsL, timeMs(timeRms, divIdxR));

baseMsL = rawMsL * offsetL : clampMs;
baseMsR = rawMsR * offsetR : clampMs;

// --- Glide ---

// Always on, in every mode. The delay time in samples is slewed with a one
// pole and fed to an interpolating tap, so a change in Time walks the read
// pointer to its new position instead of jumping: the material already in the
// buffer is resampled on the way, and that is audible as a pitch bend, exactly
// as moving a tape head is. The alternative -- crossfading between two taps --
// keeps pitch intact and is what a "digital" delay does, but it was ruled out
// for all three modes here, so Digital bends too.
//
// 180 ms is the audible knee. Much faster and a large jump zips rather than
// glides; much slower and the delay takes a noticeable moment to arrive
// where the knob already is.
// si.smoo, with its state landed on the control's value at the first sample
// instead of on zero. Faust gives a one-pole no initial condition, so a plain
// si.smoo always ramps up from silence over its time constant when the DSP
// starts or the host resets it. For a level that is 20 ms of fade-in and
// nobody notices, which is why the rest of the suite uses si.smoo unqualified.
// Here two of the smoothed controls are not levels -- see ppL / ppR, and
// timeGlide below -- so the whole file uses this instead and no control has to
// be reasoned about twice.
smooInit = si.smooth(ba.tau2pole(0.02) * float(ba.time > 0));

glideSec = 0.180;

// Landed on the target at the first sample by the same trick smooInit uses,
// and here it is not a nicety: without it every start -- and every host reset,
// since instanceClear zeroes ba.time along with the rest of the state -- would
// put the read pointer at zero delay and glide it up to the set time. That is
// a pitch dive lasting the better part of a second, on a control nobody
// touched.
timeGlide = si.smooth(ba.tau2pole(glideSec) * float(ba.time > 0));

// --- Feedback ---

// Capped at 100%. With every element in the loop at gain <= 1 that is the
// sustain point rather than a runaway: the repeats hold their level and decay
// only by whatever the Tone filters and the mode's own bandwidth limit remove.
// In Digital at Drive 0, with both Tone filters parked at their extremes, it
// will hold essentially forever, which is the intended behaviour of the top of
// the knob.
//
// Drive shortens that. A saturator in a loop is a level-dependent gain below
// unity, so the louder the tail the faster it decays -- see driveSat, where
// that is argued for rather than apologised for.
feedback = uiRepeats(hslider("[21]Feedback[style:knob][unit:%][symbol:feedback][label:Feedback][accentcolor:01][bracket:REPEATS][easy]
      [tooltip: How much of each repeat is fed back into the delay line. At 100% the repeats sustain rather than decay]",
      35, 0, 100, 0.1)) / 100 : smooInit;

// --- Cross-feedback ---

// How much of each channel's tail is returned to the *other* line instead of
// its own. The engine has always had cross-feedback -- it is what crossL and
// crossR are -- but the amount was welded to the Ping-Pong selector, which is
// an enum, so in any steady state it was 0 or 1 and nothing between.
//
// Written as a rotation that conserves the loop gain rather than as two
// independent sends:
//
//     self = Feedback * (1 - Cross)      cross = Feedback * Cross
//
// so the feedback matrix is [[a, b], [b, a]] with a = g(1-c) and b = g*c. It
// is symmetric, which means its eigenvectors are exactly mid and side, with
// eigenvalues a+b = g and a-b = g(1-2c). Both of those are worth having.
//
// The first is that the spectral radius is max(g, |g(1-2c)|) = g for any c in
// [0, 1]. Cross cannot destabilise the engine and cannot change how long a
// mono tail rings -- it is gain-neutral by construction, not by tuning, so the
// knob is safe to sweep at Feedback 100.
//
// The second is what the knob actually *is*: a control over the side signal's
// decay alone. Mid always decays at g. Side decays at g(1-2c), so at Cross 0
// the two channels are independent, at 50% the side is killed in a single pass
// and the tail collapses to the centre however wide the source was, and above
// 50% the side comes back with its sign flipped every pass -- which is the
// alternation that makes ping-pong sound like ping-pong.
//
// Which is the honest way to describe the difference between this and
// Ping-Pong: at Cross 100 the *feedback* is exactly Ping-Pong's, but the input
// routing is untouched, so a stereo source keeps its stereo on the first
// repeat and only then starts bouncing. Ping-Pong mono-sums the input into one
// line and throws that away. Inside Ping-Pong the channels are already fully
// crossed and this knob has nothing left to do, hence the requires.
crossFb = uiRepeats(hslider("[22]Cross[style:knob][unit:%][symbol:cross][label:Cross][accentcolor:01][bracket:REPEATS][requires:pingpong:0]
      [tooltip: How much of each repeat is fed back into the opposite channel. 0 = two independent delays, 50 = the tail collapses to the centre, 100 = it alternates sides. Ping-Pong is already fully crossed, so this is a Normal-mode control]",
      0, 0, 100, 0.1)) / 100 : smooInit;

// --- Drive ---

drive = uiRepeats(hslider("[23]Drive[style:knob][unit:%][symbol:drive][label:Drive][accentcolor:01][bracket:REPEATS]
      [tooltip: Saturation inside the feedback loop. The repeats thicken and compress as they go round, and the loudest of them shorten. 0 = off]",
      0, 0, 100, 0.1)) / 100 : smooInit;

// --- Modulation ---

// Detunes the repeats so a long feedback tail moves instead of standing still.
// One LFO drives both channels, with a settable phase difference between them
// -- see modPhase.
modRate = uiRepeats(hslider("[24]Mod Rate[style:knob][unit:Hz][scale:log][symbol:mod_rate][label:Mod Rate][accentcolor:03][bracket:REPEATS]
      [tooltip: Speed of the pitch modulation on the delay lines]",
      0.4, 0.02, 8, 0.001));

modDepthMs = uiRepeats(hslider("[25]Mod Depth[style:knob][unit:ms][symbol:mod_depth][label:Mod Depth][accentcolor:03][bracket:REPEATS]
      [tooltip: How far the delay time is swung by the modulation. 0 = off]",
      0, 0, 20, 0.01)) : smooInit;

// The phase difference between the two channels' modulation, which up to now
// was not a control at all: the code read modR = -modL, and negating a sine is
// a 180 degree shift, so the plugin was hard-wired to one end of this knob.
//
// The range and the wording follow u-he's Colour Copy, whose manual defines
// its Stereo Phase as "the phase difference between the left and right LFO
// signal: At 0, modulation is the same in both channels, while at 180 it
// moves in perfect opposition". 0 to 180 covers every distinct setting: a
// difference of 270 has the same magnitude as 90 with the channels swapped,
// and this plugin already has Ping-Pong L / R for handedness.
//
// What the knob is worth: at 180 the pitch drifts up on one side while it
// drifts down on the other, which is the widest the modulation can sound and
// the reason it was the hard-wired value. At 0 both lines sweep together, so
// the wobble is centred and mono-compatible -- the whole tail moves as one
// object instead of swirling. Between them the two sides move out of step
// without cancelling, and 90 in particular gives a circular drift rather than
// a back-and-forth one.
//
// Smoothed, because sweeping it is a real gesture: the offset lands inside a
// sine argument, so a step would jump the right channel's LFO to a new value
// and put a corner in the delay time. Swept, it reads as a momentary detune of
// the right side, which is what it physically is.
stereoPhaseDeg = uiRepeats(hslider("[26]Stereo Phase[style:knob][unit:deg][symbol:mod_stereo_phase][label:Stereo Ph][accentcolor:03][bracket:REPEATS]
      [tooltip: Phase difference between the left and right modulation. 0 = both channels sweep together, 180 = they move in opposition. Inert at Depth 0]",
      180, 0, 180, 0.1)) : smooInit;

modPhase = stereoPhaseDeg * ma.PI / 180.0;

// os.osc rather than the resonant os.oscrs chorus.dsp uses: this LFO has to
// stay accurate down to 0.02 Hz, where a two-pole resonator's amplitude is at
// the mercy of its own coefficient rounding.
//
// The right channel is os.oscp, which is not a second oscillator: it is
// oscsin*cos(phase) + osccos*sin(phase), a quadrature rotation of the same
// pair of table reads. Both read phasor(tablesize, modRate), the identical
// sub-expression, so Faust shares one phasor between them and the two channels
// are locked by construction -- they cannot drift apart the way two
// independently running LFOs at a nominally equal rate would. Confirmed in the
// generated C: the sine and cosine tables are indexed by the same iTemp, off
// one phasor state, and the whole file holds four phasors -- three machine
// LFOs and this one.
//
// At the 180 default this is not quite bit-identical to the old modR = -modL.
// cos(pi) rounds to exactly -1 in float, but sin(pi) is -8.7e-8 rather than 0,
// so a trace of the cosine leaks into the right channel. As a delay time that
// is 1.7 nanoseconds at the 20 ms Depth maximum -- but the number worth
// quoting is what it does to the output, since a delay-time error becomes an
// output error scaled by the signal's slope at the tap and then multiplied
// around the loop. Rendered against the previous build at Feedback 70 it
// measures -70 dB at Depth 5 and -75 dB at Depth 20, i.e. it does not even
// grow monotonically with Depth, because how much a nudge of the tap changes
// the output depends on what the tap is sitting on.
//
// At the Depth 0 default the whole term is multiplied by zero and the old and
// new builds are bit-identical, verified in all three modes.
modL = os.osc(modRate)             * modDepthMs;
modR = os.oscp(modRate, modPhase)  * modDepthMs;

// --- Mode-specific time modulation ---

// Wow and flutter are what separate a tape echo from a low pass. Depths are in
// ms and stay put regardless of the delay time, so they are proportionally
// enormous on a 20 ms slap and subtle on a half-second echo -- which is how
// the machines behave, the transport wobbling by a fixed amount of tape
// whatever the head spacing.
tapeWow     = os.osc(0.7)  * 0.9;    // ms, capstan/reel eccentricity
tapeFlutter = os.osc(6.3)  * 0.12;   // ms, faster idler-scrape component
bbdDrift    = os.osc(0.35) * 0.4;    // ms, clock oscillator drift

isTape = float(mode == 1);
isBbd  = float(mode == 2);

// Not crossfaded on a mode change, unlike ppL / ppR: switching mode already
// swaps the whole colour block, so the output is discontinuous there whatever
// this does, and a mode switch is not a performance gesture.
machineMod = tapeWow * isTape + tapeFlutter * isTape + bbdDrift * isBbd;

// --- De-Esser (head of the wet path) ---

// vocalDoubler.dsp's high-frequency limiter, taken as it stands, with one
// change made deliberately and noted below.
//
// Level-independent: it splits the input into a low ("body") band and a high
// band and compares their envelopes as a ratio in dB, rather than looking at
// the high band's absolute level. A quiet "s" in a quiet passage still spikes
// that ratio, so detection does not depend on overall loudness the way a plain
// high-band compressor does.
//
// Placed ahead of the delay lines, outside the feedback loop, which is the
// whole reason it earns its place here rather than being another tone control.
// A delay is where sibilance does its worst work: an "s" that is merely bright
// in the dry signal comes back four or six more times, and every repeat lands
// in a gap where nothing is masking it. De-essing the feed means sibilance
// never enters the buffer at all -- one pass, and every repeat inherits it.
//
// Inside the loop it would be a different and worse thing. The shelf would be
// re-applied on every circuit, so the reduction would compound and the tail
// would darken by an amount that depends on how sibilant the source was, which
// is Tone's job and is already done better by the Tone filters. Outside, the
// de-esser is a fixed property of what got recorded into the line.

// One macro control drives all four parameters. To retune the feel, edit the
// endpoint pairs: the first value is what the parameter is at Intensity 0%,
// the second at 100%, interpolated linearly in between.
hfLimSplitAt0  = 5000;  hfLimSplitAt100  = 4500;  // Hz   - crossover; lower reaches further down into the "sh" range
hfLimThreshAt0 =   -2;  hfLimThreshAt100 =   -14; // dB   - how far the high band must stick out before it counts
hfLimRatioAt0  =    2;  hfLimRatioAt100  =     8; //      - how hard the excess is squeezed
hfLimRangeAt0  =    0;  hfLimRangeAt100  =    18; // dB   - ceiling on total reduction; 0 at the bottom makes 0% a true bypass

// Level independence cuts both ways: a ratio detector fires on near-silence
// just as happily as on a sibilant, because room tone, hiss and denormals are
// spectrally flat -- i.e. brighter than voice -- so their high/low ratio looks
// exactly like an "s". An absolute gate settles it: below the floor nothing is
// touched at all, and reduction fades in over the knee above it. Not amount-
// dependent; these are "is there signal here" numbers, not taste.
//
// chorus.dsp's copy of this de-esser dropped the gate. Keeping it is the
// reason vocalDoubler.dsp's version was the one taken: a delay tail decaying
// into the noise floor is exactly the flat, quiet material the gate exists to
// leave alone, and it is a condition this plugin reaches on every single note.
hfLimGateDb   = -60;  // dBFS - floor; below this the limiter idles
hfLimGateKnee =  12;  // dB   - fade-in range above the floor (full effect at -48)

lerp(a, b, t) = a + (b - a) * t;

// smooInit where the originals use a bare slider. The macro moves four filter
// and detector constants at once, and this file smooths every control that
// reaches the audio, so stepping the split frequency on an automation ramp
// would be the one place left that could click.
hflim_amount = uiRepeats(hslider("[27]De-Ess[style:knob][unit:%][symbol:deess_amount][label:De-Ess][accentcolor:02][bracket:REPEATS]
      [tooltip: Tames sibilance in the feed to the delay, so an s does not come back on every repeat. Detects the high band relative to the body of the signal, so it works at any level. 0 = off]",
      0, 0, 100, 1)) / 100 : smooInit;

hflim_split  = lerp(hfLimSplitAt0,  hfLimSplitAt100,  hflim_amount);
hflim_thresh = lerp(hfLimThreshAt0, hfLimThreshAt100, hflim_amount);
hflim_ratio  = lerp(hfLimRatioAt0,  hfLimRatioAt100,  hflim_amount);
hflim_range  = lerp(hfLimRangeAt0,  hfLimRangeAt100,  hflim_amount);

// Stereo, unlike vocalDoubler.dsp's mono original, and linked the way
// chorus.dsp links its copy: one gain, derived from the mono sum, drives both
// channels. Two independent detectors would duck the channels by different
// amounts on the same sibilant and swing the stereo image with every "s".
// That argument is the same one gate.dsp makes for its detector and the same
// one duckGain makes below -- three stages in this plugin, one rule.
deEss(l, r) = attach(outL, reductionDb : deess_meter), outR
with {
    // Detection runs on the mono sum only. The gain is linked anyway, and
    // since the reduction is applied by a shelf rather than rebuilt from the
    // bands, the per-channel split is not needed at all: one pass per band.
    //
    // A real highpass, not `mono - lowpass`. Subtracting a Butterworth lowpass
    // does not give a Butterworth highpass: B(s)-1 has a single zero at DC, so
    // the complement rolls off at 6 dB/oct no matter what order the lowpass is,
    // and it overshoots at the corner. Measured against a 5 kHz split, that
    // "high band" was only -6 dB at 1 kHz, -0.1 dB at 2 kHz and +4.7 dB at
    // 5 kHz -- i.e. the detector was fed most of the vowel range plus a
    // resonant bump. The two bands no longer need to be complementary: nothing
    // reconstructs the signal from them, they only feed the followers.
    mono = (l + r) * 0.5;
    low  = fi.lowpass(4, hflim_split, mono);
    high = fi.highpass(4, hflim_split, mono);

    // The EPSILON floor is not cosmetic: on a truly silent input both
    // envelopes are 0, log10(0) is -inf, and diff comes out NaN.
    envDb(att, rel) = an.amp_follower_ar(att, rel) : max(ma.EPSILON) : ba.linear2db;

    hiDb  = high : envDb(0.001, 0.03);
    refDb = low  : envDb(0.001, 0.03);

    // Broadband level, for the gate only. Released slower than the ratio
    // detector so the gate stays open through the tail of a word instead of
    // chattering across the threshold.
    inDb = mono : envDb(0.001, 0.1);
    gate = min(1, max(0, (inDb - hfLimGateDb) / hfLimGateKnee));

    // dB the high band sticks out above the body band, relative to normal
    // voice spectral tilt; only the excess over threshold is limited.
    diff   = hiDb - refDb;
    excess = max(0, diff - hflim_thresh);

    // Gating the reduction rather than the detector keeps the meter honest: it
    // reads 0 when nothing is being done.
    reductionDb = min(excess * (1 - 1 / hflim_ratio), hflim_range) * gate;

    // The reduction is applied as a real high shelf on the full-band signal,
    // not by re-summing the split -- low + high*gr is a shelf too, but an
    // accidental one: the lowpass and its complement differ in phase, so away
    // from unity gain they stop summing flat and the response ripples around
    // the corner.
    //
    // A TPT state variable filter, which is stable under coefficient
    // modulation, and whose shelf mix collapses to (1,0,0) at 0 dB -- so an
    // idle de-esser passes the signal through untouched. That matters more
    // here than in either plugin this came from: at Dry-Wet 0 this whole path
    // is meant to be bit-exactly absent, and at any other setting a wet feed
    // that was merely magnitude-flat rather than identical would comb against
    // the dry half.
    shelf = fi.svf.hs(hflim_split, 0.7, 0 - reductionDb);

    outL = l : shelf;
    outR = r : shelf;
};

// --- Tone (inside the feedback loop) ---

// Applied on every pass, so the repeats narrow progressively rather than being
// filtered once on the way in. Both defaults sit at the end of their range
// where the filter is effectively out of circuit.
hpFreq = uiRepeats(hslider("[28]High Pass[style:knob][unit:Hz][scale:log][symbol:hp_freq][label:HighPass][accentcolor:06][bracket:REPEATS]
      [tooltip: Thins the repeats a little more on every pass, so the tail steps back from the low end. 20 Hz = effectively off]",
      20, 20, 2000, 1));

lpFreq = uiRepeats(hslider("[29]Low Pass[style:knob][unit:Hz][scale:log][symbol:lp_freq][label:LowPass][accentcolor:06][bracket:REPEATS]
      [tooltip: Darkens the repeats a little more on every pass. 20 kHz = effectively off]",
      20000, 200, 20000, 1));

// --- Ducking ---

duck = uiOutput(hslider("[31]Duck[style:knob][unit:%][symbol:duck][label:Duck][accentcolor:04][bracket:OUTPUT]
      [tooltip: Pulls the repeats down while the dry signal plays so they swell into the gaps. 0 = off]",
      0, 0, 100, 1)) / 100 : smooInit;

// Threshold-free, by design: instead of a level the repeats duck *below*,
// the reduction ramps across a fixed 30 dB window from -40 to -10 dBFS. That
// is the range programme material actually occupies, so the knob behaves the
// same on a quiet track as on a loud one and there is no second control to
// set. The cost is that it cannot be aimed at one specific level the way
// gate.dsp's Threshold can.
duckLoDb  = -40;
duckHiDb  = -10;

// 12 dB, halved from the 24 it was first built with. At 24 the knob was not a
// duck, it was a mute with a fade: measured against a 400 ms tone, Duck 100
// held a flat -24.0 dB for as long as the dry lasted, and even Duck 50 sat at
// a flat -12.0.
//
// Flat is the operative word, and it is why the top of this knob has to be
// modest. For any programme material the detector sits well above duckHiDb, so
// drive is pinned at 1 and the level window contributes nothing -- the knob is
// a fixed attenuation whenever the dry is playing, not a proportional one. The
// window only starts to matter below about -25 dBFS. That is a fair design for
// predictability, but it means duckMaxDb is what the control *is* at any
// normal level, rather than a ceiling it rarely reaches.
duckMaxDb = 12;

// Detector timing, and the reason it is split in two -- see duckGain.
//
// The obvious build is one envelope follower with a musical release, mapped
// through the window to a gain. It does not work, and it was measured not
// working before this comment was written: with the release on the *level*,
// recovery has to wait for the level to fall the full width of the window,
// which is 30/8.686 = 3.45 time constants, near enough a second at any
// release worth having. Over a 400 ms gap in 1 kHz tone the reduction moved
// from 24.0 dB to 24.0 dB and the repeats never swelled at all.
//
// So the level follower is fast enough to be nearly instantaneous -- it exists
// only to rectify, holding steady across the cycles of a low note rather than
// carrying any musical timing -- and the release lives on the reduction in dB
// instead. Recovery is then one honest 250 ms one-pole whatever the window is
// doing, which is how a compressor's gain stage is built and for the same
// reason.
duckDetAtt = 0.001;

// 20 ms. This was 30, chosen to span a 30 Hz cycle so the rectifier could not
// sag between the peaks of a low note, and the shorter value no longer clears
// that bar on paper -- 30 Hz is a 33 ms period. Measured rather than reasoned
// about, it does not matter: on a 30 Hz tone quiet enough to sit inside the
// level window, where the drive clamp cannot hide the sag, ripple in the
// applied gain went from 0.03 dB to 0.04 dB. The gain stage below smooths what
// the rectifier lets through. What the 10 ms buys is the front of the
// recovery: the duck used to hold flat for the first 50 ms of a gap before
// starting to let go.
duckDetRel = 0.020;

duckAtt = 0.005;   // fast enough to be under the first syllable

// 120 ms, down from 250. The old value took the better part of a second to
// clear: 390 ms into a silent gap the repeats were still 7.4 dB down out of
// 24, which is most of a bar at any tempo and reads as the delay never coming
// back. At 120 the same gap measures -8.9 dB at 100 ms, -3.9 at 200 and -1.7
// at 300, so the tail is audibly returning inside the space it is meant to
// fill.
//
// The floor under this is pumping between syllables rather than between
// phrases, which is what the old value was buying. See the measurement in the
// comment on duckGain.
duckRel = 0.120;

// --- Mix ---

width = uiOutput(hslider("[32]Width[style:knob][unit:%][symbol:width][label:Width][accentcolor:04][bracket:OUTPUT]
      [tooltip: Stereo width of the repeats only. The dry signal is untouched. 0% mono, 100% unmodified, 200% double width]",
      100, 0, 200, 1)) / 100;

// Dry-kill / wet-kill on one knob, the same shape vocalDoubler.dsp's Dry-Wet
// has. At the centre detent *both* paths pass at unity; turning toward Wet
// pulls the dry down and leaves the wet alone, turning toward Dry does the
// reverse. Only one side ever moves, so this is not a crossfade and the sum
// runs about 6 dB hotter at the centre than at either end.
//
// The taper is linear in amplitude -- the usual mix-knob feel -- so half travel
// is -6 dB on the receding path rather than half of some dB range, which would
// already be inaudible long before the knob got there.
//
// Default -50 rather than the centre. Centre would be full wet on top of full
// dry, which is a great deal of delay to open a session with. -50 puts the wet
// at 0.5 against a dry at unity, a ratio of 0.5 -- near enough the 0.35/0.65 =
// 0.538 the old 0-to-100 knob had at its 35% default, so the plugin still
// sounds like itself out of the box.
drywetPct = uiOutput(hslider("[33]Dry-Wet[style:knob][unit:%][symbol:drywet][label:Dry-Wet][accentcolor:01][bracket:OUTPUT][easy]
      [tooltip: Balance of repeats against dry. At the centre both pass at full level; toward Wet pulls the dry down, toward Dry pulls the repeats down]",
      -50, -100, 100, 0.1)) / 100 : smooInit;

// The mute floor, and the reason it is a bare comparison rather than the
// db2linear(linear2db(x)) round-trip vocalDoubler.dsp writes.
//
// That original reads faderGain(db) = db2linear(db) * (db > -70) applied to
// linear2db(max(1e-6, 1-a)), which is a log and a pow per sample per leg --
// four transcendentals for a mix knob. Since db2linear(linear2db(x)) is x, the
// whole thing collapses to (1-a) gated on (1-a) > db2linear(-70), which is one
// compare and one multiply. Checked against the original expression at 100001
// points across the travel: the two agree to 6e-8, one float ulp, and the
// collapsed form is the more accurate of the two because it never makes the
// round trip. The mute engages at the identical place, a = 0.99969.
//
// The floor has to exist at all so that the ends of the travel silence their
// path outright instead of leaving a -80 dB residue of it.
faderMinLin = ba.db2linear(-70);

fade(amount) = (1 - amount) * ((1 - amount) > faderMinLin);

mixDry = fade(max(0.0, drywetPct));
mixWet = fade(max(0.0, 0 - drywetPct));

// --- Meter ---

deess_meter = uiMeters(hbargraph("[1]HFlim Reduction[unit:dB][symbol:deess_meter]", 0, 30));
duck_meter  = uiMeters(hbargraph("[2]Duck Reduction[unit:dB][symbol:duck_meter]", 0, duckMaxDb));

// --- Nonlinearities ---

// The loop's only unconditional guarantee. tanh scaled to rail: for a signal
// at 0 dBFS it costs 0.18 dB and a third harmonic near -50 dB, so Digital is
// clean by any reasonable reading of the word; above +12 dBFS nothing gets
// through at all. It is what makes Feedback 100% a sustain rather than an
// overflow, and it is why no Drive control was needed to keep the engine safe.
rail = 4.0;
softRail(x) = rail * ma.tanh(x / rail);

// Gentler than a rail and always in circuit for the coloured modes: the
// asymmetric-free odd-harmonic curve of a tape stage driven a little warm.
// 0.5 in gives 0.4475 out, about a dB down, which is where the harmonics
// become audible as thickening rather than as distortion.
tapeSat(x) = ma.tanh(x * 1.2) / 1.2;
bbdSat(x)  = ma.tanh(x * 1.8) / 1.8;

// The Drive knob's saturator, in the loop and therefore applied once per pass.
//
// Normalised by k rather than by tanh(k), and that choice is the whole reason
// this is safe to put in a feedback path. The slope at the origin is
//
//     d/dx [ tanh(kx)/k ] at x=0  =  1
//
// for every k, so however hard it is driven a quiet signal passes at exactly
// unity and the loop gain stays exactly Feedback. Normalising by tanh(k)
// instead -- the obvious way to stop Drive from costing level -- gives a
// small-signal gain of k/tanh(k), which is 2.07 at k=2 and 4.00 at k=4. That
// multiplies the feedback: the loop would run away at any Feedback above about
// 48% with the knob at a quarter travel, softRail would catch it, and the
// Feedback control would stop meaning anything above that point. Level was not
// worth that.
//
// Since tanh(u) <= u for u >= 0, this stage's gain never exceeds 1 at any
// level, so it can only ever shorten the tail, never lengthen it. That is also
// what the knob sounds like and what the machines it is borrowed from do: on a
// tape echo, driving the record stage harder makes the repeats thicker and
// makes them die sooner, because the loss that produces the distortion is the
// same loss that eats the regeneration. It is not a defect to compensate for.
//
// Two details make Drive 0 an exact bypass rather than merely a quiet one.
//
// kMin keeps k off zero so the divide cannot produce a NaN, which matters more
// than it looks: the project builds with -ffast-math, and a NaN on the
// unselected side of a blend is not reliably discarded.
//
// driveOn then gates the saturated branch away entirely at the bottom of the
// knob. Without it, k*x followed by a divide by k does not round-trip exactly
// in float -- one multiply and one divide, neither exact -- and while that is
// only -130 dB on a single pass, the feedback loop returns it to itself and it
// settles around -78 dB. Measured, and measured again at kMin of 1e-2, 1e-3,
// 1e-4 and 1e-5: the figure does not move, which is what identifies it as the
// round-trip rather than the k^2*x^3/3 truncation, since that term would have
// fallen by 80 dB across that range. Inaudible either way -- it is a level
// error of 0.001 dB that tracks the signal down and never diverges -- but a
// knob at zero should do nothing at all, and this way it provably does.
//
// The gate reaches full by Drive 2%, where k is 0.08 and the saturator is
// still within 1e-4 dB of a straight wire, so nothing audible happens inside
// the ramp and everything above it is the pure series curve.
driveKMax = 4.0;
driveKMin = 0.001;

driveK  = max(driveKMin, drive * driveKMax);
driveOn = min(1.0, drive * 50.0);

driveSat(x) = it.interpolate_linear(driveOn, x, ma.tanh(driveK * x) / driveK);

// --- Colour blocks ---

// One pass of a mode's character. These sit inside the feedback loop, after
// the delay tap, so the first repeat has been through them once and the nth
// repeat n times -- which is the whole point: a bucket-brigade echo is not
// dark, it *gets* dark.
//
// The user Tone filters are in here too rather than in a separate stage, so
// there is exactly one filter chain per pass to pay for.
tone = fi.highpass(2, hpFreq) : fi.lowpass(2, lpFreq);

// Flat: the user's Tone filters and nothing else. Drive and softRail are
// applied after the mode select, so at Drive 0 this branch is the identity to
// within what the Tone filters are set to do.
colourDigital = tone;

// 45 Hz to 6.5 kHz with a +3 dB bump at 90 Hz. The bump is the head/tape
// resonance every tape echo has and is what stops the mode reading as a plain
// low pass -- the repeats lose their top while gaining a little weight, so
// they sit under the dry rather than merely behind it.
colourTape = fi.highpass(1, 45)
           : fi.peak_eq_cq(ba.db2linear(3), 90, 1.2)
           : fi.lowpass(2, 6500)
           : tone
           : tapeSat;

// 120 Hz to 3 kHz, a third-order low pass rather than second: the
// reconstruction filter after a bucket-brigade line is steep, and a gentle
// rolloff here leaves the repeats sounding merely muffled instead of narrow.
colourBbd = fi.highpass(2, 120)
          : fi.lowpass(3, 3000)
          : tone
          : bbdSat;

// All three are computed every sample and one is selected. The waste is three
// short filter chains, not three delay lines -- the lines are shared, which is
// what makes running every branch affordable. Computing only the live branch
// would mean switching the *state* of the filters, and a mode change would
// then land on cold biquads.
//
// Drive and softRail sit after the select rather than inside each branch,
// which is both correct and cheaper: they are mode-independent, and one tanh
// each here replaces three copies of softRail there. Counted in the generated
// C, the colour stage costs four tanh per sample per channel, against the five
// it cost before Drive existed -- adding the feature made it cheaper.
//
// Order matters at the end of this chain. Drive is a character and softRail is
// a safety rail, so the rail goes last and gets the final word: whatever Drive
// is set to, nothing leaves this block above +12 dBFS.
colour = _ <: (colourDigital, colourTape, colourBbd) : ba.selectn(3, mode)
       : driveSat
       : softRail;

// --- Delay line ---

// Floored at 4 samples: de.fdelay4's Lagrange interpolator reads a span of
// taps around the fractional position, so too short a delay would run the read
// pointer past the write pointer. Fourth order rather than the linear de.fdelay
// flanger.dsp uses, because a linear interpolator is a two-point average when
// the fractional part sits near 0.5, which is 2.0 dB down at 10 kHz. Here the
// signal goes back through the same tap on every pass, so that loss compounds
// and a long tail would darken for a reason that has nothing to do with the
// mode -- and in Digital, which is meant to be flat, for no reason at all.
minSamples = 4.0;

// The glide is applied to the base time alone and the modulation added after.
// Putting the LFO ahead of the one-pole would low-pass the modulation itself,
// so Depth would quietly mean less and less as Rate went up.
delaySamples(baseMs, modMs) =
    (baseMs * ma.SR / 1000.0 : timeGlide) + ((modMs + machineMod) * ma.SR / 1000.0)
    : max(minSamples) : min(float(MAXTAP));

line(baseMs, modMs) = de.fdelay4(MAXTAP, delaySamples(baseMs, modMs));

// --- Engine ---

// Two lines with a crossable feedback path. fwd carries the delay taps and the
// colour; fb carries only the feedback gain, so the character is applied once
// per pass and the first repeat is already coloured.
//
// The `~` contributes one sample of loop delay on top of the tap, so the
// delay is one sample longer than the control says -- measured at 4801 samples
// for a 100 ms setting at 48 kHz. That is 0.02% there, and at the 1 ms minimum
// it is 2%. Nothing here is tuned to a pitch, so unlike a Karplus-Strong loop
// it is not compensated: subtracting the sample back would push minSamples up
// and buy an error nobody can hear at any setting anyone uses.
engine = fwd ~ fb
with {
    // The morph between topologies. At ppAmt 0 each line is fed its own tail;
    // at 1 they are exchanged, so a repeat alternates across the channels. In
    // between both are present, which reads as a stereo delay with crosstalk
    // and is a usable setting rather than merely a transition.
    //
    // ppL and ppR are mirror images: whichever one is up decides which line
    // receives the input and therefore which side the first repeat lands on.
    // The two directions do not carry the same gain, and that asymmetry is the
    // whole answer to "why is there nothing on the other side at Feedback 0".
    //
    // At zero feedback there is exactly one repeat -- the second repeat is by
    // definition the first one fed back, so a geometric tail with ratio g puts
    // repeat 2 at amplitude g, and repeat 2 is the right-hand one. Wire the
    // L->R hand-off through Feedback and the right channel is silent whenever
    // Feedback is, which is a trap: Ping-Pong that does not pong, reachable by
    // turning one knob to a perfectly ordinary value.
    //
    // So the hand-off is structural and runs at unity, and Feedback buys the
    // *return* that closes the ring. Ping-Pong then always bounces at least
    // once, and Feedback means what it says on a hardware unit: how much
    // survives a full round trip, rather than how much survives one hop.
    //
    // What this costs is worth naming, because the previous wiring was not
    // arbitrary. With both directions at g the ping-pong tail was bit-identical
    // to Normal's -- the same decay, merely panned alternately, so the pingpong
    // morph changed the image and nothing else. That parity is gone: repeats
    // now arrive in equal-level pairs (1, 1, g, g, g^2, g^2) and the tail runs
    // about twice as long in seconds at the same knob setting. Both are
    // defensible; this one has no dead state in it.
    //
    // Stability across the morph, since the two gains are no longer equal. The
    // loop matrix is [[g(1-p), g*p], [p, g(1-p)]] with p = ppAmt, whose
    // spectral radius is g(1-p) + p*sqrt(g). Since g <= sqrt(g) <= 1 over the
    // knob's range, and p is clamped to <= 1 where it is defined, that is at
    // most sqrt(g)(1-p) + p*sqrt(g) = sqrt(g) <= 1 --
    // unconditionally stable, and exactly marginal at Feedback 100 where the
    // ring sustains rather than grows. The matrix is symmetric in the two
    // handednesses -- swapping ppL for ppR transposes it, which leaves the
    // spectral radius alone -- so the bound covers Ping-Pong R unchanged, and
    // it also covers the direct L-to-R transition, where the off-diagonals
    // are the blends (g*ppL + ppR) and (ppL + g*ppR) and the product under the
    // root is still at most g. softRail is behind all of it either way.
    ppHandoff = 1.0;

    // The Normal branch's two gains. At Cross 0 selfG is Feedback and crossG
    // is exactly zero, so that branch collapses to the single term it was
    // before this control existed -- bit-identically, since adding a product
    // with zero and multiplying by one are both exact.
    selfG  = feedback * (1 - crossFb);
    crossG = feedback * crossFb;

    // Read a row at a time: in Normal, own tail at selfG plus the other
    // channel's at crossG; the *return* leg at feedback when this channel is
    // the one the ring comes back to; and the *hand-off* at unity when this
    // channel is the one being handed to.
    //
    // Cross only touches the Normal branch. In Ping-Pong the crossing is
    // already total and the two remaining terms are the ring, so there is
    // nothing for a partial cross to trade against.
    crossL(wL, wR) = (wL * selfG + wR * crossG) * (1 - ppAmt)
                   + wR * feedback   * ppL
                   + wR * ppHandoff  * ppR;

    crossR(wL, wR) = (wR * selfG + wL * crossG) * (1 - ppAmt)
                   + wL * ppHandoff  * ppL
                   + wL * feedback   * ppR;

    // Ping-pong also has to change what goes *in*, and this is where the
    // handedness is actually decided. A true ping-pong puts the whole input
    // into one line and lets the crossed hand-off carry it to the other, so
    // the first repeat is hard on the fed side and the second hard on the
    // other. Feed both lines directly and the alternation collapses: every
    // repeat would appear on both sides at once. The input is summed to mono
    // on the way in -- the unfed line receives no direct signal at all -- and
    // the sum is halved so a correlated stereo source does not gain 6 dB
    // crossing the switch.
    inL(l, r) = l * (1 - ppAmt) + (l + r) * 0.5 * ppL;
    inR(l, r) = r * (1 - ppAmt) + (l + r) * 0.5 * ppR;

    fwd(fbL, fbR, l, r) = wetL, wetR
    with {
        wetL = inL(l, r) + crossL(fbL, fbR) : line(baseMsL, modL) : colour;
        wetR = inR(l, r) + crossR(fbL, fbR) : line(baseMsR, modR) : colour;
    };

    // Raw wet, ungained: the two feedback gains differ by direction now, so
    // they are applied in crossL / crossR where that asymmetry is visible.
    fb(wL, wR) = wL, wR;
};

// --- Ducking gain ---

// One gain from a mono detector drives both channels, as gate.dsp's does and
// for the same reason: two independent detectors would duck the sides by
// different amounts on the same syllable and swing the image with it.
//
// The detector reads the *dry* input, not the wet, so the repeats duck out of
// the way of the source rather than out of the way of themselves -- feeding it
// the wet signal would make the reduction part of the feedback path and the
// tail would gate itself.
duckGain(l, r) = gain
with {
    // Rectification, not timing. Floored before the log because a gap is
    // digital silence and linear2db(0) is -inf.
    env   = abs(l) + abs(r) : an.amp_follower_ar(duckDetAtt, duckDetRel);
    envDb = env : max(ba.db2linear(duckLoDb - 1)) : ba.linear2db;

    // 0 below -40 dBFS, 1 above -10, linear in dB between. Clamped at both
    // ends so a loud passage cannot duck past the knob's setting.
    //
    // Named duckDrive, not drive: `drive` is now the Drive control at file
    // scope, and a local of that name here would silently shadow it. Nothing
    // in this block wants the Drive knob today, which is exactly why the
    // collision would be found late.
    duckDrive = (envDb - duckLoDb) / (duckHiDb - duckLoDb) : max(0.0) : min(1.0);

    // The timing, applied to the reduction rather than to the level.
    // si.onePoleSwitching takes its attack coefficient when the input rises,
    // and what rises here is the number of dB being removed -- so the fast
    // constant lands on ducking down and the slow one on swelling back, which
    // is the way round a delay needs.
    //
    // The pumping check for duckRel, since 120 ms is fast enough to start
    // tracking syllables rather than phrases. On 150 ms on / 100 ms off -- a
    // syllable rate, tighter than any gap the duck is meant to fill -- the
    // applied gain swings 3.3 dB, between -12.0 and -8.7. That is the duck
    // breathing with the line, not pumping.
    //
    // The old 250 ms swung 1.73 dB on the same signal, which looks steadier
    // until you read the absolute figures: it sat between -24.0 and -22.3, so
    // the reason it did not move is that it never recovered at all. Stillness
    // there was the symptom, not the virtue.
    redDb = duck * duckMaxDb * duckDrive : si.onePoleSwitching(duckAtt, duckRel);

    gain  = ba.db2linear(0 - redDb) : attach(_, redDb : duck_meter);
};

// --- Output ---

// Width acts on the wet signal only. The dry path is left exactly as it
// arrived, so a Width of 0 narrows the repeats to the centre without
// collapsing the source with them.
stereoWidth(l, r) = m + s, m - s
with {
    m = (l + r) * 0.5;
    s = (l - r) * 0.5 * width;
};

// The two legs are scaled by mixDry and mixWet, which are never both below
// unity: see drywetPct. That rules out the equal-power crossfade flanger.dsp
// uses, and deliberately -- that one exists because a flanger's comb is
// deepest with both legs at equal amplitude, so its 3 dB dip in the dry at the
// centre detent is buying something. A delay does not comb against its dry, so
// the dip would be pure loss.
delayFx(l, r) = outL, outR
with {
    g = duckGain(l, r);

    // De-essed on the way in, so sibilance never reaches the delay line and
    // therefore never reaches any repeat. The dry leg below and duckGain above
    // both read l and r untouched: this is the wet path's own stage.
    wet = (l, r) : deEss : engine : stereoWidth;
    wetL = wet : _, !;
    wetR = wet : !, _;

    outL = l * mixDry + wetL * g * mixWet;
    outR = r * mixDry + wetR * g * mixWet;
};
