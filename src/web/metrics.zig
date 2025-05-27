const std = @import("std");
const tk = @import("tokamak");
const httpz = @import("httpz");
const m = @import("metrics");
const klib = @import("klib");

const ClientRegistry = @import("../client_registry.zig");
const MetricsBuffer = @import("../metrics_buffer.zig");

var metrics = m.initializeNoop(Metrics);

const Metrics = struct {
    statuses: Status,
    total_memory_allocated: MemUsage,
    peak_memory_allocated: MemUsage,

    const MemUsage = m.Gauge(i64);
    const StatusL = struct { status: u16 };
    const Status = m.CounterVec(u32, StatusL);
};

pub fn status(labels: Metrics.StatusL) !void {
    return metrics.statuses.incr(labels);
}

pub fn initialize(allocator: std.mem.Allocator, comptime opts: m.RegistryOpts) !void {
    metrics = .{
        .total_memory_allocated = Metrics.MemUsage.init(
            "kwatcher_total_memory_bytes",
            .{ .help = "The total allocated memory by the kwatcher" },
            opts,
        ),
        .peak_memory_allocated = Metrics.MemUsage.init(
            "kwatcher_peak_memory_bytes",
            .{ .help = "The maximum allocated memory by the kwatcher" },
            opts,
        ),
        .statuses = try Metrics.Status.init(allocator, "kwatcher_https_statuses", .{}, opts),
    };
}

pub fn deinitialize() void {
    metrics.statuses.deinit();
}

pub fn alloc(size: usize) void {
    metrics.total_memory_allocated.incrBy(@as(i64, @intCast(size)));
    const max = metrics.peak_memory_allocated.impl.value;
    const current = metrics.total_memory_allocated.impl.value;
    if (max < current)
        metrics.peak_memory_allocated.set(current);
}

pub fn free(size: usize) void {
    metrics.total_memory_allocated.incrBy(-@as(i64, @intCast(size)));
}

pub fn instrumentAllocator(allocator: std.mem.Allocator) klib.mem.InstrumentedAllocator {
    return klib.mem.InstrumentedAllocator.init(
        allocator,
        .{
            .free = &free,
            .alloc = &alloc,
        },
    );
}

fn sendMetrics(context: *tk.Context) !void {
    context.res.header("content-type", "text/plain; version=0.0.4");

    const registry = try context.injector.get(*ClientRegistry);
    const metrics_buffer = try context.injector.get(*MetricsBuffer);

    const writer = context.res.writer();

    try registry.update();

    try httpz.writeMetrics(writer);
    try registry.writeMetrics(writer);
    try metrics_buffer.write(writer);

    context.responded = true;
}

pub fn route() tk.Route {
    const H = struct {
        fn handleMetrics(context: *tk.Context) anyerror!void {
            sendMetrics(context) catch |e| {
                std.log.err("Encountered error while sending metrics: {}", .{e});
            };
            return;
        }
    };
    return .{ .handler = &H.handleMetrics };
}

pub fn track(children: []const tk.Route) tk.Route {
    const H = struct {
        fn handleMetrics(context: *tk.Context) anyerror!void {
            try context.next();
            try status(.{ .status = context.res.status });
        }
    };
    return .{ .handler = &H.handleMetrics, .children = children };
}
