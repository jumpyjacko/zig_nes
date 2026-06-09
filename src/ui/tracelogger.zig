const std = @import("std");

const main_window = @import("main_window.zig");
const emulator = @import("../emulator.zig");

const qt6 = @import("libqt6zig");
const QWidget = qt6.QWidget;
const QMenuBar = qt6.QMenuBar;
const QMenu = qt6.QMenu;
const QAction = qt6.QAction;
const QKeySequence = qt6.QKeySequence;
const QVBoxLayout = qt6.QVBoxLayout;
const QHBoxLayout = qt6.QHBoxLayout;
const QLabel = qt6.QLabel;
const QTreeWidget = qt6.QTreeWidget;
const QTreeWidgetItem = qt6.QTreeWidgetItem;
const QDialog = qt6.QDialog;
const QCheckBox = qt6.QCheckBox;
const QFont = qt6.QFont;

const qnamespace_enums = qt6.qnamespace_enums;

const AddressingMode = enum {
    Implied, // No arguments (1 byte total)
    Immediate, // 8-bit constant (#$XX)
    ZeroPage, // 8-bit RAM address ($XX)
    ZeroPageX, // 8-bit RAM address + X ($XX,X)
    ZeroPageY, // 8-bit RAM address + Y ($XX,Y)
    Absolute, // 16-bit RAM address ($XXXX)
    AbsoluteX, // 16-bit RAM address + X ($XXXX,X)
    AbsoluteY, // 16-bit RAM address + Y ($XXXX,Y)
    Indirect, // 16-bit pointer pointer (($XXXX))
    IndirectX, // Pre-indexed indirect (($XX,X))
    IndirectY, // Post-indexed indirect (($XX),Y)
    Relative, // 8-bit signed offset for branches
};

const opcode_names = [_][]const u8{
    "BRK", "ORA", "HLT", "SLO", "NOP", "ORA", "ASL", "SLO", "PHP", "ORA", "ASL", "ANC", "NOP", "ORA", "ASL", "SLO",
    "BPL", "ORA", "HLT", "SLO", "NOP", "ORA", "ASL", "SLO", "CLC", "ORA", "NOP", "SLO", "NOP", "ORA", "ASL", "SLO",
    "JSR", "AND", "HLT", "RLA", "BIT", "AND", "ROL", "RLA", "PLP", "AND", "ROL", "ANC", "BIT", "AND", "ROL", "RLA",
    "BMI", "AND", "HLT", "RLA", "NOP", "AND", "ROL", "RLA", "SEC", "AND", "NOP", "RLA", "NOP", "AND", "ROL", "RLA",
    "RTI", "EOR", "HLT", "SRE", "NOP", "EOR", "LSR", "SRE", "PHA", "EOR", "LSR", "ALR", "JMP", "EOR", "LSR", "SRE",
    "BVC", "EOR", "HLT", "SRE", "NOP", "EOR", "LSR", "SRE", "CLI", "EOR", "NOP", "SRE", "NOP", "EOR", "LSR", "SRE",
    "RTS", "ADC", "HLT", "RRA", "NOP", "ADC", "ROR", "RRA", "PLA", "ADC", "ROR", "ARR", "JMP", "ADC", "ROR", "RRA",
    "BVS", "ADC", "HLT", "RRA", "NOP", "ADC", "ROR", "RRA", "SEI", "ADC", "NOP", "RRA", "NOP", "ADC", "ROR", "RRA",
    "NOP", "STA", "NOP", "SAX", "STY", "STA", "STX", "SAX", "DEY", "NOP", "TXA", "ANE", "STY", "STA", "STX", "SAX",
    "BCC", "STA", "HLT", "SHA", "STY", "STA", "STX", "SAX", "TYA", "STA", "TXS", "SHS", "SHY", "STA", "SHX", "SHA",
    "LDY", "LDA", "LDX", "LAX", "LDY", "LDA", "LDX", "LAX", "TAY", "LDA", "TAX", "LXA", "LDY", "LDA", "LDX", "LAX",
    "BCS", "LDA", "HLT", "LAX", "LDY", "LDA", "LDX", "LAX", "CLV", "LDA", "TSX", "LAE", "LDY", "LDA", "LDX", "LAX",
    "CPY", "CMP", "NOP", "DCP", "CPY", "CMP", "DEC", "DCP", "INY", "CMP", "DEX", "AXS", "CPY", "CMP", "DEC", "DCP",
    "BNE", "CMP", "HLT", "DCP", "NOP", "CMP", "DEC", "DPC", "CLD", "CMP", "NOP", "DCP", "NOP", "CMP", "DEC", "DCP",
    "CPX", "SBC", "NOP", "ISC", "CPX", "SBC", "INC", "ISC", "INX", "SBC", "NOP", "SBC", "CPX", "SBC", "INC", "ISC",
    "BEQ", "SBC", "HLT", "ISC", "NOP", "SBC", "INC", "ISC", "SED", "SBC", "NOP", "ISC", "NOP", "SBC", "INC", "ISC",
};

