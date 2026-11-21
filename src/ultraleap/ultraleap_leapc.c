// Copyright 2026, The DisplayXR Project
// SPDX-License-Identifier: BSL-1.0
/*!
 * @file
 * @brief  Run-time binding to LeapC — see ultraleap_leapc.h.
 *
 * COMPILE-CHECK BUILDS. When this file is compiled against the stand-in
 * header (`tests/leapc_stub/LeapC.h`, which defines
 * `DXR_LEAPC_COMPILE_CHECK_STUB`), the struct layouts it was built with are
 * invented, so binding a REAL LeapC would corrupt memory. Such a build
 * therefore (a) has no default locations — it only ever looks at
 * `LEAPC_PATH` — and (b) accepts only a library that exports the stub's
 * marker symbol. A real build refuses a library that exports the marker.
 * That keeps the two worlds apart while letting the stub build exercise
 * exactly the loading code a real build runs.
 *
 * @ingroup drv_ultraleap
 */

#include "ultraleap_leapc.h"

#include <stdio.h>
#include <string.h>

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#define UL_LEAPC_FILE "LeapC.dll"
#define UL_PATH_SEP '\\'
typedef HMODULE ul_lib_t;
#else
#include <dlfcn.h>
#include <sys/stat.h>
#ifdef __APPLE__
#define UL_LEAPC_FILE "libLeapC.dylib"
#else
#define UL_LEAPC_FILE "libLeapC.so"
#endif
#define UL_PATH_SEP '/'
typedef void *ul_lib_t;
#endif

#define UL_LEAPC_STUB_MARKER "dxr_leapc_compile_check_stub_marker"
#define UL_PATH_MAX 1024

static struct ul_leapc g_api;
static enum ul_leapc_state g_state = UL_LEAPC_NOT_TRIED;


/*
 *
 * Platform helpers.
 *
 */

#ifdef _WIN32

static bool
utf8_to_wide(const char *in, wchar_t *out, int out_count)
{
	return MultiByteToWideChar(CP_UTF8, 0, in, -1, out, out_count) > 0;
}

//! 1 = a file, 2 = a directory, 0 = nothing there.
static int
path_kind(const char *path)
{
	wchar_t w[UL_PATH_MAX];
	if (!utf8_to_wide(path, w, UL_PATH_MAX)) {
		return 0;
	}
	DWORD attr = GetFileAttributesW(w);
	if (attr == INVALID_FILE_ATTRIBUTES) {
		return 0;
	}
	return (attr & FILE_ATTRIBUTE_DIRECTORY) != 0 ? 2 : 1;
}

static ul_lib_t
lib_open(const char *abs_path)
{
	wchar_t w[UL_PATH_MAX];
	if (!utf8_to_wide(abs_path, w, UL_PATH_MAX)) {
		return NULL;
	}
	// Absolute path + ALTERED_SEARCH_PATH: LeapC's own dependencies are
	// searched next to it first, and nothing here goes through PATH (#933).
	return LoadLibraryExW(w, NULL, LOAD_WITH_ALTERED_SEARCH_PATH);
}

static void *
lib_sym(ul_lib_t lib, const char *name)
{
	return (void *)GetProcAddress(lib, name);
}

static void
lib_close(ul_lib_t lib)
{
	FreeLibrary(lib);
}

static bool
is_absolute(const char *p)
{
	return (p[0] != '\0' && p[1] == ':') || (p[0] == '\\' && p[1] == '\\');
}

#else

static int
path_kind(const char *path)
{
	struct stat st;
	if (stat(path, &st) != 0) {
		return 0;
	}
	return S_ISDIR(st.st_mode) ? 2 : 1;
}

static ul_lib_t
lib_open(const char *abs_path)
{
	return dlopen(abs_path, RTLD_NOW | RTLD_LOCAL);
}

static void *
lib_sym(ul_lib_t lib, const char *name)
{
	return dlsym(lib, name);
}

static void
lib_close(ul_lib_t lib)
{
	dlclose(lib);
}

static bool
is_absolute(const char *p)
{
	return p[0] == '/';
}

#endif


/*
 *
 * Candidates.
 *
 */

