# `build.zig` for libpq

Provides a package to be used by the zig package manager for C programs.

## Status

For now the only target is linux with openssl.

- [x] libpq.a
- [x] libpgport.a
- [x] libpgcommon.a

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