const opcode_lengths = [_]u8{
    7, 2, 0, 2, 2, 2, 2, 2, 1, 2, 1, 2, 3, 3, 3, 3,
    2, 2, 0, 2, 2, 2, 2, 2, 1, 3, 1, 3, 3, 3, 3, 3,
    3, 2, 0, 2, 2, 2, 2, 2, 1, 2, 1, 2, 3, 3, 3, 3,
    2, 2, 0, 2, 2, 2, 2, 2, 1, 3, 1, 3, 3, 3, 3, 3,
    1, 2, 0, 2, 2, 2, 2, 2, 1, 2, 1, 2, 3, 3, 3, 3,
    2, 2, 0, 2, 2, 2, 2, 2, 1, 3, 1, 3, 3, 3, 3, 3,
    1, 2, 0, 2, 2, 2, 2, 2, 1, 2, 1, 2, 3, 3, 3, 3,
    2, 2, 0, 2, 2, 2, 2, 2, 1, 3, 1, 3, 3, 3, 3, 3,
    2, 2, 2, 2, 2, 2, 2, 2, 1, 2, 1, 2, 3, 3, 3, 3,
    2, 2, 0, 2, 2, 2, 2, 2, 1, 3, 1, 3, 3, 3, 3, 3,
    2, 2, 2, 2, 2, 2, 2, 2, 1, 2, 1, 2, 3, 3, 3, 3,
    2, 2, 0, 2, 2, 2, 2, 2, 1, 3, 1, 3, 3, 3, 3, 3,
    2, 2, 2, 2, 2, 2, 2, 2, 1, 2, 1, 2, 3, 3, 3, 3,
    2, 2, 0, 2, 2, 2, 2, 2, 1, 3, 1, 3, 3, 3, 3, 3,
    2, 2, 2, 2, 2, 2, 2, 2, 1, 2, 1, 2, 3, 3, 3, 3,
    2, 2, 0, 2, 2, 2, 2, 2, 1, 3, 1, 3, 3, 3, 3, 3,
};

