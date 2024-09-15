const std = @import("std");

const version = .{ .major = 16, .minor = 4 };
const libpq_path = "src/interfaces/libpq";

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const upstream = b.dependency("upstream", .{ .target = target, .optimize = optimize });
    const openssl = b.dependency("openssl", .{ .target = target, .optimize = optimize });
    const openssllib = openssl.artifact("openssl");

    const config_ext = b.addConfigHeader(.{
        .style = .{ .autoconf = upstream.path("src/include/pg_config_ext.h.in") },
        .include_path = "pg_config_ext.h",
    }, .{ .PG_INT64_TYPE = .@"long int" });
    const config = b.addConfigHeader(.{
        .style = .{ .autoconf = upstream.path("src/include/pg_config.h.in") },
        .include_path = "pg_config.h",
    }, autoconf);
    const config_os = b.addConfigHeader(.{
        .style = .{ .autoconf = upstream.path("src/include/port/linux.h") },
        .include_path = "pg_config_os.h",
    }, .{});
    const config_path = b.addConfigHeader(.{
        .style = .blank,
        .include_path = "pg_config_paths.h",
    }, default_paths);

    const lib = b.addStaticLibrary(.{
        .name = "pq",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    lib.addIncludePath(upstream.path(libpq_path));
    lib.addIncludePath(upstream.path("src/include"));
    lib.addConfigHeader(config_ext);
    lib.addConfigHeader(config);
    lib.addConfigHeader(config_os);
    lib.addConfigHeader(config_path);
    lib.addCSourceFiles(.{
        .root = upstream.path(libpq_path),
        .files = &.{
            "fe-auth-scram.c",
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
            "fe-auth.c",

            // Only with SSL:
            "fe-secure-common.c",
            "fe-secure-openssl.c",
        },
        .flags = &CFLAGS,
    });
    lib.installHeadersDirectory(upstream.path(libpq_path), "", .{ .include_extensions = &.{
        "libpq-fe.h",
        "libpq-events.h",
    } });
    lib.installHeadersDirectory(upstream.path("src/include"), "", .{
        .include_extensions = &.{
            "postgres_ext.h",
            "pg_config_manual.h",
            "postgres_fe.h",
        },
    });
    lib.installHeadersDirectory(upstream.path("src/include/libpq"), "libpq", .{ .include_extensions = &.{
        "libpq-fs.h",
        "pqcomm.h",
    } });
    lib.installHeadersDirectory(upstream.path(libpq_path), "internal", .{ .include_extensions = &.{
        "libpq-int.h",
        "fe-auth-sasl.h",
        "pqexpbuffer.h",
    } });
    lib.installConfigHeader(config);
    lib.installConfigHeader(config_ext);
    lib.installConfigHeader(config_os);
    lib.linkLibrary(openssllib);
    b.installArtifact(lib);

    const portlib = b.addStaticLibrary(.{
        .name = "pgport",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    portlib.root_module.addCMacro("_GNU_SOURCE", "1");
    portlib.root_module.addCMacro("FRONTEND", "1");
    portlib.addIncludePath(upstream.path("src/include"));
    portlib.addIncludePath(b.path("include"));
    portlib.addConfigHeader(config_ext);
    portlib.addConfigHeader(config);
    portlib.addConfigHeader(config_os);
    portlib.addConfigHeader(config_path);
    portlib.addCSourceFiles(.{
        .root = upstream.path("src/port"),
        .files = &.{
            "getpeereid.c",
            "pg_crc32c_sb8.c",
            "bsearch_arg.c",
            "chklocale.c",
            "inet_net_ntop.c",
            "noblock.c",
            "path.c",
            "pg_bitutils.c",
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
            "thread.c",
        },
        .flags = &CFLAGS,
    });
    portlib.linkLibrary(openssllib);
    b.installArtifact(portlib);

    const common = b.addStaticLibrary(.{
        .name = "pgcommon",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    common.root_module.addCMacro("_GNU_SOURCE", "1");
    common.root_module.addCMacro("FRONTEND", "1");
    common.addIncludePath(upstream.path("src/include"));
    common.addIncludePath(b.path("include"));
    common.addConfigHeader(config_ext);
    common.addConfigHeader(config);
    common.addConfigHeader(config_os);
    common.addConfigHeader(config_path);
    common.addCSourceFiles(.{
        .root = upstream.path("src/common"),
        .files = &.{
            "archive.c",
            "base64.c",
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
            "unicode_norm.c",
            "username.c",
            "wait_error.c",
            "wchar.c",

            // with openssl:
            "cryptohash_openssl.c",
            "hmac_openssl.c",
            "protocol_openssl.c",
        },
        .flags = &CFLAGS,
    });
    common.linkLibrary(openssllib);
    b.installArtifact(common);

    const test_step = b.step("examples", "Build example programs");
    const test1 = b.addExecutable(.{
        .name = "testlibpq",
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    test1.addCSourceFiles(.{ .root = upstream.path("src/test/examples"), .files = &.{"testlibpq.c"} });
    test1.linkLibrary(lib);
    test1.linkLibrary(portlib);
    test1.linkLibrary(common);
    const install_test1 = b.addInstallArtifact(test1, .{});
    test_step.dependOn(&install_test1.step);
}

const CFLAGS = .{
    "-fwrapv",
    "-fno-strict-aliasing",
    "-fexcess-precision=standard",

    "-Wno-unused-command-line-argument",
    "-Wno-compound-token-split-by-macro",
    "-Wno-format-truncation",
    "-Wno-cast-function-type-strict",

    //"-Werror",
    "-Wall",
    "-Wmissing-prototypes",
    "-Wpointer-arith",
    "-Wdeclaration-after-statement",
    "-Wvla",
    "-Wunguarded-availability-new",
    "-Wendif-labels",
    "-Wmissing-format-attribute",
    "-Wformat-security",
};

const default_paths = .{
    .PGBINDIR = "/usr/local/pgsql/bin",
    .PGSHAREDIR = "/usr/local/pgsql/share",
    .SYSCONFDIR = "/usr/local/pgsql/etc",
    .INCLUDEDIR = "/usr/local/pgsql/include",
    .PKGINCLUDEDIR = "/usr/local/pgsql/include",
    .INCLUDEDIRSERVER = "/usr/local/pgsql/include/server",
    .LIBDIR = "/usr/local/pgsql/lib",
    .PKGLIBDIR = "/usr/local/pgsql/lib",
    .LOCALEDIR = "/usr/local/pgsql/share/locale",
    .DOCDIR = "/usr/local/pgsql/share/doc/",
    .HTMLDIR = "/usr/local/pgsql/share/doc/",
    .MANDIR = "/usr/local/pgsql/share/man",
};

const autoconf = .{
    // TODO: add an option
    .USE_OPENSSL = 1,
    .HAVE_OPENSSL_INIT_SSL = 1,
    .OPENSSL_API_COMPAT = .@"0x10001000L",
    .HAVE_BIO_METH_NEW = 1,
    .HAVE_HMAC_CTX_FREE = 1,
    .HAVE_HMAC_CTX_NEW = 1,

    .ALIGNOF_DOUBLE = @alignOf(f64),
    .ALIGNOF_INT = @alignOf(c_int),
    .ALIGNOF_LONG = @alignOf(c_long),
    .ALIGNOF_PG_INT128_TYPE = @alignOf(i128),
    .ALIGNOF_SHORT = @alignOf(c_short),
    .MAXIMUM_ALIGNOF = @alignOf(c_longlong),

    .SIZEOF_BOOL = @sizeOf(bool),
    .SIZEOF_LONG = @sizeOf(c_long),
    .SIZEOF_OFF_T = @sizeOf(c_long),
    .SIZEOF_SIZE_T = @sizeOf(usize),
    .SIZEOF_VOID_P = @sizeOf(*void),

    .BLCKSZ = 8192,
    .CONFIGURE_ARGS = " '--with-ssl=openssl' 'CC=zig cc' 'CXX=zig c++'",
    .DEF_PGPORT = 5432,
    .DEF_PGPORT_STR = "5432",
    .DLSUFFIX = ".so",
    .ENABLE_THREAD_SAFETY = 1,
    .HAVE_APPEND_HISTORY = 1,
    .HAVE_ATOMICS = 1,
    .HAVE_BACKTRACE_SYMBOLS = 1,
    .HAVE_COMPUTED_GOTO = 1,
    .HAVE_DECL_FDATASYNC = 1,
    .HAVE_DECL_F_FULLFSYNC = 0,
    .HAVE_DECL_POSIX_FADVISE = 1,
    .HAVE_DECL_PREADV = 1,
    .HAVE_DECL_PWRITEV = 1,
    .HAVE_DECL_STRLCAT = 1,
    .HAVE_DECL_STRLCPY = 1,
    .HAVE_DECL_STRNLEN = 1,
    .HAVE_EXECINFO_H = 1,
    .HAVE_EXPLICIT_BZERO = 1,
    .HAVE_FSEEKO = 1,
    .HAVE_GCC__ATOMIC_INT32_CAS = 1,
    .HAVE_GCC__ATOMIC_INT64_CAS = 1,
    .HAVE_GCC__SYNC_CHAR_TAS = 1,
    .HAVE_GCC__SYNC_INT32_CAS = 1,
    .HAVE_GCC__SYNC_INT32_TAS = 1,
    .HAVE_GCC__SYNC_INT64_CAS = 1,
    .HAVE_GETIFADDRS = 1,
    .HAVE_GETOPT = 1,
    .HAVE_GETOPT_H = 1,
    .HAVE_GETOPT_LONG = 1,
    .HAVE_HISTORY_TRUNCATE_FILE = 1,
    .HAVE_IFADDRS_H = 1,
    .HAVE_INET_ATON = 1,
    .HAVE_INET_PTON = 1,
    .HAVE_INTTYPES_H = 1,
    .HAVE_INT_OPTERR = 1,
    .HAVE_INT_TIMEZONE = 1,
    .HAVE_LANGINFO_H = 1,
    .HAVE_LIBM = 1,
    .HAVE_LIBREADLINE = 1,
    .HAVE_LIBZ = 1,
    .HAVE_LOCALE_T = 1,
    .HAVE_LONG_INT_64 = 1,
    .HAVE_MEMORY_H = 1,
    .HAVE_MKDTEMP = 1,
    .HAVE_POSIX_FADVISE = 1,
    .HAVE_POSIX_FALLOCATE = 1,
    .HAVE_PPOLL = 1,
    .HAVE_PTHREAD = 1,
    .HAVE_PTHREAD_BARRIER_WAIT = 1,
    .HAVE_PTHREAD_PRIO_INHERIT = 1,
    .HAVE_READLINE_HISTORY_H = 1,
    .HAVE_READLINE_READLINE_H = 1,
    .HAVE_RL_COMPLETION_MATCHES = 1,
    .HAVE_RL_COMPLETION_SUPPRESS_QUOTE = 1,
    .HAVE_RL_FILENAME_COMPLETION_FUNCTION = 1,
    .HAVE_RL_FILENAME_QUOTE_CHARACTERS = 1,
    .HAVE_RL_FILENAME_QUOTING_FUNCTION = 1,
    .HAVE_RL_RESET_SCREEN_SIZE = 1,
    .HAVE_RL_VARIABLE_BIND = 1,
    .HAVE_SOCKLEN_T = 1,
    .HAVE_SPINLOCKS = 1,
    .HAVE_STDBOOL_H = 1,
    .HAVE_STDINT_H = 1,
    .HAVE_STDLIB_H = 1,
    .HAVE_STRCHRNUL = 1,
    .HAVE_STRERROR_R = 1,
    .HAVE_STRINGS_H = 1,
    .HAVE_STRING_H = 1,
    .HAVE_STRLCAT = 1,
    .HAVE_STRLCPY = 1,
    .HAVE_STRNLEN = 1,
    .HAVE_STRSIGNAL = 1,
    .HAVE_STRUCT_OPTION = 1,
    .HAVE_STRUCT_TM_TM_ZONE = 1,
    .HAVE_SYNCFS = 1,
    .HAVE_SYNC_FILE_RANGE = 1,
    .HAVE_SYSLOG = 1,
    .HAVE_SYS_EPOLL_H = 1,
    .HAVE_SYS_PERSONALITY_H = 1,
    .HAVE_SYS_PRCTL_H = 1,
    .HAVE_SYS_SIGNALFD_H = 1,
    .HAVE_SYS_STAT_H = 1,
    .HAVE_SYS_TYPES_H = 1,
    .HAVE_TERMIOS_H = 1,
    .HAVE_TYPEOF = 1,
    .HAVE_UNISTD_H = 1,
    .HAVE_USELOCALE = 1,
    .HAVE_VISIBILITY_ATTRIBUTE = 1,
    .HAVE_X86_64_POPCNTQ = 1,
    .HAVE__BOOL = 1,
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
    .HAVE__GET_CPUID = 1,
    .HAVE__STATIC_ASSERT = 1,
    .MEMSET_LOOP_LIMIT = 1024,
    .PG_INT128_TYPE = .__int128,
    .PG_INT64_TYPE = .@"long int",
    .PG_KRB_SRVNAM = "postgres",
    .PG_PRINTF_ATTRIBUTE = .printf,
    .INT64_MODIFIER = "l",
    .PG_USE_STDBOOL = 1,
    .PG_VERSION_NUM = version.major * 10000 + version.minor,
    .RELSEG_SIZE = 131072,
    .STDC_HEADERS = 1,
    .USE_ICU = 1,
    .USE_SLICING_BY_8_CRC32C = 1,
    .USE_SYSV_SHARED_MEMORY = 1,
    .USE_UNNAMED_POSIX_SEMAPHORES = 1,
    .XLOG_BLCKSZ = 8192,
    .pg_restrict = .__restrict,
    .restrict = .__restrict,

    .PACKAGE_BUGREPORT = "pgsql-bugs@lists.postgresql.org",
    .PACKAGE_NAME = "PostgreSQL",
    .PACKAGE_STRING = std.fmt.comptimePrint("PostgreSQL {}.{}", .{ version.major, version.minor }),
    .PACKAGE_TARNAME = "postgresql",
    .PACKAGE_URL = "https://www.postgresql.org/",
    .PACKAGE_VERSION = std.fmt.comptimePrint("{}.{}", .{ version.major, version.minor }),

    .PG_MAJORVERSION_NUM = version.major,
    .PG_MINORVERSION_NUM = version.minor,
    .PG_MAJORVERSION = std.fmt.comptimePrint("{}", .{version.major}),
    .PG_VERSION = std.fmt.comptimePrint("{}.{}", .{ version.major, version.minor }),
    .PG_VERSION_STR = std.fmt.comptimePrint("PostgreSQL {}.{}", .{ version.major, version.minor }),

    .AC_APPLE_UNIVERSAL_BUILD = null,
    .ALIGNOF_LONG_LONG_INT = null,
    .ENABLE_GSS = null,
    .ENABLE_NLS = null,
    .HAVE_ASN1_STRING_GET0_DATA = null,
    .HAVE_ATOMIC_H = null,
    .HAVE_COPYFILE = null,
    .HAVE_COPYFILE_H = null,
    .HAVE_CRTDEFS_H = null,
    .HAVE_CRYPTO_LOCK = null,
    .HAVE_DECL_LLVMCREATEGDBREGISTRATIONLISTENER = null,
    .HAVE_DECL_LLVMCREATEPERFJITEVENTLISTENER = null,
    .HAVE_DECL_LLVMGETHOSTCPUFEATURES = null,
    .HAVE_DECL_LLVMGETHOSTCPUNAME = null,
    .HAVE_DECL_LLVMORCGETSYMBOLADDRESSIN = null,
    .HAVE_EDITLINE_HISTORY_H = null,
    .HAVE_EDITLINE_READLINE_H = null,
    .HAVE_GETPEEREID = null,
    .HAVE_GETPEERUCRED = null,
    .HAVE_GSSAPI_EXT_H = null,
    .HAVE_GSSAPI_GSSAPI_EXT_H = null,
    .HAVE_GSSAPI_GSSAPI_H = null,
    .HAVE_GSSAPI_H = null,
    .HAVE_HISTORY_H = null,
    .HAVE_INT64 = null,
    .HAVE_INT8 = null,
    .HAVE_INT_OPTRESET = null,
    .HAVE_I_CONSTRAINT__BUILTIN_CONSTANT_P = null,
    .HAVE_KQUEUE = null,
    .HAVE_LDAP_INITIALIZE = null,
    .HAVE_LIBCRYPTO = null,
    .HAVE_LIBLDAP = null,
    .HAVE_LIBLZ4 = null,
    .HAVE_LIBPAM = null,
    .HAVE_LIBSELINUX = null,
    .HAVE_LIBSSL = null,
    .HAVE_LIBWLDAP32 = null,
    .HAVE_LIBXML2 = null,
    .HAVE_LIBXSLT = null,
    .HAVE_LIBZSTD = null,
    .HAVE_LONG_LONG_INT_64 = null,
    .HAVE_MBARRIER_H = null,
    .HAVE_MBSTOWCS_L = null,
    .HAVE_MEMSET_S = null,
    .HAVE_OSSP_UUID_H = null,
    .HAVE_PAM_PAM_APPL_H = null,
    .HAVE_PTHREAD_IS_THREADED_NP = null,
    .HAVE_READLINE_H = null,
    .HAVE_SECURITY_PAM_APPL_H = null,
    .HAVE_SETPROCTITLE = null,
    .HAVE_SETPROCTITLE_FAST = null,
    .HAVE_SSL_CTX_SET_CERT_CB = null,
    .HAVE_SSL_CTX_SET_NUM_TICKETS = null,
    .HAVE_STRUCT_SOCKADDR_SA_LEN = null,
    .HAVE_SYS_EVENT_H = null,
    .HAVE_SYS_PROCCTL_H = null,
    .HAVE_SYS_UCRED_H = null,
    .HAVE_UCRED_H = null,
    .HAVE_UINT64 = null,
    .HAVE_UINT8 = null,
    .HAVE_UNION_SEMUN = null,
    .HAVE_UUID_BSD = null,
    .HAVE_UUID_E2FS = null,
    .HAVE_UUID_H = null,
    .HAVE_UUID_OSSP = null,
    .HAVE_UUID_UUID_H = null,
    .HAVE_WCSTOMBS_L = null,
    .HAVE_X509_GET_SIGNATURE_INFO = null,
    .HAVE_X509_GET_SIGNATURE_NID = null,
    .HAVE__CONFIGTHREADLOCALE = null,
    .HAVE__CPUID = null,
    .LOCALE_T_IN_XLOCALE = null,
    .PROFILE_PID_DIR = null,
    .PTHREAD_CREATE_JOINABLE = null,
    .STRERROR_R_INT = null, // 1 if not _GNU_SOURCE
    .USE_ARMV8_CRC32C = null,
    .USE_ARMV8_CRC32C_WITH_RUNTIME_CHECK = null,
    .USE_ASSERT_CHECKING = null,
    .USE_BONJOUR = null,
    .USE_BSD_AUTH = null,
    .USE_LDAP = null,
    .USE_LIBXML = null,
    .USE_LIBXSLT = null,
    .USE_LLVM = null,
    .USE_LZ4 = null,
    .USE_NAMED_POSIX_SEMAPHORES = null,
    .USE_PAM = null,
    .USE_SSE42_CRC32C = null,
    .USE_SSE42_CRC32C_WITH_RUNTIME_CHECK = null,
    .USE_SYSTEMD = null,
    .USE_SYSV_SEMAPHORES = null,
    .USE_WIN32_SEMAPHORES = null,
    .USE_WIN32_SHARED_MEMORY = null,
    .USE_ZSTD = null,
    .WCSTOMBS_L_IN_XLOCALE = null,
    .WORDS_BIGENDIAN = null,
    ._FILE_OFFSET_BITS = null,
    ._LARGEFILE_SOURCE = null,
    ._LARGE_FILES = null,
    .@"inline" = null,
    .typeof = null,
};
