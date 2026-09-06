declare author "Klaus Scheuermann";
declare description "Loudness leveler: BS.1770 short-term control with integrated-loudness trim";
declare license "GPL-3.0-or-later";
declare name "Leveler";
declare unique_id "LAlv";


import("stdfaust.lib");

//======================================================================
// Configuration
//======================================================================

Nch = 2;

// Highest sample rate the exact (sliding rectangular) LUFS windows are
// dimensioned for. Each short-term window allocates roughly
// 2 * shortTermWindow * maxSR floats, so this is by far the biggest
// contributor to the plugin's memory footprint: dropping it to 96000
// halves it.
maxSR = 192000;

meters_minimum = -60;

// BS.1770-4 / EBU R128 constants
shortTermWindow = 3.0;    // LUFS-S integration window            [s]
momentaryWindow = 0.4;    // LUFS-M integration window            [s]
gateAbsolute    = -70.0;  // absolute gate                     [LUFS]
gateRelative    = -10.0;  // relative gate, below the gated mean [LU]

// Leveler internals
detectWindowSlow = 6.0;   // control detector window at speed 0   [s]
detectWindowFast = 1.0;   // control detector window at speed 1   [s]
// Brake timing. Closing the brake only freezes the gain, so it is the safe
// direction and is made fast; the hold is what rides through the gaps
// between syllables, and it is the only thing that should delay a close.
brakeWindow  = 0.06;      // brake level detector window          [s]
brakeKnee    = 6.0;       // brake soft knee                     [LU]
brakeHold    = 0.15;      // brake hold time                      [s]
brakeAttack  = 0.02;      // brake opening time constant          [s]
brakeRelease = 0.03;      // brake closing time constant          [s]
trimWarmup   = 2.0;       // gated programme before trim engages  [s]
trimRatio    = 1.5;       // trim loop slowness vs. its detector

// Defaults
init_target       = -23;
init_maxboost     = 12;
init_maxcut       = 12;
init_brake_thresh = -22;
init_speed_up     = 80;
init_speed_down   = 80;
init_boost_scale  = 100;
init_cut_scale    = 100;
init_brake_hp     = 1;
init_brake_lp     = 20000;
init_trim_range   = 3;
init_trim_window  = 30;


//======================================================================
// Process
//======================================================================
//
// The leveler runs two nested control loops, both of which regulate a
// *gated mean power* rather than an instantaneous level:
//
//   * a fast feed-forward loop that drives the rolling, BS.1770-gated
//     loudness of the input towards `target`, and
//   * a slow feedback loop that measures the same quantity on the real
//     output over a much longer window -- a rolling LUFS-I -- and trims
//     the gain so that the integrated measurement lands on `target` too.
//
// Averaging power (not dB) and gating out pauses is what keeps the
// programme *measuring* the target rather than merely hovering around it.
// LUFS-I is an energy mean over gated blocks, so a leveler that smooths
// its gain in the dB domain always lands high: level swings of +/- s dB
// around the target contribute roughly 0.115*s^2 dB of excess energy, and
// on syllabic material that is easily one to two dB. Regulating the gated
// power removes the bulk of it; the trim integrator removes what is left
// over from gain clamping and braked passages.

process = si.bus(Nch) : pregain(Nch) : (leveler ~ si.bus(2)) : (!,!,_,_);


//======================================================================
// UI
//======================================================================

// --- UI structure ---
//
// Five control groups, flat and named for what they contain, plus the two
// unnamed collectors the suite keeps for things that are not controls.
//
// Nothing in the C++ reads the group names -- FaustParameter carries a bracket
// and no group (see FaustParameters.hpp). What the plugin's own GUI reads is
// the [bracket:] on each control, and it builds a bracket out of a *run* of
// consecutive parameters sharing one (ui/widgets-todo/knob-group.hpp), so a
// bracket split across the [nn] indices would be drawn as two boxes with the
// same name. The groups are therefore kept aligned with the brackets, member
// for member, so a control in the right group is contiguous with its bracket
// by construction.
//
// The [nn] prefixes are two digits, as in delay.dsp and gate.dsp, because
// Faust orders widgets by sorting those strings rather than reading them as
// numbers: with single digits "[10]" sorts between "[1]" and "[2]" and the
// generated parameter list comes out interleaved.

uiLeveler(x) = hgroup("[0]LA LEVELER", x);

uiTarget(x) = uiLeveler(hgroup("[0]TARGET", x));

