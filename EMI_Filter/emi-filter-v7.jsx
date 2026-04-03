import { useState, useMemo, useEffect, useRef } from "react";
import { LineChart, Line, XAxis, YAxis, CartesianGrid, ReferenceLine, ReferenceArea, ResponsiveContainer, Tooltip } from "recharts";

// ── Material / Core / Wire tables ──────────────────────────────────────────
const MAT={MPP:{name:"MPP",short:"MPP",bsat_T:0.8,color:"#4488ff",steinmetz:{k:82,alpha:1.37,beta:2.0},csc:{60:{a:2.183,b:2.485,c:0.0125,d:2.099},125:{a:2.028,b:1.197,c:0.1865,d:1.750},160:{a:2.026,b:0.865,c:0.2634,d:1.712}},dcbias:{60:{a:0.0167,b:1.70e-7,c:2.454},125:{a:0.0080,b:1.71e-7,c:2.663},160:{a:0.0062,b:2.67e-7,c:2.645}},fflat:{14:4000,26:3000,60:2000,125:300,160:200},mus:[14,26,60,125,160,200]},KoolMu:{name:"Kool Mµ",short:"Kool Mµ",bsat_T:1.0,color:"#33cc55",steinmetz:{k:44.3,alpha:1.54,beta:1.99},csc:{26:{a:2.048,b:4.245,c:0.0215,d:1.990},60:{a:2.183,b:4.185,c:0.0182,d:2.024},125:{a:2.207,b:4.518,c:0.0244,d:1.967}},dcbias:{26:{a:0.0385,b:4.16e-6,c:1.709},60:{a:0.0167,b:4.70e-6,c:1.797},125:{a:0.0080,b:1.60e-5,c:1.681}},fflat:{26:3000,60:2000,125:300},mus:[26,60,75,125]},HighFlux:{name:"High Flux",short:"High Flux",bsat_T:1.5,color:"#ff8844",steinmetz:{k:122,alpha:1.43,beta:2.0},csc:{60:{a:2.284,b:3.050,c:0.0023,d:2.397},125:{a:2.165,b:1.736,c:0.1793,d:1.780},160:{a:2.104,b:2.117,c:0.1131,d:1.899}},dcbias:{60:{a:0.0167,b:5.39e-8,c:2.419},125:{a:0.0080,b:8.30e-8,c:2.523},160:{a:0.0062,b:6.92e-8,c:2.641}},fflat:{60:1000,125:700,160:400},mus:[26,60,125,160]}};
const CORES={"55350 (MPP 125µ)":{mat:"MPP",mu:125,AL:105,Ae:38.8,le:58.8,Ve:2.28,OD:23.57,ID:14.40,HT:8.89},"55439 (MPP 60µ)":{mat:"MPP",mu:60,AL:49,Ae:38.8,le:58.8,Ve:2.28,OD:23.57,ID:14.40,HT:8.89},"55059 (MPP 125µ lg)":{mat:"MPP",mu:125,AL:197,Ae:73.0,le:112.9,Ve:8.24,OD:77.00,ID:48.60,HT:25.40},"77439 (KoolMu 60µ)":{mat:"KoolMu",mu:60,AL:49,Ae:38.8,le:58.8,Ve:2.28,OD:23.57,ID:14.40,HT:8.89},"77083 (KoolMu 125µ)":{mat:"KoolMu",mu:125,AL:105,Ae:38.8,le:58.8,Ve:2.28,OD:23.57,ID:14.40,HT:8.89},"58350 (HiFlux 125µ)":{mat:"HighFlux",mu:125,AL:125,Ae:38.8,le:58.8,Ve:2.28,OD:23.57,ID:14.40,HT:8.89},Custom:{mat:"MPP",mu:125,AL:105,Ae:38.8,le:58.8,Ve:2.28,OD:23.57,ID:14.40,HT:8.89}};
const AWG_TABLE={14:{dc:1.628,dw:1.74},16:{dc:1.291,dw:1.40},17:{dc:1.150,dw:1.27},18:{dc:1.024,dw:1.14},20:{dc:0.812,dw:0.94},22:{dc:0.644,dw:0.77},24:{dc:0.511,dw:0.63},26:{dc:0.405,dw:0.51}};
const INS={standard:{er:4.0,tex:0,lb:"Standard Enamel"},heavy:{er:4.0,tex:0.025,lb:"Heavy Build"},ptfe:{er:2.1,tex:0.10,lb:"+ PTFE Tape"},triple:{er:3.2,tex:0.15,lb:"Triple Insulation"}};
const CISPR={cispr25_3:{lw:66,mw:50},cispr25_4:{lw:56,mw:40},cispr25_5:{lw:50,mw:34}};

// ── EMI Limit Engine ───────────────────────────────────────────────────────
// CISPR 25 Voltage Method — Class 5 base values (dBµV), all three detectors
// Inter-class step: LW=10, MW=8, all others=6. class_offset = (5 - cls) * step
const C25V_AVG=[
  {f0:0.15e6,f1:0.30e6,band:"LW",c5:50,step:10},
  {f0:0.53e6,f1:1.80e6,band:"MW",c5:34,step:8},
  {f0:5.9e6,f1:6.2e6,band:"SW",c5:33,step:6},
  {f0:26e6,f1:28e6,band:"CB",c5:24,step:6},
  {f0:30e6,f1:68e6,band:"VHF",c5:24,step:6},
  {f0:68e6,f1:108e6,band:"FM",c5:18,step:6},
];
const C25V_PK=[
  {f0:0.15e6,f1:0.30e6,band:"LW",c5:70,step:10},
  {f0:0.53e6,f1:1.80e6,band:"MW",c5:54,step:8},
  {f0:5.9e6,f1:6.2e6,band:"SW",c5:53,step:6},
  {f0:26e6,f1:28e6,band:"CB",c5:44,step:6},
  {f0:30e6,f1:41e6,band:"VHF-lo",c5:44,step:6},
  {f0:41e6,f1:88e6,band:"TV-I",c5:34,step:6},
  {f0:88e6,f1:108e6,band:"FM",c5:38,step:6},
];
const C25V_QP=[
  {f0:0.15e6,f1:0.30e6,band:"LW",c5:57,step:10},
  {f0:0.53e6,f1:1.80e6,band:"MW",c5:41,step:8},
  {f0:5.9e6,f1:6.2e6,band:"SW",c5:40,step:6},
  {f0:26e6,f1:28e6,band:"CB",c5:31,step:6},
  {f0:30e6,f1:54e6,band:"VHF-lo",c5:31,step:6},
  {f0:54e6,f1:68e6,band:"VHF-mid",c5:25,step:6},
  {f0:68e6,f1:108e6,band:"FM",c5:25,step:6},
];
// CISPR 25 Current Probe — Edition 1 broadband PK/QP base (dBµA), Class 5
const C25I_PK=[
  {f0:0.15e6,f1:0.30e6,band:"LW",c5:60,step:10},
  {f0:0.53e6,f1:2.0e6,band:"MW",c5:60,step:8},
  {f0:5.9e6,f1:6.2e6,band:"SW",c5:50,step:6},
  {f0:30e6,f1:54e6,band:"VHF",c5:50,step:6},
  {f0:70e6,f1:108e6,band:"FM",c5:44,step:6},
];
const C25I_QP=[
  {f0:0.15e6,f1:0.30e6,band:"LW",c5:47,step:10},
  {f0:0.53e6,f1:2.0e6,band:"MW",c5:47,step:8},
  {f0:5.9e6,f1:6.2e6,band:"SW",c5:37,step:6},
  {f0:30e6,f1:54e6,band:"VHF",c5:37,step:6},
  {f0:70e6,f1:108e6,band:"FM",c5:31,step:6},
];
const C25I_AVG=[ // "narrowband" from Ed.1
  {f0:0.15e6,f1:0.30e6,band:"LW",c5:40,step:10},
  {f0:0.53e6,f1:2.0e6,band:"MW",c5:34,step:8},
  {f0:5.9e6,f1:6.2e6,band:"SW",c5:33,step:6},
  {f0:30e6,f1:54e6,band:"VHF",c5:28,step:6},
  {f0:70e6,f1:87e6,band:"VHF-FM",c5:28,step:6},
  {f0:87e6,f1:108e6,band:"FM+6",c5:34,step:6}, // +6dB per Ed.1 note
];
// CE102 voltage adjustments: 20·log10(V/28)
const CE102_VADJ={28:0,115:12,220:18,270:20,440:24};

// CISPR 32 / EN 55032 Conducted Emissions — 150kHz–30MHz, 50µH LISN, dBµV
// Class A = non-residential, Class B = residential (more stringent)
// Lower band (150–500 kHz) slopes linearly in dBµV vs log(f)
const C32={
  A:{qp:[{f0:0.15e6,f1:0.5e6,v0:79,v1:73},{f0:0.5e6,f1:30e6,v0:73,v1:73}],
     avg:[{f0:0.15e6,f1:0.5e6,v0:66,v1:60},{f0:0.5e6,f1:30e6,v0:60,v1:60}]},
  B:{qp:[{f0:0.15e6,f1:0.5e6,v0:66,v1:56},{f0:0.5e6,f1:5e6,v0:56,v1:56},{f0:5e6,f1:30e6,v0:60,v1:60}],
     avg:[{f0:0.15e6,f1:0.5e6,v0:56,v1:46},{f0:0.5e6,f1:5e6,v0:46,v1:46},{f0:5e6,f1:30e6,v0:50,v1:50}]}
};
const c32eval=(f,cls,det,Zs)=>{
  if(f<0.15e6||f>30e6)return null;
  const segs=C32[cls]?.[det==='avg'?'avg':'qp'];
  if(!segs)return null;
  for(const s of segs){
    if(f>=s.f0&&f<=s.f1){
      const t=s.v0===s.v1?s.v0:s.v0+(s.v1-s.v0)*Math.log10(f/s.f0)/Math.log10(s.f1/s.f0);
      return t-20*Math.log10(Math.max(Zs,1)); // dBµV → dBµA
    }
  }
  return null;
};

// Unified limit evaluator — returns limit in dBµA at frequency f
// For voltage method: converts dBµV → dBµA via Zs
// Returns null if f is outside all defined bands (gap between bands)
const evalLimit=(f,stdKey,cls,det,Vnom,Zs,c32cls)=>{
  // MIL-STD-461G CE102: 10kHz–10MHz, peak detector, dBµV → dBµA
  if(stdKey==='ce102'){
    if(f<10e3||f>10e6)return null;
    const vadj=CE102_VADJ[Vnom]??0;
    const Lv=f<=2e6?94-(34/Math.log10(200))*Math.log10(f/10e3):60;
    const LdBuV=Lv+vadj;
    return LdBuV-20*Math.log10(Math.max(Zs,1));
  }
  // MIL-STD-461G CE101: 30Hz–10kHz, dBµA directly
  if(stdKey==='ce101'){
    if(f<30||f>10e3)return null;
    const flat=95; // Fig CE101-1 (DC, ships/subs baseline)
    return f<=1e3?flat:flat-20*Math.log10(f/1e3);
  }
  // CISPR 32 / EN 55032
  if(stdKey==='cispr32'){
    return c32eval(f,c32cls||'B',det,Zs);
  }
  // CISPR 25 voltage method
  if(stdKey==='cispr25v'){
    const tbl=det==='pk'?C25V_PK:det==='qp'?C25V_QP:C25V_AVG;
    let best=null;
    for(const b of tbl){
      if(f>=b.f0&&f<=b.f1){
        const Lv=b.c5+(5-cls)*b.step;
        const La=Lv-20*Math.log10(Math.max(Zs,1));
        if(best===null||La<best)best=La; // most stringent if overlapping
      }
    }
    return best;
  }
  // CISPR 25 current probe method (already dBµA)
  if(stdKey==='cispr25i'){
    const tbl=det==='pk'?C25I_PK:det==='qp'?C25I_QP:C25I_AVG;
    let best=null;
    for(const b of tbl){
      if(f>=b.f0&&f<=b.f1){
        const La=b.c5+(5-cls)*b.step;
        if(best===null||La<best)best=La;
      }
    }
    return best;
  }
  return null;
};

// Generate limit curve data for chart overlay (returns array of {logf, limA, needA})
const buildLimitCurve=(stdKey,cls,det,Vnom,Zs,srcDB,margin,c32cls)=>{
  return Array.from({length:301},(_,i)=>{
    const f=100*Math.pow(1e5,i/300);
    const logf=Math.log10(f);
    const lim=evalLimit(f,stdKey,cls,det,Vnom,Zs,c32cls);
    const needA=lim!==null?Math.max(srcDB-lim+margin,0):null;
    return{logf,needA,limA:lim};
  });
};

// Get the band name at a given frequency for display
const getBandName=(f,stdKey,det)=>{
  if(stdKey==='ce102')return f>=10e3&&f<=10e6?'CE102':'—';
  if(stdKey==='ce101')return f>=30&&f<=10e3?'CE101':'—';
  if(stdKey==='cispr32')return f>=0.15e6&&f<=30e6?(f<=0.5e6?'150k–500k':'500k–30M'):'—';
  const tbl=stdKey==='cispr25v'?(det==='pk'?C25V_PK:det==='qp'?C25V_QP:C25V_AVG)
    :(det==='pk'?C25I_PK:det==='qp'?C25I_QP:C25I_AVG);
  for(const b of tbl){if(f>=b.f0&&f<=b.f1)return b.band}
  return 'gap';
};

// ── Helper math ────────────────────────────────────────────────────────────
const nearest=(o,v)=>Object.keys(o).map(Number).reduce((p,c)=>Math.abs(c-v)<Math.abs(p-v)?c:p);
const fmt=(n,d=2)=>isFinite(n)&&n!==null?Number(n).toFixed(d):"—";
const fmtF=f=>!isFinite(f)||f<=0?"—":f>=1e6?`${(f/1e6).toFixed(2)} MHz`:f>=1e3?`${(f/1e3).toFixed(1)} kHz`:`${Math.round(f)} Hz`;
const gam=z=>{if(z<0.5)return Math.PI/(Math.sin(Math.PI*z)*gam(1-z));z-=1;const p=[0.99999999999980993,676.5203681218851,-1259.1392167224028,771.32342877765313,-176.61502916214059,12.507343278686905,-0.13857109526572012,9.9843695780195716e-6,1.5056327351493116e-7];let x=p[0];for(let i=1;i<9;i++)x+=p[i]/(z+i);const t=z+7.5;return Math.sqrt(2*Math.PI)*Math.pow(t,z+0.5)*Math.exp(-t)*x};

// ── Physics models ─────────────────────────────────────────────────────────
const pMuFn=(mat,mu,H)=>{if(H<=0)return 1;const k=nearest(mat.dcbias,mu),{a,b,c}=mat.dcbias[k];return Math.min(Math.max((1/(a+b*Math.pow(H,c)))/mu,0.01),1)};
const muFf=(f,mat,mu)=>{const ff=(mat.fflat[nearest(mat.fflat,mu)]||1000)*1e3;return 1/Math.sqrt(1+Math.pow(f/(ff*7.5),2))};

const calcCwPhysics=(dc,dw,er,tex,N,OD,ID,HT,kTor)=>{
  const e0=8.854e-12,ti=(dw-dc)/2+tex,de=dc+2*ti;
  // ── Window fill (Magnetics Inc: N×Aw / WA, WA = π/4 × ID²) ──
  const A_wire=Math.PI*Math.pow(dw/2,2); // mm²
  const A_window=Math.PI*Math.pow(ID/2,2); // mm²
  const fillPct=N*A_wire/A_window*100;
  // ── Magnetics Inc wound coil dimensions ──
  // Reference: 40% fill wound dimensions (estimated from catalog pattern per core size)
  // For a generic toroid: OD_40% ≈ OD_core + 0.4*(OD_core-ID_core), HT_40% ≈ HT_core + 0.42*(OD_core-ID_core)
  const radialGap=(OD-ID)/2;
  const OD_40=OD+0.44*radialGap, HT_40=HT+0.42*radialGap;
  const fillClamp=Math.min(Math.max(fillPct,1),85);
  const OD_wound=Math.sqrt((fillClamp/40)*(OD_40*OD_40-OD*OD)+OD*OD);
  const innerT=ID+HT-HT_40;
  const HT_wound=ID+HT-Math.sqrt(Math.max((100-fillClamp)/60*innerT*innerT,0));
  // Effective ID after winding buildup
  const wireBuild=(ID-Math.sqrt(Math.max(ID*ID-4*N*A_wire/Math.PI,0)))/2;
  const ID_eff=Math.max(ID-2*wireBuild,1);
  // ── Layer geometry from real dimensions ──
  const tpl=Math.max(1,Math.floor(Math.PI*ID/de));
  const nL=Math.ceil(N/tpl),N1=Math.min(N,tpl),N2=Math.max(0,N-N1);
  // Angular coverage: what fraction of ID circumference has 2nd layer overlap
  const circID=Math.PI*ID;
  const angularL2=N2>0?Math.min(N2*dw/circID,1.0):0;
  // Mean turn length (using wound dimensions for accuracy)
  const lt_wound=((OD_wound-ID_eff)/2*2+HT_wound*2)/1000; // m
  const lt_bare=((OD-ID)+2*HT)/1000; // m (bare core, for M-K reference)
  // ── M-K base capacitance (using Mag-Inc wound geometry) ──
  const lr=Math.log(de/Math.max(dc,0.01));
  const Ctt_w=lr>0?e0*er*Math.PI*lt_wound/lr:1e-15;
  const Ctt_b=lr>0?e0*er*Math.PI*lt_bare/lr:1e-15;
  // M-K bobbin model (original geometry for reference)
  const Cs_b=(N1>1?Ctt_b/(N1-1):Ctt_b)+(N2>1?Ctt_b/(N2-1):0);
  const Cwc_b=N*e0*er*(de/1000)*((HT+(OD-ID)/2)/1000)/(ti/1000)/6;
  const Ci_b=N2>0?(N1*N2*Ctt_b*0.4)/12:0;
  const C_mk_pF=(Cs_b+Cwc_b+Ci_b)*1e12;
  // M-K with Mag-Inc geometry (larger base — wound dimensions)
  const Cs_w=(N1>1?Ctt_w/(N1-1):Ctt_w)+(N2>1?Ctt_w/(N2-1):0);
  const Cwc_w=N*e0*er*(de/1000)*((HT_wound+(OD_wound-ID_eff)/2)/1000)/(ti/1000)/6;
  const Ci_w=N2>0?(N1*N2*Ctt_w*0.4)/12:0;
  // ── Toroid correction (k factor applied to Mag-Inc base) ──
  const rr=ID/OD;
  const Cs_tor=Cs_w*1e12; // same-layer: similar geometry, keep as-is
  const Cwc_tor=Cwc_w*1e12*rr*kTor; // tangential contact
  const Ci_tor=Ci_w*1e12*angularL2*rr*rr*kTor; // partial overlap + curved coupling
  const C_tor_pF=Cs_tor+Cwc_tor+Ci_tor;
  return{
    // M-K bobbin reference
    C_total_pF:C_mk_pF,C_same_pF:Cs_b*1e12,C_wc_eff_pF:Cwc_b*1e12,C_inter_eff_pF:Ci_b*1e12,
    // Toroid corrected (Mag-Inc geometry + k factor)
    C_tor_pF,C_tor_same:Cs_tor,C_tor_wc:Cwc_tor,C_tor_inter:Ci_tor,
    // Mag-Inc base (before toroid correction, for display)
    C_maginc_base:(Cs_w+Cwc_w+Ci_w)*1e12,
    // Geometry
    tpl,nLayers:nL,N1,N2,l_t_mm:lt_wound*1000,t_ins_mm:ti,
    fillPct,A_window_mm2:A_window,A_wire_mm2:A_wire,
    OD_wound,HT_wound,ID_eff,angularL2,
  }
};

const calcIGSE=(mat,dB,fk,D)=>{const{k,alpha,beta}=mat.steinmetz;const ki=k*gam(alpha/2+1)/(Math.pow(2,beta)*Math.pow(Math.PI,alpha-0.5)*gam((alpha+1)/2));const Pv=ki*Math.pow(2*Math.max(dB,1e-15),beta)*Math.pow(fk,alpha)*(Math.pow(Math.max(D,0.01),1-alpha)+Math.pow(Math.max(1-D,0.01),1-alpha));return{ki,Pv}};

const calcDowell=(dc,dw,N,nL,lt,Idc,Ipp,fk)=>{
  const rho=1.72e-8,mu0=4e-7*Math.PI,fHz=fk*1e3;
  const delta=Math.sqrt(rho/(Math.PI*fHz*mu0));
  const eta=Math.min(0.92,dc/dw),deff=0.886*(dc/1000)*Math.sqrt(eta),xi=deff/delta;
  const m=Math.max(1,nL);
  let FR;
  if(xi<=1.5){FR=1+(5*m*m-1)/45*Math.pow(xi,4)}
  else{const s2x=Math.sinh(2*xi),s2s=Math.sin(2*xi),c2x=Math.cosh(2*xi),c2c=Math.cos(2*xi),sx=Math.sinh(xi),ss=Math.sin(xi),cx=Math.cosh(xi),cs=Math.cos(xi);const M=xi*(s2x+s2s)/(c2x-c2c);const Dt=2*xi*(sx-ss)/(cx+cs);FR=Math.max(1,M+(m*m-1)/3*Dt)}
  const Ac=Math.PI*Math.pow(dc/2000,2),Rdc=rho*N*lt/Ac;
  const Pdc=Idc*Idc*Rdc*1000,Iac=(Ipp*1e-3)/(2*Math.sqrt(3)),Pac=Iac*Iac*Rdc*FR*1000;
  return{R_dc_mOhm:Rdc*1000,FR,xi,delta_um:delta*1e6,P_dc_mW:Pdc,P_ac_mW:Pac,P_total_mW:Pdc+Pac}
};


// ── Z_out(f) output impedance transfer functions ──────────────────────────
const cmul=([ar,ai],[br,bi])=>[ar*br-ai*bi, ar*bi+ai*br];
const cdiv=([ar,ai],[br,bi])=>{const d=br*br+bi*bi;return[(ar*br+ai*bi)/d,(ai*br-ar*bi)/d]};
const cadd=([ar,ai],[br,bi])=>[ar+br,ai+bi];
const cmag=([r,i])=>Math.sqrt(r*r+i*i);
const cpara=(Za,Zb)=>cdiv(cmul(Za,Zb),cadd(Za,Zb));

const shuntZ=(w,C_nF,Rd,Cd_nF,damp,esr=0,esl_nH=0)=>{
  const ZC=[esr, w*esl_nH*1e-9 - 1/(w*Math.max(C_nF*1e-9,1e-30))];
  if(!damp||Rd<=0||Cd_nF<=0)return ZC;
  const Zd=[Rd,-1/(w*Math.max(Cd_nF*1e-9,1e-30))]; // damping cap assumed ideal (film)
  return cpara(ZC,Zd);
};

const calcZout1=(f,L,C_nF,Zs,Rd,Cd_nF,damp,rL,esr=0,esl_nH=0)=>{
  const w=2*Math.PI*f;if(w===0)return 1e-9;
  const ZL=[rL, w*L];
  const Zser=cadd([Zs,0],ZL);
  const Zsh=shuntZ(w,C_nF,Rd,Cd_nF,damp,esr,esl_nH);
  return cmag(cpara(Zser,Zsh));
};

const calcZout2=(f,L1,C1_nF,L2,C2_nF,Zs,Rd,Cd_nF,damp,rL1,rL2,esr1=0,esl1=0,esr2=0,esl2=0)=>{
  const w=2*Math.PI*f;if(w===0)return 1e-9;
  const ZL1=[rL1, w*L1];
  const ZL2=[rL2, w*L2];
  const Zback1=cadd([Zs,0],ZL1);
  const ZC1sh=shuntZ(w,C1_nF,Rd,Cd_nF,damp,esr1,esl1);
  const Znode1=cpara(Zback1,ZC1sh);
  const Zback2=cadd(Znode1,ZL2);
  const ZC2sh=shuntZ(w,C2_nF,0,0,false,esr2,esl2);
  return cmag(cpara(Zback2,ZC2sh));
};

// ── Insertion Loss (proper complex transfer function) ──────────────────────
// Choke impedance: (rL + jwL) || Cw  — models SRF and post-SRF capacitive rolloff
const chokeZc=(w,L,rL,Cw_pF,mat,mu)=>{
  const f=w/(2*Math.PI);
  const mf=muFf(f,mat,mu);
  const Le=L*mf;
  const ZL=[rL, w*Le];
  if(Cw_pF<=0)return ZL;
  const ZCw=[0,-1/(w*Math.max(Cw_pF*1e-12,1e-30))];
  return cpara(ZL,ZCw);
};

// Cap impedance: ESR + j(wL_esl - 1/wC)
const capZc=(w,C_nF,esr,esl_nH)=>[esr, w*esl_nH*1e-9 - 1/(w*Math.max(C_nF*1e-9,1e-30))];

// Single-stage IL: Source(Zs) → choke → node → C(shunt) → Load(Zs)
// H_with = Z_load_eff / (Zs + Z_choke + Z_load_eff), Z_load_eff = ZC || Zload
// H_without = Zload / (Zs + Zload)
// IL = |H_without / H_with|
const calcIL1=(f,L,C_nF,Zs,rL,Cw_pF,esr,esl_nH,mat,mu)=>{
  const w=2*Math.PI*f;if(w<=0)return 0;
  const Zch=chokeZc(w,L,rL,Cw_pF,mat,mu);
  const ZC=capZc(w,C_nF,esr,esl_nH);
  const Zld=[Zs,0];
  const Zleff=cpara(ZC,Zld);
  const Ztot=cadd(cadd([Zs,0],Zch),Zleff);
  const Hw=cdiv(Zleff,Ztot);
  const Hwo=cdiv(Zld,cadd([Zs,0],Zld));
  const il=cmag(Hwo)/Math.max(cmag(Hw),1e-30);
  return Math.max(20*Math.log10(il),0);
};

// Two-stage IL: Zs → L1(choke+Cw) → C1(shunt) → L2 → C2(shunt) → Zload
const calcIL2=(f,L1,C1_nF,L2,C2_nF,Zs,rL1,rL2,Cw_pF,esr1,esl1,esr2,esl2,mat,mu)=>{
  const w=2*Math.PI*f;if(w<=0)return 0;
  const Zch1=chokeZc(w,L1,rL1,Cw_pF,mat,mu);
  const Zch2=[rL2, w*L2]; // 2nd choke: no Cw model
  const ZC1=capZc(w,C1_nF,esr1,esl1);
  const ZC2=capZc(w,C2_nF,esr2,esl2);
  const Zld=[Zs,0];
  // back-propagate: node2 → node1
  const Zn2=cpara(ZC2,Zld);
  const Zb=cadd(Zch2,Zn2);
  const Zn1=cpara(ZC1,Zb);
  const Ztot=cadd(cadd([Zs,0],Zch1),Zn1);
  const Hw=cmul(cdiv(Zn1,Ztot),cdiv(Zn2,Zb));
  const Hwo=cdiv(Zld,cadd([Zs,0],Zld));
  const il=cmag(Hwo)/Math.max(cmag(Hw),1e-30);
  return Math.max(20*Math.log10(il),0);
};

// ── Damped IL variants (Rd+Cd in parallel with specified cap) ─────────────
const capZcDamped=(w,C_nF,esr,esl_nH,Rd,Cd_nF)=>{
  const ZC=capZc(w,C_nF,esr,esl_nH);
  if(Rd<=0||Cd_nF<=0)return ZC;
  const ZRdCd=[Rd, -1/(w*Math.max(Cd_nF*1e-9,1e-30))]; // Rd + 1/jwCd
  return cpara(ZC,ZRdCd);
};

const calcIL1_d=(f,L,C_nF,Zs,rL,Cw_pF,esr,esl_nH,mat,mu,Rd,Cd_nF)=>{
  const w=2*Math.PI*f;if(w<=0)return 0;
  const Zch=chokeZc(w,L,rL,Cw_pF,mat,mu);
  const ZC=capZcDamped(w,C_nF,esr,esl_nH,Rd,Cd_nF);
  const Zld=[Zs,0];
  const Zleff=cpara(ZC,Zld);
  const Ztot=cadd(cadd([Zs,0],Zch),Zleff);
  const Hw=cdiv(Zleff,Ztot);
  const Hwo=cdiv(Zld,cadd([Zs,0],Zld));
  return Math.max(20*Math.log10(cmag(Hwo)/Math.max(cmag(Hw),1e-30)),0);
};

