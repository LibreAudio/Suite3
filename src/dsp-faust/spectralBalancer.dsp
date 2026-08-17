import("stdfaust.lib");

declare author "Klaus Scheuermann";
declare description "";
declare license "GPL-3.0-or-later";
declare name "Spectral Balancer";
declare unique_id "LAsb";

process = balancer;


// INIT VALUES

Nch = 2;                            // number of channels
Nbands = 16;                         // number of bands of the multiband processing and the spectral ballancer
maxSR = 192000;                     // maximum samplerate



sb_strength_init          = 20;
sb_slope_init             = -1;    // dB/octave, negative = high freqs quieter (natural tilt)
sb_xo_low_init            = 60;   // Hz, lowest crossover frequency
sb_xo_high_init           = 8000;  // Hz, highest crossover frequency
sb_limit_max_init         = 12;    // dB, maximum allowed cut/boost
sb_timing_low_init        = 200;   // ms, smoothing time constant for lowest band
sb_timing_high_init       = 10;    // ms, smoothing time constant for highest band
sb_measure_t_init         = 25;   // ms, RMS integration window for band/full measurement
sb_lookahead_init         = 0;     // %, 0 = no lookahead, 100 = full sb_measure_t compensation
sb_limit_rolloff_low_init  = 10;   // Hz, HP-style rolloff of the limit envelope
sb_limit_rolloff_high_init = 20000; // Hz, LP-style rolloff of the limit envelope

// GUI

gui_main(x) = hgroup("main",x);
gui_mb(x) = gui_main(hgroup("mbExpComp",x));
gui_leveler(x) = gui_main(hgroup("leveler",x));

sb_strength = vslider("v:[1]Spectral Ballancer/h:line1/h:Parameters/[1][unit:%]sb_strength[symbol:sb_strength]", sb_strength_init,0,100,1) : _/100;
sb_slope    = vslider("v:[1]Spectral Ballancer/h:line1/h:Parameters/[2][unit:dB/oct]sb_slope[symbol:sb_slope]", sb_slope_init,-3,3,0.1);
sb_xo_low            = vslider("v:[1]Spectral Ballancer/h:line1/h:Parameters/[3][unit:Hz][scale:log]sb_xo_low[symbol:sb_xo_low]",                       sb_xo_low_init,            20,    400, 1) : si.smoo;
sb_xo_high           = vslider("v:[1]Spectral Ballancer/h:line1/h:Parameters/[4][unit:Hz][scale:log]sb_xo_high[symbol:sb_xo_high]",                     sb_xo_high_init,          1000,   20000, 1) : si.smoo;
sb_limit_max         = vslider("v:[1]Spectral Ballancer/h:line1/h:Parameters/[5][unit:dB]sb_limit_max[symbol:sb_limit_max]",                             sb_limit_max_init,            0,      20, 0.5);
sb_limit_rolloff_low  = vslider("v:[1]Spectral Ballancer/h:line1/h:Parameters/[6][unit:Hz][scale:log]sb_limit_rolloff_low[symbol:sb_limit_rolloff_low]",  sb_limit_rolloff_low_init,   10,     1000, 1);
sb_limit_rolloff_high = vslider("v:[1]Spectral Ballancer/h:line1/h:Parameters/[7][unit:Hz][scale:log]sb_limit_rolloff_high[symbol:sb_limit_rolloff_high]", sb_limit_rolloff_high_init, 2000,  20000, 1);
sb_timing_low  = vslider("v:[1]Spectral Ballancer/h:line1/h:Parameters/[8][unit:ms]sb_timing_low[symbol:sb_timing_low]",   sb_timing_low_init,  10, 2000, 10) / 1000;
sb_timing_high = vslider("v:[1]Spectral Ballancer/h:line1/h:Parameters/[9][unit:ms]sb_timing_high[symbol:sb_timing_high]", sb_timing_high_init,  1,  500,  1) / 1000;
sb_measure_t   = vslider("v:[1]Spectral Ballancer/h:line1/h:Parameters/[10][unit:ms]sb_measure_t[symbol:sb_measure_t]",   sb_measure_t_init,   10,  500, 10) / 1000;
sb_lookahead   = vslider("v:[1]Spectral Ballancer/h:line1/h:Parameters/[11][unit:%]sb_lookahead[symbol:sb_lookahead]",     sb_lookahead_init,    0,  100,  1) / 100;