bool
ul_leapc_default_candidate(uint32_t index, char *out, size_t out_size)
{
#ifdef DXR_LEAPC_COMPILE_CHECK_STUB
	// A compile-check build never goes looking for a real LeapC.
	(void)index;
	(void)out;
	(void)out_size;
	return false;
#elif defined(_WIN32)
	// The Ultraleap installer's SDK folder. ProgramW6432 is the 64-bit
	// Program Files even when asked from a WOW64 process.
	// TO VERIFY on a machine with the current Ultraleap software; the
	// LEAPC_PATH setting covers any other layout.
	static const char *const tails[] = {
	    "\\Ultraleap\\LeapSDK\\lib\\x64\\" UL_LEAPC_FILE,
	};
	if (index >= sizeof(tails) / sizeof(tails[0])) {
		return false;
	}
	char pf[UL_PATH_MAX];
	DWORD n = GetEnvironmentVariableA("ProgramW6432", pf, (DWORD)sizeof(pf));
	if (n == 0 || n >= sizeof(pf)) {
		n = GetEnvironmentVariableA("ProgramFiles", pf, (DWORD)sizeof(pf));
	}
	if (n == 0 || n >= sizeof(pf)) {
		snprintf(pf, sizeof(pf), "C:\\Program Files");
	}
	return snprintf(out, out_size, "%s%s", pf, tails[index]) < (int)out_size;
#else
	// Linux / macOS are experimental for this provider: these locations
	// are unverified. Use LEAPC_PATH.
	static const char *const paths[] = {
#ifdef __APPLE__
	    "/Applications/Ultraleap Hand Tracking.app/Contents/LeapSDK/lib/" UL_LEAPC_FILE,
#else
	    "/opt/ultraleap-hand-tracking/LeapSDK/lib/" UL_LEAPC_FILE,
	    "/usr/lib/ultraleap-hand-tracking-service/" UL_LEAPC_FILE,
#endif
	};
	if (index >= sizeof(paths) / sizeof(paths[0])) {
		return false;
	}
	return snprintf(out, out_size, "%s", paths[index]) < (int)out_size;
#endif
}

//! Resolve the LEAPC_PATH setting (a file or a directory) to a library path.
static bool
setting_candidate(const char *setting, char *out, size_t out_size)
{
	if (setting == NULL || setting[0] == '\0' || !is_absolute(setting)) {
		return false;
	}
	if (path_kind(setting) == 2) {
		const size_t len = strlen(setting);
		const bool has_sep = setting[len - 1] == '/' || setting[len - 1] == '\\';
		if (has_sep) {
			return snprintf(out, out_size, "%s%s", setting, UL_LEAPC_FILE) < (int)out_size;
		}
		return snprintf(out, out_size, "%s%c%s", setting, UL_PATH_SEP, UL_LEAPC_FILE) < (int)out_size;
	}
	return snprintf(out, out_size, "%s", setting) < (int)out_size;
}


/*
 *
 * Binding.
 *
 */

/*
 * Compile-time proof that the table's pointer types are the prototypes of the
 * LeapC.h this file was built against. `sizeof` does not evaluate its
 * operand, so this references no LeapC symbol and adds no import; it only
 * makes a drifted signature a compile error instead of a wild call.
 */
#define UL_SAME_SIGNATURE(FIELD, FUNC) ((void)sizeof(((struct ul_leapc *)0)->FIELD = FUNC))
static inline void
ul_leapc_signature_check(void)
{
	UL_SAME_SIGNATURE(CreateConnection, LeapCreateConnection);
	UL_SAME_SIGNATURE(OpenConnection, LeapOpenConnection);
	UL_SAME_SIGNATURE(SetTrackingMode, LeapSetTrackingMode);
	UL_SAME_SIGNATURE(PollConnection, LeapPollConnection);
	UL_SAME_SIGNATURE(CloseConnection, LeapCloseConnection);
	UL_SAME_SIGNATURE(DestroyConnection, LeapDestroyConnection);
}

//! Bind every entry point from an opened library. False if one is missing.
static bool
bind_all(ul_lib_t lib, struct ul_leapc *api, const char **out_missing)
{
#define UL_BIND(FIELD, NAME)                                                                                           \
	do {                                                                                                           \
		void *p = lib_sym(lib, NAME);                                                                          \
		if (p == NULL) {                                                                                       \
			*out_missing = NAME;                                                                           \
			return false;                                                                                  \
		}                                                                                                      \
		/* Object-to-function pointer conversion, the dlsym idiom. */                                         \
		memcpy(&api->FIELD, &p, sizeof(p));                                                                    \
	} while (0)

	UL_BIND(CreateConnection, "LeapCreateConnection");
	UL_BIND(OpenConnection, "LeapOpenConnection");
	UL_BIND(SetTrackingMode, "LeapSetTrackingMode");
	UL_BIND(PollConnection, "LeapPollConnection");
	UL_BIND(CloseConnection, "LeapCloseConnection");
	UL_BIND(DestroyConnection, "LeapDestroyConnection");
#undef UL_BIND
	return true;
}

