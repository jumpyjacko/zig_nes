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
const QLabel = qt6.QLabel;
const QTreeWidget = qt6.QTreeWidget;
const QTreeWidgetItem = qt6.QTreeWidgetItem;
const QDialog = qt6.QDialog;

const qnamespace_enums = qt6.qnamespace_enums;

pub const TraceloggerWindow = struct {
    pub var window: QDialog = undefined;
    pub var tree_widget: QTreeWidget = undefined;

    fn addEntry(disassembly: []const u8, registers: []const u8) void {
        const entry = QTreeWidgetItem.New2(main_window.AppWindow.gpa, .{ disassembly, registers });
        tree_widget.AddTopLevelItem(entry);
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
    const label = QLabel.New3("Tracelogger");
    layout.AddWidget(label);

    TraceloggerWindow.tree_widget = QTreeWidget.New2();
    TraceloggerWindow.tree_widget.SetColumnCount(2);
    const headers: [2][]const u8 = .{ "Disassembly", "Register" };
    TraceloggerWindow.tree_widget.SetHeaderLabels(main_window.AppWindow.gpa, &headers);
    layout.AddWidget(TraceloggerWindow.tree_widget);

    TraceloggerWindow.window.Show();
}
