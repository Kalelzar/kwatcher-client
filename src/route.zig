const std = @import("std");
const kwatcher = @import("kwatcher");

const ClientRegistry = @import("kwatcher-client").Registry;

pub fn @"reply amq.direct/client.announce"(
    client: kwatcher.protocol.client_registration.schema.Client.Announce.V1,
    reg: *ClientRegistry,
) !kwatcher.protocol.client_registration.schema.Client.Ack.V1 {
    const id = try reg.add(client);

    return .{
        .client = client.client,
        .id = id,
    };
}

pub fn @"publish:requestReannounce amq.topic/client.requests.reannounce"(
    reg: *ClientRegistry,
) kwatcher.schema.Message(kwatcher.protocol.client_registration.schema.Client.Reannounce.Request.V1) {
    reg.ready = true;
    return .{
        .schema = .{},
        .options = .{
            .reply_to = "client.announce",
        },
    };
}

pub fn @"publish:metrics amq.direct/metrics"(
    user_info: kwatcher.schema.UserInfo,
    client_info: kwatcher.schema.ClientInfo,
    arena: *kwatcher.mem.InternalArena,
    reg: *ClientRegistry,
) !kwatcher.schema.Metrics.V1() {
    const allocator = arena.allocator();
    var buf = std.ArrayListUnmanaged(u8){};
    try reg.update();
    try reg.writeMetrics(buf.writer(allocator));
    return .{
        .timestamp = std.time.microTimestamp(),
        .client = client_info.v1(),
        .user = user_info.v1(),
        .metrics = buf.items,
    };
}

pub fn @"consume amq.direct/client.heartbeat"(
    client: kwatcher.protocol.client_registration.schema.Client.Heartbeat.V1,
    reg: *ClientRegistry,
) !void {
    try reg.bump(client);
}
