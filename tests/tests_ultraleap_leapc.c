// Copyright 2026, The DisplayXR Project
// SPDX-License-Identifier: BSL-1.0
/*!
 * @file
 * @brief  The run-time LeapC loader (src/ultraleap/ultraleap_leapc.c), driven
 *         through every outcome against the in-repo stand-in library.
 *
 * Compiled against the stand-in header, so the loader is in compile-check
 * mode: no default locations, and only a library carrying the stand-in's
 * marker may be bound. Plain C, no test framework: it must build wherever the
 * loader builds.
 */

#include "ultraleap_leapc.h"

#include <stdio.h>
#include <string.h>

static int g_failed = 0;

#define CHECK(COND)                                                                                                    \
	do {                                                                                                           \
		if (!(COND)) {                                                                                         \
			printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #COND);                                         \
			g_failed++;                                                                                    \
		}                                                                                                      \
	} while (0)

int
main(void)
{
	char detail[2048];

	// Nothing tried yet.
	CHECK(ul_leapc_state_get() == UL_LEAPC_NOT_TRIED);
	CHECK(ul_leapc_get() == NULL);

	// A compile-check build has no default locations at all.
	char cand[1024];
	CHECK(!ul_leapc_default_candidate(0, cand, sizeof(cand)));

	// No setting: nowhere to look -> the "tracking software not found" state.
	CHECK(ul_leapc_load(NULL, detail, sizeof(detail)) == UL_LEAPC_NOT_FOUND);
	CHECK(strstr(detail, "LEAPC_PATH") != NULL);
	CHECK(ul_leapc_load("", NULL, 0) == UL_LEAPC_NOT_FOUND);
	CHECK(ul_leapc_get() == NULL);

	// A relative path is never used (it would mean a search).
	CHECK(ul_leapc_load("LeapC.dll", detail, sizeof(detail)) == UL_LEAPC_NOT_FOUND);

	// A path with nothing there.
	CHECK(ul_leapc_load(UL_TEST_STUB_LIB ".missing", detail, sizeof(detail)) == UL_LEAPC_NOT_FOUND);
	CHECK(strstr(detail, ".missing") != NULL);
	printf("not found : %s\n", detail);

	// A real shared library that is not the stand-in: refused, not bound.
	CHECK(ul_leapc_load(UL_TEST_NOT_LEAPC_LIB, detail, sizeof(detail)) == UL_LEAPC_INCOMPATIBLE);
	CHECK(ul_leapc_get() == NULL);
	CHECK(strcmp(ul_leapc_state_str(ul_leapc_state_get()), "incompatible") == 0);
	printf("refused   : %s\n", detail);

	// The directory holding the stand-in: found and bound.
	CHECK(ul_leapc_load(UL_TEST_STUB_DIR, detail, sizeof(detail)) == UL_LEAPC_LOADED);
	printf("loaded    : %s\n", detail);
	const struct ul_leapc *api = ul_leapc_get();
	CHECK(api != NULL);
	if (api != NULL) {
		LEAP_CONNECTION conn = NULL;
		CHECK(api->CreateConnection(NULL, &conn) == eLeapRS_Success);
		CHECK(conn != NULL);
		CHECK(api->OpenConnection(conn) == eLeapRS_Success);
		CHECK(api->SetTrackingMode(conn, eLeapTrackingMode_Desktop) == eLeapRS_Success);
		LEAP_CONNECTION_MESSAGE msg;
		CHECK(api->PollConnection(conn, 1, &msg) == eLeapRS_Timeout);
		api->CloseConnection(conn);
		api->DestroyConnection(conn);
	}

	// Loaded is sticky: a later call with a bad path changes nothing.
	CHECK(ul_leapc_load("/nonexistent", detail, sizeof(detail)) == UL_LEAPC_LOADED);
	CHECK(ul_leapc_get() == api);

	printf(g_failed == 0 ? "ultraleap_leapc: all checks passed\n" : "ultraleap_leapc: %d check(s) FAILED\n", g_failed);
	return g_failed == 0 ? 0 : 1;
}
