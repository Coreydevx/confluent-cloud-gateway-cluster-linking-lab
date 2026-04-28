# Test Plan

Use this plan to reproduce and evaluate the original questions this lab was built to answer:

- Can Gateway help split a single cluster into multiple clusters?
- How transparent is the split?
- What happens during active/passive failover under a real workload?
- How much consumer reprocessing should be expected depending on cutoff?
- How does active/active with Cluster Linking behave if one region goes down?
- Should active/active use different consumer groups per region?

## Before Running Tests

From the repo root:

```bash
. .lab.env
docker ps
confluent kafka mirror list --cluster "$WEST_CLUSTER_ID"
confluent kafka mirror list --cluster "$EAST_CLUSTER_ID"
```

Expected state before active/passive failover:

- Gateway is running.
- `ap.orders` is an active mirror on west.
- `east.aa.orders` is active on west.
- `west.aa.orders` is active on east.

If `ap.orders` has already been failed over, recreate the lab or use a fresh topic/link pair before repeating the active/passive test.

## Test 1: Split One Cluster Into Multiple Clusters

Goal: Determine whether Gateway can route individual topics from one client bootstrap endpoint to different backing clusters.

### Steps

1. Confirm the direct east route works:

   ```bash
   . .venv/bin/activate
   python workloads/gateway_probe.py --bootstrap localhost:19192 --topic aa.orders --group split-east --seconds 30 --rate 5
   ```

2. Confirm the direct west route works:

   ```bash
   python workloads/gateway_probe.py --bootstrap localhost:19292 --topic aa.orders --group split-west --seconds 30 --rate 5
   ```

3. Confirm the stable route can point to one cluster at a time:

   ```bash
   ./scripts/04_render_gateway.sh east
   ./scripts/05_start_gateway.sh
   docker logs --tail 80 gateway-lab | grep switchover-route
   ```

4. Switch the stable route:

   ```bash
   ./scripts/06_switch_route.sh west
   docker logs --tail 80 gateway-lab | grep switchover-route
   ```

### Expected Result

Gateway can split traffic by route endpoint:

- `localhost:19192` routes to east
- `localhost:19292` routes to west
- `localhost:19092` can be switched from east to west

Gateway does not currently expose a route configuration that routes individual topic names inside one bootstrap endpoint to different clusters. A topic-level split behind one unchanged bootstrap endpoint is not reproduced by this lab because current Gateway routes map endpoints to streaming domains, and streaming domains represent Kafka clusters.

## Test 2: Active/Passive Failover Under Workload

Goal: Measure what happens when `ap.orders` moves from east to west while clients use the same Gateway bootstrap endpoint.

### Option A: Clean Cutoff

Use this option to minimize duplicates and missing records.

1. Start Gateway pointing east:

   ```bash
   ./scripts/04_render_gateway.sh east
   ./scripts/05_start_gateway.sh
   ```

2. Run a one-shot baseline workload:

   ```bash
   . .venv/bin/activate
   python workloads/gateway_probe.py --bootstrap localhost:19092 --topic ap.orders --group ap-clean-cutoff --seconds 60 --rate 10
   ```

3. Check mirror lag:

   ```bash
   confluent kafka mirror describe ap.orders --cluster "$WEST_CLUSTER_ID" --link gateway-lab-ap
   ```

4. When lag is acceptable, fail over west:

   ```bash
   confluent kafka mirror failover ap.orders --cluster "$WEST_CLUSTER_ID" --link gateway-lab-ap
   ```

5. Switch Gateway to west:

   ```bash
   ./scripts/06_switch_route.sh west
   ```

6. Run the workload again through the same bootstrap:

   ```bash
   python workloads/gateway_probe.py --bootstrap localhost:19092 --topic ap.orders --group ap-clean-cutoff --seconds 60 --rate 10
   ```

### Option B: Live Workload During Cutover

Use this option to expose the cutoff tradeoff.