// uiGain(x)  = uiLeveler(hgroup("[0]GAIN", x));
uiLevel(x) = uiLeveler(vgroup("[1]LEVELER", x));
uiLimit(x) = uiLeveler(hgroup("[2]LIMITS", x));
uiBrake(x) = uiLeveler(hgroup("[3]BRAKE", x));
uiLufsI(x) = uiLeveler(hgroup("[4]LUFS-I", x));

// Not a control: written every cycle by the RNNoise speech detector in
// LibreAudioPlugin.cpp, which re-flags it there as a hidden output. It is a
// slider only because that is how a value gets *into* a Faust DSP, so it is
// parked last and outside every bracket, where it interrupts no run.
uiExtern(x) = uiLeveler(hgroup("[8]External", x));

// Unnamed and last, as in gate.dsp and chorus.dsp: the meters are not a
// control group and the suite's UIs find them by symbol.
uiMeters(x) = uiLeveler(hgroup("[9]Meters", x));

// What the five groups mean:
//
//   GAIN     the two fixed trims either side of the leveler. Neither is part
//            of a control loop: PreGain moves what the leveler is asked to
//            correct, PostGain is an offset the leveler deliberately does not
//            chase, so it survives as an offset on the delivered loudness.
//   LEVELER  where the programme should sit, and how fast it is allowed to
//            get there.
//   LIMITS   how far the gain may travel, and how much of the correction is
//            actually applied once it has been computed.
//   BRAKE    what counts as programme at all. Everything here shapes the one
//            decision "is there something to level right now", which gates
//            both control loops and both the LUFS-I readings.
//   LUFS-I   the slow integrated-loudness trim: how much authority it has and
//            how much programme it averages before acting.

// --- Gain ---

preGainSlider = 0; //uiGain(vslider("[01]PreGain[style:knob][unit:dB][symbol:pregain][label:PreGain][accentcolor:02][bracket:GAIN]", 0, -20, 20, 0.1));

postGainSlider = 0; //uiGain(vslider("[02]PostGain[style:knob][unit:dB][symbol:postgain][label:PostGain][accentcolor:02][bracket:GAIN]", 0, -20, 20, 0.1));

// --- Leveler ---

target = uiTarget(vslider("[1]Target[unit:dB][symbol:target][label:Target][accentcolor:01][bracket:LEVELER]",
      init_target, -60, 0, 0.1));

leveler_speed_up = uiLevel(vslider("[12]Speed Up[style:knob][unit:%][symbol:speed_up][label:Speed Up][accentcolor:01][bracket:LEVELER]",
      init_speed_up, 0, 100, 1)) * 0.01;

leveler_speed_down = uiLevel(vslider("[13]Speed Down[style:knob][unit:%][symbol:speed_down][label:Speed Down][accentcolor:01][bracket:LEVELER]",
      init_speed_down, 0, 100, 1)) * 0.01;

// --- Limits ---

maxboost = uiLimit(vslider("[21]Max Boost[style:knob][unit:dB][symbol:maxboost][label:Max Boost][accentcolor:05][bracket:LIMITS]",
      init_maxboost, 0, 30, 1));

max_cut = uiLimit(vslider("[22]Max Cut[style:knob][unit:dB][symbol:max_cut][label:Max Cut][accentcolor:05][bracket:LIMITS]",
      init_maxcut, 0, 30, 1)) : ma.neg;

scale_boost = uiLimit(vslider("[23]Boost Scale[style:knob][unit:%][symbol:scale_boost][label:Boost Scale][accentcolor:05][bracket:LIMITS]",
      init_boost_scale, 0, 100, 1)) * 0.01;

scale_cut = uiLimit(vslider("[24]Cut Scale[style:knob][unit:%][symbol:scale_cut][label:Cut Scale][accentcolor:05][bracket:LIMITS]",
      init_cut_scale, 0, 100, 1)) * 0.01;

// --- Brake ---

// Expressed in LU below `target`: the brake starts to close when the levelled
// programme drops this far under the target.
leveler_brake_thresh = target +
    uiBrake(vslider("[31]Brake Threshold[style:knob][unit:dB][symbol:brake_threshold][label:Threshold][accentcolor:06][bracket:BRAKE]",
      init_brake_thresh, -90, 0, 1));

brake_hp_freq = uiBrake(vslider("[32]Brake SC High Pass[style:knob][unit:Hz][scale:log][symbol:brake_hp][label:SC HP][accentcolor:06][bracket:BRAKE]",
      init_brake_hp, 1, 500, 1));

