from locust import User, task, events
from locust.exception import LocustError
import random
import time


__version__ = "1"


class LocustTest(User):
    @task
    def tick(self) -> None:
        w = random.random()*1000.0
        if w > 750:
            time.sleep(0.01)
            self._report_failure("random", "value", w, "too much!")
        else:
            time.sleep(1)
            self._report_success("random", "value", w)

    def _report_success(self, category, name, response_time):
        events.request.fire(
            request_type=category,
            name=name,
            response_time=response_time,
            response_length=0,
            exception=None
        )

    def _report_failure(self, category, name, response_time, msg):
        events.request.fire(
            request_type=category,
            name=name,
            response_time=response_time,
            response_length=0,
            exception=LocustError(msg)
        )
