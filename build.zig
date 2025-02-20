const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) !void {
    const fastgltf_dep = b.dependency("fastgltf", .{});
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const preferred_link_mode = b.option(
        std.builtin.LinkMode,
        "preferred_link_mode",
        "Prefer building fastgltf as a statically or dynamically linked library (default: static)",
    ) orelse .static;
    const use_custom_smallvec = b.option(bool, "FASTGLTF_USE_CUSTOM_SMALLVECTOR", "Uses a custom SmallVector type optimised for small arrays") orelse false;
    const enable_deprecated_ext = b.option(bool, "FASTGLTF_ENABLE_DEPRECATED_EXT", "Enables support for deprecated extensions") orelse false;
    const disable_custom_memory_pool = b.option(bool, "FASTGLTF_DISABLE_CUSTOM_MEMORY_POOL", "Disables the memory allocation algorithm based on polymorphic resources") orelse false;
    const use_64bit_float = b.option(bool, "FASTGLTF_USE_64BIT_FLOAT", "Default to 64-bit double precision floats for everything") orelse false;
    const compile_as_cpp20 = b.option(bool, "FASTGLTF_COMPILE_AS_CPP20", "Have the library compile as C++20") orelse false;
    const compile_target = if (compile_as_cpp20) "c++20" else "c++17";

    const simdjson_dep = b.dependency("simdjson", .{});
    const simdjson_evex512: ?*std.Build.Step.WriteFile = if (target.result.cpu.arch == .x86_64) try fix_evex512_simdjson(b, simdjson_dep) else null;
    const simdjson_source_file_root = if (simdjson_evex512) |evex512| evex512.getDirectory() else simdjson_dep.path("singleheader");

    const simdjson_lib = b.addStaticLibrary(.{
        .name = "simdjson",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    simdjson_lib.linkLibCpp();
    simdjson_lib.addCSourceFiles(.{
        .root = simdjson_source_file_root,
        .files = &.{"simdjson.cpp"},
        .flags = &.{
            b.fmt("--std={s}", .{compile_target}),
        },
    });
    simdjson_lib.addIncludePath(simdjson_dep.path("singleheader"));
    simdjson_lib.installHeadersDirectory(simdjson_dep.path("singleheader"), ".", .{ .include_extensions = &.{".h"} });
    if (simdjson_evex512) |evex512| simdjson_lib.step.dependOn(&evex512.step);
    b.installArtifact(simdjson_lib);

    const fastgltf_lib: *std.Build.Step.Compile = switch (preferred_link_mode) {
        inline else => |x| switch (x) {
            .static => std.Build.addStaticLibrary,
            .dynamic => std.Build.addSharedLibrary,
        }(b, .{
            .name = "fastgltf",
            // .version = version,
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    };
    fastgltf_lib.linkLibCpp();
    fastgltf_lib.linkLibrary(simdjson_lib);
    fastgltf_lib.addIncludePath(fastgltf_dep.path(b.pathJoin(&.{"include"})));
    // fastgltf_lib.addIncludePath(simdjson_dep.path("include"));
    fastgltf_lib.addCSourceFiles(.{
        .root = fastgltf_dep.path("."),
        .files = &(.{ "src/fastgltf.cpp", "src/base64.cpp", "src/io.cpp" }),
        .flags = &.{
            "-Wall",
            "-Wno-unknown-pragmas",
            b.fmt("--std={s}", .{compile_target}),
        },
    });
    fastgltf_lib.root_module.addCMacro("FASTGLTF_USE_CUSTOM_SMALLVECTOR", if (use_custom_smallvec) "1" else "0");
    fastgltf_lib.root_module.addCMacro("FASTGLTF_ENABLE_DEPRECATED_EXT", if (enable_deprecated_ext) "1" else "0");
    fastgltf_lib.root_module.addCMacro("FASTGLTF_DISABLE_CUSTOM_MEMORY_POOL", if (disable_custom_memory_pool) "1" else "0");
    fastgltf_lib.root_module.addCMacro("FASTGLTF_USE_64BIT_FLOAT", if (use_64bit_float) "1" else "0");
    fastgltf_lib.installHeadersDirectory(fastgltf_dep.path(b.pathJoin(&.{ "include", "fastgltf" })), "fastgltf", .{
        .include_extensions = &.{ ".h", ".hpp" },
    });
    b.installArtifact(fastgltf_lib);

    const example = b.addExecutable(.{
        .name = "fastgltf-example",
        .target = target,
        .optimize = optimize,
    });
    example.linkLibCpp();
    example.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ b.install_path, "include" }) });
    example.linkLibrary(fastgltf_lib);
    example.addCSourceFile(.{ .file = b.path("example/main.cpp") });

    const run_artifact = b.addRunArtifact(example);
    const run = b.step("run", "Run example");
    run.dependOn(&run_artifact.step);
    // b.installArtifact(example);
}

fn fix_evex512_simdjson(b: *std.Build, simdjson_dep: *std.Build.Dependency) !*std.Build.Step.WriteFile {
    const original_file = try std.fs.openFileAbsolute(simdjson_dep.path(b.pathJoin(&.{ "singleheader", "simdjson.cpp" })).getPath(b), .{});
    defer original_file.close();

    const original_content = try original_file.readToEndAlloc(b.allocator, std.math.maxInt(usize));
    defer b.allocator.free(original_content);
    const edited_content = try std.mem.replaceOwned(
        u8,
        b.allocator,
        original_content,
        "SIMDJSON_TARGET_REGION(\"avx512f,avx512dq,avx512cd,avx512bw,avx512vbmi,avx512vbmi2,avx512vl,avx2,bmi,pclmul,lzcnt,popcnt\")",
        "SIMDJSON_TARGET_REGION(\"avx512f,avx512dq,avx512cd,avx512bw,avx512vbmi,avx512vbmi2,avx512vl,avx2,bmi,pclmul,lzcnt,popcnt,evex512\")",
    );
    defer b.allocator.free(edited_content);

    return b.addWriteFile("simdjson.cpp", edited_content);
}
