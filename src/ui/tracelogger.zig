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

pub const TraceloggerWindow = struct {
    pub var window: QDialog = undefined;
    pub var tree_widget: QTreeWidget = undefined;
    pub var logging_enabled: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);

    fn addEntry(disassembly: []const u8, registers: []const u8, processor_flags: []const u8) void {
        const entries: [3][]const u8 = .{ disassembly, registers, processor_flags };
        const entry = QTreeWidgetItem.New2(main_window.AppWindow.gpa, &entries);
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
};

pub fn openTracelogger(action: QAction) callconv(.c) void {
    _ = action;

    TraceloggerWindow.window = QDialog.New(main_window.AppWindow.window);
    TraceloggerWindow.window.SetAttribute(qnamespace_enums.WidgetAttribute.WA_DeleteOnClose);
    TraceloggerWindow.window.Resize(750, 800);
    TraceloggerWindow.window.SetSizeGripEnabled(true);
    TraceloggerWindow.window.SetWindowTitle("zig_nes - tracelogger");

    const layout = QVBoxLayout.New(TraceloggerWindow.window);
    const top_layout = QHBoxLayout.New2();
    const label = QLabel.New3("Tracelogger");
    const logging_checkbox = QCheckBox.New3("Enable logging");
    logging_checkbox.SetLayoutDirection(qnamespace_enums.LayoutDirection.RightToLeft);
    logging_checkbox.OnStateChanged(TraceloggerWindow.checkboxClicked);

    top_layout.AddWidget(label);
    top_layout.AddStretch();
    top_layout.AddWidget(logging_checkbox);
    layout.AddLayout(top_layout);

    const mono_font = QFont.New2("monospace");

    TraceloggerWindow.tree_widget = QTreeWidget.New2();
    TraceloggerWindow.tree_widget.SetColumnCount(3);
    const headers: [3][]const u8 = .{ "Disassembly", "Registers", "Flags (nv|dizc)" };
    TraceloggerWindow.tree_widget.SetHeaderLabels(main_window.AppWindow.gpa, &headers);
    TraceloggerWindow.tree_widget.SetColumnWidth(0, 200);
    TraceloggerWindow.tree_widget.SetColumnWidth(1, 350);
    TraceloggerWindow.tree_widget.SetFont(mono_font);
    layout.AddWidget(TraceloggerWindow.tree_widget);

    TraceloggerWindow.window.Show();
}

pub fn log_trace() void {
    var buffer_1: [256]u8 = undefined;
    const opcode: u8 = emulator.read(emulator.PC);
    const disassembly = std.fmt.bufPrint(
        &buffer_1,
        "{x:0<4}: \t{x:0<2}  {s}",
        .{ emulator.PC, opcode, opcode_names[opcode] },
    ) catch @panic("Failed to buf print");

    var buffer_2: [256]u8 = undefined;
    const registers = std.fmt.bufPrint(
        &buffer_2,
        "A: 0x{x:0<2}  X: 0x{x:0<2}  Y: 0x{x:0<2}  SP: 0x{x:0<2}",
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

    TraceloggerWindow.addEntry(disassembly, registers, processor_flags);
}
