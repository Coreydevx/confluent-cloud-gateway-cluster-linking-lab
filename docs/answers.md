# Answers

## Gateway + Cluster Linking Functionality

Gateway is transparent at the Kafka client endpoint level. Clients connect to a stable virtual bootstrap address and Gateway maps that route to a streaming domain, which represents a Kafka cluster. Switching a route from one streaming domain to another can move clients to a different backing cluster without changing the client bootstrap address.

That transparency has boundaries:

- Kafka clients will see a disconnect/reconnect during Gateway restart or route redeploy.
- Authorization and credentials still must work on the target cluster. This lab uses Gateway auth swapping so the client credential stays stable while Gateway swaps to the right Confluent Cloud API key.
- Data continuity is provided by Cluster Linking, not Gateway.
- Gateway does not currently provide per-topic routing inside one route. Splitting a single logical cluster into multiple clusters can be demonstrated with multiple Gateway routes, but not as one bootstrap endpoint that sends different topic names to different clusters.

## Splitting One Cluster Into Multiple Clusters

Per-topic routing would be the perfect match for a transparent “split one cluster into many” migration, but current Gateway configuration maps each route to one streaming domain. The supported pattern is:

- create one route per target cluster, for example `localhost:19192` for east and `localhost:19292` for west
- migrate clients by changing the route they use, or by changing a stable route to a new backing streaming domain
- use Cluster Linking to pre-copy topics before switching clients

So the split is operationally useful but not fully transparent if a single client must produce and consume topics that now live on multiple clusters through one unchanged bootstrap endpoint.

## Active/Passive Failover

The active/passive lab uses east as primary and west as DR:

- producers and consumers use `localhost:19092`
- Gateway route initially points to east
- Cluster Linking mirrors `ap.orders` from east to west
- consumer offsets are synced from east to west for mirrored topics
- failover promotes or fails over the mirror topic on west, updates the Gateway route, and updates the Gateway secret-store entry to use west credentials

Expected reprocessing depends on the last committed consumer offset and the Cluster Linking offset sync interval. With clean cutoff, committed offsets, and low mirror lag, duplicates should be small. If producers continue after the last mirrored offset, those records are stranded on the source until recovery. If consumers process records without committing before failover, those records can be reprocessed on the DR cluster.

Example lab result from April 27, 2026:

- East primary: `lkc-o8yqrx`; west DR: `lkc-vg5rd5`
- Gateway stable route: `localhost:19092`
- Before failover, `ap.orders` mirror lag on west was `0` on all six partitions.
- The mirror was failed over on west; after failover the mirror status is `STOPPED`, which is expected because it is now a regular writable topic on west.
- The Gateway route was switched from east to west without changing the client bootstrap address.
- Pre-failover probe: produced `99`, consumed `99`, duplicates `0`, missing `0`.
- Post-failover probe with the same consumer group: produced `99`, consumed `99`, duplicates `0`, missing `0`, foreign/reprocessed current-run records `0`.

## Active/Active With Cluster Linking

Active/active is different from active/passive because both clusters accept local writes. The recommended shape is:

- each cluster has a writable topic with the same base name, for example `aa.orders`
- each cluster mirrors the other cluster's topic with an origin prefix, for example `east.aa.orders` and `west.aa.orders`
- consumers in a region consume both the local writable topic and the remote mirror topic when they need the global stream
- consumer group offset sync filters are directional to avoid offset cycles

If one region goes down, affected clients move to the surviving region. Mirror topics should not be promoted in the normal active/active failover path; the surviving region already has writable local topics. After moving a consumer group, update offset sync filters so stale offsets from the failed side do not overwrite the now-active group offsets.

For consumer group naming, use different regional group names when both regions are actively processing the same logical work and duplicate side effects are unsafe. Same group names can be used only when the application design makes ownership unambiguous or processing is idempotent.

Example lab result from April 27, 2026:

- East direct Gateway route: `localhost:19192`
- West direct Gateway route: `localhost:19292`
- East writable topic: `aa.orders`; west mirror of east: `east.aa.orders`
- West writable topic: `aa.orders`; east mirror of west: `west.aa.orders`
- East-route smoke test: produced `30`, consumed `30`, duplicates `0`, missing `0`.
- West-route smoke test: produced `30`, consumed `30`, duplicates `0`, missing `0`.
- Both active-active mirrors are `ACTIVE` with max per-partition mirror lag `0`.
