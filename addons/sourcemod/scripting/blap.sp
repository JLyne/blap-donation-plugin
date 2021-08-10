#include <sourcemod>
#include <regex>
#include <tf2_stocks>
#include <SteamWorks>
#include <smjansson>
#include <socket>
#include <sdktools>
#include <sdkhooks>

#pragma newdecls required
#pragma semicolon 1

#define PLUGIN_VERSION "1.0"
#define HOLOGRAM_MODEL "models/blap19/cappoint_hologram.mdl"
#define COINS_MODEL "models/blap19/coins/coins.mdl"
#define NOTES_MODEL "models/blap19/notes/notes.mdl"
#define DUCK_PICKUP_SND "ui/itemcrate_smash_rare.wav"
#define DUCK_PICKUP_PARTICLE "bday_confetti_colors"

#define NO_SOCKET true
#define FALLBACK_URL "https://donate.blapature.org/api/json_totals"

public Plugin myinfo = 
{
	name = "Blap 19 stuff",
	author = "Jim | 42 | Kenzzer",
	description = "Ingame donation totals and reskinning for blap summer jam 2019",
	version = PLUGIN_VERSION,
	url = "http://steamcommunity.com/id/_NiGHTS/"
};

char gDuckModels[][] = {
	"models/blap19/ducks/bonus_blap.mdl",
	"models/blap19/ducks/bonus_blap_2.mdl",
	"models/blap19/ducks/bonus_blap_3.mdl",
	"models/blap19/ducks/bonus_blap_4.mdl"
};

int gDuckModelIndexes[sizeof(gDuckModels)];

//Represents an active donation total linked to an entity on the map
enum struct DonationDisplay {
	int parent;
	float scale;
	bool noProps;
	float position[3];
	float rotation[3];
	EntityType type;

	//Ent references for 4 sets of digits
	int digits[4];
}

enum struct ConfigEntry {
	char targetname[64]; //Entity targetname
	bool regex; //Whether the targetname is a regex
	bool hide; //Whether to prevent creation of default donation displays
	bool noProps;//Whether to suppress prop spawns
	float scale; //Digit sprite scale
	float position[3]; //Position relative to entity center
	float rotation[3]; //Rotation relative to entity angles
}

enum struct ConfigRegex {
	Regex regex;
	char configEntry[64];
}

enum EntityType {
	EntityType_None = 0,
	EntityType_ControlPoint = 1,
	EntityType_PayloadCart = 2,
	EntityType_Intel = 3,
	EntityType_Resupply = 4,
	EntityType_Custom = 5,
	EntityType_Tank = 7
};

enum MilestoneType {
	MilestoneType_None = 0,
	MilestoneType_1k = 1, //x000 total reached
	MilestoneType_25 = 2, //>=$25 donated at once
	MilestoneType_50 = 3, //>=$50 donated at once
	MilestoneType_100 = 4, //>=$100 donated at once
}

enum PropSpawnType {
	PropSpawnType_None = 0,
	PropSpawnType_Coins = 1,
	PropSpawnType_Notes = 2,
}

enum struct TrackerSocket {
	Handle socket;
	Handle heartbeatTimer;
	Handle timeoutTimer;
	int attempts;
}

int gDonationTotal;
int gPreviousDonationTotal;
int gDigitsRequired = 6;
int gLastMilestone;

bool gbPlayingMvM;

ArrayList gDonationDisplays;

StringMap gConfigEntries;
ArrayList gConfigRegexes;

//Cvars
ConVar gDucksCvar;
ConVar gCPsCvar;
ConVar gDonationsCvar;
ConVar gSoundsCvar;
ConVar gPropsCvar;

Handle gFallbackTimer = INVALID_HANDLE;
TrackerSocket gSocket;

#include <blap/precache>
#include <blap/config>
#include <blap/socket>
#include <blap/http>

