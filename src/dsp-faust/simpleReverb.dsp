
declare author "Klaus Scheuermann";
declare description "";
declare license "GPL-3.0-or-later";
declare name "Simple Reverb";
declare unique_id "LAsr";


import("stdfaust.lib");

process = reverb;



reverb = re.vital_rev(prelow, prehigh, lowcutoff, highcutoff, lowgain, highgain, chorus_amt, chorus_freq, predelay, time, size, mix) with {
    prelow = 0.01;
    prehigh = 0.8;
    lowcutoff = 0;
    highcutoff = 1;
    lowgain = 1;
    highgain = 0.8;
    chorus_amt = 0.1;
    chorus_freq = 0.1;
    predelay = 0;
    time = 0.60;
    size = 0.5;
    mix = 1;
};