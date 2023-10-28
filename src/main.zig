const std = @import("std");
const c = @cImport({
    @cInclude("raylib.h");
});

pub fn main() !void {
    try gameloop();
}

export fn emsc_main() void {
    gameloop() catch |err| {
        std.log.err("error code: {}\n", .{err});
    };
}

fn gameloop() !void {
    const height: u32 = 450;
    const width: u32 = 800;

    c.InitWindow(width, height, "raylib [core] example - basic window");
    defer c.CloseWindow();

    c.SetTargetFPS(60);

    while (!c.WindowShouldClose()) {
        c.BeginDrawing();
        defer c.EndDrawing();

        c.ClearBackground(c.RAYWHITE);
        c.DrawText("Congrats! You Created your first window!", 190, 200, 20, c.LIGHTGRAY);
    }
}
