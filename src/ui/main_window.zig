const std = @import("std");

const emulator = @import("../emulator.zig");
const tracelogger = @import("tracelogger.zig");
const mem_viewer = @import("mem_viewer.zig");
const pattern_tables = @import("pattern_tables.zig");

const qt6 = @import("libqt6zig");
const QApplication = qt6.QApplication;
const QMainWindow = qt6.QMainWindow;
const QWidget = qt6.QWidget;
const QMenuBar = qt6.QMenuBar;
const QAction = qt6.QAction;
const QKeySequence = qt6.QKeySequence;
const QVBoxLayout = qt6.QVBoxLayout;
const QLabel = qt6.QLabel;
const QFileDialog = qt6.QFileDialog;
const QPixmap = qt6.QPixmap;
const QImage = qt6.QImage;

const qnamespace_enums = qt6.qnamespace_enums;

pub var window: QMainWindow = undefined;
pub var gpa: std.mem.Allocator = undefined;
pub var io: std.Io = undefined;
var ROM_path: []const u8 = "";
var emu_thread: ?std.Thread = null;

var layout: QVBoxLayout = undefined;
var rom_status_label: QLabel = undefined;

pub var render_buffer: [241][256][3]u8 = undefined;
var nametable_label: QLabel = undefined;

pub fn initQtApplication(init: std.process.Init) !void {
    const argv = try qt6.init(init.gpa, init.minimal.args);
    defer qt6.deinit(init.gpa, argv);
    var argc: i32 = @intCast(argv.len);

    const qapp = QApplication.New(init.arena.allocator(), &argc, argv);
    defer qapp.Delete();

    window = QMainWindow.New2();
    gpa = init.gpa;
    io = init.io;
    defer window.Delete();
    defer freeROMPath();
    window.SetWindowFlags(qnamespace_enums.WindowType.Window | qnamespace_enums.WindowType.WindowMinMaxButtonsHint | qnamespace_enums.WindowType.WindowCloseButtonHint);
    window.Resize(600, 500);

    const widget = QWidget.New2();
    defer widget.Delete();
    window.SetCentralWidget(widget);

    const menu_bar = QMenuBar.New2();
    window.SetMenuBar(menu_bar);
    menu_bar.SetNativeMenuBar(false);

    // -- file menu --
    const file_menu = menu_bar.AddMenu2("File");
    const load_rom_action = QAction.New2("Load rom...");
    load_rom_action.SetShortcut(QKeySequence.New2("Ctrl+O"));
    load_rom_action.OnTriggered(load_rom);
    file_menu.AddAction(load_rom_action);

    _ = file_menu.AddSeparator();

    const exit_action = QAction.New2("Exit");
    exit_action.SetShortcut(QKeySequence.New2("Ctrl+Q"));
    exit_action.OnTriggered(exit_window);
    file_menu.AddAction(exit_action);

    // -- emulation menu --
    const emulation_menu = menu_bar.AddMenu2("Emulation");
    const reset_action = QAction.New2("Reset");
    reset_action.SetShortcut(QKeySequence.New2("Ctrl+R"));
    reset_action.OnTriggered(resetActionWrapper);
    emulation_menu.AddAction(reset_action);

    const halt_action = QAction.New2("Stop");
    // halt_action.SetShortcut(QKeySequence.New2(""));
    halt_action.OnTriggered(haltActionWrapper);
    emulation_menu.AddAction(halt_action);

    // -- tools menu --
    const tools_menu = menu_bar.AddMenu2("Tools");
    const tracelogger_action = QAction.New2("Tracelogger");
    tracelogger_action.OnTriggered(tracelogger.openTracelogger);
    tools_menu.AddAction(tracelogger_action);

    const mem_viewer_action = QAction.New2("Memory Viewer");
    mem_viewer_action.OnTriggered(mem_viewer.openMemViewer);
    tools_menu.AddAction(mem_viewer_action);

    const pattern_table_action = QAction.New2("Pattern Tables");
    pattern_table_action.OnTriggered(pattern_tables.openPatternTables);
    tools_menu.AddAction(pattern_table_action);

    layout = QVBoxLayout.New(widget);
    rom_status_label = QLabel.New3("No ROM loaded. Load one from Emulator > Load ROM...");
    rom_status_label.SetAlignment(qnamespace_enums.AlignmentFlag.AlignVCenter | qnamespace_enums.AlignmentFlag.AlignHCenter);
    rom_status_label.SetWordWrap(true);
    layout.AddWidget(rom_status_label);

    window.Show();

    _ = QApplication.Exec();
}

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

fn haltActionWrapper(action: QAction) callconv(.c) void {
    _ = action;
    haltEmulator();
}

fn resetEmulator() callconv(.c) void {
    if (ROM_path.len == 0) return;

    haltEmulator();

    @memset(std.mem.asBytes(&render_buffer), 0);
    emulator.CPU_halted.store(false, .monotonic);
    emu_thread = std.Thread.spawn(.{}, emulator.runEmulatorThread, .{ io, ROM_path }) catch |err| {
        std.log.err("Failed to spawn emulator thread: {any}", .{err});
        return;
    };
}

fn haltEmulator() void {
    if (ROM_path.len == 0) return;

    if (emu_thread) |thread| {
        emulator.CPU_halted.store(true, .monotonic);
        thread.join();
        emu_thread = null;
    }
}

fn freeROMPath() void {
    if (ROM_path.len > 0) {
        gpa.free(ROM_path);
    }
}

pub fn render() void {
    for (0..30) |row| {
        for (0..32) |column| {
            const vram_idx = column + (row * 32);
            const tile_index = @as(usize, emulator.VRAM[vram_idx]);
            const chr_base_addr = tile_index * 16;

            const attribute_offset: u8 = @truncate((column >> 2) + (row >> 2) * 8);
            const attributes: u8 = emulator.VRAM[@as(usize, 0x3C0) + attribute_offset];
            const quadrant: u8 = @truncate(((column >> 1) & 1) + ((row >> 1) & 1) * 2);
            const shift_amount: u3 = @intCast(quadrant * 2);
            const pair: u8 = @truncate((attributes >> shift_amount) & 3);

            for (0..8) |y| {
                const useSecondPatternTable: u16 = if (emulator.ppu_bg_pattern_table) 4096 else 0;
                const low: u8 = emulator.CHR_DATA[chr_base_addr + y + useSecondPatternTable];
                const high: u8 = emulator.CHR_DATA[chr_base_addr + 8 + y + useSecondPatternTable];

                for (0..8) |x| {
                    var twobit: u8 = if (((low >> @intCast(7 - x)) & 1) == 1) 1 else 0;
                    twobit += if (((high >> @intCast(7 - x)) & 1) == 1) 2 else 0;

                    var colour: [3]u8 = undefined;
                    if (twobit == 0) {
                        colour = emulator.palette[emulator.PALETTE_RAM[0]];
                    } else {
                        colour = emulator.palette[emulator.PALETTE_RAM[twobit + pair * 4]];
                    }

                    const target_y = y + row * 8;
                    const target_x = x + column * 8;
                    render_buffer[target_y][target_x] = colour;
                }
            }
        }
    }

    const image = QImage.New4(@ptrCast(&render_buffer), 256, 240, 13); // Format_RGB888
    const pixmap = QPixmap.FromImage(image);
    const scaled_pixmap = pixmap.Scaled4(512, 480, qnamespace_enums.AspectRatioMode.KeepAspectRatio, qnamespace_enums.TransformationMode.FastTransformation);

    rom_status_label.SetPixmap(scaled_pixmap);
}
