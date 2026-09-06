declare author "Klaus Scheuermann";
declare description "Automatic Double Tracking";
declare license "GPL-3.0-or-later";
declare name "ADT Doubler";
declare unique_id "LAad";

import("stdfaust.lib");

// UI
uiAdt(x) = hgroup("[0]Adt", x);

//======================= ADT (tape-style) =======================
// Delayed voice, delay time wobbled by a slow LFO to emulate varispeed
// "wow" from a second tape machine (Abbey Road ADT). The 2nd Voice switch
// adds a second machine: longer-delayed, with a slower and unrelated wow
// rate so the two never lock into one audible wobble.

adt_delayMs = uiAdt(hslider("[1]Delay[style:knob][unit:ms][symbol:adt_delay]", 18, 5, 40, 0.1)) : si.smoo;
adt_2voice  = 1;
adt_rateHz  = uiAdt(hslider("[2]Rate[style:knob][unit:Hz][symbol:adt_wow_rate]", 0.6, 0.05, 5, 0.01));
adt_depthMs = uiAdt(hslider("[4]Depth[style:knob][unit:ms][symbol:adt_wow_depth]", 2.5, 0, 10, 0.1)) :si.smoo;

adt_width   = 1;

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

// Constant-power pan, p in 0..1 (0 = hard left, 0.5 = center, 1 = hard right),
// normalised so a centred voice comes out at unity in both channels. The raw
// cos/sin law would put it at 0.707, which is 3 dB under the dry — the dry is
// passed through as-is, so for a mono source it already sits at unity in both
// channels and there is nothing for a pan law to spread.
panNorm = sqrt(2);
panL(p) = cos(p * ma.PI / 2) * panNorm;
panR(p) = sin(p * ma.PI / 2) * panNorm;

// Stereo in, wet pair out — the dry never enters here, dryWet blends it back
// in downstream. What each machine is fed depends on the Voices switch: one
// voice runs off the mono sum (classic ADT off a single feed), two voices
// split the input, voice A taking the left channel and voice B the right, so
// a stereo source gives the pair two genuinely different takes instead of two
// delays of the same signal.
adt(l, r) = wetL, wetR
with {

    srcA   = l;
    srcB   = r;

    voiceA = srcA : adt_voice(adt_delayMs, adt_rateHz);
    voiceB = srcB : adt_voice(adt_delay2,  adt_rate2);

    // select before the EQ so it stays one instance per channel either way
    wetL = voiceA : wetEq;
    wetR = voiceB : wetEq;
};

wetEq = dualFilter;

//======================= Dual Filter =======================
// One bipolar knob in place of separate HighPass and LowPass controls, the
// usual DJ-filter gesture: left of centre the lowpass sweeps down from the
// top, right of centre the highpass sweeps up from the bottom, and neither
// filter is engaged around centre. Wet only, like the rest of this section.

df_knob = uiAdt(hslider("[6]HP/LP Fltr[style:knob][symbol:dual_filter]", 0, -1, 1, 0.001)) : si.smoo;

df_neutral = 0.05;   // dead zone either side of centre, in knob units
df_fade    = 0.05;   // knob travel over which the filtered signal fades in

df_hpLo = 20;      df_hpHi = 2000;    // highpass sweeps up from the bottom
df_lpHi = 20000;   df_lpLo = 200;     // lowpass sweeps down from the top

// Position within each half of the knob: 0 at the edge of the dead zone,
// 1 at full travel. Only one of the two is ever above zero.
df_tHp = max(0, ( df_knob - df_neutral) / (1 - df_neutral));
df_tLp = max(0, (-df_knob - df_neutral) / (1 - df_neutral));

// Log sweep, so a given amount of knob buys the same number of octaves
// wherever you are in the travel.
df_hpHz = df_hpLo * pow(df_hpHi / df_hpLo, df_tHp);
df_lpHz = df_lpHi * pow(df_lpLo / df_lpHi, df_tLp);

// Crossfade the filter in over the first df_fade of travel. Leaving the dead
// zone would otherwise step straight into a filter sitting at 20 Hz / 20 kHz,
// which is not flat near the band edges even though it looks like it should be.
df_mixHp = min(1, df_tHp / df_fade);
df_mixLp = min(1, df_tLp / df_fade);

df_blend(g, fx) = _ <: (fx : *(g)), *(1 - g) :> _;

dualFilter = df_blend(df_mixHp, fi.highpass(2, df_hpHz))
           : df_blend(df_mixLp, fi.lowpass(2, df_lpHz));




// ======================= Tape Saturation ================

tape_saturation = hy.ja_processor_stereo(ms, a, alpha, k, c, drive, trim) with {
  ms = 800;
  a = 720;
  alpha = 0.05;
  k = 380;
  c = 0.25;
  drive = 40 : ba.db2linear;
  trim = -1 : ba.db2linear;
};


//======================= Dry-Wet =======================
// Both legs sit at unity with the knob centred and each one attenuates as the
// knob travels away from it, so centre is dry plus double rather than a
// crossfade through a dip. At either end the far leg passes faderMinDb and
// mutes outright.

faderMinDb = -70;
faderGain(db) = ba.db2linear(db) * (db > faderMinDb);

mix = uiAdt(hslider("[9]Dry-Wet[unit:%][style:knob][symbol:mix][label:Dry-Wet][accentcolor:01][easy]", 0, -100, 100, 0.1)) / 100 : si.smoo;

mixAttenDb(amount) = ba.linear2db(max(0.000001, 1 - amount));

mixDry = faderGain(mixAttenDb(max(0, mix)));
mixWet = faderGain(mixAttenDb(max(0, 0 - mix)));

// dry pair, then wet pair, in; blended pair out
dryWet(dl, dr, wl, wr) = dl * mixDry + wl * mixWet,
                         dr * mixDry + wr * mixWet;


// Main function
//process = _,_ <: (_,_, (adt : tape_saturation)) : dryWet;
process = adt : tape_saturation;
//process = adt;