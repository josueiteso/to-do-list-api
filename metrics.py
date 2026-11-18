import logging
import threading
from collections import Counter
from datetime import datetime, timezone
import boto3

log = logging.getLogger(__name__)

NAMESPACE = "TasksApp"
SERVICE = "tasks-app"


# acumula los contadores en la memoria y los envia a cloudwatch cada interval (default 60 s)
class MetricsPublisher:

    def __init__(self, region, interval=60, client=None):
        self.region = region
        self.interval = interval
        self._client = client
        self._lock = threading.Lock()
        self._counters = Counter()
        self._stop = threading.Event()

    def incr(self, name, value=1):
        with self._lock:
            self._counters[name] += value

    # vacia lo acumulado y lo devuelve en formato put_metric_data
    def drain(self):
        with self._lock:
            counters, self._counters = self._counters, Counter()

        now = datetime.now(timezone.utc)
        dims = [{"Name": "Service", "Value": SERVICE}]
        return [
            {
                "MetricName": name,
                "Dimensions": dims,
                "Timestamp": now,
                "Value": value,
                "Unit": "Count",
            }
            for name, value in counters.items()
        ]

    def flush(self):
        data = self.drain()
        if not data:
            return
        try:
            if self._client is None:
                self._client = boto3.client("cloudwatch", region_name=self.region)
            self._client.put_metric_data(Namespace=NAMESPACE, MetricData=data)
        except Exception as e:  # nunca debe tumbar la app
            log.warning("No se pudieron publicar métricas: %s", e)

    def start(self):
        def loop():
            while not self._stop.wait(self.interval):
                self.flush()

        threading.Thread(target=loop, daemon=True, name="metrics-publisher").start()
