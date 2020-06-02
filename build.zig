const std = @import("std");
const Builder = @import("std").build.Builder;

fn addWebviewDeps(exe: *std.build.LibExeObjStep) void {
    exe.addIncludeDir("src/webview");
    exe.linkLibC();
    exe.linkSystemLibrary("gtk+-3.0");
    exe.linkSystemLibrary("webkit2gtk-4.0");
}

pub fn build(b: *Builder) void {
    {
        const mode = b.standardReleaseOptions();
        const mdView = b.addExecutable("mdv", "src/main.zig");
        mdView.setBuildMode(mode);
        mdView.addPackagePath("zig-log", "lib/log.zig/src/index.zig");
        mdView.addPackagePath("mylog", "src/log/log.zig");
        mdView.addPackagePath("zig-time", "lib/zig-time/src/time.zig");
        addWebviewDeps(mdView);
        mdView.install();
        const run_cmd = mdView.run();
        run_cmd.step.dependOn(b.getInstallStep());

        const run_step = b.step("run", "Run the app");
        run_step.dependOn(&run_cmd.step);
    }

    {
        const mdTest = b.addTest("test.zig");
        mdTest.addPackagePath("zig-time", "lib/zig-time/src/time.zig");
        mdTest.addPackagePath("zig-log", "lib/log.zig/src/index.zig");
        b.step("test", "Run all tests").dependOn(&mdTest.step);
    }
}
