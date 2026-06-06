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

const qnamespace_enums = qt6.qnamespace_enums;

pub const TraceloggerWindow = struct {
    pub var window: QDialog = undefined;
    pub var tree_widget: QTreeWidget = undefined;
    pub var logging_enabled: bool = false;

    fn addEntry(disassembly: []const u8, registers: []const u8) void {
        const entry = QTreeWidgetItem.New2(main_window.AppWindow.gpa, .{ disassembly, registers });
        tree_widget.AddTopLevelItem(entry);
    }

    fn checkboxClicked(checkbox: QCheckBox, state: i32) callconv(.c) void {
        _ = checkbox;
        logging_enabled = state > 0;

        std.log.debug("Checkbox clicked, logging enabled state: {}", .{logging_enabled});
    }
};

pub fn openTracelogger(action: QAction) callconv(.c) void {
    _ = action;

    TraceloggerWindow.window = QDialog.New(main_window.AppWindow.window);
    TraceloggerWindow.window.SetAttribute(qnamespace_enums.WidgetAttribute.WA_DeleteOnClose);
    TraceloggerWindow.window.Resize(500, 600);
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

    TraceloggerWindow.tree_widget = QTreeWidget.New2();
    TraceloggerWindow.tree_widget.SetColumnCount(2);
    const headers: [2][]const u8 = .{ "Disassembly", "Register" };
    TraceloggerWindow.tree_widget.SetHeaderLabels(main_window.AppWindow.gpa, &headers);
    layout.AddWidget(TraceloggerWindow.tree_widget);

    TraceloggerWindow.window.Show();
}
