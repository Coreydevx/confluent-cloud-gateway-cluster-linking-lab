# Customer Demo Runbook

Use this runbook when presenting the lab live.

## Goal

Show that clients can keep using one stable Kafka bootstrap endpoint while Gateway moves that endpoint from an east cluster to a west cluster. Cluster Linking handles data replication; Gateway handles the client endpoint switchover.

## Setup Check

From the repo root:

```bash
. .lab.env
docker ps
confluent kafka mirror list --cluster "$WEST_CLUSTER_ID"
```

Gateway should be running and `ap.orders` should be an active mirror on west before the failover.

If this lab has already been failed over, recreate the lab or use a new topic/link pair for the customer demo.

## Terminal Layout

Use three terminal panes.

### Pane 1: Live Workload

```bash
. .venv/bin/activate
python workloads/live_failover_probe.py --topic ap.orders --group customer-demo-live --rate 10
```

Explain the columns:

- `attempted`: records the producer tried to send
- `acked`: records Kafka acknowledged
- `consumed`: unique records from this run consumed by the consumer
- `lag`: acknowledged records not yet consumed by this process
- `missing`: acknowledged records that have not been seen by the consumer
- `dupes`: duplicate records seen by the consumer
- `prod_err` and `cons_err`: client-side errors during disconnects or reconnects
- `foreign`: older records from previous runs

### Pane 2: Mirror Health And Failover

```bash
. .lab.env
confluent kafka mirror describe ap.orders --cluster "$WEST_CLUSTER_ID" --link gateway-lab-ap
```

Point out partition mirror lag. If the lag is `0`, the DR topic is caught up at that moment.

Fail over the mirror:

```bash
confluent kafka mirror failover ap.orders --cluster "$WEST_CLUSTER_ID" --link gateway-lab-ap
```

### Pane 3: Gateway Route Switch

```bash
./scripts/06_switch_route.sh west
docker logs --tail 80 gateway-lab | grep switchover-route
```

Point out that `localhost:19092` now routes to the west cluster.

## Two Demo Variants

### Clean Cutover

Use this when you want the best possible result:

1. Pause or fence producers.
2. Wait for mirror lag to reach `0`.
3. Fail over `ap.orders` on west.
4. Switch Gateway to west.
5. Resume producers.

Expected result: low or zero duplicates and missing records, depending on the consumer commit timing.

### Live Cutover Under Writes

Use this when you want to show the tradeoff:

1. Keep `live_failover_probe.py` running.
2. Fail over the west mirror.
3. Switch Gateway to west.
4. Watch the probe.

Expected result: the probe may show errors, lag, or missing records if writes were accepted by east after the mirror cutoff and before Gateway switched to west. That is the realistic RPO conversation.

## Customer Talking Points

- Gateway is transparent at the bootstrap endpoint level.
- Cluster Linking is responsible for data continuity.
- Consumer offset sync reduces reprocessing, but the exact result depends on commit timing and cutoff discipline.
- If the business requires zero data loss, the runbook must include a producer pause/fence and a mirror-lag check before failover.
- Gateway does not currently route individual topics inside one route to different clusters.

## Topic-Based Routing Question

Gateway routes are listener endpoints mapped to streaming domains. A streaming domain is a logical Kafka cluster. The route configuration does not include a topic matcher, so a single route cannot say "send topic A to east and topic B to west."

You can create separate routes for separate clusters:

- `localhost:19192` routes to east
- `localhost:19292` routes to west

That is route-based split traffic, not topic-based routing behind one unchanged bootstrap. True topic-based routing would need the Gateway to inspect Kafka produce/fetch/metadata requests and choose an upstream cluster per topic while preserving consistent metadata, offsets, group coordination, transactions, admin APIs, and error semantics. Current Gateway does not expose that as a supported route configuration.

