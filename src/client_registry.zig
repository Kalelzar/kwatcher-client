const std = @import("std");
const kwatcher = @import("kwatcher");
const kwcr = kwatcher.protocol.client_registration;

const ClientRegistry = @This();

const ClientEntry = struct {
    last_heartbeat: u64,
    status: kwcr.schema.Status = .active,
    name: []const u8,
    version: []const u8,
    host: []const u8,

    pub fn deinit(self: *ClientEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.version);
        allocator.free(self.host);
    }

    pub fn writeMetrics(self: *ClientEntry, writer: anytype) !void {
        const now: u64 = @intCast(std.time.milliTimestamp());
        const diff = now - self.last_heartbeat;
        var status: f32 = switch (self.status) {
            kwcr.schema.Status.active => 1,
            else => 0.5,
        };

        if (diff >= std.time.ms_per_min * 5 and self.status == .unknown) {
            status = 0;
        }

        try writer.print(
            "up{{exported_job=\"{s}\",client_version=\"{s}\",hostname=\"{s}\"}} {}\n",
            .{
                self.name,
                self.version,
                self.host,
                status,
            },
        );
    }
};

allocator: std.mem.Allocator,
clients: std.StringHashMapUnmanaged(ClientEntry),
ready: bool = false,

pub fn init(alloc: std.mem.Allocator) ClientRegistry {
    return .{
        .allocator = alloc,
        .clients = .{},
    };
}

pub fn deinit(self: *ClientRegistry) void {
    var it = self.clients.iterator();
    while (it.next()) |entry| {
        self.allocator.free(entry.key_ptr.*);
        entry.value_ptr.deinit(self.allocator);
    }
    self.clients.deinit(self.allocator);
}

fn genId(self: *ClientRegistry, name: []const u8, version: []const u8) ![]const u8 {
    const id = try std.fmt.allocPrint(self.allocator, "client:{s}:{s}:{x}", .{ name, version, std.crypto.random.int(u128) });
    defer self.allocator.free(id);
    const size = std.base64.url_safe_no_pad.Encoder.calcSize(id.len);
    const b64id = try self.allocator.alloc(u8, size);
    return std.base64.url_safe_no_pad.Encoder.encode(b64id, id);
}

pub fn add(self: *ClientRegistry, client: kwatcher.protocol.client_registration.schema.Client.Announce.V1) ![]const u8 {
    var it = self.clients.iterator();
    const client_id = blk: {
        while (it.next()) |entry| {
            if (std.mem.eql(u8, entry.value_ptr.name, client.client.name) and std.mem.eql(u8, entry.value_ptr.host, client.host)) {
                entry.value_ptr.deinit(self.allocator);
                break :blk entry.key_ptr.*;
            }
        }
        const id = client.id;
        const b64 = std.base64.url_safe_no_pad.Decoder;
        const size = b64.calcSizeForSlice(id) catch break :blk try self.genId(client.client.name, client.client.version);
        const buf = try self.allocator.alloc(u8, size);
        defer self.allocator.free(buf);

        b64.decode(buf, id) catch {
            break :blk try self.genId(client.client.name, client.client.version);
        };

        if (std.mem.startsWith(u8, buf, "client:")) {
            break :blk try self.allocator.dupe(u8, client.id);
        }

        break :blk try self.genId(client.client.name, client.client.version);
    };
    errdefer self.allocator.free(client_id);

    std.log.info("Client '{s}' announced themselves with '{s}': Assigned '{s}'", .{ client.client.name, client.id, client_id });
    try self.clients.put(
        self.allocator,
        client_id,
        .{
            .last_heartbeat = @intCast(std.time.milliTimestamp()),
            .name = try self.allocator.dupe(u8, client.client.name),
            .version = try self.allocator.dupe(u8, client.client.version),
            .host = try self.allocator.dupe(u8, client.host),
        },
    );

    return client_id;
}

pub fn update(self: *ClientRegistry) !void {
    var it = self.clients.iterator();
    const now: u64 = @intCast(std.time.milliTimestamp());
    while (it.next()) |entry| {
        const diff = now - entry.value_ptr.last_heartbeat;
        if (diff < 60 * std.time.ms_per_s) {
            entry.value_ptr.status = .unknown;
        }
    }
}

pub fn writeMetrics(self: *ClientRegistry, writer: anytype) !void {
    try writer.writeAll(
        \\ # HELP up Client operational status (1=up, 0.5=sleeping/pending, 0=down)
        \\ # TYPE up gauge
        \\
    );
    var it = self.clients.iterator();
    while (it.next()) |entry| {
        try entry.value_ptr.writeMetrics(writer);
    }
}

pub fn bump(self: *ClientRegistry, client: kwatcher.protocol.client_registration.schema.Client.Heartbeat.V1) !void {
    if (self.clients.getPtr(client.id)) |entry| {
        std.log.info("Client '{s}' kept the connection alive.", .{client.id});
        entry.last_heartbeat = @intCast(std.time.milliTimestamp());
    } else {
        return error.Rejected;
    }
}
