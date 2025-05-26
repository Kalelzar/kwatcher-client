const std = @import("std");
const kwatcher = @import("kwatcher");

pub const Config = struct {
    client: struct {} = .{},
};

pub const FullConfig = kwatcher.meta.MergeStructs(kwatcher.config.BaseConfig, Config);