1. Start the live workload:

   ```bash
   . .venv/bin/activate
   python workloads/live_failover_probe.py --topic ap.orders --group ap-live-cutoff --rate 10
   ```

2. In another terminal, check mirror lag:

   ```bash
   . .lab.env
   confluent kafka mirror describe ap.orders --cluster "$WEST_CLUSTER_ID" --link gateway-lab-ap
   ```

3. Fail over the west mirror:

   ```bash
   confluent kafka mirror failover ap.orders --cluster "$WEST_CLUSTER_ID" --link gateway-lab-ap
   ```

4. Switch Gateway:

   ```bash
   ./scripts/06_switch_route.sh west
   ```

5. Watch the live probe output.

### How To Read The Live Probe

The live probe prints one line per second:

```text
elapsed | attempted | acked | consumed | lag | missing | dupes | prod_err | cons_err | foreign
```

- `attempted`: records the producer tried to send
- `acked`: records Kafka acknowledged
- `consumed`: unique records from this run consumed by the consumer
- `lag`: acknowledged records not yet consumed by this process
- `missing`: acknowledged records that have not been seen by the consumer
- `dupes`: duplicate records seen by the consumer
- `prod_err` and `cons_err`: client-side errors during disconnects or reconnects
- `foreign`: older records from previous runs

### Expected Result

With a clean cutoff and mirror lag at `0`, duplicates and missing records should be low or zero. If producers keep writing after the mirror cutoff but before Gateway moves to west, records can be accepted by east and not appear on west. That is the RPO behavior this test is meant to make visible.

Consumer reprocessing depends on:

- last committed consumer offset
- offset sync timing
- whether the consumer processed records before committing
- mirror lag at cutoff
- whether writes continued during the cutover window

## Test 3: Active/Active Behavior

Goal: Show that both regions can accept local writes while Cluster Linking mirrors each side into the other region.

### Steps

1. Produce and consume through east:

   ```bash
   . .venv/bin/activate
   python workloads/gateway_probe.py --bootstrap localhost:19192 --topic aa.orders --group aa-east --seconds 60 --rate 10
   ```

2. Produce and consume through west:

   ```bash
   python workloads/gateway_probe.py --bootstrap localhost:19292 --topic aa.orders --group aa-west --seconds 60 --rate 10
   ```

3. Check mirrors:

   ```bash
   . .lab.env
   confluent kafka mirror list --cluster "$WEST_CLUSTER_ID"
   confluent kafka mirror list --cluster "$EAST_CLUSTER_ID"
   ```

Expected mirrors:

- west has `east.aa.orders`
- east has `west.aa.orders`

### Expected Result

Both clusters can accept local writes to `aa.orders`. Each region receives the other region's writes on a prefixed mirror topic.

If one region goes down, the surviving region already has its own writable local topic. In a normal active/active design, you do not promote the remote mirror topic as the primary failover mechanism. Instead, move affected clients to the surviving region's writable topic and decide whether consumers should read:

- only the local writable topic, or
- the local writable topic plus remote prefixed mirror topics for global ordering/visibility needs

## Consumer Group Guidance For Active/Active

Use different regional consumer group IDs when both regions are actively processing the same logical workload and duplicate side effects would be harmful.

Example:

- `orders-processor-east`
- `orders-processor-west`

Use the same group ID only when your application design is explicitly safe for it, such as idempotent processing, clear topic ownership, or a coordinated failover process that prevents both regions from processing the same work at the same time.

## Summary Of What This Lab Proves

- Gateway can make cluster migration or DR switchover transparent at the bootstrap endpoint level.
- Gateway does not currently provide one-bootstrap, per-topic routing across clusters.
- Cluster Linking handles replicated data and offset sync; Gateway handles endpoint routing.
- Active/passive failover results depend heavily on cutoff discipline.
- Active/active is a different operating model from active/passive and usually benefits from region-specific consumer groups.

