/*
 * EasyRPG Player - PlayStation 2 input mapping
 *
 * Conservative defaults: ordinary DualShock buttons must never trigger
 * reset/debug/fast-forward accidentally. Users can still remap supported
 * EasyRPG actions later if desired.
 */

#include "input_buttons.h"
#include "keys.h"
#include "game_config.h"

Input::ButtonMappingArray Input::GetDefaultButtonMappings() {
	return {
#if defined(USE_JOYSTICK) && defined(SUPPORT_JOYSTICK)
		// Digital controls
		{UP, Keys::JOY_DPAD_UP},
		{DOWN, Keys::JOY_DPAD_DOWN},
		{LEFT, Keys::JOY_DPAD_LEFT},
		{RIGHT, Keys::JOY_DPAD_RIGHT},

		// PlayStation conventions
		{DECISION, Keys::JOY_A},               // Cross
		{CANCEL, Keys::JOY_B},                 // Circle
		{CANCEL, Keys::JOY_BACK},              // Select = harmless back/cancel
		{SHIFT, Keys::JOY_X},                  // Square
		{SETTINGS_MENU, Keys::JOY_START},      // Start
		{PAGE_UP, Keys::JOY_SHOULDER_LEFT},    // L1
		{PAGE_DOWN, Keys::JOY_SHOULDER_RIGHT}, // R1
#endif

#if defined(USE_JOYSTICK_AXIS) && defined(SUPPORT_JOYSTICK_AXIS)
		// Left analog mirrors the D-pad. Right stick and L2/R2 are deliberately
		// unbound by default to avoid hidden debug/fast-forward actions.
		{UP, Keys::JOY_LSTICK_UP},
		{DOWN, Keys::JOY_LSTICK_DOWN},
		{LEFT, Keys::JOY_LSTICK_LEFT},
		{RIGHT, Keys::JOY_LSTICK_RIGHT},
#endif
	};
}

Input::KeyNamesArray Input::GetInputKeyNames() {
	return {
#if defined(USE_JOYSTICK) && defined(SUPPORT_JOYSTICK)
		{Keys::JOY_A, "Cross"},
		{Keys::JOY_B, "Circle"},
		{Keys::JOY_X, "Square"},
		{Keys::JOY_Y, "Triangle"},
		{Keys::JOY_BACK, "Select"},
		{Keys::JOY_START, "Start"},
		{Keys::JOY_LSTICK, "L3"},
		{Keys::JOY_RSTICK, "R3"},
		{Keys::JOY_SHOULDER_LEFT, "L1"},
		{Keys::JOY_SHOULDER_RIGHT, "R1"},
		{Keys::JOY_DPAD_UP, "D-Pad Up"},
		{Keys::JOY_DPAD_DOWN, "D-Pad Down"},
		{Keys::JOY_DPAD_LEFT, "D-Pad Left"},
		{Keys::JOY_DPAD_RIGHT, "D-Pad Right"},
#endif
#if defined(USE_JOYSTICK_AXIS) && defined(SUPPORT_JOYSTICK_AXIS)
		{Keys::JOY_LSTICK_UP, "Left Stick Up"},
		{Keys::JOY_LSTICK_DOWN, "Left Stick Down"},
		{Keys::JOY_LSTICK_LEFT, "Left Stick Left"},
		{Keys::JOY_LSTICK_RIGHT, "Left Stick Right"},
		{Keys::JOY_RSTICK_UP, "Right Stick Up"},
		{Keys::JOY_RSTICK_DOWN, "Right Stick Down"},
		{Keys::JOY_RSTICK_LEFT, "Right Stick Left"},
		{Keys::JOY_RSTICK_RIGHT, "Right Stick Right"},
		{Keys::JOY_LTRIGGER_FULL, "L2"},
		{Keys::JOY_RTRIGGER_FULL, "R2"},
#endif
	};
}

void Input::GetSupportedConfig(Game_ConfigInput& cfg) {
	// Keep swap toggles hidden. The PS2 mapping is physical-button explicit and
	// already follows Cross=decision / Circle=cancel conventions.
	(void)cfg;
}
