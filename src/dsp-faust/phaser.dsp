declare author "Klaus Scheuermann";
declare description "";
declare license "GPL-3.0-or-later";
declare name "Phaser";
declare unique_id "LAph";

// declare drywet "true";

import("stdfaust.lib");

process = phaser;

phaser = phaser2_stereo
with{
    phaser2_group(x) = vgroup("PHASER2", x);
    meter_group(x) = phaser2_group(hgroup("[0]Switches", x));
    ctl_group(x) = phaser2_group(hgroup("[1]Controls", x));
    nch_group(x) = phaser2_group(hgroup("[2]Notch", x));
    lvl_group(x) = phaser2_group(hgroup("[3]Level", x));

    invert = meter_group(checkbox("[1] Invert Internal Phaser Sum [symbol:invert]"));
    vibr = meter_group(checkbox("[2] Vibrato Mode [symbol:vibrato]")); // In this mode you can hear any "Doppler"

    // FIXME: This should be an amplitude-response display:
    // flangeview = phaser2_amp_resp : meter_group(hspectrumview("[2] Phaser Amplitude Response", 0,1));
    // phaser2_stereo_demo(x,y) = attach(x,flangeview),y : ...

    phaser2_stereo = pf.phaser2_stereo(Notches,width,frqmin,fratio,frqmax,speed,mdepth,fb,invert);

    Notches = 4; // Compile-time parameter: 2 is typical for analog phaser stomp-boxes

    speed  = ctl_group(hslider("[1] Speed [unit:Hz] [style:knob] [symbol:speed]", 0.5, 0, 10, 0.001));
    depth = ctl_group(hslider("[2] Depth [style:knob] [symbol:depth]", 0.2, 0, 1, 0.001));
    fb  = ctl_group(hslider("[3] Feedback [style:knob] [symbol:feedback]", 0, -0.999, 0.999, 0.001));

    width  = nch_group(hslider("[1] N-width [unit:Hz] [style:knob] [scale:log] [symbol:width]",
        1000, 10, 5000, 1));
    frqmin = nch_group(hslider("[2] N-min [unit:Hz] [style:knob] [scale:log] [symbol:freq_min]",
        100, 20, 5000, 1));
    frqmax = nch_group(hslider("[3] N-max [unit:Hz] [style:knob] [scale:log] [symbol:freq_mx]",
        800, 20, 10000, 1)) : max(frqmin);
    fratio = nch_group(hslider("[4] N-ratio [style:knob] [symbol:freq_ratio]",
        1.5, 1.1, 4, 0.001));


    mdepth = select2(vibr,depth,2);
};