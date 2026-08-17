declare author "Klaus Scheuermann";
declare description "";
declare license "GPL-3.0-or-later";
declare name "Leveler";
declare unique_id "LAlv";



import("stdfaust.lib");

Nch = 2;
maxSR = 192000;
meters_minimum = -60;

init_leveler_target = -16;
init_leveler_maxboost = 12;
init_leveler_maxcut = 12;
init_leveler_brake_threshold = -22;
init_leveler_speed_up = 80;
init_leveler_speed_down = 80;
init_leveler_boost_scale = 100;
init_leveler_cut_scale = 100;
init_leveler_brake_hp = 1;
init_leveler_brake_lp = 20000;


process = si.bus(Nch) : pregain(Nch) : lufs_in_meter : leveler : postgain(Nch) : lufs_out_meter : si.bus(Nch);



// UI

preGainSlider = vslider("h:[2]Controls/[0][unit:dB][symbol:pregain]PreGain", 0, -20, 20, 0.1);
target = vslider("h:[2]Controls/[1][unit:dB][symbol:target]target", -23, -60, 0, 1);

maxboost = vslider("h:[2]Controls/[2][unit:dB][symbol:maxboost]max boost", init_leveler_maxboost, 0, 30, 1);
max_cut = vslider("h:[2]Controls/[3][unit:dB][symbol:max_cut]max cut", init_leveler_maxcut, 0, 30, 1) : ma.neg;
scale_boost = vslider("h:[2]Controls/[4][unit:%][symbol:scale_boost]boost scale", init_leveler_boost_scale, 0, 100, 1) * 0.01;
scale_cut = vslider("h:[2]Controls/[5][unit:%][symbol:scale_cut]cut scale", init_leveler_cut_scale, 0, 100, 1) * 0.01;

leveler_speed_up = vslider("h:[2]Controls/[6][unit:%][symbol:speed_up]speed up", init_leveler_speed_up, 0, 100, 1) * 0.01;
leveler_speed_down = vslider("h:[2]Controls/[7][unit:%][symbol:speed_down]speed down", init_leveler_speed_down, 0, 100, 1) * 0.01;
leveler_brake_thresh = target + vslider("h:[2]Controls/[8][unit:dB][symbol:brake_threshold]brake threshold", init_leveler_brake_threshold,-90,0,1)+32;
meter_leveler_brake = _*100 : vbargraph("h:[2]Controls/[9][unit:%][symbol:brake_meter]brake",0,100);

leveler_meter_gain = vbargraph("h:[2]Controls/[10][unit:dB][symbol:gain_meter]gain",-50,50);

postGainSlider = vslider("h:[2]Controls/[11][unit:dB][symbol:postgain]PostGain", 0, -20, 20, 0.1);

meter_lufs_in = vbargraph("h:[2]Controls/[unit:dB][symbol:lufs_in]lufs in", meters_minimum, 0);
meter_lufs_out = vbargraph("h:[2]Controls/[unit:dB][symbol:lufs_out]lufs out", meters_minimum, 0);

vad = vad_ext : vad_smooth;
vad_ext = vslider("h:[2]Controls/[12][symbol:vad_ext]vad_ext", 0, 0, 1, 0.001); // from external voice activity detection (0 = no voice, 1 = voice)
vad_smooth = si.smoo;

detection_mode = vslider("h:[2]Controls/[13][symbol:detection_mode]detect", 0, 0, 1, 0.01); // 0 = internal expander only, 1 = external vad only, 0.5 = blend of both

brake_hp_freq = vslider("h:[2]Controls/[14][unit:Hz][scale:log][symbol:brake_hp]brake hp", init_leveler_brake_hp, 1, 500, 1);
brake_lp_freq = vslider("h:[2]Controls/[15][unit:Hz][scale:log][symbol:brake_lp]brake lp", init_leveler_brake_lp, 20, 20000, 1);

// utility functions

pregain(n) = par(i,n,gain) with {
    gain = _ * (preGainSlider : ba.db2linear : si.smoo);
};

postgain(n) = par(i,n,gain) with {
    gain = _ * (postGainSlider : ba.db2linear : si.smoo);
};

// LEVELER

leveler(l,r) =

  (l,r):leveler_sc(target)~(_,_)
                              ;

