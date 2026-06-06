const std = @import("std");

const emulator = @import("emulator.zig");
const gui = @import("ui/main_window.zig");

pub fn main(init: std.process.Init) !void {
    // const args = try init.minimal.args.toSlice(arena.allocator());
    // if (args.len < 2) return error.ExpectedArgument;

    // const rom_path = args[1];

    // try emulator.reset(io, rom_path);
    // try emulator.run();

    try gui.initQtApplication(init);
}

comptime { // Run included tests
    _ = @import("emulator.zig");
}
