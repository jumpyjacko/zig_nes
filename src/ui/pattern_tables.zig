const std = @import("std");

const main_window = @import("main_window.zig");
const emulator = @import("../emulator.zig");

const qt6 = @import("libqt6zig");
const QWidget = qt6.QWidget;
const QAction = qt6.QAction;
const QVBoxLayout = qt6.QVBoxLayout;
const QLabel = qt6.QLabel;
const QFont = qt6.QFont;
const QPixmap = qt6.QPixmap;
const QImage = qt6.QImage;

const qnamespace_enums = qt6.qnamespace_enums;

pub var window: QWidget = undefined;
pub var rom_ptr: [*]u8 = &emulator.CHR_ROM;

const width: comptime_int = 256;
const height: comptime_int = 128;
var pixel_buffer: [height][width]u8 = undefined;

var display_label: QLabel = undefined;

pub fn openPatternTables(action: QAction) callconv(.c) void {
    _ = action;

    window = QWidget.New(main_window.window);
    window.SetAttribute(qnamespace_enums.WidgetAttribute.WA_DeleteOnClose);
    window.SetWindowTitle("zig_nes - pattern tables");
    window.SetWindowFlags(qnamespace_enums.WindowType.Window | qnamespace_enums.WindowType.WindowMinMaxButtonsHint | qnamespace_enums.WindowType.WindowCloseButtonHint);

    const layout = QVBoxLayout.New(window);
    const label = QLabel.New3("Pattern Tables");
    layout.AddWidget(label);

    display_label = QLabel.New3("[pattern tables]");
    layout.AddWidget(display_label);

    refreshPatternTables();

    window.Show();
}

fn refreshPatternTables() void {
    @memset(std.mem.asBytes(&pixel_buffer), 0);

    for (0..2) |table| {
        for (0..16) |row| {
            for (0..16) |column| {
                for (0..8) |y| {
                    const low: u8 = rom_ptr[y + column * 16 + row * 256 + table * 4096];
                    const high: u8 = rom_ptr[8 + y + column * 16 + row * 256 + table * 4096];
                    for (0..8) |x| {
                        var twobit: u8 = if (((low >> @intCast(7 - x)) & 1) == 1) 1 else 0;
                        twobit += if (((high >> @intCast(7 - x)) & 1) == 1) 2 else 0;

                        const grayscale_val = twobit * 85;
                        const target_y = y + row * 8;
                        const target_x = x + column * 8 + table * 128;
                        pixel_buffer[target_y][target_x] = grayscale_val;
                    }
                }
            }
        }
    }

    const image = QImage.New4(@ptrCast(&pixel_buffer), @intCast(width), @intCast(height), 24); // Format_RGB888
    const pixmap = QPixmap.FromImage(image);
    const scaled_pixmap = pixmap.Scaled4(512, 256, qnamespace_enums.AspectRatioMode.KeepAspectRatio, qnamespace_enums.TransformationMode.FastTransformation);

    display_label.SetPixmap(scaled_pixmap);
}