basefreq(speed) =
  it.interpolate_linear(speed
                        :pow(
                          2 // hslider("base freq power", 2, 0.1, 10, 0.1)
                        )
                       , 0.01
                       , 0.2 // hslider("base freq fast", 0.2, 0.1, 0.3, 0.001)
                       );

sensitivity(speed) =
  it.interpolate_linear(speed
                        :pow(
                          0.5 // hslider("sens power", 0.5, 0.1, 10, 0.1)
                        )
                       , 0.00000025
                       , 0.0000025 // hslider("sens fast", 0.0000025, 0.0000025, 0.000005, 0.0000001)
                       );

lk2_fixed(Tg)= par(i,2,kfilter : zi) :> 4.342944819 * log(max(1e-12)) : -(0.691) with {
  // maximum assumed sample rate is 192k
  sump(n) = ba.slidingSump(n, Tg*maxSR)/max(n,ma.EPSILON);
  envelope(period, x) = x * x :  sump(rint(period * ma.SR));
  zi = envelope(Tg); // mean square: average power = energy/Tg = integral of squared signal / Tg

  //kfilter = ebu.ebur128;
};

lk2_var(Tg)= par(i,2,kfilter : zi) :> 4.342944819 * log(max(1e-12)) : -(0.691) with {
  // maximum assumed sample rate is 192k
  sump(n) = ba.slidingSump(n, 0.4 * maxSR)/max(n,ma.EPSILON);
  envelope(period, x) = x * x :  sump(rint(period * ma.SR));
  zi = envelope(Tg); // mean square: average power = energy/Tg = integral of squared signal / Tg

  //kfilter = ebu.ebur128;
};


lk2_short = lk2_fixed(3);
lufs_in_meter(l,r) = attach(l, (lk2_short(l,r) : meter_lufs_in)), r;
lufs_out_meter(l,r) = attach(l, (lk2_short(l,r) : meter_lufs_out)), r;


kfilter = fi.itu_r_bs_1770_4_kfilter;

// 12dB/octave (2nd order) band-limiting ahead of the brake's level detector
brakeFilter = fi.highpass(2, brake_hp_freq) : fi.lowpass(2, brake_lp_freq);



leveler_sc(target,fl,fr,l,r) =
  calc(lk2_fixed(0.01,fl,fr))
  <: (_*l,_*r)
with {
  // lp1p(cf) = si.smooth(ba.tau2pole(1/(2*ma.PI*cf)));
  calc(lufs) = FB(lufs)~_: ba.db2linear;
  FB(lufs,prev_gain) =
    (target - lufs)
    +(prev_gain )
    :  limit(max_cut,maxboost)
    : smoothGain
    : applyScale
    : leveler_meter_gain;

  smoothGain(x) = x : fi.dynamicSmoothing(
      sensitivity(activeSpeed) * brake(detectSignal)
    ,  basefreq(activeSpeed) * brake(detectSignal)
    ) with {
    activeSpeed = select2(x>0, leveler_speed_down, leveler_speed_up);
    detectSignal = abs(fl:brakeFilter) + abs(fr:brakeFilter);
  };

  applyScale(x) = x * select2(x>0, scale_cut, scale_boost);

  limit(lo,hi) = min(hi) : max(lo);

  leveler_speed_brake(sc) = brake(sc) * leveler_speed_up;

  // brake source: blend between the internal level-based detector and an
  // external voice-activity-detection signal, per detection_mode
  // (0 = internal only, 1 = vad only, in between = blend of both).
  brake(x) = blend(detect_internal(x), vad) <: attach(_, (1-_) : meter_leveler_brake) with {
    blend(internal, external) = internal*(1-detection_mode) + external*detection_mode;
  };

  detect_internal(x) = co.peak_expansion_gain_mono_db(maxHold,strength,leveler_brake_thresh,range,gate_att,hold,gate_rel,knee,prePost,x)
                 : ba.db2linear
                 :max(0)
                 :min(1) with{
                    maxHold = hold*maxSR;
                    strength = 1;
                    // hslider("gate strength", 1, 0.1, 10, 0.1);
                    range = 0-(ma.MAX);
                    gate_att =
                        0.1;
                    // hslider("gate att", 0.0, 0.0, 1, 0.001);
                    hold = 0.5;
                    gate_rel =
                        1;
                    // hslider("gate rel", 0.1, 0.0, 1, 0.001);
                    knee = ma.EPSILON;
                    // hslider("gate knee", 0, 0, 90, 1);
                    prePost = 1;
                };

  
};
















