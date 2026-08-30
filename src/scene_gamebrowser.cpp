/*
 * This file is part of EasyRPG Player.
 *
 * EasyRPG Player is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * EasyRPG Player is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with EasyRPG Player. If not, see <http://www.gnu.org/licenses/>.
 */

// Headers
#include "scene_gamebrowser.h"

#include <memory>
#ifdef __PS2__
#include <sys/stat.h>
#endif
#include "options.h"
#include "scene_settings.h"
#include "audio_midi.h"
#include "audio_secache.h"
#include "cache.h"
#include "game_system.h"
#include "input.h"
#include "player.h"
#include "scene_logo.h"
#include "bitmap.h"
#include "audio.h"
#include "output.h"

#ifdef __PS2__
/* EasyRPG-PS2 runtime v1: mass0 hotplug.
 * Use direct stat() so this probe is independent of EasyRPG's DirectoryTree cache. */
static bool Ps2Mass0Present() {
	struct stat st = {};
	return stat("mass0:/", &st) == 0;
}
#endif

Scene_GameBrowser::Scene_GameBrowser() {
	type = Scene::GameBrowser;
}

void Scene_GameBrowser::Start() {
	initial_debug_flag = Player::debug_flag;
#ifdef __PS2__
	ps2_mass_present = Ps2Mass0Present();
	ps2_media_poll_counter = 0;
#endif
	Main_Data::game_system = std::make_unique<Game_System>();
	Main_Data::game_system->SetSystemGraphic(CACHE_DEFAULT_BITMAP, lcf::rpg::System::Stretch_stretch, lcf::rpg::System::Font_gothic);
	stack.push_back({ FileFinder::Game(), 0 });
	CreateWindows();
	Game_Clock::ResetFrame(Game_Clock::now());
}

void Scene_GameBrowser::Continue(SceneType /* prev_scene */) {
	Main_Data::game_system->BgmStop();

	Cache::ClearAll();
	AudioSeCache::Clear();
	MidiDecoder::Reset();
	lcf::Data::Clear();
	Player::ResetGameObjects();

	// Restore the base resolution
	Player::RestoreBaseResolution();

	Player::game_title = "";
	Player::game_title_original = "";

	Player::translation.Reset();

	Font::ResetDefault();

	Main_Data::game_system = std::make_unique<Game_System>();
	Main_Data::game_system->SetSystemGraphic(CACHE_DEFAULT_BITMAP, lcf::rpg::System::Stretch_stretch, lcf::rpg::System::Font_gothic);

	Player::debug_flag = initial_debug_flag;
}

void Scene_GameBrowser::vUpdate() {
#ifdef __PS2__
	UpdatePs2Storage();
	if (exit_confirm_active) {
		exit_confirm_window->Update();
		UpdateExitConfirmation();
		return;
	}
#endif
	if (game_loading) {
		BootGame();
		return;
	}

	command_window->Update();
	gamelist_window->Update();

	if (command_window->GetActive()) {
		UpdateCommand();
	}
	else if (gamelist_window->GetActive()) {
		UpdateGameListSelection();
	}
}

#ifdef __PS2__
void Scene_GameBrowser::UpdatePs2Storage() {
	/* Poll twice per second at ~60 fps. Do no filesystem I/O every frame. */
	if (++ps2_media_poll_counter < 30) {
		return;
	}
	ps2_media_poll_counter = 0;

	const bool present = Ps2Mass0Present();
	if (present == ps2_mass_present) {
		return;
	}
	ps2_mass_present = present;

	if (stack.empty() || !gamelist_window || !command_window) {
		return;
	}

	/* EasyRPG-PS2 runtime v1: refresh all DirectoryTree caches after mass0 transition.
	 * This also clears the "known missing" cache, which otherwise survives removal. */
	stack.front().filesystem.GetOwner().ClearCache("");

	bool refreshed = gamelist_window->Refresh(
		stack.back().filesystem, stack.size() > 1);

	/* If the user was inside a directory that no longer exists on the new
	 * device, recover to the browser root instead of leaving a stale view. */
	if (present && !refreshed && stack.size() > 1) {
		stack.resize(1);
		stack.front().filesystem.GetOwner().ClearCache("");
		refreshed = gamelist_window->Refresh(stack.front().filesystem, false);
	}

	if (!present || !refreshed || !gamelist_window->HasValidEntry()) {
		command_window->DisableItem(GameList);
		command_window->SetActive(true);
		command_window->SetIndex(GameList);
		gamelist_window->SetActive(false);
		gamelist_window->SetIndex(-1);
	} else {
		command_window->EnableItem(GameList);
	}

	Output::Debug("PS2: mass0 {} - browser filesystem cache refreshed",
		present ? "inserted" : "removed");
}
#endif

