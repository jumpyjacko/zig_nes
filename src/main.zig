const std = @import("std");

var PC: u16 = undefined;
var A: u8 = undefined;
var X: u8 = undefined;
var Y: u8 = undefined;

var SP: u8 = undefined; // stack pointer

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

fn push(value: u8) void {
    try write(@as(u16, (@as(u16, 0x100) + SP)), value);
    SP -%= 1;
}

fn pull() u8 {
    SP +%= 1;
    return read(@as(u16, (@as(u16, 0x100) + SP)));
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
    SP = 0xFD;
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

            setFlags_ZN(Y);
            cycles = 2;
        },
        0xA2 => { // LDX Immediate
            X = read(PC);
            PC += 1;

            setFlags_ZN(X);
            cycles = 2;
        },
        0xA9 => { // LDA Immediate
            A = read(PC);
            PC += 1;

            setFlags_ZN(A);
            cycles = 2;
        },
        0xA5 => { // LDA Zero Page
            const address = read(PC);
            PC += 1;
            A = read(address);

            setFlags_ZN(A);
            cycles = 3;
        },
        0xAD => { // LDA Absolute
            const address = readOperands_AbsAddressed();
            A = read(address);

            setFlags_ZN(A);
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
            const address = readOperands_AbsAddressed();
            try write(address, A);
            cycles = 4;
        },
        0x8E => { // STX Absolute
            const address = readOperands_AbsAddressed();
            try write(address, X);
            cycles = 4;
        },
        0x8C => { // STY Absolute
            const address = readOperands_AbsAddressed();
            try write(address, Y);
            cycles = 4;
        },
        0x10 => { // BPL
            opBranch(!flag_negative);
        },
        0x30 => { // BMI
            opBranch(flag_negative);
        },
        0x50 => { // BVC
            opBranch(!flag_overflow);
        },
        0x70 => { // BVS
            opBranch(flag_overflow);
        },
        0x90 => { // BCC
            opBranch(!flag_carry);
        },
        0xB0 => { // BCS
            opBranch(flag_carry);
        },
        0xD0 => { // BNE
            opBranch(!flag_zero);
        },
        0xF0 => { // BEQ
            opBranch(flag_zero);
        },
        0x48 => { // PHA
            push(A);
            cycles = 3;
        },
        0x68 => { // PLA
            A = pull();
            setFlags_ZN(A);
            cycles = 4;
        },
        0x08 => { // PHP
            var status: u8 = 0;

            if (flag_carry) status |= 0b0000_0001;
            if (flag_zero) status |= 0b0000_0010;
            if (flag_interupt_disable) status |= 0b0000_0100;
            if (flag_decimal) status |= 0b0000_1000;
            status |= 0b0011_0000; // always set in PHP instruction
            if (flag_overflow) status |= 0b0100_0000;
            if (flag_negative) status |= 0b1000_0000;

            push(status);
            PC += 1;
            cycles = 3;
        },
        0x28 => { // PLP
            const status = pull();
            flag_carry = (status & 0b0000_0001) != 0;
            flag_zero = (status & 0b0000_0001) != 0;
            flag_interupt_disable = (status & 0b0000_0001) != 0;
            flag_decimal = (status & 0b0000_0001) != 0;
            flag_overflow = (status & 0b0000_0001) != 0;
            flag_negative = (status & 0b0000_0001) != 0;

            PC += 1;
            cycles = 4;
        },
        0x20 => { // JSR
            const sr_addr_l = read(PC);
            PC += 1;
            const sr_addr_h: u16 = read(PC);
            push(@truncate(PC >> 8));
            push(@truncate(PC & 0x00FF));
            PC = (sr_addr_h << 8) | sr_addr_l;
            cycles = 6;
        },
        0x60 => { // RTS
            const rt_addr_l = pull();
            const rt_addr_h: u16 = pull();
            PC = (rt_addr_h << 8) | rt_addr_l;
            PC += 1;
            cycles = 6;
        },
        0x4C => { // JMP
            const addr_l = read(PC);
            PC += 1;
            const addr_h: u16 = read(PC);
            PC += 1;
            PC = (addr_h << 8) | addr_l;
            cycles = 3;
        },
        0xE6 => { // INC Zero Page
            const address = read(PC);
            PC += 1;
            opINC(address, read(address));
            cycles = 5;
        },
        0xEE => { // INC Absolute
            const address = readOperands_AbsAddressed();
            opINC(address, read(address));
            cycles = 6;
        },
        0xC6 => { // DEC Zero Page
            const address = read(PC);
            PC += 1;
            opINC(address, read(address));
            cycles = 5;
        },
        0xCE => { // DEC Absolute
            const address = readOperands_AbsAddressed();
            opINC(address, read(address));
            cycles = 6;
        },
        0xE8 => { // INX
            X +%= 1;
            PC += 1;

            setFlags_ZN(X);
            cycles = 2;
        },
        0xCA => { // DEX
            X -%= 1;
            PC += 1;

            setFlags_ZN(X);
            cycles = 2;
        },
        0xC8 => { // INY
            Y +%= 1;
            PC += 1;

            setFlags_ZN(Y);
            cycles = 2;
        },
        0x88 => { // DEY
            Y -%= 1;
            PC += 1;

            setFlags_ZN(Y);
            cycles = 2;
        },
        0xAA => { // TAX
            X = A;
            PC += 1;

            setFlags_ZN(X);
            cycles = 2;
        },
        0x8A => { // TXA
            A = X;
            PC += 1;

            setFlags_ZN(A);
            cycles = 2;
        },
        0xA8 => { // TAY
            Y = A;
            PC += 1;

            setFlags_ZN(Y);
            cycles = 2;
        },
        0x98 => { // TYA
            A = Y;
            PC += 1;

            setFlags_ZN(A);
            cycles = 2;
        },
        0x9A => { // TXS
            SP = X;
            PC += 1;

            // DOES NOT SET ZN
            cycles = 2;
        },
        0xBA => { // TXS
            X = SP;
            PC += 1;

            flag_zero = X == 0;
            flag_negative = X > 0x7F;
            cycles = 2;
        },
        0x38 => { // SEC
            flag_carry = true;
            PC += 1;
            cycles = 2;
        },
        0x18 => { // CLC
            flag_carry = false;
            PC += 1;
            cycles = 2;
        },
        0xB8 => { // CLV
            flag_overflow = false;
            PC += 1;
            cycles = 2;
        },
        0x78 => { // SEI
            flag_interupt_disable = true;
            PC += 1;
            cycles = 2;
        },
        0x58 => { // CLI
            flag_interupt_disable = false;
            PC += 1;
            cycles = 2;
        },
        0xF8 => { // SED
            flag_decimal = true;
            PC += 1;
            cycles = 2;
        },
        0xD8 => { // CLD
            flag_decimal = false;
            PC += 1;
            cycles = 2;
        },
        0xEA => { // NOP
            PC += 1;
            cycles = 2;
        },
        0x0A => { // ASL A
            opASL(A, read(A));
            PC += 1;
            cycles = 2;
        },
        0x06 => { // ASL Zero Page
            const address = read(PC);
            PC += 1;
            opASL(address, read(address));
            cycles = 6;
        },
        0x0E => { // ASL Absolute
            const address = readOperands_AbsAddressed();
            opASL(address, read(address));
            cycles = 6;
        },
        0x4A => { // LSR A
            opLSR(A, read(A));
            PC += 1;
            cycles = 2;
        },
        0x46 => { // LSR Zero Page
            const address = read(PC);
            PC += 1;
            opLSR(address, read(address));
            cycles = 6;
        },
        0x4E => { // LSR Absolute
            const address = readOperands_AbsAddressed();
            opLSR(address, read(address));
            cycles = 6;
        },
        0x2A => { // ROL A
            opROL(A, read(A));
            PC += 1;
            cycles = 2;
        },
        0x26 => { // ROL Zero Page
            const address = read(PC);
            PC += 1;
            opROL(address, read(address));
            cycles = 6;
        },
        0x2E => { // ROL Absolute
            const address = readOperands_AbsAddressed();
            opROL(address, read(address));
            cycles = 6;
        },
        0x6A => { // ROR A
            opROR(A, read(A));
            PC += 1;
            cycles = 2;
        },
        0x66 => { // ROR Zero Page
            const address = read(PC);
            PC += 1;
            opROR(address, read(address));
            cycles = 6;
        },
        0x6E => { // ROR Absolute
            const address = readOperands_AbsAddressed();
            opROR(address, read(address));
            cycles = 6;
        },
        0x09 => { // ORA Immediate
            const byte = read(PC);
            PC += 1;
            opORA(byte);
            cycles = 2;
        },
        0x05 => { // ORA Zero Page 
            const address = read(PC);
            PC += 1;
            opORA(read(address));
            cycles = 3;
        },
        0x0D => { // ORA Absolute
            const address = readOperands_AbsAddressed();
            opORA(read(address));
            cycles = 4;
        },
        else => {},
    }
}

