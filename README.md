# `build.zig` for libpq

Provides a package to be used by the zig package manager for C programs.

## Status

| Architecture \ OS | Linux      | MacOS |
|:------------------|:-----------|-------|
| x86_64            | ✅         | ✅    |
| arm 64            | (untested) | ✅    |

| Refname    | PostgreSQL version | Zig `0.15.x` | Zig `0.14.x` | Zig `0.13.x` |
|------------|--------------------|--------------|--------------|--------------|
| `5.16.4+3` | `REL_16_4`         | ✅           | ✅           | ❌           |
| `5.16.4+2` | `REL_16_4`         | ❌           | ❌           | ✅           |

## Use

Add the dependency in your `build.zig.zon` by running the following command:
```zig
zig fetch --save git+https://github.com/allyourcodebase/libpq#5.16.4+3
```

Then, in your `build.zig`:
```zig
const postgres = b.dependency("libpq", { .target = target, .optimize = optimize });
const libpq = postgres.artifact("pq");

// wherever needed:
exe.linkLibrary(libpq);
```

## Options

```
  -Dssl=[enum]                 Choose which dependency to use for SSL. Defaults to LibreSSL
                                 Supported Values:
                                   OpenSSL
                                   LibreSSL
                                   None
  -Ddisable-zlib=[bool]        Remove zlib as a dependency
  -Ddisable-zstd=[bool]        Remove zstd as a dependency
```

## Bump dependencies

To update this project dependencies:

```bash
zig fetch --save=upstream git+https://github.com/postgres/postgres#REL_16_4
zig fetch --save          git+https://github.com/allyourcodebase/openssl#main
zig fetch --save          git+https://github.com/allyourcodebase/libressl#4.0.0+2
zig fetch --save          git+https://github.com/allyourcodebase/zlib#main
zig fetch --save          git+https://github.com/allyourcodebase/zstd#1.5.7
```
