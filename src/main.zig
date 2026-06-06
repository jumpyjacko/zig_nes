const std = @import("std");

const emulator = @import("emulator.zig");
const gui = @import("ui/main_window.zig");

pub fn main(init: std.process.Init) !void {
    try gui.initQtApplication(init);
}

comptime { // Run included tests
    _ = @import("ui/tracelogger.zig");
    _ = @import("emulator.zig");
}
