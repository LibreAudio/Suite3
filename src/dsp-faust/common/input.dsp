import("stdfaust.lib");

meters_minimum = -96;

// note: common parameters must be first
ms_on = checkbox("v:Input/[0]mid/side[symbol:input_ms_on]");

trim_db  = vslider("v:Input/[1][unit:dB]trim[symbol:input_trim]", 0, -60, 12, 0.1);
gain_lin = trim_db : si.smoo : ba.db2linear;

phase_l = checkbox("v:Input/[2]phase L[symbol:input_phase_l]");
phase_r = checkbox("v:Input/[3]phase R[symbol:input_phase_r]");

peak_meter_fall = 0.2;

peak_meter_l = _ <: attach(_, an.peak_envelope(peak_meter_fall) : ba.linear2db : max(meters_minimum) : vbargraph("v:Input/h:[5]meters/[1][unit:dB]L[symbol:input_peak_L]", -70, 24));
peak_meter_r = _ <: attach(_, an.peak_envelope(peak_meter_fall) : ba.linear2db : max(meters_minimum) : vbargraph("v:Input/h:[5]meters/[2][unit:dB]R[symbol:input_peak_R]", -70, 24));

phase_sign(p) = 1 - 2*p;

ms_or_stereo(l, r) =
    select2(ms_on, l, (l+r)*0.5),
    select2(ms_on, r, (l-r)*0.5);

process =
    *(gain_lin), *(gain_lin) :
    ms_or_stereo :
    *(phase_sign(phase_l)), *(phase_sign(phase_r)) :
    peak_meter_l, peak_meter_r;
