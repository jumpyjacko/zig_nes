const std = @import("std");

var PC: u16 = undefined;
var A: u8 = undefined;
var X: u8 = undefined;
var Y: u8 = undefined;

var RAM: [0x800]u8 = undefined;
var ROM: [0x8000]u8 = undefined;

var HEADER: [16]u8 = undefined;

var flag_carry: bool = false;
var flag_zero: bool = false;
var flag_interupt_disable: bool = false;
var flag_decimal: bool = false;
var flag_overflow: bool = false;
var flag_negative: bool = false;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 2) return error.ExpectedArgument;

    const rom_path = args[1];

    try reset(io, rom_path);

    std.debug.print("PC: {x}\n", .{PC});
    std.debug.print("A: {x}\n", .{A});
    std.debug.print("X: {x}\n", .{X});
    std.debug.print("Y: {x}\n", .{Y});

    std.debug.print("{x} {x} {x}\n", .{ RAM[0], RAM[1], RAM[2] });
    std.debug.print("{x}\n", .{RAM[0x0550]});

    std.debug.print("flag_carry: {}\n", .{flag_carry});
    std.debug.print("flag_zero: {}\n", .{flag_zero});
    std.debug.print("flag_interupt_disable: {}\n", .{flag_interupt_disable});
    std.debug.print("flag_decimal: {}\n", .{flag_decimal});
    std.debug.print("flag_overflow: {}\n", .{flag_overflow});
    std.debug.print("flag_negative: {}\n", .{flag_negative});

    _ = gpa;
}

fn read(address: u16) u8 {
    if (address <= 0x1FFF) {
        return RAM[address & 0b0000_0111_1111_1111];
    }

    if (address >= 0x8000) {
        return ROM[address - 0x8000];
    }

    return 0; // i don't know what to do here
}

fn write(address: u16, value: u8) !void {
    if (address >= 0x8000) return;

    if (address <= 0x1FFF) {
        RAM[address & 0b0000_0111_1111_1111] = value;
        return;
    }
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

    flag_interupt_disable = true;
    try run();
}

var CPU_Halted = false;
fn run() !void {
    while (!CPU_Halted) {
        try emulate();
    }
}

