import("stdfaust.lib");

meters_minimum = -96;

// note: common parameters must be first
ms_on = checkbox("v:Output/[0]mid/side[symbol:input_ms_on]");

trim_db  = vslider("v:Output/[1][unit:dB]trim[symbol:output_trim]", 0, -60, 12, 0.1);
gain_lin = trim_db : si.smoo : ba.db2linear;

peak_meter_fall = 0.2;

peak_meter_l = _ <: attach(_, an.peak_envelope(peak_meter_fall) : ba.linear2db : max(meters_minimum) : vbargraph("v:Output/h:[5]meters/[1][unit:dB]L[symbol:output_peak_L]", -70, 24));
peak_meter_r = _ <: attach(_, an.peak_envelope(peak_meter_fall) : ba.linear2db : max(meters_minimum) : vbargraph("v:Output/h:[5]meters/[2][unit:dB]R[symbol:output_peak_R]", -70, 24));

phase_sign(p) = 1 - 2*p;

ms_or_stereo(m, s) =
    select2(ms_on, m, m+s),
    select2(ms_on, s, m-s);

process =
    *(gain_lin), *(gain_lin) :
    ms_or_stereo :
    peak_meter_l, peak_meter_r;
