#include <sourcemod>
#include <regex>
#include <tf2_stocks>
#include <halflife>
#include <SteamWorks>
#include <smjansson>
#include <socket>

#pragma newdecls required
#pragma semicolon 1

#define PLUGIN_VERSION "1.1"
#define HOLOGRAM_MODEL "models/blap/cappoint_hologram.mdl"

#define _DEBUG true
#define NO_SOCKET true
#define FALLBACK_URL "https://blapbash.broadcast.tf/api/json_totals"

public Plugin myinfo = 
{
	name = "Blap stuff",
	author = "Jim",
	description = "Server blapification",
	version = PLUGIN_VERSION,
	url = "http://steamcommunity.com/id/_NiGHTS/"
};

//Represents an active donation total linked to an entity on the map
enum DonationDisplay {
	DDParent,
	Float:DDScale,
	Float:DDPosition[3],
	Float:DDRotation[3],
	EntityType:DDType,

	//Ent references for 4 sets of digits
	DDDigits[4],
}

enum ConfigEntry {
	String:CETargetname[64], //Entity targetname
	bool:CERegex, //Whether the targetname is a regex
	bool:CEHide,
	Float:CEScale, //Digit sprite scale
	Float:CEPosition[3], //Position relative to entity center
	Float:CERotation[3], //Rotation relative to entity angles
}

enum ConfigRegex {
	Regex:CRRegex,
	String:CRConfigEntry[64],
}

enum EntityType {
	EntityType_None = 0,
	EntityType_ControlPoint = 1,
	EntityType_PayloadCart = 2,
	EntityType_Intel = 3,
	EntityType_Resupply = 4,
	EntityType_Custom = 5,
};

enum Socket {
	Handle:SSocket,
	Handle:SHeartbeatTimer,
	Handle:STimeoutTimer,
	SAttempts,
}

int gDonationTotal;
int gDigitsRequired = 6;
int gLastMilestone;

ArrayList gDuckModels;
ArrayList gDonationDisplays;

StringMap gConfigEntries;
ArrayList gConfigRegexes;

ConVar gTFDucksCvar;
ConVar gDucksCvar;
ConVar gCPsCvar;
ConVar gDonationsCvar;

Handle gFallbackTimer = INVALID_HANDLE;
Socket gSocket[Socket];

#include <blap/config>
#include <blap/socket>

