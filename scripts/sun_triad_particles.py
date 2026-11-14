#!/usr/bin/env python3
"""Bake original H17 particle curves and real geometry into bounded private tracks.

The source uses automatic random seeds. This produces one repeatable random
realization, retaining the original rates, capacity, lifetime, shapes, curves,
materials, texture identities and mesh topology. It never fetches resources.
Engine modules whose force/trail semantics are not yet adapted are reported
explicitly in the private receipt; source data is retained for their adapters.
"""
from __future__ import annotations
import argparse, collections, copy, gzip, hashlib, heapq, json, math, random, warnings
from pathlib import Path
import numpy as np
from sun_triad_assets import matrix,qmatrix,quaternion,private_output,write_private,require
from sun_triad_particle_curves import minmax,color,birth_times,euler_rotation,quaternion_multiply
from sun_triad_particle_assets import SourceAssets


def seed(*parts):return int.from_bytes(hashlib.sha256('/'.join(map(str,parts)).encode()).digest()[:8],'little')
def vec(value):return np.array([float(value[k]) for k in ('x','y','z')])
def unit(value,fallback=(0,0,1)):
    value=np.asarray(value,dtype=float);size=np.linalg.norm(value)
    return value/size if size>1e-12 else np.asarray(fallback,dtype=float)


class Particle:
    def __init__(self,source,identity,birth,index,burst_index=0,burst_count=1):
        self.birth=birth;self.index=index;self.phase=(birth%source['lengthInSec'])/source['lengthInSec']
        self.burst_index=burst_index;self.burst_count=burst_count
        self.random=random.Random(seed(identity,index));self.values={}
        self.life=minmax(source['InitialModule']['startLifetime'],self.phase,self.r('life'))
        require(0<self.life<=36_000,'Original particle lifetime exceeds source bound')
    def r(self,name):
        if name not in self.values:self.values[name]=self.random.random()
        return self.values[name]


def emission_schedule(source,identity):
    """Enforce source maxNumParticles, then fold a proved repeating schedule.

Random choices repeat over a deterministic super-period. The capacity state is
simulated until the same active particles recur at a period boundary; only
then may an existing track be reused. This avoids cutting off cross-cycle tails
or multiplying max=1 forest trees into thousands of simultaneous instances.
"""
    maximum=int(source['InitialModule']['maxNumParticles']);require(1<=maximum<=100_000,'Invalid source particle capacity')
    duration=float(source['lengthInSec']);first=birth_times(source,random.Random(seed(identity,'emission',0)))
    if not first:return []
    if not source['looping']:
        active=[];accepted=[];counts=collections.Counter(first);ordinals=collections.Counter()
        for index,birth in enumerate(first):
            particle=Particle(source,identity,birth,index,ordinals[birth],counts[birth]);ordinals[birth]+=1
            while active and active[0]<=birth+1e-9:heapq.heappop(active)
            if len(active)>=maximum:continue
            heapq.heappush(active,birth+particle.life);accepted.append((particle,birth,None))
        return accepted
    life=source['InitialModule']['startLifetime']
    maximum_life=max(minmax(life,float(t),r) for t in np.linspace(0,1,129) for r in (0.,1.))
    if maximum_life>120:
        require(maximum==1 and len(first)==1 and first[0]==0 and life['minMaxState']==0,
                'Long-lived source emitter needs an explicit bounded schedule')
        particle=Particle(source,identity,0,0)
        return [(particle,0,math.ceil(particle.life/duration)*duration)]
    cycles=max(1,math.ceil(2*maximum_life/duration));period=cycles*duration
    require(period<=360 and cycles<=4000,'Source particle super-period exceeds bounds')
    candidates=[]
    for cycle in range(cycles):
        births=birth_times(source,random.Random(seed(identity,'emission',cycle)))
        counts=collections.Counter(births);ordinals=collections.Counter()
        for time in births:
            birth=cycle*duration+time
            candidates.append(Particle(source,identity,birth,len(candidates),ordinals[time],counts[time]));ordinals[time]+=1
    active=[];per_period=[];states={():0}
    for turn in range(128):
        accepted=[];origin=turn*period
        for particle in candidates:
            birth=origin+particle.birth
            while active and active[0][0]<=birth+1e-8:heapq.heappop(active)
            if len(active)>=maximum:continue
            heapq.heappush(active,(birth+particle.life,particle.index));accepted.append(particle.index)
        boundary=(turn+1)*period
        while active and active[0][0]<=boundary+1e-8:heapq.heappop(active)
        state=tuple(sorted((index,round(end-boundary,7)) for end,index in active))
        per_period.append(set(accepted))
        if state in states:
            steady_start=states[state];cycle_length=turn+1-steady_start;break
        states[state]=turn+1
    else:raise ValueError('Original capacity schedule did not reach a verified repeating state')
    result=[];remaining={(turn,index) for turn,indices in enumerate(per_period) for index in indices}
    for phase in range(cycle_length):
        turn=steady_start+phase
        for index in sorted(per_period[turn]):
            start=turn
            while start>=cycle_length and index in per_period[start-cycle_length]:start-=cycle_length
            particle=candidates[index]
            result.append((particle,start*period+particle.birth,cycle_length*period))
            for repeated in range(start,len(per_period),cycle_length):remaining.discard((repeated,index))
    result.extend((candidates[index],turn*period+candidates[index].birth,None) for turn,index in remaining)
    return sorted(result,key=lambda x:(x[1],x[0].index))


