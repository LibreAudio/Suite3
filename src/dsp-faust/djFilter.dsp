import("stdfaust.lib");

declare author "Klaus Scheuermann";
declare description "";
declare license "GPL-3.0-or-later";
declare name "DJ Filter";
declare unique_id "LAdj";

Nch = 2;                            // djFilter is stereo

// Signal chain: highpass → lowpass → volume fadeout → reverb send/return → limiter
process = si.bus(Nch) : with_highpass : with_lowpass : with_overdrive : volume_apply : with_reverb : limiter;

// --- Knob ---
knob = hslider("knob", 0, -1, 1, 0.0001) : si.smoo;

// filter frequency meters
highpass_meter = _ <: attach(_, hbargraph("[scale:log][unit:Hz]highpass_frequency", highpass_frequency_low, highpass_frequency_hi));
lowpass_meter = _ <: attach(_, hbargraph("[scale:log][unit:Hz]lowpass_frequency",  lowpass_frequency_low,  lowpass_frequency_hi));

// --- Parameters ---

// Knob center zone: -neutral..+neutral passes audio clean, no filters active
neutral = 0.1;
// Knob range at each extreme over which volume fades to silence
fadeout = 0.02;

// Filter frequency ranges (Hz)
highpass_frequency_low = 40;        
highpass_frequency_hi = 10000;      
lowpass_frequency_low = 40;         
lowpass_frequency_hi = 10000;       

// Filter Q ranges
highpassQ_min = 1;
highpassQ_max = 8;
lowpassQ_min = 1;
lowpassQ_max = 8;

// 0 = no resonance (Q at min), 1 = max resonance
emphasizeQ = hslider("emphasizeQ", 0, 0, 1, 0.001);

// Exponential Q rise with knob travel; emphasizeQ scales the exponent (0 = flat at min, 1 = full rise to max)
highpassQ = highpassQ_min * pow(highpassQ_max / highpassQ_min, emphasizeQ * t_highpass);
lowpassQ  = lowpassQ_min  * pow(lowpassQ_max  / lowpassQ_min,  emphasizeQ * t_lowpass);

// Width of the crossfade blend between clean and filtered signal, in knob units
fade_width = 0.05;

// --- Filter position (normalized 0..1 within each active zone) ---

// 0 at neutral boundary, 1 at full right/left — symmetric by sign flip
t_highpass = max(0,  (knob - neutral) / (1 - neutral));
t_lowpass  = max(0, (-knob - neutral) / (1 - neutral));

// --- Filter frequencies (logarithmic mapping from t) ---

// Rises from _low to _hi as knob moves right
highpass_frequency = highpass_frequency_low * pow(highpass_frequency_hi / highpass_frequency_low, t_highpass) : highpass_meter;
// Drops from _hi to _low as knob moves left
lowpass_frequency  = lowpass_frequency_hi  * pow(lowpass_frequency_low  / lowpass_frequency_hi,  t_lowpass)  : lowpass_meter;

// --- Crossfade gains (0 = dry, 1 = fully filtered) ---

// Ramps 0→1 over fade_width knob units past the neutral boundary
fade_highpass = min(1, t_highpass / fade_width);
fade_lowpass  = min(1, t_lowpass  / fade_width);

// --- Filter instances (Nch channels) ---

highpass = par(i, Nch, fi.svf.hp(highpass_frequency, highpassQ));
lowpass  = par(i, Nch, fi.svf.lp(lowpass_frequency, lowpassQ));

// --- Crossfaded filter stages (Nch channels) ---

// Split Nch inputs into filtered + dry copies, blend by fade gain, sum back to Nch
with_highpass = si.bus(Nch) <: (si.bus(Nch) : highpass), si.bus(Nch)
              : par(i, Nch, _*fade_highpass), par(i, Nch, _*(1-fade_highpass))
              :> si.bus(Nch);
with_lowpass  = si.bus(Nch) <: (si.bus(Nch) : lowpass),  si.bus(Nch)
              : par(i, Nch, _*fade_lowpass),  par(i, Nch, _*(1-fade_lowpass))
              :> si.bus(Nch);

// --- Volume fadeout at knob extremes ---

// Normalized position within the fadeout zone at each extreme (0 = zone entry, 1 = hard limit)
t_fadeout_hi = max(0,  (knob - (1 - 2*fadeout)) / (2*fadeout));
t_fadeout_lo = max(0, (-knob - (1 - 2*fadeout)) / (2*fadeout));
// Quadratic curve: perceptually log-shaped, reaches true silence at the extreme
volume = pow(1 - t_fadeout_hi, 2) * pow(1 - t_fadeout_lo, 2);
volume_apply = par(i, Nch, *(volume));

// Overdrive: slider sets max amount, scales 0→max as knob moves to either extreme
overdrive_amount = hslider("overdrive", 0, 0, 1, 0.001);

overdrive_t = overdrive_amount * max(t_highpass, t_lowpass)^0.7;
overdrive_drive = 1 + overdrive_t * 7;
// tanh(x*drive)/drive keeps small-signal gain at unity; wet/dry blend avoids loudness increase
overdrive_mono = _ <: *(1 - overdrive_t), (*(overdrive_drive) : ma.tanh : /(overdrive_drive) : *(overdrive_t)) :> _;
with_overdrive = par(i, Nch, overdrive_mono);

// Reverb send: adjustable maximum, scales 0→max as knob moves to either extreme
reverb_send_max = hslider("reverb_send", 0, 0, 1, 0.001);
reverb_send = reverb_send_max * max(t_highpass, t_lowpass)^0.7;

// Send/return: dry signal + reverb-processed send, summed together
with_reverb = si.bus(Nch) <: si.bus(Nch), (par(i, Nch, *(reverb_send)) : reverb )
            :> si.bus(Nch);

limiter = par(i, Nch, co.limiter_1176_R4_mono);

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