fn opBranch(condition: bool) void {
    const offset: i8 = @as(i8, @bitCast(read(PC)));
    PC += 1;

    if (condition) {
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
}

fn opINC(address: u16, value: u8) void {
    const result: u8 = value +% 1;
    try write(address, result);
    setFlags_ZN(result);
}

fn opDEC(address: u16, value: u8) void {
    const result: u8 = value -% 1;
    try write(address, result);
    setFlags_ZN(result);
}

fn opASL(address: u16, value: u8) void {
    flag_carry = (value & 0b1000_0000) != 0;
    const result = value << 1;

    try write(address, result);
    setFlags_ZN(result);
}

fn opLSR(address: u16, value: u8) void {
    flag_carry = (value & 1) != 0;
    const result = value >> 1;

    try write(address, result);
    setFlags_ZN(result);
}

fn opROL(address: u16, value: u8) void {
    const new_carry = (value & 0x80) != 0;

    var result = value << 1;
    if (flag_carry) result |= 1;

    try write(address, result);
    flag_carry = new_carry;
    setFlags_ZN(result);
}

fn opROR(address: u16, value: u8) void {
    const new_carry = (value & 1) != 0;

    var result = value >> 1;
    if (flag_carry) result |= 0b1000_0000;

    try write(address, result);
    flag_carry = new_carry;
    setFlags_ZN(result);
}

fn opORA(byte: u8) void {
    A |= byte;
    setFlags_ZN(A);
}

fn readOperands_AbsAddressed() u16 {
    const low = read(PC);
    PC += 1;

    const high: u16 = read(PC);
    PC += 1;

    return (high << 8) | low;
}

fn setFlags_ZN(byte: u8) void {
    flag_zero = byte == 0;
    flag_negative = (byte & 0b1000_0000) != 0;
}

const testing = @import("std").testing;
test "read() ram" {
    RAM[0] = 0x67;
    const ram = read(0x0000);
    try testing.expectEqual(0x67, ram);
}

test "read() ram mirrored" {
    RAM[0] = 0x67;
    const ram_mirrored = read(0x0800);
    try testing.expectEqual(0x67, ram_mirrored);
}

test "read() rom" {
    ROM[0] = 0x69;
    const rom = read(0x8000);
    try testing.expectEqual(0x69, rom);
}

test "write() ram" {
    RAM[0] = 0x01;
    try testing.expectEqual(0x01, RAM[0]);

    try write(0x0000, 0x02);
    try testing.expectEqual(0x02, RAM[0]);
}

test "write() rom" {
    ROM[0] = 0x01;
    try testing.expectEqual(0x01, ROM[0]);

    try write(0x8000, 0x02);
    try testing.expectEqual(0x01, ROM[0]);
}

test "push (normal stack pointer)" {
    SP = 0xFD;
    push(0xAA);

    try testing.expectEqual(0xAA, RAM[0x01FD]);
    try testing.expectEqual(0xFC, SP);
}

test "push (underflow stack pointer)" {
    SP = 0x00;
    push(0xAA);

    try testing.expectEqual(0xAA, RAM[0x01FF]);
    try testing.expectEqual(0xFF, SP);
}

test "pull (normal stack pointer)" {
    RAM[0x01AF] = 0x42;
    SP = 0xAE;
    const value = pull();

    try testing.expectEqual(0x42, value);
    try testing.expectEqual(0xAF, SP);
}

test "pull (overflow stack pointer)" {
    RAM[0x0100] = 0x42;
    SP = 0xFF;
    const value = pull();

    try testing.expectEqual(0x42, value);
    try testing.expectEqual(0x00, SP);
}

test "readOperands_AbsAddressed()" {
    PC = 0x8001;
    ROM[1] = 0x08;
    ROM[2] = 0x80;

    const address = readOperands_AbsAddressed();

    try testing.expectEqual(@as(u16, 0x8008), address);
    try testing.expectEqual(@as(u16, 0x8003), PC);
}

test "setFlags_ZN() zero" {
    setFlags_ZN(0);
    try testing.expect(flag_zero);
}

test "setFlags_ZN() negative" {
    setFlags_ZN(@bitCast(@as(i8, -1)));
    try testing.expect(flag_negative);
}

test "setFlags_ZN() no set" {
    setFlags_ZN(1);
    try testing.expect(!flag_zero and !flag_negative);
}

test "generic branch" {
    PC = 0x8001;
    ROM[1] = 0x01;

    flag_carry = true;
    opBranch(flag_carry);

    try testing.expectEqual(0x8003, PC);
}

test "generic branch (modify high bits)" {
    PC = 0x80FE;
    ROM[0xFE] = 0x02;

    flag_carry = true;
    opBranch(flag_carry);

    try testing.expectEqual(0x8101, PC);
    try testing.expectEqual(4, cycles);
}

test "INC normal" {
    RAM[0] = 1;
    opINC(0x0000, read(0x0000));

    try testing.expectEqual(2, RAM[0]);
    try testing.expect(!flag_zero);
    try testing.expect(!flag_negative);
}

test "INC overflow" {
    RAM[0] = 255;
    opINC(0x0000, read(0x0000));

    try testing.expectEqual(0, RAM[0]);
    try testing.expect(flag_zero);
    try testing.expect(!flag_negative);
}

test "INC set negative" {
    RAM[0] = @as(u8, @bitCast(@as(i8, -128)));
    opINC(0x0000, read(0x0000));

    try testing.expectEqual(@as(u8, @bitCast(@as(i8, -127))), RAM[0]);
    try testing.expect(!flag_zero);
    try testing.expect(flag_negative);
}

test "DEC normal" {
    RAM[0] = 2;
    opDEC(0x0000, read(0x0000));

    try testing.expectEqual(1, RAM[0]);
    try testing.expect(!flag_zero);
    try testing.expect(!flag_negative);
}

test "DEC overflow" {
    RAM[0] = 0;
    opDEC(0x0000, read(0x0000));

    try testing.expectEqual(255, RAM[0]);
    try testing.expect(!flag_zero);
    try testing.expect(flag_negative);
}

test "DEC set zero" {
    RAM[0] = 1;
    opDEC(0x0000, read(0x0000));

    try testing.expectEqual(0, RAM[0]);
    try testing.expect(flag_zero);
    try testing.expect(!flag_negative);
}

test "DEC set negative" {
    RAM[0] = @as(u8, @bitCast(@as(i8, -126)));
    opDEC(0x0000, read(0x0000));

    try testing.expectEqual(@as(u8, @bitCast(@as(i8, -127))), RAM[0]);
    try testing.expect(!flag_zero);
    try testing.expect(flag_negative);
}

test "ASL normal" {
    opASL(0x0000, 2);
    try testing.expectEqual(4, RAM[0]);
}

test "ASL carry" {
    opASL(0x0000, 0b1000_0001);
    try testing.expectEqual(0b0000_0010, RAM[0]);
    try testing.expect(flag_carry);
}

test "LSR normal" {
    opLSR(0x0000, 2);
    try testing.expectEqual(1, RAM[0]);
}

test "LSR carry" {
    opLSR(0x0000, 3);
    try testing.expectEqual(1, RAM[0]);
    try testing.expect(flag_carry);
}

test "ROL normal" {
    flag_carry = false;
    opROL(0x0000, 0b0000_0001);
    try testing.expectEqual(0b0000_0010, RAM[0]);
    try testing.expect(!flag_carry);
}

test "ROL no previous carry" {
    flag_carry = false;
    opROL(0x0000, 0b1000_0001);
    try testing.expectEqual(0b0000_0010, RAM[0]);
    try testing.expect(flag_carry);
}

test "ROL /w previous carry" {
    flag_carry = true;
    opROL(0x0000, 0b1000_0001);
    try testing.expectEqual(0b0000_0011, RAM[0]);
    try testing.expect(flag_carry);
}

test "ROR normal" {
    flag_carry = false;
    opROR(0x0000, 0b0000_0010);
    try testing.expectEqual(0b0000_0001, RAM[0]);
    try testing.expect(!flag_carry);
}

test "ROR no previous carry" {
    flag_carry = false;
    opROR(0x0000, 0b0000_0001);
    try testing.expectEqual(0b0000_0000, RAM[0]);
    try testing.expect(flag_carry);
}

test "ROR /w previous carry" {
    flag_carry = true;
    opROR(0x0000, 0b1000_0001);
    try testing.expectEqual(0b1100_0000, RAM[0]);
    try testing.expect(flag_carry);
}

test "ORA" {
    A = 0b0101_0101;
    opORA(0b1010_1010);

    try testing.expectEqual(0xFF, A);
    try testing.expect(!flag_zero);
    try testing.expect(flag_negative);
}