sb_target_spectrum = par(i, Nbands, sb_slope * (i - (Nbands-1)/2.0)  + sb_target_slider(i)) ;
sb_target_slider(i) = vslider("v:[1]Spectral Ballancer/h:line1/h:target sliders/[10][unit:dB]%2i[symbol:target_slider_%2i]",   0,   -12,  12, 1);

meters_minimum = -70;

// meters

sb_meter(i) = _; // _ <: attach(_, vbargraph("v:[1]Spectral Ballancer/h:line2/h:[2]loudness normalized spectrum/[1][unit:dB]band %2i[symbol:sb_meter_%2i]",-40,40));
sb_gainmeter(i) = _ <: attach(_, vbargraph("v:[1]Spectral Ballancer/h:line2/h:[3]resulting gain/[1]sb_gain %2i[symbol:sb_gain_%2i]",-12,12));

meter_analyzer(i) = _; //_ <: attach(_, vbargraph("v:[1]Spectral Ballancer/h:line2/h:[2]analyzer/[1][unit:dB]band %2i",-40,0));

latency_meter = _ <: attach(_,vbargraph("v:[1]Spectral Ballancer/h:line1/[symbol:latency_samples]latency_samples", 0, maxSR));






/*
   _____                 _             _   ____        _ _                           
  / ____|               | |           | | |  _ \      | | |                          
 | (___  _ __   ___  ___| |_ _ __ __ _| | | |_) | __ _| | | __ _ _ __   ___ ___ _ __ 
  \___ \| '_ \ / _ \/ __| __| '__/ _` | | |  _ < / _` | | |/ _` | '_ \ / __/ _ \ '__|
  ____) | |_) |  __/ (__| |_| | | (_| | | | |_) | (_| | | | (_| | | | | (_|  __/ |   
 |_____/| .__/ \___|\___|\__|_|  \__,_|_| |____/ \__,_|_|_|\__,_|_| |_|\___\___|_|   
        | |                                                                          
        |_|                                                                        */


//----------------------- Ballancer Section -----------------------

balancer = si.bus(Nch) <:
        (sum_to_mono : gain_section : ro.cross(Nbands)),
        par(i, Nch, de.delay(maxSR, lookahead_samp))
        : route(Nbands+Nch, Nch*(Nbands+1),
            (par(j, Nbands, par(i, Nch, (j+1, i*(Nbands+1)+j+1))),
             par(i, Nch, (Nbands+i+1, i*(Nbands+1)+Nbands+1)))
          )
        : par(i, Nch, shelfcascade(xoFreqs))

        with {

            sum_to_mono    = si.bus(Nch) :> _;
            lookahead_samp = int(sb_lookahead * sb_measure_t * ma.SR) : latency_meter;

            xoFreqs = logArray(Nbands-1, sb_xo_low, sb_xo_high);
            logArray(N, b, t) = par(i, N, pow(pow(t/b, 1.0/(N-1)), i) * b);

            gain_section =
                _ <:
                    (measure_full <: par(i,Nbands,_)),
                    (an.analyzer(6, xoFreqs) : ro.cross(Nbands) : par(i,Nbands, measure_bp : meter_analyzer(i) ))

                : sb_target_spectrum, par(i,Nbands*2,_)
                : ro.interleave(Nbands,3)

                : par(i,Nbands, (_,(ro.cross(2)
                    :(_-_)
                    :sb_meter(i))))

                : par(i,Nbands, (_-_)
                    : sb_envelope(i)
                    
                    : _*sb_strength
                    
                    : sb_limit(i)

                    : sb_gainmeter(i));

            fc(j)         = sb_xo_low * pow(sb_xo_high / sb_xo_low, (2*j - 1) / (2.0 * (Nbands-2)));
            hp_gain(f)    = 1 / sqrt(1 + pow(sb_limit_rolloff_low  / max(ma.EPSILON, f), 8));
            lp_gain(f)    = 1 / sqrt(1 + pow(f / max(ma.EPSILON, sb_limit_rolloff_high), 8));
            band_limit(j) = sb_limit_max * hp_gain(fc(j)) * lp_gain(fc(j));
            sb_limit(i)   = max(ma.neg(band_limit(i))) : min(band_limit(i));

            sb_envelope(i) = si.smooth(ba.tau2pole(tau)) with{
                tau = sb_timing_low + (sb_timing_high - sb_timing_low) * i / (Nbands-1);
            };

            rms(t)       = _ <: * : si.smooth(ba.tau2pole(t)) : sqrt;

            measure_full = rms(sb_measure_t) : ba.linear2db;

            measure_bp   = _ * ba.db2linear(12) : rms(sb_measure_t) : ba.linear2db;

            ls3(f,g) = fi.svf.ls(f, .5, g3) : fi.svf.ls(f, .707, g3) : fi.svf.ls(f, 2, g3) with {g3 = g/3;};
            bs3(f1,f2,g) = ls3(f1,-g) : ls3(f2,g);
            hs3(f,g) = fi.svf.hs(f, .5, g3) : fi.svf.hs(f, .707, g3) : fi.svf.hs(f, 2, g3) with {g3 = g/3;};

            shelfcascade(lf) = fbus(lf), ls3(first(lf)) : sc(lf)
            with {
                sc((f1, f2, lf)) = fbus((f2,lf)), bs3(f1,f2) : sc((f2,lf));
                sc((f1, f2))     = _, bs3(f1,f2) : hs3(f2);
                fbus(l)          = par(i, outputs(l), _);
                first((x,xs))    = x;
            };

        };




