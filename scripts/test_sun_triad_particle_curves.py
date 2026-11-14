import math, random, unittest
import numpy as np
from sun_triad_particle_curves import curve,minmax,gradient,birth_times,repeat_copies,euler_rotation
from sun_triad_particles import Particle,emission_schedule,clip_begin,clip_end,sample_particle


def key(time,value,slope=0,mode=0,in_weight=1/3,out_weight=1/3):
    return dict(time=time,value=value,inSlope=slope,outSlope=slope,weightedMode=mode,
                inWeight=in_weight,outWeight=out_weight)


def constant(value):
    return dict(minMaxState=0,scalar=value,minScalar=value,maxCurve={'m_Curve':[]},minCurve={'m_Curve':[]})


class ParticleCurveTests(unittest.TestCase):
    def test_hermite_curve_preserves_tangent_shape_and_endpoints(self):
        c={'m_Curve':[key(0,0,2),key(1,1,0)]}
        self.assertEqual(curve(c,-1),0);self.assertEqual(curve(c,2),1)
        self.assertAlmostEqual(curve(c,.5),.75)

    def test_weighted_curve_solves_time_instead_of_using_time_as_parameter(self):
        c={'m_Curve':[key(0,0,1,2,out_weight=.1),key(1,1,1,1,in_weight=.7)]}
        for time in [.1,.3,.7,.9]:self.assertAlmostEqual(curve(c,time),time,places=9)

    def test_step_tangent_and_two_curves_share_one_multiplier(self):
        c={'m_Curve':[key(0,2,float('inf')),key(1,4)]}
        self.assertEqual(curve(c,.999),2)
        v=dict(minMaxState=2,scalar=5,minScalar=999,
               minCurve={'m_Curve':[key(0,1)]},maxCurve={'m_Curve':[key(0,3)]})
        self.assertEqual(minmax(v,.5,.25),7.5)

    def test_color_and_alpha_use_independent_key_times(self):
        g=dict(m_Mode=0,m_NumColorKeys=2,m_NumAlphaKeys=2,ctime0=0,ctime1=65535,atime0=0,atime1=32768,
               key0=dict(r=0,g=1,b=0,a=0),key1=dict(r=1,g=0,b=0,a=1))
        value=gradient(g,.5)
        np.testing.assert_allclose(value[:3],[.5,.5,0]);self.assertAlmostEqual(value[3],.9999847412)

    def test_emission_accumulator_and_burst_do_not_drop_partial_ticks(self):
        e=dict(lengthInSec=1.,EmissionModule=dict(enabled=True,rateOverTime=constant(2.5),rateOverDistance=constant(0),
            m_Bursts=[dict(time=0,countCurve=constant(2),cycleCount=1,repeatInterval=.1,probability=1)]))
        np.testing.assert_allclose(birth_times(e,random.Random(1)),[0,0,.4,.8],atol=1e-9)

    def test_overlap_schedule_never_reuses_track_before_death(self):
        result=repeat_copies(1.2,.5)
        self.assertEqual(result,[(0.,1.5),(.5,1.5),(1.,1.5)])
        self.assertTrue(all(period>=1.2 for _,period in result))

    def test_rotation_basis_and_invalid_curves(self):
        np.testing.assert_allclose(euler_rotation([0,math.pi,0]),[0,1,0,0],atol=1e-10)
        with self.assertRaisesRegex(ValueError,'strictly ordered'):
            curve({'m_Curve':[key(0,0),key(0,1)]},.1)

    def test_capacity_schedule_finds_multiple_period_cycle_without_overlap(self):
        source=dict(lengthInSec=1.,looping=True,InitialModule=dict(startLifetime=constant(1.5),maxNumParticles=1),
            EmissionModule=dict(enabled=True,rateOverTime=constant(0),rateOverDistance=constant(0),
                m_Bursts=[dict(time=0,countCurve=constant(1),cycleCount=1,repeatInterval=.1,probability=1)]))
        schedule=emission_schedule(source,'synthetic')
        births=[]
        for particle,start,period in schedule:
            self.assertGreaterEqual(period,particle.life)
            while start<=10:
                births.append(start);start+=period
        np.testing.assert_allclose(sorted(births),[0,2,4,6,8,10])

    def test_source_capacity_truncates_large_burst_without_extra_geometry(self):
        source=dict(lengthInSec=.05,looping=False,InitialModule=dict(startLifetime=constant(1.5),maxNumParticles=1),
            EmissionModule=dict(enabled=True,rateOverTime=constant(9999),rateOverDistance=constant(0),
                m_Bursts=[dict(time=0,countCurve=constant(1111),cycleCount=1,repeatInterval=.1,probability=1)]))
        self.assertEqual(len(emission_schedule(source,'large-burst')),1)

    def test_prewarm_clips_an_existing_particle_without_restarting_color(self):
        data=dict(frames=[[0,0,0,0,1,1,0,0,0,0,0,0,0,1,1],[2,4,0,0,1,1,0,1,1,1,1,0,0,1,1]],
                  orientations=[[0,0,0,1],[0,0,0,1]],depthScales=[1,1],customData1=[[0]*4,[1]*4],customData2=[[0]*4,[0]*4])
        value=clip_begin(data,.5)
        self.assertEqual(value['frames'][0][0],0)
        self.assertEqual(value['frames'][0][1],1)
        self.assertEqual(value['frames'][0][7],.25)
        self.assertEqual(value['frames'][-1][0],1.5)

    def test_effect_duration_crops_all_custom_streams_at_one_exact_time(self):
        data=dict(frames=[[0,0,0,0,1,1,0,0,0,0,0,0,0,1,1],[2,4,0,0,1,1,0,1,1,1,1,0,0,1,1]],
                  orientations=[[0,0,0,1],[0,0,0,1]],depthScales=[1,3],customData1=[[0]*4,[1]*4],customData2=[[0]*4,[0]*4],duration=2)
        value=clip_end(data,.5)
        self.assertEqual(value['frames'][-1][0],.5)
        self.assertEqual(value['frames'][-1][1],1)
        self.assertEqual(value['customData1'][-1],[.25]*4)
        self.assertEqual(value['depthScales'][-1],1.5)
        self.assertEqual(value['duration'],.5)

    def test_gravity_uses_verified_project_source_units_before_scene_scaling(self):
        source=dict(lengthInSec=1,simulationSpeed=1,scalingMode=0,
            InitialModule=dict(startLifetime=constant(1),startSpeed=constant(0),startSize=constant(1),size3D=False,
                startRotationX=constant(0),startRotationY=constant(0),startRotation=constant(0),rotation3D=False,
                randomizeRotationDirection=0,gravityModifier=constant(1),
                startColor=dict(minMaxState=0,maxColor=dict(r=1,g=1,b=1,a=1))))
        for name in ('ShapeModule','RotationModule','VelocityModule','ClampVelocityModule','SizeModule','ColorModule','UVModule','CustomDataModule'):
            source[name]=dict(enabled=False)
        renderer=dict(m_RenderAlignment=0,m_RenderMode=0)
        with self.assertRaisesRegex(ValueError,'project gravity'):
            sample_particle(source,renderer,np.eye(4),[1,1,1],Particle(source,'source-gravity',0,0))
        result,_=sample_particle(source,renderer,np.eye(4),[1,1,1],Particle(source,'source-gravity',0,0),project_gravity=[0,-981,0])
        self.assertAlmostEqual(result['frames'][-1][2],-490.5,places=6)


if __name__=='__main__':unittest.main()
