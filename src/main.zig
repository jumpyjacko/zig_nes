const std = @import("std");

const program_counter: u16 = undefined;
const A: u8 = undefined;
const X: u8 = undefined;
const Y: u8 = undefined;

const RAM: [0x800]u8 = undefined;
const ROM: [0x8000]u8 = undefined;

pub fn main() !void {

}

fn read(address: u16) u8 {
    if (address <= 0x1FFF) {
        return RAM[address & 0b0000_0111_1111_1111];
    }

    if (address >= 0x8000) {
        return ROM[address-0x8000];
    }
}
