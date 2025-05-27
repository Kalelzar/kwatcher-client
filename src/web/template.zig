const std = @import("std");
const zmpl = @import("zmpl");
const tk = @import("tokamak");

const TemplateData = struct {};
const templateData = TemplateData{};

pub const Template = struct {
    template: zmpl.Template,
    pub fn init(name: []const u8) !Template {
        const template = zmpl.find(name) orelse {
            std.log.err("Tried to instantiate a non-exsistant template '{s}'", .{name});
            return error.TemplateNotFound;
        };
        return .{
            .template = template,
        };
    }

    pub fn sendResponse(self: *const Template, context: *tk.Context) !void {
        const data = try context.injector.get(*zmpl.Data);
        return self.sendResponseWithData(context, data);
    }

    pub fn sendResponseWithData(self: *const Template, context: *tk.Context, data: *zmpl.Data) !void {
        if (context.req.header("accept")) |accept| {
            const alloc = context.res.arena;
            if (std.mem.eql(u8, accept, "application/json")) {
                const body = try data.toJson();
                context.res.header("content-type", "applicaton/json");
                context.res.header("cache-control", "no-cache, no-store, must-revalidate");
                context.res.body = try alloc.dupe(u8, body);
            } else {
                const body = try self.template.render(data, TemplateData, templateData, .{});
                context.res.header("content-type", "text/html");
                context.res.header("cache-control", "no-cache, no-store, must-revalidate");
                context.res.body = try alloc.dupe(u8, body);
            }
        }

        context.responded = true;
    }
};

pub fn templates(children: []const tk.Route) tk.Route {
    const H = struct {
        fn handleTemplates(context: *tk.Context) anyerror!void {
            const alloc = context.res.arena;
            var data = zmpl.Data.init(alloc);
            defer data.deinit();

            var tdata = .{
                .data = &data,
            };

            return context.nextScoped(&tdata);
        }
    };
    return .{ .handler = &H.handleTemplates, .children = children };
}
