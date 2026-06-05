const std = @import("std");

const emulator = @import("emulator.zig");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 2) return error.ExpectedArgument;

    const rom_path = args[1];

    try emulator.reset(io, rom_path);
    try emulator.run();

    _ = gpa;
}

comptime { // Run included tests
    _ = @import("emulator.zig");
}
