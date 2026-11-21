// Copyright 2026, The DisplayXR Project
// SPDX-License-Identifier: BSL-1.0
/*!
 * @file
 * @brief  What this provider knows about Ultraleap's own OpenXR API layer.
 *
 * Ultraleap's installer registers `XR_APILAYER_ULTRALEAP_hand_tracking` as an
 * IMPLICIT layer, so the OpenXR loader puts it in every OpenXR app —
 * DisplayXR ones included — and each load switches the Ultraleap tracking
 * service back to Head-mounted mode. For a Leap on the desk that swaps the
 * hands and turns sideways motion into depth. The provider cannot stop it;
 * it says so once, with the workaround.
 *
 * The vendor-specific half (the layer's name, its off switch, the advice
 * text) lives here. The generic lookup ("is implicit layer X registered and
 * active?") is the runtime's `util/u_openxr_layers.h`.
 *
 * Forked from the runtime trunk's `u_openxr_layers.{h,c}` (v2.69.3), where
 * the same constants and text still exist for `displayxr-cli`.
 *
 * @ingroup drv_ultraleap
 */

#pragma once

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

struct u_openxr_implicit_layer;

//! Ultraleap's hand-tracking API layer.
#define UL_OPENXR_LAYER_NAME "XR_APILAYER_ULTRALEAP_hand_tracking"

//! The variable its manifest declares as `disable_environment`.
#define UL_OPENXR_LAYER_DISABLE_ENV "DISABLE_XR_APILAYER_ULTRALEAP_HAND_TRACKING_1"

/*!
 * One-line advisory for an ACTIVE layer registration (@p layer from
 * `u_openxr_implicit_layer_find`): what it does to a desk-mounted Leap and
 * the workaround.
 */
void
ul_layer_advice(const struct u_openxr_implicit_layer *layer, char *buf, size_t size);

#ifdef __cplusplus
}
#endif
