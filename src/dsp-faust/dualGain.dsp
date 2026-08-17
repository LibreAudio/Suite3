import("stdfaust.lib");

declare author "Klaus Scheuermann";
declare description "";
declare license "GPL-3.0-or-later";
declare name "Dual Gain";
declare unique_id "LAdg";

trim_L  = hslider("[1][unit:dB]trim L[symbol:trimL]", 0, -20, 20, 0.1);
trim_R  = hslider("[2][unit:dB]trim R[symbol:trimR]", 0, -20, 20, 0.1);

process =
    * (trim_L : ba.db2linear),
    * (trim_R : ba.db2linear);
