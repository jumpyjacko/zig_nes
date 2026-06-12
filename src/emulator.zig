const std = @import("std");

const tracelogger = @import("ui/tracelogger.zig");
const mem_viewer = @import("ui/mem_viewer.zig");
const pattern_tables = @import("ui/pattern_tables.zig");

pub var PC: u16 = undefined; // program counter
pub var A: u8 = undefined;
pub var X: u8 = undefined;
pub var Y: u8 = undefined;

pub var SP: u8 = undefined; // stack pointer

pub var RAM: [0x800]u8 = undefined;
pub var ROM: [0x8000]u8 = undefined;
pub var CHR_DATA: [0x2000]u8 = undefined;
pub var VRAM: [0x800]u8 = undefined;
pub var PALETTE_RAM: [0x20]u8 = undefined;

pub var HEADER: [16]u8 = undefined;

pub var flag_carry: bool = false;
pub var flag_zero: bool = false;
pub var flag_interupt_disable: bool = false;
pub var flag_decimal: bool = false;
pub var flag_overflow: bool = false;
pub var flag_negative: bool = false;

pub var CPU_halted: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);
pub var cycles: usize = 0;
pub var total_cycles: usize = 0;

// -- PPU --
pub var write_latch: bool = false; // PPU w register
pub var transfer_address: u16 = undefined; // PPU t register
pub var vram_address: u16 = undefined; // PPU v register
pub var ppu_vram_inc_32mode: bool = false;

pub fn runEmulatorThread(io: std.Io, path: []const u8) void {
    std.log.info("File path loaded: {s}", .{path});
    reset(io, path) catch |err| {
        std.log.err("Emulator failed to start: {any}", .{err});
        return;
    };
}

pub fn read(address: u16) u8 {
    if (address <= 0x1FFF) {
        return RAM[address & 0b0000_0111_1111_1111];
    }

    if (address >= 0x8000) {
        return ROM[address - 0x8000];
    }

    return 0; // i don't know what to do here
}

fn write(address: u16, value: u8) void {
    if (address >= 0x8000) return;

    if (address < 0x2000) {
        RAM[address & 0b0000_0111_1111_1111] = value;
        return;
    } else if (address < 0x4000) {
        const ppu_address = address & 0x2007; // ppu ram mirroring
        switch (ppu_address) {
            0x2000 => {},
            0x2001 => {},
            0x2002 => {},
            0x2003 => {},
            0x2004 => {},
            0x2005 => {},
            0x2006 => { // PPUADDR
                var temp_vram_address: u16 = 0;
                if (!write_latch) {
                    temp_vram_address = (@as(u16, value) & 0x3F) << 8;
                } else {
                    vram_address = temp_vram_address | value;
                }
                write_latch = !write_latch;
            },
            0x2007 => { // PPUDATA
                if (vram_address < 0x2000) {
                    if (HEADER[5] == 0) { // write to pattern table
                        CHR_DATA[vram_address] = value;
                    }
                } else if (vram_address < 0x3F00) {
                    if ((HEADER[6] & 1) == 0) { // horizontal mirroring
                        VRAM[(vram_address & 0x3FF) | (vram_address & 0x800) >> 1] = value;
                    } else { // vertical mirroring
                        VRAM[vram_address & 0x7FF] = value;
                    }
                } else { // write to palette ram
                    if ((vram_address & 3) == 0) {
                        PALETTE_RAM[vram_address & 0x0F] = value;
                    } else {
                        PALETTE_RAM[vram_address & 0x1F] = value;
                    }
                }

                vram_address += if (ppu_vram_inc_32mode) 32 else 1;
                vram_address &= 0x3FFF; // TODO: consider using u14
            },
            else => {},
        }
    }
}

fn push(value: u8) void {
    write(@as(u16, (@as(u16, 0x100) + SP)), value);
    SP -%= 1;
}

fn pull() u8 {
    SP +%= 1;
    return read(@as(u16, (@as(u16, 0x100) + SP)));
}

pub fn reset(io: std.Io, path: []const u8) !void {
    if (path.len == 0) return error.NoFile;

    var file = try std.Io.Dir.cwd().openFile(io, path, .{ .mode = .read_only });
    defer file.close(io);

    var buf: [4096]u8 = undefined;
    var reader = file.reader(io, &buf);

    @memset(&RAM, 0);
    try reader.interface.readSliceAll(&HEADER);
    try reader.interface.readSliceAll(&ROM);
    try reader.interface.readSliceAll(&CHR_DATA);

    A = 0;
    X = 0;
    Y = 0;
    SP = 0;

    const PC_low = read(0xFFFC);
    const PC_high = read(0xFFFD);

    PC = (@as(u16, PC_high) * 0x100) + @as(u16, PC_low);

    flag_interupt_disable = true;
    SP = 0xFD;

    total_cycles = 7;

    if (pattern_tables.window.ptr != null) pattern_tables.refreshPatternTables();
    try run();
}