const calcIL2_d=(f,L1,C1_nF,L2,C2_nF,Zs,rL1,rL2,Cw_pF,esr1,esl1,esr2,esl2,mat,mu,Rd1,Cd1,Rd2,Cd2)=>{
  const w=2*Math.PI*f;if(w<=0)return 0;
  const Zch1=chokeZc(w,L1,rL1,Cw_pF,mat,mu);
  const Zch2=[rL2, w*L2];
  const ZC1=capZcDamped(w,C1_nF,esr1,esl1,Rd1,Cd1);
  const ZC2=capZcDamped(w,C2_nF,esr2,esl2,Rd2,Cd2);
  const Zld=[Zs,0];
  const Zn2=cpara(ZC2,Zld);
  const Zb=cadd(Zch2,Zn2);
  const Zn1=cpara(ZC1,Zb);
  const Ztot=cadd(cadd([Zs,0],Zch1),Zn1);
  const Hw=cmul(cdiv(Zn1,Ztot),cdiv(Zn2,Zb));
  const Hwo=cdiv(Zld,cadd([Zs,0],Zld));
  return Math.max(20*Math.log10(cmag(Hwo)/Math.max(cmag(Hw),1e-30)),0);
};

// ── Detector correction model (CISPR 16-1-1, analytical only) ──────────────
// Charge-balance QP: V_QP/V_pk = (1-α)/(1-αβ)
// α = exp(-t_b/τ_c), β = exp(-T/τ_d), t_b = 1/BW, T = 1/PRF
// Average broadband: AVG = PK + 20·log10(PRF/BW) when PRF < BW
// For narrowband (PRF > BW, typical fixed-freq SMPS): PK ≈ QP ≈ AVG
const detCorr=(f,fsw_Hz)=>{
  const bandB=f<30e6;
  const BW=bandB?9e3:120e3;
  const tc=1e-3, td=bandB?160e-3:550e-3;
  const tb=1/BW;
  const T=1/Math.max(fsw_Hz,1);

  // Charge-balance QP offset
  const alpha=Math.exp(-tb/tc);
  const beta=Math.exp(-T/td);
  const ratio=(1-alpha)/(1-alpha*beta);
  const pk2qp=-20*Math.log10(Math.max(ratio,1e-10)); // ≥0

  // Average offset (broadband formula — only significant if PRF < BW)
  const pk2avg=fsw_Hz<BW?-20*Math.log10(fsw_Hz/BW):0;

  return{pk2qp,pk2avg};
};

// ── Source Spectrum Engine — DM harmonic amplitudes per topology ───────────
// Returns |I_n| in Amperes (one-sided peak) at harmonic n
// Rise-time correction: multiply by |sinc(n·π·tr·fsw)|
const sincSafe=x=>x===0?1:Math.sin(x)/x;
const riseCorr=(n,tr,fsw)=>Math.abs(sincSafe(n*Math.PI*tr*fsw));

const TOPOS={
  buck:{name:"Buck CCM",hasIso:false,
    duty:(Vi,Vo)=>Math.min(Math.max(Vo/Vi,0.01),0.99),
    ipp:(Vi,Vo,D,L,fsw)=>(Vi-Vo)*D/(L*fsw),
    In:(n,D,Iout,tr,fsw)=>{
      if(n===0)return 0;
      return 2*Iout*D*Math.abs(sincSafe(n*Math.PI*D))*riseCorr(n,tr,fsw);
    },
    envA:(Iout,D)=>2*Iout*D,
    desc:"Rectangular pulse — noisiest DM input"},
  boost:{name:"Boost CCM",hasIso:false,
    duty:(Vi,Vo)=>Math.min(Math.max(1-Vi/Vo,0.01),0.99),
    ipp:(Vi,Vo,D,L,fsw)=>Vi*D/(L*fsw),
    In:(n,D,Iout,tr,fsw,Ipp)=>{
      if(n===0)return 0;
      const dI=Ipp||0.001;
      return dI*Math.abs(Math.sin(n*Math.PI*D))/(D*(1-D)*n*n*Math.PI*Math.PI);
      // No rise-time sinc — inductor controls transitions
    },
    envA:(Iout,D,Ipp)=>Ipp||0.001, // envelope peak is ripple, not load
    desc:"Triangular ripple only — quietest DM"},
  flyCCM:{name:"Flyback CCM",hasIso:true,
    duty:(Vi,Vo,NsNp)=>Math.min(Math.max(Vo/(Vo+Vi*(NsNp||1)),0.01),0.99),
    ipp:(Vi,Vo,D,Lm,fsw)=>Vi*D/(Lm*fsw),
    In:(n,D,Iout,tr,fsw,Ipp,Iavg)=>{
      if(n===0)return 0;
      const dI=Ipp||0.001;
      const Iavg_on=Iavg/Math.max(D,0.01);
      const Imin=Math.max(Iavg_on-dI/2,0);
      const Ipeak=Iavg_on+dI/2;
      const phi=2*Math.PI*n*D;
      const psi=2*Math.PI*n;
      const cp=Math.cos(phi),sp=Math.sin(phi);
      // Rectangular component (Imin)
      const r_re=Imin*D*sp/psi, r_im=-Imin*D*(1-cp)/psi;
      // Ramp component (0 → dI)
      const rp_re=(dI*D/(phi*phi))*(cp+phi*sp-1);
      const rp_im=(dI*D/(phi*phi))*(phi*cp-sp);
      const re=r_re+rp_re, im=r_im+rp_im;
      return 2*Math.sqrt(re*re+im*im)*riseCorr(n,tr,fsw);
    },
    envA:(Iout,D,Ipp,Iavg)=>{const Io=Iavg/Math.max(D,0.01);return 2*(Io+Ipp/2)*D;},
    desc:"Trapezoidal pulse — two step discontinuities"},
  flyDCM:{name:"Flyback DCM",hasIso:true,
    duty:(Vi,Vo,NsNp)=>Math.min(Math.max(Vo/(Vo+Vi*(NsNp||1)),0.01),0.99),
    ipp:(Vi,Vo,D,Lm,fsw)=>Vi*D/(Lm*fsw), // = Ipeak in DCM
    In:(n,D,Iout,tr,fsw,Ipp)=>{
      if(n===0)return 0;
      const Ipeak=Ipp||0.001; // In DCM, Ipp IS Ipeak (starts from 0)
      const phi=2*Math.PI*n*D;
      const cp=Math.cos(phi),sp=Math.sin(phi);
      const re=(Ipeak*D/(phi*phi))*(cp+phi*sp-1);
      const im=(Ipeak*D/(phi*phi))*(phi*cp-sp);
      return 2*Math.sqrt(re*re+im*im)*riseCorr(n,tr,fsw);
    },
    envA:(Iout,D,Ipp)=>2*(Ipp||0.001)*D,
    desc:"Triangular pulse with dead time — one step discontinuity"},
  fwd2sw:{name:"2-Switch Forward",hasIso:true,
    duty:(Vi,Vo,NsNp)=>Math.min(Math.max(Vo/(Vi*(NsNp||1)),0.01),0.50),
    ipp:(Vi,Vo,D,Lm,fsw)=>Vi*D/(Lm*fsw), // magnetizing delta
    In:(n,D,Iout,tr,fsw,Ipp,Iavg,NsNp)=>{
      if(n===0)return 0;
      const IL=(NsNp||1)*Iout; // reflected load
      const dIm=Ipp||0.001;    // magnetizing ripple
      const phi=2*Math.PI*n*D;
      const psi=2*Math.PI*n;
      const cp=Math.cos(phi),sp=Math.sin(phi);
      const c2p=Math.cos(2*phi),s2p=Math.sin(2*phi);
      // Interval 1: [0,DT] → IL + ramp(0,dIm)
      const r1r=IL*D*sp/psi, r1i=-IL*D*(1-cp)/psi;
      const rm1r=(dIm*D/(phi*phi))*(cp+phi*sp-1);
      const rm1i=(dIm*D/(phi*phi))*(phi*cp-sp);
      // Interval 2: [DT,2DT] → -dIm + ramp(0,dIm), phase-shifted by e^{-jφ}
      const r2r=-dIm*D*sp/psi, r2i=dIm*D*(1-cp)/psi;
      const s2r=r2r+rm1r, s2i=r2i+rm1i; // before phase shift
      const i2r=s2r*cp+s2i*sp, i2i=s2i*cp-s2r*sp; // e^{-jφ} applied
      const re=r1r+rm1r+i2r, im=r1i+rm1i+i2i;
      return 2*Math.sqrt(re*re+im*im)*riseCorr(n,tr,fsw);
    },
    envA:(Iout,D,Ipp,Iavg,NsNp)=>2*((NsNp||1)*Iout+Ipp)*D,
    desc:"Bipolar waveform — magnetizing return through clamp diodes"},
};

// Compute harmonics array: [{n, f, In_A, dBuA, dBuA_filt, margin}]
const computeHarmonics=(topo,params,maxF)=>{
  const{D,Iout,tr,fsw,Ipp,Iavg,NsNp}=params;
  const T=topo;
  const harmonics=[];
  const nMax=Math.min(Math.ceil(maxF/(fsw*1e3)),500);
  for(let n=1;n<=nMax;n++){
    const f=n*fsw*1e3;
    if(f>maxF)break;
    let In;
    if(T.name==="Boost CCM")In=T.In(n,D,Iout,tr,fsw*1e3,Ipp);
    else if(T.name==="Flyback CCM")In=T.In(n,D,Iout,tr,fsw*1e3,Ipp,Iavg);
    else if(T.name==="2-Switch Forward")In=T.In(n,D,Iout,tr,fsw*1e3,Ipp,Iavg,NsNp);
    else In=T.In(n,D,Iout,tr,fsw*1e3,Ipp);
    const dBuA=20*Math.log10(Math.max(Math.abs(In),1e-15)*1e6);
    harmonics.push({n,f,In,dBuA});
  }
  return harmonics;
};

// Spectral envelope (continuous) — for chart overlay
const envAmplitude=(f,topo,params)=>{
  const{D,Iout,tr,fsw,Ipp,Iavg,NsNp}=params;
  const fswHz=fsw*1e3;
  const f1=fswHz/(Math.PI*Math.max(D,0.01));
  const f2=1/(Math.PI*Math.max(tr,1e-9));
  const A0=topo.envA(Iout,D,Ipp,Iavg,NsNp);
  // Boost has no flat region — starts at -40dB/dec
  if(topo.name==="Boost CCM"){
    const A_fund=Ipp/(D*(1-D)*Math.PI*Math.PI);
    return A_fund*fswHz/Math.max(f,fswHz); // -20dB/dec approximation for envelope
  }
  if(f<=f1)return A0;
  if(f<=f2)return A0*f1/f;
  return A0*f1*f2/(f*f);
};

// ── SPICE Import: FFT engine + file parsing ───────────────────────────────
// Radix-2 Cooley-Tukey FFT (in-place, arrays must be power-of-2 length)
const fftRadix2=(re,im)=>{
  const n=re.length;
  // Bit-reversal permutation
  for(let i=1,j=0;i<n;i++){
    let bit=n>>1;
    for(;j&bit;bit>>=1)j^=bit;
    j^=bit;
    if(i<j){[re[i],re[j]]=[re[j],re[i]];[im[i],im[j]]=[im[j],im[i]];}
  }
  // FFT butterfly
  for(let len=2;len<=n;len<<=1){
    const ang=-2*Math.PI/len;
    const wR=Math.cos(ang),wI=Math.sin(ang);
    for(let i=0;i<n;i+=len){
      let curR=1,curI=0;
      for(let j=0;j<len/2;j++){
        const tR=re[i+j+len/2]*curR-im[i+j+len/2]*curI;
        const tI=re[i+j+len/2]*curI+im[i+j+len/2]*curR;
        re[i+j+len/2]=re[i+j]-tR; im[i+j+len/2]=im[i+j]-tI;
        re[i+j]+=tR; im[i+j]+=tI;
        const nR=curR*wR-curI*wI; curI=curR*wI+curI*wR; curR=nR;
      }
    }
  }
};

// Resample variable-timestep data to uniform grid
const resampleUniform=(time,amp,nPts)=>{
  const t0=time[0],t1=time[time.length-1];
  const dt=(t1-t0)/(nPts-1);
  const re=new Float64Array(nPts);
  let j=0;
  for(let i=0;i<nPts;i++){
    const t=t0+i*dt;
    while(j<time.length-2&&time[j+1]<t)j++;
    const frac=(t-time[j])/(time[j+1]-time[j]||1e-30);
    re[i]=amp[j]+(amp[j+1]-amp[j])*Math.min(Math.max(frac,0),1);
  }
  return{re,dt,t0,t1};
};

// Auto-detect fsw from FFT (find dominant peak above DC)
const autoDetectFsw=(magSpectrum,df)=>{
  let peakIdx=1,peakVal=0;
  const minBin=Math.max(1,Math.floor(1e3/df)); // skip below 1 kHz
  const maxBin=Math.min(magSpectrum.length/2,Math.floor(50e6/df));
  for(let i=minBin;i<maxBin;i++){
    if(magSpectrum[i]>peakVal){peakVal=magSpectrum[i];peakIdx=i;}
  }
  return peakIdx*df;
};

// Trim to integer cycles for clean FFT
const trimToIntegerCycles=(time,amp,fswHz)=>{
  const T=1/fswHz;
  const duration=time[time.length-1]-time[0];
  const nCycles=Math.floor(duration*fswHz);
  if(nCycles<1)return{time,amp,nCycles:0};
  const targetDuration=nCycles*T;
  const tEnd=time[0]+targetDuration;
  let endIdx=time.length-1;
  for(let i=0;i<time.length;i++){if(time[i]>=tEnd){endIdx=i;break;}}
  return{time:time.slice(0,endIdx+1),amp:amp.slice(0,endIdx+1),nCycles};
};

// Parse CSV or tab-delimited text (time, amplitude)
const parseSpiceFile=(text)=>{
  const lines=text.trim().split(/\r?\n/);
  const time=[],amp=[];
  let headerSkipped=false;
  for(const line of lines){
    const parts=line.trim().split(/[\t,;]+/).map(s=>s.trim());
    if(parts.length<2)continue;
    const t=parseFloat(parts[0]),a=parseFloat(parts[1]);
    if(isNaN(t)||isNaN(a)){
      if(!headerSkipped){headerSkipped=true;continue;} // skip header
      continue;
    }
    time.push(t);amp.push(a);
  }
  return{time,amp,points:time.length};
};

// Full SPICE processing pipeline
const processSpiceImport=(text,sigType,Zs,fswOverride)=>{
  // 1. Parse
  const parsed=parseSpiceFile(text);
  if(parsed.points<64)return{error:"Too few data points (need ≥64)",parsed};
  const duration=parsed.time[parsed.time.length-1]-parsed.time[0];
  // 2. Estimate effective sample density
  const avgDt=duration/parsed.points;
  const effSampleRate=1/avgDt;
  const fMax=effSampleRate/2; // Nyquist
  // 3. Resample to uniform grid (next power of 2 for FFT)
  const nFFT=Math.min(Math.pow(2,Math.ceil(Math.log2(parsed.points))),65536);
  const{re,dt}=resampleUniform(parsed.time,parsed.amp,nFFT);
  // 4. Remove DC offset
  let dcSum=0; for(let i=0;i<nFFT;i++)dcSum+=re[i];
  const dcOffset=dcSum/nFFT;
  for(let i=0;i<nFFT;i++)re[i]-=dcOffset;
  // 5. Apply Hanning window
  for(let i=0;i<nFFT;i++){const w=0.5*(1-Math.cos(2*Math.PI*i/(nFFT-1)));re[i]*=w;}
  // 6. FFT
  const im=new Float64Array(nFFT);
  fftRadix2(re,im);
  // 7. Magnitude spectrum (one-sided, corrected for window)
  const df=1/(nFFT*dt);
  const mag=new Float64Array(nFFT/2);
  for(let i=0;i<nFFT/2;i++){
    mag[i]=2*Math.sqrt(re[i]*re[i]+im[i]*im[i])/nFFT*2; // ×2 for Hanning correction
  }
  // 8. Auto-detect fsw if not overridden
  const fswDetected=autoDetectFsw(mag,df);
  const fswHz=fswOverride>0?fswOverride:fswDetected;
  // 9. Convert to dBuA (or from voltage via LISN)
  const toDBuA=(val)=>{
    const amps=sigType==="voltage"?val/Math.max(Zs,1):val;
    return 20*Math.log10(Math.max(Math.abs(amps),1e-15)*1e6);
  };
  // 10. Extract harmonics at n×fsw
  const harmonics=[];
  for(let n=1;n<=500;n++){
    const fH=n*fswHz;
    if(fH>fMax||fH>30e6)break;
    const bin=Math.round(fH/df);
    if(bin<1||bin>=nFFT/2)continue;
    // Peak search ±2 bins to handle spectral leakage
    let peakMag=0,peakBin=bin;
    for(let b=Math.max(1,bin-2);b<=Math.min(nFFT/2-1,bin+2);b++){
      if(mag[b]>peakMag){peakMag=mag[b];peakBin=b;}
    }
    const dBuA=toDBuA(peakMag);
    harmonics.push({n,f:peakBin*df,In:peakMag,dBuA});
  }
  // 11. Continuous envelope (for chart overlay)
  const envelope=[];
  for(let i=1;i<nFFT/2;i++){
    const f=i*df;
    if(f<100||f>30e6)continue;
    envelope.push({f,dBuA:toDBuA(mag[i])});
  }
  return{
    error:null,parsed,
    nFFT,dt,df,duration,effSampleRate,fMax,
    dcOffset,fswDetected,fswHz,
    harmonics,envelope,
    validation:{
      points:parsed.points,
      duration,effSampleRate,fMax,
      fswDetected,nCyclesDetected:Math.round(duration*fswHz),
    }
  };
};

// Compute requirements from EMI standard
const getStdRequirements=(stdKey)=>{
  const stds={
    cispr25v:{name:"CISPR 25 Voltage",fMin:150e3,fMax:30e6,rbw:9e3},
    cispr25i:{name:"CISPR 25 Current",fMin:150e3,fMax:30e6,rbw:9e3},
    cispr32:{name:"CISPR 32",fMin:150e3,fMax:30e6,rbw:9e3},
    ce102:{name:"MIL CE102",fMin:10e3,fMax:10e6,rbw:9e3},
    ce101:{name:"MIL CE101",fMin:30,fMax:10e3,rbw:10},
    custom:{name:"Custom",fMin:1e3,fMax:30e6,rbw:9e3},
  };
  const s=stds[stdKey]||stds.custom;
  const minDuration=1/s.rbw; // seconds — frequency resolution must be ≤ RBW
  return{...s,minDuration,minDurationUs:minDuration*1e6};
};

// ── Shared UI components ───────────────────────────────────────────────────
const Tip=({active,payload,label})=>{
  if(!active||!payload?.length)return null;
  return(<div style={{background:"#111",border:"1px solid #2a2a2a",padding:"6px 10px",fontSize:11,borderRadius:3}}>
    <div style={{color:"#f0b44c",marginBottom:3}}>{fmtF(Math.pow(10,label))}</div>
    {payload.map((p,i)=><div key={i} style={{color:p.color}}>{p.name}: {fmt(p.value,1)} {p.unit||""}</div>)}
  </div>)
};
const ZTip=({active,payload,label})=>{
  if(!active||!payload?.length)return null;
  return(<div style={{background:"#111",border:"1px solid #2a2a2a",padding:"6px 10px",fontSize:11,borderRadius:3}}>
    <div style={{color:"#f0b44c",marginBottom:3}}>{fmtF(Math.pow(10,label))}</div>
    {payload.map((p,i)=><div key={i} style={{color:p.color}}>{p.name}: {fmt(p.value,1)} dBΩ</div>)}
  </div>)
};
const BT=({active,payload,label,color})=>{
  if(!active||!payload?.length)return null;
  return(<div style={{background:"#111",border:"1px solid #2a2a2a",padding:"6px 10px",fontSize:11,borderRadius:3}}>
    <div style={{color:"#f0b44c"}}>H={label} Oe</div>
    <div style={{color:color||"#aaa"}}>µ={fmt(payload[0]?.value,1)}%</div>
  </div>)
};

const NI=({lbl,val,set,unit,min,max,step,ro,style:extraStyle,inputStyle})=>{
  const [raw,setRaw]=useState(String(val));
  const focused=useRef(false);
  useEffect(()=>{if(!focused.current)setRaw(String(val));},[val]);
  const commit=()=>{
    focused.current=false;
    const n=parseFloat(raw);
    if(!isNaN(n)){
      const clamped=Math.min(max,Math.max(min,n));
      set(clamped);
      setRaw(String(clamped));
    } else {
      setRaw(String(val));
    }
  };
  return(
    <div style={{display:"flex",alignItems:"center",gap:6,marginBottom:7,...extraStyle}}>
      {lbl&&<label style={{color:"#555",fontSize:11,width:158,flexShrink:0,lineHeight:1.3}}>{lbl}</label>}
      <input type="text" inputMode="decimal" value={raw} readOnly={ro}
        onFocus={()=>{focused.current=true;}}
        onChange={e=>!ro&&setRaw(e.target.value)}
        onBlur={commit}
        onKeyDown={e=>{if(e.key==="Enter")e.target.blur();}}
        style={{background:ro?"#0a0a0a":"#141414",border:`1px solid ${ro?"#181818":"#2a2a2a"}`,color:ro?"#999":"#f0b44c",
          padding:"3px 7px",borderRadius:3,width:70,fontFamily:'"IBM Plex Mono",monospace',fontSize:13,outline:"none",...inputStyle}}/>
      {unit&&<span style={{color:"#444",fontSize:10,whiteSpace:"nowrap"}}>{unit}</span>}
    </div>
  );
};

const IR=({lbl,val,set,unit,min,max,step,ro})=>(
  <NI lbl={lbl} val={ro?parseFloat(fmt(val,2)):val} set={set} unit={unit} min={min??-Infinity} max={max??Infinity} step={step} ro={ro}/>
);

const Tog=({lbl,val,set,detail,fac})=>(
  <div onClick={()=>set(!val)} style={{display:"flex",alignItems:"flex-start",gap:8,padding:"5px 8px",background:val?"#0f1f0f":"#0d0d0d",border:`1px solid ${val?"#226622":"#1e1e1e"}`,borderRadius:3,marginBottom:4,cursor:"pointer",userSelect:"none"}}>
    <div style={{width:12,height:12,borderRadius:2,marginTop:2,flexShrink:0,background:val?"#33cc55":"transparent",border:`2px solid ${val?"#33cc55":"#333"}`}}/>
    <div>
      <div style={{color:val?"#88ee88":"#666",fontSize:11,fontWeight:600}}>{lbl} {fac&&<span style={{color:val?"#33cc55":"#444"}}>{fac}</span>}</div>
      {detail&&<div style={{color:"#333",fontSize:9.5,marginTop:1}}>{detail}</div>}
    </div>
  </div>
);

const Sec=({title,children,accent})=>(
  <div style={{background:"#0c0c0c",border:`1px solid ${accent||"#1a1a1a"}`,borderRadius:5,padding:"11px 13px",marginBottom:10}}>
    <div style={{color:accent||"#f0b44c",fontSize:9,letterSpacing:2.5,marginBottom:10}}>{title}</div>
    {children}
  </div>
);

const MC=({lbl,val,status})=>{
  const c=status==="pass"?"#33cc55":status==="fail"?"#ff4444":status==="warn"?"#f0b44c":"#aaa";
  return(<div style={{background:"#0d0d0d",border:"1px solid #1a1a1a",borderRadius:4,padding:"7px 10px"}}>
    <div style={{color:"#2e2e2e",fontSize:8,textTransform:"uppercase",letterSpacing:1}}>{lbl}</div>
    <div style={{color:c,fontSize:13,fontFamily:'"IBM Plex Mono",monospace',fontWeight:700,marginTop:2}}>{val}</div>
  </div>)
};

const W=({msg,col})=>(
  <div style={{background:col?"#0a100a":"#1a0808",border:`1px solid ${col||"#882222"}`,borderRadius:4,padding:"7px 12px",marginBottom:8,color:col?"#88ee88":"#ff6666",fontSize:10,lineHeight:1.6}}>
    {col?"✔":"⚠"} {msg}
  </div>
);

// ── Equations Panel ────────────────────────────────────────────────────────
const EQ={
  lbl:"#888", val:"#f0b44c", hi:"#88aaff", grn:"#33cc55", pur:"#cc88ff", org:"#ff8844", dim:"#444"
};
const Frac=({n,d,color})=>(
  <span style={{display:"inline-flex",flexDirection:"column",alignItems:"center",verticalAlign:"middle",margin:"0 3px",lineHeight:1.1}}>
    <span style={{color:color||EQ.val,borderBottom:"1px solid #555",paddingBottom:1,fontSize:"0.92em"}}>{n}</span>
    <span style={{color:color||EQ.val,paddingTop:1,fontSize:"0.92em"}}>{d}</span>
  </span>
);
const Eq=({children,label})=>(
  <div style={{display:"flex",alignItems:"center",justifyContent:"space-between",gap:12,padding:"7px 0",borderBottom:"1px solid #111",flexWrap:"wrap"}}>
    <div style={{fontFamily:'"IBM Plex Mono",monospace',fontSize:12.5,color:EQ.val,lineHeight:1.9}}>{children}</div>
    {label&&<div style={{color:"#333",fontSize:9,whiteSpace:"nowrap",letterSpacing:1}}>{label}</div>}
  </div>
);
const EqSec=({title,accent,children})=>(
  <div style={{background:"#0a0a0a",border:`1px solid ${accent||"#1e1e1e"}`,borderRadius:5,padding:"12px 16px",marginBottom:10}}>
    <div style={{color:accent||"#f0b44c",fontSize:9,letterSpacing:3,marginBottom:10,fontFamily:'"IBM Plex Mono",monospace'}}>{title}</div>
    {children}
  </div>
);
const Note=({children})=>(
  <div style={{color:"#444",fontSize:10,lineHeight:1.6,marginTop:5,fontFamily:'"IBM Plex Mono",monospace'}}>{children}</div>
);
const Sym=({c,s})=><span style={{color:c||EQ.hi}}>{s}</span>;