var cycles: usize = 0;
fn emulate() !void {
    const opcode: u8 = read(PC);
    PC += 1;

    switch (opcode) {
        0x02 => { // HLT
            CPU_Halted = true;
        },
        0xA0 => { // LDY Immediate
            Y = read(PC);
            PC += 1;

            flag_zero = Y == 0;
            flag_negative = Y > 127;
            cycles = 2;
        },
        0xA2 => { // LDX Immediate
            X = read(PC);
            PC += 1;

            flag_zero = X == 0;
            flag_negative = X > 127;
            cycles = 2;
        },
        0xA9 => { // LDA Immediate
            A = read(PC);
            PC += 1;

            flag_zero = A == 0;
            flag_negative = A > 127;
            cycles = 2;
        },
        0xA5 => { // LDA Zero Page
            const address = read(PC);
            PC += 1;
            A = read(address);

            flag_zero = A == 0;
            flag_negative = A > 127;
            cycles = 3;
        },
        0xAD => { // LDA Absolute
            const addr_low = read(PC);
            PC += 1;
            const addr_high: u16 = read(PC);
            PC += 1;
            const address = (addr_high << 8) | addr_low;
            A = read(address);

            flag_zero = A == 0;
            flag_negative = A > 127;
            cycles = 4;
        },
        0x85 => { // STA Zero Page
            const address = read(PC);
            PC += 1;
            try write(address, A);
            cycles = 3;
        },
        0x86 => { // STX Zero Page
            const address = read(PC);
            PC += 1;
            try write(address, X);
            cycles = 3;
        },
        0x84 => { // STY Zero Page
            const address = read(PC);
            PC += 1;
            try write(address, Y);
            cycles = 3;
        },
        0x8D => { // STA Absolute
            const addr_low = read(PC);
            PC += 1;
            const addr_high: u16 = read(PC);
            PC += 1;
            try write((addr_high << 8) | addr_low, A);
            cycles = 4;
        },
        0x8E => { // STX Absolute
            const addr_low = read(PC);
            PC += 1;
            const addr_high: u16 = read(PC);
            PC += 1;
            try write((addr_high << 8) | addr_low, X);
            cycles = 4;
        },
        0x8C => { // STY Absolute
            const addr_low = read(PC);
            PC += 1;
            const addr_high: u16 = read(PC);
            PC += 1;
            try write((addr_high << 8) | addr_low, Y);
            cycles = 4;
        },
        0x10 => { // BPL
            const offset: i8 = @as(i8, @bitCast(read(PC)));
            PC += 1;

            if (!flag_negative) {
                const old_pc = PC;
                PC = @as(u16, @intCast(@as(i32, PC) + offset));

                if ((old_pc & 0xFF00) != (PC & 0xFF00)) {
                    cycles = 4;
                } else {
                    cycles = 3;
                }
            } else {
                cycles = 2;
            }
        },
        0x30 => { // BMI
            const offset: i8 = @as(i8, @bitCast(read(PC)));
            PC += 1;

            if (flag_negative) {
                const old_pc = PC;
                PC = @as(u16, @intCast(@as(i32, PC) + offset));

                if ((old_pc & 0xFF00) != (PC & 0xFF00)) {
                    cycles = 4;
                } else {
                    cycles = 3;
                }
            } else {
                cycles = 2;
            }
        },
        0x50 => { // BVC
            const offset: i8 = @as(i8, @bitCast(read(PC)));
            PC += 1;

            if (!flag_overflow) {
                const old_pc = PC;
                PC = @as(u16, @intCast(@as(i32, PC) + offset));

                if ((old_pc & 0xFF00) != (PC & 0xFF00)) {
                    cycles = 4;
                } else {
                    cycles = 3;
                }
            } else {
                cycles = 2;
            }
        },
        0x70 => { // BVS
            const offset: i8 = @as(i8, @bitCast(read(PC)));
            PC += 1;

            if (flag_overflow) {
                const old_pc = PC;
                PC = @as(u16, @intCast(@as(i32, PC) + offset));

                if ((old_pc & 0xFF00) != (PC & 0xFF00)) {
                    cycles = 4;
                } else {
                    cycles = 3;
                }
            } else {
                cycles = 2;
            }
        },
        0x90 => { // BCC
            const offset: i8 = @as(i8, @bitCast(read(PC)));
            PC += 1;

            if (!flag_carry) {
                const old_pc = PC;
                PC = @as(u16, @intCast(@as(i32, PC) + offset));

                if ((old_pc & 0xFF00) != (PC & 0xFF00)) {
                    cycles = 4;
                } else {
                    cycles = 3;
                }
            } else {
                cycles = 2;
            }
        },
        0xB0 => { // BCS
            const offset: i8 = @as(i8, @bitCast(read(PC)));
            PC += 1;

            if (flag_carry) {
                const old_pc = PC;
                PC = @as(u16, @intCast(@as(i32, PC) + offset));

                if ((old_pc & 0xFF00) != (PC & 0xFF00)) {
                    cycles = 4;
                } else {
                    cycles = 3;
                }
            } else {
                cycles = 2;
            }
        },
        0xD0 => { // BNE
            const offset: i8 = @as(i8, @bitCast(read(PC)));
            PC += 1;

            if (!flag_zero) {
                const old_pc = PC;
                PC = @as(u16, @intCast(@as(i32, PC) + offset));

                if ((old_pc & 0xFF00) != (PC & 0xFF00)) {
                    cycles = 4;
                } else {
                    cycles = 3;
                }
            } else {
                cycles = 2;
            }
        },
        0xF0 => { // BEQ
            const offset: i8 = @as(i8, @bitCast(read(PC)));
            PC += 1;

            if (flag_zero) {
                const old_pc = PC;
                PC = @as(u16, @intCast(@as(i32, PC) + offset));

                if ((old_pc & 0xFF00) != (PC & 0xFF00)) {
                    cycles = 4;
                } else {
                    cycles = 3;
                }
            } else {
                cycles = 2;
            }
        },
        else => {},
    }
}
