const std = @import("std");

const main_window = @import("ui/main_window.zig");
const tracelogger = @import("ui/tracelogger.zig");
const mem_viewer = @import("ui/mem_viewer.zig");
const pattern_tables = @import("ui/pattern_tables.zig");

// -- CPU --
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
pub var transfer_address: u16 = 0; // PPU t register
pub var vram_address: u16 = 0; // PPU v register
pub var ppu_x_register: u8 = 0;
var temp_vram_address: u16 = 0;
var ppu_read_buffer: u8 = 0;

pub var ppu_dot: u16 = 0; // pixel X
pub var ppu_scanline: u16 = 0; // pixel Y
pub var ppu_vblank: bool = false;

pub var ppu_mask_8pxmaskBG: bool = false;
pub var ppu_mask_8pxmaskSprites: bool = false;
pub var ppu_mask_RenderBG: bool = false;
pub var ppu_mask_RenderSprites: bool = false;

pub var ppu_nametable_select: u2 = 0;
pub var ppu_vram_inc_32mode: bool = false;
pub var ppu_sprite_pattern_table: bool = false;
pub var ppu_bg_pattern_table: bool = false;
pub var ppu_use_8x16_sprites: bool = false;
pub var ppu_enable_NMI: bool = false;

var ppu_shift_register_pattern_l: u16 = 0;
var ppu_shift_register_pattern_h: u16 = 0;
var ppu_shift_register_attribute_l: u16 = 0;
var ppu_shift_register_attribute_h: u16 = 0;

var ppu_8step_pattern_lowplane: u8 = 0;
var ppu_8step_pattern_highplane: u8 = 0;
var ppu_8step_attribute: u8 = 0;
var ppu_8step_nextcharacter: u16 = 0;
var ppu_8step_temp: u8 = 0;

// -- PPU logging --
pub var ppu_cycle: usize = 28;

pub const Colour = [3]u8;
pub const palette = [_]Colour{
    .{ 0x65, 0x65, 0x65 }, .{ 0x00, 0x2A, 0x84 }, .{ 0x15, 0x13, 0xA2 }, .{ 0x3A, 0x01, 0x9E },
    .{ 0x59, 0x00, 0x7A }, .{ 0x6A, 0x00, 0x3E }, .{ 0x68, 0x08, 0x00 }, .{ 0x53, 0x1D, 0x00 },
    .{ 0x32, 0x34, 0x00 }, .{ 0x0D, 0x46, 0x00 }, .{ 0x00, 0x4F, 0x00 }, .{ 0x00, 0x4C, 0x09 },
    .{ 0x00, 0x3F, 0x4B }, .{ 0x00, 0x00, 0x00 }, .{ 0x00, 0x00, 0x00 }, .{ 0x00, 0x00, 0x00 },
    .{ 0xAE, 0xAE, 0xAE }, .{ 0x17, 0x5F, 0xD6 }, .{ 0x43, 0x41, 0xFF }, .{ 0x75, 0x29, 0xFA },
    .{ 0x9E, 0x1D, 0xCA }, .{ 0xB4, 0x20, 0x7B }, .{ 0xB1, 0x33, 0x22 }, .{ 0x96, 0x4E, 0x00 },
    .{ 0x6A, 0x6C, 0x00 }, .{ 0x39, 0x84, 0x00 }, .{ 0x0F, 0x90, 0x00 }, .{ 0x00, 0x8D, 0x33 },
    .{ 0x00, 0x7B, 0x8C }, .{ 0x00, 0x00, 0x00 }, .{ 0x00, 0x00, 0x00 }, .{ 0x00, 0x00, 0x00 },
    .{ 0xFE, 0xFE, 0xFE }, .{ 0x66, 0xAF, 0xFF }, .{ 0x93, 0x90, 0xFF }, .{ 0xC5, 0x78, 0xFF },
    .{ 0xEE, 0x6C, 0xFF }, .{ 0xFF, 0x6F, 0xCA }, .{ 0xFF, 0x82, 0x71 }, .{ 0xE6, 0x9E, 0x25 },
    .{ 0xBA, 0xBC, 0x00 }, .{ 0x88, 0xD5, 0x01 }, .{ 0x5E, 0xE1, 0x32 }, .{ 0x47, 0xDD, 0x82 },
    .{ 0x4A, 0xCB, 0xDC }, .{ 0x4E, 0x4E, 0x4E }, .{ 0x00, 0x00, 0x00 }, .{ 0x00, 0x00, 0x00 },
    .{ 0xFE, 0xFE, 0xFE }, .{ 0xC0, 0xDE, 0xFF }, .{ 0xD2, 0xD1, 0xFF }, .{ 0xE7, 0xC7, 0xFF },
    .{ 0xF8, 0xC2, 0xFF }, .{ 0xFF, 0xC3, 0xE9 }, .{ 0xFF, 0xCB, 0xC4 }, .{ 0xF5, 0xD7, 0xA5 },
    .{ 0xE2, 0xE3, 0x94 }, .{ 0xCE, 0xED, 0x96 }, .{ 0xBC, 0xF2, 0xAA }, .{ 0xB3, 0xF1, 0xCB },
    .{ 0xB4, 0xE9, 0xF0 }, .{ 0xB6, 0xB6, 0xB6 }, .{ 0x00, 0x00, 0x00 }, .{ 0x00, 0x00, 0x00 },
};

