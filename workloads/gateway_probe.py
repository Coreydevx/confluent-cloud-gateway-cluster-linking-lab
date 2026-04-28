#!/usr/bin/env python3
import argparse
import json
import signal
import threading
import time
from collections import Counter
from uuid import uuid4

from confluent_kafka import Consumer, KafkaException, Producer


def config(args):
    return {
        "bootstrap.servers": args.bootstrap,
        "security.protocol": "SASL_PLAINTEXT",
        "sasl.mechanism": "PLAIN",
        "sasl.username": args.user,
        "sasl.password": args.password,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--bootstrap", default="localhost:19092")
    parser.add_argument("--user", default="labclient")
    parser.add_argument("--password", default="lab-password")
    parser.add_argument("--topic", default="ap.orders")
    parser.add_argument("--group", default="cg-ap")
    parser.add_argument("--seconds", type=int, default=60)
    parser.add_argument("--rate", type=float, default=20.0)
    args = parser.parse_args()

    stop = threading.Event()
    produced = Counter()
    consumed = []
    foreign = 0
    errors = []
    run_id = uuid4().hex

    def on_signal(_signum, _frame):
        stop.set()

    signal.signal(signal.SIGINT, on_signal)
    signal.signal(signal.SIGTERM, on_signal)

    def produce_loop():
        producer = Producer(config(args) | {"client.id": "gateway-probe-producer"})
        seq = 0
        interval = 1.0 / args.rate if args.rate > 0 else 0.0
        while not stop.is_set():
            value = {"run_id": run_id, "seq": seq, "ts": time.time()}
            producer.produce(args.topic, key=str(seq), value=json.dumps(value))
            produced[seq] += 1
            seq += 1
            producer.poll(0)
            if interval:
                time.sleep(interval)
        producer.flush(10)

    def consume_loop():
        nonlocal foreign
        consumer = Consumer(
            config(args)
            | {
                "group.id": args.group,
                "client.id": "gateway-probe-consumer",
                "auto.offset.reset": "earliest",
                "enable.auto.commit": True,
                "auto.commit.interval.ms": 1000,
            }
        )
        consumer.subscribe([args.topic])
        try:
            while not stop.is_set():
                msg = consumer.poll(1.0)
                if msg is None:
                    continue
                if msg.error():
                    errors.append(str(msg.error()))
                    continue
                try:
                    payload = json.loads(msg.value().decode("utf-8"))
                    if payload.get("run_id") == run_id:
                        consumed.append(payload["seq"])
                    else:
                        foreign += 1
                except Exception as exc:
                    errors.append(repr(exc))
        finally:
            consumer.close()

    producer_thread = threading.Thread(target=produce_loop, daemon=True)
    consumer_thread = threading.Thread(target=consume_loop, daemon=True)
    producer_thread.start()
    consumer_thread.start()

    deadline = time.time() + args.seconds
    while time.time() < deadline and not stop.is_set():
        time.sleep(1)
    stop.set()
    producer_thread.join()
    consumer_thread.join()

    counts = Counter(consumed)
    duplicates = sum(count - 1 for count in counts.values() if count > 1)
    missing = sorted(set(produced.keys()) - set(consumed))
    report = {
        "topic": args.topic,
        "group": args.group,
        "run_id": run_id,
        "produced": sum(produced.values()),
        "consumed": len(consumed),
        "foreign_consumed": foreign,
        "duplicates": duplicates,
        "missing_count": len(missing),
        "first_missing": missing[:20],
        "errors": errors[-20:],
    }
    print(json.dumps(report, indent=2, sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except KafkaException as exc:
        raise SystemExit(str(exc))
