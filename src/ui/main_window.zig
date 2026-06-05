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

pub fn initQtApplication(init: std.process.Init) !void {
    const argv = try qt6.init(init.gpa, init.minimal.args);
    defer qt6.deinit(init.gpa, argv);
    var argc: i32 = @intCast(argv.len);

    const qapp = QApplication.New(init.arena.allocator(), &argc, argv);
    defer qapp.Delete();

    const window = QMainWindow.New2();
    defer window.Delete();
    window.SetFixedSize2(300, 250);

    const widget = QWidget.New2();
    defer widget.Delete();
    window.SetCentralWidget(widget);

    const menu_bar = QMenuBar.New2();
    window.SetMenuBar(menu_bar);
    menu_bar.SetNativeMenuBar(false);

    const file_menu = menu_bar.AddMenu2("Emulator");
    const exitAction = QAction.New2("Exit");
    exitAction.SetShortcut(QKeySequence.New2("Ctrl+Q"));
    file_menu.AddAction(exitAction);

    const tools_menu = menu_bar.AddMenu2("Tools");
    const traceloggerAction = QAction.New2("Tracelogger");
    // traceloggerAction.OnTriggered();
    tools_menu.AddAction(traceloggerAction);

    window.Show();

    _ = QApplication.Exec();
}
