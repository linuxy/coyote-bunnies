const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const mode = b.standardReleaseOptions();

    const rpmPkg = std.build.Pkg{ .name = "rpmalloc", .source = std.build.FileSource{ .path = "vendor/coyote-ecs/vendor/rpmalloc-zig-port/src/rpmalloc.zig"}};
    const ecsPkg = std.build.Pkg{ .name = "coyote-ecs", .source = std.build.FileSource{ .path = "vendor/coyote-ecs/src/coyote.zig" }, .dependencies = &[_]std.build.Pkg{ rpmPkg }};

    const exe = b.addExecutable("bunnies", "src/coyote-bunnies.zig");
    exe.setBuildMode(mode);
    exe.linkLibC();
    //Linux paths
    exe.addIncludePath("/usr/include");
    exe.addIncludePath("/usr/include/x86_64-linux-gnu");
    //Homebrew OSX paths
    exe.addIncludePath("/opt/homebrew/Cellar/sdl2/2.24.2/include");
    exe.addLibraryPath("/opt/homebrew/Cellar/sdl2/2.24.2/lib");
    exe.linkSystemLibrary("SDL2");
    exe.linkSystemLibrary("SDL2_image");
    exe.linkSystemLibrary("SDL2_ttf");
    exe.addPackage(ecsPkg);
    exe.addPackage(rpmPkg);
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}