brake_lp_freq = uiBrake(vslider("[33]Brake SC Low Pass[style:knob][unit:Hz][scale:log][symbol:brake_lp][label:SC LP][accentcolor:06][bracket:BRAKE]",
      init_brake_lp, 20, 20000, 1));

// 0 = internal level detector only, 1 = external VAD only, in between blends.
//detection_mode = uiBrake(vslider("[34]Detect[style:knob][symbol:detection_mode][label:Detect][accentcolor:06][bracket:BRAKE]", 0, 0, 1, 0.01));
detection_mode = uiBrake(nentry("[01]Detect[style:radio{'Threshold':0;'Speech':1}][symbol:mode]", 0, 0, 1, 1));
  

// --- LUFS-I trim ---

// Authority of the integrated-loudness trim. 0 disables it and turns the
// leveler back into a pure short-term device.
trim_range = uiLufsI(vslider("[41]Trim Range[style:knob][unit:dB][symbol:trim_range][label:Trim][accentcolor:04][bracket:LUFS-I]",
      init_trim_range, 0, 6, 0.1));

// Memory of the rolling integrated measurement. Short values track a live
// programme, long values behave like a whole-file LUFS-I measurement.
trim_window = uiLufsI(vslider("[42]Trim Window[style:knob][unit:s][scale:log][symbol:trim_window][label:Window][accentcolor:04][bracket:LUFS-I]",
      init_trim_window, 5, 120, 1));

// --- External speech detection ---

vad = dpf_vad : si.smoo;
dpf_vad = uiBrake(vslider("[01]dpf_vad[symbol:dpf_vad]", 0, 0, 1, 0.001));

// --- Meters ---

leveler_meter_gain = uiMeters(vbargraph("[1]Gain[unit:dB][symbol:gain_meter]", -50, 50));

// Shown as the amount of braking, so 0% is a leveler running freely.
meter_leveler_brake = _*100 : uiBrake(vbargraph("[2]Brake[unit:%][symbol:brake_meter]", 0, 100));

meter_lufs_in = uiTarget(vbargraph("[0]LUFS-S In[unit:dB][symbol:lufs_in]", meters_minimum, 0));
meter_lufs_out = uiMeters(vbargraph("[4]LUFS-S Out[unit:dB][symbol:lufs_out]", meters_minimum, 0));
meter_lufs_i = uiLufsI(vbargraph("[5]LUFS-I[unit:dB][symbol:lufs_i]", meters_minimum, 0));
meter_trim = uiLufsI(vbargraph("[6]Trim[unit:dB][symbol:trim_meter]", -6, 6));


//======================================================================
// Gain utilities
//======================================================================

pregain(n) = par(i, n, gain) with {
    gain = _ * (preGainSlider : ba.db2linear : si.smoo);
};

postGainLin = postGainSlider : ba.db2linear : si.smoo;


//======================================================================
// Loudness measurement (ITU-R BS.1770-4)
//======================================================================

// NOTE: fi.itu_r_bs_1770_4_kfilter is normalised to unity gain at 997 Hz,
// which already accounts for the -0.691 dB term of BS.1770-4 eq. (2). The
// offset must therefore NOT be applied again here -- doing so reads 0.691 LU
// low and makes the leveler settle 0.691 dB above target. Verified against
// libebur128: a 1 kHz sine at -23 dBFS RMS in both channels reads -20.0 LUFS.
kfilter = fi.itu_r_bs_1770_4_kfilter;

sq(x) = x * x;

// Loudness of a K-weighted, channel-summed mean-square power, and back.
lufs(p) = 10.0 * log10(max(p, 1e-12));
lufs2power(lu) = pow(10.0, lu / 10.0);

// Exact BS.1770 mean square: sliding rectangular window of T seconds.
// Numerically stable "forever" (ba.slidingSump), which matters because the
// summed signal is strictly positive.
meanSquare(T) = ba.slidingSump(n, T*maxSR) / max(n, 1.0) with { n = rint(T*ma.SR); };

// Cheap mean square with the same equivalent noise bandwidth as a
// rectangular window of T seconds (ENBW 1/T vs. 1/(2*tau)). Used wherever
// the value feeds a control loop rather than a meter, which saves the
// sliding-window tables entirely.
meanSquareFast(T) = si.smooth(ba.tau2pole(T * 0.5));

// Gate thresholds as power ratios, so the gate needs no logarithms.
gateAbsolutePower = pow(10.0, gateAbsolute / 10.0);
gateRelativeRatio = pow(10.0, gateRelative / 10.0);

