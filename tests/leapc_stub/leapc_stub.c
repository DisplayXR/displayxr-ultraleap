// Copyright 2026, The DisplayXR Project
// SPDX-License-Identifier: BSL-1.0
/*!
 * @file
 * @brief  COMPILE-CHECK STUB bodies for tests/leapc_stub/LeapC.h. NOT LeapC.
 *
 * Behaves like "the tracking service is reachable, no device is attached and
 * no frame ever arrives": a connection can be created and opened, and every
 * poll times out. That is enough for the provider to load, negotiate, create
 * its devices and report its hardware ABSENT - so the stub build can be driven
 * through a real runtime loader as a load / link-surface check. It produces no
 * hand data and proves nothing about tracking.
 */

#include "LeapC.h"

#include <stddef.h>

#ifdef _WIN32
#include <windows.h>
static void
stub_sleep_ms(uint32_t ms)
{
	Sleep(ms);
}
#else
#include <time.h>
static void
stub_sleep_ms(uint32_t ms)
{
	struct timespec ts = {(time_t)(ms / 1000), (long)(ms % 1000) * 1000000L};
	nanosleep(&ts, NULL);
}
#endif

struct _LEAP_CONNECTION
{
	int open;
};

static struct _LEAP_CONNECTION g_stub_connection;

eLeapRS
LeapCreateConnection(const LEAP_CONNECTION_CONFIG *pConfig, LEAP_CONNECTION *phConnection)
{
	(void)pConfig;
	if (phConnection == NULL) {
		return eLeapRS_InvalidArgument;
	}
	*phConnection = &g_stub_connection;
	return eLeapRS_Success;
}

eLeapRS
LeapOpenConnection(LEAP_CONNECTION hConnection)
{
	if (hConnection == NULL) {
		return eLeapRS_InvalidArgument;
	}
	hConnection->open = 1;
	return eLeapRS_Success;
}

eLeapRS
LeapSetTrackingMode(LEAP_CONNECTION hConnection, eLeapTrackingMode mode)
{
	(void)hConnection;
	(void)mode;
	return eLeapRS_Success;
}

eLeapRS
LeapSetPause(LEAP_CONNECTION hConnection, bool pause)
{
	(void)hConnection;
	(void)pause;
	return eLeapRS_Success;
}

eLeapRS
LeapPollConnection(LEAP_CONNECTION hConnection, uint32_t timeout, LEAP_CONNECTION_MESSAGE *evt)
{
	(void)hConnection;
	if (evt != NULL) {
		evt->type = eLeapEventType_None;
		evt->tracking_event = NULL;
	}
	// Honour the timeout so the provider's poll thread does not spin.
	stub_sleep_ms(timeout > 50 ? 50 : timeout);
	return eLeapRS_Timeout;
}

void
LeapCloseConnection(LEAP_CONNECTION hConnection)
{
	if (hConnection != NULL) {
		hConnection->open = 0;
	}
}

void
LeapDestroyConnection(LEAP_CONNECTION hConnection)
{
	(void)hConnection;
}
