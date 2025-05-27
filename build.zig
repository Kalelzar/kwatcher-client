const std = @import("std");
const builtin = @import("builtin");

const Builder = struct {
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    opt: std.builtin.OptimizeMode,
    check_step: *std.Build.Step,

    kwatcher_client: *std.Build.Module,
    kwatcher_client_lib: *std.Build.Module,

    fn init(b: *std.Build) Builder {
        const target = b.standardTargetOptions(.{});
        const opt = b.standardOptimizeOption(.{});

        const check_step = b.step("check", "");

        const kw = b.dependency("kwatcher", .{});
        const kwatcher = kw.module("kwatcher");
        const klib = kw.builder.dependency("klib", .{ .target = target, .optimize = opt }).module("klib");
        const tk = b.dependency("tokamak", .{ .target = target, .optimize = opt });
        const tokamak = tk.module("tokamak");
        const hz = tk.builder.dependency("httpz", .{ .target = target, .optimize = opt });
        const httpz = hz.module("httpz");
        const metrics = hz.builder.dependency("metrics", .{ .target = target, .optimize = opt }).module("metrics");
        const zmpl = b.dependency("zmpl", .{ .target = target, .optimize = opt }).module("zmpl");
        const kwatcher_client_lib = b.addModule("kwatcher", .{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = opt,
        });
        kwatcher_client_lib.link_libc = true;
        kwatcher_client_lib.addImport("kwatcher", kwatcher);
        kwatcher_client_lib.addImport("tokamak", tokamak);
        kwatcher_client_lib.addImport("zmpl", zmpl);
        kwatcher_client_lib.addImport("httpz", httpz);
        kwatcher_client_lib.addImport("metrics", metrics);
        kwatcher_client_lib.addImport("klib", klib);

        const kwatcher_client = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = opt,
        });
        kwatcher_client.link_libc = true;
        kwatcher_client.addImport("kwatcher", kwatcher);
        kwatcher_client.addImport("kwatcher-client", kwatcher_client_lib);
        kwatcher_client.addImport("tokamak", tokamak);
        kwatcher_client.addImport("zmpl", zmpl);

        return .{
            .b = b,
            .check_step = check_step,
            .target = target,
            .opt = opt,
            .kwatcher_client = kwatcher_client,
            .kwatcher_client_lib = kwatcher_client_lib,
        };
    }

    fn addDependencies(
        self: *Builder,
        step: *std.Build.Step.Compile,
    ) void {
        _ = self;
        step.linkLibC();
        step.linkSystemLibrary("rabbitmq");
        step.addLibraryPath(.{ .cwd_relative = "." });
    }

    fn addExecutable(self: *Builder, name: []const u8, root_module: *std.Build.Module) *std.Build.Step.Compile {
        return self.b.addExecutable(.{
            .name = name,
            .root_module = root_module,
        });
    }

    fn addStaticLibrary(self: *Builder, name: []const u8, root_module: *std.Build.Module) *std.Build.Step.Compile {
        return self.b.addStaticLibrary(.{
            .name = name,
            .root_module = root_module,
        });
    }

    fn addTest(self: *Builder, name: []const u8, root_module: *std.Build.Module) *std.Build.Step.Compile {
        return self.b.addTest(.{
            .name = name,
            .root_module = root_module,
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

    const lib = builder.addStaticLibrary("kwatcher-client-lib", builder.kwatcher_client_lib);
    builder.addDependencies(lib);
    try builder.installAndCheck(lib);

    const exe = builder.addExecutable("kwatcher-client", builder.kwatcher_client);
    builder.addDependencies(exe);
    try builder.installAndCheck(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
