const std = @import("std");
const qt6 = @import("libqt6zig");

const QApplication = qt6.QApplication;
const QMainWindow = qt6.QMainWindow;
const QWidget = qt6.QWidget;
const QMenuBar = qt6.QMenuBar;
const QMenu = qt6.QMenu;
const QAction = qt6.QAction;
const QKeySequence = qt6.QKeySequence;
const QVBoxLayout = qt6.QVBoxLayout;
const QLabel = qt6.QLabel;
const QListWidget = qt6.QListWidget;

const qnamespace_enums = qt6.qnamespace_enums;

const AppWindow = struct {
    var window: QMainWindow = undefined;

    fn exit_window(action: QAction) callconv(.c) void {
        _ = action;
        _ = window.Close();
    }
};

pub fn initQtApplication(init: std.process.Init) !void {
    const argv = try qt6.init(init.gpa, init.minimal.args);
    defer qt6.deinit(init.gpa, argv);
    var argc: i32 = @intCast(argv.len);

    const qapp = QApplication.New(init.arena.allocator(), &argc, argv);
    defer qapp.Delete();

    AppWindow.window = QMainWindow.New2();
    defer AppWindow.window.Delete();
    AppWindow.window.SetFixedSize2(300, 250);

    const widget = QWidget.New2();
    defer widget.Delete();
    AppWindow.window.SetCentralWidget(widget);

    const menu_bar = QMenuBar.New2();
    AppWindow.window.SetMenuBar(menu_bar);
    menu_bar.SetNativeMenuBar(false);

    const file_menu = menu_bar.AddMenu2("Emulator");
    const load_rom_action = QAction.New2("Load rom...");
    file_menu.AddAction(load_rom_action);

    const reset_action = QAction.New2("Reset");
    file_menu.AddAction(reset_action);

    const exit_action = QAction.New2("Exit");
    exit_action.SetShortcut(QKeySequence.New2("Ctrl+Q"));
    exit_action.OnTriggered(AppWindow.exit_window);
    file_menu.AddAction(exit_action);

    const tools_menu = menu_bar.AddMenu2("Tools");
    const tracelogger_action = QAction.New2("Tracelogger");
    // traceloggerAction.OnTriggered();
    tools_menu.AddAction(tracelogger_action);

    AppWindow.window.Show();

    _ = QApplication.Exec();
}
