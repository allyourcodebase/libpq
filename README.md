# `build.zig` for libpq

Provides a package to be used by the zig package manager for C programs.

## Status

| Architecture \ OS | Linux | MacOS             |
|:------------------|:------|-------------------|
| x86_64            | ✅    | ?                 |
| arm 64            | ❌    | ☑️ `-Ddisable-ssl` |

Optional dependencies used by default:
- openssl
- zlib
- zstd

## Use

Add the dependency in your `build.zig.zon` by running the following command:
```zig
zig fetch --save git+https://github.com/allyourcodebase/libpq#5.16.4
```

Then, in your `build.zig`:
```zig
const postgres = b.dependency("libpq", { .target = target, .optimize = optimize });
const libpq = postgres.artifact("pq");

// wherever needed:
exe.linkLibrary(libpq);
```
