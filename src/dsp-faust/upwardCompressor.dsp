// -*-Faust-*-

import("stdfaust.lib");

declare author "Klaus Scheuermann";
declare description "";
declare license "GPL-3.0-or-later";
declare name "Upward Compressor";
declare unique_id "LAuc";

declare drywet "true";

// numerb of channels
Nch = 2;

// maximum time in seconds for attack, hold and release
maxRelTime = 1;

maxHold = 1000;

maxLookaheadSamples = 19200; // 100ms at 192kHz

latency_meter = _ <: attach(_,meter_group(hbargraph("[symbol:latency_samples]latency_samples", 0, maxLookaheadSamples)));


process =       // bp2(ms_switch,ms_enc) :
            expanderSC_N_chan(strength,threshold,range,attack,hold,release,knee,prePost,link,meter1,maxHold,Nch,sidechain(scfreq),0,0,lookaheadSamples)
                
                //:   bp2(ms_switch,ms_dec)
        ;

sidechain(scfreq) = fi.highpass(1,scfreq);



// stereo bypass with si.smoo fading
bp2(sw,pr) =  _,_ <: _,_,pr : (_*sm,_*sm),(_*(1-sm),_*(1-sm)) :> _,_ with {
    sm = sw : si.smoo;
};

// stereo to m/s encoder
ms_enc = _*0.5,_*0.5 <: +, -;

// m/s to stereo decoder
ms_dec = _,_ <: +, -;


//---------------------------------- GUI --------------------------------------
expander_group(x) = vgroup("Upward Compressor", x);

meter_group(x)  = expander_group(vgroup("[1]Meters", x));
knob_group(x)  = expander_group(hgroup("[0]Controls", x));

maxGR = -100;
meter1 = _<:(_, (max(maxGR):meter_group((hbargraph("[1]gain 1[unit:dB][tooltip: gain in dB]", 0, 20))))):attach;
meter2 = _<:(_, (max(maxGR):meter_group((hbargraph("[2]gain 2[unit:dB][tooltip: gain in dB]", 0, 20))))):attach;
chanMeter(0) = meter1;
chanMeter(1) = meter2;

ctl_group(x)  = knob_group(hgroup("[3] Compression Control", x));

threshold = ctl_group(vslider("[0] Threshold [unit:dB]
      [tooltip: When the signal level exceeds the Threshold (in dB), its level is compressed according to the Strength]",
                              -17, maxGR, 10, 0.1));

strength = 0 - (ctl_group(vslider("[1] Ratio", 1, 1, 20, 1)) : co.ratio2strength);

range = 0 - ctl_group(vslider("[2] Range [unit:dB]
      [tooltip: When the signal level exceeds the Threshold (in dB), its level is compressed according to the Strength]",
                          6, 0, 24, 1));

knee = ctl_group(vslider("[3] Knee [unit:dB]
      [tooltip: soft knee amount in dB]",
                         6, 0, 24, 0.1));

scale1 = ctl_group(vslider("[4] Scale 1 [unit:%]
      [tooltip: Scales the amount of compression boost for channel 1]",
                         100, 0, 200, 1) / 100);
scale2 = ctl_group(vslider("[5] Scale 2 [unit:%]
      [tooltip: Scales the amount of compression boost for channel 2]",
                         100, 0, 200, 1) / 100);
chanScale(i) = select2(i, scale1, scale2);

env_group(x)  = knob_group(hgroup("[4] Compression Response", x));

