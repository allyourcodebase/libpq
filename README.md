# `build.zig` for libpq

Provides a package to be used by the zig package manager for C programs.

## Status

| Architecture \ OS | Linux | MacOS                          |
|:------------------|:------|--------------------------------|
| x86_64            | ✅    | `-Ddisable-ssl -Ddisable-zstd` |
| arm 64            | X     | `-Ddisable-ssl -Ddisable-zstd` |

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
const libpgcommon = postgres.artifact("pgcommon");
const libpgport = postgres.artifact("pgport");

// wherever needed:
exe.linkLibrary(libpq);
exe.linkLibrary(libpgcommon);
exe.linkLibrary(libpgport);
```
