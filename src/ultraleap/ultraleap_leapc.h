// Copyright 2026, The DisplayXR Project
// SPDX-License-Identifier: BSL-1.0
/*!
 * @file
 * @brief  Run-time binding to the Ultraleap tracking software's LeapC library.
 *
 * The provider does NOT link LeapC. It is built against `LeapC.h` only and
 * binds the handful of functions it calls at run time, from the Ultraleap
 * install on the user's machine:
 *
 * - nothing of Ultraleap's is shipped, copied or staged by DisplayXR;
 * - the library is always opened by ABSOLUTE PATH (on Windows with
 *   `LOAD_WITH_ALTERED_SEARCH_PATH`), never by bare name, so another
 *   `LeapC.dll` on `PATH` — the LeiaSR Platform installs one — can never be
 *   picked up instead (runtime issue #933);
 * - a machine without the Ultraleap tracking software is a STATE
 *   (@ref UL_LEAPC_NOT_FOUND), not a failure to load the provider: the
 *   provider loads, creates its devices, reports its hardware absent, and
 *   retries, so installing the Ultraleap software later needs no reinstall.
 *
 * Where it looks, first hit wins:
 *   1. the `LEAPC_PATH` setting — a file, or a directory holding the library;
 *   2. the platform's default Ultraleap install locations
 *      (`ul_leapc_default_candidate`).
 *
 * @ingroup drv_ultraleap
 */

#pragma once

#include "LeapC.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#ifndef LEAP_CALL
#define LEAP_CALL
#endif

//! The LeapC entry points this provider uses, bound at run time.
struct ul_leapc
{
	eLeapRS(LEAP_CALL *CreateConnection)(const LEAP_CONNECTION_CONFIG *pConfig, LEAP_CONNECTION *phConnection);
	eLeapRS(LEAP_CALL *OpenConnection)(LEAP_CONNECTION hConnection);
	eLeapRS(LEAP_CALL *SetTrackingMode)(LEAP_CONNECTION hConnection, eLeapTrackingMode mode);
	eLeapRS(LEAP_CALL *PollConnection)(LEAP_CONNECTION hConnection, uint32_t timeout, LEAP_CONNECTION_MESSAGE *evt);
	void(LEAP_CALL *CloseConnection)(LEAP_CONNECTION hConnection);
	void(LEAP_CALL *DestroyConnection)(LEAP_CONNECTION hConnection);
};

enum ul_leapc_state
{
	//! No attempt yet.
	UL_LEAPC_NOT_TRIED = 0,
	//! Bound; `ul_leapc_get()` returns the table.
	UL_LEAPC_LOADED = 1,
	//! No LeapC library at the configured path or any default location:
	//! the Ultraleap tracking software is not installed.
	UL_LEAPC_NOT_FOUND = 2,
	//! A library was found but cannot be used: it does not load, lacks an
	//! entry point, or is the wrong kind for this build (see the .c file).
	UL_LEAPC_INCOMPATIBLE = 3,
};

/*!
 * Try to bind LeapC. Idempotent once @ref UL_LEAPC_LOADED; otherwise every
 * call looks again (cheap: a few file-existence checks), which is what lets
 * the poll thread notice the Ultraleap software being installed later.
 *
 * @p path_setting  the `LEAPC_PATH` setting, or NULL / "" for the defaults.
 * @p detail        optional; receives one line saying what was loaded, or
 *                  where it looked and why it could not.
 *
 * Not thread-safe against itself: the provider calls it from one thread at
 * a time (create_devices under the hub lock before the poll thread exists,
 * then the poll thread only).
 */
enum ul_leapc_state
ul_leapc_load(const char *path_setting, char *detail, size_t detail_size);

//! The bound table, or NULL unless the last load returned @ref UL_LEAPC_LOADED.
const struct ul_leapc *
ul_leapc_get(void);

//! The state the last @ref ul_leapc_load left.
enum ul_leapc_state
ul_leapc_state_get(void);

//! "loaded" / "not-found" / "incompatible" / "not-tried".
const char *
ul_leapc_state_str(enum ul_leapc_state state);

/*!
 * The @p index-th default location of the LeapC library on this platform, as
 * an absolute path, or false past the end. Exposed for the log line and tests.
 */
bool
ul_leapc_default_candidate(uint32_t index, char *out, size_t out_size);

#ifdef __cplusplus
}
#endif
