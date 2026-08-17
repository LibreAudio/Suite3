import("stdfaust.lib");

declare author "Klaus Scheuermann";
declare description "Stereo Tilt EQ — linear / resonant shelf / dual shelf modes";
declare license "GPL-3.0-or-later";
declare name "Tilt EQ";
declare unique_id "LAti";

//----------------------------------------------------------------- constants
Nch      = 2;     // stereo
N        = 1;     // shelf order (shelf-based modes)
DSQmin   = 0.5;   // dual-shelf resonance bell Q at low resonance (wide, gentle)
DSQmax   = 6.0;   // ... at full resonance (narrow, steep)
LinOrder = 8;     // spectral-tilt order (mode 1) — enough poles for a smooth line
LinF0    = 10;    // Hz, roll-off band low edge  (below audible)
LinF1    = 18000; // Hz, band high edge — below Nyquist at 44.1 kHz keeps the
                  // top pole stable (a pole above Nyquist makes spectral_tilt blow up)

//----------------------------------------------------------------- UI
mode   = nentry("[0] Mode [style:menu{'Linear':0;'Shelf + Resonance':1;'Dual Shelf':2}][symbol:mode]", 0, 0, 2, 1);

// shared by every mode
tilt   = hslider("[1] Tilt [unit:dB][symbol:tilt]", 0, -12, 12, 0.1) : si.smoo;
freq   = hslider("[2] Frequency [unit:Hz][scale:log][symbol:freq]", 630, 20, 20000, 1) : si.smoo;

// per-mode
res    = hslider("[3] Resonance [symbol:res]", 0.707, 0.4, 8, 0.01) : si.smoo;         // Shelf + Resonance
spread = hslider("[4] Spread [symbol:spread]", 2, 1, 20, 0.01) : si.smoo;               // Dual Shelf
dsres  = hslider("[5] DS Resonance [unit:dB][symbol:ds_res]", 0, 0, 12, 0.1) : si.smoo; // Dual Shelf

//----------------------------------------------------------------- process
process = par(i, Nch, tiltMono);

// all channels run every mode and select the active one — click-free switching.
// convention: tilt > 0 boosts highs / cuts lows (brighter); every mode pivots at freq.
// (dualShelf, the asymmetric spread variant, is kept below but not exposed in the menu.)
tiltMono = _ <: (linear, shelfRes, dualShelfSym) : ba.selectn(3, mode)
with {
    ntilt = 0 - tilt;

    // Mode 0 — Linear: constant-slope tilt (straight line on log-f), pivoting at freq.
    //   alpha is the slope in nepers/neper (+-0.4 here => ~+-2.4 dB/oct at +-12 dB).
    //   spectral_tilt is A(alpha)*(f/LinF0)^alpha in-band, so (LinF0/freq)^alpha alone
    //   leaves a fixed offset; Koff (dB) cancels A(alpha) so the curve crosses 0 dB
    //   exactly at freq (gain compensated). Koff is a polynomial fit measured against
    //   this exact design (LinF0/LinF1/order) over alpha in [-0.4,0.4], err < 0.01 dB.
    alpha    = tilt / 30;
    Koff     = alpha * (4.70119 + alpha * (4.70851 - 0.13213 * alpha));
    compGain = pow(LinF0 / freq, alpha) * ba.db2linear(0 - Koff);
    linear   = fi.spectral_tilt(LinOrder, LinF0, LinF1 - LinF0, alpha) : *(compGain);

    // Mode 1 — Shelf + Resonance: shelf pair pivoting at freq, res sets Q/resonance.
    shelfRes  = fi.svf.ls(freq, res, ntilt) : fi.svf.hs(freq, res, tilt);

    // Mode 2 — Dual Shelf + Spread: two shelves pushed apart around freq.
    //   The two overlapping first-order shelves leave a residual boost at freq
    //   (always upward, grows with tilt, shrinks with spread). For N=1 it is
    //   exactly |H(freq)| = sqrt(1 + dsD^2), with dsD = spread*(a-b)/(1+spread^2),
    //   a = 10^(-tilt/20), b = 10^(tilt/20). Divide it out so the tilt pivots at 0 dB.
    dsA       = ba.db2linear(ntilt);
    dsB       = ba.db2linear(tilt);
    dsD       = spread * (dsA - dsB) / (1 + spread * spread);
    dsPivot   = 1.0 / sqrt(1 + dsD * dsD);
    dualShelf = fi.lowshelf(N, ntilt, freq / spread)
              : fi.highshelf(N, tilt, freq * spread)
              : *(dsPivot);

    // Mode 2 — Dual Shelf (symmetric): a true mirror-image tilt about freq.
    //   Symmetry needs fH*fL = 10^(tilt/20) * freq^2 (geometric pole/zero mirror through
    //   wc = 2*PI*freq). Splitting that factor as a sqrt onto BOTH corners centres them on
    //   freq*sqrt(10^(tilt/20)) and lets spread widen the transition monotonically
    //   (spread = 1 => a single shelf, steepest; larger spread => wider). Putting the whole
    //   factor on the low corner alone (as before) made the corners cross over and converge
    //   for spread < 10^(tilt/40), so the tilt narrowed instead of widening. |H| is still
    //   antisymmetric in dB and pivots at 0 dB with no compensation (exact for N=1).
    dsBh         = ba.db2linear(tilt / 2);   // sqrt(10^(tilt/20)) — corner-centre offset
    symShelf     = fi.highshelf(N, tilt, freq * dsBh * spread)
                 : fi.lowshelf(N, ntilt, freq * dsBh / spread);

    //   Resonance (dsres, dB): a mirror-placed bell pair at the two corners — a peak at
    //   freq*spread and its mirror dip at freq/spread (product freq^2 => still symmetric,
    //   still pivots at 0). Both bells share dsQ, which rises with dsres so the bump
    //   starts wide/gentle and sharpens as resonance is pushed up. Sign follows tilt so
    //   it always emphasises the shelf's own direction; at dsres = 0 the bells are flat.
    dsSgn        = select2(tilt < 0, dsres, 0 - dsres);
    dsQ          = DSQmin + (dsres / 12) * (DSQmax - DSQmin);
    resBells     = fi.svf.bell(freq * spread, dsQ, dsSgn)
                 : fi.svf.bell(freq / spread, dsQ, 0 - dsSgn);
    dualShelfSym = symShelf : resBells;
};