def shape(source,particle):
    module=source['ShapeModule']
    if not module['enabled']:return np.zeros(3),np.array([0.,0.,1.])
    require(module['type'] in (0,4,10,12),'Unsupported source emitter shape')
    radius=float(module['radius']['value']);thickness=float(module['radiusThickness'])
    require(module['arc']['mode'] in (0,3) and module['radius']['mode'] in (0,3),
            'Animated source emission arc needs its source clock')
    angular_fraction=(particle.burst_index/particle.burst_count if module['arc']['mode']==3 else particle.r('shapeAngle'))
    angle=angular_fraction*math.radians(module['arc']['value'])
    if module['type']==0:
        z=2*particle.r('shapeZ')-1;circle=math.sqrt(max(0,1-z*z))
        direction=np.array([circle*math.cos(angle),circle*math.sin(angle),z])
        inner=max(0,1-thickness);distance=radius*(inner**3+(1-inner**3)*particle.r('shapeRadius'))**(1/3)
        position=direction*distance
    elif module['type'] in (4,10):
        inner=max(0,1-thickness);distance=radius*math.sqrt(inner*inner+(1-inner*inner)*particle.r('shapeRadius'))
        position=np.array([math.cos(angle)*distance,math.sin(angle)*distance,0.])
        if module['type']==4:
            opening=math.radians(module['angle']);direction=unit([math.cos(angle)*math.sin(opening)*distance/max(radius,1e-9),
                math.sin(angle)*math.sin(opening)*distance/max(radius,1e-9),math.cos(opening)])
        else:direction=unit(position)
    else:
        fraction=(particle.burst_index/max(1,particle.burst_count-1) if module['radius']['mode']==3 else particle.r('shapeEdge'))
        position=np.array([(fraction*2-1)*radius,0.,0.]);direction=np.array([0.,0.,1.])
    rotation=qmatrix(euler_rotation(np.radians(vec(module['m_Rotation']))))[:3,:3]
    position=rotation@(position*vec(module['m_Scale']))+vec(module['m_Position']);direction=rotation@direction
    random_direction=module['randomDirectionAmount']
    if random_direction:
        r=unit([2*particle.r('randomDirection'+str(i))-1 for i in range(3)])
        direction=unit(direction*(1-random_direction)+r*random_direction)
    if module['sphericalDirectionAmount']:
        factor=module['sphericalDirectionAmount'];direction=unit(direction*(1-factor)+unit(position)*factor)
    if module['randomPositionAmount']:
        position+=module['randomPositionAmount']*np.array([2*particle.r('randomPosition'+str(i))-1 for i in range(3)])
    return position,direction