function EqPanel(){
  const s={color:EQ.lbl,fontFamily:'"IBM Plex Mono",monospace',fontSize:12.5};
  return(
  <div style={{marginTop:14,padding:"0 0 40px"}}>

    {/* ── 1. INSERTION LOSS ── */}
    <EqSec title="1 · INSERTION LOSS — COMPLEX TRANSFER FUNCTION" accent="#b87820">
      <Eq label="Transfer function with filter (single stage)">
        <Sym s="H" c={EQ.hi}/><sub>with</sub>
        {" = "}
        <Frac n={<span>Z<sub>C</sub> ∥ Z<sub>load</sub></span>} d={<span>Z<sub>s</sub> + Z<sub>choke</sub> + Z<sub>C</sub> ∥ Z<sub>load</sub></span>}/>
      </Eq>
      <Eq label="Choke impedance (includes Cw, freq-dependent µ)">
        <Sym s="Z" c={EQ.hi}/><sub>choke</sub>
        {" = (r"}<sub>L</sub>{" + jωL·µ'(f)/µ"}<sub>i</sub>{") ∥ "}
        <Frac n="1" d={<span>jωC<sub>w</sub></span>}/>
      </Eq>
      <Eq label="Cap impedance (ESR + ESL)">
        <Sym s="Z" c={EQ.hi}/><sub>C</sub>
        {" = ESR + j(ωL"}<sub>ESL</sub>{" − "}
        <Frac n="1" d={<span>ωC</span>}/>{")"}
      </Eq>
      <Eq label="Insertion loss">
        <Sym s="IL" c={EQ.hi}/>
        {" = 20 · log"}<sub>10</sub>
        <Frac n={<span>|H<sub>without</sub>|</span>} d={<span>|H<sub>with</sub>|</span>}/>
        <span style={{color:EQ.lbl,fontSize:10}}> dB</span>
      </Eq>
      <Eq label="Required attenuation (with design margin)">
        <Sym s="A" c={EQ.hi}/><sub>req</sub>
        {" = I"}<sub>src,dBµA</sub>
        {" − L"}<sub>limit</sub>
        {" + M"}<sub>design</sub>
      </Eq>
      <Note>Pass: IL(f<sub>sw</sub>) ≥ A<sub>req</sub>. Two-stage uses cascaded voltage divider through both LC sections. ESL creates a cap SRF above which the cap goes inductive — attenuation floor.</Note>
    </EqSec>

    {/* ── 2. WINDING PARASITIC CAPACITANCE (M-K) ── */}
    <EqSec title="2 · PARASITIC CAPACITANCE — MASSARINI-KAZIMIERCZUK 1997" accent="#204488">
      <Eq label="Turn-to-turn same layer">
        <Sym s="C" c={EQ.hi}/><sub>tt</sub>
        {" = ε"}<sub>r</sub>{"ε"}<sub>0</sub>
        <Frac n={<span><Sym s="A" c={EQ.hi}/><sub>overlap</sub></span>} d={<span><Sym s="t" c={EQ.hi}/><sub>ins</sub></span>}/>
      </Eq>
      <Eq label="Effective winding capacitance (single layer, N turns)">
        <Sym s="C" c={EQ.hi}/><sub>w</sub>
        {" = "}<Frac n={<Sym s="C" c={EQ.hi}/>} d={<span>(N−1)²</span>}/>
        <span style={{color:EQ.lbl}}>{" · Σ (n·V"}<sub>n</sub>{"/ V"}<sub>total</sub>{")"}<sup>2</sup></span>
      </Eq>
      <Eq label="Interlayer capacitance">
        <Sym s="C" c={EQ.hi}/><sub>int</sub>
        {" = ε"}<sub>r</sub>{"ε"}<sub>0</sub>
        <Frac n={<span><Sym s="l" c={EQ.hi}/><sub>wire</sub> · <Sym s="d" c={EQ.hi}/><sub>wire</sub></span>} d={<span><Sym s="t" c={EQ.hi}/><sub>ins</sub> + <Sym s="d" c={EQ.hi}/><sub>air</sub></span>}/>
      </Eq>
      <Note>C<sub>eff</sub> = C<sub>w</sub>(technique multiplier). Technique reductions: Sectioned ÷4, Progressive ÷2.5, Opposite-terminal ÷1.7, Multi-strand ÷1.4, Spaced ÷1.3</Note>
    </EqSec>

    {/* ── 3. SELF-RESONANT FREQUENCY ── */}
    <EqSec title="3 · SELF-RESONANT FREQUENCY" accent="#204488">
      <Eq label="SRF uses unbiased inductance">
        <Sym s="f" c={EQ.hi}/><sub>SRF</sub>
        {" = "}<Frac n={<span>1</span>} d={<span>2π <Sym s="√" c={EQ.lbl}/>(L<sub>unbias</sub> · C<sub>w,eff</sub>)</span>}/>
      </Eq>
      <Eq label="Usable inductive range">
        <Sym s="f" c={EQ.hi}/><sub>sw</sub>{" < "}
        <Frac n={<Sym s="f" c={EQ.hi}/>} d="3"/>
        <span style={{color:EQ.lbl}}>{" where f = f"}<sub>SRF</sub></span>
      </Eq>
      <Eq label="Choke impedance magnitude (with Cw)">
        {"|Z(f)| = "}
        <Frac n={<span>ωL</span>} d={<span>|1 − ω²LC<sub>w</sub>|</span>}/>
      </Eq>
      <Note>Permeability rolloff: µ'(f) = µ<sub>i</sub> / √(1 + (f / f<sub>flat</sub>)²) — single-pole model. f<sub>flat</sub> varies by material and permeability grade.</Note>
    </EqSec>

    {/* ── 4. DC BIAS ── */}
    <EqSec title="4 · DC BIAS — PERMEABILITY ROLLOFF" accent="#884400">
      <Eq label="Effective permeability (CSC rational fit)">
        <Sym s="µ" c={EQ.org}/><sub>e</sub>
        {" = "}<Frac n="1" d={<span>a + b · H<sup>c</sup></span>}/>
        <span style={{color:EQ.lbl}}>{" , H [Oe] = "}</span>
        <Frac n={<span>0.4π · N · I<sub>dc</sub></span>} d={<span>l<sub>e</sub> [cm]</span>}/>
      </Eq>
      <Eq label="Biased inductance">
        <Sym s="L" c={EQ.org}/><sub>bias</sub>
        {" = A"}<sub>L</sub>{" · N² · "}
        <Frac n={<Sym s="µ" c={EQ.org}/>} d={<Sym s="µ" c={EQ.org}/>}/>
        <span style={{color:EQ.lbl}}> (µ<sub>e</sub>/µ<sub>i</sub>)</span>
      </Eq>
      <Eq label="DC flux density">
        <Sym s="B" c={EQ.org}/><sub>dc</sub>
        {" = "}<Frac n={<span>µ<sub>0</sub> · µ<sub>e</sub> · N · I<sub>dc</sub></span>} d={<span>l<sub>e</sub></span>}/>
      </Eq>
      <Note>Curve-fit coefficients a, b, c are material- and grade-specific (MPP/Kool Mµ/High Flux at 60µ/125µ/160µ). Saturation warning: B<sub>dc</sub> &gt; 0.9·B<sub>sat</sub>.</Note>
    </EqSec>

    {/* ── 5. CORE LOSS ── */}
    <EqSec title="5 · CORE LOSS" accent="#882222">
      <Eq label="iGSE — Improved Generalised Steinmetz (Venkatachalam 2002)">
        <Sym s="P" c={EQ.hi}/><sub>v</sub>
        {" = k"}<sub>i</sub>
        {" · "}<Frac n={<span>1</span>} d={<span>T</span>}/>
        {"∫"}<sub>0</sub><sup>T</sup>
        {" |dB/dt|"}
        <sup>α</sup>
        {" ΔB"}
        <sup>β−α</sup>
        {" dt"}
      </Eq>
      <Eq label="ki coefficient">
        {"k"}<sub>i</sub>{" = "}
        <Frac
          n={<span>k</span>}
          d={<span>(2π)<sup>α−1</sup> · ∫<sub>0</sub><sup>2π</sup> |cos θ|<sup>α</sup> 2<sup>β−α</sup> dθ</span>}
        />
      </Eq>
      <Eq label="CSC two-term (Shen 2008)">
        <Sym s="P" c={EQ.hi}/><sub>v</sub>
        {" = C"}<sub>m</sub>
        {" · f"}<sup>x</sup>
        {" · B̂"}<sup>y</sup>
        {" · (a·T² − b·T + c)"}
      </Eq>
      <Eq label="Simple Steinmetz">
        <Sym s="P" c={EQ.hi}/><sub>v</sub>
        {" = k · f"}<sup>α</sup>{" · B̂"}<sup>β</sup>
      </Eq>
      <Note>P<sub>core</sub> = P<sub>v</sub> [W/m³] · V<sub>e</sub> [m³]. ΔB from ripple current: ΔB = (µ₀µ<sub>e</sub>NΔI)/(l<sub>e</sub>). For iGSE and CSC, duty cycle D sets the waveform.</Note>
    </EqSec>

    {/* ── 6. COPPER LOSS — DOWELL ── */}
    <EqSec title="6 · COPPER LOSS — DOWELL FR FACTOR" accent="#226644">
      <Eq label="Dowell normalised conductor thickness">
        <Sym s="Δ" c={EQ.grn}/>
        {" = "}<Frac n={<span>d<sub>c</sub></span>} d={<span>δ<sub>s</sub></span>}/>
        {" , δ"}<sub>s</sub>
        {" = "}<Frac n={<span>1</span>} d={<span>√(π · f · µ₀ · σ<sub>Cu</sub>)</span>}/>
      </Eq>
      <Eq label="AC resistance factor">
        <Sym s="F" c={EQ.grn}/><sub>R</sub>
        {" = Δ · [M(Δ) + "}
        <Frac n={<span>(m² − 1)</span>} d="3"/>
        {" · D(Δ)]"}
      </Eq>
      <Eq label="M and D auxiliary functions">
        {"M(Δ) = "}
        <Frac
          n={<span>sinh(2Δ) + sin(2Δ)</span>}
          d={<span>cosh(2Δ) − cos(2Δ)</span>}/>
        {"  D(Δ) = "}
        <Frac
          n={<span>sinh(Δ) − sin(Δ)</span>}
          d={<span>cosh(Δ) + cos(Δ)</span>}/>
      </Eq>
      <Eq label="AC winding loss">
        <Sym s="P" c={EQ.grn}/><sub>Cu</sub>
        {" = F"}<sub>R</sub>
        {" · I²"}<sub>rms</sub>
        {" · R"}<sub>dc</sub>
      </Eq>
      <Note>m = number of winding layers. F<sub>R</sub> = 1 at DC; rises steeply above the skin-depth crossover. R<sub>dc</sub> = ρ<sub>Cu</sub> · l<sub>wire</sub> / A<sub>wire</sub>.</Note>
    </EqSec>

    {/* ── 7. FILTER OUTPUT IMPEDANCE ── */}
    <EqSec title="7 · FILTER OUTPUT IMPEDANCE Z_out(f)" accent="#442266">
      <Eq label="Single-stage (source Zs — L — C to GND)">
        <Sym s="Z" c={EQ.pur}/><sub>out</sub>
        {" = (Z"}<sub>s</sub>{" + Z"}<sub>L</sub>{") ∥ Z"}<sub>C</sub>
        {" = "}
        <Frac
          n={<span>(Z<sub>s</sub>+jωL) · Z<sub>C</sub></span>}
          d={<span>Z<sub>s</sub> + jωL + Z<sub>C</sub></span>}/>
      </Eq>
      <Eq label="Two-stage ladder (back-propagation, right to left)">
        <Sym s="Z" c={EQ.pur}/><sub>out</sub>
        {" = Z"}<sub>C2</sub>
        {" ∥ [Z"}<sub>L2</sub>
        {" + (Z"}<sub>C1</sub>
        {" ∥ (Z"}<sub>s</sub>
        {" + Z"}<sub>L1</sub>
        {"))]}"}
      </Eq>
      <Eq label="Shunt impedance with R_d + C_d damping network">
        <Sym s="Z" c={EQ.pur}/><sub>shunt</sub>
        {" = Z"}<sub>C</sub>
        {" ∥ (R"}<sub>d</sub>
        {" + Z"}<sub>Cd</sub>
        {")"} 
      </Eq>
      <Note>Z<sub>L</sub> = r<sub>L</sub> + jωL · · · Z<sub>C</sub> = −j/(ωC) · · · r<sub>L</sub> estimated from DC resistance via Dowell model</Note>
    </EqSec>

    {/* ── 8. MIDDLEBROOK STABILITY ── */}
    <EqSec title="8 · MIDDLEBROOK STABILITY CRITERION" accent="#441166">
      <Eq label="Converter input impedance (constant-power, DC approximation)">
        <Sym s="Z" c={EQ.pur}/><sub>in</sub>
        {" = "}
        <Frac
          n={<span>V<sub>bus</sub>² · η</span>}
          d={<span>P<sub>out</sub></span>}/>
      </Eq>
      <Eq label="Middlebrook criterion (sufficient stability condition)">
        {"|Z"}<sub>out</sub>
        {"(f)| < |Z"}<sub>in</sub>
        {"| ∀ f"}
        <span style={{color:EQ.lbl}}>{" (at all frequencies)"}</span>
      </Eq>
      <Eq label="Peak Z_out tracked above fc1/5 (avoids source-impedance plateau)">
        <Sym s="f" c={EQ.pur}/><sub>track</sub>
        {" > "}
        <Frac n={<Sym s="f" c={EQ.pur}/>} d="5"/>
        <span style={{color:EQ.lbl}}> where f = f<sub>c1</sub></span>
      </Eq>
      <Eq label="Recommended damping (collapses resonance peak)">
        {"R"}<sub>d</sub>
        {" = Z"}<sub>0</sub>
        {" = "}
        <Frac n={<span>√L</span>} d={<span>√C</span>}/>
        {"  ,  C"}<sub>d</sub>
        {" = 4 · C"}
      </Eq>
      <Note>⚠ App uses a DC-derived constant Z<sub>in</sub>. True Middlebrook requires frequency-dependent Z<sub>in</sub>(f) of the converter. This is conservative at high frequency (Z<sub>in</sub> typically rises above loop crossover, giving additional margin not shown here).</Note>
    </EqSec>

    {/* ── 9. WINDOW FILL ── */}
    <EqSec title="9 · WINDOW UTILISATION" accent="#b87820">
      <Eq label="Wire cross-section (with insulation)">
        <Sym s="A" c={EQ.hi}/><sub>wire</sub>
        {" = π · (d"}<sub>w</sub>{"/2)²"}
        <span style={{color:EQ.lbl}}>{" , d"}<sub>w</sub>{" = d"}<sub>bare</sub>{" + 2·t"}<sub>ins</sub></span>
      </Eq>
      <Eq label="Window area (toroid inner bore)">
        <Sym s="A" c={EQ.hi}/><sub>window</sub>
        {" = π · (ID/2)²"}
      </Eq>
      <Eq label="Fill factor">
        <Sym s="k" c={EQ.hi}/><sub>u</sub>
        {" = "}
        <Frac
          n={<span>N · A<sub>wire</sub></span>}
          d={<span>A<sub>window</sub></span>}/>
        {" × 100%"}
      </Eq>
      <Note>Thresholds: k<sub>u</sub> &lt; 35% — comfortable fit · 35–50% — tight, verify physically · &gt; 50% — overfull, wire will not fit. Practical limit for hand-wound toroids ≈ 40%.</Note>
    </EqSec>

    {/* ── 10. EMI LIMITS ── */}
    <EqSec title="10 · EMI LIMITS &amp; REQUIRED ATTENUATION" accent="#882222">
      <Eq label="DM source current level">
        <Sym s="I" c={EQ.hi}/><sub>src,dBµA</sub>
        {" = 20 · log"}<sub>10</sub>
        <Frac
          n={<span>I<sub>pp</sub>/2</span>}
          d={<span>1µA</span>}/>
      </Eq>
      <Eq label="Required filter attenuation (with design margin)">
        <Sym s="A" c={EQ.hi}/><sub>req</sub>
        {" = I"}<sub>src,dBµA</sub>
        {" − L"}<sub>limit,dBµA</sub>
        {" + M"}<sub>design</sub>
      </Eq>
      <Note>
        CISPR 25 Class 3: 66/50 dBµA (LW/MW) · Class 4: 56/40 · Class 5: 50/34{"\n"}
        MIL-STD-461 CE102: frequency-dependent piecewise limit{"\n"}
        LISN source impedance Z<sub>s</sub> = 50 Ω (standard){"\n"}
        Design margin M typically 6–10 dB to account for layout parasitics and component tolerances
      </Note>
    </EqSec>

  </div>
  );
}

