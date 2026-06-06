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

pub const MemViewerWindow = struct {
    pub var window: QDialog = undefined;
};

pub fn openMemViewer(action: QAction) callconv(.c) void {
    _ = action;

    MemViewerWindow.window = QDialog.New(main_window.AppWindow.window);
    MemViewerWindow.window.SetAttribute(qnamespace_enums.WidgetAttribute.WA_DeleteOnClose);
    MemViewerWindow.window.Resize(400, 600);
    MemViewerWindow.window.SetSizeGripEnabled(true);
    MemViewerWindow.window.SetWindowTitle("zig_nes - memory viewer");

    const layout = QVBoxLayout.New(MemViewerWindow.window);
    const label = QLabel.New3("Memory viewer");
    layout.AddWidget(label);

    const mono_font = QFont.New2("monospace");
    _ = mono_font;

    MemViewerWindow.window.Show();
}
