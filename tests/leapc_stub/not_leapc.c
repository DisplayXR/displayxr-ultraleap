// Copyright 2026, The DisplayXR Project
// SPDX-License-Identifier: BSL-1.0
/*!
 * @file
 * @brief  A shared library that is neither LeapC nor its stand-in.
 *
 * Test fixture: the run-time loader must refuse to bind it.
 */

int
dxr_not_leapc_placeholder(void)
{
	return 0;
}