pub fn runEmulatorThread(io: std.Io, path: []const u8) void {
    std.log.info("File path loaded: {s}", .{path});
    reset(io, path) catch |err| {
        std.log.err("Emulator failed to start: {any}", .{err});
        return;
    };
}

var ppu_address: u16 = 0;
pub fn read(address: u16) u8 {
    if (address < 0x2000) {
        return RAM[address & 0b0000_0111_1111_1111];
    } else if (address < 0x4000) {
        ppu_address = address & 0x2007;
        switch (ppu_address) {
            0x2002 => { // PPUSTATUS (incomplete)
                var ppu_status: u8 = 0;
                ppu_status |= if (ppu_vblank) 0x80 else 0;
                ppu_status |= 0x40;
                ppu_vblank = false;
                write_latch = false;
                return ppu_status;
            },
            0x2007 => {
                var temp = ppu_read_buffer;
                if (vram_address > 0x3F00) {
                    temp = readPPU(vram_address);
                } else {
                    ppu_read_buffer = readPPU(vram_address);
                }
                vram_address += if (ppu_vram_inc_32mode) 32 else 1;
                vram_address &= 0x3FFF;
                return temp;
            },
            else => {
                return 0;
            },
        }
    } else if (address >= 0x8000) {
        return ROM[address - 0x8000];
    }

    return 0; // i don't know what to do here
}

fn readPPU(address: u16) u8 {
    if (address < 0x2000) {
        return CHR_DATA[address];
    } else if (address < 0x3F00) {
        if ((HEADER[6] & 1) == 0) {
            return VRAM[(address & 0x3FF) | (address & 0x800) >> 1];
        } else {
            return VRAM[address & 0x7FF];
        }
    } else {
        if ((address & 3) == 0) {
            return PALETTE_RAM[address & 0x0F];
        } else {
            return PALETTE_RAM[address & 0x1F];
        }
    }
}

