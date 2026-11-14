#!/usr/bin/env python3
"""Bounded evaluation of serialized Unity particle curves and emission times.

Enum and MinMax evaluation semantics follow the Unity C# reference source:
https://github.com/Unity-Technologies/UnityCsReference/blob/master/Modules/ParticleSystem/Managed/ParticleSystemEnums.cs
https://github.com/Unity-Technologies/UnityCsReference/blob/master/Modules/ParticleSystem/Managed/ParticleSystemStructs.cs

The converter samples one documented random realization. It does not claim
to reproduce a particular run's automatically selected Unity random seed.
"""
from __future__ import annotations
import bisect, math
import numpy as np


def require(condition, message):
    if not condition:raise ValueError(message)


def scalar(value):
    if isinstance(value,dict) and 'nonfiniteSourceValue' in value:
        text=value['nonfiniteSourceValue']
        require(text in ('inf','-inf'),'Invalid nonfinite source tangent')
        return float(text)
    return float(value)


def curve(value, time):
    keys=value['m_Curve']
    require(0 < len(keys) <= 256,'Source curve has no keys or exceeds the bound')
    times=[float(k['time']) for k in keys]
    require(all(math.isfinite(x) for x in times) and all(a<b for a,b in zip(times,times[1:])),
            'Source curve times are not strictly ordered')
    require(math.isfinite(time),'Nonfinite source curve query')
    if time <= times[0]:return float(keys[0]['value'])
    if time >= times[-1]:return float(keys[-1]['value'])
    index=bisect.bisect_right(times,time)-1;a,b=keys[index:index+2]
    span=times[index+1]-times[index];u=(time-times[index])/span
    first,second=float(a['value']),float(b['value'])
    out_slope,in_slope=scalar(a['outSlope']),scalar(b['inSlope'])
    if not math.isfinite(out_slope) or not math.isfinite(in_slope):return first
    # Unity's weighted tangents are time-normalized Bezier handles. Unweighted
    # handles are precisely one third of the interval and reduce to Hermite.
    out_weight=float(a['outWeight']) if int(a['weightedMode'])&2 else 1/3
    in_weight=float(b['inWeight']) if int(b['weightedMode'])&1 else 1/3
    require(0 <= out_weight <= 1 and 0 <= in_weight <= 1,'Invalid source tangent weight')
    x1,x2=out_weight,1-in_weight
    if abs(x1-1/3)>1e-8 or abs(x2-2/3)>1e-8:
        low,high=0.,1.
        for _ in range(36):
            t=(low+high)/2;inv=1-t
            x=3*inv*inv*t*x1+3*inv*t*t*x2+t*t*t
            if x<u:low=t
            else:high=t
        u=(low+high)/2
    y1=first+out_slope*span*out_weight;y2=second-in_slope*span*in_weight;inv=1-u
    return inv**3*first+3*inv*inv*u*y1+3*inv*u*u*y2+u**3*second


def minmax(value, time, random):
    mode=int(value['minMaxState']);high=float(value['scalar']);low=float(value['minScalar'])
    require(0 <= random <= 1 and math.isfinite(high) and math.isfinite(low),'Invalid source MinMax scalar')
    if mode==0:return high
    if mode==1:return high*curve(value['maxCurve'],time)
    if mode==2:
        # minScalar is not a second multiplier in TwoCurves mode.
        a,b=curve(value['minCurve'],time),curve(value['maxCurve'],time)
        return high*(a+(b-a)*random)
    if mode==3:return low+(high-low)*random
    raise ValueError('Unsupported source MinMax mode')


def rgba(value):return np.array([float(value[k]) for k in ('r','g','b','a')])


def gradient(value,time):
    require(value['m_Mode']==0,'Unimplemented source fixed/perceptual gradient mode')
    result=np.empty(4)
    for count_key,prefix,channels in [('m_NumColorKeys','ctime',slice(0,3)),('m_NumAlphaKeys','atime',slice(3,4))]:
        count=int(value[count_key]);require(1<=count<=8,'Invalid source gradient key count')
        times=np.array([value[prefix+str(i)]/65535 for i in range(count)])
        colors=np.array([rgba(value['key'+str(i)])[channels] for i in range(count)])
        require(np.all(times[1:]>=times[:-1]),'Unordered source gradient keys')
        index=min(count-1,max(0,int(np.searchsorted(times,time,side='right'))-1))
        other=min(count-1,index+1)
        weight=0 if other==index else np.clip((time-times[index])/max(1e-15,times[other]-times[index]),0,1)
        result[channels]=colors[index]*(1-weight)+colors[other]*weight
    return result


