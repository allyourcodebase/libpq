const std = @import("std");
const libcquery = @import("libcquery");

const version = .{ .major = 18, .minor = 4 };
const libpq_path = "src/interfaces/libpq";

const ssl_type = enum { OpenSSL, LibreSSL, None };

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const features = libcquery.libc_features.detect(target.result);
    const headers = libcquery.libc_headers.detect(target.result);
    const constants = libcquery.libc_constants.detect(target.result);
    const types = libcquery.libc_types.detect(target.result);

    const os_header = switch (target.result.os.tag) {
        .freebsd => "src/include/port/freebsd.h",
        .linux => "src/include/port/linux.h",
        .macos => "src/include/port/darwin.h",
        .netbsd => "src/include/port/netbsd.h",
        .openbsd => "src/include/port/openbsd.h",
        .windows => "src/include/port/win32.h",
        else => return error.OsNotSupported,
    };

    const ssl_option = b.option(ssl_type, "ssl", "Choose which dependency to use for SSL among OpenSSL, LibreSSL and None. Defaults to LibreSSL") orelse .LibreSSL;
    const disable_zlib = b.option(bool, "disable-zlib", "Remove zlib as a dependency") orelse false;
    const disable_zstd = b.option(bool, "disable-zstd", "Remove zstd as a dependency") orelse false;

    const upstream = b.dependency("upstream", .{});

    const pg_config = b.addConfigHeader(
        .{
            .style = .{ .autoconf_undef = upstream.path("src/include/pg_config.h.in") },
            .include_path = "pg_config.h",
        },
        autoconf,
    );
    const config_os = b.addConfigHeader(
        .{
            .style = .{ .autoconf_at = upstream.path(os_header) },
            .include_path = "pg_config_os.h",
        },
        .{},
    );
    const config_path = b.addConfigHeader(
        .{ .style = .blank, .include_path = "pg_config_paths.h" },
        default_paths,
    );
    const mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const lib = b.addLibrary(.{ .name = "pq", .root_module = mod });

    mod.addCSourceFiles(.{
        .root = upstream.path(libpq_path),
        .files = &libpq_sources,
        .flags = &CFLAGS,
    });
    mod.addCSourceFiles(.{
        .root = upstream.path("src/port"),
        .files = &libport_sources,
        .flags = &CFLAGS,
    });
    mod.addCSourceFiles(.{
        .root = upstream.path("src/common"),
        .files = &common_sources,
        .flags = &CFLAGS,
    });

    const config_headers = [_]*std.Build.Step.ConfigHeader{ pg_config, config_os };

    mod.addIncludePath(upstream.path("src/include"));
    mod.addIncludePath(b.path("include"));
    mod.addIncludePath(upstream.path(libpq_path));
    mod.addConfigHeader(config_path);
    mod.addCMacro("FRONTEND", "1");
    mod.addCMacro("JSONAPI_USE_PQEXPBUFFER", "1");
    b.installArtifact(lib);

    for (config_headers) |header| {
        mod.addConfigHeader(header);
        lib.installConfigHeader(header);
    }

    const use_ssl = defineIf(ssl_option != .None);
    const use_openssl = defineIf(ssl_option == .OpenSSL);

    switch (ssl_option) {
        .OpenSSL => {
            if (b.lazyDependency("openssl", .{ .target = target, .optimize = optimize })) |openssl_dep| {
                const openssl = openssl_dep.artifact("openssl");
                mod.linkLibrary(openssl);
            }
        },
        .LibreSSL => {
            if (b.lazyDependency("libressl", .{ .target = target, .optimize = optimize })) |libressl_dep| {
                const libressl = libressl_dep.artifact("ssl");
                mod.linkLibrary(libressl);
            }
        },
        .None => {},
    }

    pg_config.addValues(.{
        .USE_OPENSSL = use_ssl,
        .OPENSSL_API_COMPAT = .@"0x10001000L",
        .HAVE_LIBCRYPTO = use_ssl,
        .HAVE_LIBSSL = use_ssl,
        .HAVE_SSL_CTX_SET_CERT_CB = use_openssl,
        .HAVE_SSL_CTX_SET_NUM_TICKETS = use_ssl,
        .HAVE_X509_GET_SIGNATURE_INFO = use_openssl,
    });

    if (ssl_option != .None) {
        mod.addCSourceFiles(.{
            .root = upstream.path(libpq_path),
            .files = &.{
                "fe-secure-common.c",
                "fe-secure-openssl.c",
            },
            .flags = &CFLAGS,
        });
        mod.addCSourceFiles(.{
            .root = upstream.path("src/common"),
            .files = &.{
                "cryptohash_openssl.c",
                "hmac_openssl.c",
            },
            .flags = &CFLAGS,
        });
    } else {
        mod.addCSourceFiles(.{
            .root = upstream.path("src/common"),
            .files = &.{
                "cryptohash.c",
                "hmac.c",
                "md5.c",
                "sha1.c",
                "sha2.c",
            },
            .flags = &CFLAGS,
        });
    }

    if (!disable_zlib) {
        if (b.lazyDependency("zlib", .{ .target = target, .optimize = optimize })) |zlib_dep| {
            mod.linkLibrary(zlib_dep.artifact("z"));
        }
    }
    if (!disable_zstd) {
        if (b.lazyDependency("zstd", .{ .target = target, .optimize = optimize })) |zstd_dep| {
            mod.linkLibrary(zstd_dep.artifact("zstd"));
        }
    }
    const use_zstd = defineIf(!disable_zstd);
    pg_config.addValues(.{
        .HAVE_LIBZSTD = use_zstd,
        .USE_ZSTD = use_zstd,
    });

    const is_amd64 = defineIf(target.result.cpu.arch == .x86_64);
    pg_config.addValues(.{
        .HAVE__GET_CPUID = is_amd64,
        .HAVE_X86_64_POPCNTQ = is_amd64,
    });


    // While building with musl, defining _GNU_SOURCE makes musl declare extra things (e.g. struct ucred)
    mod.addCMacro("_GNU_SOURCE", "1");

    pg_config.addValues(.{
        .HAVE_ATOMIC_H = defineIf(headers.atomic_h),
        .HAVE_BACKTRACE_SYMBOLS = defineIf(features.backtrace_symbols),
        .HAVE_COPYFILE = defineIf(features.copyfile),
        .HAVE_COPYFILE_H = defineIf(headers.copyfile_h),
        .HAVE_COPY_FILE_RANGE = defineIf(features.copy_file_range),
        .HAVE_CRTDEFS_H = defineIf(headers.crtdefs_h),
        .HAVE_DECL_FDATASYNC = features.fdatasync,
        .HAVE_DECL_F_FULLFSYNC = constants.f_fullfsync,
        .HAVE_DECL_MEMSET_S = defineIf(features.memset_s),
        .HAVE_DECL_POSIX_FADVISE = features.posix_fadvise,
        .HAVE_DECL_PREADV = features.preadv,
        .HAVE_DECL_PWRITEV = features.pwritev,
        .HAVE_DECL_STRCHRNUL = defineIf(features.strchrnul),
        .HAVE_DECL_STRLCAT = features.strlcat,
        .HAVE_DECL_STRLCPY = features.strlcpy,
        .HAVE_DECL_STRNLEN = features.strnlen,
        .HAVE_DECL_STRSEP = features.strsep,
        .HAVE_DECL_TIMINGSAFE_BCMP = features.timingsafe_bcmp,
        .HAVE_ELF_AUX_INFO = defineIf(features.elf_aux_info),
        .HAVE_EXECINFO_H = defineIf(headers.execinfo_h),
        .HAVE_EXPLICIT_BZERO = defineIf(features.explicit_bzero),
        .HAVE_FSEEKO = defineIf(features.fseeko),
        .HAVE_GETAUXVAL = defineIf(features.getauxval),
        .HAVE_GETIFADDRS = defineIf(features.getifaddrs),
        .HAVE_GETOPT = defineIf(features.getopt),
        .HAVE_GETOPT_H = defineIf(headers.getopt_h),
        .HAVE_GETPEEREID = defineIf(features.getpeereid),
        .HAVE_IFADDRS_H = defineIf(headers.ifaddrs_h),
        .HAVE_INET_ATON = defineIf(features.inet_aton),
        .HAVE_INET_PTON = defineIf(features.inet_pton),
        .HAVE_INTTYPES_H = defineIf(headers.inttypes_h),
        .HAVE_KQUEUE = defineIf(headers.sys_event_h),
        .HAVE_LIBZ = defineIf(!disable_zlib),
        .HAVE_LOCALECONV_L = defineIf(features.localeconv_l),
        .HAVE_MBSTOWCS_L = defineIf(features.mbstowcs_l),
        .HAVE_MEMORY_H = defineIf(headers.memory_h),
        .HAVE_MKDTEMP = defineIf(features.mkdtemp),
        .HAVE_POSIX_FADVISE = defineIf(features.posix_fadvise),
        .HAVE_POSIX_FALLOCATE = defineIf(features.posix_fallocate),
        .HAVE_PPOLL = defineIf(features.ppoll),
        .HAVE_SETPROCTITLE = defineIf(features.setproctitle),
        .HAVE_SOCKLEN_T = defineIf(types.socklen_t),
        .HAVE_STDINT_H = defineIf(headers.stdint_h),
        .HAVE_STDLIB_H = defineIf(headers.stdlib_h),
        .HAVE_STRERROR_R = defineIf(features.strerror_r),
        .HAVE_STRINGS_H = defineIf(headers.strings_h),
        .HAVE_STRING_H = defineIf(headers.string_h),
        .HAVE_STRLCAT = defineIf(features.strlcat),
        .HAVE_STRLCPY = defineIf(features.strlcpy),
        .HAVE_STRNLEN = defineIf(features.strnlen),
        .HAVE_STRSEP = defineIf(features.strsep),
        .HAVE_STRSIGNAL = defineIf(features.strsignal),
        .HAVE_STRUCT_SOCKADDR_SA_LEN = defineIf(types.struct_sockaddr_sa_len),
        .HAVE_STRUCT_TM_TM_ZONE = defineIf(types.struct_tm_tm_zone),
        .HAVE_SYNCFS = defineIf(features.syncfs),
        .HAVE_SYNC_FILE_RANGE = defineIf(features.sync_file_range),
        .HAVE_SYSLOG = defineIf(features.syslog),
        .HAVE_SYS_EPOLL_H = defineIf(headers.sys_epoll_h),
        .HAVE_SYS_EVENT_H = defineIf(headers.sys_event_h),
        .HAVE_SYS_PERSONALITY_H = defineIf(headers.sys_personality_h),
        .HAVE_SYS_PRCTL_H = defineIf(headers.sys_prctl_h),
        .HAVE_SYS_PROCCTL_H = defineIf(headers.sys_procctl_h),
        .HAVE_SYS_SIGNALFD_H = defineIf(headers.sys_signalfd_h),
        .HAVE_SYS_STAT_H = defineIf(headers.sys_stat_h),
        .HAVE_SYS_TYPES_H = defineIf(headers.sys_types_h),
        .HAVE_SYS_UCRED_H = defineIf(headers.sys_ucred_h),
        .HAVE_TERMIOS_H = defineIf(headers.termios_h),
        .HAVE_TIMINGSAFE_BCMP = defineIf(features.timingsafe_bcmp),
        .HAVE_UNISTD_H = defineIf(headers.unistd_h),
        .HAVE_USELOCALE = defineIf(features.uselocale),
        .HAVE_UUID_H = defineIf(headers.uuid_h),
        .HAVE_UUID_UUID_H = defineIf(headers.uuid_uuid_h),
        .HAVE_WCSTOMBS_L = defineIf(features.wcstombs_l),
        .HAVE_XLOCALE_H = defineIf(headers.xlocale_h),
        .STRERROR_R_INT = defineIf(!target.result.isGnuLibC()),
        .WORDS_BIGENDIAN = defineIf(target.result.cpu.arch.endian() == .big),
    });
    if (!features.explicit_bzero) mod.addCSourceFile(.{ .file = upstream.path("src/port/explicit_bzero.c"), .flags = &CFLAGS });
    if (!features.getpeereid) mod.addCSourceFile(.{ .file = upstream.path("src/port/getpeereid.c"), .flags = &CFLAGS });
    if (!features.inet_aton) mod.addCSourceFile(.{ .file = upstream.path("src/port/inet_aton.c"), .flags = &CFLAGS });
    if (!features.mkdtemp) mod.addCSourceFile(.{ .file = upstream.path("src/port/mkdtemp.c"), .flags = &CFLAGS });
    if (!features.strlcat) mod.addCSourceFile(.{ .file = upstream.path("src/port/strlcat.c"), .flags = &CFLAGS });
    if (!features.strlcpy) mod.addCSourceFile(.{ .file = upstream.path("src/port/strlcpy.c"), .flags = &CFLAGS });
    if (!features.strnlen) mod.addCSourceFile(.{ .file = upstream.path("src/port/strnlen.c"), .flags = &CFLAGS });
    if (!features.strsep) mod.addCSourceFile(.{ .file = upstream.path("src/port/strsep.c"), .flags = &CFLAGS });
    if (!features.timingsafe_bcmp) mod.addCSourceFile(.{ .file = upstream.path("src/port/timingsafe_bcmp.c"), .flags = &CFLAGS });

    pg_config.addValues(.{
        .ALIGNOF_DOUBLE = target.result.cTypeAlignment(.double),
        .ALIGNOF_INT = target.result.cTypeAlignment(.int),
        .ALIGNOF_INT64_T = @alignOf(i64),
        .ALIGNOF_LONG = target.result.cTypeAlignment(.long),
        .ALIGNOF_PG_INT128_TYPE = @alignOf(i128),
        .ALIGNOF_SHORT = target.result.cTypeAlignment(.short),
        .MAXIMUM_ALIGNOF = @alignOf(i128),

        .SIZEOF_LONG = target.result.cTypeByteSize(.long),
        .SIZEOF_LONG_LONG = target.result.cTypeByteSize(.longlong),
        .SIZEOF_OFF_T = target.result.cTypeByteSize(.long),
        .SIZEOF_SIZE_T = target.result.cTypeByteSize(.ulong),
        .SIZEOF_VOID_P = @sizeOf(*void),
    });

    // Export public headers, the way the Makefile in src/interfaces/libpq does
    lib.installHeadersDirectory(
        upstream.path(libpq_path),
        "",
        .{
            .include_extensions = &.{
                "libpq-fe.h", // -> "postgres_ext.h" -> "pg_config_ext.h"
                "libpq-events.h", // -> "libpq-fe.h" -> [...]
            },
        },
    );
    lib.installHeadersDirectory(
        upstream.path(libpq_path),
        "postgresql/internal",
        .{
            .include_extensions = &.{
                // Comment says:
                // > This file contains internal definitions meant to be used only by the frontend libpq library, not by applications that call it.
                // > An application can include this file if it wants to bypass the official API defined by libpq-fe.h,
                // > but code that does so is much more likely to break across PostgreSQL releases than code that uses only the official API.
                "libpq-int.h", // "lipq-events.h" -> [...] ; "lipq/pqcomm.h" ; "fe-auth-sasl.h" -> [...] ; "pqexpbuffer.h"
                "fe-auth-sasl.h", // -> "libpq-fe.h" -> [...]
                "pqexpbuffer.h", // {}
            },
        },
    );
    lib.installHeader(upstream.path("src/include/postgres_ext.h"), "postgres_ext.h"); // -> "pg_config_ext.h" ; included by libpq-fe.h
    lib.installHeader(upstream.path("src/include/libpq/pqcomm.h"), "postgresql/internal/libpq/pqcomm.h"); // included by libpq-int.h

    lib.installHeader(upstream.path("src/include/libpq/libpq-fs.h"), "libpq/libpq-fs.h"); // included by the textlo examples

    // Comment inside says: "This should be the first file included by PostgreSQL client libraries and application programs"
    lib.installHeader(upstream.path("src/include/postgres_fe.h"), "postgresql/internal/postgres_fe.h"); // "c.h" -> [...] ; "common/fe_memutils.h"
    lib.installHeader(upstream.path("src/include/c.h"), "postgresql/internal/c.h"); // "postgres_ext.h" -> [...] ; "pg_config.h" ; "pg_config_manual.h" ; "pg_config_os.h"
    lib.installHeader(upstream.path("src/include/pg_config_manual.h"), "pg_config_manual.h"); // {}
    lib.installHeader(upstream.path("src/include/port.h"), "postgresql/internal/port.h"); // {}

    // Build executables to ensure no symbols are left undefined
    const test_step = b.step("examples", "Build example programs");

    const test1 = b.addExecutable(.{ .name = "testlibpq", .root_module = b.createModule(.{ .target = target, .optimize = optimize }) });
    const test2 = b.addExecutable(.{ .name = "testlibpq2", .root_module = b.createModule(.{ .target = target, .optimize = optimize }) });
    const test3 = b.addExecutable(.{ .name = "testlibpq3", .root_module = b.createModule(.{ .target = target, .optimize = optimize }) });
    const test4 = b.addExecutable(.{ .name = "testlibpq4", .root_module = b.createModule(.{ .target = target, .optimize = optimize }) });
    const test5 = b.addExecutable(.{ .name = "testlo", .root_module = b.createModule(.{ .target = target, .optimize = optimize }) });
    const test6 = b.addExecutable(.{ .name = "testlo64", .root_module = b.createModule(.{ .target = target, .optimize = optimize }) });

    test1.root_module.addCSourceFiles(.{ .root = upstream.path("src/test/examples"), .files = &.{"testlibpq.c"} });
    test2.root_module.addCSourceFiles(.{ .root = upstream.path("src/test/examples"), .files = &.{"testlibpq2.c"} });
    test3.root_module.addCSourceFiles(.{ .root = upstream.path("src/test/examples"), .files = &.{"testlibpq3.c"} });
    test4.root_module.addCSourceFiles(.{ .root = upstream.path("src/test/examples"), .files = &.{"testlibpq4.c"} });
    test5.root_module.addCSourceFiles(.{ .root = upstream.path("src/test/examples"), .files = &.{"testlo.c"} });
    test6.root_module.addCSourceFiles(.{ .root = upstream.path("src/test/examples"), .files = &.{"testlo64.c"} });

    const tests = [_]*std.Build.Step.Compile{ test1, test2, test3, test4, test5, test6 };
    for (tests) |t| {
        t.root_module.link_libc = true;
        t.root_module.linkLibrary(lib);
        const install_test = b.addInstallArtifact(t, .{});
        test_step.dependOn(&install_test.step);
    }

    { // Generate zig bindings from C headers
        const include_all = b.addWriteFile("grpc.h",
            \\#include <libpq-fe.h>
            \\#include <libpq-events.h>
        );
        const binding = b.addTranslateC(.{
            .root_source_file = try include_all.getDirectory().join(b.allocator, "grpc.h"),
            .target = target,
            .optimize = optimize,
        });
        for (config_headers) |header| {
            binding.addConfigHeader(header);
        }
        binding.addIncludePath(upstream.path(libpq_path));
        binding.addIncludePath(upstream.path("src/include"));
        const bindmod = binding.addModule("libpq");
        bindmod.linkLibrary(lib);
    }
}

