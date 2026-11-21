// Copyright 2026, The DisplayXR Project
// SPDX-License-Identifier: BSL-1.0
/*!
 * @file
 * @brief  COMPILE-CHECK STUB. This is NOT the Ultraleap LeapC header.
 *
 * It declares only the names `src/ultraleap/ultraleap_provider.cpp` refers
 * to, written from that file's usage, so the provider sources can be parsed
 * and linked on a machine (and a CI runner) that has no Ultraleap SDK. It is
 * selected only by `-DULTRALEAP_USE_LEAPC_STUB=ON`, which also renames the
 * output `DisplayXR-Ultraleap-STUBCHECK` and disables every install /
 * packaging rule.
 *
 * Nothing here is ABI-compatible with the real SDK: struct layouts, packing,
 * enumerator values and calling conventions are all invented. A binary built
 * against this file must never be registered with a runtime on a machine
 * where real LeapC could be loaded. The real header ships with the Ultraleap
 * tracking SDK and is the only thing a shippable build may use.
 */

#pragma once

#define DXR_LEAPC_COMPILE_CHECK_STUB 1

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum _eLeapRS
{
	eLeapRS_Success = 0,
	eLeapRS_UnknownError,
	eLeapRS_InvalidArgument,
	eLeapRS_InsufficientResources,
	eLeapRS_InsufficientBuffer,
	eLeapRS_Timeout,
	eLeapRS_NotConnected,
	eLeapRS_HandshakeIncomplete,
	eLeapRS_BufferSizeOverflow,
	eLeapRS_ProtocolError,
	eLeapRS_InvalidClientID,
	eLeapRS_UnexpectedClosed,
	eLeapRS_UnknownImageFrameRequest,
	eLeapRS_UnknownTrackingFrameID,
	eLeapRS_RoutineIsNotSeer,
	eLeapRS_TimestampTooEarly,
	eLeapRS_ConcurrentPoll,
	eLeapRS_NotAvailable,
	eLeapRS_NotStreaming,
	eLeapRS_CannotOpenDevice,
} eLeapRS;

typedef enum _eLeapEventType
{
	eLeapEventType_None = 0,
	eLeapEventType_Connection,
	eLeapEventType_ConnectionLost,
	eLeapEventType_Device,
	eLeapEventType_DeviceLost,
	eLeapEventType_Tracking,
} eLeapEventType;

typedef enum _eLeapHandType
{
	eLeapHandType_Left = 0,
	eLeapHandType_Right,
} eLeapHandType;

typedef enum _eLeapTrackingMode
{
	eLeapTrackingMode_Desktop = 0,
	eLeapTrackingMode_HMD,
} eLeapTrackingMode;

typedef struct _LEAP_CONNECTION *LEAP_CONNECTION;
typedef struct _LEAP_CONNECTION_CONFIG LEAP_CONNECTION_CONFIG;

typedef struct _LEAP_VECTOR
{
	float x, y, z;
} LEAP_VECTOR;

typedef struct _LEAP_QUATERNION
{
	float x, y, z, w;
} LEAP_QUATERNION;

typedef struct _LEAP_BONE
{
	LEAP_VECTOR prev_joint;
	LEAP_VECTOR next_joint;
	float width;
	LEAP_QUATERNION rotation;
} LEAP_BONE;

typedef struct _LEAP_DIGIT
{
	LEAP_BONE metacarpal;
	LEAP_BONE proximal;
	LEAP_BONE intermediate;
	LEAP_BONE distal;
} LEAP_DIGIT;

typedef struct _LEAP_PALM
{
	LEAP_VECTOR position;
	LEAP_VECTOR velocity;
	float width;
	LEAP_QUATERNION orientation;
} LEAP_PALM;

typedef struct _LEAP_HAND
{
	eLeapHandType type;
	float pinch_strength;
	float grab_strength;
	LEAP_PALM palm;
	LEAP_DIGIT thumb;
	LEAP_DIGIT index;
	LEAP_DIGIT middle;
	LEAP_DIGIT ring;
	LEAP_DIGIT pinky;
	LEAP_BONE arm;
} LEAP_HAND;

typedef struct _LEAP_FRAME_HEADER
{
	int64_t timestamp;
} LEAP_FRAME_HEADER;

typedef struct _LEAP_TRACKING_EVENT
{
	LEAP_FRAME_HEADER info;
	uint32_t nHands;
	LEAP_HAND *pHands;
} LEAP_TRACKING_EVENT;

typedef struct _LEAP_CONNECTION_MESSAGE
{
	eLeapEventType type;
	const LEAP_TRACKING_EVENT *tracking_event;
} LEAP_CONNECTION_MESSAGE;

eLeapRS
LeapCreateConnection(const LEAP_CONNECTION_CONFIG *pConfig, LEAP_CONNECTION *phConnection);
eLeapRS
LeapOpenConnection(LEAP_CONNECTION hConnection);
eLeapRS
LeapSetTrackingMode(LEAP_CONNECTION hConnection, eLeapTrackingMode mode);
eLeapRS
LeapSetPause(LEAP_CONNECTION hConnection, bool pause);
eLeapRS
LeapPollConnection(LEAP_CONNECTION hConnection, uint32_t timeout, LEAP_CONNECTION_MESSAGE *evt);
void
LeapCloseConnection(LEAP_CONNECTION hConnection);
void
LeapDestroyConnection(LEAP_CONNECTION hConnection);

#ifdef __cplusplus
}
#endif