const opcode_modes = [_]AddressingMode{
    .Implied,   .IndirectX, .Implied,   .IndirectX, .ZeroPage,  .ZeroPage,  .ZeroPage,  .ZeroPage,  .Implied, .Immediate, .Implied, .Immediate, .Absolute,  .Absolute,  .Absolute,  .Absolute,
    .Relative,  .IndirectY, .Implied,   .IndirectY, .ZeroPageX, .ZeroPageX, .ZeroPageX, .ZeroPageX, .Implied, .AbsoluteY, .Implied, .AbsoluteY, .AbsoluteX, .AbsoluteX, .AbsoluteX, .AbsoluteX,
    .Absolute,  .IndirectX, .Implied,   .IndirectX, .ZeroPage,  .ZeroPage,  .ZeroPage,  .ZeroPage,  .Implied, .Immediate, .Implied, .Immediate, .Absolute,  .Absolute,  .Absolute,  .Absolute,
    .Relative,  .IndirectY, .Implied,   .IndirectY, .ZeroPageX, .ZeroPageX, .ZeroPageX, .ZeroPageX, .Implied, .AbsoluteY, .Implied, .AbsoluteY, .AbsoluteX, .AbsoluteX, .AbsoluteX, .AbsoluteX,
    .Implied,   .IndirectX, .Implied,   .IndirectX, .ZeroPage,  .ZeroPage,  .ZeroPage,  .ZeroPage,  .Implied, .Immediate, .Implied, .Immediate, .Absolute,  .Absolute,  .Absolute,  .Absolute,
    .Relative,  .IndirectY, .Implied,   .IndirectY, .ZeroPageX, .ZeroPageX, .ZeroPageX, .ZeroPageX, .Implied, .AbsoluteY, .Implied, .AbsoluteY, .AbsoluteX, .AbsoluteX, .AbsoluteX, .AbsoluteX,
    .Implied,   .IndirectX, .Implied,   .IndirectX, .ZeroPage,  .ZeroPage,  .ZeroPage,  .ZeroPage,  .Implied, .Immediate, .Implied, .Immediate, .Indirect,  .Absolute,  .Absolute,  .Absolute,
    .Relative,  .IndirectY, .Implied,   .IndirectY, .ZeroPageX, .ZeroPageX, .ZeroPageX, .ZeroPageX, .Implied, .AbsoluteY, .Implied, .AbsoluteY, .AbsoluteX, .AbsoluteX, .AbsoluteX, .AbsoluteX,
    .Immediate, .IndirectX, .Immediate, .IndirectX, .ZeroPage,  .ZeroPage,  .ZeroPage,  .ZeroPage,  .Implied, .Immediate, .Implied, .Immediate, .Absolute,  .Absolute,  .Absolute,  .Absolute,
    .Relative,  .IndirectY, .Implied,   .IndirectY, .ZeroPageX, .ZeroPageX, .ZeroPageY, .ZeroPageY, .Implied, .AbsoluteY, .Implied, .AbsoluteY, .AbsoluteX, .AbsoluteX, .AbsoluteY, .AbsoluteY,
    .Immediate, .IndirectX, .Immediate, .IndirectX, .ZeroPage,  .ZeroPage,  .ZeroPage,  .ZeroPage,  .Implied, .Immediate, .Implied, .Immediate, .Absolute,  .Absolute,  .Absolute,  .Absolute,
    .Relative,  .IndirectY, .Implied,   .IndirectY, .ZeroPageX, .ZeroPageX, .ZeroPageY, .ZeroPageY, .Implied, .AbsoluteY, .Implied, .AbsoluteY, .AbsoluteX, .AbsoluteX, .AbsoluteY, .AbsoluteY,
    .Immediate, .IndirectX, .Immediate, .IndirectX, .ZeroPage,  .ZeroPage,  .ZeroPage,  .ZeroPage,  .Implied, .Immediate, .Implied, .Immediate, .Absolute,  .Absolute,  .Absolute,  .Absolute,
    .Relative,  .IndirectY, .Implied,   .IndirectY, .ZeroPageX, .ZeroPageX, .ZeroPageX, .ZeroPageX, .Implied, .AbsoluteY, .Implied, .AbsoluteY, .AbsoluteX, .AbsoluteX, .AbsoluteX, .AbsoluteX,
    .Immediate, .IndirectX, .Immediate, .IndirectX, .ZeroPage,  .ZeroPage,  .ZeroPage,  .ZeroPage,  .Implied, .Immediate, .Implied, .Immediate, .Absolute,  .Absolute,  .Absolute,  .Absolute,
    .Relative,  .IndirectY, .Implied,   .IndirectY, .ZeroPageX, .ZeroPageX, .ZeroPageX, .ZeroPageX, .Implied, .AbsoluteY, .Implied, .AbsoluteY, .AbsoluteX, .AbsoluteX, .AbsoluteX, .AbsoluteX,
};

pub var window: QWidget = undefined;
pub var tree_widget: QTreeWidget = undefined;
pub var logging_enabled: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);