def custom(module,stream,time,particle):
    if not module['enabled'] or module['mode'+str(stream)]==0:return np.zeros(4)
    mode=module['mode'+str(stream)]
    if mode==2:return color(module['color'+str(stream)],time,particle.r('customColor'+str(stream)))
    require(mode==1,'Unsupported original particle custom-data mode')
    count=module['vectorComponentCount'+str(stream)];require(1<=count<=4,'Invalid source custom-data width')
    return np.array([minmax(module['vector'+str(stream)+'_'+str(i)],time,particle.r('custom'+str(stream)+'_'+str(i)))
                     if i<count else 0. for i in range(4)])


def uv_transform(module,time,age,particle):
    if not module['enabled']:return np.array([0.,0.,1.,1.])
    require(module['mode']==0 and module['timeMode'] in (0,2),'Unsupported source texture animation mode')
    x,y=int(module['tilesX']),int(module['tilesY']);require(1<=x<=64 and 1<=y<=64,'Source texture grid out of bounds')
    count=x*y if module['animationType']==0 else x
    start=minmax(module['startFrame'],time,particle.r('startFrame'))*count
    frame=(minmax(module['frameOverTime'],time,particle.r('frameOverTime'))*module['cycles']*count
           if module['timeMode']==0 else age*module['fps'])
    selected=int(math.floor(start+frame))%count
    row=selected//x if module['animationType']==0 else (
        min(y-1,int(particle.r('row')*y)) if module['rowMode']==1 else int(module['rowIndex']))
    # This transform stays in original Unity UV coordinates. The authenticated
    # shader adapter reverses the geometry V reflection before applying it,
    # before applying it to the original compressed Unity texture bytes.
    return np.array([(selected%x)/x,1-(row+1)/y,1/x,1/y])


