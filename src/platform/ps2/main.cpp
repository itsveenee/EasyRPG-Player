/*
 * EasyRPG Player - PlayStation 2 standalone entrypoint.
 *
 * SDL2's PS2 SDL2main resets/synchronizes IOP, applies SBV patches and
 * initializes ps2_drivers filesystem support before calling this SDL_main().
 */
#include <SDL.h>

#include <cerrno>
#include <cstdio>
#include <string>
#include <utility>
#include <vector>
#include <sys/stat.h>

#include <ps2_filesystem_driver.h>
#include "player.h"

namespace {
constexpr const char* kProjectPath = "mass0:/EasyRPG";
constexpr const char* kRtpPath = "mass0:/EasyRPG/RTP";
constexpr const char* kGamesPath = "mass0:/EasyRPG/Games";
constexpr const char* kConfigPath = "mass0:/EasyRPG/config";

void EnsureDirectory(const char* path) {
	if (mkdir(path, 0777) < 0 && errno != EEXIST) {
		std::printf("EasyRPG-PS2: mkdir failed: %s (errno=%d)\n", path, errno);
	}
}
}

int main(int argc, char* argv[]) {
	// ps2_drivers 1.8.0 declares waitUntilDeviceIsReady(char*), not const char*.
	char mass_root[] = "mass0:/";
	if (!waitUntilDeviceIsReady(mass_root)) {
		std::printf("EasyRPG-PS2: mass0:/ is not ready\n");
		return 2;
	}

	EnsureDirectory(kProjectPath);
	EnsureDirectory(kRtpPath);
	EnsureDirectory(kGamesPath);
	EnsureDirectory(kConfigPath);

	std::vector<std::string> args;
	args.emplace_back((argc > 0 && argv && argv[0]) ? argv[0] : "EasyRPG-PS2");
	args.emplace_back("--config-path");
	args.emplace_back(kConfigPath);
	args.emplace_back("--project-path");
	args.emplace_back(kProjectPath);
	args.emplace_back("--rtp-path");
	args.emplace_back(kRtpPath);
	args.emplace_back("--no-log-color");

	for (int i = 1; i < argc; ++i) {
		if (argv[i]) args.emplace_back(argv[i]);
	}

	Player::Init(std::move(args));
	Player::Run();
	return Player::exit_code;
}