def color(value,time,random):
    mode=int(value['minMaxState']);require(0<=random<=1,'Invalid source gradient random value')
    if mode==0:return rgba(value['maxColor'])
    if mode==1:return gradient(value['maxGradient'],time)
    if mode==2:return rgba(value['minColor'])*(1-random)+rgba(value['maxColor'])*random
    if mode==3:return gradient(value['minGradient'],time)*(1-random)+gradient(value['maxGradient'],time)*random
    if mode==4:return gradient(value['maxGradient'],random)
    raise ValueError('Unsupported source MinMax gradient mode')


def quaternion_multiply(a,b):
    av,bv=np.asarray(a[:3]),np.asarray(b[:3])
    return np.r_[a[3]*bv+b[3]*av+np.cross(av,bv),a[3]*b[3]-av@bv]


def euler_rotation(angles):
    # Unity Quaternion.Euler applies z, then x, then y in its source basis.
    x,y,z=np.asarray(angles,dtype=float)*.5
    qx=np.array([math.sin(x),0,0,math.cos(x)])
    qy=np.array([0,math.sin(y),0,math.cos(y)])
    qz=np.array([0,0,math.sin(z),math.cos(z)])
    return quaternion_multiply(qy,quaternion_multiply(qx,qz))


def birth_times(emitter,random,rate=240):
    """Integrate original bursts/rates for one emitter cycle, in source seconds."""
    duration=float(emitter['lengthInSec']);require(0<duration<=60,'Source emitter duration out of bounds')
    module=emitter['EmissionModule']
    if not module['enabled']:return []
    # Motion-dependent distance emission cannot be replaced by a guessed rate.
    require(abs(minmax(module['rateOverDistance'],.5,.5))<1e-10,
            'Distance emission requires the original emitter motion')
    births=[]
    for burst in module['m_Bursts']:
        require(1<=burst['cycleCount']<=10000,'Invalid source burst count')
        for cycle in range(burst['cycleCount']):
            time=float(burst['time'])+cycle*float(burst['repeatInterval'])
            if time>=duration:continue
            if random.random()>burst['probability']:continue
            count=int(round(minmax(burst['countCurve'],time/duration,random.random())))
            require(0<=count<=10000,'Source burst particle count out of bounds')
            births.extend([time]*count)
    # Crossing each integer of the integrated rate yields an emission instant;
    # the fractional remainder is not discarded at display sample boundaries.
    times=np.linspace(0,duration,max(1,math.ceil(duration*rate))+1)
    factor=random.random();accumulator=0.;threshold=1.
    for first,last in zip(times,times[1:]):
        a=max(0.,minmax(module['rateOverTime'],first/duration,factor))
        b=max(0.,minmax(module['rateOverTime'],last/duration,factor))
        area=(a+b)*.5*(last-first)
        while threshold <= accumulator+area+1e-10:
            # Exact constant/linear within this integration interval.
            target=threshold-accumulator;slope=(b-a)/(last-first)
            delta=target/a if abs(slope)<1e-10 and a>0 else (
                (-a+math.sqrt(max(0.,a*a+2*slope*target)))/slope if abs(slope)>1e-10 else 0.)
            emitted=first+np.clip(delta,0,last-first)
            if emitted<duration-1e-8:births.append(float(emitted))
            threshold+=1
        accumulator+=area
    require(len(births)<=10000,'Source emission cycle exceeds the sampling bound')
    return sorted(births)


def repeat_copies(duration,period,prewarm=False):
    """Keep particles that cross an emitter cycle alive in separate tracks."""
    require(duration>0 and period>0,'Invalid source loop period')
    copies=max(1,math.ceil((duration-1e-10)/period));repeat=copies*period
    # Negative birth times are represented by clipped, already-aged tracks by
    # the exporter; returning the complete schedule avoids silent tail resets.
    start=-copies if prewarm else 0
    return [(index*period,repeat) for index in range(start,copies)]