/// configHeader maps ?bool: null → `/* #undef FOO */`, true → `#define FOO 1`, false → `#define FOO 0`.
/// HAVE_* macros follow the autoconf convention of being either defined (1) or absent,
/// tested with `#ifdef` rather than `#if` to avoid -Wundef warnings.
/// Passing false directly would emit `#define FOO 0`, making the macro defined — breaking `#ifdef` guards.
fn defineIf(b: bool) ?bool {
    return if (b) true else null;
}

const libpq_sources = .{
    "fe-auth-oauth.c",
    "fe-auth-scram.c",
    "fe-auth.c",
    "fe-cancel.c",
    "fe-connect.c",
    "fe-exec.c",
    "fe-lobj.c",
    "fe-misc.c",
    "fe-print.c",
    "fe-protocol3.c",
    "fe-secure.c",
    "fe-trace.c",
    "legacy-pqsignal.c",
    "libpq-events.c",
    "pqexpbuffer.c",
};

const libport_sources = .{
    "bsearch_arg.c",
    "chklocale.c",
    "inet_net_ntop.c",
    "noblock.c",
    "path.c",
    "pg_bitutils.c",
    "pg_crc32c_sb8.c",
    "pg_localeconv_r.c",
    "pg_numa.c",
    "pg_popcount_aarch64.c",
    "pg_popcount_avx512.c",
    "pg_strong_random.c",
    "pgcheckdir.c",
    "pgmkdirp.c",
    "pgsleep.c",
    "pgstrcasecmp.c",
    "pgstrsignal.c",
    "pqsignal.c",
    "qsort.c",
    "qsort_arg.c",
    "quotes.c",
    "snprintf.c",
    "strerror.c",
    "tar.c",
};