// ── Main App ───────────────────────────────────────────────────────────────
export default function App() {
  // Core
  const [coreName,setCoreName]=useState("55350 (MPP 125µ)");
  const [cMat,setCMat]=useState("MPP");const [cMu,setCMu]=useState(125);const [cAL,setCAL]=useState(105);
  const [cAe,setCAe]=useState(38.8);const [cLe,setCLe]=useState(58.8);const [cVe,setCVe]=useState(2.28);
  const [cOD,setCOD]=useState(23.57);const [cID,setCID]=useState(14.40);const [cHT,setCHT]=useState(8.89);
  // Winding
  const [N,setN]=useState(57);const [Idc,setIdc]=useState(2.8);
  const [awg,setAwg]=useState(17);const [insType,setInsType]=useState("heavy");
  // Loss
  const [lmod,setLmod]=useState("igse");const [dutyCy,setDutyCy]=useState(0.5);
  // Filter
  const [autoL,setAutoL]=useState(true);const [Lman,setLman]=useState(240);
  const [Cnf,setCnf]=useState(10);const [fsw,setFsw]=useState(221);
  // EMI
  const [stdKey,setStdKey]=useState("cispr25v");const [emiCls,setEmiCls]=useState(5);
  const [emiDet,setEmiDet]=useState("avg");const [emiVnom,setEmiVnom]=useState(28);
  const [c32Cls,setC32Cls]=useState("B");
  const [limMan,setLimMan]=useState(20);const [Zs,setZs]=useState(50);
  const [Ipp,setIpp]=useState(5);
  // Source spectrum (DUT topology)
  const [topoKey,setTopoKey]=useState("buck");const [autoIpp,setAutoIpp]=useState(true);
  const [Vin,setVin]=useState(28);const [Vout,setVout]=useState(5);const [Iout,setIout]=useState(3);
  const [tr,setTr]=useState(20); // ns
  const [NsNp,setNsNp]=useState(0.5);const [Lm,setLm]=useState(500); // µH
  // SRF winding techniques
  const [wS,setWS]=useState(false);const [wP,setWP]=useState(false);const [wO,setWO]=useState(false);const [wF,setWF]=useState(false);const [wSp,setWSp]=useState(false);
  const [cwMode,setCwMode]=useState("toroid"); // "mk" (bobbin M-K), "toroid" (corrected), "manual"
  const [cwManual,setCwManual]=useState(10); // pF, manual override value
  const [kTor,setKTor]=useState(0.025); // toroid coupling factor
  const [srfLmode,setSrfLmode]=useState("unbias"); // "unbias", "bias", "manual"
  const [srfLman,setSrfLman]=useState(330); // µH, manual L for SRF
  // SPICE import
  const [useSpice,setUseSpice]=useState(false);
  const [spiceSigType,setSpiceSigType]=useState("current"); // "current" or "voltage"
  const [spiceResult,setSpiceResult]=useState(null); // processed FFT result
  const [spiceFswOvr,setSpiceFswOvr]=useState(0); // 0 = auto-detect
  const [spiceFileName,setSpiceFileName]=useState("");
  // 2nd stage
  const [st2,setSt2]=useState(false);const [L2,setL2]=useState(50);const [C2,setC2]=useState(47);
  // Cap parasitics
  const [capEsr,setCapEsr]=useState(10);   // mΩ
  const [capEsl,setCapEsl]=useState(1.0);  // nH
  const [capEsr2,setCapEsr2]=useState(10); // mΩ (2nd stage)
  const [capEsl2,setCapEsl2]=useState(1.0);// nH (2nd stage)
  // Design margin
  const [desMgn,setDesMgn]=useState(6);    // dB
  // Middlebrook / converter
  const [Vbus,setVbus]=useState(28);const [Pout,setPout]=useState(100);const [etaMB,setEtaMB]=useState(0.90);
  // Damping
  const [useDamping,setUseDamping]=useState(false);
  const [dampAuto,setDampAuto]=useState(true);
  const [RdMan,setRdMan]=useState(5);
  const [CdMan,setCdMan]=useState(40);
  // Equations panel
  const [showEq,setShowEq]=useState(false);
  const [showSchem,setShowSchem]=useState(false);
  // EMI damping (separate from Middlebrook stability damping)
  const [emiDamp,setEmiDamp]=useState(false);
  const [emiDampAuto,setEmiDampAuto]=useState(true);
  const [emiRd,setEmiRd]=useState(5);const [emiCd,setEmiCd]=useState(40);
  const [emiDampStage,setEmiDampStage]=useState(1); // which stage to damp (1 or 2)

  // ── Derived core params ──────────────────────────────────────────────────
  const ic=coreName==="Custom",P=CORES[coreName]||CORES.Custom;
  const matKey=ic?cMat:P.mat, mat=MAT[matKey]||MAT.MPP;
  const mu=ic?cMu:P.mu,AL=ic?cAL:P.AL,Ae=(ic?cAe:P.Ae)*1e-6,lec=(ic?cLe:P.le)/10,Ve=ic?cVe:P.Ve;
  const OD=ic?cOD:P.OD,ID=ic?cID:P.ID,HT=ic?cHT:P.HT;
  const wire=AWG_TABLE[awg]||AWG_TABLE[17],ins=INS[insType]||INS.heavy;

  // ── DC Bias ──────────────────────────────────────────────────────────────
  const H=(0.4*Math.PI*N*Idc)/lec;
  const pMu=pMuFn(mat,mu,H),Lbias=(AL*N*N*pMu)/1000,Lunbias=(AL*N*N)/1000;
  const Bdc=(Lbias*1e-6*Idc)/(N*Ae),satPct=Bdc/mat.bsat_T*100;
  const Luh=autoL?Lbias:Lman;
  const satW=satPct>80;

  // ── M-K Cw physics ───────────────────────────────────────────────────────
  const cwP=useMemo(()=>calcCwPhysics(wire.dc,wire.dw,ins.er,ins.tex,N,OD,ID,HT,kTor),[wire.dc,wire.dw,ins.er,ins.tex,N,OD,ID,HT,kTor]);

  // ── Effective Cw after mode selection + winding techniques ──────────────
  const CwEff_pF=useMemo(()=>{
    if(cwMode==="manual")return cwManual;
    let c=cwMode==="toroid"?cwP.C_tor_pF:cwP.C_total_pF;
    if(wS)c/=4; if(wP)c/=2.5; if(wO)c/=1.7; if(wF)c/=1.4; if(wSp)c/=1.3;
    return Math.max(c,0.01);
  },[cwP.C_total_pF,cwP.C_tor_pF,cwMode,cwManual,wS,wP,wO,wF,wSp]);

  // ── SRF uses UNBIASED L (v6 fix) ─────────────────────────────────────────
  // ── SRF — uses selectable L reference ─────────────────────────────────────
  const srfL=srfLmode==="unbias"?Lunbias:srfLmode==="bias"?Lbias:srfLman;
  const SRF=useMemo(()=>1/(2*Math.PI*Math.sqrt(srfL*1e-6*Math.max(CwEff_pF,1)*1e-12)),[srfL,CwEff_pF]);
  const SRFu=SRF/3;
  const srfOk=SRFu>fsw*1e3;

  // ── Source topology computations ─────────────────────────────────────────
  const topo=TOPOS[topoKey]||TOPOS.buck;
  // Compute unclamped D to detect impossible operating points
  const topD_raw=topoKey==="buck"?Vout/Vin
    :topoKey==="boost"?1-Vin/Vout
    :topoKey==="fwd2sw"?Vout/(Vin*(NsNp||0.01))
    :Vout/(Vout+Vin*(NsNp||0.01)); // flyback CCM/DCM
  const topD_max=topoKey==="fwd2sw"?0.5:0.99;
  const topD_valid=topD_raw>=0.01&&topD_raw<=topD_max;
  const topD=Math.min(Math.max(topD_raw,0.01),topD_max);
  // Minimum Ns/Np to achieve Vout at D_max (for isolated topologies)
  const NsNp_min=topoKey==="fwd2sw"?Vout/(Vin*0.5)
    :(topoKey==="flyCCM"||topoKey==="flyDCM")?Vout*Vin/(Vin*Vin-Vout*Vin+0.01) // approximate
    :null;
  const topIpp_auto=topo.ipp(Vin,Vout,topD,topo.hasIso?Lm*1e-6:Luh*1e-6,fsw*1e3)*1e3; // mA
  const Ipp_eff=autoIpp?topIpp_auto:Ipp;
  const Iavg_in=Iout*Vout/(Vin*0.9);
  const srcDB=20*Math.log10(Math.max(Ipp_eff/2,0.001)*1000);

  // Harmonic spectrum
  const srcParams=useMemo(()=>({D:topD,Iout,tr:tr*1e-9,fsw,Ipp:Ipp_eff*1e-3,Iavg:Iavg_in,NsNp}),[topD,Iout,tr,fsw,Ipp_eff,Iavg_in,NsNp]);
  const harmonicsAnalytical=useMemo(()=>computeHarmonics(topo,srcParams,10e6),[topo,srcParams]);
  // Use SPICE harmonics when available, otherwise analytical
  const harmonics=useSpice&&spiceResult&&!spiceResult.error?spiceResult.harmonics:harmonicsAnalytical;
  const srcLabel=useSpice&&spiceResult&&!spiceResult.error?`SPICE (${spiceFileName})`:topo.name;

  // Spectral envelope: SPICE or analytical
  // SPICE envelope function: interpolate from processed envelope array
  const spiceEnvAtF=useSpice&&spiceResult&&!spiceResult.error&&spiceResult.envelope.length>0
    ?(f)=>{
      const env=spiceResult.envelope;
      if(f<=env[0].f)return Math.pow(10,(env[0].dBuA-120)/20);
      if(f>=env[env.length-1].f)return Math.pow(10,(env[env.length-1].dBuA-120)/20);
      // Binary search
      let lo=0,hi=env.length-1;
      while(hi-lo>1){const m=(lo+hi)>>1;if(env[m].f<=f)lo=m;else hi=m;}
      const frac=(f-env[lo].f)/(env[hi].f-env[lo].f||1);
      const dB=env[lo].dBuA+(env[hi].dBuA-env[lo].dBuA)*frac;
      return Math.pow(10,(dB-120)/20);
    }:null;

  // Spectral envelope (continuous) for chart
  const srcEnvPts=useMemo(()=>Array.from({length:301},(_,i)=>{
    const f=100*Math.pow(1e5,i/300),logf=Math.log10(f);
    const Ienv=spiceEnvAtF?spiceEnvAtF(f):envAmplitude(f,topo,srcParams);
    const dBuA=20*Math.log10(Math.max(Ienv,1e-15)*1e6);
    return{logf,srcEnv:dBuA};
  }),[topo,srcParams,spiceEnvAtF]);

  // ── Core loss (uses Ipp_eff) ──────────────────────────────────────────────
  const {dB_T,Pvs,Pvc,Pvi,Pv,Ptot}=useMemo(()=>{
    const LH=Luh*1e-6,dBT=(LH*(Ipp_eff/2)*1e-3)/(N*Ae);
    const {k,alpha,beta}=mat.steinmetz,Pvs=k*Math.pow(fsw,alpha)*Math.pow(Math.max(dBT,1e-15),beta);
    const km=nearest(mat.csc,mu),{a,b,c,d}=mat.csc[km],bg=Math.max(dBT*10,1e-15);
    const Pvc=a*fsw*Math.pow(bg,b)+c*Math.pow(fsw,d)*bg*bg;
    const {Pv:Pvi}=calcIGSE(mat,dBT,fsw,topD);
    const Pv=lmod==="csc"?Pvc:lmod==="igse"?Pvi:Pvs;
    return{dB_T:dBT,Pvs,Pvc,Pvi,Pv,Ptot:Pv*Ve};
  },[Luh,N,Ae,Ipp_eff,fsw,mat,mu,Ve,lmod,topD]);

  // ── Dowell copper (uses Ipp_eff) ──────────────────────────────────────────
  const cu=useMemo(()=>calcDowell(wire.dc,wire.dw,N,cwP.nLayers,cwP.l_t_mm/1000,Idc,Ipp_eff,fsw),[wire.dc,wire.dw,N,cwP.nLayers,cwP.l_t_mm,Idc,Ipp_eff,fsw]);

  // ── EMI limit ────────────────────────────────────────────────────────────
  const limAtFsw=useMemo(()=>evalLimit(fsw*1e3,stdKey,emiCls,emiDet,emiVnom,Zs,c32Cls),[fsw,stdKey,emiCls,emiDet,emiVnom,Zs,c32Cls]);
  const lim=limAtFsw!==null?limAtFsw:limMan;
  const fswBand=getBandName(fsw*1e3,stdKey,emiDet);
  // Full limit curve for chart overlay
  const limCurve=useMemo(()=>buildLimitCurve(stdKey,emiCls,emiDet,emiVnom,Zs,srcDB,desMgn,c32Cls),[stdKey,emiCls,emiDet,emiVnom,Zs,srcDB,desMgn,c32Cls]);

  // ── Middlebrook: converter input impedance ────────────────────────────────
  const Zin_conv=Vbus*Vbus*etaMB/Math.max(Pout,1);
  const Zin_dBOhm=20*Math.log10(Math.max(Zin_conv,0.001));

  // ── Recommended damping values ────────────────────────────────────────────
  const Z0_undamped=Math.sqrt(Luh*1e-6/Math.max(Cnf*1e-9,1e-18));
  const Rd_rec=Z0_undamped;
  const Cd_rec_nF=4*Cnf;
  const Rd_act=dampAuto?Rd_rec:RdMan;
  const Cd_act_nF=dampAuto?Cd_rec_nF:CdMan;
  const rL_ohm=(cu.R_dc_mOhm||5)/1000;

  // ── Z_out(f) spectrum ─────────────────────────────────────────────────────
  const fc1_Hz=1/(2*Math.PI*Math.sqrt(Luh*1e-6*Math.max(Cnf*1e-9,1e-30)));
  const esrOhm1=capEsr/1000, esrOhm2=capEsr2/1000;
  const zoutPts=useMemo(()=>{
    const LH=Luh*1e-6, L2H=L2*1e-6;
    const rL2_ohm=rL_ohm*0.5;
    const peakFloor=fc1_Hz/5;
    let peakZout=0,peakF=0;
    const pts=Array.from({length:301},(_,i)=>{
      const f=100*Math.pow(1e5,i/300);
      const logf=Math.log10(f);
      const Z1_und=calcZout1(f,LH,Cnf,Zs,0,0,false,rL_ohm,esrOhm1,capEsl);
      const Z1_dmp=useDamping?calcZout1(f,LH,Cnf,Zs,Rd_act,Cd_act_nF,true,rL_ohm,esrOhm1,capEsl):null;
      const Z2_und=st2?calcZout2(f,LH,Cnf,L2H,C2,Zs,0,0,false,rL_ohm,rL2_ohm,esrOhm1,capEsl,esrOhm2,capEsl2):null;
      const Z2_dmp=st2&&useDamping?calcZout2(f,LH,Cnf,L2H,C2,Zs,Rd_act,Cd_act_nF,true,rL_ohm,rL2_ohm,esrOhm1,capEsl,esrOhm2,capEsl2):null;
      const activeZ=st2?(useDamping?Z2_dmp:Z2_und):(useDamping?Z1_dmp:Z1_und);
      if(f>=peakFloor && activeZ>peakZout){peakZout=activeZ;peakF=f;}
      const todB=v=>Math.min(Math.max(20*Math.log10(Math.max(v,0.001)),-40),100);
      return{
        logf,
        Z1_und:todB(Z1_und),
        Z1_dmp:useDamping?todB(Z1_dmp):null,
        Z2_und:st2?todB(Z2_und):null,
        Z2_dmp:st2&&useDamping?todB(Z2_dmp):null,
      };
    });
    const mbPass=peakZout<Zin_conv;
    return{pts,peakZout,peakF,mbPass};
  },[Luh,Cnf,Zs,rL_ohm,useDamping,Rd_act,Cd_act_nF,Zin_conv,st2,L2,C2,fc1_Hz,esrOhm1,capEsl,esrOhm2,capEsl2]);

  // ── Attenuation (proper insertion loss) + |Z| choke spectrum ──────────────
  const specPts=useMemo(()=>Array.from({length:301},(_,i)=>{
    const f=100*Math.pow(1e5,i/300),logf=Math.log10(f),w=2*Math.PI*f;
    const mf=muFf(f,mat,mu);
    const Le=Luh*1e-6*mf;
    const Cw=CwEff_pF*1e-12;
    const lct=w*w*Le*Cw;
    const Zmag=Math.abs(1-lct)<0.005?1e6:(w*Le)/Math.abs(1-lct);
    // IL computation — includes Middlebrook damping when active
    const a1=useDamping?calcIL1_d(f,Luh*1e-6,Cnf,Zs,rL_ohm,CwEff_pF,esrOhm1,capEsl,mat,mu,Rd_act,Cd_act_nF)
      :calcIL1(f,Luh*1e-6,Cnf,Zs,rL_ohm,CwEff_pF,esrOhm1,capEsl,mat,mu);
    let a2=a1;
    if(st2){
      a2=useDamping?calcIL2_d(f,Luh*1e-6,Cnf,L2*1e-6,C2,Zs,rL_ohm,rL_ohm*0.5,CwEff_pF,esrOhm1,capEsl,esrOhm2,capEsl2,mat,mu,Rd_act,Cd_act_nF,0,0)
        :calcIL2(f,Luh*1e-6,Cnf,L2*1e-6,C2,Zs,rL_ohm,rL_ohm*0.5,CwEff_pF,esrOhm1,capEsl,esrOhm2,capEsl2,mat,mu);
    }
    const lc=limCurve[i];
    const activeIL=st2?a2:a1;
    // Source from spectral envelope (frequency-dependent)
    const Ienv=spiceEnvAtF?spiceEnvAtF(f):envAmplitude(f,topo,srcParams);
    const srcAtF=20*Math.log10(Math.max(Ienv,1e-15)*1e6);
    const filteredEmission=srcAtF-activeIL;
    const dc=detCorr(f,fsw*1e3);
    // Required attenuation: source_envelope - limit (frequency-dependent)
    const needAtF=lc&&lc.limA!==null?Math.max(srcAtF-lc.limA+desMgn,0):null;
    return{logf,a1:Math.min(a1,120),a2:Math.min(a2,120),Z:Math.min(Math.max(20*Math.log10(Math.max(Zmag,1e-3)),-10),110),mupct:Math.min(mf*110,110),
      needA:needAtF!==null?Math.min(needAtF,120):null,
      limA:lc?lc.limA:null,
      srcEnv:srcAtF,
      emPk:filteredEmission,
      emQP:filteredEmission-dc.pk2qp,
      emAvg:filteredEmission-dc.pk2avg}
  }),[Luh,Cnf,mat,mu,CwEff_pF,st2,L2,C2,Zs,rL_ohm,esrOhm1,capEsl,esrOhm2,capEsl2,limCurve,fsw,topo,srcParams,desMgn,useDamping,Rd_act,Cd_act_nF,spiceEnvAtF]);

  const biasCurve=useMemo(()=>Array.from({length:101},(_,i)=>({H:i*2,pMu:Math.max(pMuFn(mat,mu,i*2)*100,0)})),[mat,mu]);

  // ── Resonance scanner — find peaks in emission that approach/exceed limit ──
  const fc2_Hz=st2?1/(2*Math.PI*Math.sqrt(L2*1e-6*C2*1e-9)):null;
  const capSRF1=1/(2*Math.PI*Math.sqrt(Math.max(capEsl*1e-9,1e-30)*Cnf*1e-9));
  const capSRF2=st2?1/(2*Math.PI*Math.sqrt(Math.max(capEsl2*1e-9,1e-30)*C2*1e-9)):null;

  const resonances=useMemo(()=>{
    const res=[];
    const Z0_1=Math.sqrt(Luh*1e-6/Math.max(Cnf*1e-9,1e-18));
    const Q1=Z0_1/Math.max(rL_ohm+esrOhm1,0.01);
    res.push({type:"LC₁",f:fc1_Hz,Q:Q1,Z0:Z0_1,stage:1,L:Luh,C:Cnf,
      Rd_sug:Z0_1,Cd_sug:4*Cnf,desc:"Stage 1 LC resonance"});
    if(st2&&fc2_Hz){
      const Z0_2=Math.sqrt(L2*1e-6/Math.max(C2*1e-9,1e-18));
      const Q2=Z0_2/Math.max(rL_ohm*0.5+esrOhm2,0.01);
      res.push({type:"LC₂",f:fc2_Hz,Q:Q2,Z0:Z0_2,stage:2,L:L2,C:C2,
        Rd_sug:Z0_2,Cd_sug:4*C2,desc:"Stage 2 LC resonance"});
    }
    res.push({type:"SRF",f:SRF,Q:null,Z0:null,stage:1,L:srfL,C:CwEff_pF/1000,
      Rd_sug:null,Cd_sug:null,desc:"Choke self-resonance (Cw)"});
    if(capSRF1<10e6)res.push({type:"C₁ SRF",f:capSRF1,Q:null,Z0:null,stage:1,L:0,C:Cnf,
      Rd_sug:null,Cd_sug:null,desc:"Cap 1 ESL resonance"});

    for(const r of res){
      const limAtRes=evalLimit(r.f,stdKey,emiCls,emiDet,emiVnom,Zs,c32Cls);
      if(limAtRes===null){r.margin=null;r.marginD=null;r.severity="—";r.severityD="—";continue}
      // Undamped emission at resonance frequency
      const srcAtRes=20*Math.log10(Math.max(envAmplitude(r.f,topo,srcParams),1e-15)*1e6);
      let il;
      if(st2)il=calcIL2(r.f,Luh*1e-6,Cnf,L2*1e-6,C2,Zs,rL_ohm,rL_ohm*0.5,CwEff_pF,esrOhm1,capEsl,esrOhm2,capEsl2,mat,mu);
      else il=calcIL1(r.f,Luh*1e-6,Cnf,Zs,rL_ohm,CwEff_pF,esrOhm1,capEsl,mat,mu);
      const em=srcAtRes-il;
      r.margin=limAtRes-em;r.em=em;r.lim=limAtRes;
      r.severity=r.margin<0?"FAIL":r.margin<6?"WARN":"OK";
      // Damped emission (if damping enabled)
      if(emiDamp&&r.Rd_sug){
        let ilD;
        const rAct=emiDampAuto?r.Rd_sug:(emiDampStage===r.stage?emiRd:0);
        const cAct=emiDampAuto?r.Cd_sug:(emiDampStage===r.stage?emiCd:0);
        if(rAct>0&&cAct>0){
          if(st2){
            const R1=r.stage===1?rAct:0,C1d=r.stage===1?cAct:0;
            const R2=r.stage===2?rAct:0,C2d=r.stage===2?cAct:0;
            ilD=calcIL2_d(r.f,Luh*1e-6,Cnf,L2*1e-6,C2,Zs,rL_ohm,rL_ohm*0.5,CwEff_pF,esrOhm1,capEsl,esrOhm2,capEsl2,mat,mu,R1,C1d,R2,C2d);
          } else {
            ilD=calcIL1_d(r.f,Luh*1e-6,Cnf,Zs,rL_ohm,CwEff_pF,esrOhm1,capEsl,mat,mu,rAct,cAct);
          }
          const emD=srcAtRes-ilD;
          r.marginD=limAtRes-emD;r.emD=emD;
          r.severityD=r.marginD<0?"FAIL":r.marginD<6?"WARN":"OK";
        } else {r.marginD=r.margin;r.severityD=r.severity;}
      } else {r.marginD=null;r.severityD=null;}
    }
    return res;
  },[fc1_Hz,fc2_Hz,SRF,capSRF1,Luh,Cnf,L2,C2,rL_ohm,esrOhm1,esrOhm2,st2,CwEff_pF,srfL,
    stdKey,emiCls,emiDet,emiVnom,Zs,c32Cls,topo,srcParams,mat,mu,capEsl,capEsl2,
    emiDamp,emiDampAuto,emiDampStage,emiRd,emiCd]);

  // ── EMI damping: auto-suggested values from worst resonance ──────────────
  const worstRes=resonances.find(r=>r.severity==="FAIL")||resonances.find(r=>r.severity==="WARN");
  const emiRd_sug=worstRes?.Rd_sug||Math.sqrt(Luh*1e-6/Math.max(Cnf*1e-9,1e-18));
  const emiCd_sug=worstRes?.Cd_sug||4*Cnf;
  const emiDampStg=emiDampAuto?(worstRes?.stage||1):emiDampStage;
  const emiRd_act=emiDampAuto?emiRd_sug:emiRd;
  const emiCd_act=emiDampAuto?emiCd_sug:emiCd;

  // ── Damped emission trace (with EMI damping applied) ─────────────────────
  const dampedPts=useMemo(()=>{
    if(!emiDamp)return null;
    return Array.from({length:301},(_,i)=>{
      const f=100*Math.pow(1e5,i/300),logf=Math.log10(f);
      let il;
      if(st2){
        const Rd1=emiDampStg===1?emiRd_act:0,Cd1=emiDampStg===1?emiCd_act:0;
        const Rd2=emiDampStg===2?emiRd_act:0,Cd2=emiDampStg===2?emiCd_act:0;
        il=calcIL2_d(f,Luh*1e-6,Cnf,L2*1e-6,C2,Zs,rL_ohm,rL_ohm*0.5,CwEff_pF,esrOhm1,capEsl,esrOhm2,capEsl2,mat,mu,Rd1,Cd1,Rd2,Cd2);
      } else {
        il=calcIL1_d(f,Luh*1e-6,Cnf,Zs,rL_ohm,CwEff_pF,esrOhm1,capEsl,mat,mu,emiRd_act,emiCd_act);
      }
      const Ienv=spiceEnvAtF?spiceEnvAtF(f):envAmplitude(f,topo,srcParams);
      const srcAtF=20*Math.log10(Math.max(Ienv,1e-15)*1e6);
      return{logf,emDamp:srcAtF-il};
    });
  },[emiDamp,emiRd_act,emiCd_act,emiDampStg,Luh,Cnf,L2,C2,Zs,rL_ohm,CwEff_pF,esrOhm1,capEsl,esrOhm2,capEsl2,mat,mu,st2,topo,srcParams,spiceEnvAtF]);

  // Merge damped trace into specPts — when damping ON, main traces show damped, with undamped as "before"
  const specPtsFinal=useMemo(()=>{
    if(!dampedPts)return specPts;
    return specPts.map((p,i)=>{
      const damp=dampedPts[i];
      if(!damp)return p;
      const dc=detCorr(Math.pow(10,p.logf),fsw*1e3);
      const dampedIL=p.srcEnv-damp.emDamp; // IL = source_envelope - damped_emission
      return{...p,
        emBefore:p.emPk,
        emPk:damp.emDamp,
        emQP:damp.emDamp-dc.pk2qp,
        emAvg:damp.emDamp-dc.pk2avg,
        a1_before:p.a1,
        a2_before:p.a2,
        a1:Math.min(dampedIL,120),
        a2:st2?Math.min(dampedIL,120):p.a2,
      };
    });
  },[specPts,dampedPts,fsw,st2]);

  // ── Per-harmonic emission dots — actual discrete emissions at n×fsw ──────
  const harmDots=useMemo(()=>{
    const dots=[];
    for(const h of harmonics){
      if(h.f>10e6||h.f<100)continue;
      const logfH=Math.log10(h.f);
      // Compute IL at this exact harmonic (with all active damping)
      let ilH;
      const mbR=useDamping?Rd_act:0, mbC=useDamping?Cd_act_nF:0;
      const eR1=emiDamp&&emiDampStg===1?emiRd_act:0, eC1=emiDamp&&emiDampStg===1?emiCd_act:0;
      const R1=Math.max(mbR,eR1), C1d=R1===mbR&&mbR>0?mbC:eC1;
      const eR2=emiDamp&&emiDampStg===2?emiRd_act:0, eC2=emiDamp&&emiDampStg===2?emiCd_act:0;
      if(st2)ilH=(R1>0||eR2>0)?calcIL2_d(h.f,Luh*1e-6,Cnf,L2*1e-6,C2,Zs,rL_ohm,rL_ohm*0.5,CwEff_pF,esrOhm1,capEsl,esrOhm2,capEsl2,mat,mu,R1,C1d,eR2,eC2)
        :calcIL2(h.f,Luh*1e-6,Cnf,L2*1e-6,C2,Zs,rL_ohm,rL_ohm*0.5,CwEff_pF,esrOhm1,capEsl,esrOhm2,capEsl2,mat,mu);
      else ilH=R1>0?calcIL1_d(h.f,Luh*1e-6,Cnf,Zs,rL_ohm,CwEff_pF,esrOhm1,capEsl,mat,mu,R1,C1d)
        :calcIL1(h.f,Luh*1e-6,Cnf,Zs,rL_ohm,CwEff_pF,esrOhm1,capEsl,mat,mu);
      const emFilt=h.dBuA-ilH;
      const limH=evalLimit(h.f,stdKey,emiCls,emiDet,emiVnom,Zs,c32Cls);
      dots.push({logf:logfH,harmEm:emFilt,n:h.n,limH,pass:limH===null||emFilt<limH-desMgn});
    }
    return dots;
  },[harmonics,Luh,Cnf,L2,C2,Zs,rL_ohm,CwEff_pF,esrOhm1,capEsl,esrOhm2,capEsl2,mat,mu,st2,
    useDamping,Rd_act,Cd_act_nF,emiDamp,emiRd_act,emiCd_act,emiDampStg,stdKey,emiCls,emiDet,emiVnom,c32Cls,desMgn]);

  // Merge harmonic dots into specPtsFinal at nearest bins
  const chartData=useMemo(()=>{
    const data=specPtsFinal.map(p=>({...p,harmEm:null}));
    for(const dot of harmDots){
      // Find nearest bin
      const idx=Math.round((dot.logf-Math.log10(100))/(Math.log10(1e7)-Math.log10(100))*300);
      if(idx>=0&&idx<data.length){
        data[idx]={...data[idx],harmEm:dot.harmEm,harmPass:dot.pass,harmN:dot.n};
      }
    }
    return data;
  },[specPtsFinal,harmDots]);

  const fc1=fc1_Hz;
  // Source level at fsw from spectral envelope
  const srcAtFsw=20*Math.log10(Math.max(envAmplitude(fsw*1e3,topo,srcParams),1e-15)*1e6);
  const need=limAtFsw!==null?srcAtFsw-limAtFsw+desMgn:srcDB+desMgn;
  // Attenuation at fsw — includes Middlebrook and/or EMI damping
  const mbRd_=useDamping?Rd_act:0, mbCd_=useDamping?Cd_act_nF:0;
  const eRd1_=emiDamp&&emiDampStg===1?emiRd_act:0, eCd1_=emiDamp&&emiDampStg===1?emiCd_act:0;
  const Rd1_=Math.max(mbRd_,eRd1_), Cd1_=Rd1_===mbRd_&&mbRd_>0?mbCd_:eCd1_;
  const eRd2_=emiDamp&&emiDampStg===2?emiRd_act:0, eCd2_=emiDamp&&emiDampStg===2?emiCd_act:0;
  let ach;
  if(st2){
    ach=(Rd1_>0||eCd2_>0)?calcIL2_d(fsw*1e3,Luh*1e-6,Cnf,L2*1e-6,C2,Zs,rL_ohm,rL_ohm*0.5,CwEff_pF,esrOhm1,capEsl,esrOhm2,capEsl2,mat,mu,Rd1_,Cd1_,eRd2_,eCd2_)
      :calcIL2(fsw*1e3,Luh*1e-6,Cnf,L2*1e-6,C2,Zs,rL_ohm,rL_ohm*0.5,CwEff_pF,esrOhm1,capEsl,esrOhm2,capEsl2,mat,mu);
  } else {
    ach=(Rd1_>0)?calcIL1_d(fsw*1e3,Luh*1e-6,Cnf,Zs,rL_ohm,CwEff_pF,esrOhm1,capEsl,mat,mu,Rd1_,Cd1_)
      :calcIL1(fsw*1e3,Luh*1e-6,Cnf,Zs,rL_ohm,CwEff_pF,esrOhm1,capEsl,mat,mu);
  }
  // Find worst harmonic margin across all harmonics (not just fsw)
  const worstHarmonic=useMemo(()=>{
    let worst={n:1,margin:Infinity,f:fsw*1e3,src:srcAtFsw};
    for(const h of harmonics){
      const limH=evalLimit(h.f,stdKey,emiCls,emiDet,emiVnom,Zs,c32Cls);
      if(limH===null)continue;
      let ilH;
      // Middlebrook damping Rd/Cd on stage 1
      const mbRd=useDamping?Rd_act:0, mbCd=useDamping?Cd_act_nF:0;
      // EMI damping (additional, may be on stage 1 or 2)
      const eRd1=emiDamp&&emiDampStg===1?emiRd_act:0, eCd1=emiDamp&&emiDampStg===1?emiCd_act:0;
      const eRd2=emiDamp&&emiDampStg===2?emiRd_act:0, eCd2=emiDamp&&emiDampStg===2?emiCd_act:0;
      // Use the larger Rd on stage 1 (Middlebrook or EMI — only one physical network)
      const Rd1=Math.max(mbRd,eRd1), Cd1=Rd1===mbRd&&mbRd>0?mbCd:eCd1;
      if(st2){
        ilH=calcIL2_d(h.f,Luh*1e-6,Cnf,L2*1e-6,C2,Zs,rL_ohm,rL_ohm*0.5,CwEff_pF,esrOhm1,capEsl,esrOhm2,capEsl2,mat,mu,Rd1,Cd1,eRd2,eCd2);
      } else {
        ilH=(Rd1>0||Cd1>0)?calcIL1_d(h.f,Luh*1e-6,Cnf,Zs,rL_ohm,CwEff_pF,esrOhm1,capEsl,mat,mu,Rd1,Cd1)
          :calcIL1(h.f,Luh*1e-6,Cnf,Zs,rL_ohm,CwEff_pF,esrOhm1,capEsl,mat,mu);
      }
      const emH=h.dBuA-ilH;
      const margin=limH-emH-desMgn;
      if(margin<worst.margin){worst={n:h.n,margin,f:h.f,src:h.dBuA,em:emH,lim:limH};}
    }
    return worst;
  },[harmonics,stdKey,emiCls,emiDet,emiVnom,Zs,c32Cls,desMgn,Luh,Cnf,L2,C2,rL_ohm,CwEff_pF,esrOhm1,capEsl,esrOhm2,capEsl2,mat,mu,st2,emiDamp,emiRd_act,emiCd_act,emiDampStg,useDamping,Rd_act,Cd_act_nF]);
  const pass=worstHarmonic.margin>=0;
  const Cn_needed=(1/(Math.pow(2*Math.PI*(fsw*1e3/Math.pow(10,need/40)),2)*Luh*1e-6))*1e9;

  const lgFsw=Math.log10(fsw*1e3),lgSRFu=Math.log10(SRFu),lgSRF=Math.log10(SRF);
  const lgFc1=Math.log10(fc1);
  const lgFc2=st2?Math.log10(1/(2*Math.PI*Math.sqrt(L2*1e-6*C2*1e-9))):null;
  const lgPeakF=zoutPts.peakF>0?Math.log10(zoutPts.peakF):lgFc1;

  const sel={background:"#141414",border:"1px solid #2a2a2a",color:"#f0b44c",padding:"4px 8px",borderRadius:3,width:"100%",fontSize:11,fontFamily:'"IBM Plex Mono",monospace',outline:"none"};

  const xfmt=v=>{const f=Math.pow(10,v);return f>=1e6?`${(f/1e6).toFixed(0)}M`:f>=1e3?`${Math.round(f/1e3)}k`:`${Math.round(f)}`};

  return (
    <div style={{background:"#080808",minHeight:"100vh",color:"#ccc",fontFamily:'"IBM Plex Mono","Courier New",monospace',padding:"14px 14px 60px",boxSizing:"border-box"}}>

      {/* Header */}
      <div style={{borderBottom:"1px solid #1a1a1a",paddingBottom:10,marginBottom:14,display:"flex",alignItems:"baseline",gap:16,flexWrap:"wrap"}}>
        <div style={{color:"#f0b44c",fontSize:15,fontWeight:700,letterSpacing:3}}>DM-EMI FILTER TOOL</div>
        <div style={{color:"#252525",fontSize:8,letterSpacing:1.5}}>v7.2 · EMI limits: CISPR25 V/I, CISPR32, CE102, CE101 · Emission spectrum chart · IL: complex TF · Z_out · Dowell · iGSE</div>
      </div>

      <div style={{display:"flex",gap:12,flexWrap:"wrap",alignItems:"flex-start"}}>
        {/* ── LEFT COLUMN ── */}
        <div style={{flex:"0 0 280px",minWidth:255}}>

          <Sec title="CORE MATERIAL">
            <div style={{marginBottom:8}}>
              <div style={{color:"#444",fontSize:9,marginBottom:4}}>CORE PRESET</div>
              <select value={coreName} onChange={e=>setCoreName(e.target.value)} style={sel}>
                {Object.keys(CORES).map(k=><option key={k} value={k}>{k}</option>)}
              </select>
            </div>
            {coreName==="Custom"?(<>
              <div style={{display:"grid",gridTemplateColumns:"1fr 1fr",gap:6,marginBottom:8}}>
                <div><div style={{color:"#444",fontSize:9,marginBottom:4}}>MATERIAL</div>
                  <select value={cMat} onChange={e=>setCMat(e.target.value)} style={{...sel,width:"100%"}}>
                    {Object.keys(MAT).map(k=><option key={k} value={k}>{MAT[k].short}</option>)}
                  </select></div>
                <div><div style={{color:"#444",fontSize:9,marginBottom:4}}>µi</div>
                  <select value={cMu} onChange={e=>setCMu(Number(e.target.value))} style={{...sel,width:"100%"}}>
                    {MAT[cMat].mus.map(p=><option key={p} value={p}>{p}µ</option>)}
                  </select></div>
              </div>
              <IR lbl="AL (nH/N²)" val={cAL} set={setCAL} unit="nH/N²" min={1} max={10000} step={1}/>
              <IR lbl="Ae" val={cAe} set={setCAe} unit="mm²" min={1} max={10000} step={0.1}/>
              <IR lbl="le" val={cLe} set={setCLe} unit="mm" min={1} max={1000} step={0.1}/>
              <IR lbl="Ve" val={cVe} set={setCVe} unit="cm³" min={0.01} max={1000} step={0.01}/>
              <IR lbl="OD" val={cOD} set={setCOD} unit="mm" min={1} max={300} step={0.1}/>
              <IR lbl="ID" val={cID} set={setCID} unit="mm" min={1} max={200} step={0.1}/>
              <IR lbl="HT" val={cHT} set={setCHT} unit="mm" min={1} max={100} step={0.1}/>
            </>):(
              <div style={{background:"#0a0a0a",border:"1px solid #1a1a1a",borderRadius:3,padding:"7px 9px",marginBottom:8}}>
                <div style={{display:"flex",flexWrap:"wrap",gap:"3px 14px",fontSize:10}}>
                  {[["µi",`${mu}`,"#aaa"],["AL",`${AL} nH/N²`,"#aaa"],["Bsat",`${mat.bsat_T} T`,mat.color],["Dims",`${OD}/${ID}/${HT}mm`,"#555"]].map(([l,v,c])=>(
                    <span key={l} style={{color:"#444"}}>{l}: <span style={{color:c}}>{v}</span></span>
                  ))}
                </div>
              </div>
            )}
            <IR lbl="Turns N" val={N} set={setN} unit="turns" min={1} max={1000} step={1}/>
            <IR lbl="DC load current" val={Idc} set={setIdc} unit="A rms" min={0} max={500} step={0.1}/>
            <div style={{background:"#08100a",border:"1px solid #162416",borderRadius:4,padding:"8px 10px",marginTop:4}}>
              <div style={{display:"grid",gridTemplateColumns:"1fr 1fr",gap:"5px 8px"}}>
                {[["H",`${fmt(H,1)} Oe`,"#aaa"],["%µ",`${fmt(pMu*100,1)}%`,pMu>0.7?"#33cc55":pMu>0.4?"#f0b44c":"#ff4444"],
                  ["L unbias",`${fmt(Lunbias,0)} µH`,"#888"],["L bias",`${fmt(Lbias,1)} µH`,"#f0b44c"],
                  ["B_dc",`${fmt(Bdc*1000,0)} mT`,satW?"#ff4444":"#aaa"],["Sat%",`${fmt(satPct,1)}%`,satW?"#ff4444":"#33cc55"]
                ].map(([l,v,c])=>(
                  <div key={l}><div style={{color:"#2a2a2a",fontSize:8}}>{l}</div><div style={{color:c,fontSize:12,fontWeight:700}}>{v}</div></div>
                ))}
              </div>
            </div>
          </Sec>

          <Sec title="WIRE — Cw MODEL" accent="#334466">
            <div style={{display:"grid",gridTemplateColumns:"1fr 1fr",gap:6,marginBottom:7}}>
              <div><div style={{color:"#444",fontSize:9,marginBottom:4}}>AWG</div>
                <select value={awg} onChange={e=>setAwg(Number(e.target.value))} style={{...sel,width:"100%"}}>
                  {Object.keys(AWG_TABLE).map(a=><option key={a} value={a}>{a} AWG</option>)}
                </select></div>
              <div><div style={{color:"#444",fontSize:9,marginBottom:4}}>INSULATION</div>
                <select value={insType} onChange={e=>setInsType(e.target.value)} style={{...sel,width:"100%"}}>
                  {Object.keys(INS).map(k=><option key={k} value={k}>{INS[k].lb}</option>)}
                </select></div>
            </div>

            {/* Window Fill (Magnetics Inc: N×Aw / WA, WA = π/4 × ID²) */}
            <div style={{background:cwP.fillPct>50?"#1a0808":cwP.fillPct>35?"#1a1200":"#080e18",border:`1px solid ${cwP.fillPct>50?"#882222":cwP.fillPct>35?"#664400":"#1a2a3a"}`,borderRadius:4,padding:"8px 10px",marginBottom:7}}>
              <div style={{color:"#334466",fontSize:8,marginBottom:4}}>WINDOW UTILIZATION (Magnetics Inc: N×Aw/WA)</div>
              <div style={{display:"flex",gap:12,alignItems:"center",marginBottom:6}}>
                <div>
                  <div style={{color:"#1a2a3a",fontSize:8}}>Fill %</div>
                  <div style={{color:cwP.fillPct>50?"#ff4444":cwP.fillPct>35?"#f0b44c":"#33cc55",fontSize:16,fontWeight:700}}>{fmt(cwP.fillPct,0)}%</div>
                </div>
                <div>
                  <div style={{color:"#1a2a3a",fontSize:8}}>A_window</div>
                  <div style={{color:"#555",fontSize:11}}>{fmt(cwP.A_window_mm2,0)} mm²</div>
                </div>
                <div>
                  <div style={{color:"#1a2a3a",fontSize:8}}>N×A_wire</div>
                  <div style={{color:"#555",fontSize:11}}>{fmt(N*cwP.A_wire_mm2,0)} mm²</div>
                </div>
              </div>
              <div style={{background:"#0a0a0a",height:6,borderRadius:3,overflow:"hidden"}}>
                <div style={{width:`${Math.min(cwP.fillPct,100)}%`,height:"100%",background:cwP.fillPct>50?"#ff4444":cwP.fillPct>35?"#f0b44c":"#33cc55",transition:"width 0.3s"}}/>
              </div>
              <div style={{color:"#333",fontSize:8,marginTop:4}}>
                {cwP.fillPct>50?"⚠ OVERFULL — wire won't fit. Reduce N or use finer wire.":cwP.fillPct>35?"⚠ Tight — verify fit. Consider smaller wire or fewer turns.":"✓ Fits comfortably"}
              </div>
              <div style={{color:"#1e1e1e",fontSize:8,marginTop:3}}>Turns/layer: {cwP.tpl} · Layers: {cwP.nLayers} · N₁={cwP.N1} N₂={cwP.N2} · MTL: {fmt(cwP.l_t_mm,1)}mm</div>
              <div style={{color:"#1e1e1e",fontSize:8,marginTop:2}}>Wound dims (Mag-Inc): OD={fmt(cwP.OD_wound,1)}mm · HT={fmt(cwP.HT_wound,1)}mm · ID_eff={fmt(cwP.ID_eff,1)}mm · L2 coverage: {fmt(cwP.angularL2*100,0)}%</div>
            </div>

            {/* Cw Geometry Mode Selector */}
            <div style={{marginBottom:8}}>
              <div style={{color:"#334466",fontSize:9,marginBottom:4}}>WINDING CAPACITANCE MODEL</div>
              <div style={{display:"flex",gap:4}}>
                {[["mk","M-K (Bobbin)"],["toroid","Toroid"],["manual","Manual"]].map(([k,lb])=>(
                  <div key={k} onClick={()=>setCwMode(k)}
                    style={{flex:1,textAlign:"center",padding:"4px 0",fontSize:9,fontWeight:700,cursor:"pointer",borderRadius:3,letterSpacing:1,
                      background:cwMode===k?"#1a2a3a":"#0d0d0d",border:`1px solid ${cwMode===k?"#4488ff":"#1e1e1e"}`,color:cwMode===k?"#4488ff":"#444"}}>
                    {lb}
                  </div>
                ))}
              </div>
            </div>

            {/* Manual Cw input */}
            {cwMode==="manual"&&<div style={{marginBottom:8}}>
              <IR lbl="Cw (measured)" val={cwManual} set={setCwManual} unit="pF" min={0.1} max={10000} step={0.1}/>
              <div style={{color:"#334466",fontSize:8,marginTop:2}}>From impedance analyzer: measure SRF, then Cw = 1/(4π²·f_SRF²·L)</div>
            </div>}

            {/* Toroid k factor slider */}
            {cwMode==="toroid"&&<div style={{marginBottom:8}}>
              <div style={{display:"flex",alignItems:"center",gap:8}}>
                <div style={{flex:1}}>
                  <div style={{color:"#334466",fontSize:8,marginBottom:3}}>COUPLING FACTOR k = {fmt(kTor,3)}</div>
                  <input type="range" min={0.005} max={0.1} step={0.001} value={kTor}
                    onChange={e=>setKTor(parseFloat(e.target.value))}
                    style={{width:"100%",accentColor:"#4488ff"}}/>
                  <div style={{display:"flex",justifyContent:"space-between",color:"#1a2a3a",fontSize:7}}>
                    <span>0.005 (loose)</span><span>0.025</span><span>0.1 (tight)</span>
                  </div>
                </div>
                <div onClick={()=>setKTor(0.025)} style={{padding:"3px 8px",fontSize:8,color:"#4488ff",border:"1px solid #1a2a3a",borderRadius:3,cursor:"pointer",whiteSpace:"nowrap"}}>Reset</div>
              </div>
              <div style={{color:"#1a2a3a",fontSize:7,marginTop:3}}>
                Default 0.025 calibrated against measured 55350/57T/17AWG data. Increase for tighter windings, decrease for single-layer or spaced turns.
              </div>
            </div>}

            {/* Cw decomposition — pipeline: Mag-Inc geometry → M-K base → toroid correction */}
            {cwMode!=="manual"&&<div style={{background:"#080e18",border:"1px solid #1a2a3a",borderRadius:4,padding:"8px 10px",marginBottom:7}}>
              {cwMode==="toroid"&&<>
                <div style={{color:"#334466",fontSize:7,marginBottom:4,letterSpacing:1}}>Mag-Inc GEOMETRY → M-K BASE → TOROID k={fmt(kTor,3)}</div>
                <div style={{display:"grid",gridTemplateColumns:"1fr 0.3fr 1fr",gap:4,alignItems:"center"}}>
                  {/* M-K base column (Mag-Inc geometry) */}
                  <div>
                    <div style={{color:"#1a2a3a",fontSize:7,marginBottom:3}}>M-K BASE (wound dims)</div>
                    {[["Same-layer",cwP.C_tor_same],["Wdg-core",cwP.C_wc_eff_pF],["Interlayer",cwP.C_inter_eff_pF],
                    ].map(([l,v])=>(
                      <div key={l} style={{display:"flex",justifyContent:"space-between",padding:"1px 0"}}>
                        <span style={{color:"#1a2a3a",fontSize:8}}>{l}</span>
                        <span style={{color:"#555",fontSize:9}}>{l==="Same-layer"?fmt(v,1):fmt(cwMode==="toroid"?cwP.C_maginc_base:v,0)} pF</span>
                      </div>
                    ))}
                  </div>
                  {/* Arrow */}
                  <div style={{textAlign:"center",color:"#4488ff",fontSize:14}}>→</div>
                  {/* Toroid corrected column */}
                  <div>
                    <div style={{color:"#4488ff",fontSize:7,marginBottom:3}}>TOROID (×k)</div>
                    {[["Same-layer",cwP.C_tor_same,"#4488ff"],["Wdg-core",cwP.C_tor_wc,"#ff8844"],["Interlayer",cwP.C_tor_inter,"#cc88ff"],
                    ].map(([l,v,c])=>(
                      <div key={l} style={{display:"flex",justifyContent:"space-between",padding:"1px 0"}}>
                        <span style={{color:"#1a2a3a",fontSize:8}}>{l}</span>
                        <span style={{color:c,fontSize:10,fontWeight:700}}>{fmt(v,2)} pF</span>
                      </div>
                    ))}
                    <div style={{display:"flex",justifyContent:"space-between",padding:"2px 0",borderTop:"1px solid #1a2a3a",marginTop:2}}>
                      <span style={{color:"#1a2a3a",fontSize:8,fontWeight:700}}>TOTAL</span>
                      <span style={{color:"#33cc55",fontSize:11,fontWeight:700}}>{fmt(cwP.C_tor_pF,1)} pF</span>
                    </div>
                  </div>
                </div>
                <div style={{color:"#1a2a3a",fontSize:7,marginTop:6,lineHeight:1.4}}>
                  Pipeline: Magnetics Inc wound dimensions (OD={fmt(cwP.OD_wound,1)}, ID_eff={fmt(cwP.ID_eff,1)}) → M-K parallel-plate base ({fmt(cwP.C_maginc_base,0)} pF) → toroid coupling correction (k={fmt(kTor,3)}, L2 coverage={fmt(cwP.angularL2*100,0)}%).
                </div>
              </>}
              {cwMode==="mk"&&<>
                <div style={{color:"#334466",fontSize:7,marginBottom:4,letterSpacing:1}}>M-K BOBBIN MODEL (bare core dims)</div>
                {[["Same-layer",cwP.C_same_pF,"#4488ff"],["Wdg-to-core",cwP.C_wc_eff_pF,"#ff8844"],
                  ["Interlayer",cwP.C_inter_eff_pF,"#cc88ff"],["TOTAL",cwP.C_total_pF,"#33cc55"]
                ].map(([l,v,c])=>(
                  <div key={l} style={{display:"flex",justifyContent:"space-between",padding:"1px 0"}}>
                    <span style={{color:"#1a2a3a",fontSize:8}}>{l}</span>
                    <span style={{color:c,fontSize:10,fontWeight:l==="TOTAL"?700:400}}>{fmt(v,1)} pF</span>
                  </div>
                ))}
                <div style={{color:"#1a2a3a",fontSize:7,marginTop:6,lineHeight:1.4}}>
                  Massarini-Kazimierczuk 1997 — accurate for bobbin/E-core. Overestimates Cw on toroids by 30–100×.
                </div>
              </>}
            </div>}

            {/* Active Cw + SRF display with L-reference selector */}
            <div style={{background:cwMode==="manual"?"#0a1820":"#080e18",border:`1px solid ${cwMode==="manual"?"#226688":"#1a2a3a"}`,borderRadius:4,padding:"8px 10px"}}>
              <div style={{display:"flex",justifyContent:"space-between",alignItems:"center",marginBottom:6}}>
                <div>
                  <div style={{color:"#1a2a3a",fontSize:7}}>EFFECTIVE Cw{cwMode==="manual"?" (measured)":cwMode==="toroid"?` (k=${fmt(kTor,3)})`:""}</div>
                  <div style={{color:"#4488ff",fontSize:14,fontWeight:700}}>{fmt(CwEff_pF,1)} pF</div>
                </div>
                <div style={{textAlign:"right"}}>
                  <div style={{color:"#1a2a3a",fontSize:7}}>SRF (L={fmt(srfL,0)}µH)</div>
                  <div style={{color:srfOk?"#33cc55":"#ff4444",fontSize:14,fontWeight:700}}>{fmtF(SRF)}</div>
                </div>
              </div>
              {/* SRF L-reference selector */}
              <div style={{marginBottom:4}}>
                <div style={{color:"#1a2a3a",fontSize:7,marginBottom:3}}>SRF INDUCTANCE REFERENCE</div>
                <div style={{display:"flex",gap:3}}>
                  {[["unbias",`Unbias ${fmt(Lunbias,0)}µH`],["bias",`Biased ${fmt(Lbias,0)}µH`],["manual","Manual"]].map(([k,lb])=>(
                    <div key={k} onClick={()=>setSrfLmode(k)}
                      style={{flex:1,textAlign:"center",padding:"3px 0",fontSize:8,fontWeight:700,cursor:"pointer",borderRadius:3,
                        background:srfLmode===k?"#1a2a3a":"#0a0a0a",border:`1px solid ${srfLmode===k?"#4488ff":"#151515"}`,color:srfLmode===k?"#4488ff":"#444"}}>
                      {lb}
                    </div>
                  ))}
                </div>
              </div>
              {srfLmode==="manual"&&<div style={{marginBottom:4}}>
                <IR lbl="L for SRF" val={srfLman} set={setSrfLman} unit="µH" min={1} max={100000} step={1}/>
              </div>}
              <div style={{color:"#1a2a3a",fontSize:7,lineHeight:1.4}}>
                {srfLmode==="unbias"?"Unbiased: worst-case SRF (highest L → lowest SRF). Conservative."
                  :srfLmode==="bias"?"Biased: actual SRF under DC load. L drops with bias → SRF rises."
                  :"Manual: enter your measured or known inductance value."}
              </div>
              {(wS||wP||wO||wF||wSp)&&cwMode!=="manual"&&<div style={{color:"#2a3a4a",fontSize:8,marginTop:3}}>After winding techniques: {cwMode==="toroid"?fmt(cwP.C_tor_pF,1):fmt(cwP.C_total_pF,1)} pF → {fmt(CwEff_pF,1)} pF</div>}
            </div>
          </Sec>

          <Sec title="CORE LOSS + COPPER (DOWELL)">
            <div style={{display:"flex",gap:4,marginBottom:8}}>
              {[["simple","Simple"],["csc","CSC"],["igse","iGSE"]].map(([m,lb])=>(
                <div key={m} onClick={()=>setLmod(m)} style={{flex:1,textAlign:"center",padding:"4px 0",fontSize:8,background:lmod===m?"#1a1a0a":"#0d0d0d",border:`1px solid ${lmod===m?"#f0b44c":"#1e1e1e"}`,color:lmod===m?"#f0b44c":"#444",borderRadius:3,cursor:"pointer"}}>{lb}</div>
              ))}
            </div>
            <IR lbl="DM Ripple (pk-pk)" val={Ipp} set={setIpp} unit="mA pk-pk" min={0.01} max={10000} step={0.1}/>
            {lmod==="igse"&&<IR lbl="Duty cycle D" val={parseFloat(fmt(topD,3))} set={()=>{}} unit={`(from ${topo.name})`} ro/>}
            <div style={{background:"#0a0a0a",border:"1px solid #1a1a1a",borderRadius:4,padding:"8px 10px",marginBottom:7}}>
              <div style={{display:"grid",gridTemplateColumns:"1fr 1fr",gap:"5px 8px"}}>
                {[["ΔB",`${fmt(dB_T*1000,3)} mT`,"#888"],["Pv(s)",`${fmt(Pvs,1)} mW/cm³`,lmod==="simple"?"#f0b44c":"#333"],
                  ["Pv(csc)",`${fmt(Pvc,1)} mW/cm³`,lmod==="csc"?"#f0b44c":"#333"],["Pv(iGSE)",`${fmt(Pvi,1)} mW/cm³`,lmod==="igse"?"#f0b44c":"#333"],
                  ["P_core",`${fmt(Ptot,0)} mW`,Ptot>500?"#ff4444":Ptot>200?"#f0b44c":"#33cc55"],["Ve",`${Ve} cm³`,"#444"]
                ].map(([l,v,c])=>(
                  <div key={l}><div style={{color:"#282828",fontSize:8}}>{l}</div><div style={{color:c,fontSize:11,fontWeight:700}}>{v}</div></div>
                ))}
              </div>
            </div>
            <div style={{background:"#0a0a0a",border:"1px solid #1a1a1a",borderRadius:4,padding:"8px 10px"}}>
              <div style={{display:"grid",gridTemplateColumns:"1fr 1fr",gap:"5px 8px"}}>
                {[["δ",`${fmt(cu.delta_um,0)} µm`,"#888"],["ξ=d/δ",`${fmt(cu.xi,2)}`,"#888"],
                  ["FR",`${fmt(cu.FR,2)}×`,"#f0b44c"],["R_dc",`${fmt(cu.R_dc_mOhm,1)} mΩ`,"#555"],
                  ["P_copper",`${fmt(cu.P_total_mW,0)} mW`,cu.P_total_mW>1000?"#ff4444":cu.P_total_mW>500?"#f0b44c":"#33cc55"],
                  ["Total",`${fmt(Ptot+cu.P_total_mW,0)} mW`,"#aaa"]
                ].map(([l,v,c])=>(
                  <div key={l}><div style={{color:"#282828",fontSize:8}}>{l}</div><div style={{color:c,fontSize:11,fontWeight:700}}>{v}</div></div>
                ))}
              </div>
            </div>
          </Sec>

          <Sec title="FILTER PARAMETERS">
            <div style={{display:"flex",alignItems:"center",gap:7,marginBottom:10,flexWrap:"wrap"}}>
              <div style={{color:"#444",fontSize:9}}>L:</div>
              {[true,false].map(ia=>(<div key={String(ia)} onClick={()=>setAutoL(ia)} style={{padding:"3px 10px",fontSize:9,letterSpacing:1,borderRadius:10,background:autoL===ia?"#f0b44c":"#1a1a1a",border:"1px solid #2a2a2a",color:autoL===ia?"#000":"#555",cursor:"pointer",fontWeight:700}}>{ia?"AUTO":"MANUAL"}</div>))}
            </div>
            {autoL?<IR lbl="L (biased, auto)" val={Lbias} set={()=>{}} unit="µH" ro/>:<IR lbl="L (manual)" val={Lman} set={setLman} unit="µH" min={1} max={100000} step={1}/>}
            <IR lbl="Capacitance C" val={Cnf} set={setCnf} unit="nF" min={0.01} max={100000} step={0.1}/>
            <IR lbl="Switching Freq." val={fsw} set={setFsw} unit="kHz" min={1} max={5000} step={1}/>
            <div style={{background:"#0a0a0a",border:"1px solid #1a1a1a",borderRadius:4,padding:"8px 10px",marginTop:6}}>
              <div style={{color:"#444",fontSize:8,marginBottom:5}}>CAP PARASITICS</div>
              <IR lbl="ESR" val={capEsr} set={setCapEsr} unit="mΩ" min={0} max={10000} step={1}/>
              <IR lbl="ESL" val={capEsl} set={setCapEsl} unit="nH" min={0} max={100} step={0.1}/>
              <div style={{color:"#222",fontSize:8,marginTop:2}}>Cap SRF: {fmtF(1/(2*Math.PI*Math.sqrt(Math.max(capEsl*1e-9,1e-30)*Cnf*1e-9)))}</div>
            </div>
          </Sec>

          <Sec title="DUT — SOURCE SPECTRUM" accent="#884400">
            {/* Source mode toggle */}
            <div style={{display:"flex",gap:4,marginBottom:10}}>
              {[["topo","TOPOLOGY"],["spice","IMPORT SPICE"]].map(([k,lb])=>(
                <div key={k} onClick={()=>setUseSpice(k==="spice")}
                  style={{flex:1,textAlign:"center",padding:"5px 0",fontSize:9,fontWeight:700,cursor:"pointer",borderRadius:3,letterSpacing:1.5,
                    background:(k==="spice")==useSpice?"#884400":"#0d0d0d",border:`1px solid ${(k==="spice")==useSpice?"#ff8844":"#1e1e1e"}`,
                    color:(k==="spice")==useSpice?"#ff8844":"#444"}}>
                  {lb}
                </div>
              ))}
            </div>

            {/* ── SPICE IMPORT PANEL ── */}
            {useSpice&&(()=>{
              const stdReq=getStdRequirements(stdKey);
              const handleFile=(e)=>{
                const file=e.target.files?.[0];
                if(!file)return;
                setSpiceFileName(file.name);
                const reader=new FileReader();
                reader.onload=(ev)=>{
                  const text=ev.target?.result;
                  if(!text)return;
                  const result=processSpiceImport(text,spiceSigType,Zs,fsw*1e3);
                  setSpiceResult(result);
                };
                reader.readAsText(file);
              };
              return <>
                {/* Requirements panel */}
                <div style={{background:"#120800",border:"1px solid #3a2200",borderRadius:4,padding:"10px 12px",marginBottom:10}}>
                  <div style={{color:"#ff8844",fontSize:8,letterSpacing:1.5,marginBottom:6}}>DATA REQUIREMENTS — {stdReq.name}</div>
                  <div style={{color:"#664400",fontSize:8,marginBottom:4}}>Based on your selected EMI standard ({stdReq.name}, {fmtF(stdReq.fMin)}–{fmtF(stdReq.fMax)})</div>
                  <div style={{display:"grid",gridTemplateColumns:"1fr 1fr",gap:"5px 12px",marginBottom:8}}>
                    {[["Steady-state duration",`≥ ${fmt(stdReq.minDurationUs,0)} µs`],
                      ["Freq resolution (1/duration)",`≤ ${fmtF(stdReq.rbw)}`],
                      ["Min cycles @ fsw",`≥ ${Math.ceil(stdReq.minDuration*fsw*1e3)} cycles`],
                      ["Frequency coverage",`${fmtF(stdReq.fMin)} → ${fmtF(stdReq.fMax)}`],
                    ].map(([l,v])=>(
                      <div key={l}>
                        <div style={{color:"#442200",fontSize:7}}>{l}</div>
                        <div style={{color:"#ff8844",fontSize:10,fontWeight:700}}>{v}</div>
                      </div>
                    ))}
                  </div>
                  <div style={{color:"#442200",fontSize:7,lineHeight:1.5}}>
                    Capture the DM input current (or LISN voltage) from your SPICE simulation after startup transients have fully settled. Export as CSV (time, amplitude) or LTspice .txt.
                  </div>
                </div>

                {/* Signal type selector */}
                <div style={{marginBottom:8}}>
                  <div style={{color:"#664400",fontSize:8,marginBottom:3}}>SIGNAL TYPE</div>
                  <div style={{display:"flex",gap:4}}>
                    {[["current","Current (A)"],["voltage","Voltage across LISN (V)"]].map(([k,lb])=>(
                      <div key={k} onClick={()=>setSpiceSigType(k)}
                        style={{flex:1,textAlign:"center",padding:"4px 0",fontSize:9,fontWeight:700,cursor:"pointer",borderRadius:3,
                          background:spiceSigType===k?"#3a2200":"#0d0d0d",border:`1px solid ${spiceSigType===k?"#ff8844":"#1e1e1e"}`,
                          color:spiceSigType===k?"#ff8844":"#444"}}>
                        {lb}
                      </div>
                    ))}
                  </div>
                  {spiceSigType==="voltage"&&<div style={{color:"#442200",fontSize:7,marginTop:3}}>Voltage will be divided by LISN impedance ({Zs}Ω) to get current</div>}
                </div>

                {/* Fsw for harmonic extraction */}
                <div style={{marginBottom:8}}>
                  <div style={{color:"#664400",fontSize:8,marginBottom:3}}>SWITCHING FREQUENCY FOR HARMONICS</div>
                  <div style={{color:"#ff8844",fontSize:10,fontWeight:700,marginBottom:3}}>Using: {fsw} kHz (from filter parameters)</div>
                  <div style={{color:"#442200",fontSize:7}}>Harmonics extracted at n × {fsw} kHz. Change fsw in Filter Parameters section above if needed. Auto-detected fsw shown in validation for comparison.</div>
                </div>

                {/* File upload */}
                <div style={{marginBottom:10}}>
                  <label style={{display:"block",background:"#1a0e00",border:"2px dashed #663300",borderRadius:6,padding:"16px 12px",textAlign:"center",cursor:"pointer"}}>
                    <input type="file" accept=".csv,.txt,.tsv" onChange={handleFile} style={{display:"none"}}/>
                    <div style={{color:"#ff8844",fontSize:11,fontWeight:700,marginBottom:4}}>
                      {spiceFileName?`📄 ${spiceFileName}`:"📂 UPLOAD CSV / TXT FILE"}
                    </div>
                    <div style={{color:"#553300",fontSize:8}}>
                      {spiceFileName?"Click to replace":"Column 1: time (s) · Column 2: amplitude (A or V)"}
                    </div>
                  </label>
                </div>

                {/* Validation results */}
                {spiceResult&&spiceResult.error&&<div style={{background:"#1a0808",border:"1px solid #662222",borderRadius:4,padding:"8px 10px",marginBottom:8,color:"#ff6666",fontSize:10}}>
                  ✖ {spiceResult.error}
                </div>}

                {spiceResult&&!spiceResult.error&&<div style={{background:"#0a0800",border:"1px solid #2a1a00",borderRadius:4,padding:"10px 12px",marginBottom:8}}>
                  <div style={{color:"#ff8844",fontSize:8,letterSpacing:1.5,marginBottom:6}}>IMPORT VALIDATION</div>
                  <div style={{display:"grid",gridTemplateColumns:"1fr 1fr",gap:"4px 10px",marginBottom:8}}>
                    {[
                      ["Points",`${spiceResult.validation.points.toLocaleString()}`,true],
                      ["Duration",`${fmt(spiceResult.validation.duration*1e6,1)} µs`,spiceResult.validation.duration>=stdReq.minDuration],
                      ["Freq resolution (df)",fmtF(spiceResult.df),spiceResult.df<=stdReq.rbw],
                      ["Max frequency",fmtF(spiceResult.validation.fMax),spiceResult.validation.fMax>=stdReq.fMax],
                      ["fsw detected",fmtF(spiceResult.validation.fswDetected),Math.abs(spiceResult.validation.fswDetected-fsw*1e3)<fsw*50],
                      ["Cycles",`${spiceResult.validation.nCyclesDetected}`,spiceResult.validation.nCyclesDetected>=3],
                    ].map(([l,v,ok])=>(
                      <div key={l}>
                        <div style={{color:"#442200",fontSize:7}}>{ok?"✓":"⚠"} {l}</div>
                        <div style={{color:ok?"#33cc55":"#ff8844",fontSize:10,fontWeight:700}}>{v}</div>
                      </div>
                    ))}
                  </div>
                  {spiceResult.df>stdReq.rbw&&<div style={{background:"#1a0808",border:"1px solid #662222",borderRadius:3,padding:"5px 8px",marginBottom:6,color:"#ff6666",fontSize:8}}>
                    ⚠ Frequency resolution ({fmtF(spiceResult.df)}) exceeds RBW ({fmtF(stdReq.rbw)}). Harmonics may not be individually resolved. Increase simulation duration to ≥{fmt(1/stdReq.rbw*1e6,0)} µs.
                  </div>}
                  {Math.abs(spiceResult.validation.fswDetected-fsw*1e3)>fsw*50&&<div style={{background:"#1a1200",border:"1px solid #664400",borderRadius:3,padding:"5px 8px",marginBottom:6,color:"#f0b44c",fontSize:8}}>
                    ⚠ Detected fsw ({fmtF(spiceResult.validation.fswDetected)}) differs from filter parameter ({fsw} kHz). Using {fsw} kHz for harmonic extraction.
                  </div>}
                  {spiceResult.dcOffset!==0&&<div style={{color:"#664400",fontSize:8,marginBottom:4}}>DC offset removed: {fmt(spiceResult.dcOffset*1000,2)} mA</div>}
                  <div style={{color:"#ff8844",fontSize:9,fontWeight:700}}>Harmonics extracted: {spiceResult.harmonics.length} (H1–H{spiceResult.harmonics.length})</div>
                  {spiceResult.harmonics.length>0&&<div style={{color:"#664400",fontSize:8,marginTop:4}}>
                    H1: {fmt(spiceResult.harmonics[0].dBuA,1)} dBµA @ {fmtF(spiceResult.harmonics[0].f)}
                    {spiceResult.harmonics.length>2&&<span> · H3: {fmt(spiceResult.harmonics[2].dBuA,1)} dBµA</span>}
                  </div>}
                  {/* Analytical comparison */}
                  {harmonicsAnalytical.length>0&&<div style={{background:"#0a0600",border:"1px solid #221100",borderRadius:3,padding:"6px 8px",marginTop:8}}>
                    <div style={{color:"#442200",fontSize:7,marginBottom:4}}>SPICE vs ANALYTICAL COMPARISON (first 5 harmonics)</div>
                    <div style={{display:"grid",gridTemplateColumns:"auto 1fr 1fr 1fr",gap:"2px 8px",fontSize:8}}>
                      <div style={{color:"#332200"}}></div><div style={{color:"#332200"}}>SPICE</div><div style={{color:"#332200"}}>Analytical</div><div style={{color:"#332200"}}>Δ</div>
                      {spiceResult.harmonics.slice(0,5).map((sh,i)=>{
                        const ah=harmonicsAnalytical[i];
                        const delta=ah?sh.dBuA-ah.dBuA:0;
                        return [
                          <div key={`l${i}`} style={{color:"#664400"}}>H{sh.n}</div>,
                          <div key={`s${i}`} style={{color:"#ff8844"}}>{fmt(sh.dBuA,1)}</div>,
                          <div key={`a${i}`} style={{color:"#888"}}>{ah?fmt(ah.dBuA,1):"—"}</div>,
                          <div key={`d${i}`} style={{color:Math.abs(delta)>6?"#ff4444":Math.abs(delta)>3?"#f0b44c":"#33cc55"}}>{delta>0?"+":""}{fmt(delta,1)} dB</div>,
                        ];
                      })}
                    </div>
                  </div>}
                </div>}

                {/* Clear button */}
                {spiceResult&&<div style={{textAlign:"center",marginBottom:8}}>
                  <div onClick={()=>{setSpiceResult(null);setSpiceFileName("");}} style={{display:"inline-block",padding:"4px 14px",fontSize:9,color:"#664400",border:"1px solid #332200",borderRadius:3,cursor:"pointer"}}>CLEAR IMPORT</div>
                </div>}
              </>;
            })()}

            {/* ── TOPOLOGY PANEL (hidden when SPICE active with valid data) ── */}
            {(!useSpice||!spiceResult||spiceResult.error)&&<>
            <div style={{marginBottom:8}}>
              <div style={{color:"#664400",fontSize:9,marginBottom:4}}>CONVERTER TOPOLOGY</div>
              <select value={topoKey} onChange={e=>setTopoKey(e.target.value)} style={{...sel,borderColor:"#884400"}}>
                {Object.keys(TOPOS).map(k=><option key={k} value={k}>{TOPOS[k].name}</option>)}
              </select>
            </div>
            <div style={{color:"#332200",fontSize:8,marginBottom:8}}>{topo.desc}</div>
            <IR lbl="V_in (bus)" val={Vin} set={setVin} unit="V" min={1} max={1000} step={1}/>
            <IR lbl="V_out" val={Vout} set={setVout} unit="V" min={0.5} max={500} step={0.5}/>
            <IR lbl="I_out (load)" val={Iout} set={setIout} unit="A" min={0.01} max={200} step={0.1}/>
            {topo.hasIso&&<>
              <IR lbl="Ns/Np (turns ratio)" val={NsNp} set={setNsNp} unit="" min={0.01} max={100} step={0.01}/>
              <IR lbl="Lm (magnetizing)" val={Lm} set={setLm} unit="µH" min={1} max={100000} step={1}/>
            </>}
            <IR lbl="Rise/fall time" val={tr} set={setTr} unit="ns" min={1} max={500} step={1}/>
            {/* Ipp auto/manual — different meaning per topology */}
            {!topo.hasIso&&<>
              <div style={{display:"flex",alignItems:"center",gap:7,marginTop:8,marginBottom:6,flexWrap:"wrap"}}>
                <div style={{color:"#444",fontSize:9}}>ΔI_pp:</div>
                {[true,false].map(ia=>(<div key={String(ia)} onClick={()=>setAutoIpp(ia)} style={{padding:"3px 10px",fontSize:9,letterSpacing:1,borderRadius:10,background:autoIpp===ia?"#f0b44c":"#1a1a1a",border:"1px solid #2a2a2a",color:autoIpp===ia?"#000":"#555",cursor:"pointer",fontWeight:700}}>{ia?"AUTO":"MANUAL"}</div>))}
              </div>
              {autoIpp?<IR lbl="ΔI_pp (auto)" val={parseFloat(fmt(Ipp_eff,2))} set={()=>{}} unit="mA pk-pk" ro/>
                :<IR lbl="ΔI_pp (manual)" val={Ipp} set={setIpp} unit="mA pk-pk" min={0.01} max={10000} step={0.1}/>}
            </>}
            {topo.hasIso&&<>
              <div style={{display:"flex",alignItems:"center",gap:7,marginTop:8,marginBottom:6,flexWrap:"wrap"}}>
                <div style={{color:"#444",fontSize:9}}>Source mode:</div>
                {[true,false].map(ia=>(<div key={String(ia)} onClick={()=>setAutoIpp(ia)} style={{padding:"3px 10px",fontSize:9,letterSpacing:1,borderRadius:10,background:autoIpp===ia?"#f0b44c":"#1a1a1a",border:"1px solid #2a2a2a",color:autoIpp===ia?"#000":"#555",cursor:"pointer",fontWeight:700}}>{ia?"AUTO":"MANUAL"}</div>))}
              </div>
              {!autoIpp&&<IR lbl="ΔI_m (manual override)" val={Ipp} set={setIpp} unit="mA pk-pk" min={0.01} max={10000} step={0.1}/>}
            </>}
            {/* Computed operating point */}
            {!topD_valid&&<div style={{background:"#1a0808",border:"1px solid #662222",borderRadius:4,padding:"7px 10px",marginBottom:6,fontSize:9,color:"#ff6666"}}>
              ✖ IMPOSSIBLE OPERATING POINT — D_required = {fmt(topD_raw,3)} but {topo.name} max is {fmt(topD_max,2)}.
              {topoKey==="fwd2sw"&&NsNp_min!==null&&<span> Minimum Ns/Np = <b>{fmt(NsNp_min,3)}</b> (you have {NsNp})</span>}
              {topoKey!=="fwd2sw"&&topoKey!=="buck"&&topoKey!=="boost"&&NsNp_min!==null&&<span> Try increasing Ns/Np above {fmt(NsNp_min,3)}</span>}
              {(topoKey==="buck")&&<span> V_out must be &lt; V_in ({Vin}V)</span>}
            </div>}
            {/* DM noise source breakdown for isolated topologies */}
            {topo.hasIso&&(()=>{
              const IL_refl=NsNp*Iout;
              const dIm=Ipp_eff; // mA
              const dIm_A=dIm/1000;
              // Fundamental harmonic amplitude (approximate)
              const H1_rect=2*IL_refl*topD*Math.abs(Math.sin(Math.PI*topD)/(Math.PI*topD));
              const H1_mag=2*dIm_A*topD/(Math.PI*Math.PI*topD*topD); // rough
              const H1_total=H1_rect+H1_mag;
              const pctRect=H1_rect/(H1_total||1)*100;
              return <div style={{background:"#120a00",border:"1px solid #3a2200",borderRadius:4,padding:"9px 10px",marginTop:6,marginBottom:6}}>
                <div style={{color:"#884400",fontSize:8,letterSpacing:1.5,marginBottom:6}}>DM INPUT CURRENT BREAKDOWN</div>
                <div style={{color:"#664400",fontSize:8,marginBottom:3}}>The input current has two components that create EMI:</div>
                {/* Reflected load — dominant */}
                <div style={{display:"flex",alignItems:"center",gap:8,padding:"6px 8px",background:"#1a0e00",borderRadius:3,marginBottom:4,border:"1px solid #442200"}}>
                  <div style={{width:8,height:8,borderRadius:4,background:"#ff8844",flexShrink:0}}/>
                  <div style={{flex:1}}>
                    <div style={{color:"#ff8844",fontSize:10,fontWeight:700}}>I_reflected = Ns/Np × I_out = {fmt(IL_refl,2)} A</div>
                    <div style={{color:"#884400",fontSize:8}}>Rectangular pulse at D={fmt(topD,3)} — this is a {fmt(IL_refl,1)}A current being switched on/off {fmt(fsw,0)} kHz.</div>
                    <div style={{color:"#ff8844",fontSize:9,fontWeight:700,marginTop:2}}>Dominates emissions ({fmt(pctRect,0)}% of H1)</div>
                  </div>
                </div>
                {/* Magnetizing ripple — small */}
                <div style={{display:"flex",alignItems:"center",gap:8,padding:"6px 8px",background:"#0e0a00",borderRadius:3,marginBottom:4,border:"1px solid #2a1a00"}}>
                  <div style={{width:8,height:8,borderRadius:4,background:"#f0b44c",flexShrink:0,opacity:0.5}}/>
                  <div style={{flex:1}}>
                    <div style={{color:"#f0b44c",fontSize:10}}>ΔI_magnetizing = V_in×D/(L_m×f_sw) = {fmt(dIm,1)} mA</div>
                    <div style={{color:"#664400",fontSize:8}}>Triangular ramp during on-time, returns through clamp diodes during reset.</div>
                    <div style={{color:"#886622",fontSize:9,marginTop:2}}>Minor contributor ({fmt(100-pctRect,0)}% of H1)</div>
                  </div>
                </div>
                {/* Net H1 amplitude */}
                <div style={{background:"#0a0600",border:"1px solid #221100",borderRadius:3,padding:"6px 8px",marginTop:4}}>
                  <div style={{color:"#443300",fontSize:7}}>FUNDAMENTAL (H1 at {fmt(fsw,0)} kHz)</div>
                  <div style={{color:"#f0b44c",fontSize:11,fontWeight:700}}>≈ {fmt(H1_total*1000,0)} mA → {fmt(20*Math.log10(H1_total*1e6),1)} dBµA unfiltered</div>
                </div>
              </div>;
            })()}
            {/* Standard operating point grid */}
            <div style={{background:topD_valid?"#0e0800":"#0e0808",border:`1px solid ${topD_valid?"#2a1a00":"#442222"}`,borderRadius:4,padding:"8px 10px",marginTop:6}}>
              <div style={{color:"#664400",fontSize:8,marginBottom:4}}>COMPUTED OPERATING POINT</div>
              <div style={{display:"grid",gridTemplateColumns:"1fr 1fr 1fr",gap:"4px 8px"}}>
                {[["D",`${fmt(topD,3)}${topD_valid?"":" (clamped)"}`,topD_valid?"#f0b44c":"#ff6666"],
                  topo.hasIso?["I_refl",`${fmt(NsNp*Iout,2)} A`,"#ff8844"]:["ΔI_pp",`${fmt(Ipp_eff,2)} mA`,"#f0b44c"],
                  ["P_in",`${fmt(Vin*Iout*Vout/(Vin*0.9),1)} W`,"#888"],
                  ["f₁",fmtF(fsw*1e3/(Math.PI*topD)),"#88aaff"],["f₂",fmtF(1/(Math.PI*tr*1e-9)),"#88aaff"],
                  topo.hasIso?["ΔI_m",`${fmt(Ipp_eff,1)} mA`,"#886622"]:["I_avg",`${fmt(Iavg_in,2)} A`,"#888"]
                ].map(([l,v,c])=>(
                  <div key={l}><div style={{color:"#2a1a00",fontSize:7}}>{l}</div><div style={{color:c,fontSize:10,fontWeight:700}}>{v}</div></div>
                ))}
              </div>
              <div style={{color:"#221100",fontSize:7,marginTop:4}}>f₁ = pulse width breakpoint (−20dB/dec onset) · f₂ = rise time breakpoint (−40dB/dec onset)</div>
            </div>
            </>}
            {/* Source label */}
            {useSpice&&spiceResult&&!spiceResult.error&&<div style={{background:"#120800",border:"1px solid #663300",borderRadius:4,padding:"6px 10px"}}>
              <div style={{color:"#ff8844",fontSize:9,fontWeight:700}}>Source: SPICE import — {spiceFileName}</div>
              <div style={{color:"#553300",fontSize:8}}>H1={fmt(spiceResult.harmonics[0]?.dBuA,1)} dBµA @ {fmtF(spiceResult.fswHz)} · {spiceResult.harmonics.length} harmonics</div>
            </div>}
          </Sec>

          <Sec title="EMI STANDARD & SOURCE" accent="#3a2a00">
            <div style={{marginBottom:8}}>
              <div style={{color:"#554400",fontSize:9,marginBottom:4}}>STANDARD</div>
              <select value={stdKey} onChange={e=>{setStdKey(e.target.value);if(e.target.value==='ce102'||e.target.value==='ce101')setEmiDet('pk');if(e.target.value==='cispr32')setEmiDet('avg')}} style={{...sel,borderColor:"#3a2a00"}}>
                <option value="cispr25v">CISPR 25 — Voltage (AN/LISN)</option>
                <option value="cispr25i">CISPR 25 — Current Probe</option>
                <option value="cispr32">CISPR 32 / EN 55032</option>
                <option value="ce102">MIL-STD-461G CE102</option>
                <option value="ce101">MIL-STD-461G CE101</option>
                <option value="custom">Custom (manual)</option>
              </select>
            </div>
            {/* Class selector — CISPR 25 */}
            {(stdKey==='cispr25v'||stdKey==='cispr25i')&&<div style={{marginBottom:8}}>
              <div style={{color:"#554400",fontSize:9,marginBottom:4}}>CLASS</div>
              <div style={{display:"flex",gap:3}}>
                {[5,4,3,2,1].map(c=>(
                  <div key={c} onClick={()=>setEmiCls(c)} style={{flex:1,textAlign:"center",padding:"4px 0",fontSize:10,fontWeight:700,cursor:"pointer",borderRadius:3,
                    background:emiCls===c?"#3a2a00":"#0d0d0d",border:`1px solid ${emiCls===c?"#f0b44c":"#1e1e1e"}`,color:emiCls===c?"#f0b44c":"#444"}}>{c}</div>
                ))}
              </div>
            </div>}
            {/* Class selector — CISPR 32 (A/B) */}
            {stdKey==='cispr32'&&<div style={{marginBottom:8}}>
              <div style={{color:"#554400",fontSize:9,marginBottom:4}}>CLASS</div>
              <div style={{display:"flex",gap:3}}>
                {[["B","B (Residential)"],["A","A (Industrial)"]].map(([k,lb])=>(
                  <div key={k} onClick={()=>setC32Cls(k)} style={{flex:1,textAlign:"center",padding:"4px 0",fontSize:9,fontWeight:700,cursor:"pointer",borderRadius:3,
                    background:c32Cls===k?"#3a2a00":"#0d0d0d",border:`1px solid ${c32Cls===k?"#f0b44c":"#1e1e1e"}`,color:c32Cls===k?"#f0b44c":"#444"}}>{lb}</div>
                ))}
              </div>
            </div>}
            {/* Detector selector — CISPR 25 + CISPR 32 */}
            {(stdKey==='cispr25v'||stdKey==='cispr25i'||stdKey==='cispr32')&&<div style={{marginBottom:8}}>
              <div style={{color:"#554400",fontSize:9,marginBottom:4}}>DETECTOR</div>
              <div style={{display:"flex",gap:3}}>
                {(stdKey==='cispr32'?[["avg","AVG"],["qp","QP"]]:[["avg","AVG"],["qp","QP"],["pk","PK"]]).map(([k,lb])=>(
                  <div key={k} onClick={()=>setEmiDet(k)} style={{flex:1,textAlign:"center",padding:"4px 0",fontSize:9,fontWeight:700,cursor:"pointer",borderRadius:3,
                    background:emiDet===k?"#3a2a00":"#0d0d0d",border:`1px solid ${emiDet===k?"#f0b44c":"#1e1e1e"}`,color:emiDet===k?"#f0b44c":"#444"}}>{lb}</div>
                ))}
              </div>
            </div>}
            {/* Voltage selector — CE102 only */}
            {stdKey==='ce102'&&<div style={{marginBottom:8}}>
              <div style={{color:"#554400",fontSize:9,marginBottom:4}}>NOMINAL VOLTAGE</div>
              <select value={emiVnom} onChange={e=>setEmiVnom(Number(e.target.value))} style={{...sel,borderColor:"#3a2a00"}}>
                {Object.keys(CE102_VADJ).map(v=><option key={v} value={v}>{v} V ({v<=28?'DC':v<=270&&v>28?(/220|270/.test(v)?'DC/AC':'AC'):'AC'})</option>)}
              </select>
            </div>}
            {/* Custom manual limit */}
            {stdKey==="custom"&&<IR lbl="Emission Limit" val={limMan} set={setLimMan} unit="dBµA" min={-20} max={100} step={1}/>}
            {/* Limit info display */}
            {stdKey!=="custom"&&limAtFsw!==null&&(
              <div style={{background:"#0e0a00",border:"1px solid #2a1a00",borderRadius:3,padding:"6px 9px",marginBottom:8}}>
                <div style={{display:"flex",gap:14,flexWrap:"wrap"}}>
                  <div><div style={{color:"#2a1a00",fontSize:8}}>BAND @ fsw</div><div style={{color:"#f0b44c",fontSize:10,fontWeight:700}}>{fswBand}</div></div>
                  <div><div style={{color:"#2a1a00",fontSize:8}}>LIMIT</div><div style={{color:"#f0b44c",fontSize:13,fontWeight:700}}>{fmt(lim,1)} <span style={{fontSize:8}}>dBµA</span></div></div>
                  <div><div style={{color:"#2a1a00",fontSize:8}}>UNIT</div><div style={{color:"#887744",fontSize:10}}>{stdKey.startsWith('cispr25v')?'dBµV→dBµA':stdKey==='ce102'?'dBµV→dBµA':'dBµA'}</div></div>
                </div>
              </div>
            )}
            {stdKey!=="custom"&&limAtFsw===null&&(
              <div style={{background:"#1a0808",border:"1px solid #662222",borderRadius:3,padding:"6px 9px",marginBottom:8,color:"#ff6666",fontSize:10}}>
                ⚠ fsw={fmtF(fsw*1e3)} falls in a gap between defined bands for {stdKey.toUpperCase()}
              </div>
            )}
            <IR lbl="LISN Impedance" val={Zs} set={setZs} unit="Ω" min={1} max={1000} step={1}/>
            <IR lbl="Design Margin" val={desMgn} set={setDesMgn} unit="dB" min={0} max={30} step={1}/>
            <div style={{background:"#0a0a0a",border:"1px solid #1a1a1a",borderRadius:3,padding:"5px 9px",marginBottom:7,color:"#333",fontSize:9}}>
              {useSpice&&spiceResult&&!spiceResult.error
                ?`Source: SPICE import (${spiceFileName}) · ${spiceResult.harmonics.length} harmonics · fsw=${fmtF(spiceResult.fswHz)}`
                :topo.hasIso?`Reflected load ${fmt(NsNp*Iout,2)}A pulsed at D=${fmt(topD,2)} + ΔI_m ${fmt(Ipp_eff,1)}mA — ${topo.name}`
                :`DM ripple ${fmt(Ipp_eff,2)} mA pk-pk — from ${topo.name}`}
            </div>
            <div style={{display:"flex",gap:10,marginTop:6,background:"#111",borderRadius:3,padding:"6px 9px",flexWrap:"wrap"}}>
              <div><div style={{color:"#2e2e2e",fontSize:9}}>SRC@fsw</div><div style={{color:"#aaa",fontSize:13,fontWeight:700}}>{fmt(srcAtFsw,1)} <span style={{fontSize:9,color:"#444"}}>dBµA</span></div></div>
              <div><div style={{color:"#2e2e2e",fontSize:9}}>MARGIN</div><div style={{color:"#cc88ff",fontSize:13,fontWeight:700}}>+{desMgn} <span style={{fontSize:9,color:"#444"}}>dB</span></div></div>
              <div><div style={{color:"#2e2e2e",fontSize:9}}>NEED</div><div style={{color:"#ff8844",fontSize:13,fontWeight:700}}>{fmt(need,1)} <span style={{fontSize:9,color:"#444"}}>dB</span></div></div>
            </div>
          </Sec>

          <Sec title="SRF — WINDING TECHNIQUES">
            <div style={{background:"#080e08",border:"1px solid #162016",borderRadius:3,padding:"6px 9px",marginBottom:8}}>
              <div style={{color:"#2a3a2a",fontSize:8,marginBottom:3}}>USING UNBIASED L = {fmt(Lunbias,0)} µH (v6 fix)</div>
              <div style={{color:"#33cc55",fontSize:14,fontWeight:700}}>{fmt(cwP.C_total_pF,1)} pF baseline</div>
              <div style={{color:"#2a2a2a",fontSize:8}}>SRF before techniques: {fmtF(1/(2*Math.PI*Math.sqrt(srfL*1e-6*cwP.C_total_pF*1e-12)))}</div>
            </div>
            <Tog lbl="Sectioned Winding"     fac="÷4.0" val={wS}  set={setWS}  detail="Two series sections"/>
            <Tog lbl="Progressive Bank Wind" fac="÷2.5" val={wP}  set={setWP}  detail="270° occupancy"/>
            <Tog lbl="Opposite Terminals"    fac="÷1.7" val={wO}  set={setWO}  detail="Pins on opposite sides"/>
            <Tog lbl="Multi-strand Wire"     fac="÷1.4" val={wF}  set={setWF}  detail="Reduced facing area"/>
            <Tog lbl="Spaced Winding"        fac="÷1.3" val={wSp} set={setWSp} detail="Air gap between turns"/>
            <div style={{background:"#0a120a",border:"1px solid #162416",borderRadius:4,padding:"8px 10px",marginTop:8,display:"grid",gridTemplateColumns:"1fr 1fr",gap:"5px 8px"}}>
              {[["Eff. Cw",`${fmt(CwEff_pF,1)} pF`,"#33cc55"],["SRF",fmtF(SRF),"#33cc55"],
                ["SRF/3",fmtF(SRFu),srfOk?"#33cc55":"#ff4444"],["@ fsw",srfOk?"INDUCTIVE ✓":"CAPACITIVE ✗",srfOk?"#33cc55":"#ff4444"]
              ].map(([l,v,c])=>(
                <div key={l}><div style={{color:"#2a2a2a",fontSize:8}}>{l}</div><div style={{color:c,fontSize:11,fontWeight:700}}>{v}</div></div>
              ))}
            </div>
          </Sec>

          <Sec title="2ND FILTER STAGE">
            <div style={{display:"flex",alignItems:"center",gap:8,marginBottom:10}}>
              <div onClick={()=>setSt2(!st2)} style={{background:st2?"#f0b44c":"#1a1a1a",border:"1px solid #2a2a2a",color:st2?"#000":"#555",fontSize:9,padding:"3px 10px",borderRadius:10,cursor:"pointer",letterSpacing:1.5,fontWeight:700}}>{st2?"ENABLED":"DISABLED"}</div>
            </div>
            {st2&&(<><IR lbl="L2" val={L2} set={setL2} unit="µH" min={1} max={10000} step={1}/><IR lbl="C2" val={C2} set={setC2} unit="nF" min={0.01} max={100000} step={1}/><IR lbl="ESR₂" val={capEsr2} set={setCapEsr2} unit="mΩ" min={0} max={10000} step={1}/><IR lbl="ESL₂" val={capEsl2} set={setCapEsl2} unit="nH" min={0} max={100} step={0.1}/>{lgFc2&&<div style={{color:"#555",fontSize:10,marginTop:3}}>fc₂: <span style={{color:"#f0b44c"}}>{fmtF(Math.pow(10,lgFc2))}</span></div>}</>)}
          </Sec>

          <Sec title="MIDDLEBROOK STABILITY" accent="#2a0033">
            <IR lbl="Bus voltage V_in" val={Vbus} set={setVbus} unit="V" min={1} max={1000} step={1}/>
            <IR lbl="Converter P_out" val={Pout} set={setPout} unit="W" min={1} max={50000} step={10}/>
            <IR lbl="Efficiency η" val={etaMB} set={setEtaMB} unit="" min={0.5} max={0.99} step={0.01}/>
            <div style={{display:"flex",alignItems:"center",gap:8,marginTop:8,marginBottom:6}}>
              <div onClick={()=>setUseDamping(!useDamping)} style={{background:useDamping?"#cc88ff":"#1a1a1a",border:"1px solid #2a2a2a",color:useDamping?"#000":"#555",fontSize:9,padding:"3px 10px",borderRadius:10,cursor:"pointer",letterSpacing:1.5,fontWeight:700}}>{useDamping?"DAMPING ON":"DAMPING OFF"}</div>
              <div style={{color:"#333",fontSize:9}}>Rd+Cd ∥ C</div>
            </div>
            <div style={{background:"#120022",border:`1px solid ${zoutPts.mbPass?"#334433":"#441133"}`,borderRadius:4,padding:"8px 10px",marginTop:6}}>
              <div style={{display:"grid",gridTemplateColumns:"1fr 1fr",gap:"5px 8px",marginBottom:8}}>
                {[["Z_in conv.",`${fmt(Zin_conv,2)} Ω`,"#aaa"],["Peak Z_out",`${fmt(zoutPts.peakZout,2)} Ω`,zoutPts.mbPass?"#33cc55":"#ff4444"],
                  ["Peak @ ",fmtF(zoutPts.peakF),zoutPts.mbPass?"#33cc55":"#ff4444"],["MB",zoutPts.mbPass?"PASS ✓":"FAIL ✗",zoutPts.mbPass?"#33cc55":"#ff4444"]
                ].map(([l,v,c])=>(
                  <div key={l}><div style={{color:"#221133",fontSize:8}}>{l}</div><div style={{color:c,fontSize:11,fontWeight:700}}>{v}</div></div>
                ))}
              </div>
              {/* Suggested values row */}
              <div style={{color:"#2a1a33",fontSize:8,marginBottom:4}}>SUGGESTED (R_d=Z₀, C_d=4×C)</div>
              <div style={{display:"flex",gap:14,marginBottom:8}}>
                <div><div style={{color:"#2a1a33",fontSize:8}}>R_d</div><div style={{color:"#cc88ff",fontSize:12,fontWeight:700}}>{fmt(Rd_rec,2)} Ω</div></div>
                <div><div style={{color:"#2a1a33",fontSize:8}}>C_d</div><div style={{color:"#cc88ff",fontSize:12,fontWeight:700}}>{fmt(Cd_rec_nF,0)} nF</div></div>
              </div>
              {/* EMI benefit of Middlebrook damping */}
              {(()=>{
                const fRes=fc1_Hz;
                const srcRes=20*Math.log10(Math.max(envAmplitude(fRes,topo,srcParams),1e-15)*1e6);
                const ilUnd=st2?calcIL2(fRes,Luh*1e-6,Cnf,L2*1e-6,C2,Zs,rL_ohm,rL_ohm*0.5,CwEff_pF,esrOhm1,capEsl,esrOhm2,capEsl2,mat,mu)
                  :calcIL1(fRes,Luh*1e-6,Cnf,Zs,rL_ohm,CwEff_pF,esrOhm1,capEsl,mat,mu);
                const ilDmp=st2?calcIL2_d(fRes,Luh*1e-6,Cnf,L2*1e-6,C2,Zs,rL_ohm,rL_ohm*0.5,CwEff_pF,esrOhm1,capEsl,esrOhm2,capEsl2,mat,mu,Rd_rec,Cd_rec_nF,0,0)
                  :calcIL1_d(fRes,Luh*1e-6,Cnf,Zs,rL_ohm,CwEff_pF,esrOhm1,capEsl,mat,mu,Rd_rec,Cd_rec_nF);
                const emUnd=srcRes-ilUnd, emDmp=srcRes-ilDmp;
                const limRes=evalLimit(fRes,stdKey,emiCls,emiDet,emiVnom,Zs,c32Cls);
                const delta=emUnd-emDmp;
                return <div style={{background:"#0a0811",border:"1px solid #2a1a33",borderRadius:3,padding:"6px 9px",marginBottom:6}}>
                  <div style={{color:"#8866aa",fontSize:8}}>EMI EFFECT AT LC₁ RESONANCE ({fmtF(fRes)})</div>
                  <div style={{color:"#cc88ff",fontSize:10,fontWeight:700}}>{delta>0.1?`Damping reduces emission by ${fmt(delta,1)} dB at fc₁`:`Minimal effect at fc₁ (${fmt(delta,1)} dB)`}</div>
                  <div style={{color:"#665588",fontSize:8,marginTop:2}}>Damping controls resonance Q, not asymptotic attenuation</div>
                  {limRes!==null&&<div style={{color:emDmp<limRes?"#33cc55":"#ff6666",fontSize:9,marginTop:2}}>
                    {emDmp<limRes?`✓ Resonance ${fmt(limRes-emDmp,1)} dB below limit`:`✗ Resonance ${fmt(emDmp-limRes,1)} dB above limit`}
                  </div>}
                </div>;
              })()}
              {/* Auto / Manual toggle */}
              {useDamping&&<>
                <div style={{display:"flex",gap:6,marginBottom:8}}>
                  {["AUTO","MANUAL"].map(m=>(
                    <div key={m} onClick={()=>setDampAuto(m==="AUTO")}
                      style={{flex:1,textAlign:"center",padding:"3px 0",fontSize:9,letterSpacing:1.5,fontWeight:700,cursor:"pointer",borderRadius:3,
                        background:((m==="AUTO")==dampAuto)?"#331144":"#0d0d0d",
                        border:`1px solid ${((m==="AUTO")==dampAuto)?"#cc88ff":"#222"}`,
                        color:((m==="AUTO")==dampAuto)?"#cc88ff":"#444"}}>
                      {m}
                    </div>
                  ))}
                </div>
                {!dampAuto&&<>
                  <div style={{marginBottom:6}}>
                    <div style={{color:"#444",fontSize:9,marginBottom:3}}>R_d (Ω) <span style={{color:"#332244"}}>— suggested {fmt(Rd_rec,2)} Ω</span></div>
                    <NI val={RdMan} set={setRdMan} unit="Ω" min={0.01} max={100000} step={0.1}
                      extraStyle={{marginBottom:0}}
                      inputStyle={{width:"100%",boxSizing:"border-box",border:"1px solid #442266",color:"#cc88ff",background:"#0a0a0a"}}/>
                  </div>
                  <div>
                    <div style={{color:"#444",fontSize:9,marginBottom:3}}>C_d (nF) <span style={{color:"#332244"}}>— suggested {fmt(Cd_rec_nF,0)} nF</span></div>
                    <NI val={CdMan} set={setCdMan} unit="nF" min={0.1} max={1000000} step={1}
                      extraStyle={{marginBottom:0}}
                      inputStyle={{width:"100%",boxSizing:"border-box",border:"1px solid #442266",color:"#cc88ff",background:"#0a0a0a"}}/>
                  </div>
                  <div style={{marginTop:6,color:"#332244",fontSize:8}}>
                    ACTIVE: R_d={fmt(Rd_act,2)}Ω · C_d={fmt(Cd_act_nF,0)}nF
                  </div>
                </>}
                {dampAuto&&<div style={{color:"#332244",fontSize:8}}>
                  ACTIVE: R_d={fmt(Rd_act,2)}Ω · C_d={fmt(Cd_act_nF,0)}nF
                </div>}
              </>}
            </div>
          </Sec>

          <Sec title="RESONANCE DIAGNOSTIC" accent="#882244">
            {/* Resonance table */}
            <div style={{background:"#0a0a0a",border:"1px solid #1a1a1a",borderRadius:4,padding:"8px 10px",marginBottom:8}}>
              <div style={{color:"#882244",fontSize:8,marginBottom:6}}>RESONANCE SCAN</div>
              {resonances.map((r,i)=>(
                <div key={i} style={{display:"flex",alignItems:"center",gap:6,padding:"4px 0",borderBottom:"1px solid #111",flexWrap:"wrap"}}>
                  <div style={{width:8,height:8,borderRadius:4,flexShrink:0,background:r.severity==="FAIL"?"#ff4444":r.severity==="WARN"?"#f0b44c":"#33cc55"}}/>
                  <div style={{flex:"1 1 60px",minWidth:50}}>
                    <div style={{color:"#aaa",fontSize:10,fontWeight:700}}>{r.type}</div>
                    <div style={{color:"#444",fontSize:8}}>{fmtF(r.f)}</div>
                  </div>
                  {r.Q!==null&&<div style={{flex:"0 0 50px"}}>
                    <div style={{color:"#333",fontSize:7}}>Q</div>
                    <div style={{color:r.Q>10?"#ff4444":r.Q>5?"#f0b44c":"#33cc55",fontSize:10,fontWeight:700}}>{fmt(r.Q,1)}</div>
                  </div>}
                  <div style={{flex:"0 0 60px"}}>
                    <div style={{color:"#333",fontSize:7}}>MARGIN{emiDamp?" (before)":""}</div>
                    <div style={{color:r.severity==="FAIL"?"#ff4444":r.severity==="WARN"?"#f0b44c":"#33cc55",fontSize:10,fontWeight:700,textDecoration:emiDamp&&r.marginD!==null?"line-through":"none",opacity:emiDamp&&r.marginD!==null?0.5:1}}>{r.margin!==null?`${r.margin>0?"+":""}${fmt(r.margin,1)} dB`:"—"}</div>
                  </div>
                  {emiDamp&&r.marginD!==null&&<div style={{flex:"0 0 60px"}}>
                    <div style={{color:"#552266",fontSize:7}}>DAMPED</div>
                    <div style={{color:r.severityD==="FAIL"?"#ff4444":r.severityD==="WARN"?"#f0b44c":"#33cc55",fontSize:10,fontWeight:700}}>{`${r.marginD>0?"+":""}${fmt(r.marginD,1)} dB`}</div>
                  </div>}
                </div>
              ))}
            </div>
            {/* Worst resonance callout */}
            {worstRes&&worstRes.severity!=="OK"&&<div style={{background:worstRes.severity==="FAIL"?"#1a0808":"#1a1200",border:`1px solid ${worstRes.severity==="FAIL"?"#662222":"#664400"}`,borderRadius:4,padding:"7px 10px",marginBottom:8,fontSize:9,color:worstRes.severity==="FAIL"?"#ff6666":"#f0b44c"}}>
              {worstRes.severity==="FAIL"?"✖":"⚠"} {worstRes.type} at {fmtF(worstRes.f)}{worstRes.Q?` (Q=${fmt(worstRes.Q,0)})`:""} — {worstRes.margin!==null?`${fmt(Math.abs(worstRes.margin),1)} dB ${worstRes.severity==="FAIL"?"over":"from"} limit`:""}
              {worstRes.Rd_sug&&<div style={{color:"#888",marginTop:3}}>Suggested: Rd={fmt(worstRes.Rd_sug,2)}Ω + Cd={fmt(worstRes.Cd_sug,0)}nF on stage {worstRes.stage}</div>}
            </div>}
            {/* EMI damping toggle */}
            <div style={{display:"flex",alignItems:"center",gap:8,marginBottom:8}}>
              <div onClick={()=>setEmiDamp(!emiDamp)} style={{background:emiDamp?"#cc88ff":"#1a1a1a",border:"1px solid #2a2a2a",color:emiDamp?"#000":"#555",fontSize:9,padding:"3px 10px",borderRadius:10,cursor:"pointer",letterSpacing:1.5,fontWeight:700}}>{emiDamp?"EMI DAMP ON":"EMI DAMP OFF"}</div>
              <div style={{color:"#333",fontSize:8}}>Rd+Cd ∥ C (separate from Middlebrook)</div>
            </div>
            {emiDamp&&<>
              {/* Auto / Manual */}
              <div style={{display:"flex",gap:6,marginBottom:8}}>
                {["AUTO","MANUAL"].map(m=>(
                  <div key={m} onClick={()=>setEmiDampAuto(m==="AUTO")}
                    style={{flex:1,textAlign:"center",padding:"3px 0",fontSize:9,letterSpacing:1.5,fontWeight:700,cursor:"pointer",borderRadius:3,
                      background:((m==="AUTO")===emiDampAuto)?"#331144":"#0d0d0d",
                      border:`1px solid ${((m==="AUTO")===emiDampAuto)?"#cc88ff":"#222"}`,
                      color:((m==="AUTO")===emiDampAuto)?"#cc88ff":"#444"}}>
                    {m}
                  </div>
                ))}
              </div>
              {/* Stage selector (2-stage only) */}
              {st2&&!emiDampAuto&&<div style={{marginBottom:8}}>
                <div style={{color:"#444",fontSize:8,marginBottom:3}}>DAMP ON STAGE</div>
                <div style={{display:"flex",gap:4}}>
                  {[1,2].map(s=>(
                    <div key={s} onClick={()=>setEmiDampStage(s)} style={{flex:1,textAlign:"center",padding:"3px 0",fontSize:10,fontWeight:700,cursor:"pointer",borderRadius:3,
                      background:emiDampStage===s?"#331144":"#0d0d0d",border:`1px solid ${emiDampStage===s?"#cc88ff":"#222"}`,color:emiDampStage===s?"#cc88ff":"#444"}}>Stage {s}</div>
                  ))}
                </div>
              </div>}
              {/* Manual Rd/Cd inputs */}
              {!emiDampAuto&&<>
                <IR lbl="Rd (Ω)" val={emiRd} set={setEmiRd} unit="Ω" min={0.01} max={100000} step={0.1}/>
                <IR lbl="Cd (nF)" val={emiCd} set={setEmiCd} unit="nF" min={0.1} max={1000000} step={1}/>
              </>}
              {/* Active values display */}
              <div style={{background:"#120022",border:"1px solid #331144",borderRadius:4,padding:"7px 10px",marginTop:4}}>
                <div style={{color:"#221133",fontSize:8,marginBottom:3}}>ACTIVE EMI DAMPING{emiDampAuto?" (AUTO)":""}</div>
                <div style={{display:"flex",gap:14}}>
                  <div><div style={{color:"#221133",fontSize:8}}>Rd</div><div style={{color:"#cc88ff",fontSize:12,fontWeight:700}}>{fmt(emiRd_act,2)} Ω</div></div>
                  <div><div style={{color:"#221133",fontSize:8}}>Cd</div><div style={{color:"#cc88ff",fontSize:12,fontWeight:700}}>{fmt(emiCd_act,0)} nF</div></div>
                  <div><div style={{color:"#221133",fontSize:8}}>Stage</div><div style={{color:"#cc88ff",fontSize:12,fontWeight:700}}>{emiDampStg}</div></div>
                </div>
                {useDamping&&emiDampStg===1&&<div style={{color:"#442233",fontSize:8,marginTop:4}}>Note: Middlebrook damping also on stage 1 — both networks in parallel with C₁</div>}
              </div>
            </>}
          </Sec>

        </div>{/* end left column */}

        {/* ── RIGHT COLUMN ── */}
        <div style={{flex:"1 1 380px",minWidth:0}}>

          {/* Status banner */}
          <div style={{background:pass?"#0a1a0a":"#1a0a0a",border:`1px solid ${pass?"#226622":"#662222"}`,borderRadius:5,padding:"8px 14px",marginBottom:10,display:"flex",alignItems:"center",justifyContent:"space-between",flexWrap:"wrap",gap:8}}>
            <div style={{fontSize:18,fontWeight:700,letterSpacing:2,color:pass?"#33cc55":"#ff4444"}}>{pass?"▶ PASS":"✖ FAIL"}</div>
            <div style={{color:"#555",fontSize:10}}>MARGIN: <span style={{color:pass?"#33cc55":"#ff4444",fontWeight:700}}>{worstHarmonic.margin>=0?"+":""}{fmt(worstHarmonic.margin,1)} dB</span>&nbsp;&nbsp;@ {fmtF(worstHarmonic.f)} (H{worstHarmonic.n})&nbsp;&nbsp;{stdKey==="custom"?"Custom":stdKey==="cispr25v"?`CISPR25-V Cl${emiCls} ${emiDet.toUpperCase()}`:stdKey==="cispr25i"?`CISPR25-I Cl${emiCls} ${emiDet.toUpperCase()}`:stdKey==="cispr32"?`CISPR32 Cl${c32Cls} ${emiDet.toUpperCase()}`:stdKey.toUpperCase()}</div>
          </div>

          {/* Warnings */}
          {satW&&<W msg={`SATURATION: B_dc=${fmt(Bdc*1000,0)}mT = ${fmt(satPct,1)}% of Bsat`}/>}
          {!srfOk&&<W msg={`CHOKE CAPACITIVE @ fsw — SRF/3=${fmtF(SRFu)}, need SRF > ${fmtF(fsw*3e3)} (L_ref=${fmt(srfL,0)}µH ${srfLmode})`}/>}
          {!pass&&<div style={{background:"#150e04",border:"1px solid #774422",borderRadius:4,padding:"7px 12px",marginBottom:8,color:"#ff9955",fontSize:10}}>⚠ WORST HARMONIC H{worstHarmonic.n} ({fmtF(worstHarmonic.f)}) — {fmt(Math.abs(worstHarmonic.margin),1)} dB over limit {desMgn>0?`(incl. ${desMgn}dB margin)`:""}</div>}
          {/* LC sizing advisor when failing */}
          {/* LC SIZING ADVISOR — numerical solver for target values */}
          {!pass&&worstHarmonic.margin<0&&(()=>{
            const shortfall=Math.abs(worstHarmonic.margin);
            // Numerical solver: find minimum C (or L) multiplier that passes ALL harmonics
            const checkPass=(cMult1,cMult2,lMult1,lMult2)=>{
              const tC1=Cnf*cMult1, tC2_=C2*cMult2;
              const tL1=Luh*1e-6*lMult1, tL2_=L2*1e-6*lMult2;
              let worstM=Infinity;
              for(const h of harmonics){
                if(h.f>10e6)continue;
                const limH=evalLimit(h.f,stdKey,emiCls,emiDet,emiVnom,Zs,c32Cls);
                if(limH===null)continue;
                let ilH;
                const mbR=useDamping?Rd_act:0,mbC=useDamping?Cd_act_nF:0;
                if(st2)ilH=calcIL2_d(h.f,tL1,tC1,tL2_,tC2_,Zs,rL_ohm,rL_ohm*0.5,CwEff_pF,esrOhm1,capEsl,esrOhm2,capEsl2,mat,mu,mbR,mbC,0,0);
                else ilH=mbR>0?calcIL1_d(h.f,tL1,tC1,Zs,rL_ohm,CwEff_pF,esrOhm1,capEsl,mat,mu,mbR,mbC)
                  :calcIL1(h.f,tL1,tC1,Zs,rL_ohm,CwEff_pF,esrOhm1,capEsl,mat,mu);
                const m=limH-(h.dBuA-ilH)-desMgn;
                if(m<worstM)worstM=m;
              }
              return worstM;
            };
            // Binary search: find minimum multiplier for C-only, L-only, and balanced
            const solve=(fn)=>{let lo=1,hi=100;for(let i=0;i<30;i++){const m=(lo+hi)/2;if(fn(m)>=0)hi=m;else lo=m;}return hi;};
            const cMult=solve(m=>checkPass(m,st2?m:1,1,1));
            const lMult=solve(m=>checkPass(1,1,m,st2?m:1));
            const bMult=solve(m=>checkPass(Math.sqrt(m),st2?Math.sqrt(m):1,Math.sqrt(m),st2?Math.sqrt(m):1));
            // Round to practical values
            const roundC=v=>v<100?Math.ceil(v/10)*10:v<1000?Math.ceil(v/10)*10:v<10000?Math.ceil(v/100)*100:Math.ceil(v/1000)*1000;
            const roundL=v=>v<10?Math.ceil(v):v<100?Math.ceil(v/5)*5:Math.ceil(v/10)*10;
            const C1c=roundC(Cnf*cMult), C2c=st2?roundC(C2*cMult):null;
            const L1l=roundL(Luh*lMult), L2l=st2?roundL(L2*lMult):null;
            const C1b=roundC(Cnf*Math.sqrt(bMult)), L1b=roundL(Luh*Math.sqrt(bMult));
            const C2b=st2?roundC(C2*Math.sqrt(bMult)):null, L2b=st2?roundL(L2*Math.sqrt(bMult)):null;

            return <div style={{background:"#0e0804",border:"1px solid #553311",borderRadius:4,padding:"10px 12px",marginBottom:8}}>
              <div style={{color:"#ff8844",fontSize:9,letterSpacing:1.5,marginBottom:6}}>LC SIZING ADVISOR — need {fmt(shortfall,1)} dB more to pass all harmonics</div>
              <div style={{color:"#885522",fontSize:8,marginBottom:8}}>
                Damping controls resonance Q but cannot increase asymptotic rolloff. These target values are computed to pass every harmonic with {desMgn} dB margin.
              </div>
              <div style={{display:"grid",gridTemplateColumns:"1fr 1fr 1fr",gap:6}}>
                {/* Option A: C only */}
                <div style={{background:"#0a0600",border:"1px solid #332200",borderRadius:3,padding:"7px 8px"}}>
                  <div style={{color:"#664400",fontSize:7,marginBottom:4,letterSpacing:1}}>INCREASE C</div>
                  <div style={{color:"#f0b44c",fontSize:10,fontWeight:700}}>C₁→{C1c} nF</div>
                  {st2&&<div style={{color:"#f0b44c",fontSize:10,fontWeight:700}}>C₂→{C2c} nF</div>}
                  <div style={{color:"#443300",fontSize:7,marginTop:3}}>L unchanged</div>
                </div>
                {/* Option B: L only */}
                <div style={{background:"#0a0600",border:"1px solid #332200",borderRadius:3,padding:"7px 8px"}}>
                  <div style={{color:"#664400",fontSize:7,marginBottom:4,letterSpacing:1}}>INCREASE L</div>
                  <div style={{color:"#f0b44c",fontSize:10,fontWeight:700}}>L₁→{L1l} µH</div>
                  {st2&&<div style={{color:"#f0b44c",fontSize:10,fontWeight:700}}>L₂→{L2l} µH</div>}
                  <div style={{color:"#443300",fontSize:7,marginTop:3}}>C unchanged</div>
                </div>
                {/* Option C: Balanced */}
                <div style={{background:"#0a0600",border:"1px solid #332200",borderRadius:3,padding:"7px 8px"}}>
                  <div style={{color:"#664400",fontSize:7,marginBottom:4,letterSpacing:1}}>BALANCED</div>
                  <div style={{color:"#f0b44c",fontSize:10,fontWeight:700}}>C₁→{C1b} nF</div>
                  <div style={{color:"#f0b44c",fontSize:10,fontWeight:700}}>L₁→{L1b} µH</div>
                  {st2&&<div style={{color:"#f0b44c",fontSize:9}}>C₂→{C2b} L₂→{L2b}</div>}
                  <div style={{color:"#443300",fontSize:7,marginTop:3}}>√ split</div>
                </div>
              </div>
              <div style={{color:"#332200",fontSize:7,marginTop:6,lineHeight:1.5}}>
                Target values computed numerically against all harmonics. Parasitic limits (SRF, ESL) may require different ratios. C is cheaper/smaller than L. Tip: try entering these values above — if the advisor disappears, you pass.
              </div>
            </div>;
          })()}
          {cwP.fillPct>50&&<W msg={`WINDOW OVERFULL: ${fmt(cwP.fillPct,0)}% — ${N} turns of ${awg}AWG won't fit in ID=${ID}mm hole`}/>}
          {cwP.fillPct>35&&cwP.fillPct<=50&&<div style={{background:"#1a1200",border:"1px solid #664400",borderRadius:4,padding:"7px 12px",marginBottom:8,color:"#f0b44c",fontSize:10}}>⚠ TIGHT FIT: {fmt(cwP.fillPct,0)}% window utilization — verify physically</div>}
          {!zoutPts.mbPass&&<div style={{background:"#100015",border:"1px solid #441155",borderRadius:4,padding:"7px 12px",marginBottom:8,color:"#cc88ff",fontSize:10}}>⚠ MIDDLEBROOK FAIL: Peak Z_out={fmt(zoutPts.peakZout,2)}Ω &gt; Z_in={fmt(Zin_conv,2)}Ω at {fmtF(zoutPts.peakF)} — enable damping: R_d={fmt(Rd_rec,2)}Ω + C_d={fmt(Cd_rec_nF,0)}nF</div>}
          {zoutPts.mbPass&&<W msg={`MIDDLEBROOK OK — Peak Z_out=${fmt(zoutPts.peakZout,2)}Ω < Z_in=${fmt(Zin_conv,2)}Ω`} col="#33cc55"/>}

          {/* Metric cards */}
          <div style={{display:"grid",gridTemplateColumns:"repeat(auto-fit,minmax(100px,1fr))",gap:7,marginBottom:12}}>
            <MC lbl="L biased" val={`${fmt(Lbias,0)} µH`} status={pMu>0.6?"pass":"warn"}/>
            <MC lbl="%µ @ Idc" val={`${fmt(pMu*100,0)}%`} status={pMu>0.7?"pass":pMu>0.4?"warn":"fail"}/>
            <MC lbl="LC Corner" val={fmtF(fc1)}/>
            <MC lbl={`SRF (${srfLmode==="unbias"?"unbias":srfLmode==="bias"?"biased":"manual"})`} val={fmtF(SRF)} status={srfOk?"pass":"fail"}/>
            <MC lbl="Attenuation" val={`${fmt(ach,0)} dB`} status={pass?"pass":"fail"}/>
            <MC lbl="Window Fill" val={`${fmt(cwP.fillPct,0)}%`} status={cwP.fillPct>50?"fail":cwP.fillPct>35?"warn":"pass"}/>
            <MC lbl="Core Loss" val={`${fmt(Ptot,0)} mW`} status={Ptot<200?"pass":Ptot<500?"warn":"fail"}/>
            <MC lbl="FR Dowell" val={`${fmt(cu.FR,2)}×`} status={cu.FR<2?"pass":cu.FR<5?"warn":"fail"}/>
            <MC lbl="Middlebrook" val={zoutPts.mbPass?"PASS":"FAIL"} status={zoutPts.mbPass?"pass":"fail"}/>
            <MC lbl="Peak Z_out" val={`${fmt(zoutPts.peakZout,2)} Ω`} status={zoutPts.mbPass?"pass":"fail"}/>
            <MC lbl="B_dc" val={`${fmt(Bdc*1000,0)} mT`} status={satW?"fail":"pass"}/>
            <MC lbl={`Margin H${worstHarmonic.n}`} val={`${worstHarmonic.margin>=0?"+":""}${fmt(worstHarmonic.margin,1)} dB`} status={pass?"pass":"fail"}/>
          </div>

          {/* Chart 1: Attenuation */}
          <div style={{background:"#0c0c0c",border:`1px solid ${pass?"#1a2a1a":"#3a1a00"}`,borderRadius:5,padding:"11px 8px 6px",marginBottom:10}}>
            <div style={{color:"#f0b44c",fontSize:9,letterSpacing:2.5,marginLeft:4,marginBottom:6}}>INSERTION LOSS vs FREQUENCY (full complex model){st2&&<span style={{color:"#33cc55",marginLeft:8}}>· 2-STAGE</span>}{emiDamp&&<span style={{color:"#cc88ff",marginLeft:8}}>· EMI DAMPED</span>}</div>
            <ResponsiveContainer width="100%" height={200}>
              <LineChart data={specPtsFinal} margin={{top:4,right:18,bottom:22,left:4}}>
                <CartesianGrid strokeDasharray="2 5" stroke="#141414"/>
                <XAxis dataKey="logf" type="number" domain={[3,7]} ticks={[3,3.5,4,4.5,5,5.5,6,6.5,7]} tickFormatter={xfmt} tick={{fill:"#444",fontSize:9}} label={{value:"Frequency",position:"insideBottom",offset:-12,fill:"#333",fontSize:9}}/>
                <YAxis domain={[0,120]} tick={{fill:"#444",fontSize:9}} label={{value:"IL (dB)",angle:-90,position:"insideLeft",offset:14,fill:"#333",fontSize:9}}/>
                <Tooltip content={<Tip/>}/>
                <ReferenceArea y1={0} y2={need>0?need:0} fill="#ff4444" fillOpacity={0.06}/>
                <ReferenceArea y1={need>0?need:0} y2={120} fill="#33cc55" fillOpacity={0.06}/>
                <ReferenceArea x1={3} x2={lgSRFu} fill="#4488ff" fillOpacity={0.04}/>
                {stdKey==='custom'&&<ReferenceLine y={need} stroke="#ff4444" strokeDasharray="5 3" label={{value:`REQ ${fmt(need,0)}dB`,position:"right",fill:"#ff4444",fontSize:8}}/>}
                <ReferenceLine x={lgFc1} stroke="#f0b44c" strokeDasharray="3 4" label={{value:"fc₁",position:"insideTopRight",fill:"#f0b44c",fontSize:8}}/>
                {st2&&lgFc2&&<ReferenceLine x={lgFc2} stroke="#88aaff" strokeDasharray="3 4" label={{value:"fc₂",position:"insideTopRight",fill:"#88aaff",fontSize:8}}/>}
                <ReferenceLine x={lgFsw} stroke="#4488ff" strokeDasharray="3 3" label={{value:"fsw",position:"insideTopLeft",fill:"#4488ff",fontSize:8}}/>
                <ReferenceLine x={lgSRFu} stroke="#33cc55" strokeDasharray="2 5" label={{value:"SRF/3",position:"insideTopRight",fill:"#33cc55",fontSize:8}}/>
                {/* Harmonic markers */}
                {[2,3,5].map(h=>{const lh=Math.log10(fsw*1e3*h);return lh<=7?<ReferenceLine key={h} x={lh} stroke="#665522" strokeDasharray="1 4" strokeOpacity={0.6} label={{value:`${h}×`,position:"insideBottomRight",fill:"#554411",fontSize:7}}/>:null})}
                {/* Required attenuation curve from limit standard */}
                {stdKey!=='custom'&&<Line type="stepAfter" dataKey="needA" stroke="#ff4444" dot={false} strokeWidth={1.5} strokeDasharray="4 2" name="Required (dB)" connectNulls={false}/>}
                {/* Active IL — a2 is primary when 2-stage on, a1 otherwise */}
                {st2&&<Line type="monotone" dataKey="a2" stroke="#33cc55" dot={false} strokeWidth={2} name="IL 2-stage (dB)"/>}
                {!st2&&<Line type="monotone" dataKey="a1" stroke="#f0b44c" dot={false} strokeWidth={2} name="IL 1-stage (dB)"/>}
                {st2&&<Line type="monotone" dataKey="a1" stroke="#f0b44c" dot={false} strokeWidth={1} strokeDasharray="3 3" strokeOpacity={0.4} name="IL 1-stage (ref)"/>}
                {/* Undamped "before" trace when EMI damping is active */}
                {emiDamp&&<Line type="monotone" dataKey="a1_before" stroke="#ff6666" dot={false} strokeWidth={1} strokeDasharray="2 3" strokeOpacity={0.5} name="Before (undamped)"/>}
              </LineChart>
            </ResponsiveContainer>
          </div>

          {/* Chart 1b: EMISSION SPECTRUM — Test Perspective */}
          {stdKey!=='custom'&&<div style={{background:"#0c0c0c",border:"1px solid #3a2a00",borderRadius:5,padding:"11px 8px 6px",marginBottom:10}}>
            <div style={{color:"#ff8844",fontSize:9,letterSpacing:2.5,marginLeft:4,marginBottom:2}}>
              EMISSION SPECTRUM — TEST PERSPECTIVE
              <span style={{color:"#554400",marginLeft:8}}>· {srcLabel} · {stdKey==='cispr25v'?`CISPR25-V Cl${emiCls}`:stdKey==='cispr25i'?`CISPR25-I Cl${emiCls}`:stdKey==='cispr32'?`CISPR32 Cl${c32Cls}`:stdKey.toUpperCase()} {emiDet.toUpperCase()}</span>
            </div>
            <div style={{color:"#333",fontSize:8,marginLeft:4,marginBottom:6}}>
              Dots = actual harmonic emissions (green=pass, red=fail) · Dim line = spectral envelope (no energy between harmonics) · Pass/fail is per-harmonic only
            </div>
            <ResponsiveContainer width="100%" height={240}>
              <LineChart data={chartData} margin={{top:4,right:18,bottom:22,left:4}}>
                <CartesianGrid strokeDasharray="2 5" stroke="#141414"/>
                <XAxis dataKey="logf" type="number" domain={[3,7]} ticks={[3,3.5,4,4.5,5,5.5,6,6.5,7]} tickFormatter={xfmt} tick={{fill:"#444",fontSize:9}} label={{value:"Frequency",position:"insideBottom",offset:-12,fill:"#333",fontSize:9}}/>
                <YAxis domain={[-20,140]} ticks={[-20,0,20,40,60,80,100,120,140]} tick={{fill:"#444",fontSize:9}} label={{value:"dBµA",angle:-90,position:"insideLeft",offset:14,fill:"#333",fontSize:9}}/>
                <Tooltip content={({active,payload,label})=>{
                  if(!active||!payload?.length)return null;
                  const hData=payload.find(p=>p.dataKey==="harmEm"&&p.value!==null&&p.value!==undefined);
                  return(<div style={{background:"#111",border:"1px solid #2a2a2a",padding:"6px 10px",fontSize:11,borderRadius:3}}>
                    <div style={{color:"#f0b44c",marginBottom:3}}>{fmtF(Math.pow(10,label))}</div>
                    {hData&&<div style={{color:hData.payload.harmPass?"#33ff55":"#ff4444",fontWeight:700}}>H{hData.payload.harmN}: {fmt(hData.value,1)} dBµA {hData.payload.harmPass?"✓":"✗"}</div>}
                    {payload.map((p,i)=>p.value!==null&&p.value!==undefined&&p.dataKey!=="harmEm"?<div key={i} style={{color:p.color,opacity:0.7}}>{p.name}: {fmt(p.value,1)} dBµA</div>:null)}
                  </div>)
                }}/>
                {/* Source envelope is now a proper line trace (srcEnv), no flat reference needed */}
                <ReferenceLine x={lgFsw} stroke="#4488ff" strokeDasharray="3 3" label={{value:"fsw",position:"insideTopLeft",fill:"#4488ff",fontSize:8}}/>
                {/* Harmonic markers — show harmonics within 20dB of limit */}
                {harmonics.filter(h=>h.f<=10e6).map(h=>{
                  const lh=Math.log10(h.f);
                  if(lh<3||lh>7)return null;
                  return <ReferenceLine key={h.n} x={lh} stroke={h.n<=5?"#886622":"#332211"} strokeDasharray="1 4" strokeOpacity={h.n<=3?0.7:0.3}/>;
                })}
                {/* Source envelope (unflitered) */}
                <Line type="monotone" dataKey="srcEnv" stroke="#ff8844" dot={false} strokeWidth={1} strokeDasharray="2 4" strokeOpacity={0.4} name="Source envelope (dBµA)"/>
                {/* Standard limit line */}
                <Line type="stepAfter" dataKey="limA" stroke="#ff4444" dot={false} strokeWidth={2} strokeDasharray="6 3" name="Limit" connectNulls={false}/>
                {/* Continuous emission envelope (dimmed — this is NOT where energy exists) */}
                <Line type="monotone" dataKey="emPk" stroke="#33cc55" dot={false} strokeWidth={1} strokeOpacity={0.3} name="Envelope (PK)" connectNulls={false}/>
                <Line type="monotone" dataKey="emQP" stroke="#44dddd" dot={false} strokeWidth={1} strokeDasharray="5 2" strokeOpacity={0.2} name="Envelope (QP)" connectNulls={false}/>
                <Line type="monotone" dataKey="emAvg" stroke="#f0b44c" dot={false} strokeWidth={1} strokeDasharray="3 3" strokeOpacity={0.2} name="Envelope (AVG)" connectNulls={false}/>
                {/* Harmonic dots — actual discrete emissions (THIS is what the receiver sees) */}
                <Line type="monotone" dataKey="harmEm" stroke="#33ff55" strokeWidth={0} connectNulls={false} name="Harmonics"
                  dot={({cx,cy,payload})=>{
                    if(payload.harmEm===null||payload.harmEm===undefined||!cx||!cy)return null;
                    const col=payload.harmPass?"#33ff55":"#ff4444";
                    return <g key={payload.harmN}>
                      <circle cx={cx} cy={cy} r={4} fill={col} stroke="#000" strokeWidth={0.5} opacity={0.9}/>
                      {payload.harmN<=8&&<text x={cx} y={cy-7} fill={col} fontSize={7} textAnchor="middle">H{payload.harmN}</text>}
                    </g>;
                  }}/>
                {/* Undamped "before" trace when damping is active */}
                {emiDamp&&<Line type="monotone" dataKey="emBefore" stroke="#ff6666" dot={false} strokeWidth={1} strokeDasharray="2 3" strokeOpacity={0.5} name="Before (undamped PK)" connectNulls={false}/>}
              </LineChart>
            </ResponsiveContainer>
            {/* Legend */}
            <div style={{display:"flex",gap:10,padding:"4px 8px 2px",flexWrap:"wrap"}}>
              <div style={{display:"flex",alignItems:"center",gap:4}}><div style={{width:8,height:8,borderRadius:4,background:"#33ff55"}}/><span style={{color:"#555",fontSize:8}}>Harmonic (pass)</span></div>
              <div style={{display:"flex",alignItems:"center",gap:4}}><div style={{width:8,height:8,borderRadius:4,background:"#ff4444"}}/><span style={{color:"#555",fontSize:8}}>Harmonic (fail)</span></div>
              <div style={{display:"flex",alignItems:"center",gap:4}}><div style={{width:16,height:1,background:"#33cc55",opacity:0.3}}/><span style={{color:"#444",fontSize:8}}>Envelope</span></div>
              <div style={{display:"flex",alignItems:"center",gap:4}}><div style={{width:16,height:1,background:"#ff8844",opacity:0.4}}/><span style={{color:"#444",fontSize:8}}>Source</span></div>
              <div style={{display:"flex",alignItems:"center",gap:4}}><div style={{width:16,height:2,background:"#ff4444",borderTop:"1px dashed #ff4444"}}/><span style={{color:"#444",fontSize:8}}>Limit ({emiDet.toUpperCase()})</span></div>
              {emiDamp&&<div style={{display:"flex",alignItems:"center",gap:4}}><div style={{width:16,height:1,background:"#ff6666",opacity:0.5}}/><span style={{color:"#444",fontSize:8}}>Before (undamped)</span></div>}
            </div>
            <div style={{color:"#2a2200",fontSize:7,padding:"2px 8px",lineHeight:1.5}}>
              {useSpice&&spiceResult&&!spiceResult.error
                ?`Source: SPICE import (${spiceFileName}), ${spiceResult.harmonics.length} harmonics extracted via FFT. Dots show filtered emission at each harmonic — only these matter for pass/fail.`
                :`${topo.name}: D=${fmt(topD,3)}, f₁=${fmtF(fsw*1e3/(Math.PI*topD))}, f₂=${fmtF(1/(Math.PI*tr*1e-9))}. Dots show filtered emission at each n×fsw — only these matter for pass/fail. The dim envelope between dots shows the spectral shape but contains no actual energy.`}
            </div>
          </div>}

          {/* Chart 2: Z_out(f) — MIDDLEBROOK */}
          <div style={{background:"#0c0c0c",border:`1px solid ${zoutPts.mbPass?"#162416":"#2a1133"}`,borderRadius:5,padding:"11px 8px 6px",marginBottom:10}}>
            <div style={{color:"#cc88ff",fontSize:9,letterSpacing:2.5,marginLeft:4,marginBottom:2}}>
              FILTER OUTPUT IMPEDANCE Z_out(f) — MIDDLEBROOK CRITERION
              {st2&&<span style={{color:"#f0b44c",marginLeft:8}}>· 1-STAGE vs 2-STAGE</span>}
            </div>
            <div style={{color:"#333",fontSize:8,marginLeft:4,marginBottom:6}}>
              Criterion: |Z_out(f)| &lt; Z_in_converter at all frequencies · Peak at LC resonance is the danger point
              {st2&&" · Note: 2nd stage adds a 2nd resonance peak"}
            </div>
            <ResponsiveContainer width="100%" height={st2?230:210}>
              <LineChart data={zoutPts.pts} margin={{top:4,right:18,bottom:22,left:4}}>
                <CartesianGrid strokeDasharray="2 5" stroke="#141414"/>
                <XAxis dataKey="logf" type="number" domain={[2,7]} ticks={[2,2.5,3,3.5,4,4.5,5,5.5,6,6.5,7]} tickFormatter={xfmt} tick={{fill:"#444",fontSize:9}} label={{value:"Frequency",position:"insideBottom",offset:-12,fill:"#333",fontSize:9}}/>
                <YAxis domain={[-40,80]} allowDataOverflow={true} tick={{fill:"#444",fontSize:9}} label={{value:"|Z| (dBΩ)",angle:-90,position:"insideLeft",offset:14,fill:"#333",fontSize:9}}/>
                <Tooltip content={<ZTip/>}/>
                <ReferenceArea y1={Zin_dBOhm} y2={80} fill="#ff4444" fillOpacity={0.07}/>
                <ReferenceArea y1={-40} y2={Zin_dBOhm} fill="#33cc55" fillOpacity={0.04}/>
                <ReferenceLine y={Zin_dBOhm} stroke="#cc88ff" strokeWidth={2} strokeDasharray="6 3"
                  label={{value:`Z_in = ${fmt(Zin_conv,1)}Ω`,position:"insideTopRight",fill:"#cc88ff",fontSize:9}}/>
                <ReferenceLine x={lgPeakF} stroke="#ff4444" strokeDasharray="2 4" strokeOpacity={0.5}
                  label={{value:`peak @ ${fmtF(zoutPts.peakF)}`,position:"insideTopLeft",fill:"#ff4444",fontSize:8}}/>
                <ReferenceLine x={lgFsw} stroke="#4488ff" strokeDasharray="3 3"
                  label={{value:"fsw",position:"insideBottomLeft",fill:"#4488ff",fontSize:8}}/>
                {/* Single-stage curves — always shown */}
                <Line type="monotone" dataKey="Z1_und" stroke={st2?"#446688":"#88aaff"} dot={false} strokeWidth={st2?1.5:2.5}
                  strokeDasharray={st2?"4 2":undefined} name={st2?"1-stage undamped":"Z_out undamped"} opacity={st2?0.7:1}/>
                {useDamping&&<Line type="monotone" dataKey="Z1_dmp" stroke={st2?"#336633":"#33cc55"} dot={false} strokeWidth={st2?1.5:2}
                  strokeDasharray={st2?"4 2":"5 2"} name={st2?"1-stage damped":"Z_out damped"} opacity={st2?0.7:1}/>}
                {/* Two-stage curves — only when st2 enabled */}
                {st2&&<Line type="monotone" dataKey="Z2_und" stroke="#ff8844" dot={false} strokeWidth={2.5}
                  name="2-stage undamped"/>}
                {st2&&useDamping&&<Line type="monotone" dataKey="Z2_dmp" stroke="#33cc55" dot={false} strokeWidth={2}
                  strokeDasharray="5 2" name="2-stage damped"/>}
              </LineChart>
            </ResponsiveContainer>
            {/* Legend */}
            <div style={{display:"flex",gap:12,padding:"6px 8px 2px",flexWrap:"wrap"}}>
              <div style={{display:"flex",alignItems:"center",gap:5}}>
                <div style={{width:20,height:2,background:st2?"#446688":"#88aaff"}}/>
                <span style={{color:"#444",fontSize:9}}>{st2?"1-stage":"Z_out"} undamped</span>
              </div>
              {useDamping&&<div style={{display:"flex",alignItems:"center",gap:5}}>
                <div style={{width:20,height:2,background:st2?"#336633":"#33cc55"}}/>
                <span style={{color:"#444",fontSize:9}}>{st2?"1-stage":"Z_out"} damped (R_d={fmt(Rd_act,1)}Ω · C_d={fmt(Cd_act_nF,0)}nF{!dampAuto?" ✎":""})</span>
              </div>}
              {st2&&<div style={{display:"flex",alignItems:"center",gap:5}}>
                <div style={{width:20,height:2,background:"#ff8844"}}/>
                <span style={{color:"#f0b44c",fontSize:9,fontWeight:700}}>2-stage undamped</span>
              </div>}
              {st2&&useDamping&&<div style={{display:"flex",alignItems:"center",gap:5}}>
                <div style={{width:20,height:2,background:"#33cc55"}}/>
                <span style={{color:"#33cc55",fontSize:9,fontWeight:700}}>2-stage damped</span>
              </div>}
              <div style={{display:"flex",alignItems:"center",gap:5}}>
                <div style={{width:20,height:2,background:"#cc88ff"}}/>
                <span style={{color:"#444",fontSize:9}}>Z_in = {fmt(Zin_conv,1)}Ω</span>
              </div>
            </div>
          </div>

          {/* Chart 3: Choke |Z| */}
          <div style={{background:"#0c0c0c",border:"1px solid #1a1a1a",borderRadius:5,padding:"11px 8px 6px",marginBottom:10}}>
            <div style={{color:"#f0b44c",fontSize:9,letterSpacing:2.5,marginLeft:4,marginBottom:6}}>CHOKE |Z| + µ'(f)</div>
            <ResponsiveContainer width="100%" height={195}>
              <LineChart data={specPtsFinal} margin={{top:4,right:18,bottom:22,left:4}}>
                <CartesianGrid strokeDasharray="2 5" stroke="#141414"/>
                <XAxis dataKey="logf" type="number" domain={[2,7]} ticks={[2,2.5,3,3.5,4,4.5,5,5.5,6,6.5,7]} tickFormatter={xfmt} tick={{fill:"#444",fontSize:9}} label={{value:"Frequency",position:"insideBottom",offset:-12,fill:"#333",fontSize:9}}/>
                <YAxis domain={[-10,110]} tick={{fill:"#444",fontSize:9}} label={{value:"|Z| (dBΩ)",angle:-90,position:"insideLeft",offset:14,fill:"#333",fontSize:9}}/>
                <Tooltip content={<ZTip/>}/>
                <ReferenceArea x1={2} x2={lgSRFu} y1={-10} y2={110} fill="#33cc55" fillOpacity={0.06}/>
                <ReferenceArea x1={lgSRFu} x2={lgSRF} y1={-10} y2={110} fill="#f0b44c" fillOpacity={0.05}/>
                <ReferenceArea x1={lgSRF} x2={7} y1={-10} y2={110} fill="#ff4444" fillOpacity={0.06}/>
                <ReferenceLine x={lgFsw} stroke="#4488ff" strokeDasharray="3 3" label={{value:"fsw",position:"insideTopLeft",fill:"#4488ff",fontSize:8}}/>
                <ReferenceLine x={lgSRF} stroke="#ff4444" strokeDasharray="3 3" label={{value:"SRF",position:"insideTopRight",fill:"#ff4444",fontSize:8}}/>
                <ReferenceLine x={lgSRFu} stroke="#33cc55" strokeDasharray="2 5" label={{value:"SRF/3",position:"insideTopLeft",fill:"#33cc55",fontSize:8}}/>
                <Line type="monotone" dataKey="Z" stroke="#88aaff" dot={false} strokeWidth={2} name="|Z| choke (dBΩ)"/>
                <Line type="monotone" dataKey="mupct" stroke={mat.color} dot={false} strokeWidth={1.5} strokeDasharray="5 3" name={`µ'(f) ${mat.short}`}/>
              </LineChart>
            </ResponsiveContainer>
          </div>

          {/* Chart 4: DC Bias */}
          <div style={{background:"#0c0c0c",border:"1px solid #1a1a1a",borderRadius:5,padding:"11px 8px 6px",marginBottom:10}}>
            <div style={{color:"#f0b44c",fontSize:9,letterSpacing:2.5,marginLeft:4,marginBottom:6}}>PERMEABILITY vs DC BIAS — {mat.short} {mu}µ</div>
            <ResponsiveContainer width="100%" height={165}>
              <LineChart data={biasCurve} margin={{top:4,right:18,bottom:22,left:4}}>
                <CartesianGrid strokeDasharray="2 5" stroke="#141414"/>
                <XAxis dataKey="H" tick={{fill:"#444",fontSize:9}} label={{value:"H (Oersteds)",position:"insideBottom",offset:-12,fill:"#333",fontSize:9}}/>
                <YAxis domain={[0,110]} tick={{fill:"#444",fontSize:9}} label={{value:"µ'(H) %",angle:-90,position:"insideLeft",offset:14,fill:"#333",fontSize:9}}/>
                <Tooltip content={<BT color={mat.color}/>}/>
                <ReferenceArea y1={70} y2={110} fill="#33cc55" fillOpacity={0.08}/>
                <ReferenceArea y1={40} y2={70}  fill="#f0b44c" fillOpacity={0.08}/>
                <ReferenceArea y1={0}  y2={40}  fill="#ff4444" fillOpacity={0.08}/>
                <ReferenceLine y={70} stroke="#33cc55" strokeDasharray="2 4" strokeOpacity={0.4}/>
                <ReferenceLine y={40} stroke="#f0b44c" strokeDasharray="2 4" strokeOpacity={0.4}/>
                <ReferenceLine x={Math.min(H,200)} stroke="#f0b44c" strokeDasharray="3 3" label={{value:`${fmt(H,0)} Oe`,position:"insideTopRight",fill:"#f0b44c",fontSize:8}}/>
                <ReferenceLine y={pMu*100} stroke="#555" strokeDasharray="2 4"/>
                <Line type="monotone" dataKey="pMu" stroke={mat.color} dot={false} strokeWidth={2} name="µ'(H) %"/>
              </LineChart>
            </ResponsiveContainer>
          </div>

          <div style={{color:"#1e1e1e",fontSize:9,lineHeight:1.8}}>
            v7.4 · Source: {srcLabel} · Limits: CISPR25 V/I Cl1-5, CISPR32 A/B, CE102, CE101 · SPICE import · IL: complex TF w/ Cw+ESR/ESL · Z_out(f) · {lmod==="igse"?`iGSE D=${fmt(topD,3)}`:lmod==="csc"?"CSC":"Steinmetz"} · Dowell FR
          </div>
        </div>
      </div>

      {/* ── CIRCUIT SCHEMATIC + EQUATIONS BUTTONS ── */}
      <div style={{marginTop:18,textAlign:"center",display:"flex",justifyContent:"center",gap:12,flexWrap:"wrap"}}>
        <div onClick={()=>setShowSchem(v=>!v)}
          style={{display:"inline-flex",alignItems:"center",gap:8,background:"#0e0e0e",border:"1px solid #2a2a2a",borderRadius:20,padding:"8px 22px",cursor:"pointer",userSelect:"none",color:"#cc88ff",fontSize:11,letterSpacing:2,fontWeight:700}}>
          <span style={{fontSize:14}}>{showSchem?"▲":"▼"}</span> CIRCUIT SCHEMATIC
        </div>
        <div onClick={()=>setShowEq(v=>!v)}
          style={{display:"inline-flex",alignItems:"center",gap:8,background:"#0e0e0e",border:"1px solid #2a2a2a",borderRadius:20,padding:"8px 22px",cursor:"pointer",userSelect:"none",color:"#f0b44c",fontSize:11,letterSpacing:2,fontWeight:700}}>
          <span style={{fontSize:14}}>{showEq?"▲":"▼"}</span> EQUATIONS &amp; CRITERIA
        </div>
      </div>

      {/* ── CIRCUIT SCHEMATIC PANEL ── */}
      {showSchem&&(()=>{
        // Layout geometry
        const W=st2?760:560, H=useDamping||emiDamp?290:230;
        const y1=60,yGnd=H-30; // main wire y, ground y
        const xSrc=40, xL1=st2?160:180, xN1=st2?280:320, xL2=400, xN2=520, xOut=st2?660:460;
        const cW=24,cH=40; // cap symbol size
        const tc="#f0b44c",wc="#888",gc="#333",ac="#cc88ff",mc="#33cc55"; // colors: trace, wire, ground, accent, middlebrook

        // SVG drawing helpers
        const Wire=({x1:xa,y1:ya,x2:xb,y2:yb,c,d})=><line x1={xa} y1={ya} x2={xb} y2={yb} stroke={c||wc} strokeWidth={1.5} strokeDasharray={d||""}/>;
        const Dot=({x,y,c})=><circle cx={x} cy={y} r={3} fill={c||wc}/>;
        const Lbl=({x,y,t,c,sz,fw,an})=><text x={x} y={y} fill={c||tc} fontSize={sz||10} fontWeight={fw||700} fontFamily="'IBM Plex Mono',monospace" textAnchor={an||"middle"}>{t}</text>;
        const ValLbl=({x,y,t,c})=><text x={x} y={y} fill={c||"#555"} fontSize={8} fontFamily="'IBM Plex Mono',monospace" textAnchor="middle">{t}</text>;

        // Inductor symbol (coil)
        const Coil=({x,y,w})=>{
          const nLoops=4,r=w/(nLoops*2);
          let d=`M${x} ${y}`;
          for(let i=0;i<nLoops;i++){d+=` A${r},${r*0.8} 0 1,1 ${x+r*2*(i+1)},${y}`}
          return <path d={d} fill="none" stroke={wc} strokeWidth={1.5}/>;
        };

        // Cap symbol (two plates)
        const Cap=({x,y,c})=>{
          const g=4,pw=cW/2;
          return <g><line x1={x} y1={y-g} x2={x} y2={y-cH/2} stroke={c||wc} strokeWidth={1.5}/>
            <line x1={x-pw} y1={y-g} x2={x+pw} y2={y-g} stroke={c||wc} strokeWidth={2}/>
            <line x1={x-pw} y1={y+g} x2={x+pw} y2={y+g} stroke={c||wc} strokeWidth={2}/>
            <line x1={x} y1={y+g} x2={x} y2={y+cH/2} stroke={c||wc} strokeWidth={1.5}/></g>;
        };

        // Resistor symbol (zigzag)
        const Res=({x,y,h,c})=>{
          const n=4,s=h/n,w=6;
          let d=`M${x} ${y}`;
          for(let i=0;i<n;i++){d+=` l${w} ${s/2} l${-w*2} 0 l${w} ${s/2}`}
          return <path d={d} fill="none" stroke={c||ac} strokeWidth={1.5}/>;
        };

        // Ground symbol
        const Gnd=({x,y})=><g>
          <line x1={x} y1={y} x2={x} y2={y+6} stroke={gc} strokeWidth={1.5}/>
          <line x1={x-8} y1={y+6} x2={x+8} y2={y+6} stroke={gc} strokeWidth={1.5}/>
          <line x1={x-5} y1={y+10} x2={x+5} y2={y+10} stroke={gc} strokeWidth={1}/>
          <line x1={x-2} y1={y+14} x2={x+2} y2={y+14} stroke={gc} strokeWidth={0.5}/>
        </g>;

        // Damping network (Rd + Cd in series, drawn vertically)
        const DampNet=({x,y1:ya,y2:yb,Rd:rv,Cd:cv,label,c})=>{
          const mid=(ya+yb)/2;
          return <g>
            <line x1={x} y1={ya} x2={x} y2={ya+8} stroke={c||ac} strokeWidth={1.5}/>
            <Res x={x} y={ya+8} h={(mid-ya-8)} c={c}/>
            <Cap x={x} y={mid+6} c={c}/>
            <line x1={x} y1={mid+6+cH/2} x2={x} y2={yb} stroke={c||ac} strokeWidth={1.5}/>
            <ValLbl x={x+20} y={ya+(mid-ya)/2+4} t={`${fmt(rv,1)}Ω`} c={c}/>
            <ValLbl x={x+20} y={mid+14} t={`${fmt(cv,0)}nF`} c={c}/>
            <ValLbl x={x} y={ya-6} t={label} c={c}/>
          </g>;
        };

        // Node positions for optional 2nd stage
        const capY=y1+20, capBot=capY+cH+10;
        const dampY1=y1+10, dampY2=capBot+30;

        return <div style={{background:"#0a0a0a",border:"1px solid #1e1e1e",borderRadius:5,padding:"14px",marginTop:14}}>
          <div style={{color:"#cc88ff",fontSize:9,letterSpacing:2.5,marginBottom:10}}>FILTER SCHEMATIC — LIVE VALUES</div>
          <svg viewBox={`0 0 ${W} ${H}`} style={{width:"100%",maxWidth:W,height:"auto",display:"block",margin:"0 auto"}}>
            {/* ── Main wire ── */}
            <Wire x1={xSrc} y1={y1} x2={xL1-20} y2={y1}/>
            <Coil x={xL1-20} y={y1} w={st2?80:100}/>
            <Wire x1={xL1+(st2?60:80)} y1={y1} x2={xN1} y2={y1}/>
            <Dot x={xN1} y={y1}/>
            {st2?<>
              <Wire x1={xN1} y1={y1} x2={xL2-20} y2={y1}/>
              <Coil x={xL2-20} y={y1} w={80}/>
              <Wire x1={xL2+60} y1={y1} x2={xN2} y2={y1}/>
              <Dot x={xN2} y={y1}/>
              <Wire x1={xN2} y1={y1} x2={xOut} y2={y1}/>
            </>:<Wire x1={xN1} y1={y1} x2={xOut} y2={y1}/>}

            {/* ── Source label ── */}
            <Lbl x={xSrc} y={y1-14} t="LISN" c="#555" sz={8}/>
            <Lbl x={xSrc} y={y1+18} t={`${Zs}Ω`} c="#555" sz={9}/>

            {/* ── DUT / Converter (current source) ── */}
            <rect x={xOut-30} y={y1-28} width={60} height={56} rx={4} fill="#0e0800" stroke="#664400" strokeWidth={1} strokeDasharray="3 2"/>
            <Lbl x={xOut} y={y1-16} t={topoKey==="buck"?"BUCK":topoKey==="boost"?"BOOST":topoKey==="flyCCM"?"FLY-CCM":topoKey==="flyDCM"?"FLY-DCM":"2SW-FWD"} c="#ff8844" sz={7}/>
            {/* Current source symbol (circle with arrow) */}
            <circle cx={xOut} cy={y1} r={8} fill="none" stroke="#ff8844" strokeWidth={1.2}/>
            <line x1={xOut} y1={y1-5} x2={xOut} y2={y1+5} stroke="#ff8844" strokeWidth={1.2}/>
            <polygon points={`${xOut-2.5},${y1-2} ${xOut},${y1-6} ${xOut+2.5},${y1-2}`} fill="#ff8844"/>
            <ValLbl x={xOut} y={y1+18} t={`D=${fmt(topD,2)}`} c={topD_valid?"#664400":"#ff4444"}/>
            <ValLbl x={xOut} y={y1+28} t={`${fmt(Vin,0)}V→${fmt(Vout,1)}V`} c="#664400"/>
            {!topD_valid&&<Lbl x={xOut} y={y1+38} t="⚠ INVALID" c="#ff4444" sz={7}/>}

            {/* ── L1 label ── */}
            <Lbl x={xL1+(st2?20:30)} y={y1-18} t="L₁" c={tc}/>
            <ValLbl x={xL1+(st2?20:30)} y={y1-8} t={`${fmt(Luh,1)}µH`}/>

            {/* ── C1 ── */}
            <Wire x1={xN1} y1={y1} x2={xN1} y2={capY}/>
            <Cap x={xN1} y={capY+cH/2}/>
            <Wire x1={xN1} y1={capY+cH} x2={xN1} y2={capBot}/>
            <Gnd x={xN1} y={capBot}/>
            <Lbl x={xN1+18} y={capY+cH/2-4} t="C₁" c={tc} sz={9}/>
            <ValLbl x={xN1+18} y={capY+cH/2+8} t={`${fmt(Cnf,1)}nF`}/>
            {capEsr>0&&<ValLbl x={xN1+18} y={capY+cH/2+18} t={`ESR ${capEsr}mΩ`} c="#333"/>}

            {/* ── Stage 2 ── */}
            {st2&&<>
              <Lbl x={xL2+20} y={y1-18} t="L₂" c={tc}/>
              <ValLbl x={xL2+20} y={y1-8} t={`${fmt(L2,1)}µH`}/>
              <Wire x1={xN2} y1={y1} x2={xN2} y2={capY}/>
              <Cap x={xN2} y={capY+cH/2}/>
              <Wire x1={xN2} y1={capY+cH} x2={xN2} y2={capBot}/>
              <Gnd x={xN2} y={capBot}/>
              <Lbl x={xN2+18} y={capY+cH/2-4} t="C₂" c={tc} sz={9}/>
              <ValLbl x={xN2+18} y={capY+cH/2+8} t={`${fmt(C2,1)}nF`}/>
            </>}

            {/* ── Ground bus ── */}
            <Wire x1={xN1-10} y1={capBot+14} x2={st2?xN2+10:xN1+10} y2={capBot+14} c={gc} d="4 3"/>

            {/* ── Middlebrook damping (green, left side of C1) ── */}
            {useDamping&&<>
              <Wire x1={xN1} y1={y1} x2={xN1-35} y2={y1} c={mc}/>
              <Dot x={xN1-35} y={y1} c={mc}/>
              <DampNet x={xN1-35} y1={y1} y2={capBot} Rd={Rd_act} Cd={Cd_act_nF} label="MB" c={mc}/>
              <Gnd x={xN1-35} y={capBot}/>
            </>}

            {/* ── EMI damping (purple, right side of target cap) ── */}
            {emiDamp&&(()=>{
              const tx=emiDampStg===2&&st2?xN2+35:xN1+35;
              const tNode=emiDampStg===2&&st2?xN2:xN1;
              return <>
                <Wire x1={tNode} y1={y1} x2={tx} y2={y1} c={ac}/>
                <Dot x={tx} y={y1} c={ac}/>
                <DampNet x={tx} y1={y1} y2={capBot} Rd={emiRd_act} Cd={emiCd_act} label="EMI" c={ac}/>
                <Gnd x={tx} y={capBot}/>
              </>;
            })()}

            {/* ── Cw annotation on L1 ── */}
            <ValLbl x={xL1+(st2?20:30)} y={y1+16} t={`Cw ${fmt(CwEff_pF,0)}pF`} c="#334466"/>
            <ValLbl x={xL1+(st2?20:30)} y={y1+26} t={`SRF ${fmtF(SRF)}`} c="#2a3a2a"/>

          </svg>
        </div>;
      })()}

      {/* ── EQUATIONS / CRITERIA PANEL ── */}

      {showEq&&<EqPanel/>}
    </div>
  );
}