void Scene_GameBrowser::CreateWindows() {
	// Create Options Window
	std::vector<std::string> options;

	options.push_back("Games");
	options.push_back("Settings");
	options.push_back("About");
	options.push_back("Exit");

	command_window = std::make_unique<Window_Command_Horizontal>(options, Player::screen_width);
	command_window->SetY(32);
	command_window->SetIndex(0);

	gamelist_window = std::make_unique<Window_GameList>(0, 64, Player::screen_width, Player::screen_height - 64);
	gamelist_window->Refresh(stack.back().filesystem, false);

	if (stack.size() == 1 && !gamelist_window->HasValidEntry()) {
		command_window->DisableItem(0);
	}

	help_window = std::make_unique<Window_Help>(0, 0, Player::screen_width, 32);
	help_window->SetText("EasyRPG Player - RPG Maker 2000/2003 interpreter");

	load_window = std::make_unique<Window_Help>(Player::screen_width / 4, Player::screen_height / 2 - 16, Player::screen_width / 2, 32);
	load_window->SetText("Loading...");
	load_window->SetVisible(false);

#ifdef __PS2__
	exit_prompt_window = std::make_unique<Window_Help>(
		Player::screen_width / 4, Player::screen_height / 2 - 32,
		Player::screen_width / 2, 32);
	exit_prompt_window->SetText("Exit EasyRPG Player?");
	exit_prompt_window->SetVisible(false);

	exit_confirm_window = std::make_unique<Window_Command_Horizontal>(
		std::vector<std::string>{ "No", "Yes" }, Player::screen_width / 2);
	exit_confirm_window->SetX(Player::screen_width / 4);
	exit_confirm_window->SetY(Player::screen_height / 2);
	exit_confirm_window->SetIndex(0);
	exit_confirm_window->SetActive(false);
	exit_confirm_window->SetVisible(false);
#endif

	about_window = std::make_unique<Window_About>(0, 64, Player::screen_width, Player::screen_height - 64);
	about_window->Refresh();
	about_window->SetVisible(false);
}

#ifdef __PS2__
void Scene_GameBrowser::OpenExitConfirmation() {
	if (exit_confirm_active) {
		return;
	}
	exit_confirm_active = true;
	command_window->SetActive(false);
	gamelist_window->SetActive(false);
	exit_prompt_window->SetVisible(true);
	exit_confirm_window->SetVisible(true);
	exit_confirm_window->SetActive(true);
	exit_confirm_window->SetIndex(0); // No is the safe default
}

void Scene_GameBrowser::CloseExitConfirmation() {
	exit_confirm_active = false;
	exit_confirm_window->SetActive(false);
	exit_confirm_window->SetVisible(false);
	exit_prompt_window->SetVisible(false);
	command_window->SetActive(true);
	command_window->SetIndex(Quit);
}

void Scene_GameBrowser::UpdateExitConfirmation() {
	if (Input::IsTriggered(Input::CANCEL)) {
		CloseExitConfirmation();
		return;
	}
	if (!Input::IsTriggered(Input::DECISION)) {
		return;
	}

	if (exit_confirm_window->GetIndex() == 1) {
		exit_confirm_window->SetActive(false);
		exit_confirm_active = false;
		Scene::Pop();
		return;
	}

	CloseExitConfirmation();
}
#endif