public void OnPluginStart() {
	gDucksCvar = CreateConVar("blap_ducks_enabled", "1", "Whether blap reskinned ducks are enabled", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	gCPsCvar = CreateConVar("blap_cps_enabled", "1", "Whether blap reskinned control points are enabled", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	gSoundsCvar = CreateConVar("blap_sounds_enabled", "1", "Whether donation displays can make sounds", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	gPropsCvar = CreateConVar("blap_props_enabled", "1", "Whether donation displays can spawn props", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	gDonationsCvar = CreateConVar("blap_donations_enabled", "1", "Whether blap donation total displays are enabled", FCVAR_NOTIFY, true, 0.0, true, 1.0);

	RegAdminCmd("sm_reloadblap", Command_Reloadblap, ADMFLAG_GENERIC);
	RegAdminCmd("sm_setdonationtotal", Command_SetDonationTotal, ADMFLAG_GENERIC);

	gDonationDisplays = new ArrayList(sizeof(DonationDisplay));
	gConfigEntries = new StringMap();
	gConfigRegexes = new ArrayList(sizeof(ConfigRegex));

	gDonationsCvar.AddChangeHook(OnDonationsCvarChanged);

	HookEvent("teamplay_round_start", OnRoundStart);
	HookEvent("player_death", OnPlayerDeath);
	
	HookEvent("mvm_wave_complete", OnWaveUpdate);
	HookEvent("mvm_begin_wave", OnWaveUpdate);
}

public void OnPluginEnd() {
	DestroyDonationDisplays();
}

public void OnMapStart() {
	AutoExecConfig(true);

	gDonationDisplays.Clear();
	gConfigEntries.Clear();
	gConfigRegexes.Clear();

	PrecacheAssets();
	LoadMapConfig();
	RequestFrame(FindMapEntities);
	
	gbPlayingMvM = view_as<bool>(GameRules_GetProp("m_bPlayingMannVsMachine"));
}

public void OnConfigsExecuted() {
	if(gDonationsCvar.BoolValue) {
		InitDonationSocket();
	} 
}

public void OnEntityCreated(int iEntity, const char[] sClassName) {
	if(gbPlayingMvM) {
		if(gDucksCvar.BoolValue && strncmp(sClassName, "item_currencypack", 17) == 0) {
			RequestFrame(Frame_UpdateMoney, EntIndexToEntRef(iEntity));
		} else if(strcmp(sClassName, "tank_boss", false) == 0) {
			RequestFrame(Frame_TankSpawn, EntIndexToEntRef(iEntity));
		}
	}
}

public void OnEntityDestroyed(int iEntity) {
	if(!gbPlayingMvM) {
		return; // Since this only concerns the tank entity atm. We can save some performance for PvP
	}
	
	for(int i = gDonationDisplays.Length-1; i >= 0; i--) {
		DonationDisplay entity;
		gDonationDisplays.GetArray(i, entity, sizeof(DonationDisplay));
		
		if(entity.parent != iEntity) {
			continue;
		}

		for(int j = 0; j < 4; j++) {
			if(IsValidEntity(entity.digits[j])) {
				AcceptEntityInput(entity.digits[j], "Kill");
			}
		}
		
		gDonationDisplays.Erase(i);

		break;
	}
}

public Action OnRoundStart(Event event, const char[] name, bool dontBroadcast) {
	bool full = event.GetBool("full_reset");

	if(full) {
		OnMapStart();
	}
}

public Action OnWaveUpdate(Event event, const char[] name, bool dontBroadcast) {
	UpdateDonationDisplays();
}

public Action OnPlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	int iClient = GetClientOfUserId(event.GetInt("userid"));
	if(!iClient || gbPlayingMvM || !gDucksCvar.BoolValue) {
		return Plugin_Continue;
	}
	
	if(GetEntityCount() > 1900) {
		return Plugin_Continue;
	} 

	float vecPos[3], vecVel[3];
	GetEntPropVector(iClient, Prop_Send, "m_vecOrigin", vecPos);
	vecPos[2] += 20.0;
	
	for(int i = GetRandomInt(6,3); i > 0; i--) {
		int iKey = CreateEntityByName("tf_halloween_pickup");
		
		int iModelIndex = GetRandomInt(0, sizeof(gDuckModels)-1);
		DispatchKeyValue(iKey, "powerup_model", gDuckModels[iModelIndex]);
		DispatchKeyValue(iKey, "modelscale", "1.0");
		DispatchKeyValue(iKey, "pickup_sound", "vo/null.mp3");
		DispatchKeyValue(iKey, "pickup_particle", DUCK_PICKUP_PARTICLE);
		
		TeleportEntity(iKey, vecPos, NULL_VECTOR, NULL_VECTOR);
		DispatchSpawn(iKey);
		ActivateEntity(iKey);
		
		SetEntityMoveType(iKey, MOVETYPE_FLYGRAVITY);
		SetEntProp(iKey, Prop_Data, "m_iEFlags", (1<<23)|(1<<22)|(2<<18));
		for (int j = 0; j < 4; j++) SetEntProp(iKey, Prop_Send, "m_nModelIndexOverrides", gDuckModelIndexes[iModelIndex], _, j);
		
		vecVel[0] = GetRandomFloat(-100.0, 100.0);
		vecVel[1] = GetRandomFloat(-100.0, 100.0);
		vecVel[2] = GetRandomFloat(300.0, 400.0);
		TeleportEntity(iKey, NULL_VECTOR, NULL_VECTOR, vecVel);
		SetEntProp(iKey, Prop_Data, "m_MoveCollide", 1);
		
		SDKHook(iKey, SDKHook_Touch, Duck_OnTouch);
		
		HookSingleEntityOutput(iKey, "OnRedPickup", Duck_OnPickup, true);
		HookSingleEntityOutput(iKey, "OnBluePickup", Duck_OnPickup, true);
		SetVariantString("OnRedPickup !self:Kill::0.0:1");
		AcceptEntityInput(iKey, "AddOutput");
		
		SetVariantString("OnBluePickup !self:Kill::0.0:1");
		AcceptEntityInput(iKey, "AddOutput");
		
		SetVariantString("OnUser1 !self:Kill::30.0:1");
		AcceptEntityInput(iKey, "AddOutput");
		AcceptEntityInput(iKey, "FireUser1");
	}

	return Plugin_Continue;
}

public Action Duck_OnTouch(int iEntity, int iPlayer) {
	if(0 < iPlayer <= MaxClients && IsClientInGame(iPlayer) && TF2_IsInvisible(iPlayer)) {
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public Action Duck_OnPickup(const char[] output, int caller, int activator, float delay) {
	EmitSoundToAll(DUCK_PICKUP_SND, caller, _, SNDLEVEL_DRYER);
}

void Frame_UpdateMoney(int iRef) {
	int iMoney = EntRefToEntIndex(iRef);

	if(iMoney > MaxClients) {
		int iModelIndex = GetRandomInt(0, sizeof(gDuckModels)-1);
		for (int j = 0; j < 4; j++) SetEntProp(iMoney, Prop_Send, "m_nModelIndexOverrides", gDuckModelIndexes[iModelIndex], _, j);
	}
}

void Frame_TankSpawn(int iRef) {
	int iTank = EntRefToEntIndex(iRef);

	if(iTank > MaxClients) {
		DonationDisplay donationDisplay;
		
		donationDisplay.parent = iTank;
		donationDisplay.scale = 1.0;
		donationDisplay.noProps = true;
		donationDisplay.type = EntityType_Tank;
		
		SetupDonationDisplay(iTank, donationDisplay);
		UpdateDonationDisplays();
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

	gPreviousDonationTotal = gDonationTotal;
	gDonationTotal = total;
	UpdateDonationDisplays();
	ReplyToCommand(client, "[SM] Total updated");

	return Plugin_Handled;
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
		
		ConfigEntry configEntry;
		DonationDisplay donationDisplay;

		donationDisplay.parent = i;

		//Reskin and setup display for control points
		if(StrEqual(class, "team_control_point", false)) {
			donationDisplay.type = EntityType_ControlPoint;

			if(gCPsCvar.BoolValue) {
				PrepareControlPoint(i);
			}
		}

		//Reskin and setup display for intel
		if(StrEqual(class, "item_teamflag", false)) {
			donationDisplay.type = EntityType_Intel;
			PrepareFlag(i);
		}

		//Payloads
		if(payloads.FindString(name) > -1) {
			donationDisplay.type = EntityType_PayloadCart;
		}

		//Resupply cabinets
		if(cabinets.FindValue(i) > -1) {
			donationDisplay.type = EntityType_Resupply;			
		}

		//Check if entity has a config entry and use if so
		if(gConfigEntries.GetArray(name, configEntry, sizeof(ConfigEntry))) {
			#if defined _DEBUG
				PrintToServer("Entity %s has config entry", name);
			#endif

			donationDisplay.scale = configEntry.scale;
			donationDisplay.noProps = !!configEntry.noProps;
			
			donationDisplay.position[0] = configEntry.position[0];
			donationDisplay.position[1] = configEntry.position[1];
			donationDisplay.position[2] = configEntry.position[2];

			donationDisplay.rotation[0] = configEntry.rotation[0];
			donationDisplay.rotation[1] = configEntry.rotation[1];
			donationDisplay.rotation[2] = configEntry.rotation[2];

			if(donationDisplay.type == EntityType_None) {
				donationDisplay.type = EntityType_Custom;
			}
		}

		//Check for regex matches and use it's config entry if matching
		if(strlen(name)) {
			for(int j = 0; j < gConfigRegexes.Length; j++) {
				ConfigRegex configRegex;
				gConfigRegexes.GetArray(j, configRegex, sizeof(ConfigRegex));

				if(configRegex.regex.Match(name) > 0) {
					#if defined _DEBUG
						PrintToServer("Entity %s matched config regex", name);
					#endif

					gConfigEntries.GetArray(configRegex.configEntry, configEntry, sizeof(ConfigEntry));

					donationDisplay.scale = configEntry.scale;
					donationDisplay.noProps = !!configEntry.noProps;
					donationDisplay.type = EntityType_Custom;
					
					donationDisplay.position[0] = configEntry.position[0];
					donationDisplay.position[1] = configEntry.position[1];
					donationDisplay.position[2] = configEntry.position[2];

					donationDisplay.rotation[0] = configEntry.rotation[0];
					donationDisplay.rotation[1] = configEntry.rotation[1];
					donationDisplay.rotation[2] = configEntry.rotation[2];
				}
			}
		}

		if(configEntry.hide) {
			#if defined _DEBUG
				PrintToServer("Donation display for %s hidden", name);
			#endif
			
			continue;
		}

		//If entity should have a donation display create it
		if(donationDisplay.type != EntityType_None && gDonationsCvar.BoolValue) {
			#if defined _DEBUG
				PrintToServer("Entity %s has donation display of type %d", name, donationDisplay.type);
			#endif

			SetupDonationDisplay(i, donationDisplay);
		}
	}

	UpdateDonationDisplays();
}

void SetupDonationDisplay(int entity, DonationDisplay donationDisplay) {
	if(!donationDisplay.parent) {
		donationDisplay.parent = entity;
	}

	if(!donationDisplay.scale) {
		donationDisplay.scale = 1.0;
	}

	donationDisplay.digits[0] = CreateDonationDigit(false);
	donationDisplay.digits[1] = CreateDonationDigit(true);
	donationDisplay.digits[2] = CreateDonationDigit(false);
	donationDisplay.digits[3] = CreateDonationDigit(false, true);

	int index = gDonationDisplays.PushArray(donationDisplay);

	PositionDonationDisplay(donationDisplay);
	ParentDonationDisplay(donationDisplay, index);
}

void PositionDonationDisplay(DonationDisplay donationDisplay) {
	float position[3]; //Entity origin
	float angles[3]; //Entity rotation

	float offset[3]; //Offset from entity origin to use for positioning sprite
	float rotationOffset[3]; 
	float displayPosition[3]; //Final sprite position

	float firstDigitOffset = GetFirstDigitOffset(donationDisplay.type == EntityType_Resupply) * donationDisplay.scale; //Initial offset before first digit to roughly "center" the display around the desired position
	float digitSpacing = 32.0 * donationDisplay.scale; //Spacing between digits

	char scale[10];

	GetEntPropVector(donationDisplay.parent, Prop_Data, "m_vecAbsOrigin", position);
	GetEntPropVector(donationDisplay.parent, Prop_Send, "m_angRotation", angles);

	switch(donationDisplay.type) {
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
		
		// Position in front of the tank
		case EntityType_Tank :
		{
			rotationOffset[1] += 180.0;
			offset[2] += 128.0;
			offset[0] += 120.0;
		}
		
		//Position above control point hologram
		case EntityType_Intel :
			offset[2] += 30.0;
	}

	Format(scale, sizeof(scale), "%00.2f", 0.25 * donationDisplay.scale);

	//Add position offset from config
	offset[0] += donationDisplay.position[0];
	offset[1] += donationDisplay.position[1];
	offset[2] += donationDisplay.position[2];

	//Add rotation offset from config
	rotationOffset[0] += donationDisplay.rotation[0];
	rotationOffset[1] += donationDisplay.rotation[1];
	rotationOffset[2] += donationDisplay.rotation[2];

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

		DispatchKeyValue(donationDisplay.digits[i], "scale", scale);
		TeleportEntity(donationDisplay.digits[i], displayPosition, angles, NULL_VECTOR);
	}
}

void ParentDonationDisplay(DonationDisplay donationDisplay, int index) {
	for(int i = 0; i < 4; i++) {
		SetVariantString("!activator");
		AcceptEntityInput(donationDisplay.digits[i], "SetParent", donationDisplay.parent, donationDisplay.parent);
	}

	if(donationDisplay.type == EntityType_ControlPoint) {
		RequestFrame(ParentControlPointDonationDisplay, index);
	}
}

void ParentControlPointDonationDisplay(any index) {
	DonationDisplay donationDisplay;

	gDonationDisplays.GetArray(index, donationDisplay, sizeof(DonationDisplay));

	for(int i = 0; i < 4; i++) {
		SetVariantString("donations");
		AcceptEntityInput(donationDisplay.digits[i], "SetParentAttachmentMaintainOffset");
	}
}

void UnparentDonationDisplay(DonationDisplay donationDisplay) {
	for(int i = 0; i < 4; i++) {
		AcceptEntityInput(donationDisplay.digits[i], "ClearParent", donationDisplay.parent, donationDisplay.parent);
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
		DonationDisplay entity;

		gDonationDisplays.GetArray(i, entity, sizeof(DonationDisplay));

		for(int j = 0; j < 4; j++) {
			if(IsValidEntity(entity.digits[j])) {
				AcceptEntityInput(entity.digits[j], "Kill");
			}
		}
	}

	gDonationDisplays.Clear();
}

//Set control point model to reskinned version
void PrepareControlPoint(int entity) {
	entity = EntRefToEntIndex(entity);

	if(entity != INVALID_ENT_REFERENCE) {
		DispatchKeyValue(entity, "team_model_3", HOLOGRAM_MODEL);
		DispatchKeyValue(entity, "team_model_2", HOLOGRAM_MODEL);
		DispatchKeyValue(entity, "team_model_0", HOLOGRAM_MODEL);
		SetEntityModel(entity, HOLOGRAM_MODEL);
	}
}

//Set flag model to money
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
		DispatchKeyValue(entity, "model", "blap19/numbers-comma.vmt");
	} else {
		DispatchKeyValue(entity, "model", "blap19/numbers.vmt");
	}

	DispatchKeyValue(entity, "framerate", "0");
	DispatchKeyValue(entity, "spawnflags", "1");
	DispatchKeyValue(entity, "scale", "0.25");
	
	SetEntityRenderMode(entity, RENDER_TRANSALPHAADD);

	DispatchSpawn(entity);
	AcceptEntityInput(entity, "ShowSprite");

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

public int UpdateDonationDisplays() {
	float digits[4] = { 110.0, 110.0, 110.0, 110.0 };
	int divisor = 1;
	int digitsRequired = 0;

	MilestoneType milestone = MilestoneType_None;
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

	int difference = gDonationTotal - gPreviousDonationTotal;

	if(difference >= 25) {
		milestone = MilestoneType_25;
	}

	if(difference >= 50) {
		milestone = MilestoneType_50;
	}

	if(difference >= 100) {
		milestone = MilestoneType_100;
	}

	if((gDonationTotal - (gDonationTotal % 1000)) > gLastMilestone) {
		gLastMilestone = (gDonationTotal - (gDonationTotal % 1000));
		milestone = MilestoneType_1k;
	}

	//Number of required digits for display has changed
	if(digitsRequired != gDigitsRequired) {
		gDigitsRequired = digitsRequired;
		reposition = true;
	}

	for(int i = 0; i < gDonationDisplays.Length; i++) {
		DonationDisplay entity;

		gDonationDisplays.GetArray(i, entity, sizeof(DonationDisplay));

		//If display needs repositioning, unparent then reparent to avoid weirdness
		if(reposition && entity.type != EntityType_Resupply) {
			UnparentDonationDisplay(entity);
			PositionDonationDisplay(entity);
			ParentDonationDisplay(entity, i);
		}

		for(int j = 0; j < 4; j++) {
			SetEntPropFloat(entity.digits[j], Prop_Send, "m_flFrame", digits[j]);
		}

		if(milestone != MilestoneType_None) {
			HandleMilestone(milestone, entity);
		}
		
		TE_Particle("repair_claw_heal_blue", NULL_VECTOR, NULL_VECTOR, NULL_VECTOR, entity.digits[2]);
	}
}

public int HandleMilestone(MilestoneType milestone, DonationDisplay display) {
	switch(milestone) {
		case MilestoneType_1k: //Play tf_birthday sound and spawn confetti
		{
			if(gSoundsCvar.BoolValue) {
				char sound[PLATFORM_MAX_PATH];
		
				Format(sound, sizeof(sound), "misc/happy_birthday_tf_%02i.wav", GetRandomInt(1, 29));
				EmitSoundToAll(sound, display.digits[2]);
			}

			TE_Particle("bday_confetti", NULL_VECTOR, NULL_VECTOR, NULL_VECTOR, display.digits[1]);
		}

		case MilestoneType_100: //Play horn/cheers and spawn coins/notes
		{
			if(gSoundsCvar.BoolValue) {
				EmitSoundToAll("passtime/horn_air2.wav", display.digits[2]);
				EmitSoundToAll("passtime/crowd_cheer.wav", display.digits[2]);
			}

			TE_Particle("taunt_spy_cash", NULL_VECTOR, NULL_VECTOR, NULL_VECTOR, display.digits[1]);
			TE_Particle("bday_balloon02", NULL_VECTOR, NULL_VECTOR, NULL_VECTOR, display.digits[1]);
			SpawnProp(display, PropSpawnType_Coins);
			SpawnProp(display, PropSpawnType_Notes);
		}

		case MilestoneType_50: //Play mvm upgrade sound and spawn notes
		{
			if(gSoundsCvar.BoolValue) {
				EmitSoundToAll("mvm/mvm_bought_upgrade.wav", display.digits[2], SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 0.6);
			}

			TE_Particle("taunt_spy_cash", NULL_VECTOR, NULL_VECTOR, NULL_VECTOR, display.digits[1]);
			SpawnProp(display, PropSpawnType_Notes);
		}

		case MilestoneType_25: //Play mvm money sound and spawn coins
		{
			if(gSoundsCvar.BoolValue) {
				EmitSoundToAll("mvm/mvm_money_pickup.wav", display.digits[2], SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 0.4);
			}

			TE_Particle("taunt_spy_cash", NULL_VECTOR, NULL_VECTOR, NULL_VECTOR, display.digits[1]);
			SpawnProp(display, PropSpawnType_Coins);
		}
	}
}

public int SpawnProp(DonationDisplay display, PropSpawnType type) {
	if(!gPropsCvar.BoolValue) {
		return;
	}

	if(display.noProps != false) {
		return;
	}

	float position[3];
	float rotation[3];

	GetEntPropVector(display.digits[1], Prop_Data, "m_vecAbsOrigin", position);

	int entity = CreateEntityByName("prop_physics_multiplayer");

	if(entity < 0) {
		return;
	}

	//Add some randomness to positioning
	position[2] += GetRandomFloat(-3.0, 3.0);
	rotation[0] = GetRandomFloat(-90.0, 90.0);
	rotation[1] = GetRandomFloat(-90.0, 90.0);
	rotation[2] = GetRandomFloat(-90.0, 90.0);

	switch(type) {
		case PropSpawnType_Coins:
			SetEntityModel(entity, COINS_MODEL);
		case PropSpawnType_Notes:
			SetEntityModel(entity, NOTES_MODEL);
		default:
			return;
	}

	DispatchSpawn(entity);
	TeleportEntity(entity, position, rotation, NULL_VECTOR);

	RequestFrame(InitProp, EntIndexToEntRef(entity)); //Wait a frame to create gibs
}

//Break prop into gibs
public int InitProp(any entity) {
	int index = EntRefToEntIndex(entity);

	if(index == INVALID_ENT_REFERENCE) {
		return;
	}

	AcceptEntityInput(entity, "Break");
}

bool TF2_IsInvisible(int client) {
	return ((TF2_IsPlayerInCondition(client, TFCond_Cloaked) ||
		TF2_IsPlayerInCondition(client, TFCond_DeadRingered) ||
		TF2_IsPlayerInCondition(client, TFCond_Stealthed))
		&& !TF2_IsPlayerInCondition(client, TFCond_StealthedUserBuffFade)
		&& !TF2_IsPlayerInCondition(client, TFCond_CloakFlicker));
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