const common_sources = .{
    "archive.c",
    "base64.c",
    "binaryheap.c",
    "blkreftable.c",
    "checksum_helper.c",
    "compression.c",
    "config_info.c",
    "controldata_utils.c",
    "d2s.c",
    "encnames.c",
    "exec.c",
    "f2s.c",
    "file_perm.c",
    "file_utils.c",
    "hashfn.c",
    "ip.c",
    "jsonapi.c",
    "keywords.c",
    "kwlookup.c",
    "link-canary.c",
    "md5_common.c",
    "parse_manifest.c",
    "percentrepl.c",
    "pg_get_line.c",
    "pg_lzcompress.c",
    "pg_prng.c",
    "pgfnames.c",
    "psprintf.c",
    "relpath.c",
    "rmtree.c",
    "saslprep.c",
    "scram-common.c",
    "string.c",
    "stringinfo.c",
    "unicode_case.c",
    "unicode_category.c",
    "unicode_norm.c",
    "username.c",
    "wait_error.c",
    "wchar.c",
};

const CFLAGS = .{
    "-fwrapv",
    "-fno-strict-aliasing",
    "-fexcess-precision=standard",

    "-Wno-unused-command-line-argument",
    "-Wno-compound-token-split-by-macro",
    "-Wno-format-truncation",
    "-Wno-cast-function-type-strict",

    "-Werror",
    "-Wall",
    "-Wmissing-prototypes",
    "-Wpointer-arith",
    "-Wvla",
    "-Wunguarded-availability-new",
    "-Wendif-labels",
    "-Wmissing-format-attribute",
    "-Wformat-security",
};