fn run() !void {
    while (!CPU_halted.load(.monotonic)) {
        if (tracelogger.logging_enabled.load(.monotonic)) {
            tracelogger.logTrace();
        }

        try emulate();
        total_cycles += cycles;
    }
}

fn emulate() !void {
    const opcode: u8 = read(PC);
    PC += 1;

    switch (opcode) {
        0x02 => { // HLT
            CPU_halted.store(true, .monotonic);
        },
        0xA0 => { // LDY Immediate
            Y = read(PC);
            PC += 1;

            setFlags_ZN(Y);
            cycles = 2;
        },
        0xA4 => { // LDY Zero Page
            const address = readOperands_ZeroPage();
            Y = read(address);

            setFlags_ZN(Y);
            cycles = 3;
        },
        0xB4 => { // LDY Zero Page, X
            const address = readOperands_ZeroPage_XIdx();
            Y = read(address);

            setFlags_ZN(Y);
            cycles = 4;
        },
        0xAC => { // LDY Absolute
            const address = readOperands_AbsoluteAddressed();
            Y = read(address);

            setFlags_ZN(Y);
            cycles = 4;
        },
        0xBC => { // LDY Absolute, X
            cycles = 4;
            const address = readOperands_AbsoluteAddressed_XIdx();
            Y = read(address);

            setFlags_ZN(Y);
        },
        0xA2 => { // LDX Immediate
            X = read(PC);
            PC += 1;

            setFlags_ZN(X);
            cycles = 2;
        },
        0xA6 => { // LDX Zero Page
            const address = readOperands_ZeroPage();
            X = read(address);

            setFlags_ZN(X);
            cycles = 3;
        },
        0xB6 => { // LDX Zero Page, X
            const address = readOperands_ZeroPage_YIdx();
            X = read(address);

            setFlags_ZN(X);
            cycles = 4;
        },
        0xAE => { // LDX Absolute
            const address = readOperands_AbsoluteAddressed();
            X = read(address);

            setFlags_ZN(X);
            cycles = 4;
        },
        0xBE => { // LDX Absolute, Y
            cycles = 4;
            const address = readOperands_AbsoluteAddressed_YIdx();
            X = read(address);

            setFlags_ZN(X);
        },
        0xA9 => { // LDA Immediate
            A = read(PC);
            PC += 1;

            setFlags_ZN(A);
            cycles = 2;
        },
        0xA5 => { // LDA Zero Page
            const address = readOperands_ZeroPage();
            A = read(address);

            setFlags_ZN(A);
            cycles = 3;
        },
        0xB5 => { // LDA Zero Page, X
            const address = readOperands_ZeroPage_XIdx();
            A = read(address);

            setFlags_ZN(A);
            cycles = 4;
        },
        0xAD => { // LDA Absolute
            const address = readOperands_AbsoluteAddressed();
            A = read(address);

            setFlags_ZN(A);
            cycles = 4;
        },
        0xBD => { // LDA Absolute, X
            cycles = 4;
            const address = readOperands_AbsoluteAddressed_XIdx();
            A = read(address);

            setFlags_ZN(A);
        },
        0xB9 => { // LDA Absolute, Y
            cycles = 4;
            const address = readOperands_AbsoluteAddressed_YIdx();
            A = read(address);

            setFlags_ZN(A);
        },
        0xA1 => { // LDA Indirect, X
            const address = readOperands_IndirectAddressed_XIdx();
            A = read(address);

            cycles = 6;
            setFlags_ZN(A);
        },
        0xB1 => { // LDA Indirect, Y
            cycles = 5;
            const address = readOperands_IndirectAddressed_YIdx();
            A = read(address);

            setFlags_ZN(A);
        },
        0x85 => { // STA Zero Page
            const address = readOperands_ZeroPage();
            write(address, A);
            cycles = 3;
        },
        0x95 => { // STA Zero Page, X
            const address = readOperands_ZeroPage_XIdx();
            write(address, A);
            cycles = 4;
        },
        0x86 => { // STX Zero Page
            const address = readOperands_ZeroPage();
            write(address, X);
            cycles = 3;
        },
        0x96 => { // STX Zero Page, Y
            const address = readOperands_ZeroPage_YIdx();
            write(address, X);
            cycles = 4;
        },
        0x84 => { // STY Zero Page
            const address = readOperands_ZeroPage();
            write(address, Y);
            cycles = 3;
        },
        0x94 => { // STY Zero Page, X
            const address = readOperands_ZeroPage_XIdx();
            write(address, Y);
            cycles = 4;
        },
        0x8D => { // STA Absolute
            const address = readOperands_AbsoluteAddressed();
            write(address, A);
            cycles = 4;
        },
        0x9D => { // STA Absolute, X
            const address = readOperands_AbsoluteAddressed_XIdx();
            write(address, A);
            cycles = 5;
        },
        0x99 => { // STA Absolute, Y
            const address = readOperands_AbsoluteAddressed_YIdx();
            write(address, A);
            cycles = 5;
        },
        0x81 => { // STA Indirect, X
            const address = readOperands_IndirectAddressed_XIdx();
            write(address, A);
            cycles = 6;
        },
        0x91 => { // STA Indirect, Y
            const address = readOperands_IndirectAddressed_YIdx();
            write(address, A);
            cycles = 6;
        },
        0x8E => { // STX Absolute
            const address = readOperands_AbsoluteAddressed();
            write(address, X);
            cycles = 4;
        },
        0x8C => { // STY Absolute
            const address = readOperands_AbsoluteAddressed();
            write(address, Y);
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
            cycles = 3;
        },
        0x28 => { // PLP
            const status = pull();
            flag_carry = (status & 0b0000_0001) != 0;
            flag_zero = (status & 0b0000_0010) != 0;
            flag_interupt_disable = (status & 0b0000_0100) != 0;
            flag_decimal = (status & 0b0000_1000) != 0;
            flag_overflow = (status & 0b0100_0000) != 0;
            flag_negative = (status & 0b1000_0000) != 0;

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
        0x6C => { // JMP Indirect
            const i_addr_l = read(PC);
            PC += 1;
            const i_addr_h: u16 = read(PC);
            PC += 1;
            const indirect_address = (i_addr_h << 8) | i_addr_l;

            const addr_l = read(indirect_address);
            var addr_h: u16 = 0;
            if ((indirect_address & 0x00FF) == 0x00FF) { // if on page boundary
                addr_h = read(indirect_address & 0xFF00);
            } else {
                addr_h = read(indirect_address + 1);
            }

            PC = (addr_h << 8) | addr_l;
            cycles = 5;
        },
        0xE6 => { // INC Zero Page
            const address = readOperands_ZeroPage();
            opINC(address, read(address));
            cycles = 5;
        },
        0xF6 => { // INC Zero Page, X
            const address = readOperands_ZeroPage_XIdx();
            opINC(address, read(address));
            cycles = 6;
        },
        0xEE => { // INC Absolute
            const address = readOperands_AbsoluteAddressed();
            opINC(address, read(address));
            cycles = 6;
        },
        0xFE => { // INC Absolute, X
            cycles = 6;
            const address = readOperands_AbsoluteAddressed_XIdx();
            opINC(address, read(address));
        },
        0xC6 => { // DEC Zero Page
            const address = readOperands_ZeroPage();
            opDEC(address, read(address));
            cycles = 5;
        },
        0xD6 => { // DEC Zero Page, X
            const address = readOperands_ZeroPage_XIdx();
            opDEC(address, read(address));
            cycles = 6;
        },
        0xCE => { // DEC Absolute
            const address = readOperands_AbsoluteAddressed();
            opDEC(address, read(address));
            cycles = 6;
        },
        0xDE => { // DEC Absolute, X
            cycles = 6;
            const address = readOperands_AbsoluteAddressed_XIdx();
            opDEC(address, read(address));
        },
        0xE8 => { // INX
            X +%= 1;
            setFlags_ZN(X);
            cycles = 2;
        },
        0xCA => { // DEX
            X -%= 1;
            setFlags_ZN(X);
            cycles = 2;
        },
        0xC8 => { // INY
            Y +%= 1;
            setFlags_ZN(Y);
            cycles = 2;
        },
        0x88 => { // DEY
            Y -%= 1;
            setFlags_ZN(Y);
            cycles = 2;
        },
        0xAA => { // TAX
            X = A;
            setFlags_ZN(X);
            cycles = 2;
        },
        0x8A => { // TXA
            A = X;
            setFlags_ZN(A);
            cycles = 2;
        },
        0xA8 => { // TAY
            Y = A;
            setFlags_ZN(Y);
            cycles = 2;
        },
        0x98 => { // TYA
            A = Y;
            setFlags_ZN(A);
            cycles = 2;
        },
        0x9A => { // TXS
            SP = X;
            // DOES NOT SET ZN
            cycles = 2;
        },
        0xBA => { // TXS
            X = SP;
            setFlags_ZN(X);
            cycles = 2;
        },
        0x38 => { // SEC
            flag_carry = true;
            cycles = 2;
        },
        0x18 => { // CLC
            flag_carry = false;
            cycles = 2;
        },
        0xB8 => { // CLV
            flag_overflow = false;
            cycles = 2;
        },
        0x78 => { // SEI
            flag_interupt_disable = true;
            cycles = 2;
        },
        0x58 => { // CLI
            flag_interupt_disable = false;
            cycles = 2;
        },
        0xF8 => { // SED
            flag_decimal = true;
            cycles = 2;
        },
        0xD8 => { // CLD
            flag_decimal = false;
            cycles = 2;
        },
        0xEA => { // NOP
            cycles = 2;
        },
        0x0A => { // ASL A
            flag_carry = (A & 0b1000_0000) != 0;
            A = A << 1;
            setFlags_ZN(A);
            cycles = 2;
        },
        0x06 => { // ASL Zero Page
            const address = readOperands_ZeroPage();
            opASL(address, read(address));
            cycles = 5;
        },
        0x16 => { // ASL Zero Page, X
            const address = readOperands_ZeroPage_XIdx();
            opASL(address, read(address));
            cycles = 6;
        },
        0x0E => { // ASL Absolute
            const address = readOperands_AbsoluteAddressed();
            opASL(address, read(address));
            cycles = 6;
        },
        0x1E => { // ASL Absolute
            const address = readOperands_AbsoluteAddressed_XIdx();
            opASL(address, read(address));
            cycles = 7;
        },
        0x4A => { // LSR A
            flag_carry = (A & 1) != 0;
            A = A >> 1;
            setFlags_ZN(A);
            cycles = 2;
        },
        0x46 => { // LSR Zero Page
            const address = readOperands_ZeroPage();
            opLSR(address, read(address));
            cycles = 5;
        },
        0x56 => { // LSR Zero Page, X
            const address = readOperands_ZeroPage_XIdx();
            opLSR(address, read(address));
            cycles = 6;
        },
        0x4E => { // LSR Absolute
            const address = readOperands_AbsoluteAddressed();
            opLSR(address, read(address));
            cycles = 6;
        },
        0x5E => { // LSR Absolute, X
            const address = readOperands_AbsoluteAddressed_XIdx();
            opLSR(address, read(address));
            cycles = 7;
        },
        0x2A => { // ROL A
            const new_carry = (A & 0x80) != 0;
            A = A << 1;
            if (flag_carry) A |= 1;
            flag_carry = new_carry;
            setFlags_ZN(A);
            cycles = 2;
        },
        0x26 => { // ROL Zero Page
            const address = readOperands_ZeroPage();
            opROL(address, read(address));
            cycles = 5;
        },
        0x36 => { // ROL Zero Page, X
            const address = readOperands_ZeroPage_XIdx();
            opROL(address, read(address));
            cycles = 6;
        },
        0x2E => { // ROL Absolute
            const address = readOperands_AbsoluteAddressed();
            opROL(address, read(address));
            cycles = 6;
        },
        0x3E => { // ROL Absolute, X
            const address = readOperands_AbsoluteAddressed_XIdx();
            opROL(address, read(address));
            cycles = 7;
        },
        0x6A => { // ROR A
            const new_carry = (A & 1) != 0;
            A = A >> 1;
            if (flag_carry) A |= 0b1000_0000;
            flag_carry = new_carry;
            setFlags_ZN(A);
            cycles = 2;
        },
        0x66 => { // ROR Zero Page
            const address = readOperands_ZeroPage();
            opROR(address, read(address));
            cycles = 5;
        },
        0x76 => { // ROR Zero Page, X
            const address = readOperands_ZeroPage_XIdx();
            opROR(address, read(address));
            cycles = 6;
        },
        0x6E => { // ROR Absolute
            const address = readOperands_AbsoluteAddressed();
            opROR(address, read(address));
            cycles = 6;
        },
        0x7E => { // ROR Absolute, X
            const address = readOperands_AbsoluteAddressed_XIdx();
            opROR(address, read(address));
            cycles = 7;
        },
        0x09 => { // ORA Immediate
            const byte = read(PC);
            PC += 1;
            opORA(byte);
            cycles = 2;
        },
        0x05 => { // ORA Zero Page
            const address = readOperands_ZeroPage();
            opORA(read(address));
            cycles = 3;
        },
        0x15 => { // ORA Zero Page, X
            const address = readOperands_ZeroPage_XIdx();
            opORA(read(address));
            cycles = 4;
        },
        0x0D => { // ORA Absolute
            const address = readOperands_AbsoluteAddressed();
            opORA(read(address));
            cycles = 4;
        },
        0x1D => { // ORA Absolute, X
            cycles = 4;
            const address = readOperands_AbsoluteAddressed_XIdx();
            opORA(read(address));
        },
        0x19 => { // ORA Absolute, Y
            cycles = 4;
            const address = readOperands_AbsoluteAddressed_YIdx();
            opORA(read(address));
        },
        0x01 => { // ORA Indirect, X
            const address = readOperands_IndirectAddressed_XIdx();
            opORA(read(address));
            cycles = 6;
        },
        0x11 => { // ORA Indirect, Y
            cycles = 5;
            const address = readOperands_IndirectAddressed_YIdx();
            opORA(read(address));
        },
        0x29 => { // AND Immediate
            const byte = read(PC);
            PC += 1;
            opAND(byte);
            cycles = 2;
        },
        0x25 => { // AND Zero Page
            const address = readOperands_ZeroPage();
            opAND(read(address));
            cycles = 3;
        },
        0x35 => { // AND Zero Page, X
            const address = readOperands_ZeroPage_XIdx();
            opAND(read(address));
            cycles = 4;
        },
        0x2D => { // AND Absolute
            const address = readOperands_AbsoluteAddressed();
            opAND(read(address));
            cycles = 4;
        },
        0x3D => { // AND Absolute, X
            cycles = 4;
            const address = readOperands_AbsoluteAddressed_XIdx();
            opAND(read(address));
        },
        0x39 => { // AND Absolute, Y
            cycles = 4;
            const address = readOperands_AbsoluteAddressed_YIdx();
            opAND(read(address));
        },
        0x21 => { // AND Indirect, X
            const address = readOperands_IndirectAddressed_XIdx();
            opAND(read(address));
            cycles = 6;
        },
        0x31 => { // AND Indirect, Y
            cycles = 5;
            const address = readOperands_IndirectAddressed_YIdx();
            opAND(read(address));
        },
        0x49 => { // EOR Immediate
            const byte = read(PC);
            PC += 1;
            opEOR(byte);
            cycles = 2;
        },
        0x45 => { // EOR Zero Page
            const address = readOperands_ZeroPage();
            opEOR(read(address));
            cycles = 3;
        },
        0x55 => { // EOR Zero Page, X
            const address = readOperands_ZeroPage_XIdx();
            opEOR(read(address));
            cycles = 4;
        },
        0x4D => { // EOR Absolute
            const address = readOperands_AbsoluteAddressed();
            opEOR(read(address));
            cycles = 4;
        },
        0x5D => { // EOR Absolute, X
            cycles = 4;
            const address = readOperands_AbsoluteAddressed_XIdx();
            opEOR(read(address));
        },
        0x59 => { // EOR Absolute, Y
            cycles = 4;
            const address = readOperands_AbsoluteAddressed_YIdx();
            opEOR(read(address));
        },
        0x41 => { // EOR Indirect, X
            const address = readOperands_IndirectAddressed_XIdx();
            opEOR(read(address));
            cycles = 6;
        },
        0x51 => { // EOR Indirect, Y
            cycles = 5;
            const address = readOperands_IndirectAddressed_YIdx();
            opEOR(read(address));
        },
        0x69 => { // ADC Immediate
            const other = read(PC);
            PC += 1;
            opADC(other);
            cycles = 2;
        },
        0x65 => { // ADC Zero Page
            const address = readOperands_ZeroPage();
            opADC(read(address));
            cycles = 3;
        },
        0x75 => { // ADC Zero Page, X
            const address = readOperands_ZeroPage_XIdx();
            opADC(read(address));
            cycles = 4;
        },
        0x6D => { // ADC Absolute
            const address = readOperands_AbsoluteAddressed();
            opADC(read(address));
            cycles = 4;
        },
        0x7D => { // ADC Absolute, X
            cycles = 4;
            const address = readOperands_AbsoluteAddressed_XIdx();
            opADC(read(address));
        },
        0x79 => { // ADC Absolute, Y
            cycles = 4;
            const address = readOperands_AbsoluteAddressed_YIdx();
            opADC(read(address));
        },
        0x61 => { // ADC Indirect, X
            const address = readOperands_IndirectAddressed_XIdx();
            opADC(read(address));
            cycles = 6;
        },
        0x71 => { // ADC Indirect, Y
            cycles = 5;
            const address = readOperands_IndirectAddressed_YIdx();
            opADC(read(address));
        },
        0xE9 => { // SBC Immediate
            const other = read(PC);
            PC += 1;
            opSBC(other);
            cycles = 2;
        },
        0xE5 => { // SBC Zero Page
            const address = readOperands_ZeroPage();
            opSBC(read(address));
            cycles = 3;
        },
        0xF5 => { // SBC Zero Page, X
            const address = readOperands_ZeroPage_XIdx();
            opSBC(read(address));
            cycles = 4;
        },
        0xED => { // SBC Absolute
            const address = readOperands_AbsoluteAddressed();
            opSBC(read(address));
            cycles = 4;
        },
        0xFD => { // SBC Absolute, X
            cycles = 4;
            const address = readOperands_AbsoluteAddressed_XIdx();
            opSBC(read(address));
        },
        0xF9 => { // SBC Absolute, Y
            cycles = 4;
            const address = readOperands_AbsoluteAddressed_YIdx();
            opSBC(read(address));
        },
        0xE1 => { // SBC Indirect, X
            const address = readOperands_IndirectAddressed_XIdx();
            opSBC(read(address));
            cycles = 6;
        },
        0xF1 => { // SBC Indirect, Y
            cycles = 5;
            const address = readOperands_IndirectAddressed_YIdx();
            opSBC(read(address));
        },
        0xC9 => { // CMP Immediate
            const value = read(PC);
            PC += 1;
            opCMP(value, A);
            cycles = 2;
        },
        0xC5 => { // CMP Zero Page
            const address = readOperands_ZeroPage();
            opCMP(read(address), A);
            cycles = 3;
        },
        0xD5 => { // CMP Zero Page, X
            const address = readOperands_ZeroPage_XIdx();
            opCMP(read(address), A);
            cycles = 4;
        },
        0xCD => { // CMP Absolute
            const address = readOperands_AbsoluteAddressed();
            opCMP(read(address), A);
            cycles = 4;
        },
        0xDD => { // CMP Absolute, X
            cycles = 4;
            const address = readOperands_AbsoluteAddressed_XIdx();
            opCMP(read(address), A);
        },
        0xD9 => { // CMP Absolute, Y
            cycles = 4;
            const address = readOperands_AbsoluteAddressed_YIdx();
            opCMP(read(address), A);
        },
        0xC1 => { // CMP Indirect, X
            const address = readOperands_IndirectAddressed_XIdx();
            opCMP(read(address), A);
            cycles = 6;
        },
        0xD1 => { // CMP Indirect, Y
            cycles = 5;
            const address = readOperands_IndirectAddressed_YIdx();
            opCMP(read(address), A);
        },
        0xE0 => { // CPX Immediate
            const value = read(PC);
            PC += 1;
            opCMP(value, X);
            cycles = 2;
        },
        0xE4 => { // CPX Zero Page
            const address = readOperands_ZeroPage();
            opCMP(read(address), X);
            cycles = 3;
        },
        0xEC => { // CPX Absolute
            const address = readOperands_AbsoluteAddressed();
            opCMP(read(address), X);
            cycles = 4;
        },
        0xC0 => { // CPY Immediate
            const value = read(PC);
            PC += 1;
            opCMP(value, Y);
            cycles = 2;
        },
        0xC4 => { // CPY Zero Page
            const address = readOperands_ZeroPage();
            opCMP(read(address), Y);
            cycles = 3;
        },
        0xCC => { // CPY Absolute
            const address = readOperands_AbsoluteAddressed();
            opCMP(read(address), Y);
            cycles = 4;
        },
        0x24 => { // BIT Zero Page
            const address = readOperands_ZeroPage();
            opBIT(read(address));
            cycles = 3;
        },
        0x2C => { // BIT Absolute
            const address = readOperands_AbsoluteAddressed();
            opBIT(read(address));
            cycles = 4;
        },
        0x00 => { // BRK
            PC += 1;
            push(@truncate(PC >> 8));
            push(@truncate(PC));

            var status: u8 = 0;
            if (flag_carry) status |= 0b0000_0001;
            if (flag_zero) status |= 0b0000_0010;
            if (flag_interupt_disable) status |= 0b0000_0100;
            if (flag_decimal) status |= 0b0000_1000;
            status |= 0b0011_0000;
            if (flag_overflow) status |= 0b0100_0000;
            if (flag_negative) status |= 0b1000_0000;
            push(status);

            const temp_low = read(0xFFFE);
            const temp_high: u16 = read(0xFFFF);
            PC = (temp_high << 8) + temp_low;
            cycles = 7;
        },
        0x40 => { // RTI
            const status = pull();
            flag_carry = (status & 0b0000_0001) != 0;
            flag_zero = (status & 0b0000_0010) != 0;
            flag_interupt_disable = (status & 0b0000_0100) != 0;
            flag_decimal = (status & 0b0000_1000) != 0;
            flag_overflow = (status & 0b0100_0000) != 0;
            flag_negative = (status & 0b1000_0000) != 0;

            const address_low = pull();
            const address_high: u16 = pull();
            PC = (address_high << 8) + address_low;
            cycles = 6;
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
    write(address, result);
    setFlags_ZN(result);
}

fn opDEC(address: u16, value: u8) void {
    const result: u8 = value -% 1;
    write(address, result);
    setFlags_ZN(result);
}

fn opASL(address: u16, value: u8) void {
    flag_carry = (value & 0b1000_0000) != 0;
    const result = value << 1;

    write(address, result);
    setFlags_ZN(result);
}

fn opLSR(address: u16, value: u8) void {
    flag_carry = (value & 1) != 0;
    const result = value >> 1;

    write(address, result);
    setFlags_ZN(result);
}

fn opROL(address: u16, value: u8) void {
    const new_carry = (value & 0x80) != 0;

    var result = value << 1;
    if (flag_carry) result |= 1;

    write(address, result);
    flag_carry = new_carry;
    setFlags_ZN(result);
}

fn opROR(address: u16, value: u8) void {
    const new_carry = (value & 1) != 0;

    var result = value >> 1;
    if (flag_carry) result |= 0b1000_0000;

    write(address, result);
    flag_carry = new_carry;
    setFlags_ZN(result);
}

fn opORA(byte: u8) void {
    A |= byte;
    setFlags_ZN(A);
}

fn opAND(byte: u8) void {
    A &= byte;
    setFlags_ZN(A);
}

fn opEOR(byte: u8) void {
    A ^= byte;
    setFlags_ZN(A);
}

fn opADC(byte: u8) void {
    const sum: u32 = @as(u32, byte) + @as(u32, A) + (@intFromBool(flag_carry));
    flag_overflow = (~(A ^ byte) & (A ^ sum) & 0x80) != 0;
    flag_carry = sum > 0xFF;
    A = @truncate(sum);

    setFlags_ZN(A);
}

fn opSBC(byte: u8) void {
    const borrow: u8 = if (flag_carry) 0 else 1;
    const sum = @as(i32, A) - @as(i32, byte) - borrow;
    const final_sum = @as(u8, @truncate(@as(u32, @bitCast(sum))));
    flag_overflow = ((A ^ byte) & (A ^ final_sum) & 0x80) != 0;
    flag_carry = sum >= 0;
    A = final_sum;

    setFlags_ZN(A);
}

fn opCMP(byte: u8, register: u8) void {
    flag_carry = register >= byte;
    flag_zero = byte == register;
    const result = register -% byte;
    flag_negative = (result & 0x80) != 0;
}

fn opBIT(byte: u8) void {
    flag_zero = (A & byte) == 0;
    flag_negative = (byte & 0x80) != 0;
    flag_overflow = (byte & 0x40) != 0;
}

fn readOperands_ZeroPage() u16 {
    const address = read(PC);
    PC += 1;

    return address;
}

fn readOperands_ZeroPage_XIdx() u16 {
    var address: u8 = read(PC);
    PC += 1;
    address +%= X;
    return @as(u16, address);
}

fn readOperands_ZeroPage_YIdx() u16 {
    var address: u8 = read(PC);
    PC += 1;
    address +%= Y;
    return @as(u16, address);
}

fn readOperands_AbsoluteAddressed() u16 {
    const low = read(PC);
    PC += 1;

    const high: u16 = read(PC);
    PC += 1;

    return (high << 8) | low;
}

fn readOperands_AbsoluteAddressed_XIdx() u16 {
    const low = read(PC);
    PC += 1;
    const high: u16 = read(PC);
    PC += 1;
    const address = (high << 8) | low;
    const final_address = address + X;

    if ((address & 0xFF00) != (final_address & 0xFF00)) {
        cycles += 1;
    }

    return final_address;
}

fn readOperands_AbsoluteAddressed_YIdx() u16 {
    const low = read(PC);
    PC += 1;
    const high: u16 = read(PC);
    PC += 1;
    const address = (high << 8) | low;
    const final_address = address + Y;

    if ((address & 0xFF00) != (final_address & 0xFF00)) {
        cycles += 1;
    }

    return final_address;
}

fn readOperands_IndirectAddressed_XIdx() u16 {
    const base_address = read(PC);
    PC += 1;

    const temp = base_address +% X;
    const address_low: u16 = read(temp);
    const address_high: u16 = read(temp +% 1);

    const address = (address_high << 8) | address_low;
    return address;
}

fn readOperands_IndirectAddressed_YIdx() u16 {
    const temp = read(PC);
    PC += 1;

    const address_low: u16 = read(temp);
    const address_high: u16 = read(temp +% 1);
    const base_address = (address_high << 8) | address_low;
    const final_address = base_address +% Y;

    if ((base_address & 0xFF00) != (final_address & 0xFF00)) {
        cycles += 1;
    }

    return final_address;
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

    write(0x0000, 0x02);
    try testing.expectEqual(0x02, RAM[0]);
}

test "write() rom" {
    ROM[0] = 0x01;
    try testing.expectEqual(0x01, ROM[0]);

    write(0x8000, 0x02);
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

    const address = readOperands_AbsoluteAddressed();

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

test "AND" {
    A = 0b0101_0101;
    opAND(0b1000_0111);

    try testing.expectEqual(0b0000_0101, A);
    try testing.expect(!flag_zero);
    try testing.expect(!flag_negative);
}

test "EOR" {
    A = 0b0101_0101;
    opEOR(0b1011_0111);

    try testing.expectEqual(0b1110_0010, A);
    try testing.expect(!flag_zero);
    try testing.expect(flag_negative);
}

test "ADC normal" {
    A = 0x50;
    flag_carry = true;

    opADC(0x20);

    try testing.expectEqual(0x71, A);
    try testing.expect(!flag_zero);
    try testing.expect(!flag_negative);
    try testing.expect(!flag_carry);
    try testing.expect(!flag_overflow);
}

test "ADC carry set" {
    A = 0xF0;
    flag_carry = false;

    opADC(0x20);

    try testing.expectEqual(0x10, A);
    try testing.expect(!flag_zero);
    try testing.expect(!flag_negative);
    try testing.expect(flag_carry);
    try testing.expect(!flag_overflow);
}

test "ADC overflow set" {
    A = 0x70;
    flag_carry = false;

    opADC(0x20);

    try testing.expectEqual(0x90, A);
    try testing.expect(!flag_zero);
    try testing.expect(flag_negative);
    try testing.expect(!flag_carry);
    try testing.expect(flag_overflow);
}

test "SBC normal" {
    A = 0x50;
    flag_carry = true;

    opSBC(0x20);

    try testing.expectEqual(0x30, A);
    try testing.expect(!flag_zero);
    try testing.expect(!flag_negative);
    try testing.expect(flag_carry);
    try testing.expect(!flag_overflow);
}

test "SBC carry set" {
    A = 0x10;
    flag_carry = false;

    opSBC(0x20);

    try testing.expectEqual(0xEF, A);
    try testing.expect(!flag_zero);
    try testing.expect(flag_negative);
    try testing.expect(!flag_carry);
    try testing.expect(!flag_overflow);
}

test "SBC overflow set" {
    A = 0x90;
    flag_carry = false;

    opSBC(0x20);

    try testing.expectEqual(0x6F, A);
    try testing.expect(!flag_zero);
    try testing.expect(!flag_negative);
    try testing.expect(flag_carry);
    try testing.expect(flag_overflow);
}

test "CMP Z" {
    A = 1;
    opCMP(1, A);

    try testing.expectEqual(true, flag_zero);
}

test "CMP C" {
    A = 2;
    opCMP(1, A);

    try testing.expectEqual(false, flag_carry);
}

test "CMP 3" {
    A = 1;
    opCMP(5, A);

    try testing.expectEqual(true, flag_negative);
}

test "BIT 1" {
    A = 0b0101_0101;
    opBIT(0b1010_1010);

    try testing.expectEqual(true, flag_zero);
}

test "BIT 2" {
    A = 0b0101_0101;
    opBIT(0b1000_0000);

    try testing.expectEqual(true, flag_negative);
}

test "BIT 3" {
    A = 0b0101_0101;
    opBIT(0b0100_0000);

    try testing.expectEqual(true, flag_overflow);
}
