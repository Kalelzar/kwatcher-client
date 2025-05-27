const std = @import("std");
const builtin = @import("builtin");
const kwatcher = @import("kwatcher");
const client = @import("kwatcher-client");

const routes = @import("route.zig");

const metrics = client.web.metrics;
const template = client.web.template;

const tk = @import("tokamak");
const zmpl = @import("zmpl");

fn notFound(context: *tk.Context, data: *zmpl.Data) !template.Template {
    _ = try data.object();
    context.res.status = 404;
    return template.Template.init("not_found");
}

const App = struct {
    server: *tk.Server,
    routes: []const tk.Route = &.{
        tk.logger(.{}, &.{
            metrics.track(&.{
                .get("/metrics", metrics.route()),
                template.templates(&.{
                    .get("/openapi.json", tk.swagger.json(.{ .info = .{ .title = "KWatcher Client Registry" } })),
                    .get("/swagger-ui", tk.swagger.ui(.{ .url = "openapi.json" })),
                    .get("/*", notFound),
                }),
            }),
        }),
    },
};

const SingletonDependencies = struct {
    client_registry: client.Registry,
    metrics_buffer: client.MetricsBuffer,

    pub fn init(allocator: std.mem.Allocator) SingletonDependencies {
        return .{
            .client_registry = .init(allocator),
            .metrics_buffer = .init(allocator),
        };
    }

    pub fn deinit(self: *SingletonDependencies) void {
        self.client_registry.deinit();
        self.metrics_buffer.deinit();
    }
};

const ScopedDependencies = struct {};

const EventProvider = struct {
    pub fn requestReannounce(reg: *client.Registry) !bool {
        return !reg.ready;
    }

    pub fn disabled() bool {
        return false;
    }
};

fn initWebServer(allocator: std.mem.Allocator, deps: *SingletonDependencies) !void {
    try metrics.initialize(allocator, .{});
    defer metrics.deinitialize();
    var instr_allocator = metrics.instrumentAllocator(allocator);
    const alloc = instr_allocator.allocator();

    var instr_page_allocator = metrics.instrumentAllocator(std.heap.page_allocator);
    const page_allocator = instr_page_allocator.allocator();
    var arena = std.heap.ArenaAllocator.init(page_allocator);
    defer arena.deinit();

    const config = try kwatcher.config.findConfigFile(
        client.config.WebConfig,
        arena.allocator(),
        "client.web",
    ) orelse return error.ConfigNotFound;

    const root = tk.Injector.init(&.{
        &alloc,
        &tk.ServerOptions{
            .listen = .{
                .hostname = config.web.hostname,
                .port = config.web.port,
            },
        },
        &deps.client_registry,
        &deps.metrics_buffer,
    }, null);

    var app: App = undefined;
    const injector = try tk.Module(App).init(&app, &root);
    defer tk.Module(App).deinit(injector);

    if (injector.find(*tk.Server)) |server| {
        server.injector = injector;
        server_instance = server;
        try server.start();
    }
}

const KwatcherClient = kwatcher.server.Server(
    "client",
    "0.1.0",
    SingletonDependencies,
    ScopedDependencies,
    client.config.Config,
    struct {},
    routes,
    EventProvider,
);

fn initAmqpServer(allocator: std.mem.Allocator, singleton: *SingletonDependencies) !void {
    var server = try KwatcherClient.init(
        allocator,
        singleton,
    );
    defer server.deinit();

    kwatcher_instance = &server;
    try server.start();
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var singleton = SingletonDependencies.init(allocator);
    defer singleton.deinit();

    const kwthread = try std.Thread.spawn(
        .{ .allocator = allocator },
        initAmqpServer,
        .{ allocator, &singleton },
    );

    const tkthread = try std.Thread.spawn(
        .{ .allocator = allocator },
        initWebServer,
        .{ allocator, &singleton },
    );

    if (comptime builtin.os.tag == .linux) {
        // call our shutdown function (below) when
        // SIGINT or SIGTERM are received
        std.posix.sigaction(std.posix.SIG.INT, &.{
            .handler = .{ .handler = shutdown },
            .mask = std.posix.empty_sigset,
            .flags = 0,
        }, null);
        std.posix.sigaction(std.posix.SIG.TERM, &.{
            .handler = .{ .handler = shutdown },
            .mask = std.posix.empty_sigset,
            .flags = 0,
        }, null);
    }

    kwthread.join();
    tkthread.join();
}

var server_instance: ?*tk.Server = null;
var kwatcher_instance: ?*KwatcherClient = null;

fn shutdown(_: c_int) callconv(.C) void {
    if (server_instance) |server| {
        server_instance = null;
        server.stop();
    }
    if (kwatcher_instance) |kwatch| {
        kwatcher_instance = null;
        kwatch.stop();
    }
}
