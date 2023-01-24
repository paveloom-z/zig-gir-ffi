const std = @import("std");

const deps = @import("deps.zig");

pub fn build(b: *std.build.Builder) void {
    // Add standard target options
    const target = b.standardTargetOptions(.{});
    // Add standard release options
    const mode = b.standardReleaseOptions();
    // Add the executable
    const exe = b.addExecutable("zig-gir-ffi", "src/main.zig");
    // Make sure the executable can be built and installed
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.install();
    // Add a run step
    const run_step = b.step("run", "Run the program");
    const run_cmd = exe.run();
    run_cmd.expected_exit_code = null;
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    run_step.dependOn(&run_cmd.step);
    // Add the dependencies
    exe.addPackage(deps.pkgs.girepository.pkg.?);
    // Link the libraries
    exe.linkLibC();
    exe.linkSystemLibrary("gobject-introspection-1.0");
    // Use the `stage1` compiler
    exe.use_stage1 = true;
}
