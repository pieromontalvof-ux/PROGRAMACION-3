"""Autoscaling policy and graceful work-boundary retirement, independent of HTTP."""
from dataclasses import dataclass
from math import ceil
from pathlib import Path
import time


@dataclass
class ScalingPolicy:
    minimum: int = 1
    maximum: int = 4
    jobs_per_worker: int = 4
    grow_seconds: float = 10
    idle_seconds: float = 60
    wait_seconds: float = 15
    last_growth: float | None = None
    idle_since: float | None = None

    def __post_init__(self):
        if not 1<=self.minimum<=self.maximum<=4 or self.jobs_per_worker<1:
            raise ValueError('Workers: mínimo 1, máximo 4; carga por worker positiva.')
        if min(self.grow_seconds,self.idle_seconds,self.wait_seconds)<=0:
            raise ValueError('Los intervalos deben ser positivos.')

    def decide(self,current,*,ready,busy,oldest,now,blocked=False,unhealthy=False):
        if current<self.minimum:
            return self.minimum
        if ready==0 and busy==0:
            if self.idle_since is None:self.idle_since=now
            if now-self.idle_since>=self.idle_seconds and current>self.minimum:
                self.idle_since=now
                return current-1
            return current
        self.idle_since=None
        if blocked or unhealthy:
            return current
        desired=max(self.minimum,min(self.maximum,ceil((ready+busy)/self.jobs_per_worker)))
        if ready>0 and oldest>=self.wait_seconds:
            desired=min(self.maximum,max(desired,current+1))
        if desired>current and (self.last_growth is None or now-self.last_growth>=self.grow_seconds):
            self.last_growth=now
            return desired
        return current


def worker_loop(process,*,stop_file=None,sleep=time.sleep,once=False,should_stop=lambda:False):
    stop=Path(stop_file) if stop_file else None
    while not (stop and stop.exists()) and not should_stop():
        worked=process()  # Finish the current operation before checking retirement.
        if once:return
        if not worked and not (stop and stop.exists()):sleep(2)