pub fn openTracelogger(action: QAction) callconv(.c) void {
    _ = action;

    window = QWidget.New(main_window.window);
    window.SetAttribute(qnamespace_enums.WidgetAttribute.WA_DeleteOnClose);
    window.Resize(820, 800);
    window.SetWindowTitle("zig_nes - tracelogger");
    window.SetWindowFlags(qnamespace_enums.WindowType.Window | qnamespace_enums.WindowType.WindowMinMaxButtonsHint | qnamespace_enums.WindowType.WindowCloseButtonHint);

    const layout = QVBoxLayout.New(window);
    const top_layout = QHBoxLayout.New2();
    const label = QLabel.New3("Tracelogger");
    const logging_checkbox = QCheckBox.New3("Enable logging");
    logging_checkbox.SetLayoutDirection(qnamespace_enums.LayoutDirection.RightToLeft);
    logging_checkbox.OnStateChanged(checkboxClicked);

    top_layout.AddWidget(label);
    top_layout.AddStretch();
    top_layout.AddWidget(logging_checkbox);
    layout.AddLayout(top_layout);

    const mono_font = QFont.New2("monospace");

    tree_widget = QTreeWidget.New2();
    tree_widget.SetColumnCount(4);
    const headers: [4][]const u8 = .{ "Disassembly", "Registers", "Flags (nv|dizc)", "Cycle" };
    tree_widget.SetHeaderLabels(main_window.gpa, &headers);
    tree_widget.SetColumnWidth(0, 300);
    tree_widget.SetColumnWidth(1, 275);
    tree_widget.SetColumnWidth(2, 150);
    tree_widget.SetColumnWidth(3, 50);
    tree_widget.SetFont(mono_font);
    layout.AddWidget(tree_widget);

    window.OnDestroyed(windowClose);
    window.Show();
}

