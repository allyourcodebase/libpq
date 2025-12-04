# `build.zig` for libpq

Provides a package to be used by the zig package manager for C programs.

## Status

| Architecture \ OS | Linux      | MacOS |
|:------------------|:-----------|-------|
| x86_64            | ✅         | ✅    |
| arm 64            | (untested) | ✅*   |

| Refname    | PostgreSQL version | Zig `0.16.x` | Zig `0.15.x` | Zig `0.14.x` | Zig `0.13.x` |
|------------|--------------------|--------------|--------------|--------------|--------------|
| `5.16.4+5` | `REL_16_4`         | ✅           | ✅           | ✅           | ❌           |
| `5.16.4+4` | `REL_16_4`         | ✅*          | ✅           | ✅           | ❌           |
| `5.16.4+4` | `REL_16_4`         | ✅*          | ✅           | ✅           | ❌           |
| `5.16.4+3` | `REL_16_4`         | ❌           | ❌           | ✅           | ❌           |
| `5.16.4+2` | `REL_16_4`         | ❌           | ❌           | ❌           | ✅           |

*: Will not work with OpenSSL

## Use

Add the dependency in your `build.zig.zon` by running the following command:
```zig
zig fetch --save git+https://github.com/allyourcodebase/libpq#master
```

Then, in your `build.zig`:
```zig
const postgres = b.dependency("libpq", { .target = target, .optimize = optimize });

// to use from Zig (since 5.16.4+5):
mod.addImport("libpq", postgres.module("libpq"));

// to use from C:
exe.linkLibrary(postgres.artifact("pq"));
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
zig fetch --save          git+https://github.com/allyourcodebase/libressl#master
zig fetch --save          git+https://github.com/allyourcodebase/zlib#main
zig fetch --save          git+https://github.com/allyourcodebase/zstd#master
```
