// -*-Faust-*-

// For some parts of this file, a large language model was involved as a coding assistant.
// The ideas, the design decisions and the listening behind it are purely human.

declare author "Klaus Scheuermann";
declare description "Tool";
declare license "GPL-3.0-or-later";
declare name "Tool";
declare unique_id "LAto";


import("stdfaust.lib");


process = ms_enc : ms_dec;

ms_enc(l, r) = (l+r)*0.5,(l-r)*0.5;
ms_dec(m, s) = m+s,m-s;