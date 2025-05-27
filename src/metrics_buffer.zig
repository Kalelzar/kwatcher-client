const std = @import("std");

const MetricsBuffer = @This();

buffer: std.StringArrayHashMapUnmanaged([]const u8),
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) MetricsBuffer {
    return .{
        .buffer = .{},
        .allocator = allocator,
    };
}

pub fn ensure(self: *MetricsBuffer, size: u32) !void {
    try self.buffer.ensureTotalCapacity(self.allocator, size);
}

pub fn track(self: *MetricsBuffer, client_id: []const u8, data: []const u8) !void {
    const adopted = try self.allocator.dupe(u8, data);
    const entry = self.buffer.getOrPutAssumeCapacity(client_id);
    if (entry.found_existing) {
        self.allocator.free(entry.value_ptr.*);
    }
    entry.value_ptr.* = adopted;
}

pub fn write(self: *const MetricsBuffer, writer: anytype) !void {
    for (self.buffer.values()) |entry| {
        try writer.writeAll(entry);
        try writer.writeAll("\n");
    }
}

pub fn deinit(self: *MetricsBuffer) void {
    for (self.buffer.values()) |entry| {
        self.allocator.free(entry);
    }

    self.buffer.deinit(self.allocator);
}
