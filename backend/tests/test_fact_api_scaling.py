import unittest


class ScalingPolicyTests(unittest.TestCase):
    def policy(self):
        from app.modules.facturacion.scaling import ScalingPolicy
        return ScalingPolicy(minimum=1,maximum=4,jobs_per_worker=4,grow_seconds=10,idle_seconds=60)

    def test_backlog_grows_with_a_hard_limit(self):
        policy=self.policy()
        self.assertEqual(policy.decide(1,ready=30,busy=1,oldest=2,now=0),4)
        self.assertEqual(policy.decide(4,ready=300,busy=4,oldest=200,now=20),4)

    def test_cooldown_prevents_rapid_repeated_growth(self):
        policy=self.policy()
        self.assertEqual(policy.decide(1,ready=8,busy=1,oldest=1,now=0),3)
        self.assertEqual(policy.decide(3,ready=50,busy=3,oldest=1,now=1),3)
        self.assertEqual(policy.decide(3,ready=50,busy=3,oldest=1,now=11),4)

    def test_waiting_work_can_get_help_even_with_a_small_queue(self):
        policy=self.policy()
        self.assertEqual(policy.decide(1,ready=1,busy=1,oldest=20,now=0),2)

    def test_idle_period_shrinks_one_worker_and_never_below_minimum(self):
        policy=self.policy()
        self.assertEqual(policy.decide(4,ready=0,busy=0,oldest=0,now=0),4)
        self.assertEqual(policy.decide(4,ready=0,busy=0,oldest=0,now=61),3)
        self.assertEqual(policy.decide(3,ready=0,busy=0,oldest=0,now=62),3)
        self.assertEqual(policy.decide(3,ready=0,busy=1,oldest=0,now=130),3)
        self.assertEqual(policy.decide(1,ready=0,busy=0,oldest=0,now=500),1)

    def test_outage_never_causes_more_workers(self):
        policy=self.policy()
        self.assertEqual(policy.decide(2,ready=100,busy=0,oldest=90,now=0,blocked=True),2)
        self.assertEqual(policy.decide(2,ready=100,busy=0,oldest=90,now=20,unhealthy=True),2)

    def test_invalid_limits_are_rejected(self):
        from app.modules.facturacion.scaling import ScalingPolicy
        for low,high in ((0,4),(3,2),(1,5)):
            with self.subTest(low=low,high=high),self.assertRaises(ValueError):
                ScalingPolicy(minimum=low,maximum=high)

    def test_stop_file_retires_only_at_a_work_boundary(self):
        from app.modules.facturacion.scaling import worker_loop
        from tempfile import TemporaryDirectory
        from pathlib import Path
        with TemporaryDirectory() as folder:
            stop=Path(folder)/'retire'
            calls=[]
            def process():
                calls.append('started');stop.touch();calls.append('finished');return True
            worker_loop(process,stop_file=stop,sleep=lambda _:None)
            self.assertEqual(calls,['started','finished'])


class SupervisorLifecycleTests(unittest.TestCase):
    def test_scales_up_and_retires_without_terminating_a_process(self):
        from app.modules.facturacion.supervisor import Supervisor
        from app.modules.facturacion.scaling import ScalingPolicy
        from tempfile import TemporaryDirectory
        class Process:
            def __init__(self,pid):self.pid=pid;self.exit=None
            def poll(self):return self.exit
        created=[];now=[0]
        def spawn(*args,**kwargs):
            process=Process(len(created)+1);created.append(process);return process
        with TemporaryDirectory() as folder:
            manager=Supervisor(folder,ScalingPolicy(),clock=lambda:now[0],spawn=spawn)
            busy={'ready':30,'busy':0,'oldest':0,'blocked':False,'unhealthy':False}
            idle={**busy,'ready':0}
            self.assertEqual(manager.tick(busy),1)
            now[0]=11
            self.assertEqual(manager.tick(busy),4)
            self.assertEqual(len(created),4)
            now[0]=12;manager.tick(idle)
            now[0]=73;self.assertEqual(manager.tick(idle),3)
            self.assertTrue(manager.children[-1].stop.exists())
            self.assertEqual(len(manager.children),4)  # Still allowed to finish.
            created[-1].exit=0
            now[0]=74;manager.tick(idle)
            self.assertEqual(len(manager.children),3)
            for process in created:process.exit=0
            manager.reap()