// Rolling, BS.1770-gated loudness of a K-weighted power signal.
//
//   win  : length of the exponential window, in seconds
//   gate : 0..1, how much of the programme this instant counts as; the
//          window only ages while it is open, so a pause neither drags the
//          measurement down nor erases the programme that came before it
//   refP : ceiling for the relative gate's reference power; pass 0 to use
//          the absolute gate alone
//
// This is the recommendation's gating with an exponential instead of an
// infinite memory, which is what a continuous programme needs. The relative
// gate references the running gated mean -- the usual real-time stand-in
// for the two-pass computation -- but capped at `refP`. Without that cap a
// programme that drops more than `gateRelative` below the running mean gates
// itself out permanently and the measurement freezes; capping the reference
// at the target power means a levelled signal can always gate itself back in.
//
// The accumulator is bias corrected: `w` tracks the total weight applied so
// far, so `s/w` is an exact running mean from the very first gated sample
// and relaxes into an exponential average of `win` seconds as the window
// fills. Without it the measurement would need a full window to become
// usable and would drag the trim with it.
//
// Outputs the loudness in LUFS and the accumulated weight, the latter being
// zero until the first gated block has been seen.
gatedLoudness(win, gate, refP, p) = (accumulate ~ si.bus(2)) : report
with {
    a = 1.0 - exp(0.0 - 1.0 / max(1.0, win * ma.SR));
    pm = p : meanSquareFast(momentaryWindow);
    accumulate(sPrev, wPrev) = s, w
    with {
        mean = sPrev / max(wPrev, 1e-12);
        open = (pm > gateAbsolutePower)
             & (pm >= min(mean, refP) * gateRelativeRatio);
        k = gate * open * a;
        s = sPrev + k * (pm - sPrev);
        w = wPrev + k * (1.0 - wPrev);
    };
    report(s, w) = (s / max(w, 1e-12) : lufs), w;
};

//======================================================================
// Leveler
//======================================================================
//
// Feedback bus (both signals one sample old):
//   gPrev    : total gain in dB, used to refer the brake detector to the
//              levelled output without creating a delay-free loop
//   trimPrev : integrated-loudness trim in dB

