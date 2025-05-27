const std = @import("std");
const kwatcher = @import("kwatcher");

pub const Config = struct {
    client: struct {} = .{},
};

pub const WebConfig = struct {
    web: struct {
        hostname: []const u8 = "0.0.0.0",
        port: u16 = 4369,
    } = .{},
};

pub const FullConfig = kwatcher.meta.MergeStructs(kwatcher.config.BaseConfig, Config);
