// Copyright 2026, The DisplayXR Project
// SPDX-License-Identifier: BSL-1.0
/*!
 * @file
 * @brief  Advice text for Ultraleap's implicit OpenXR layer — see ultraleap_layer.h.
 * @ingroup drv_ultraleap
 */

#include "ultraleap_layer.h"

#include "util/u_openxr_layers.h"

#include <stdio.h>

void
ul_layer_advice(const struct u_openxr_implicit_layer *layer, char *buf, size_t size)
{
	if (buf == NULL || size == 0) {
		return;
	}
	const char *env =
	    layer != NULL && layer->disable_env[0] != '\0' ? layer->disable_env : UL_OPENXR_LAYER_DISABLE_ENV;
	snprintf(buf, size,
	         "Ultraleap's implicit OpenXR API layer %s is registered and enabled (%s %s). The OpenXR loader puts "
	         "it in every OpenXR app, and it resets the Leap tracking service to Head-mounted mode: with a Leap on "
	         "the desk the hands come back left/right-swapped and sideways motion turns into depth. Workaround: "
	         "set %s=1 in the user environment, restart OpenXR apps, then set Desktop mode in the Ultraleap "
	         "Control Panel.",
	         UL_OPENXR_LAYER_NAME, layer != NULL ? layer->hive : "?", layer != NULL ? layer->manifest_path : "?",
	         env);
}
