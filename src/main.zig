const std = @import("std");

const emulator = @import("emulator.zig");
const gui = @import("ui/main_window.zig");

pub fn main(init: std.process.Init) !void {
    try gui.initQtApplication(init);
}
