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
const QTimer = qt6.QTimer;

const qnamespace_enums = qt6.qnamespace_enums;

pub var window: QWidget = undefined;
pub var tree_widget: QTreeWidget = undefined;
pub var ram_ptr: [*]u8 = &emulator.RAM;

fn refreshView(timer: QTimer) callconv(.c) void {
    _ = timer;
    if (tree_widget.ptr == null) return;

    tree_widget.Clear();

    const bytes_per_row = 16;
    const ram_size = 0x800;

    var i: usize = 0;
    while (i < ram_size) : (i += bytes_per_row) {
        var addr_buf: [10]u8 = undefined;
        const addr_str = std.fmt.bufPrint(&addr_buf, "0x{X:0>4} ", .{i}) catch "0x0000";

        var hex_buf: [64]u8 = undefined;
        var hex_idx: usize = 0;
        var ascii_buf: [16]u8 = undefined;

        for (0..bytes_per_row) |j| {
            if (i + j < ram_size) {
                if (j == 8) {
                    const sep_remaining = hex_buf[hex_idx..];
                    const sep_printed = std.fmt.bufPrint(sep_remaining, " ", .{}) catch "";
                    hex_idx += sep_printed.len;
                }

                const byte = ram_ptr[i + j];
                const remaining = hex_buf[hex_idx..];
                const printed = std.fmt.bufPrint(remaining, "{X:0>2} ", .{byte}) catch "";
                hex_idx += printed.len;

                ascii_buf[j] = if (byte >= 32 and byte <= 126) byte else '.';
            }
        }

        const entries: [3][]const u8 = .{ addr_str, hex_buf[0..hex_idx], ascii_buf[0..bytes_per_row] };
        const entry = QTreeWidgetItem.New2(main_window.gpa, &entries);
        tree_widget.AddTopLevelItem(entry);
    }
}

pub fn openMemViewer(action: QAction) callconv(.c) void {
    _ = action;

    window = QWidget.New(main_window.window);
    window.SetAttribute(qnamespace_enums.WidgetAttribute.WA_DeleteOnClose);
    window.Resize(750, 600);
    window.SetWindowTitle("zig_nes - memory viewer");
    window.SetWindowFlags(qnamespace_enums.WindowType.Window | qnamespace_enums.WindowType.WindowMinMaxButtonsHint | qnamespace_enums.WindowType.WindowCloseButtonHint);

    const update_timer = QTimer.New2(window);
    update_timer.OnTimeout(refreshView);
    update_timer.Start(100);

    const layout = QVBoxLayout.New(window);
    const label = QLabel.New3("Memory viewer");
    layout.AddWidget(label);

    const mono_font = QFont.New2("monospace");

    tree_widget = QTreeWidget.New2();
    tree_widget.SetColumnCount(3);
    const header = tree_widget.Header();
    header.SetSectionResizeMode(3); // ResizeToContents
    const headers: [3][]const u8 = .{ "", "00 01 02 03 04 05 06 07  08 09 0A 0B 0C 0D 0E 0F", "ASCII" };
    tree_widget.SetHeaderLabels(main_window.gpa, &headers);
    tree_widget.SetFont(mono_font);
    layout.AddWidget(tree_widget);

    window.Show();
}