//! Try one absolute path. Returns the resulting state; fills @p why on failure.
static enum ul_leapc_state
try_path(const char *path, char *why, size_t why_size)
{
	if (path_kind(path) != 1) {
		return UL_LEAPC_NOT_FOUND;
	}
	ul_lib_t lib = lib_open(path);
	if (lib == NULL) {
		snprintf(why, why_size, "%s exists but could not be loaded", path);
		return UL_LEAPC_INCOMPATIBLE;
	}

	const bool is_stub_lib = lib_sym(lib, UL_LEAPC_STUB_MARKER) != NULL;
#ifdef DXR_LEAPC_COMPILE_CHECK_STUB
	if (!is_stub_lib) {
		snprintf(why, why_size,
		         "%s is a real LeapC, and this is a COMPILE-CHECK build of the provider (built against a "
		         "stand-in header) - refusing to bind it",
		         path);
		lib_close(lib);
		return UL_LEAPC_INCOMPATIBLE;
	}
#else
	if (is_stub_lib) {
		snprintf(why, why_size, "%s is the DisplayXR compile-check stub, not LeapC - refusing to bind it", path);
		lib_close(lib);
		return UL_LEAPC_INCOMPATIBLE;
	}
#endif

	struct ul_leapc api;
	const char *missing = NULL;
	memset(&api, 0, sizeof(api));
	if (!bind_all(lib, &api, &missing)) {
		snprintf(why, why_size, "%s has no %s (a LeapC too old for this provider?)", path, missing);
		lib_close(lib);
		return UL_LEAPC_INCOMPATIBLE;
	}

	// Kept loaded for the life of the process: LeapC owns threads.
	g_api = api;
	return UL_LEAPC_LOADED;
}

enum ul_leapc_state
ul_leapc_load(const char *path_setting, char *detail, size_t detail_size)
{
	char scratch[8];
	if (detail == NULL || detail_size == 0) {
		detail = scratch;
		detail_size = sizeof(scratch);
	}
	detail[0] = '\0';

	if (g_state == UL_LEAPC_LOADED) {
		return g_state;
	}

	char looked[UL_PATH_MAX * 2];
	size_t looked_len = 0;
	looked[0] = '\0';
	char why[UL_PATH_MAX + 256];
	why[0] = '\0';
	enum ul_leapc_state result = UL_LEAPC_NOT_FOUND;

	for (int i = -1;; i++) {
		char path[UL_PATH_MAX];
		if (i < 0) {
			if (!setting_candidate(path_setting, path, sizeof(path))) {
				continue;
			}
		} else if (!ul_leapc_default_candidate((uint32_t)i, path, sizeof(path))) {
			break;
		}

		int n = snprintf(looked + looked_len, sizeof(looked) - looked_len, "%s%s", looked_len > 0 ? "; " : "",
		                 path);
		if (n > 0 && (size_t)n < sizeof(looked) - looked_len) {
			looked_len += (size_t)n;
		}

		enum ul_leapc_state st = try_path(path, why, sizeof(why));
		if (st == UL_LEAPC_LOADED) {
			g_state = UL_LEAPC_LOADED;
			snprintf(detail, detail_size, "LeapC loaded from %s", path);
			return g_state;
		}
		if (st == UL_LEAPC_INCOMPATIBLE) {
			result = UL_LEAPC_INCOMPATIBLE; // Remember, keep looking.
		}
	}

	g_state = result;
	if (result == UL_LEAPC_INCOMPATIBLE) {
		snprintf(detail, detail_size, "%s", why);
	} else if (looked_len == 0) {
		snprintf(detail, detail_size, "no LeapC location to look in (set the LEAPC_PATH setting)");
	} else {
		snprintf(detail, detail_size, "no LeapC library at: %s", looked);
	}
	return g_state;
}

const struct ul_leapc *
ul_leapc_get(void)
{
	return g_state == UL_LEAPC_LOADED ? &g_api : NULL;
}

enum ul_leapc_state
ul_leapc_state_get(void)
{
	return g_state;
}

const char *
ul_leapc_state_str(enum ul_leapc_state state)
{
	switch (state) {
	case UL_LEAPC_LOADED: return "loaded";
	case UL_LEAPC_NOT_FOUND: return "not-found";
	case UL_LEAPC_INCOMPATIBLE: return "incompatible";
	case UL_LEAPC_NOT_TRIED:
	default: return "not-tried";
	}
}