//        _   _ _ _ _         
//       | | (_) (_) |        
//  _   _| |_ _| |_| |_ _   _ 
// | | | | __| | | | __| | | |
// | |_| | |_| | | | |_| |_| |
//  \__,_|\__|_|_|_|\__|\__, |
//                       __/ |
//                      |___/ 

// mono2stereo2mono

momo2stereo = _ <: _,_;
stereo2mono = _,_ :> _ *0.5;

// pre and post gain

pregain(n) = par(i,n,gain) with {
    gain = _ * (preGainSlider : ba.db2linear : si.smoo);
};

postgain(n) = par(i,n,gain) with {
    gain = _ * (postGainSlider : ba.db2linear : si.smoo);
};

// Stereo bypass with smooth fading
bp2(sw,pr) = _,_ <: _,_,pr : (_*sm,_*sm),(_*(1-sm),_*(1-sm)) :> _,_ with {
    sm = sw : si.smoo;
};

// Mono bypass with smooth fading
bp1(sw,pr) = _ <: _,pr : (_*sm),(_*(1-sm)) :> _ with {
    sm = sw : si.smoo;
};

// ratio2strength
ratio2strength(ratio) = 1-(1/ratio);

// PRE FILTER
preFilter = preFilter_hp with {

    preFilter_hp = fi.highpass(1,preFilter_hp_freq);

};

// CROSSOVER for spectral ballancer (and multiband compressor)

crossover = fi.crossover8LR4(xo1,xo2,xo3,xo4,xo5,xo6,xo7) with{
        xo1 = 100;
        xo2 = 200;
        xo3 = 400;
        xo4 = 800;
        xo5 = 1600;
        xo6 = 3200;
        xo7 = 6400;

};



// Input Gate Computer

input_gate_computer = level : knee_gain : ar_smooth
    with {
        threshold = hslider("threshold[unit:dB]", -40, -80,    0,  1);
        knee      = hslider("knee[unit:dB]",       12,   0,   24,  1);
        attack    = hslider("attack[unit:ms]",     10,   1,  200,  1) / 1000;
        release   = hslider("release[unit:ms]",   100,  10, 2000, 10) / 1000;
        rms_t     = hslider("rms[unit:ms]",        10,   1,  100,  1) / 1000;

        level = _ <: * : si.smooth(ba.tau2pole(rms_t)) : sqrt : ba.linear2db;

        knee_gain = (_ - (threshold - knee/2)) / max(ma.EPSILON, knee)
            : max(0) : min(1)
            : *(ma.PI) : cos : (0-_) : +(1) : *(0.5);

        ar_smooth = loop ~ _
            with {
                loop(x, prev) = select2(x > prev,
                    prev * ba.tau2pole(release) + x * (1 - ba.tau2pole(release)),
                    prev * ba.tau2pole(attack)  + x * (1 - ba.tau2pole(attack))
                );
            };
    };










