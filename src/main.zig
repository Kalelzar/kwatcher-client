const std = @import("std");
const kwatcher = @import("kwatcher");
const client = @import("kwatcher-client");

const routes = @import("route.zig");

const SingletonDependencies = struct {
    client_registry: client.Registry,

    pub fn init(allocator: std.mem.Allocator) SingletonDependencies {
        return .{
            .client_registry = .init(allocator),
        };
    }

    pub fn deinit(self: *SingletonDependencies) void {
        self.client_registry.deinit();
    }
};

const ScopedDependencies = struct {};

const EventProvider = struct {
    pub fn requestReannounce(reg: *client.Registry) !bool {
        return !reg.ready;
    }

    pub fn metrics(timer: kwatcher.Timer) !bool {
        return try timer.ready("metrics");
    }

    pub fn disabled() bool {
        return false;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var singleton = SingletonDependencies.init(allocator);
    defer singleton.deinit();
    var server = try kwatcher.server.Server(
        "client",
        "0.1.0",
        SingletonDependencies,
        ScopedDependencies,
        client.config.Config,
        struct {},
        routes,
        EventProvider,
    ).init(
        allocator,
        &singleton,
    );
    defer server.deinit();

    try server.start();
}
