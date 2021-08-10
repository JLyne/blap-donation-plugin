
stock bool LoadMapConfig() {
	char map[50];
	char configPath[PLATFORM_MAX_PATH];
	KeyValues config = new KeyValues("blap");
	bool opened;

	GetCurrentMap(map, sizeof(map));

	BuildPath(Path_SM, configPath, sizeof(configPath), "configs/blap.cfg");

	opened = config.ImportFromFile(configPath);

	if(!opened) {
		//SetFailState("Failed to load config file addons/sourcemod/configs/blap.cfg");

		return false;
	}

	ReplaceString(map, sizeof(map), "workshop/", "");

	#if defined _DEBUG
	LogMessage("Checking for config entry for map: %s", map);
	#endif

	if(config.JumpToKey(map, false)) {
		config.GotoFirstSubKey(false);
		ParseMapConfig(config);
	} else {
		return false;
	}

	return true;
}

stock void ParseMapConfig(KeyValues kv) {
	do {
		char keyName[64];

		kv.GetSectionName(keyName, sizeof(keyName));

		ConfigEntry configEntry;

		kv.GotoFirstSubKey(false);
		ParseEntityConfig(kv, configEntry);
		kv.GoBack();

		strcopy(configEntry.targetname, sizeof(configEntry.targetname), keyName);

		//If entry is a regex then save as ConfigRegex
		if(configEntry.regex) {
			RegexError errorType;
			char error[64];
			Regex regex = new Regex(keyName, 0, error, sizeof(error), errorType);

			if(errorType != REGEX_ERROR_NONE) {
				LogError("Config: Error in regex '%s': %s", keyName, error);
				continue;
			}

			ConfigRegex configRegex;
			configRegex.regex = regex;
			strcopy(configRegex.configEntry, sizeof(configRegex.configEntry), keyName);

			gConfigRegexes.PushArray(configRegex);
		}

		gConfigEntries.SetArray(keyName, configEntry, sizeof(ConfigEntry), true);
	} while(kv.GotoNextKey(false));
}

stock void ParseEntityConfig(KeyValues kv, ConfigEntry configEntry) {
	do {
		char keyName[50];

		kv.GetSectionName(keyName, sizeof(keyName));

		if(StrEqual(keyName, "hide", false)) {
			configEntry.hide = !!kv.GetNum(NULL_STRING, 1);
			continue;
		}

		if(StrEqual(keyName, "noprops", false)) {
			configEntry.noProps = !!kv.GetNum(NULL_STRING, 1);
			continue;
		}

		if(StrEqual(keyName, "regex", false)) {
			configEntry.regex = !!kv.GetNum(NULL_STRING, 1);
			continue;
		}

		if(StrEqual(keyName, "scale", false)) {
			configEntry.scale = kv.GetFloat(NULL_STRING, 1.0);
			continue;
		}

		if(StrEqual(keyName, "position", false)) {
			float position[3];

			kv.GetVector(NULL_STRING, position, NULL_VECTOR);

			configEntry.position[0] = position[0];
			configEntry.position[1] = position[1];
			configEntry.position[2] = position[2];

			continue;
		}

		if(StrEqual(keyName, "rotation", false)) {
			float rotation[3];

			kv.GetVector(NULL_STRING, rotation, NULL_VECTOR);

			configEntry.rotation[0] = rotation[0];
			configEntry.rotation[1] = rotation[1];
			configEntry.rotation[2] = rotation[2];

			continue;
		}
	} while(kv.GotoNextKey(false));
}