void Scene_GameBrowser::UpdateCommand() {
	int menu_index = command_window->GetIndex();

	switch (menu_index) {
		case GameList:
			gamelist_window->SetVisible(true);
			about_window->SetVisible(false);
			break;
		case About:
			gamelist_window->SetVisible(false);
			about_window->SetVisible(true);
			break;
		default:
			break;
	}

	if (Input::IsTriggered(Input::CANCEL)) {
#ifdef __PS2__
		OpenExitConfirmation();
#else
		Main_Data::game_system->SePlay(Main_Data::game_system->GetSystemSE(Main_Data::game_system->SFX_Cancel));
		Scene::Pop();
#endif
	} else if (Input::IsTriggered(Input::DECISION)) {

		switch (menu_index) {
			case GameList:
				if (stack.size() == 1 && !gamelist_window->HasValidEntry()) {
					return;
				}
				command_window->SetActive(false);
				command_window->SetIndex(-1);
				gamelist_window->SetActive(true);
				gamelist_window->SetIndex(old_gamelist_index);
				break;
			case About:
				break;
			case Options:
				Scene::Push(std::make_shared<Scene_Settings>());
				break;
			case Quit:
#ifdef __PS2__
				OpenExitConfirmation();
#else
				Scene::Pop();
#endif
				break;
			default:
				break;
		}
	}
}

void Scene_GameBrowser::UpdateGameListSelection() {
	if (Input::IsTriggered(Input::CANCEL)) {
		command_window->SetActive(true);
		command_window->SetIndex(0);
		gamelist_window->SetActive(false);
		old_gamelist_index = gamelist_window->GetIndex();
		gamelist_window->SetIndex(-1);
	} else if (Input::IsTriggered(Input::DECISION)) {
		load_window->SetVisible(true);
		game_loading = true;
	} else if (Input::IsTriggered(Input::DEBUG_MENU) || Input::IsTriggered(Input::SHIFT)) {
		Player::debug_flag = true;
		load_window->SetVisible(true);
		game_loading = true;
	}
}

void Scene_GameBrowser::BootGame() {
	if (stack.size() > 1 && gamelist_window->GetIndex() == 0) {
		// ".." -> Go one level up
		int index = stack.back().index;
		stack.pop_back();
		gamelist_window->Refresh(stack.back().filesystem, stack.size() > 1);
		gamelist_window->SetIndex(index);
		load_window->SetVisible(false);
		game_loading = false;
		return;
	}

	auto entry = gamelist_window->GetFilesystemEntry();

	if (!entry.fs) {
		Output::Warning("The selected file or directory cannot be opened");
		load_window->SetVisible(false);
		game_loading = false;
		return;
	}

	if (entry.type == FileFinder::ProjectType::Unknown) {
		// Fetched again for platforms where the type is not populated due to bad IO performance
		entry.type = FileFinder::GetProjectType(entry.fs);
	}

	if (entry.type > FileFinder::ProjectType::Supported) {
		// Game is using a known unsupported engine
		Main_Data::game_system->SePlay(Main_Data::game_system->GetSystemSE(Main_Data::game_system->SFX_Buzzer));
		Output::Warning(
				"{} has unsupported engine {}",
				FileFinder::GetPathAndFilename(entry.fs.GetFullPath()).second,
				FileFinder::kProjectType.tag(entry.type)
		);
		load_window->SetVisible(false);
		game_loading = false;
		return;
	}

	if (entry.type == FileFinder::ProjectType::Unknown && !FileFinder::OpenViewToEasyRpgFile(entry.fs)) {
		// Not a game: Open as directory
		load_window->SetVisible(false);
		game_loading = false;
		if (!gamelist_window->Refresh(entry.fs, true)) {
			Output::Warning("The selected file or directory cannot be opened");
			return;
		}
		stack.push_back({ entry.fs, gamelist_window->GetIndex() });
		gamelist_window->SetIndex(0);

		return;
	}

	FileFinder::SetGameFilesystem(entry.fs);
	Player::CreateGameObjects();

	game_loading = false;
	load_window->SetVisible(false);

	auto logos = Scene_Logo::LoadLogos();
	if (!logos.empty()) {
		// Delegate to Scene_Logo when a startup graphic was found
		Scene::Push(std::make_shared<Scene_Logo>(std::move(logos), 1));
		return;
	}

	Scene::PushTitleScene();
}
