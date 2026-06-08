const std = @import("std");

const emulator = @import("../emulator.zig");
const tracelogger = @import("tracelogger.zig");
const mem_viewer = @import("mem_viewer.zig");

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
const QFileDialog = qt6.QFileDialog;

const qnamespace_enums = qt6.qnamespace_enums;

pub const AppWindow = struct { // HACK: idek man
    pub var window: QMainWindow = undefined;
    pub var gpa: std.mem.Allocator = undefined;
    pub var io: std.Io = undefined;
    var ROM_path: []const u8 = "";
    var emu_thread: ?std.Thread = null;

    fn exit_window(action: QAction) callconv(.c) void {
        _ = action;
        _ = window.Close();
    }

    fn load_rom(action: QAction) callconv(.c) void {
        _ = action;

        const file_path = QFileDialog.GetOpenFileName4(
            gpa,
            window,
            "Open ROM File",
            "",
            "NES ROMs (*.nes);;All Files (*)",
        );
        defer gpa.free(file_path);

        if (file_path.len > 0) {
            if (ROM_path.len > 0) {
                gpa.free(ROM_path);
            }
            ROM_path = gpa.dupe(u8, file_path) catch {
                return;
            };

            resetEmulator();
        }
    }

    fn resetActionWrapper(action: QAction) callconv(.c) void {
        _ = action;
        resetEmulator();
    }

    fn resetEmulator() void {
        if (ROM_path.len == 0) return;

        if (emu_thread) |thread| {
            emulator.CPU_Halted.store(true, .monotonic);
            thread.join();
            emu_thread = null;
        }

        emulator.CPU_Halted.store(false, .monotonic);
        emu_thread = std.Thread.spawn(.{}, emulator.runEmulatorThread, .{ io, ROM_path }) catch |err| {
            std.log.err("Failed to spawn emulator thread: {any}", .{err});
            return;
        };
    }

    fn freeROMPath() void {
        if (ROM_path.len > 0) {
            gpa.free(ROM_path);
        }
    }
};

pub fn initQtApplication(init: std.process.Init) !void {
    const argv = try qt6.init(init.gpa, init.minimal.args);
    defer qt6.deinit(init.gpa, argv);
    var argc: i32 = @intCast(argv.len);

    const qapp = QApplication.New(init.arena.allocator(), &argc, argv);
    defer qapp.Delete();

    AppWindow.window = QMainWindow.New2();
    AppWindow.gpa = init.gpa;
    AppWindow.io = init.io;
    defer AppWindow.window.Delete();
    defer AppWindow.freeROMPath();
    AppWindow.window.SetFixedSize2(300, 250);

    const widget = QWidget.New2();
    defer widget.Delete();
    AppWindow.window.SetCentralWidget(widget);

    const menu_bar = QMenuBar.New2();
    AppWindow.window.SetMenuBar(menu_bar);
    menu_bar.SetNativeMenuBar(false);

    const file_menu = menu_bar.AddMenu2("File");
    const load_rom_action = QAction.New2("Load rom...");
    load_rom_action.OnTriggered(AppWindow.load_rom);
    file_menu.AddAction(load_rom_action);

    _ = file_menu.AddSeparator();

    const exit_action = QAction.New2("Exit");
    exit_action.SetShortcut(QKeySequence.New2("Ctrl+Q"));
    exit_action.OnTriggered(AppWindow.exit_window);
    file_menu.AddAction(exit_action);

    const emulation_menu = menu_bar.AddMenu2("Emulation");
    const reset_action = QAction.New2("Reset");
    reset_action.OnTriggered(AppWindow.resetActionWrapper);
    emulation_menu.AddAction(reset_action);

    const tools_menu = menu_bar.AddMenu2("Tools");
    const tracelogger_action = QAction.New2("Tracelogger");
    tracelogger_action.OnTriggered(tracelogger.openTracelogger);
    tools_menu.AddAction(tracelogger_action);

    const mem_viewer_action = QAction.New2("Memory Viewer");
    mem_viewer_action.OnTriggered(mem_viewer.openMemViewer);
    tools_menu.AddAction(mem_viewer_action);

    const layout = QVBoxLayout.New(widget);
    const rom_status_label = QLabel.New3("No ROM loaded. Load one from Emulator > Load ROM...");
    rom_status_label.SetAlignment(qnamespace_enums.AlignmentFlag.AlignVCenter | qnamespace_enums.AlignmentFlag.AlignHCenter);
    rom_status_label.SetWordWrap(true);
    layout.AddWidget(rom_status_label);

    AppWindow.window.Show();

    _ = QApplication.Exec();
}
