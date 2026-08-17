declare author "Klaus Scheuermann";
declare description "";
declare license "GPL-3.0-or-later";
declare name "Flanger";
declare unique_id "LAfl";

// declare drywet "true";

import("stdfaust.lib");

process = flanger;


flanger = flanger_stereo
with{
    flanger_group(x) = vgroup("FLANGER", x);
    meter_group(x) = flanger_group(hgroup("[0]Meters", x)); 
    ctl_group(x) = flanger_group(hgroup("[1]Controls", x));
    del_group(x) = flanger_group(hgroup("[2] Delay Controls", x));
    lvl_group(x) = flanger_group(hgroup("[3]", x));

    invert = 0; //ctl_group(checkbox("[1] Invert Flange Sum"));

    // FIXME: This should be an amplitude-response display:
    flangeview = lfor(freq) + lfol(freq) : meter_group(hbargraph("[2] Flange LFO ", -1.5,+1.5));

    stereoWidth(w) = _,_ <: (*(a),*(b):>_),(*(b),*(a):>_)
        with { a = 0.5*(1+w); b = 0.5*(1-w); };

    levelComp = 1 / (1 + depth*comp);

    flanger_stereo(x,y) = attach(x,flangeview),y :
        (_*2,_*2) :
        pf.flanger_stereo(dmax,curdel1,curdel2,depth,fb,invert) :
        par(i,2, fi.svf.hp(hp_freq,0.707) : fi.svf.lp(lp_freq,0.707)) :
        *(levelComp),*(levelComp) :
        stereoWidth(width);

    lfol = os.oscrs;
    lfor = os.oscrc;

    dmax = 2048;
    dflange = 0.001 * ma.SR * del_group(hslider("[1] Flange Delay [unit:ms] [style:knob] [symbol:delay]", 10, 0, 20, 0.001));
    odflange = 0.001 * ma.SR * del_group(hslider("[2] Delay Offset [unit:ms] [style:knob] [symbol:delay_offset]", 1, 0, 20, 0.001));
    freq   = ctl_group(hslider("[1] Speed [unit:Hz] [style:knob] [symbol:speed]", 0.5, 0.01, 5, 0.0001));
    depth  = ctl_group(hslider("[2] Depth [style:knob] [symbol:depth]", 0.5, 0, 1, 0.001));
    fb     = ctl_group(hslider("[3] Feedback [style:knob] [symbol:feedback]", 0, -0.999, 0.999, 0.001));
    width  = ctl_group(hslider("[4] Stereo Width [unit:%] [style:knob] [symbol:stereo_width]", 100, 0, 200, 1)) / 100;
    level  = lvl_group(hslider("Flanger Output Level [unit:dB] [symbol:level]", 0, -60, 10, 0.1)) : ba.db2linear;
    comp = 0.375; //ctl_group(hslider("[5] Level Comp [style:knob] [symbol:level_comp]", 0.5, 0, 1, 0.001));
    drywet  = lvl_group(hslider("dry/wet [unit:%] [symbol:drywet]", 50, 0, 100, 1)) / 100;
    curdel1 = odflange+dflange*(1 + lfol(freq))/2;
    curdel2 = odflange+dflange*(1 + lfor(freq))/2;
    hp_freq     = hslider("hp_freq [unit:Hz][scale:log][symbol:hp_freq]",    1,    1,   20000,  1);
    lp_freq     = hslider("lp_freq [unit:Hz][scale:log][symbol:lp_freq]",    20000, 1,  20000, 1);

};