const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "zig_nes",
        .version = .{ .major = 0, .minor = 1, .patch = 0 },
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .link_libcpp = true,
        }),
    });

    const qt6zig = b.dependency("libqt6zig", .{
        .target = target,
        .optimize = .ReleaseFast,
    });

    exe.root_module.linkSystemLibrary("Qt6Widgets", .{});
    exe.root_module.linkSystemLibrary("Qt6Gui", .{});
    exe.root_module.linkSystemLibrary("Qt6Core", .{});
    exe.root_module.addImport("libqt6zig", qt6zig.module("libqt6zig"));

    const qtlibs = [_][]const u8{
        "qapplication",
        "qwidget",
        "qmenubar",
        "qmenu",
        "qkeysequence",
        "qaction",
        "qmainwindow",
        "qboxlayout",
        "qlabel",
        "qtreewidget",
        "qtreeview",
        "qfiledialog",
        "qdialog",
        "qcheckbox",
        "qfont",
        "qtimer",
        "qheaderview",
        "qobject"
    };

    for (qtlibs) |lib| {
        exe.root_module.linkLibrary(qt6zig.artifact(lib));
    }

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);
}
