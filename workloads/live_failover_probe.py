#!/usr/bin/env python3
import argparse
import json
import signal
import sys
import threading
import time
from collections import Counter
from uuid import uuid4

from confluent_kafka import Consumer, KafkaException, Producer


def kafka_config(args):
    return {
        "bootstrap.servers": args.bootstrap,
        "security.protocol": "SASL_PLAINTEXT",
        "sasl.mechanism": "PLAIN",
        "sasl.username": args.user,
        "sasl.password": args.password,
    }


def fmt_int(value):
    return f"{value:,}"


def main():
    parser = argparse.ArgumentParser(
        description="Continuously produce and consume through Gateway while you perform a failover."
    )
    parser.add_argument("--bootstrap", default="localhost:19092")
    parser.add_argument("--user", default="labclient")
    parser.add_argument("--password", default="lab-password")
    parser.add_argument("--topic", default="ap.orders")
    parser.add_argument("--group", default="cg-live-failover")
    parser.add_argument("--rate", type=float, default=10.0, help="Messages per second to produce.")
    parser.add_argument("--interval", type=float, default=1.0, help="Seconds between status lines.")
    parser.add_argument("--seconds", type=int, default=0, help="Stop after N seconds. Default is run until Ctrl-C.")
    parser.add_argument("--format", choices=["table", "json"], default="table")
    args = parser.parse_args()

    stop = threading.Event()
    lock = threading.Lock()
    run_id = uuid4().hex
    first_ts = time.time()

    produced_attempted = 0
    produced_acked = set()
    produce_failed = 0
    consumed = []
    foreign_consumed = 0
    consume_errors = []
    produce_errors = []
    highest_seq = -1

    def on_signal(_signum, _frame):
        stop.set()

    signal.signal(signal.SIGINT, on_signal)
    signal.signal(signal.SIGTERM, on_signal)

    def delivery_report(err, msg):
        nonlocal produce_failed
        try:
            seq = int(msg.key().decode("utf-8"))
        except Exception:
            seq = None
        with lock:
            if err is not None:
                produce_failed += 1
                produce_errors.append(str(err))
            elif seq is not None:
                produced_acked.add(seq)

    def produce_loop():
        nonlocal produced_attempted, highest_seq, produce_failed
        producer = Producer(
            kafka_config(args)
            | {
                "client.id": "live-failover-producer",
                "request.timeout.ms": 10000,
                "message.timeout.ms": 30000,
                "reconnect.backoff.ms": 250,
                "reconnect.backoff.max.ms": 3000,
            }
        )
        seq = 0
        interval = 1.0 / args.rate if args.rate > 0 else 0.0
        while not stop.is_set():
            payload = {
                "run_id": run_id,
                "seq": seq,
                "created_at": time.time(),
                "note": "live failover probe",
            }
            try:
                producer.produce(args.topic, key=str(seq), value=json.dumps(payload), callback=delivery_report)
                with lock:
                    produced_attempted += 1
                    highest_seq = seq
                seq += 1
            except BufferError as exc:
                with lock:
                    produce_failed += 1
                    produce_errors.append(f"producer buffer full: {exc}")
                producer.poll(1.0)
            except KafkaException as exc:
                with lock:
                    produce_failed += 1
                    produce_errors.append(str(exc))
                time.sleep(1.0)
            producer.poll(0)
            if interval:
                time.sleep(interval)
        producer.flush(15)

    def consume_loop():
        nonlocal foreign_consumed
        consumer = Consumer(
            kafka_config(args)
            | {
                "group.id": args.group,
                "client.id": "live-failover-consumer",
                "auto.offset.reset": "earliest",
                "enable.auto.commit": True,
                "auto.commit.interval.ms": 1000,
                "session.timeout.ms": 10000,
                "reconnect.backoff.ms": 250,
                "reconnect.backoff.max.ms": 3000,
            }
        )
        consumer.subscribe([args.topic])
        try:
            while not stop.is_set():
                msg = consumer.poll(1.0)
                if msg is None:
                    continue
                if msg.error():
                    with lock:
                        consume_errors.append(str(msg.error()))
                    continue
                try:
                    payload = json.loads(msg.value().decode("utf-8"))
                    with lock:
                        if payload.get("run_id") == run_id:
                            consumed.append(payload["seq"])
                        else:
                            foreign_consumed += 1
                except Exception as exc:
                    with lock:
                        consume_errors.append(repr(exc))
        finally:
            consumer.close()

    def snapshot():
        with lock:
            counts = Counter(consumed)
            duplicate_records = sum(count - 1 for count in counts.values() if count > 1)
            consumed_unique = set(counts.keys())
            missing = sorted(produced_acked - consumed_unique)
            lag = max(len(produced_acked) - len(consumed_unique), 0)
            return {
                "elapsed_s": round(time.time() - first_ts, 1),
                "run_id": run_id,
                "topic": args.topic,
                "group": args.group,
                "bootstrap": args.bootstrap,
                "attempted": produced_attempted,
                "acked": len(produced_acked),
                "highest_seq": highest_seq,
                "consumed": len(consumed),
                "consumed_unique": len(consumed_unique),
                "duplicates": duplicate_records,
                "missing_count": len(missing),
                "first_missing": missing[:10],
                "foreign_consumed": foreign_consumed,
                "produce_failed": produce_failed,
                "produce_errors": produce_errors[-5:],
                "consume_errors": consume_errors[-5:],
                "approx_current_lag": lag,
            }

    producer_thread = threading.Thread(target=produce_loop, daemon=True)
    consumer_thread = threading.Thread(target=consume_loop, daemon=True)
    producer_thread.start()
    consumer_thread.start()

    print(f"run_id={run_id}", flush=True)
    print("Start your failover in another terminal. Press Ctrl-C here to stop.", flush=True)
    if args.format == "table":
        print(
            "elapsed | attempted | acked | consumed | lag | missing | dupes | prod_err | cons_err | foreign",
            flush=True,
        )

    deadline = time.time() + args.seconds if args.seconds > 0 else None
    try:
        while not stop.is_set():
            if deadline and time.time() >= deadline:
                stop.set()
                break
            report = snapshot()
            if args.format == "json":
                print(json.dumps(report, sort_keys=True), flush=True)
            else:
                print(
                    " | ".join(
                        [
                            f"{report['elapsed_s']:>7.1f}s",
                            f"{fmt_int(report['attempted']):>9}",
                            f"{fmt_int(report['acked']):>5}",
                            f"{fmt_int(report['consumed_unique']):>8}",
                            f"{fmt_int(report['approx_current_lag']):>3}",
                            f"{fmt_int(report['missing_count']):>7}",
                            f"{fmt_int(report['duplicates']):>5}",
                            f"{fmt_int(report['produce_failed']):>8}",
                            f"{fmt_int(len(report['consume_errors'])):>8}",
                            f"{fmt_int(report['foreign_consumed']):>7}",
                        ]
                    ),
                    flush=True,
                )
            time.sleep(args.interval)
    finally:
        stop.set()
        producer_thread.join()
        consumer_thread.join()
        final = snapshot()
        print("\nFinal report:")
        print(json.dumps(final, indent=2, sort_keys=True))

        if final["missing_count"] or final["duplicates"] or final["produce_failed"] or final["consume_errors"]:
            print(
                "\nInterpretation: non-zero missing, duplicate, or error counts are expected if writes continue "
                "during the cutoff window or clients reconnect while Gateway is being switched.",
                file=sys.stderr,
            )


if __name__ == "__main__":
    try:
        main()
    except KafkaException as exc:
        raise SystemExit(str(exc))