def sample_particle(source,renderer,transform,local_scale,particle,*,sample_rate=60,project_gravity=None):
    initial=source['InitialModule'];speed=float(source['simulationSpeed']);require(0<speed<=100,'Invalid source simulation speed')
    position,direction=shape(source,particle);phase=particle.phase
    velocity=direction*minmax(initial['startSpeed'],phase,particle.r('speed'))
    initial_color=color(initial['startColor'],phase,particle.r('color'))
    size=np.repeat(minmax(initial['startSize'],phase,particle.r('size')),3)
    if initial['size3D']:
        size[1]=minmax(initial['startSizeY'],phase,particle.r('sizeY'));size[2]=minmax(initial['startSizeZ'],phase,particle.r('sizeZ'))
    rotation=np.array([minmax(initial[k],phase,particle.r(k)) for k in ('startRotationX','startRotationY','startRotation')])
    if not initial['rotation3D']:rotation[:2]=0
    if particle.r('rotationDirection')<initial['randomizeRotationDirection']:rotation=-rotation
    full_scale=np.linalg.norm(transform[:3,:3],axis=0);emitter_rotation=transform[:3,:3]/full_scale
    mode=source['scalingMode'];scale=full_scale if mode==0 else np.asarray(local_scale) if mode==1 else np.ones(3)
    require(mode in (0,1,2),'Unknown source particle scaling mode')
    if mode==2:position*=full_scale
    actor_rotation=quaternion(emitter_rotation);period=particle.life/speed
    samples=max(1,math.ceil(period*sample_rate))
    static=samples>14_400
    if static:
        require(np.linalg.norm(velocity)<1e-9 and not any(source[k]['enabled'] for k in
                ('VelocityModule','RotationModule','ForceModule','NoiseModule','ExternalForcesModule')),
                'Long-lived source particle needs an analytic motion adapter')
        samples=128
    times=np.linspace(0,period,samples+1);frames=[];orientations=[];depth=[];custom1=[];custom2=[]
    old_time=0.;last_velocity=velocity.copy();velocity_module=source['VelocityModule'];position0=position.copy()
    for time in times:
        age=time*speed;normal=min(1.,age/particle.life);dt=(time-old_time)*speed;old_time=time
        angular=np.zeros(3)
        if source['RotationModule']['enabled']:
            r=source['RotationModule'];angular[2]=minmax(r['curve'],normal,particle.r('angularZ'))
            if r['separateAxes']:
                angular[:2]=[minmax(r[k],normal,particle.r('angular'+k)) for k in ('x','y')]
        rotation+=angular*dt
        animated=np.zeros(3);modifier=1.
        if velocity_module['enabled']:
            v=velocity_module;animated=np.array([minmax(v[k],normal,particle.r('velocity'+k)) for k in ('x','y','z')])
            if v['inWorldSpace']:animated=emitter_rotation.T@animated
            center=np.array([minmax(v['orbitalOffset'+k],normal,particle.r('orbitOffset'+k)) for k in ('X','Y','Z')])
            orbit=np.array([minmax(v['orbital'+k],normal,particle.r('orbit'+k)) for k in ('X','Y','Z')])
            if np.linalg.norm(orbit)>0:
                position=center+qmatrix(euler_rotation(orbit*dt))[:3,:3]@(position-center)
            radial=minmax(v['radial'],normal,particle.r('radial'))
            animated+=unit(position-center,(0,0,0))*radial
            modifier=minmax(v['speedModifier'],normal,particle.r('speedModifier'))
        gravity=minmax(initial['gravityModifier'],normal,particle.r('gravity'))
        if gravity:
            require(project_gravity is not None,'Original project gravity must be supplied in source units')
            velocity+=emitter_rotation.T@(np.asarray(project_gravity)*gravity*dt)
        current_velocity=(velocity+animated)*modifier
        if source['ClampVelocityModule']['enabled']:
            clamp=source['ClampVelocityModule'];candidate=current_velocity.copy()
            if clamp['inWorldSpace']:candidate=emitter_rotation@candidate
            if clamp['separateAxis']:
                limits=np.array([minmax(clamp[k],normal,particle.r('clamp'+k)) for k in ('x','y','z')])
                target=np.clip(candidate,-limits,limits)
            else:
                limit=max(0.,minmax(clamp['magnitude'],normal,particle.r('clampMagnitude')))
                target=unit(candidate,(0,0,0))*min(np.linalg.norm(candidate),limit)
            damping=1-(1-clamp['dampen'])**(dt*60)
            candidate+=(target-candidate)*damping
            drag=minmax(clamp['drag'],normal,particle.r('drag'))
            if clamp['multiplyDragByParticleSize']:drag*=float(np.mean(abs(size)))
            if clamp['multiplyDragByParticleVelocity']:drag*=float(np.linalg.norm(candidate))
            candidate*=math.exp(-max(0.,drag)*dt)
            current_velocity=emitter_rotation.T@candidate if clamp['inWorldSpace'] else candidate
            velocity=current_velocity/max(1e-12,modifier)-animated
        if dt:position+=(last_velocity+current_velocity)*.5*dt
        last_velocity=current_velocity.copy()
        current_size=size.copy()
        if source['SizeModule']['enabled']:
            module=source['SizeModule'];amount=minmax(module['curve'],normal,particle.r('sizeOverLife'))
            current_size*=np.array([amount]+[minmax(module[k],normal,particle.r('sizeOverLife'+k)) for k in ('y','z')]) if module['separateAxes'] else amount
        current_color=initial_color.copy()
        if source['ColorModule']['enabled']:current_color*=color(source['ColorModule']['gradient'],normal,particle.r('colorOverLife'))
        coordinate=transform[:3,3]+emitter_rotation@(position*scale)
        q=euler_rotation(rotation)
        if renderer['m_RenderAlignment']==2:q=quaternion_multiply(actor_rotation,q)
        elif renderer['m_RenderAlignment']==4:
            z=unit(emitter_rotation@current_velocity);x=unit(np.cross([0,1,0],z),(1,0,0));y=np.cross(z,x)
            q=quaternion_multiply(quaternion(np.array([x,y,z]).T),q)
        else:require(renderer['m_RenderAlignment'] in (0,1),'Unsupported source particle render alignment')
        q*=np.array([-1.,-1.,1.,1.]);q/=np.linalg.norm(q)
        dimensions=current_size*scale
        # Stretched camera-facing particles preserve the original distance
        # and speed scale. Screen-space direction is provided separately.
        if renderer['m_RenderMode']==1:
            dimensions[1]=abs(dimensions[1]*renderer['m_LengthScale'])+np.linalg.norm(current_velocity)*abs(renderer['m_VelocityScale'])
        uv=uv_transform(source['UVModule'],normal,age,particle)
        frame=np.r_[time,coordinate*np.array([1,1,-1]),dimensions[:2],rotation[2],current_color,uv]
        require(np.isfinite(frame).all() and np.all(frame[7:11]>=0),'Invalid sampled source particle frame')
        frames.append(frame.tolist());orientations.append(q.tolist());depth.append(float(dimensions[2]))
        custom1.append(custom(source['CustomDataModule'],0,normal,particle).tolist())
        custom2.append(custom(source['CustomDataModule'],1,normal,particle).tolist())
    if static:
        values=np.c_[np.array(frames)[:,1:],orientations,depth,custom1,custom2]
        require(np.max(abs(values-values[0]))<1e-6,'Long-lived source tree is not constant')
        indices=[0,len(frames)-1]
    else:
        # The original 60 Hz samples remain the reference. Removed samples may
        # differ by at most 0.001 source unit (0.01 mm), 1/4096 color/custom
        # value, or 1e-5 quaternion/radian, with exact texture-frame steps.
        data=np.c_[np.array(frames)[:,1:],orientations,depth,custom1,custom2];indices=[0]
        tolerances=np.array([1e-3]*5+[1e-5]+[1/4096]*4+[1e-7]*4+[1e-5]*4+[1e-3]+[1/4096]*8)
        def split(a,b):
            if b-a<=1:return
            weights=(times[a+1:b]-times[a])/(times[b]-times[a])
            expected=data[a]+(data[b]-data[a])*weights[:,None]
            error=np.max(abs(data[a+1:b]-expected)/tolerances,axis=1);relative=int(np.argmax(error))
            if error[relative]>1:
                middle=a+1+relative;split(a,middle);indices.append(middle);split(middle,b)
        split(0,len(frames)-1);indices.append(len(frames)-1)
    def keep(values):return [np.round(values[i],7).tolist() for i in indices]
    return dict(frames=keep(frames),orientations=keep(orientations),depthScales=keep(depth),
                customData1=keep(custom1),customData2=keep(custom2)),dict(sourceBirth=particle.birth,sourceLifetime=particle.life,
                    sourceRandomValues=particle.values,samplesBeforeReduction=len(frames),samples=len(indices))


