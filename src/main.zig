const std = @import("std");

var PC: u16 = undefined;
var A: u8 = undefined;
var X: u8 = undefined;
var Y: u8 = undefined;

var RAM: [0x800]u8 = undefined;
var ROM: [0x8000]u8 = undefined;

var HEADER: [16]u8 = undefined;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 2) return error.ExpectedArgument;

    const rom_path = args[1];

    try reset(io, rom_path);

    std.debug.print("Program counter: {x}\n", .{PC});

    _ = gpa;
}

fn read(address: u16) u8 {
    if (address <= 0x1FFF) {
        return RAM[address & 0b0000_0111_1111_1111];
    }

    if (address >= 0x8000) {
        return ROM[address-0x8000];
    }

    return 0; // i don't know what to do here
}

fn reset(io: std.Io, path: []const u8) !void {
    var file = try std.Io.Dir.cwd().openFile(io, path, .{
        .mode = .read_only,
    });
    defer file.close(io);

    var buf: [4096]u8 = undefined;
    var reader = file.reader(io, &buf);
    
    try reader.interface.readSliceAll(&HEADER);
    try reader.interface.readSliceAll(&ROM);

    const PC_low = read(0xFFFC);
    const PC_high = read(0xFFFD);

    PC = (@as(u16, PC_high) * 0x100) + @as(u16, PC_low);
}