public void OnPluginStart() {
	gTFDucksCvar = FindConVar("tf_player_drop_bonus_ducks");
	gDucksCvar = CreateConVar("blap_ducks_enabled", "1", "Whether blap reskinned ducks are enabled", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	gCPsCvar = CreateConVar("blap_cps_enabled", "1", "Whether blap reskinned control points are enabled", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	gDonationsCvar = CreateConVar("blap_donations_enabled", "1", "Whether blap donation total displays are enabled", FCVAR_NOTIFY, true, 0.0, true, 1.0);

	RegAdminCmd("sm_reloadblap", Command_Reloadblap, ADMFLAG_GENERIC);
	RegAdminCmd("sm_setdonationtotal", Command_SetDonationTotal, ADMFLAG_GENERIC);

	gDuckModels = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
	gDonationDisplays = new ArrayList(view_as<int>(DonationDisplay));
	gConfigEntries = new StringMap();
	gConfigRegexes = new ArrayList(view_as<int>(ConfigRegex));

	gDuckModels.PushString("models/blap/bonus_blap.mdl");
	gDuckModels.PushString("models/blap/bonus_blap_2.mdl");
	gDuckModels.PushString("models/blap/bonus_blap_3.mdl");
	gDuckModels.PushString("models/blap/bonus_blap_4.mdl");

	gDonationsCvar.AddChangeHook(OnDonationsCvarChanged);

	HookEvent("teamplay_round_start", OnRoundStart);
}

public void OnPluginEnd() {
	DestroyDonationDisplays();
}

public void OnMapStart() {
	AutoExecConfig(true);

	gDonationDisplays.Clear();
	gConfigEntries.Clear();
	gConfigRegexes.Clear();

	for(int i = 0; i < gDuckModels.Length; i++) {
		char model[PLATFORM_MAX_PATH];

		gDuckModels.GetString(i, model, sizeof(model));
		PrecacheModel(model);
		AddFileToDownloadsTable(model);
	}

	PrecacheModel("models/items/currencypack_large.mdl");
	PrecacheModel(HOLOGRAM_MODEL);
	AddFileToDownloadsTable(HOLOGRAM_MODEL);

	PrecacheGeneric("materials/blap/numbers-2019.vmt");
	PrecacheGeneric("materials/blap/numbers-2019.vtf");
	PrecacheGeneric("materials/blap/numbers-2019-comma.vmt");
	PrecacheGeneric("materials/blap/numbers-2019-comma.vtf");

	AddFileToDownloadsTable("materials/blap/numbers-2019.vmt");
	AddFileToDownloadsTable("materials/blap/numbers-2019.vtf");
	AddFileToDownloadsTable("materials/blap/numbers-2019-comma.vmt");
	AddFileToDownloadsTable("materials/blap/numbers-2019-comma.vtf");

	AddFileToDownloadsTable("materials/models/blap/cappoint_logo_blue.vtf");
	AddFileToDownloadsTable("materials/models/blap/cappoint_logo_red.vtf");
	AddFileToDownloadsTable("materials/models/effects/blap_cappoint_logo_blue.vmt");
	AddFileToDownloadsTable("materials/models/effects/blap_cappoint_logo_blue_dark.vmt");
	AddFileToDownloadsTable("materials/models/effects/blap_cappoint_logo_red.vmt");
	AddFileToDownloadsTable("materials/models/effects/blap_cappoint_logo_red_dark.vmt");
	
	AddFileToDownloadsTable("models/blap/bonus_blap.dx80.vtx");
	AddFileToDownloadsTable("models/blap/bonus_blap.dx90.vtx");
	AddFileToDownloadsTable("models/blap/bonus_blap.sw.vtx");
	AddFileToDownloadsTable("models/blap/bonus_blap.vvd");
	AddFileToDownloadsTable("models/blap/bonus_blap_2.dx80.vtx");
	AddFileToDownloadsTable("models/blap/bonus_blap_2.dx90.vtx");
	AddFileToDownloadsTable("models/blap/bonus_blap_2.sw.vtx");
	AddFileToDownloadsTable("models/blap/bonus_blap_2.vvd");
	AddFileToDownloadsTable("models/blap/bonus_blap_3.dx80.vtx");
	AddFileToDownloadsTable("models/blap/bonus_blap_3.dx90.vtx");
	AddFileToDownloadsTable("models/blap/bonus_blap_3.sw.vtx");
	AddFileToDownloadsTable("models/blap/bonus_blap_3.vvd");
	AddFileToDownloadsTable("models/blap/bonus_blap_4.dx80.vtx");
	AddFileToDownloadsTable("models/blap/bonus_blap_4.dx90.vtx");
	AddFileToDownloadsTable("models/blap/bonus_blap_4.sw.vtx");
	AddFileToDownloadsTable("models/blap/bonus_blap_4.vvd");
	AddFileToDownloadsTable("models/blap/cappoint_hologram.dx80.vtx");
	AddFileToDownloadsTable("models/blap/cappoint_hologram.dx90.vtx");
	AddFileToDownloadsTable("models/blap/cappoint_hologram.sw.vtx");
	AddFileToDownloadsTable("models/blap/cappoint_hologram.vvd");

	for(int i = 1; i <= 29; i++) {
		char sound[PLATFORM_MAX_PATH];
		Format(sound, sizeof(sound), "misc/happy_birthday_tf_%02i.wav", i);
		PrecacheSound(sound);
	}

	LoadMapConfig();
	RequestFrame(FindMapEntities);
}

public void OnConfigsExecuted() {
	if(gTFDucksCvar != null && gDucksCvar.BoolValue) {
		gTFDucksCvar.SetFloat(1.0);
	}

	if(gDonationsCvar.BoolValue) {
		InitDonationSocket();
	} 
}

public Action OnRoundStart(Event event, const char[] name, bool dontBroadcast) {
	bool full = event.GetBool("full_reset");

	if(full) {
		OnMapStart();
	}
}
	
public void OnEntityCreated(int entity, const char[] classname) {
	if(!strcmp(classname, "tf_bonus_duck_pickup", false) && gDucksCvar.BoolValue) {
		RequestFrame(SetDuckModel, EntIndexToEntRef(entity));
	}
}

public void OnDonationsCvarChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
	if(!convar.BoolValue) {
		DestroyDonationDisplays();

		if(gFallbackTimer != INVALID_HANDLE) {
			KillTimer(gFallbackTimer);
			gFallbackTimer = INVALID_HANDLE;
		}
	} else {
		RequestFrame(FindMapEntities);
		InitDonationSocket();
	}
}

public Action Command_Reloadblap(int client, int args) {
	DestroyDonationDisplays();
	LoadMapConfig();
	RequestFrame(FindMapEntities);
	ReplyToCommand(client, "[SM] Config reloaded");

	return Plugin_Handled;
}

public Action Command_SetDonationTotal(int client, int args) {
	char totalArg[16];
	int total;

	GetCmdArg(1, totalArg, sizeof(totalArg));
	total = StringToInt(totalArg);

	gDonationTotal = total;
	UpdateDonationDisplays();
	ReplyToCommand(client, "[SM] Total updated");

	return Plugin_Handled;
}

public void SetDuckModel(any entity) {
	entity = EntRefToEntIndex(entity);

	if(entity != INVALID_ENT_REFERENCE) {
		int index = GetRandomInt(0, gDuckModels.Length -1);
		char model[PLATFORM_MAX_PATH];

		gDuckModels.GetString(index, model, sizeof(model));

		SetEntityModel(entity, model);
		SetEntPropFloat(entity, Prop_Data, "m_flModelScale", 1.0);
	}
}

//Loops over map entities and creates donation displays on appropriate ones
void FindMapEntities(any unused) {
	ArrayList payloads = new ArrayList(32);
	ArrayList cabinets = new ArrayList();
	int index = -1;

	//Find payload trains
	while((index = FindEntityByClassname(index, "team_train_watcher")) != -1) {
		char name[32];
		GetEntPropString(index, Prop_Data, "m_iszTrain", name, sizeof(name));

		if(strlen(name)) {
			payloads.PushString(name);
		}
	}

	//Find resupply cabinet props
	while((index = FindEntityByClassname(index, "func_regenerate")) != -1) {
		cabinets.Push(GetEntPropEnt(index, Prop_Data, "m_hAssociatedModel"));
	}

	for(int i = MaxClients; i < GetMaxEntities(); i++) {
		if(!IsValidEntity(i)) {
			continue;
		}
	
		char name[32];
		char class[32];
		GetEntPropString(i, Prop_Data, "m_iName", name, sizeof(name));
		GetEntityClassname(i, class, 32);
		
		ConfigEntry configEntry[ConfigEntry];
		DonationDisplay donationDisplay[DonationDisplay];

		donationDisplay[DDParent] = i;

		//Reskin and setup display for control points
		if(StrEqual(class, "team_control_point", false)) {
			donationDisplay[DDType] = EntityType_ControlPoint;

			if(gCPsCvar.BoolValue) {
				PrepareControlPoint(i);
			}
		}

		//Reskin and setup display for intel
		if(StrEqual(class, "item_teamflag", false)) {
			donationDisplay[DDType] = EntityType_Intel;
			PrepareFlag(i);
		}

		//Payloads
		if(payloads.FindString(name) > -1) {
			donationDisplay[DDType] = EntityType_PayloadCart;
		}

		//Resupply cabinets
		if(cabinets.FindValue(i) > -1) {
			donationDisplay[DDType] = EntityType_Resupply;			
		}

		//Check if entity has a config entry and use if so
		if(gConfigEntries.GetArray(name, configEntry[0], view_as<int>(ConfigEntry))) {
			#if defined _DEBUG
				PrintToServer("Entity %s has config entry", name);
			#endif

			donationDisplay[DDScale] = configEntry[CEScale];
			
			donationDisplay[DDPosition][0] = configEntry[CEPosition][0];
			donationDisplay[DDPosition][1] = configEntry[CEPosition][1];
			donationDisplay[DDPosition][2] = configEntry[CEPosition][2];

			donationDisplay[DDRotation][0] = configEntry[CERotation][0];
			donationDisplay[DDRotation][1] = configEntry[CERotation][1];
			donationDisplay[DDRotation][2] = configEntry[CERotation][2];

			if(donationDisplay[DDType] == EntityType_None) {
				donationDisplay[DDType] = EntityType_Custom;
			}
		}

		//Check for regex matches and use it's config entry if matching
		if(strlen(name)) {
			for(int j = 0; j < gConfigRegexes.Length; j++) {
				ConfigRegex configRegex[ConfigRegex];
				gConfigRegexes.GetArray(j, configRegex[0], view_as<int>(ConfigRegex));

				if(configRegex[CRRegex].Match(name) > 0) {
					#if defined _DEBUG
						PrintToServer("Entity %s matched config regex", name);
					#endif

					gConfigEntries.GetArray(configRegex[CRConfigEntry], configEntry[0], view_as<int>(ConfigEntry));

					donationDisplay[DDScale] = configEntry[CEScale];
					donationDisplay[DDType] = EntityType_Custom;
					
					donationDisplay[DDPosition][0] = configEntry[CEPosition][0];
					donationDisplay[DDPosition][1] = configEntry[CEPosition][1];
					donationDisplay[DDPosition][2] = configEntry[CEPosition][2];

					donationDisplay[DDRotation][0] = configEntry[CERotation][0];
					donationDisplay[DDRotation][1] = configEntry[CERotation][1];
					donationDisplay[DDRotation][2] = configEntry[CERotation][2];
				}
			}
		}

		if(configEntry[CEHide]) {
			#if defined _DEBUG
				PrintToServer("Donation display for %s hidden", name);
			#endif
			
			continue;
		}

		//If entity should have a donation display create it
		if(donationDisplay[DDType] != EntityType_None && gDonationsCvar.BoolValue) {
			#if defined _DEBUG
				PrintToServer("Entity %s has donation display of type %d", name, donationDisplay[DDType]);
			#endif

			SetupDonationDisplay(i, donationDisplay);
		}
	}

	UpdateDonationDisplays();
}

void SetupDonationDisplay(int entity, DonationDisplay donationDisplay[DonationDisplay]) {
	if(!donationDisplay[DDParent]) {
		donationDisplay[DDParent] = entity;
	}

	if(!donationDisplay[DDScale]) {
		donationDisplay[DDScale] = 1.0;
	}

	donationDisplay[DDDigits][0] = CreateDonationDigit(false);
	donationDisplay[DDDigits][1] = CreateDonationDigit(true);
	donationDisplay[DDDigits][2] = CreateDonationDigit(false);
	donationDisplay[DDDigits][3] = CreateDonationDigit(false, true);

	int index = gDonationDisplays.PushArray(donationDisplay[0]);

	PositionDonationDisplay(donationDisplay);
	ParentDonationDisplay(donationDisplay, index);
}

void PositionDonationDisplay(DonationDisplay donationDisplay[DonationDisplay]) {
	float position[3]; //Entity origin
	float angles[3]; //Entity rotation

	float offset[3]; //Offset from entity origin to use for positioning sprite
	float rotationOffset[3]; 
	float displayPosition[3]; //Final sprite position

	float firstDigitOffset = GetFirstDigitOffset(donationDisplay[DDType] == EntityType_Resupply) * donationDisplay[DDScale]; //Initial offset before first digit to roughly "center" the display around the desired position
	float digitSpacing = 32.0 * donationDisplay[DDScale]; //Spacing between digits

	char scale[10];

	GetEntPropVector(donationDisplay[DDParent], Prop_Data, "m_vecAbsOrigin", position);
	GetEntPropVector(donationDisplay[DDParent], Prop_Send, "m_angRotation", angles);

	switch(donationDisplay[DDType]) {
		case EntityType_Resupply :
		{
			rotationOffset[1] += 180.0;
			rotationOffset[2] += 90.0;
			offset[2] += 52.0;
			offset[1] -= 34.0;
			offset[0] += 14.0;
		}

		//Position above control point hologram
		case EntityType_ControlPoint :
		{
			rotationOffset[1] += 90.0;
			offset[2] += 190.0;
		}

		//Position above control point hologram
		case EntityType_PayloadCart :
		{
			rotationOffset[1] += 90.0;
			offset[2] += 50.0;
			offset[0] += 10.0;
		}
		
		//Position above control point hologram
		case EntityType_Intel :
			offset[2] += 30.0;
	}

	Format(scale, sizeof(scale), "%00.2f", 0.25 * donationDisplay[DDScale]);

	//Add position offset from config
	offset[0] += donationDisplay[DDPosition][0];
	offset[1] += donationDisplay[DDPosition][1];
	offset[2] += donationDisplay[DDPosition][2];

	//Add rotation offset from config
	rotationOffset[0] += donationDisplay[DDRotation][0];
	rotationOffset[1] += donationDisplay[DDRotation][1];
	rotationOffset[2] += donationDisplay[DDRotation][2];

	//Angle vectors
	float fwd[3];
	float right[3];
	float up[3];
	
	GetAngleVectors(angles, fwd, right, up);

	ScaleVector(fwd, offset[0]);
	ScaleVector(right, offset[1]);
	ScaleVector(up, offset[2]);

	AddVectors(position, fwd, displayPosition);
	AddVectors(displayPosition, right, displayPosition);
	AddVectors(displayPosition, up, displayPosition);

	//Apply rotation offset
	AddVectors(angles, rotationOffset, angles);
	GetAngleVectors(angles, fwd, right, up);

	//Add first digit offset for centering
	ScaleVector(right, firstDigitOffset);
	AddVectors(displayPosition, right, displayPosition);

	//Position each digit
	for(int i = 0; i < 4; i++) {		
		if(i) {
			NormalizeVector(right, right); //Reset distance
			ScaleVector(right, digitSpacing);
			SubtractVectors(displayPosition, right, displayPosition);
		}

		DispatchKeyValue(donationDisplay[DDDigits][i], "scale", scale);
		TeleportEntity(donationDisplay[DDDigits][i], displayPosition, angles, NULL_VECTOR);
	}
}

void ParentDonationDisplay(DonationDisplay donationDisplay[DonationDisplay], int index) {
	for(int i = 0; i < 4; i++) {
		SetVariantString("!activator");
		AcceptEntityInput(donationDisplay[DDDigits][i], "SetParent", donationDisplay[DDParent], donationDisplay[DDParent]);
	}

	if(donationDisplay[DDType] == EntityType_ControlPoint) {
		RequestFrame(ParentControlPointDonationDisplay, index);
	}
}

void ParentControlPointDonationDisplay(any index) {
	DonationDisplay donationDisplay[DonationDisplay];

	gDonationDisplays.GetArray(index, donationDisplay[0], view_as<int>(DonationDisplay));

	for(int i = 0; i < 4; i++) {
		SetVariantString("donations");
		AcceptEntityInput(donationDisplay[DDDigits][i], "SetParentAttachmentMaintainOffset");
	}
}

void UnparentDonationDisplay(DonationDisplay donationDisplay[DonationDisplay]) {
	for(int i = 0; i < 4; i++) {
		AcceptEntityInput(donationDisplay[DDDigits][i], "ClearParent", donationDisplay[DDParent], donationDisplay[DDParent]);
	}
}

//Get first digit offset to "center" donation display, based on number of used digits
float GetFirstDigitOffset(bool resupply = false) {
	if(resupply) {
		return 32.0;
	}

	return (gDigitsRequired - 2) * 8.0;
}

void DestroyDonationDisplays() {
	for(int i = 0; i < gDonationDisplays.Length; i++) {
		DonationDisplay entity[DonationDisplay];

		gDonationDisplays.GetArray(i, entity[0], view_as<int>(DonationDisplay));

		for(int j = 0; j < 4; j++) {
			if(IsValidEntity(entity[DDDigits][j])) {
				AcceptEntityInput(entity[DDDigits][j], "Kill");
			}
		}
	}

	gDonationDisplays.Clear();
}

void PrepareControlPoint(int entity) {
	entity = EntRefToEntIndex(entity);

	if(entity != INVALID_ENT_REFERENCE) {
		DispatchKeyValue(entity, "team_model_3", HOLOGRAM_MODEL);
		DispatchKeyValue(entity, "team_model_2", HOLOGRAM_MODEL);
		DispatchKeyValue(entity, "team_model_0", HOLOGRAM_MODEL);
		SetEntityModel(entity, HOLOGRAM_MODEL);
	}
}

void PrepareFlag(int entity) {
	SetEntityModel(entity, "models/items/currencypack_large.mdl");

	float origin[3];

	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", origin);
	origin[2] -= 10.0; //Move flag down to account for higher up model
	TeleportEntity(entity, origin, NULL_VECTOR, NULL_VECTOR);
}

int CreateDonationDigit(bool comma, bool startBlank = false) {
	int entity = CreateEntityByName("env_sprite_oriented");

	if(comma) {
		DispatchKeyValue(entity, "model", "blap/numbers-2019-comma.vmt");
	} else {
		DispatchKeyValue(entity, "model", "blap/numbers-2019.vmt");
	}

	DispatchKeyValue(entity, "framerate", "0");
	DispatchKeyValue(entity, "spawnflags", "1");
	DispatchKeyValue(entity, "scale", "0.25");
	
	// SetEntityRenderMode(entity, RENDER_NORMAL);
	SetEntityRenderMode(entity, RENDER_TRANSALPHAADD);

	DispatchSpawn(entity);
	AcceptEntityInput(entity, "ShowSprite");
	// SetVariantFloat(189.0);
	// AcceptEntityInput(entity, "ColorRedValue");
	// SetVariantFloat(217.0);
	// AcceptEntityInput(entity, "ColorGreenValue");
	// SetVariantFloat(55.0);
	// AcceptEntityInput(entity, "ColorBlueValue");

	if(startBlank) {
		SetEntPropFloat(entity, Prop_Data, "m_flFrame", 110.0);
		SetEntPropFloat(entity, Prop_Send, "m_flFrame", 110.0);
	} else {
		SetEntPropFloat(entity, Prop_Data, "m_flFrame", 114.0);
		SetEntPropFloat(entity, Prop_Send, "m_flFrame", 114.0);
	}

	SetEntPropFloat(entity, Prop_Send, "m_flGlowProxySize", 64.0);
	SetEntPropFloat(entity, Prop_Data, "m_flGlowProxySize", 64.0);
	SetEntPropFloat(entity, Prop_Send, "m_flHDRColorScale", 1.0);
	SetEntPropFloat(entity, Prop_Data, "m_flHDRColorScale", 1.0);

	return EntIndexToEntRef(entity);
}

void ScheduleDonationRequest(bool immediate = false) {
	if(gFallbackTimer != INVALID_HANDLE) {
		KillTimer(gFallbackTimer);
		gFallbackTimer = INVALID_HANDLE;
	}

	if(!gDonationsCvar.BoolValue) {
		return;
	}

	#if defined _DEBUG
		LogMessage("HTTP: Scheduling donation request");
	#endif

	gFallbackTimer = CreateTimer(immediate ? 0.1 : 5.0, MakeDonationRequest);
}

public Action MakeDonationRequest(Handle timer, any data) {
	#if defined _DEBUG
		LogMessage("HTTP: Making donation request");
	#endif

	Handle request = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, FALLBACK_URL);

	SteamWorks_SetHTTPCallbacks(request, OnTotalRequestCompleted);

	if(!SteamWorks_SendHTTPRequest(request)) {
		LogError("HTTP: Donation total HTTP request failed");
		ScheduleDonationRequest();
	}

	gFallbackTimer = INVALID_HANDLE;
	return Plugin_Stop;
}