def clip_begin(data,offset):
    """Prewarm retains the already aged particle, without restarting its life."""
    frames=data['frames'];times=[f[0] for f in frames]
    if offset<=0:return copy.deepcopy(data)
    if offset>=times[-1]:return None
    high=int(np.searchsorted(times,offset,side='right'));low=high-1
    weight=(offset-times[low])/(times[high]-times[low]);result={}
    for key,values in data.items():
        if key not in ('frames','orientations','depthScales','customData1','customData2'):continue
        a,b=np.asarray(values[low]),np.asarray(values[high]);first=a*(1-weight)+b*weight
        if key=='orientations':first/=np.linalg.norm(first)
        result[key]=[first.tolist()]+copy.deepcopy(values[high:])
    for frame in result['frames']:frame[0]=round(frame[0]-offset,7)
    result['frames'][0][0]=0.
    return result


def clip_end(data,limit):
    if data['frames'][-1][0]<=limit:return copy.deepcopy(data)
    times=[frame[0] for frame in data['frames']];high=int(np.searchsorted(times,limit,side='left'));low=max(0,high-1)
    require(0<limit and high>0,'Original effect override has no visible particle lifetime')
    weight=(limit-times[low])/(times[high]-times[low]);result=copy.deepcopy(data)
    for key in ('frames','orientations','depthScales','customData1','customData2'):
        if key not in data:continue
        values=data[key];a,b=np.asarray(values[low]),np.asarray(values[high]);last=a*(1-weight)+b*weight
        if key=='orientations':last/=np.linalg.norm(last)
        result[key]=copy.deepcopy(values[:high])+[last.tolist()]
    result['frames'][-1][0]=limit
    if 'duration' in result:result['duration']=limit
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--models',type=Path,required=True);parser.add_argument('--effects',type=Path,required=True)
    parser.add_argument('--character',type=Path,required=True);parser.add_argument('--source-configuration',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True);parser.add_argument('--only',action='append',default=[])
    args=parser.parse_args();warnings.filterwarnings('ignore',category=Warning,module='UnityPy')
    output=private_output(args.output);assets=SourceAssets(args.models,args.effects,output)
    # Private, resumable sampling only. Material programs and external textures
    # are always revalidated from their original source receipts on every run.
    cache_directory=output/'sampling-cache-private';cache_directory.mkdir(exist_ok=True,mode=0o700)
    cache_identity=hashlib.sha256(Path(__file__).read_bytes()+
        Path(__file__).with_name('sun_triad_particle_curves.py').read_bytes()).hexdigest()
    inventory=json.loads((args.effects/'h17-effects-inventory.json').read_text())
    records={str(o.path_id):dict(type=o.type.name,data=o.read_typetree()) for o in assets.environment.objects
             if o.type.name in ('ParticleSystem','ParticleSystemRenderer','MonoBehaviour')}
    effects={};audit=[];issues=[]
    for effect in inventory['entries']:
        name=effect['rootName']
        if args.only and name not in args.only:continue
        cache_file=cache_directory/(hashlib.sha256(name.encode()).hexdigest()+'.json')
        cached=None
        if cache_file.exists():
            try:
                candidate=json.loads(cache_file.read_text())
                if candidate['converterSHA256']==cache_identity and candidate['sourceBundleSHA256']==inventory['sourceBundleSHA256']:
                    cached=candidate
            except (ValueError,KeyError):pass
        first_audit=len(audit)
        controllers=[records[c['pathID']]['data'] for c in effect['transforms'][0]['components']
                     if c['type']=='MonoBehaviour' and 'overrideDuration' in records[c['pathID']]['data']]
        require(len(controllers)==1,'Original H17 effect controller missing or ambiguous')
        controller=controllers[0];duration_override=float(controller['duration']) if controller['overrideDuration'] else None
        transforms={};active={};tracks=[]
        for transform in effect['transforms']:
            parent=transform['parentPathID'];local=matrix(transform['position'],transform['rotation'],transform['scale'])
            world=transforms[parent]@local if parent else local;transforms[transform['pathID']]=world
            references={c['type']:c['pathID'] for c in transform['components']}
            if 'ParticleSystem' not in references:continue
            identity=references['ParticleSystem'];source=records[identity]['data']
            renderer=records[references['ParticleSystemRenderer']]['data']
            game_object=assets.local[int(source['m_GameObject']['m_PathID'])].read()
            if not renderer['m_Enabled'] or not game_object.m_IsActive:continue
            for module in ('NoiseModule','ExternalForcesModule','SubModule','TrailModule','ForceModule'):
                if source[module]['enabled']:
                    issues.append(dict(effect=name,emitter=transform['name'],sourcePathID=identity,module=module,
                        status='Original module retained; dedicated engine behavior adapter required'))
            if renderer['m_RenderMode']==5:continue
            require(renderer['m_Materials'],'Source particle has no material')
            material=assets.material(renderer['m_Materials'][0]);mat=assets.materials[material]
            geometry=assets.geometry(renderer['m_Mesh']) if renderer['m_RenderMode']==4 else None
            if geometry is None and (renderer['m_RenderAlignment']==2 or renderer['m_RenderMode']==2):
                geometry=dict(positions=[-.5,-.5,0,.5,-.5,0,.5,.5,0,-.5,.5,0],normals=[0,0,-1]*4,
                    uv=[0,1,1,1,1,0,0,0],indices=[0,2,1,0,3,2])
            if cached is not None:continue
            schedule=emission_schedule(source,identity)
            speed=source['simulationSpeed'];prewarm=source['lengthInSec']/speed if source['prewarm'] and source['looping'] else 0.
            start_delay=minmax(source['startDelay'],0,random.Random(seed(identity,'delay')).random())/speed
            for particle,birth,period in schedule:
                data,receipt=sample_particle(source,renderer,world,transform['scale'],particle,project_gravity=assets.gravity)
                delay=start_delay+birth/speed-prewarm
                occurrences=[]
                if delay<0:
                    clipped=clip_begin(data,-delay)
                    if clipped is not None:occurrences.append((0.,None,clipped))
                    if period is not None:occurrences.append((delay+period/speed,period/speed,data))
                else:occurrences.append((delay,None if period is None else period/speed,data))
                for delay,repeat,samples in occurrences:
                    require(delay>=0,'Source prewarm exceeded one particle repeat period')
                    floats=mat['floats'];blend=(floats.get('_Blend1',floats.get('_SrcBlend',1)),floats.get('_Blend2',floats.get('_DstBlend',0)))
                    base=dict(name=transform['name']+'_'+identity+'_'+str(particle.index)+'_'+str(len(tracks)),
                        layer=int(game_object.m_Layer),material=material,texture=mat['textures']['_MainTex']['file'],
                        blend='add' if blend[1]==1 else 'alpha',wrapS=mat['textures']['_MainTex']['wrapS'],
                        wrapT=mat['textures']['_MainTex']['wrapT'],multiplyTextureAlpha=blend[0]==5,
                        overlay=False,sortingOrder=int(renderer['m_SortingOrder']),delay=round(delay,7),
                        duration=samples['frames'][-1][0],vertexStreams=renderer['m_VertexStreams'],
                        sourceRenderMode=renderer['m_RenderMode'],sourceRenderAlignment=renderer['m_RenderAlignment'],
                        sourceSimulationSpace=source['moveWithTransform'],sourceParticleSystem=identity,
                        sourceBlend=list(blend),sourceCull=int(floats.get('_Cull',0)),
                        sourceWritesDepth=bool(floats.get('_ZWrite',0)),**samples)
                    base['stableRandom']=[particle.r('stableRandom'+str(i)) for i in range(4)]
                    if repeat is not None:base['loopPeriod']=round(repeat,7)
                    if geometry is not None:base['geometry']=geometry
                    else:base.pop('orientations');base.pop('depthScales')
                    tracks.append(base)
                audit.append(dict(effect=name,emitter=transform['name'],sourcePathID=identity,capacity=source['InitialModule']['maxNumParticles'],
                    sourceEmitterPeriod=source['lengthInSec'],simulationSpeed=speed,sourcePrewarm=source['prewarm'],
                    material=material,**receipt))
        if cached is not None:
            effects[name]=cached['effect'];audit.extend(cached['particles'])
            print(json.dumps(dict(effect=name,tracks=len(cached['effect']['tracks']),samplingCacheVerified=True)),flush=True)
            continue
        if not tracks:continue
        if duration_override is not None:
            tracks=[clip_end(track,round(duration_override-track['delay'],7)) for track in tracks if track['delay']<duration_override-1e-7]
        duration=duration_override if duration_override is not None else max(t['delay']+t['duration'] for t in tracks)
        effects[name]=dict(sourceName=effect['sourcePath'],duration=round(duration,7),tracks=tracks,
            sourceDurationOverride=duration_override,sourceController={k:v for k,v in controller.items()
                if k not in ('m_GameObject','m_Script','m_Name','m_Enabled')})
        write_private(cache_file,json.dumps(dict(converterSHA256=cache_identity,
            sourceBundleSHA256=inventory['sourceBundleSHA256'],effect=effects[name],particles=audit[first_audit:]),
            separators=(',',':'),allow_nan=False).encode())
        print(json.dumps(dict(effect=name,tracks=len(tracks),samples=sum(len(t['frames']) for t in tracks),duration=duration)),flush=True)
    document=dict(version=1,profileID='sun_triad',characterSHA256=hashlib.sha256(args.character.read_bytes()).hexdigest(),
        sourceConfigurationSHA256=hashlib.sha256(args.source_configuration.read_bytes()).hexdigest(),sampleRate=60,
        worldUnitsPerSourceUnit=.01,evidence=[
            'Original H17 ParticleSystem and ParticleSystemRenderer parameters, not substitute effects.',
            'Original meshes preserve three-dimensional positions, normals, source UVs, vertex colors and triangle topology.',
            'Original material keyword variants are matched to authenticated compiled GLES shader programs.',
            'A repeatable random realization is sampled; the original automatic random seed varies between game runs.',
            'Original emission capacity is enforced before a verified periodic capacity state is folded into recurring tracks.',
            'Prewarm keeps the already aged particles; long-lived static trees retain their original 10000-second lifetime.',
            'Hermite and weighted Bezier curves, separate color/alpha gradient keys, original particle CustomData and texture frames are sampled.',
            'The private provenance identifies engine modules still requiring dedicated adapters; this is not a claim of complete Unity runtime parity.'],
        files=sorted(assets.files.values(),key=lambda x:x['name']),materials=assets.materials,effects=effects,bindings=[],markers=[])
    raw=json.dumps(document,separators=(',',':'),allow_nan=False).encode()
    compressed=gzip.compress(raw,mtime=0)
    require(len(raw)<=256_000_000 and len(compressed)<=32_000_000,'Source effect document exceeds bounded decompression size')
    write_private(output/'SF3_H17_Effects.json',raw)
    write_private(output/'SF3_H17_Effects.json.gz',compressed)
    write_private(output/'h17-particle-sampling-provenance-private.json',json.dumps(dict(
        sourceBundleSHA256=inventory['sourceBundleSHA256'],candidateOnly=True,engineParityVerified=False,
        sourceObjects=assets.audit,projectColorSpaceEvidence=assets.color_space,projectPhysicsQualityEvidence=assets.physics_quality,
        particles=audit,unadaptedModules=issues),indent=2,allow_nan=False).encode())
    print(json.dumps(dict(file='SF3_H17_Effects.json',bytes=len(raw),sha256=hashlib.sha256(raw).hexdigest(),
        compressedBytes=len(compressed),compressedSHA256=hashlib.sha256(compressed).hexdigest(),
        effects=len(effects),materials=len(assets.materials),textures=len(assets.files),
        tracks=sum(len(e['tracks']) for e in effects.values()),samples=sum(len(t['frames']) for e in effects.values() for t in e['tracks']),
        unadaptedModuleInstances=len(issues))))


if __name__=='__main__':main()
