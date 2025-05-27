const std = @import("std");
const kwatcher = @import("kwatcher");
const kwcr = kwatcher.protocol.client_registration;

const ClientRegistry = @import("kwatcher-client").Registry;
const MetricsBuffer = @import("kwatcher-client").MetricsBuffer;

pub fn @"reply amq.direct/client.announce"(
    client: kwatcher.protocol.client_registration.schema.Client.Announce.V1,
    reg: *ClientRegistry,
    metrics_buffer: *MetricsBuffer,
) !kwcr.schema.Client.Ack.V1 {
    const id = try reg.add(client);
    // Preallocate space for the metrics of the client.
    try metrics_buffer.ensure(reg.clients.size);
    return .{
        .client = client.client,
        .id = id,
    };
}

pub fn @"publish:requestReannounce amq.topic/client.requests.reannounce"(
    reg: *ClientRegistry,
) kwatcher.schema.Message(kwcr.schema.Client.Reannounce.Request.V1) {
    reg.ready = true;
    return .{
        .schema = .{},
        .options = .{
            .reply_to = "client.announce",
        },
    };
}

// @deprecated This is a legacy path. Prefer to send a Metrics.V2() with an explicit client_id
// TODO: Add the V2 path after the client library has support for schema-based routing on the same
// route.
pub fn @"consume amq.direct/metrics/metrics"(
    metrics: kwatcher.schema.Metrics.V1(),
    reg: *ClientRegistry,
    metrics_buffer: *MetricsBuffer,
) !void {
    // If the client isn't registered with us then we don't want it. These metrics likely belong to another consumer.
    const client_id = reg.lookup(metrics.client.name, metrics.user.hostname) orelse return error.Reject;
    try metrics_buffer.track(client_id, metrics.metrics);
}

pub fn @"consume amq.direct/client.heartbeat"(
    client: kwcr.schema.Client.Heartbeat.V1,
    reg: *ClientRegistry,
) !void {
    try reg.bump(client);
}