public int OnTotalRequestCompleted(Handle request, bool failure, bool successful, EHTTPStatusCode eStatusCode) {
	ScheduleDonationRequest();

	if(!successful || eStatusCode != k_EHTTPStatusCode200OK) {
		LogError("Donation total HTTP request failed %d");

	} else {
		int size;

		SteamWorks_GetHTTPResponseBodySize(request, size);

		char[] sBody = new char[size];

		SteamWorks_GetHTTPResponseBodyData(request, sBody, size);

		int newTotal = ParseTotalJsonResponse(sBody);

		if(newTotal > 0 && newTotal != gDonationTotal) {
			#if defined _DEBUG
			LogMessage("HTTP: New total received %d", newTotal);
			#endif

			gDonationTotal = newTotal;
			UpdateDonationDisplays();
		}
	}

	CloseHandle(request);
}

public int ParseTotalJsonResponse(const char[] json) {
	Handle parsed = json_load(json);
	char total[16];

	if(parsed == INVALID_HANDLE) {
		LogError("HTTP: Invalid json (failed to parse)");

		return -1;
	}


	if(json_object_get_string(parsed, "grand_total", total, sizeof(total)) == -1) {
		LogError("HTTP: Invalid json (invalid total)");

		return -1;
	}

	ReplaceString(total, sizeof(total), "$", "");
	ReplaceString(total, sizeof(total), ",", "");

	CloseHandle(parsed);
	return RoundToFloor(StringToFloat(total));
}

