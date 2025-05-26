const std = @import("std");
const builtin = @import("builtin");

const Builder = struct {
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    opt: std.builtin.OptimizeMode,
    check_step: *std.Build.Step,
    kwatcher: *std.Build.Module,
    kwatcher_client: *std.Build.Module,
    kwatcher_client_lib: *std.Build.Module,

    fn init(b: *std.Build) Builder {
        const target = b.standardTargetOptions(.{});
        const opt = b.standardOptimizeOption(.{});

        const check_step = b.step("check", "");

        const kwatcher = b.dependency("kwatcher", .{}).module("kwatcher");
        const kwatcher_client_lib = b.addModule("kwatcher", .{
            .root_source_file = b.path("src/root.zig"),
        });
        kwatcher_client_lib.link_libc = true;
        kwatcher_client_lib.addImport("kwatcher", kwatcher);

        const kwatcher_client = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
        });
        kwatcher_client.link_libc = true;
        kwatcher_client.addImport("kwatcher", kwatcher);
        kwatcher_client.addImport("kwatcher-client", kwatcher_client_lib);

        return .{
            .b = b,
            .check_step = check_step,
            .target = target,
            .opt = opt,
            .kwatcher = kwatcher,
            .kwatcher_client = kwatcher_client,
            .kwatcher_client_lib = kwatcher_client_lib,
        };
    }

    fn addDependencies(
        self: *Builder,
        step: *std.Build.Step.Compile,
    ) void {
        step.root_module.addImport("kwatcher", self.kwatcher);
        step.linkLibC();
        step.linkSystemLibrary("rabbitmq");
        step.addLibraryPath(.{ .cwd_relative = "." });
    }

    fn addExecutable(self: *Builder, name: []const u8, root_source_file: []const u8) *std.Build.Step.Compile {
        return self.b.addExecutable(.{
            .name = name,
            .root_source_file = self.b.path(root_source_file),
            .target = self.target,
            .optimize = self.opt,
        });
    }

    fn addStaticLibrary(self: *Builder, name: []const u8, root_source_file: []const u8) *std.Build.Step.Compile {
        return self.b.addStaticLibrary(.{
            .name = name,
            .root_source_file = self.b.path(root_source_file),
            .target = self.target,
            .optimize = self.opt,
        });
    }

    fn addTest(self: *Builder, name: []const u8, root_source_file: []const u8) *std.Build.Step.Compile {
        return self.b.addTest(.{
            .name = name,
            .root_source_file = self.b.path(root_source_file),
            .target = self.target,
            .optimize = self.opt,
        });
    }

    fn installAndCheck(self: *Builder, exe: *std.Build.Step.Compile) !void {
        const check_exe = try self.b.allocator.create(std.Build.Step.Compile);
        check_exe.* = exe.*;
        self.check_step.dependOn(&check_exe.step);
        self.b.installArtifact(exe);
    }
};

pub fn build(b: *std.Build) !void {
    var builder = Builder.init(b);

    const lib = builder.addStaticLibrary("kwatcher-client-lib", "src/root.zig");
    builder.addDependencies(lib);
    try builder.installAndCheck(lib);

    const exe = builder.addExecutable("kwatcher-client", "src/main.zig");
    builder.addDependencies(exe);
    try builder.installAndCheck(exe);
    exe.root_module.addImport("kwatcher-client", builder.kwatcher_client_lib);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