pub fn log_trace() void {
    var buffer_1: [256]u8 = undefined;
    const opcode: u8 = emulator.read(emulator.PC);
    const len = opcode_lengths[opcode];
    const name = opcode_names[opcode];
    const mode = opcode_modes[opcode];

    var disassembly: []const u8 = undefined;

    if (len == 0) {
        disassembly = std.fmt.bufPrint(
            &buffer_1,
            "{X:0>4}: \t{X:0>2}        {s} (HLT)",
            .{ emulator.PC, opcode, name },
        ) catch @panic("Failed to buf print");
    } else {
        const arg1 = if (len > 1) emulator.read(emulator.PC + 1) else 0;
        const arg2 = if (len > 2) emulator.read(emulator.PC + 2) else 0;
        const combined_address = (@as(u16, arg2) << 8) | arg1;

        var hex_buf: [12]u8 = undefined;
        const hex_dump = switch (len) {
            1 => std.fmt.bufPrint(&hex_buf, "{X:0>2}      ", .{opcode}) catch "",
            2 => std.fmt.bufPrint(&hex_buf, "{X:0>2} {X:0>2}   ", .{ opcode, arg1 }) catch "",
            3 => std.fmt.bufPrint(&hex_buf, "{X:0>2} {X:0>2} {X:0>2}", .{ opcode, arg1, arg2 }) catch "",
            else => std.fmt.bufPrint(&hex_buf, "{X:0>2}      ", .{opcode}) catch "",
        };

        // Format the syntax based on the actual addressing mode
        var syntax_buf: [32]u8 = undefined;
        const syntax = switch (mode) {
            .Implied => std.fmt.bufPrint(&syntax_buf, "{s}", .{name}) catch "",
            .Immediate => std.fmt.bufPrint(&syntax_buf, "{s} #{X:0>2}", .{ name, arg1 }) catch "",
            .ZeroPage => std.fmt.bufPrint(&syntax_buf, "{s} <${X:0>2}", .{ name, arg1 }) catch "",
            .ZeroPageX => std.fmt.bufPrint(&syntax_buf, "{s} <${X:0>2},X", .{ name, arg1 }) catch "",
            .ZeroPageY => std.fmt.bufPrint(&syntax_buf, "{s} <${X:0>2},Y", .{ name, arg1 }) catch "",
            .Absolute => std.fmt.bufPrint(&syntax_buf, "{s} ${X:0>4}", .{ name, combined_address }) catch "",
            .AbsoluteX => std.fmt.bufPrint(&syntax_buf, "{s} ${X:0>4},X", .{ name, combined_address }) catch "",
            .AbsoluteY => std.fmt.bufPrint(&syntax_buf, "{s} ${X:0>4},Y", .{ name, combined_address }) catch "",
            .Indirect => label: {
                const low: u16 = emulator.read(combined_address);
                const high: u16 = emulator.read(combined_address +% 1);
                const target = (high << 8) | low;
                break :label std.fmt.bufPrint(&syntax_buf, "{s} (${X:0>4}) -> ${X:0>4}", .{ name, combined_address, target }) catch "";
            },
            .IndirectX => label: {
                const temp = arg1 +% emulator.X;
                const low: u16 = emulator.read(temp);
                const high: u16 = emulator.read(temp +% 1);
                const target = (high << 8) | low;
                break :label std.fmt.bufPrint(&syntax_buf, "{s} (${X:0>2},X) -> ${X:0>4}", .{ name, arg1, target }) catch "";
            },
            .IndirectY => label: {
                const low: u16 = emulator.read(arg1);
                const high: u16 = emulator.read(arg1 +% 1);
                const base = (high << 8) | low;
                const target = base +% emulator.Y;
                break :label std.fmt.bufPrint(&syntax_buf, "{s} (${X:0>2}),Y -> ${X:0>4}", .{ name, arg1, target }) catch "";
            },
            .Relative => label: {
                const offset = @as(i8, @bitCast(arg1));
                const target_pc = @as(u16, @intCast(@as(i32, @intCast(emulator.PC)) + 2 + offset));
                break :label std.fmt.bufPrint(&syntax_buf, "{s} ${X:0>4}", .{ name, target_pc }) catch "";
            },
        };

        disassembly = std.fmt.bufPrint(
            &buffer_1,
            "{X:0>4}: \t{s}  {s}",
            .{ emulator.PC, hex_dump, syntax },
        ) catch @panic("Failed to buf print");
    }

    var buffer_2: [256]u8 = undefined;
    const registers = std.fmt.bufPrint(
        &buffer_2,
        "A: {X:0>2}  X: {X:0>2}  Y: {X:0>2}  SP: {X:0>2}",
        .{ emulator.A, emulator.X, emulator.Y, emulator.SP },
    ) catch @panic("Failed to buf print");

    var buffer_3: [256]u8 = undefined;
    const processor_flags = std.fmt.bufPrint(
        &buffer_3,
        "{s} {s} | {s} {s} {s} {s}",
        .{
            (if (emulator.flag_negative) "N" else "-"),
            (if (emulator.flag_overflow) "V" else "-"),
            (if (emulator.flag_decimal) "D" else "-"),
            (if (emulator.flag_interupt_disable) "I" else "-"),
            (if (emulator.flag_zero) "Z" else "-"),
            (if (emulator.flag_carry) "C" else "-"),
        },
    ) catch @panic("Failed to buf print");

    const cycle = std.fmt.allocPrint(main_window.gpa, "{d}", .{emulator.total_cycles}) catch {
        return;
    };
    defer main_window.gpa.free(cycle);

    addEntry(disassembly, registers, processor_flags, cycle);
}

fn addEntry(disassembly: []const u8, registers: []const u8, processor_flags: []const u8, cycle: []const u8) void {
    const entries: [4][]const u8 = .{ disassembly, registers, processor_flags, cycle };
    const entry = QTreeWidgetItem.New2(main_window.gpa, &entries);
    tree_widget.AddTopLevelItem(entry);
}

fn checkboxClicked(checkbox: QCheckBox, state: i32) callconv(.c) void {
    _ = checkbox;
    if (state == 0) {
        logging_enabled.store(false, .monotonic);
    } else {
        logging_enabled.store(true, .monotonic);
    }

    std.log.debug("Checkbox clicked, logging enabled state: {}", .{logging_enabled.load(.monotonic)});
}

fn windowClose(widget: QWidget) callconv(.c) void {
    _ = widget;
    logging_enabled.store(false, .monotonic);
}