public int UpdateDonationDisplays() {
	float digits[4] = { 110.0, 110.0, 110.0, 110.0 };
	int divisor = 1;
	int digitsRequired = 0;

	bool milestone = false;
	bool reposition = false;

	if(gDonationTotal) {
		//Divide total into groups of 2 digits and work out which sprite frame to display for each
		for(int i = 0; i < 4; i++) {
			float amount = float((gDonationTotal / divisor) % 100);

			if(!amount && gDonationTotal < divisor) { //Total is below the range of this digit, display $ sign and skip the rest
				digitsRequired += 1;
				digits[i] = 112.0; //112th frame is $ on its own
				break;
			} else if((amount && amount < 10.0) && (gDonationTotal < (divisor * 100))) { //Total is within range but only uses one of the 2 numbers, display with $ sign
				digitsRequired += 2;
				digits[i] = amount + 100.0; //Frames 100 - 109 are single numbers with dollar signs
				break;
			} else { //Total uses both numbers within this digit, display normally
				digitsRequired += 2;
				digits[i] = amount;
			}

			divisor *= 100;
		}
	} else {
		digitsRequired = 6;
		digits[0] = 114.0;
		digits[1] = 114.0;
		digits[2] = 114.0;
	}

	if((gDonationTotal - (gDonationTotal % 1000)) > gLastMilestone) {
		gLastMilestone = (gDonationTotal - (gDonationTotal % 1000));
		milestone = true;
	}

	//Number of required digits for display has changed
	if(digitsRequired != gDigitsRequired) {
		gDigitsRequired = digitsRequired;
		reposition = true;
	}

	for(int i = 0; i < gDonationDisplays.Length; i++) {
		DonationDisplay entity[DonationDisplay];

		gDonationDisplays.GetArray(i, entity[0], view_as<int>(DonationDisplay));

		//If display needs repositioning, unparent then reparent to avoid weirdness
		if(reposition && entity[DDType] != EntityType_Resupply) {
			UnparentDonationDisplay(entity);
			PositionDonationDisplay(entity);
			ParentDonationDisplay(entity, i);
		}

		for(int j = 0; j < 4; j++) {
			SetEntPropFloat(entity[DDDigits][j], Prop_Send, "m_flFrame", digits[j]);
		}

		if(milestone) {
			char sound[PLATFORM_MAX_PATH];

			Format(sound, sizeof(sound), "misc/happy_birthday_tf_%02i.wav", GetRandomInt(1, 29));

			EmitSoundToAll(sound, entity[DDDigits][2]);
			TE_Particle("bday_confetti", NULL_VECTOR, NULL_VECTOR, NULL_VECTOR, entity[DDDigits][1]);
		}
		
		TE_Particle("repair_claw_heal_blue", NULL_VECTOR, NULL_VECTOR, NULL_VECTOR, entity[DDDigits][2]);
	}
}