fn write(address: u16, value: u8) void {
    if (address >= 0x8000) return;

    if (address < 0x2000) {
        RAM[address & 0b0000_0111_1111_1111] = value;
        return;
    } else if (address < 0x4000) {
        ppu_address = address & 0x2007; // ppu ram mirroring
        switch (ppu_address) {
            0x2000 => { // PPUCTRL
                ppu_nametable_select = @intCast(value & 3);
                ppu_vram_inc_32mode = (value & 4) != 0;
                ppu_sprite_pattern_table = (value & 8) != 0;
                ppu_bg_pattern_table = (value & 0x10) != 0;
                ppu_use_8x16_sprites = (value & 0x20) != 0;
                ppu_enable_NMI = (value & 0x80) != 0;
            },
            0x2001 => { // PPUMASK
                ppu_mask_8pxmaskBG = (value & 2) != 0;
                ppu_mask_8pxmaskSprites = (value & 4) != 0;
                ppu_mask_RenderBG = (value & 8) != 0;
                ppu_mask_RenderSprites = (value & 0x10) != 0;
            },
            0x2002 => {},
            0x2003 => {},
            0x2004 => {},
            0x2005 => { // PPUSCROLL
                if (!write_latch) {
                    ppu_x_register = value & 7;
                    temp_vram_address = (temp_vram_address & 0b0111111111100000) | (value >> 3);
                } else {
                    transfer_address = (temp_vram_address & 0b0000110000011111) | (((value & 0xF8) << 2) | (@as(u16, value & 7) << 12));
                }
                write_latch = !write_latch;
            },
            0x2006 => { // PPUADDR
                if (!write_latch) {
                    temp_vram_address = (@as(u16, value) & 0x3F) << 8;
                } else {
                    vram_address = temp_vram_address | value;
                    transfer_address = vram_address;
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
                vram_address &= 0x3FFF;
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
    @memset(&VRAM, 0);
    @memset(&PALETTE_RAM, 0);
    @memset(&CHR_DATA, 0);
    try reader.interface.readSliceAll(&HEADER);
    try reader.interface.readSliceAll(&ROM);
    reader.interface.readSliceAll(&CHR_DATA) catch |err| {
        std.log.warn("No CHR_DATA found on rom, skipping... {}", .{err});
    };

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

    ppu_cycle = 28;
    ppu_dot = 28;
    ppu_scanline = 0;

    if (pattern_tables.window != null) pattern_tables.refreshPatternTables();
    try run();
}

fn run() !void {
    while (!CPU_halted.load(.monotonic)) {
        try emulate();
        total_cycles += cycles;

        while (cycles > 0) {
            cycles -= 1;
            emulatePPU();
            emulatePPU();
            emulatePPU();
        }
    }

    main_window.render();
}

var NMI_level_detector: bool = false;
var do_NMI: bool = false;
fn emulate() !void {
    const prev_NMI_level_detector = NMI_level_detector;
    NMI_level_detector = ppu_enable_NMI and ppu_vblank;
    if (!prev_NMI_level_detector and NMI_level_detector) {
        do_NMI = true;
    }

    var opcode: u8 = undefined;
    if (!do_NMI) {
        opcode = read(PC);
        if (tracelogger.logging_enabled.load(.monotonic)) {
            tracelogger.logTrace();
        }
        PC += 1;
    } else { // doing an NMI
        opcode = 0x00;
    }

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
            cycles = 2;
            opBranch(!flag_negative);
        },
        0x30 => { // BMI
            cycles = 2;
            opBranch(flag_negative);
        },
        0x50 => { // BVC
            cycles = 2;
            opBranch(!flag_overflow);
        },
        0x70 => { // BVS
            cycles = 2;
            opBranch(flag_overflow);
        },
        0x90 => { // BCC
            cycles = 2;
            opBranch(!flag_carry);
        },
        0xB0 => { // BCS
            cycles = 2;
            opBranch(flag_carry);
        },
        0xD0 => { // BNE
            cycles = 2;
            opBranch(!flag_zero);
        },
        0xF0 => { // BEQ
            cycles = 2;
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
            const address = readOperands_AbsoluteAddressed_XIdx();
            opINC(address, read(address));
            cycles = 7;
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
            const address = readOperands_AbsoluteAddressed_XIdx();
            opDEC(address, read(address));
            cycles = 7;
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
            if (!do_NMI) {
                PC += 1;
            }
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

            const temp_low = read(if (do_NMI) 0xFFFA else 0xFFFE);
            const temp_high: u16 = read(if (do_NMI) 0xFFFB else 0xFFFF);
            PC = (temp_high << 8) + temp_low;
            cycles = 7;
            do_NMI = false;
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
        cycles += 1;

        const old_pc = PC;
        PC = @as(u16, @intCast(@as(i32, PC) + offset));

        if ((old_pc & 0xFF00) != (PC & 0xFF00)) {
            cycles += 1;
        }
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

fn emulatePPU() void {
    if (ppu_dot == 1 and ppu_scanline == 241) {
        ppu_vblank = true;
    } else if (ppu_dot == 1 and ppu_scanline == 261) {
        ppu_vblank = false;
    }

    if (ppu_scanline < 240 or ppu_scanline == 261) {
        if ((ppu_dot > 0 and ppu_dot <= 256) or (ppu_dot > 320 and ppu_dot <= 336)) {
            if (ppu_mask_RenderBG or ppu_mask_RenderSprites) {
                if (ppu_mask_RenderBG) {
                    ppu_shift_register_pattern_l = ppu_shift_register_pattern_l << 1;
                    ppu_shift_register_pattern_h = ppu_shift_register_pattern_h << 1;
                    ppu_shift_register_attribute_l = ppu_shift_register_attribute_l << 1;
                    ppu_shift_register_attribute_h = ppu_shift_register_attribute_h << 1;
                }

                var cycle_tick: u8 = 0;
                cycle_tick = @intCast((ppu_dot - 1) & 7);
                switch (cycle_tick) {
                    0 => {
                        ppu_shift_register_pattern_l = (ppu_shift_register_pattern_l & 0xFF00) | ppu_8step_pattern_lowplane;
                        ppu_shift_register_pattern_h = (ppu_shift_register_pattern_h & 0xFF00) | ppu_8step_pattern_highplane;
                        ppu_shift_register_attribute_l = (ppu_shift_register_attribute_l & 0xFF00) | if ((ppu_8step_attribute & 1) == 1) @as(u16, 0xFF) else @as(u16, 0);
                        ppu_shift_register_attribute_h = (ppu_shift_register_attribute_h & 0xFF00) | if ((ppu_8step_attribute & 2) == 2) @as(u16, 0xFF) else @as(u16, 0);
                        ppu_address = 0x2000 + (vram_address & 0x0FFF);
                        ppu_8step_temp = readPPU(ppu_address);
                    },
                    1 => {
                        ppu_8step_nextcharacter = ppu_8step_temp;
                    },
                    2 => {
                        ppu_address = (0x23C0 | (vram_address & 0x0C00) | ((vram_address >> 4) & 0x38) | ((vram_address >> 2) & 0x07));
                        ppu_8step_temp = readPPU(ppu_address);
                    },
                    3 => {
                        ppu_8step_attribute = ppu_8step_temp;
                        if ((vram_address & 3) >= 2) {
                            ppu_8step_attribute = ppu_8step_attribute >> 2;
                        }
                        if ((((vram_address & 0b0000001111100000) >> 5) & 3) >= 2) {
                            ppu_8step_attribute = ppu_8step_attribute >> 4;
                        }
                        ppu_8step_attribute = ppu_8step_attribute & 3;
                    },
                    4 => {
                        ppu_address = (((vram_address & 0b0111000000000000) >> 12) | ppu_8step_nextcharacter * 16 | (if (ppu_bg_pattern_table) @as(u16, 0x1000) else @as(u16, 0)));
                        ppu_8step_temp = readPPU(ppu_address);
                    },
                    5 => {
                        ppu_8step_pattern_lowplane = ppu_8step_temp;
                        ppu_address += 8;
                    },
                    6 => {
                        ppu_8step_temp = readPPU(ppu_address);
                    },
                    7 => {
                        ppu_8step_pattern_highplane = ppu_8step_temp;
                        if ((vram_address & 0x001F) == 31) {
                            vram_address &= 0xFFE0;
                            vram_address ^= 0x0400;
                        } else {
                            vram_address += 1;
                        }
                    },
                    else => unreachable,
                }
            }
        }
    }

    if (ppu_dot == 256) {
        ppu_IncrementScrollY();
    } else if (ppu_dot == 257) {
        ppu_ResetXScroll();
    }
    if (ppu_dot >= 280 and ppu_dot <= 304 and ppu_scanline == 261) {
        ppu_ResetYScroll();
    }

    if (ppu_scanline < 241 and ppu_dot > 0 and ppu_dot <= 256) {
        var palette_high: u8 = 0; // which palette to use
        var palette_low: u8 = 0; // which indexed colour
        if (ppu_mask_RenderBG and (ppu_dot > 8 or ppu_mask_8pxmaskBG)) {
            const col0 = (ppu_shift_register_pattern_l >> @intCast(15 - ppu_x_register)) & 1;
            const col1 = (ppu_shift_register_pattern_h >> @intCast(15 - ppu_x_register)) & 1;
            palette_low = @truncate((col1 << 1) | col0);

            const pal0 = (ppu_shift_register_attribute_l >> @intCast(15 - ppu_x_register)) & 1;
            const pal1 = (ppu_shift_register_attribute_h >> @intCast(15 - ppu_x_register)) & 1;
            palette_high = @truncate((pal1 << 1) | pal0);

            if (palette_low == 0 and palette_high != 0) {
                palette_high = 0;
            }
        }

        const dot_palette = PALETTE_RAM[(palette_high << 2) + palette_low] & 0x3F;
        const colour = palette[dot_palette];

        const target_x = ppu_dot - 1;
        const target_y = ppu_scanline;
        main_window.render_buffer[target_y][target_x] = colour;
    }

    ppu_dot += 1;
    if (ppu_dot >= 341) {
        ppu_dot = 0;
        ppu_scanline += 1;
        if (ppu_scanline > 261) {
            ppu_scanline = 0;
        }
    }

    ppu_cycle += 1;
}

fn ppu_IncrementScrollY() void {
    if ((vram_address & 0x7000) != 0x7000) {
        vram_address += 0x1000;
    } else {
        vram_address &= 0x0FFF;
        var y = (vram_address & 0x03E0) >> 5;
        if (y == 29) {
            y = 0;
            vram_address ^= 0x0800;
        } else {
            y += 1;
            y &= 0x1F;
        }

        vram_address = (vram_address & 0xFC1F) | (y << 5);
    }
}

fn ppu_ResetXScroll() void {
    vram_address = (vram_address & 0b0111101111100000) | (transfer_address & 0b0000010000011111);
}

fn ppu_ResetYScroll() void {
    vram_address = (vram_address & 0b0000010000011111) | (transfer_address & 0b0111101111100000);
}