const default_paths = .{
    .DOCDIR = "/usr/local/pgsql/share/doc/",
    .HTMLDIR = "/usr/local/pgsql/share/doc/",
    .INCLUDEDIR = "/usr/local/pgsql/include",
    .INCLUDEDIRSERVER = "/usr/local/pgsql/include/server",
    .LIBDIR = "/usr/local/pgsql/lib",
    .LOCALEDIR = "/usr/local/pgsql/share/locale",
    .MANDIR = "/usr/local/pgsql/share/man",
    .PGBINDIR = "/usr/local/pgsql/bin",
    .PGSHAREDIR = "/usr/local/pgsql/share",
    .PKGINCLUDEDIR = "/usr/local/pgsql/include",
    .PKGLIBDIR = "/usr/local/pgsql/lib",
    .SYSCONFDIR = "/usr/local/pgsql/etc",
};

const autoconf = .{
    ._FILE_OFFSET_BITS = null,
    ._LARGE_FILES = null,
    ._LARGEFILE_SOURCE = null,
    .@"inline" = null,
    .AC_APPLE_UNIVERSAL_BUILD = null,
    .BLCKSZ = 8192,
    .CONFIGURE_ARGS = " '--with-ssl=openssl' 'CC=zig cc' 'CXX=zig c++'",
    .DEF_PGPORT = 5432,
    .DEF_PGPORT_STR = "5432",
    .DLSUFFIX = ".so",
    .ENABLE_GSS = null,
    .ENABLE_NLS = null,
    .HAVE__BUILTIN_BSWAP16 = 1,
    .HAVE__BUILTIN_BSWAP32 = 1,
    .HAVE__BUILTIN_BSWAP64 = 1,
    .HAVE__BUILTIN_CLZ = 1,
    .HAVE__BUILTIN_CONSTANT_P = 1,
    .HAVE__BUILTIN_CTZ = 1,
    .HAVE__BUILTIN_FRAME_ADDRESS = 1,
    .HAVE__BUILTIN_OP_OVERFLOW = 1,
    .HAVE__BUILTIN_POPCOUNT = 1,
    .HAVE__BUILTIN_TYPES_COMPATIBLE_P = 1,
    .HAVE__BUILTIN_UNREACHABLE = 1,
    .HAVE__CPUID = null,
    .HAVE__CPUIDEX = null,
    .HAVE__GET_CPUID_COUNT = null,
    .HAVE__STATIC_ASSERT = 1,
    .HAVE_APPEND_HISTORY = 1,
    .HAVE_COMPUTED_GOTO = 1,
    .HAVE_DECL_LLVMCREATEGDBREGISTRATIONLISTENER = null,
    .HAVE_DECL_LLVMCREATEPERFJITEVENTLISTENER = null,
    .HAVE_EDITLINE_HISTORY_H = null,
    .HAVE_EDITLINE_READLINE_H = null,
    .HAVE_GCC__ATOMIC_INT32_CAS = 1,
    .HAVE_GCC__ATOMIC_INT64_CAS = 1,
    .HAVE_GCC__SYNC_CHAR_TAS = 1,
    .HAVE_GCC__SYNC_INT32_CAS = 1,
    .HAVE_GCC__SYNC_INT32_TAS = 1,
    .HAVE_GCC__SYNC_INT64_CAS = 1,
    .HAVE_GETOPT_LONG = 1,
    .HAVE_GETPEERUCRED = null,
    .HAVE_GSSAPI_EXT_H = null,
    .HAVE_GSSAPI_GSSAPI_EXT_H = null,
    .HAVE_GSSAPI_GSSAPI_H = null,
    .HAVE_GSSAPI_H = null,
    .HAVE_HISTORY_H = null,
    .HAVE_HISTORY_TRUNCATE_FILE = 1,
    .HAVE_I_CONSTRAINT__BUILTIN_CONSTANT_P = null,
    .HAVE_INT_OPTERR = 1,
    .HAVE_INT_OPTRESET = null,
    .HAVE_INT_TIMEZONE = 1,
    .HAVE_IO_URING_QUEUE_INIT_MEM = null,
    .HAVE_LDAP_INITIALIZE = null,
    .HAVE_LIBCURL = null,
    .HAVE_LIBLDAP = null,
    .HAVE_LIBLZ4 = null,
    .HAVE_LIBM = 1,
    .HAVE_LIBNUMA = null,
    .HAVE_LIBPAM = null,
    .HAVE_LIBREADLINE = 1,
    .HAVE_LIBSELINUX = null,
    .HAVE_LIBWLDAP32 = null,
    .HAVE_LIBXML2 = null,
    .HAVE_LIBXSLT = null,
    .HAVE_MBARRIER_H = null,
    .HAVE_OSSP_UUID_H = null,
    .HAVE_PAM_PAM_APPL_H = null,
    .HAVE_PTHREAD = 1,
    .HAVE_PTHREAD_BARRIER_WAIT = 1,
    .HAVE_PTHREAD_IS_THREADED_NP = null,
    .HAVE_PTHREAD_PRIO_INHERIT = 1,
    .HAVE_READLINE_H = null,
    .HAVE_READLINE_HISTORY_H = 1,
    .HAVE_READLINE_READLINE_H = 1,
    .HAVE_RL_COMPLETION_MATCHES = 1,
    .HAVE_RL_COMPLETION_SUPPRESS_QUOTE = 1,
    .HAVE_RL_FILENAME_COMPLETION_FUNCTION = 1,
    .HAVE_RL_FILENAME_QUOTE_CHARACTERS = 1,
    .HAVE_RL_FILENAME_QUOTING_FUNCTION = 1,
    .HAVE_RL_RESET_SCREEN_SIZE = 1,
    .HAVE_RL_VARIABLE_BIND = 1,
    .HAVE_SECURITY_PAM_APPL_H = null,
    .HAVE_SETPROCTITLE_FAST = null,
    .HAVE_SSL_CTX_SET_CIPHERSUITES = null,
    .HAVE_SSL_CTX_SET_KEYLOG_CALLBACK = null,
    .HAVE_STRUCT_OPTION = 1,
    .HAVE_THREADSAFE_CURL_GLOBAL_INIT = null,
    .HAVE_TYPEOF = 1,
    .HAVE_UCRED_H = null,
    .HAVE_UNION_SEMUN = null,
    .HAVE_UUID_BSD = null,
    .HAVE_UUID_E2FS = null,
    .HAVE_UUID_OSSP = null,
    .HAVE_VISIBILITY_ATTRIBUTE = 1,
    .HAVE_XSAVE_INTRINSICS = null,
    .MEMSET_LOOP_LIMIT = 1024,
    .PACKAGE_BUGREPORT = "pgsql-bugs@lists.postgresql.org",
    .PACKAGE_NAME = "PostgreSQL",
    .PACKAGE_STRING = std.fmt.comptimePrint("PostgreSQL {}.{}", .{ version.major, version.minor }),
    .PACKAGE_TARNAME = "postgresql",
    .PACKAGE_URL = "https://www.postgresql.org/",
    .PACKAGE_VERSION = std.fmt.comptimePrint("{}.{}", .{ version.major, version.minor }),
    .PG_INT128_TYPE = .__int128,
    .PG_KRB_SRVNAM = "postgres",
    .PG_MAJORVERSION = std.fmt.comptimePrint("{}", .{version.major}),
    .PG_MAJORVERSION_NUM = version.major,
    .PG_MINORVERSION_NUM = version.minor,
    .PG_C_PRINTF_ATTRIBUTE = .printf,
    .PG_CXX_PRINTF_ATTRIBUTE = .printf,
    .pg_restrict = .__restrict,
    .PG_VERSION = std.fmt.comptimePrint("{}.{}", .{ version.major, version.minor }),
    .PG_VERSION_NUM = version.major * 10000 + version.minor,
    .PG_VERSION_STR = std.fmt.comptimePrint("PostgreSQL {}.{}", .{ version.major, version.minor }),
    .PROFILE_PID_DIR = null,
    .PTHREAD_CREATE_JOINABLE = null,
    .RELSEG_SIZE = 131072,
    .restrict = .__restrict,
    .STDC_HEADERS = 1,
    .typeof = null,
    .USE_ARMV8_CRC32C = null,
    .USE_ARMV8_CRC32C_WITH_RUNTIME_CHECK = null,
    .USE_ASSERT_CHECKING = null,
    .USE_AVX512_CRC32C_WITH_RUNTIME_CHECK = null,
    .USE_AVX512_POPCNT_WITH_RUNTIME_CHECK = null,
    .USE_BONJOUR = null,
    .USE_BSD_AUTH = null,
    .USE_ICU = 1,
    .USE_INJECTION_POINTS = null,
    .USE_LDAP = null,
    .USE_LIBCURL = null,
    .USE_LIBNUMA = null,
    .USE_LIBURING = null,
    .USE_LIBXML = null,
    .USE_LIBXSLT = null,
    .USE_LLVM = null,
    .USE_LOONGARCH_CRC32C = null,
    .USE_LZ4 = null,
    .USE_NAMED_POSIX_SEMAPHORES = null,
    .USE_PAM = null,
    .USE_SLICING_BY_8_CRC32C = 1,
    .USE_SSE42_CRC32C = null,
    .USE_SSE42_CRC32C_WITH_RUNTIME_CHECK = null,
    .USE_SVE_POPCNT_WITH_RUNTIME_CHECK = null,
    .USE_SYSTEMD = null,
    .USE_SYSV_SEMAPHORES = null,
    .USE_SYSV_SHARED_MEMORY = 1,
    .USE_UNNAMED_POSIX_SEMAPHORES = 1,
    .USE_WIN32_SEMAPHORES = null,
    .USE_WIN32_SHARED_MEMORY = null,
    .WORDS_BIGENDIAN = null,
    .XLOG_BLCKSZ = 8192,
};