void TE_Particle(char[] Name, float origin[3]=NULL_VECTOR, float start[3]=NULL_VECTOR, float angles[3]=NULL_VECTOR, int entindex=-1, int attachtype=-1, int attachpoint=-1, bool resetParticles=true, float delay=0.0) {
    // find string table
    int tblidx = FindStringTable("ParticleEffectNames");

    if(tblidx == INVALID_STRING_TABLE) {
        LogError("Could not find string table: ParticleEffectNames");
        return;
    }
    
    // find particle index
    char tmp[256];
    
    int count = GetStringTableNumStrings(tblidx);
    int stridx = INVALID_STRING_INDEX;
    int i;

    for(i = 0; i < count; i++) {
        ReadStringTable(tblidx, i, tmp, sizeof(tmp));
        
        if(StrEqual(tmp, Name, false)) {
            stridx = i;
            break;
        }
    }

    if(stridx == INVALID_STRING_INDEX) {
        LogError("Could not find particle: %s", Name);
        return;
    }
    
    TE_Start("TFParticleEffect");
    TE_WriteFloat("m_vecOrigin[0]", origin[0]);
    TE_WriteFloat("m_vecOrigin[1]", origin[1]);
    TE_WriteFloat("m_vecOrigin[2]", origin[2]);
    TE_WriteFloat("m_vecStart[0]", start[0]);
    TE_WriteFloat("m_vecStart[1]", start[1]);
    TE_WriteFloat("m_vecStart[2]", start[2]);
    TE_WriteVector("m_vecAngles", angles);
    TE_WriteNum("m_iParticleSystemIndex", stridx);
   
    if(entindex != -1) {
        TE_WriteNum("entindex", entindex);
    }

    if(attachtype!=-1) {
        TE_WriteNum("m_iAttachType", attachtype);
    }

    if(attachpoint!=-1) {
        TE_WriteNum("m_iAttachmentPointIndex", attachpoint);
    }

    TE_WriteNum("m_bResetParticles", resetParticles ? 1 : 0);    
    TE_SendToAll(delay);
}