leveler(gPrev, trimPrev, l, r) = gTotal, trim, outL, outR
with {

    //------------------------------------------------------------------
    // Input analysis. One K-filter pair feeds the LUFS-S meter, the
    // control detector and the brake detector.
    //------------------------------------------------------------------
    kl = l : kfilter;
    kr = r : kfilter;
    pIn = sq(kl) + sq(kr);                  // BS.1770 power, G_L = G_R = 1

    lufsInS = pIn : meanSquare(shortTermWindow) : lufs : meter_lufs_in;

    // Control detector: rolling gated loudness of the input. Nothing can be
    // levelled faster than it is measured, so the detector window shortens
    // with the speed controls.
    detectWindow = it.interpolate_linear(max(leveler_speed_up, leveler_speed_down),
                                         detectWindowSlow, detectWindowFast);
    // Pauses are the brake's business, so the control detector takes the
    // brake as its gate and adds only the absolute gate on top. A relative
    // gate would be wrong here: the input is not levelled, so a genuine drop
    // in programme level is indistinguishable from a pause.
    lufsInG = pIn : gatedLoudness(detectWindow, brake, 0.0) : idleAtTarget;
    // Until something has been gated in there is nothing to correct.
    idleAtTarget(lvl, w) = select2(w > 0.0, target, lvl);

    //------------------------------------------------------------------
    // Fast loop.
    //
    // Scale first, then clamp, then smooth, so that "max boost"/"max cut"
    // really are the limits of the delivered gain and the smoother is never
    // asked to chase the +100 dB that digital silence would ask for.
    //------------------------------------------------------------------
    gFast = (target - lufsInG) : applyScale : limitGain : smoothGain;

    gRaw = gFast + trimPrev;
    gTotal = gRaw : limitGain : leveler_meter_gain;

    gLin = gTotal : ba.db2linear;
    outL0 = l * gLin * postGainLin;
    outR0 = r * gLin * postGainLin;

    //------------------------------------------------------------------
    // Output analysis: the real plugin output, post gain and post PostGain.
    //------------------------------------------------------------------
    pOut = sq(outL0 : kfilter) + sq(outR0 : kfilter);
    lufsOutS = pOut : meanSquare(shortTermWindow) : lufs : meter_lufs_out;

    // The output measurement uses the same "is this programme" decision as
    // the control loop, so that a fully closed brake (an external VAD
    // reporting no speech, say) freezes the trim instead of letting it walk
    // off on room tone. With the default internal brake this gates almost
    // exactly where BS.1770's own relative gate would.
    outGated = pOut : gatedLoudness(trim_window, brake,
                                    lufs2power(target + postGainSlider));
    lufsOutI = outGated : (_,!);
    lufsOutW = outGated : (!,_);
    lufsIdisplay = select2(lufsOutW > 0.0, meters_minimum, lufsOutI) : meter_lufs_i;

    //------------------------------------------------------------------
    // Slow loop: integrate the integrated-loudness error onto the gain.
    //
    // PostGain is a deliberate offset, so the loop targets `target` at the
    // leveler's own output, i.e. `target + postGain` at the plugin output.
    // The integrator runs only while the brake says there is programme to
    // measure, once the measurement has warmed up, and while the requested
    // direction still has headroom inside max boost / max cut (anti-windup).
    // Without the brake term a long pause would let the trim converge onto a
    // frozen error and then overshoot when the programme comes back.
    //------------------------------------------------------------------
    trimErr = (target + postGainSlider) - lufsOutI;
    trimRate = trimErr / max(1.0, trimRatio * trim_window * ma.SR);
    warmedUp = lufsOutW > (1.0 - exp(0.0 - trimWarmup / max(0.001, trim_window)));
    headroom = ((trimRate > 0.0) & (gRaw < maxboost))
             | ((trimRate < 0.0) & (gRaw > max_cut));

    trim = (trimPrev + brake * warmedUp * headroom * trimRate)
         : min(trim_range) : max(0.0 - trim_range) : meter_trim;

    //------------------------------------------------------------------
    // Outputs, with the metering taps attached so they are not optimised
    // away. All meters read the wire they name; none of them feed audio.
    //------------------------------------------------------------------
    outL = outL0 : attach(_, lufsInS) : attach(_, lufsOutS) : attach(_, lufsIdisplay);
    outR = outR0;


    //------------------------------------------------------------------
    // Gain shaping
    //------------------------------------------------------------------
    applyScale(x) = x * select2(x > 0.0, scale_cut, scale_boost);
    limitGain = min(maxboost) : max(max_cut);

    // Program-dependent smoothing. `speed up` governs how fast the gain is
    // allowed to rise, `speed down` how fast it falls, decided by the
    // direction the gain is actually moving in rather than by the sign of
    // the requested gain.
    smoothGain(x) = go ~ _
    with {
        go(prev) = fi.dynamicSmoothing(sensitivity(speed) * brake,
                                       basefreq(speed) * brake,
                                       x)
        with {
            speed = select2(x > prev, leveler_speed_down, leveler_speed_up);
        };
    };

    //------------------------------------------------------------------
    // Brake: freezes the smoother (and therefore the gain) whenever there
    // is no programme to level, so pauses and room tone are not pulled up.
    //
    // The detector runs on the band-limited K-weighted input referred to
    // the output by the previous total gain, so its threshold is a
    // meaningful "LU below target" on the levelled signal -- the same idea
    // as the BS.1770 relative gate.
    //------------------------------------------------------------------
    brake = blended <: attach(_, (1.0 - _) : meter_leveler_brake)
    with {
        blended = detectInternal * (1.0 - detection_mode) + vad * detection_mode;
    };

    detectInternal =
        (lufsBrake - leveler_brake_thresh) / brakeKnee
        : max(0.0) : min(1.0)
        : ba.peakholder(brakeHold * ma.SR)
        : si.lag_ud(brakeAttack, brakeRelease);

    lufsBrake = pBrake : meanSquareFast(brakeWindow) : lufs : +(gPrev);
    pBrake = sq(kl : brakeFilter) + sq(kr : brakeFilter);
};

// 12 dB/octave band limiting ahead of the brake's level detector.
brakeFilter = fi.highpass(2, brake_hp_freq) : fi.lowpass(2, brake_lp_freq);

// Smoother tuning: base cutoff 0.01 Hz (tau ~ 16 s) at speed 0 up to 0.2 Hz
// (tau ~ 0.8 s) at speed 1, with the sensitivity term opening the cutoff
// further on fast level changes.
basefreq(speed) = it.interpolate_linear(speed : pow(2), 0.01, 0.2);
sensitivity(speed) = it.interpolate_linear(speed : pow(0.5), 0.00000025, 0.0000025);