attack = env_group(vslider("[1] Attack [unit:ms]  [scale:log]
      [tooltip: Time constant in ms (1/e smoothing time) for the compression gain to approach (exponentially) a new lower target level (the compression `kicking in')]",
                           20, 0.001, 100, 0.1)-0.001) : *(0.001) :max(0);
hold = env_group(vslider("[2] Hold [unit:ms]  [scale:log]
      [tooltip: Time constant in ms (1/e smoothing time) for the compression gain to approach (exponentially) a new lower target level (the compression `kicking in')]",
                         0.1, 0.1, 1000, 0.1)-0.001) : *(0.001) :max(0);
// The actual attack value is 0.1 smaller than the one displayed.
// This is done for hard limiting:
// You need 0 attack for that, but a log scale starting at 0 is useless

release = env_group(vslider("[3] Release [unit:ms]
      [tooltip: Time constant in ms (1/e smoothing time) for the compression gain to approach (exponentially) a new higher target level (the compression 'releasing')]",
                            250, 0.001, maxRelTime*1000, 0.1)-0.001) : *(0.001) : max(0);


sw_group(x)  = env_group(vgroup("[4]Options", x));
prePost = sw_group(checkbox("[1] slow/fast  [tooltip: Unchecked: log  domain return-to-threshold detector
      Checked: linear return-to-zero detector]")*-1)+1;

ms_switch = sw_group(checkbox("[1] mid/side  [tooltip: Unchecked: Left and right
      Checked: Mid and side]")*-1)+1;

SCswitch = sw_group(checkbox("[2] External SideChain  [tooltip: Unchecked: original signal
      Checked: Use external Sidechain]")*-1)+1;

link = env_group(vslider("[5] link
      [tooltip: 0 means all channels get individual gain reduction, 1 means they all get the same gain reduction]",
                         100, 0, 100, 1) /100 );

scfreq = env_group(vslider("[6]SC HP [scale:log]", 1, 1, 200, 1));

lookaheadMs = env_group(vslider("[7] Lookahead [unit:ms]
      [tooltip: Delays the audio so the gain reacts before transients arrive. 0 = off]",
                         0, 0, 100, 1));
lookaheadSamples = int(lookaheadMs * ma.SR / 1000) : latency_meter;

























//--------------------`(co.)peak_expansion_gain_N_chan_db`-------------------
// N channels dynamic range expander gain computer.
// `peak_expansion_gain_N_chan_db` is a standard Faust function.
//
// #### Usage
//
// ```
// si.bus(N) : peak_expansion_gain_N_chan_db(strength,thresh,range,att,hold,rel,knee,prePost,link,maxHold,N) : si.bus(N)
// ```
//
// Where:
//
// * `strength`: strength of the expansion (0 = no expansion, 100 means gating, <1 means upward compression)
// * `thresh`: dB level threshold below which expansion kicks in
// * `range`: maximum amount of expansion in dB
// * `att`: attack time = time constant (sec) coming out of expansion
// * `hold` : hold time (sec)
// * `rel`: release time = time constant (sec) going into expansion
// * `knee`: a gradual increase in gain reduction around the threshold:
// above thresh+(knee/2) there is no gain reduction,
// below thresh-(knee/2) there is the same gain reduction as without a knee,
// and in between there is a gradual increase in gain reduction
// * `prePost`: places the level detector either at the input or after the gain computer;
// this turns it from a linear return-to-zero detector into a log  domain return-to-range detector
// * `link`: the amount of linkage between the channels: 0 = each channel is independent, 1 = all channels have the same amount of gain reduction
// * `maxHold`: the maximum hold time in samples, known at compile time
// * `N`: the number of channels of the gain computer, known at compile time
//
//------------------------------------------------------------

declare peak_expansion_gain_N_chan_db author "Bart Brouns";
declare peak_expansion_gain_N_chan_db license "GPLv3";

// generalise expansion gains for N channels.
// first we define a mono version:
peak_expansion_gain_N_chan_db(strength,thresh,range,att,hold,rel,knee,prePost,link,maxHold,1) =
  peak_expansion_gain_mono_db(maxHold,strength,thresh,range,att,hold,rel,knee,prePost);

// The actual N-channels version:
// Calculate the maximum gain reduction of N channels,
// and then crossfade between that and each channel's own gain reduction,
// to link/unlink channels
peak_expansion_gain_N_chan_db(strength,thresh,range,att,hold,rel,knee,prePost,link,maxHold,N) =
  par(i, N, peak_expansion_gain_mono_db(maxHold,strength,thresh,range,att,hold,rel,knee,prePost))

  <: (si.bus(N),(ba.parallelMax(N) <: si.bus(N))) : ro.interleave(N,2) : par(i,N,(it.interpolate_linear(link)));


peak_expansion_gain_mono_db(maxHold,strength,thresh,range,attack,hold,release,knee,prePost) =
  level(hold,maxHold):ba.bypass1(prePost,si.lag_ud(attack,release)) :ba.linear2db : gain_computer(strength,thresh,range,knee) : ba.bypass1((prePost !=1),si.lag_ud(att,rel))
with {
  gain_computer(strength,thresh,range,knee,level) =
    (select3((level>(thresh-(knee/2)))+(level>(thresh+(knee/2)))
             , (level-thresh)
             , ((level-thresh-(knee/2)):pow(2) /(min(ma.EPSILON,knee*-2)))
             , 0
             ) *abs(strength):max(range) * (-1+(2*(strength>0)))
    );
  att = select2((strength>0),release,attack);
  rel = select2((strength>0),attack,release);
  level(hold,maxHold,x) = x : abs : ba.slidingMax(hold*ma.SR,maxHold);
};


//--------------------`(co.)expander_N_chan`-------------------
// Feed forward N channels dynamic range expander.
// `expander_N_chan` is a standard Faust function.
//
// #### Usage
//
// ```
// si.bus(N) : expander_N_chan(strength,thresh,range,att,hold,rel,knee,prePost,link,meter,maxHold,N) : si.bus(N)
// ```
//
// Where:
//
// * `strength`: strength of the expansion (0 = no expansion, 100 means gating, <1 means upward compression)
// * `thresh`: dB level threshold below which expansion kicks in
// * `range`: maximum amount of expansion in dB
// * `att`: attack time = time constant (sec) coming out of expansion
// * `hold` : hold time
// * `rel`: release time = time constant (sec) going into expansion
// * `knee`: a gradual increase in gain reduction around the threshold:
// above thresh+(knee/2) there is no gain reduction,
// below thresh-(knee/2) there is the same gain reduction as without a knee,
// and in between there is a gradual increase in gain reduction
// * `prePost`: places the level detector either at the input or after the gain computer;
// this turns it from a linear return-to-zero detector into a log  domain return-to-range detector
// * `link`: the amount of linkage between the channels: 0 = each channel is independent, 1 = all channels have the same amount of gain reduction
// * `meter`: a gain reduction meter. It can be implemented like so:
// `meter = _<:(_, (ba.linear2db:max(maxGR):meter_group((hbargraph("[1][unit:dB][tooltip: gain reduction in dB]", maxGR, 0))))):attach;`
// * `maxHold`: the maximum hold time in samples, known at compile time
// * `N`: the number of channels of the expander, known at compile time
//
//------------------------------------------------------------

declare expander_N_chan author "Bart Brouns";
declare expander_N_chan license "GPLv3";

// Feed forward expander
expander_N_chan(strength,thresh,range,att,hold,rel,knee,prePost,link,meter,maxHold,N) =
  expanderSC_N_chan(strength,thresh,range,att,hold,rel,knee,prePost,link,meter,maxHold,N,_,0,0,0);

//--------------------`(co.)expanderSC_N_chan`-------------------
// Feed forward N channels dynamic range expander with sidechain.
// `expanderSC_N_chan` is a standard Faust function.
//
// #### Usage
//
// ```
// si.bus(N) : expanderSC_N_chan(strength,thresh,range,att,hold,rel,knee,prePost,link,meter,maxHold,N,SCfunction,SCswitch,SCsignal) : si.bus(N)
// ```
//
// Where:
//
// * `strength`: strength of the expansion (0 = no expansion, 100 means gating, <1 means upward compression)
// * `thresh`: dB level threshold below which expansion kicks in
// * `range`: maximum amount of expansion in dB
// * `att`: attack time = time constant (sec) coming out of expansion
// * `hold` : hold time
// * `rel`: release time = time constant (sec) going into expansion
// * `knee`: a gradual increase in gain reduction around the threshold:
// above thresh+(knee/2) there is no gain reduction,
// below thresh-(knee/2) there is the same gain reduction as without a knee,
// and in between there is a gradual increase in gain reduction
// * `prePost`: places the level detector either at the input or after the gain computer;
// this turns it from a linear return-to-zero detector into a log  domain return-to-range detector
// * `link`: the amount of linkage between the channels: 0 = each channel is independent, 1 = all channels have the same amount of gain reduction
// * `meter`: a gain reduction meter. It can be implemented like so:
// `meter = _<:(_, (ba.linear2db:max(maxGR):meter_group((hbargraph("[1][unit:dB][tooltip: gain reduction in dB]", maxGR, 0))))):attach;`
// * `maxHold`: the maximum hold time in samples, known at compile time
// * `N`: the number of channels of the expander, known at compile time
// * `SCfunction` : a function that get's placed before the level-detector, needs to have a single input and output
// * `SCswitch` : use either the regular audio input or the SCsignal as the input for the level detector
// * `SCsignal` : an audio signal, to be used as the input for the level detector when SCswitch is 1
//
//------------------------------------------------------------

declare expanderSC_N_chan author "Bart Brouns";
declare expanderSC_N_chan license "GPLv3";

// Feed forward expander with sidechain
expanderSC_N_chan(strength,thresh,range,att,hold,rel,knee,prePost,link,meter,maxHold,N,SCfunction,SCswitch,SCsignal,lookaheadSamp) =
  si.bus(N) <:
  ((par(i, N, select2(SCswitch,_,SCsignal):SCfunction)
    : peak_expansion_gain_N_chan_db(strength,thresh,range,att,hold,rel,knee,prePost,link,maxHold,N))
  ,(par(i, N, de.delay(maxLookaheadSamples, lookaheadSamp))))
  : ro.interleave(N,2)
  : par(i,N,(*(chanScale(i)):chanMeter(i):ba.db2linear)*_);
