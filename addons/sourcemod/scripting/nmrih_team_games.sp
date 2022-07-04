#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <multicolors>

#pragma semicolon 1
#pragma newdecls required
//#pragma dynamic 131072

#define PLUGIN_AUTHOR "Ulreth*"
#define PLUGIN_VERSION "1.3.1" // 4-07-2022
#define PLUGIN_NAME "[NMRiH] Team Games"

#define FL_DUCKING (1 << 1)
#define DMG_WELDER 128

// BASIC MAP REQUIREMENTS:
/*
DEPRECATED - RED "trigger_multiple" (area_red) --> Adds players to RED team
DEPRECATED - BLUE "trigger_multiple" (area_blue) --> Adds players to BLUE team
- RED "trigger_multiple" (terro_But) --> BLUE team will try to score in this net
- BLUE "trigger_multiple" (ct_But) --> RED team will try to score in this net

- RED Spawn "info_player_nmrih" (t_player) --> SoccerMod
- BLUE Spawn "info_player_nmrih" (ct_player) --> SoccerMod

- RED Spawn "info_player_nmrih" (attacker) --> Team Deathmatch
- BLUE Spawn "info_player_nmrih" (defender) --> Team Deathmatch

- Extraction Zone --> "func_nmrih_extractionzone"

- RED "trigger_teleport" (TeledestinationT) --> RED team base teleport 
- BLUE "trigger_teleport" (TeledestinationCt)--> BLUE team base teleport

- RED Template Maker "npc_template_maker" (template_red_gk)
- BLUE Template Maker "npc_template_maker" (template_blue_gk)

- RED "trigger_hurt" (red_hurt_npc)
- BLUE "trigger_hurt" (blue_hurt_npc)

- RED "trigger_multiple" (red_trigger_npc_area)
- BLUE "trigger_multiple" (blue_trigger_npc_area)

- RED "npc_nmrih_runnerzombie" (npc_gk_red)
- BLUE "npc_nmrih_runnerzombie" (npc_gk_blue)

- MAIN SOCCERBALL "prop_physics" (pelota0)
- MAIN TRIGGER "trigger_multiple" (trigger_ball0)

Important note: Case sensitive for entity targetname
*/

// IN THE FUTURE:
/*
- SOCCERMOD DAMAGE BETWEEN ENEMIES NEAR THE BALL (NOT GK)
*/

/*
CHANGELOG
1.0.1:
- Added tool_welder as main weapon uppon player respawn (Soccermod)
- Added admin command !forcerandom to shuffle teams (SoccerMod)
- Added client commands to change team BLUE or RED (SoccerMod)
- Fixed bugs related to enemy spawns after round end

1.1.1:
- Added GK position with increased health points
- Added cvar to shutdown plugin
- Added admin command to end round
- Added menu to show admin commands
- Added default hl2 sounds to help user commands
- Fixed hats attachment (credit Niki4)
- Fixed starting player angle position
- Fixed extraction bug for TDM gamemode

1.1.2:
- Added new player glow mode based on color (includes GK outline)
- Removed buggy sprites and models

1.2.0:
- Added CFG files to manage TDM and SoccerMod maps
- Added warning logs if map is not valid
- Added crouch bonus speed for GKs inside own areas
- Updated list of map requirements
- Fixed player team selection bug
- Fixed player movement during round start

1.2.1:
- Added goalkeeper small color trails
- Added ball dynamic collision type during match (+ colors)
- Added ball trails according to collision type
- Optimized entity location code
- Optimized global timer code
- Updated workshop map for SoccerMod

1.2.2:
- Fixed glow and trail not applying for first team index

1.2.3:
- Added CVAR cooldown for any team change
- Added loser team teleport near ball for next kick off
- Changed plugin name since now covers both game modes
- Improved key detection for CFG files (map_version not required now)
- Improved quality of FF text
- Fixed wrong precache route for some files
- Optimized some old code

1.2.4:
- Added team balance check
- Fixed wrong team auto shuffle
- Fixed missing CVAR flag

1.3.0:
- Added chat announcements for SoccerMod events
- Added auto team balance during global timer
- Added sounds to make TDM events more clear
- Added even more clear game text for all teams
- Added translations for all chat msg
- Added tool_welder periodic cleanup
- Improved ball catch and dribble
- Optimized old ugly code
- Simplified array of teams
- Fixed wrong team player count (when changing teams)
- Fixed goal count when scoring at warmup round
- Fixed ball steal and pass count

1.3.1:
- Removed spamming text when trying team change
- Fixed team change wrong cvar cooldown
- Fixed team change bug
*/

#define TEAM_MAXPLAYERS 5
#define SOCCERMOD_GK_DISTANCE 352.0
#define SOCCERMOD_BALL_DISTANCE 412.0
#define SOCCERMOD_CRITICAL_HEIGHT 60.0
#define HINT_INTERVAL 99
#define BALL_STOP_COOLDOWN 3
#define TEAM_GAMES_CFG_COUNT 2

#define SOUND_WARNING_BELL "play *ambient/alarms/warningbell1.wav"
#define SOUND_KLAXON "play *ambient/alarms/klaxon1.wav"
#define SOUND_WARNING "play *common/warning.wav"
#define SOUND_SURV_ALARM "play *survival/surv_alarm.wav"
#define SOUND_ELEV_BELL "play *plats/elevbell1.wav"

// BALL STRING COLORS
#define BALL_DEBRIS_COLOR "254 254 254"
#define BALL_SOLID_COLOR "254 254 0"

// TRAIL VECTOR COLORS
#define NO_TRAIL {1, 1, 1, 0}
#define GK_RED_TRAIL_COLOR {200, 100, 0, 128}
#define GK_BLUE_TRAIL_COLOR {100, 200, 255, 128}
#define BALL_TRAIL_DEBRIS {128, 128, 128, 128}
#define BALL_TRAIL_SOLID {254, 254, 0, 128}

// GLOW COLORS
#define RED_GK_COLOR "200 100 0"
#define RED_COLOR_1 "255 0 1"
#define RED_COLOR_2 "254 1 0"
#define RED_COLOR_3 "254 0 1"
#define RED_COLOR_4 "253 1 0"
#define RED_COLOR_5 "253 0 1"

#define BLUE_GK_COLOR "100 200 255"
#define BLUE_COLOR_1 "1 0 255"
#define BLUE_COLOR_2 "0 1 254"
#define BLUE_COLOR_3 "1 0 254"
#define BLUE_COLOR_4 "0 1 253"
#define BLUE_COLOR_5 "1 0 253"

// CONVARS
ConVar cvar_tdm_enabled;
ConVar cvar_tdm_debug;
ConVar cvar_tdm_insta_extract;
ConVar cvar_tdm_command_cd;

int g_TimerCount = 0;
int g_Timer_CooldownCount = 0;

// GAME STATES
int g_GameMode = 0; // 0 = Classic TDM | 1 = SoccerMod

bool g_PluginEnabled = true;
bool g_Warmup = true;
//bool g_RoundStart = false;
bool g_ExtractionStarted = false;

int g_LastScore = 0; // 0 = No goals scored | 1 = RED team scored previous round | 2 = BLUE team scored previous round

// PLAYERS COUNT
int g_PlayerCount = 0;
int g_BlueCount = 0; // Count alive BLUE players in TDM | Count BLUE also dead players in SoccerMod
int g_RedCount = 0; // Count alive RED players | Count also RED dead players in SoccerMod
char g_PlayerName[MAXPLAYERS][64];
int g_PlayerMenuCooldown[MAXPLAYERS];

// TDM TEXT VARIABLES
char sMessageColor_Red[32];
char sMessageColor_Blue[32];
char sMessageEffect[3];
char sMessageChannel[32];
char sMessagePosX[16];
char sMessagePosY[16];
char sMessageFadeIn[32];
char sMessageFadeOut[16];
char sMessageHoldTime[16];
char sMessage_RedTeam[64];
char sMessage_BlueTeam[64];
char sMessage_RedGK[64];
char sMessage_BlueGK[64];

// BALL VARIABLES

// Ball owner is anyone that comes in contact with ball, with or without applying any welder DMG (this means an accidental bounce)
int g_Ball_Owner = -1;

// Ball shooter can only be someone that applied welder DMG to ball
int g_Ball_Shooter = -1;

// Ball passer only can exist when 2 or more players share a team
int g_Ball_Passer = -1;

int g_SoccerBall = INVALID_ENT_REFERENCE;
float g_SoccerBall_pos[3];
float g_SoccerBall_origin[3];
//int g_TriggerBall = INVALID_ENT_REFERENCE;
int g_Ball_Trail_Color[4] = {128, 128, 128, 128};
int g_MI_trail;

// "ready" sound cooldown
bool g_bStop_Cooldown = false;

// BLUE PLAYERS
float g_GK_blue_distance;
float g_GK_blue_position[3];
int g_GK_blue = -1;
int g_BluePlayers[MAXPLAYERS]; // Saves index of BLUE players
float g_OriginBlue[3]; // Saves spawn origins of RED players
float g_Origin_Blue_Goal[3]; // Saves origin of CT button

// RED PLAYERS
float g_GK_red_distance;
float g_GK_red_position[3];
int g_GK_red = -1;
int g_RedPlayers[MAXPLAYERS]; // Saves index of RED players
float g_OriginRed[3]; // Saves spawn origins of RED players
float g_Origin_Red_Goal[3]; // Saves origin of T button

// VOTING SYSTEM
int g_VotingPlayers[MAXPLAYERS]; // Stores client IDs to make a vote count later
int g_VotingCount = 0;

// SCOREBOARD
Handle h_T_Global = null; // Global timer
int g_RedScore = 0;
int g_BlueScore = 0;

public Plugin myinfo =
{
	name = PLUGIN_NAME,
	author = PLUGIN_AUTHOR,
	description = "A plugin that enables team deathmatch functions, useful in custom maps such as mg_castle_assault or mg_soccer_2020",
	version = PLUGIN_VERSION,
	url = "http://steamcommunity.com/groups/lunreth-laboratory"
};

public void OnPluginStart()
{
	LoadTranslations("nmrih_team_games.phrases");
	CreateConVar("tdm_version", PLUGIN_VERSION, PLUGIN_NAME, FCVAR_NOTIFY);
	cvar_tdm_enabled = CreateConVar("tdm_enable", "1.0", "Enable or disable Team Deathmatch plugin.", _, true, 0.0, true, 1.0);
	cvar_tdm_debug = CreateConVar("tdm_debug", "0.0", "Debug mode for plugin - Will spam messages in console if set to 1", _, true, 0.0, true, 1.0);
	cvar_tdm_insta_extract = CreateConVar("tdm_insta_extraction", "1.0", "Set to 1.0 if you want an instant extraction of players", _, true, 0.0, true, 1.0);
	cvar_tdm_command_cd = CreateConVar("tdm_changeteam_cd", "30.0", "Amount of seconds that players should wait between any team change");
	AutoExecConfig(true, "nmrih_team_games");
	
	// GK COMMANDS
	RegConsoleCmd("sm_goalkeeper", Command_GK, "Type !goalkeeper to be the goalkeeper.");
	RegConsoleCmd("sm_gk", Command_GK, "Type !gk to be the goalkeeper.");
	RegConsoleCmd("sm_arquero", Command_GK, "Escribe !arquero para atajar.");
	RegConsoleCmd("sm_atajo", Command_GK, "Escribe !atajo para ser arquero.");
	RegConsoleCmd("sm_atajar", Command_GK, "Escribe !atajar para ser arquero.");
	RegConsoleCmd("sm_portero", Command_GK, "Escribe !arquero para atajar.");
	RegConsoleCmd("sm_player", Command_GK_Disable, "Say !player to leave GK position");
	RegConsoleCmd("sm_noatajo", Command_GK_Disable, "Escribe !noatajo para dejar de ser arquero");
	RegConsoleCmd("sm_jugador", Command_GK_Disable, "Escribe !jugador para dejar de ser arquero");
	// RED AND BLUE COMMANDS
	RegConsoleCmd("sm_red", Command_Red, "Say !red to switch to RED team.");
	RegConsoleCmd("sm_rojo", Command_Red, "Say !rojo para ser parte del equipo ROJO.");
	RegConsoleCmd("sm_blue", Command_Blue, "Say !blue to become part of BLUE team.");
	RegConsoleCmd("sm_azul", Command_Blue, "Say !azul para ser parte del equipo AZUL.");
	// RANDOM TEAMS VOTE
	RegConsoleCmd("sm_shuffle", Command_Shuffle, "Say !shuffle to randomize teams and restart match.");
	RegConsoleCmd("sm_restart", Command_Shuffle, "Say !restart to randomize teams and restart match.");
	RegConsoleCmd("sm_mezclar", Command_Shuffle, "Escribir !mezclar para votar equipos aleatorios.");
	// ADMIN COMMANDS
	RegAdminCmd("sm_soccer", Menu_Main, ADMFLAG_BAN);
	RegAdminCmd("sm_soccermod", Menu_Main, ADMFLAG_BAN);
	RegAdminCmd("sm_endround", Command_EndRound, ADMFLAG_BAN);
	RegAdminCmd("sm_forcerandom", Command_ForceRandom, ADMFLAG_BAN);
	
	if (GetConVarFloat(cvar_tdm_enabled) == 0.0)
	{
		g_PluginEnabled = false;
		return;
	}
	
	HookEvent("nmrih_round_begin", Event_RoundStart);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Pre);
	HookEvent("nmrih_reset_map", Event_ResetMap);
	HookEvent("nmrih_practice_ending", Event_PracticeStart);
	//HookEntityOutput("prop_physics", "OnTakeDamage", PropTakeDamage);
	HookEventEx("extraction_begin", Event_ExtractionBegin);
	HookEventEx("objective_fail", Event_ResetVariables);
	HookEventEx("player_join", Event_PlayerJoin, EventHookMode_Post);
	HookEventEx("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
	// OnClientPutInServer
	// OnClientDisconnect
	// OnMapStart
	// OnMapEnd
	
	// OnTakeDamage_SDK() --> GK protection + prop_physics + tool_welder + attacker ID
	// OnTouch() --> trigger_multiple
	// PLAYER LOOP
	for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
        {
            SDKHook(i, SDKHook_OnTakeDamage, OnTakeDamage_SDK);
        }
    }
	// TIMER FOR PLAYER COLOR
	h_T_Global = CreateTimer(0.1, Timer_Global, _, TIMER_REPEAT);
}

public void OnMapStart()
{
	if (GetConVarFloat(cvar_tdm_enabled) == 0.0)
	{
		g_PluginEnabled = false;
		return;
	}
	
	// PRECACHE
	PrecacheModel("materials/trails/beam_01.vmt");
	PrecacheSound("ambient/alarms/warningbell1.wav");
	PrecacheSound("ambient/alarms/klaxon1.wav");
	PrecacheSound("common/warning.wav");
	PrecacheSound("survival/surv_alarm.wav");
	PrecacheSound("plats/elevbell1.wav");
	
	// FULL MAPNAME DIFFERS FROM CFG NAMES
	char full_mapname[65];
	GetCurrentMap(full_mapname, sizeof(full_mapname));
	
	KeyValues hConfig;
	char path[PLATFORM_MAX_PATH];
	for (int index = 0; index < TEAM_GAMES_CFG_COUNT; index++)
	{
		switch (index)
		{
			case 0:
			{
				hConfig = new KeyValues("team_deathmatch");
				BuildPath(Path_SM, path, sizeof(path), "configs/nmrih_tdm_maps.cfg");
			}
			case 1:
			{
				hConfig = new KeyValues("soccermod");
				BuildPath(Path_SM, path, sizeof(path), "configs/nmrih_soccermod_maps.cfg");
			}
		}
		hConfig.ImportFromFile(path);
		
		// Jump into the first subsection
		if (!hConfig.GotoFirstSubKey())
		{
			PrintToServer("[NMRiH] Invalid CFG file, check full example at plugin download page");
			LogMessage("[NMRiH] Invalid CFG file, check full example at plugin download page");
		}
		
		// Iterate over subsections at the same nesting level
		char buffer[255];
		do
		{
			hConfig.GetSectionName(buffer, sizeof(buffer));
			if (StrContains(full_mapname, buffer, false) != -1)
			{
				g_PluginEnabled = true;
				switch (index)
				{
					case 0:
					{
						g_GameMode = 0;
						PrintToServer("[TEAM DEATHMATCH] Map for this gamemode detected");
						LogMessage("[TEAM DEATHMATCH] Map for this gamemode detected");
					}
					case 1:
					{
						g_GameMode = 1;
						PrintToServer("[SOCCERMOD] Map for this gamemode detected");
						LogMessage("[SOCCERMOD] Map for this gamemode detected");
						
						AddFileToDownloadsTable("sound/fight.mp3");
						PrecacheSound("sound/fight.mp3");
						
						AddFileToDownloadsTable("sound/crowd_1.mp3");
						PrecacheSound("sound/crowd_1.mp3");
						
						AddFileToDownloadsTable("sound/alarm_win.mp3");
						PrecacheSound("sound/alarm_win.mp3");
						
						AddFileToDownloadsTable("sound/customsounds/shot2_arb.mp3");
						PrecacheSound("sound/customsounds/shot2_arb.mp3");
						
						AddFileToDownloadsTable("sound/customsounds/ready.mp3");
						PrecacheSound("sound/customsounds/ready.mp3");
						
						AddFileToDownloadsTable("sound/customsounds/ready_gk.mp3");
						PrecacheSound("sound/customsounds/ready_gk.mp3");
						
						AddFileToDownloadsTable("sound/fieldsounds/crowd_generic1.wav");
						PrecacheSound("sound/fieldsounds/crowd_generic1.wav");
						
						AddFileToDownloadsTable("sound/fieldsounds/crowd_generic2.wav");
						PrecacheSound("sound/fieldsounds/crowd_generic2.wav");
						
						AddFileToDownloadsTable("sound/fieldsounds/crowd_maracana.wav");
						PrecacheSound("sound/fieldsounds/crowd_maracana.wav");
						
						AddFileToDownloadsTable("sound/fieldsounds/gol_brasil_mcn.wav");
						PrecacheSound("sound/fieldsounds/gol_brasil_mcn.wav");
						
						AddFileToDownloadsTable("sound/fieldsounds/golsound_b4.mp3");
						PrecacheSound("sound/fieldsounds/golsound_b4.mp3");
						
						AddFileToDownloadsTable("sound/fieldsounds/sifflet_but.mp3");
						PrecacheSound("sound/fieldsounds/sifflet_but.mp3");
						
						AddFileToDownloadsTable("sound/fieldsounds/sifflet_start.mp3");
						PrecacheSound("sound/fieldsounds/sifflet_start.mp3");
					}
				}
				break;
			}
		} while(hConfig.GotoNextKey());
		
		delete hConfig;
	}
	g_Warmup = true;
	VariablesToZero();
	MatchVariablesZero();
	SearchSpawns();
}

public void OnClientPutInServer(int client)
{
	if (!g_PluginEnabled) return;
	if (GetConVarFloat(cvar_tdm_enabled) != 1.0) return;
	
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage_SDK);
	GetClientName(client, g_PlayerName[client], sizeof(g_PlayerName[]));
}

public Action OnTakeDamage_SDK(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
	if (!g_PluginEnabled) return Plugin_Continue;
	if (GetConVarFloat(cvar_tdm_enabled) != 1.0) return Plugin_Continue;
	
	
	// GOALKEEPER SAVE
	if (attacker == EntRefToEntIndex(g_SoccerBall))
	{
		if ((g_Ball_Shooter != victim) && (g_Ball_Shooter != -1))
		{
			// CHECKING GOALKEEPER TEAM
			if ((victim == g_GK_red) && (g_GK_red_distance <= SOCCERMOD_GK_DISTANCE))
			{
				//CPrintToChatAll("[{lime}SOCCERMOD{default}] Goalkeeper {fullred}%s{default} saved an incoming shot!", g_PlayerName[victim]);
				CPrintToChatAll("%t", "gk_red_saved_shot", g_PlayerName[victim]);
				ClientCommand(victim, "play *customsounds/ready_gk.mp3");
			}
			else if ((victim == g_GK_blue) && (g_GK_blue_distance <= SOCCERMOD_GK_DISTANCE))
			{
				//CPrintToChatAll("[{lime}SOCCERMOD{default}] Goalkeeper {fullblue}%s{default} saved an incoming shot!", g_PlayerName[victim]);
				CPrintToChatAll("%t", "gk_blue_saved_shot", g_PlayerName[victim]);
				ClientCommand(victim, "play *customsounds/ready_gk.mp3");
			}
			if ((0 < victim) && (victim <= MaxClients))
			{
				g_Ball_Owner = victim;
				if ((damage > 0.0) && (victim != g_GK_blue) && (victim != g_GK_red))
				{
					CPrintToChat(victim, "%t", "ball_damage_detected", damage);
				}
			}
		}
	}
	// PLAYER INTERACTING WITH BALL
	if (((0 < attacker) && (attacker <= MaxClients)) && (IsClientInGame(attacker)))
	{
		// VALID SOCCERBALL REF INDEX
		if (EntRefToEntIndex(g_SoccerBall) == victim)
		{
			// PREVIOUS OWNER WILL BE DIFFERENT THAN NEW ATTACKER
			if ((g_Ball_Owner != attacker) && (g_Ball_Owner != -1) && (IsClientInGame(g_Ball_Owner)))
			{
				// CHECKING TEAM CASES
				if (IsPlayerRed(attacker))
				{
					if (IsPlayerBlue(g_Ball_Owner))
					{
						// RED STEALS BALL FROM BLUE BY KICKING BALL AWAY (without stopping the ball)
						g_Ball_Passer = -1;
						ClientCommand(g_Ball_Owner, "play *ambient/alarms/warningbell1.wav");
						//CPrintToChat(g_Ball_Owner, "[{lime}SOCCERMOD{default}] You lost the {yellow}BALL{default} and now {fullred}%s{default} has it!", g_PlayerName[attacker]);
						CPrintToChat(g_Ball_Owner, "%t", "you_lost_ball_blue", g_PlayerName[attacker]);
					}
					else if (IsPlayerRed(g_Ball_Owner))
					{
						// RED MAKES A VOLLEY SHOT COMING FROM TEAMMATE QUICK PASS (without stopping the ball)
						g_Ball_Passer = g_Ball_Owner;
						ClientCommand(g_Ball_Owner, "play *hl1/fvox/fuzz.wav");
						//CPrintToChat(g_Ball_Owner, "[{lime}SOCCERMOD{default}] Nice {yellow}pass{default} to your teammate {fullred}%s!", g_PlayerName[attacker]);
						CPrintToChat(g_Ball_Owner, "%t", "nice_pass_red", g_PlayerName[attacker]);
					}
				}
				else if (IsPlayerBlue(attacker))
				{
					if (IsPlayerRed(g_Ball_Owner))
					{
						// BLUE STEALS BALL FROM RED BY KICKING BALL AWAY (without stopping the ball)
						g_Ball_Passer = -1;
						ClientCommand(g_Ball_Owner, "play *ambient/alarms/warningbell1.wav");
						//CPrintToChat(g_Ball_Owner, "[{lime}SOCCERMOD{default}] You lost the {yellow}BALL{default} and now {fullblue}%s{default} has it!", g_PlayerName[attacker]);
						CPrintToChat(g_Ball_Owner, "%t", "you_lost_ball_red", g_PlayerName[attacker]);
					}
					else if (IsPlayerBlue(g_Ball_Owner))
					{
						// BLUE MAKES A VOLLEY SHOT COMING FROM TEAMMATE QUICK PASS (without stopping the ball)
						g_Ball_Passer = g_Ball_Owner;
						ClientCommand(g_Ball_Owner, "play *hl1/fvox/fuzz.wav");
						//CPrintToChat(g_Ball_Owner, "[{lime}SOCCERMOD{default}] Nice {yellow}pass{default} to your teammate {fullblue}%s!", g_PlayerName[attacker]);
						CPrintToChat(g_Ball_Owner, "%t", "nice_pass_blue", g_PlayerName[attacker]);
					}
				}
			}
			// DETECTED WELDER WEAPON
			if ((damagetype == DMG_WELDER) && (g_Ball_Shooter != attacker))
			{
				// THE ATTACKER IS NOW THE LAST BALL SHOOTER
				g_Ball_Shooter = attacker;
				if (IsPlayerRed(attacker)) CPrintToChatAll("%t", "ball_kick_red", g_PlayerName[attacker]);
				else if (IsPlayerBlue(attacker)) CPrintToChatAll("%t", "ball_kick_blue", g_PlayerName[attacker]);
			}
			
			// NEW TEMPORARY OWNER (BALL BOUNCED ON HIM PROBABLY)
			g_Ball_Owner = attacker;
			
			// APPLYING GLOBAL COOLDOWN TO CATCH BALL
			g_bStop_Cooldown = true;
			g_Timer_CooldownCount = 0;
			// Damage Type 0 (player collision) = 1 (DMG_CRUSH)
			// Damage Type 1 (tool_welder / item_zippo) = 128 (DMG_WELDER)
			// Damage Type 2 (me_fists) = 16777344
			// Damage Type 3 (me_fireaxe) = 16777220
			
			//PrintToServer("Last passer = %d", g_Ball_Passer);
			//PrintToServer("Attacker = %d", attacker);
			//PrintToServer("Ball (Victim) = %d", victim);
			//PrintToServer("Damage type = %d", damagetype);
		}
	}
	// NO GOALKEEPER DAMAGE
	if (attacker == EntRefToEntIndex(g_SoccerBall))
	{
		// CHECKING GOALKEEPER TEAM
		if ((victim == g_GK_red) && (g_GK_red_distance <= SOCCERMOD_GK_DISTANCE))
		{
			damage = 0.0;
			PrintHintText(victim, "%t", "gk_no_damage_hint");
			return Plugin_Changed;
		}
		else if ((victim == g_GK_blue) && (g_GK_blue_distance <= SOCCERMOD_GK_DISTANCE))
		{
			damage = 0.0;
			PrintHintText(victim, "%t", "gk_no_damage_hint");
			return Plugin_Changed;
		}
	}
	// CHECKING FRIENDLY FIRE
	if ((0 < victim) && (victim <= MaxClients) && (0 < attacker) && (attacker <= MaxClients) && (victim != attacker))
	{
		if ((IsPlayerRed(victim) && IsPlayerRed(attacker)) || (IsPlayerBlue(victim) && IsPlayerBlue(attacker)))
		{
			// DETECTED FRIENDLY FIRE
			damage = 0.0;
			ClientCommand(attacker, "play *ambient/alarms/warningbell1.wav");
			PrintHintText(attacker, "%t", "ff_disabled_hint");
			return Plugin_Changed;
		}
	}
	
	return Plugin_Continue;
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if(!g_PluginEnabled) return;
	if(StrEqual(classname, "trigger_multiple", false))
	{
		// HOOKS EVENTS FOR TRIGGER_MULTIPLE
		SDKHookEx(entity, SDKHook_Touch, OnTouch);
	}
	else if(StrContains(classname, "prop_physics", false) != -1)
	{
		SDKHook(entity, SDKHook_OnTakeDamage, OnTakeDamage_SDK);
	}
}

public Action OnTouch(int entity, int other)
{
	if ((g_PluginEnabled == false) && (GetConVarFloat(cvar_tdm_enabled) == 1.0))
	{
		return Plugin_Continue;
	}
	
	char class_name[32];
	GetEdictClassname(other, class_name, 32);
	
	char ball_name[64];
	GetEntPropString(other, Prop_Data, "m_iName", ball_name, sizeof(ball_name));
	
	char trigger_name[64];
	GetEntPropString(entity, Prop_Data, "m_iName", trigger_name, sizeof(trigger_name));
	
	char client_name[64];
	
	if (StrEqual(ball_name, "pelota0", false))
	{
		if ((g_ExtractionStarted == false) && (g_Warmup == false))
		{
			if (StrEqual(trigger_name, "terro_But", false))
			{
				// WINNER: BLUE TEAM
				g_LastScore = 2;
				g_BlueScore = (g_BlueScore + 1);
				KillTeam(g_RedPlayers);
				ForceExtractTeam(g_BluePlayers);
				if (g_Ball_Shooter != -1)
				{
					if (IsPlayerBlue(g_Ball_Shooter))
					{
						//CPrintToChatAll("[{lime}SOCCERMOD{default}] Player {fullblue}%s{default} scores an amazing goal!", g_PlayerName[g_Ball_Shooter]);
						CPrintToChatAll("%t", "amazing_goal_blue", g_PlayerName[g_Ball_Shooter]);
						if ((g_Ball_Passer != -1) && (IsClientInGame(g_Ball_Passer)))
						{
							if (IsPlayerBlue(g_Ball_Passer))
							{
								//CPrintToChatAll("[{lime}SOCCERMOD{default}] Assisted by {fullblue}%s{default}!", g_PlayerName[g_Ball_Passer]);
								CPrintToChatAll("%t", "assisted_by_blue", g_PlayerName[g_Ball_Passer]);
							}
						}
					}
					else if (IsPlayerRed(g_Ball_Shooter))
					{
						//CPrintToChatAll("[{lime}SOCCERMOD{default}] Embarrasing own goal made by {fullred}%s{default}!", g_PlayerName[g_Ball_Shooter]);
						CPrintToChatAll("%t", "own_goal_red", g_PlayerName[g_Ball_Shooter]);
					}
				}
				//CPrintToChatAll("[{lime}Team Games{default}] {fullblue}BLUE{default} team wins this round!");
				CPrintToChatAll("%t", "blue_team_wins");
				PrintCenterTextAll("%t", "blue_team_center_wins");
			}
			else if (StrEqual(trigger_name, "ct_But", false))
			{
				// WINNER: RED TEAM
				g_LastScore = 1;
				g_RedScore = (g_RedScore + 1);
				KillTeam(g_BluePlayers);
				ForceExtractTeam(g_RedPlayers);
				if (g_Ball_Shooter != -1)
				{
					if (IsPlayerRed(g_Ball_Shooter))
					{
						//CPrintToChatAll("[{lime}SOCCERMOD{default}] Player {fullred}%s{default} scores an amazing goal!", g_PlayerName[g_Ball_Shooter]);
						CPrintToChatAll("%t", "amazing_goal_red", g_PlayerName[g_Ball_Shooter]);
						if ((g_Ball_Passer != -1) && (IsClientInGame(g_Ball_Passer)))
						{
							if (IsPlayerRed(g_Ball_Passer))
							{
								//CPrintToChatAll("[{lime}SOCCERMOD{default}] Assisted by {fullred}%s{default}!", g_PlayerName[g_Ball_Passer]);
								CPrintToChatAll("%t", "assisted_by_red", g_PlayerName[g_Ball_Passer]);
							}
						}
					}
					else if (IsPlayerBlue(g_Ball_Shooter))
					{
						//CPrintToChatAll("[{lime}SOCCERMOD{default}] Embarrasing own goal made by {fullblue}%s{default}!", g_PlayerName[g_Ball_Shooter]);
						CPrintToChatAll("%t", "own_goal_blue", g_PlayerName[g_Ball_Shooter]);
					}
				}
				//CPrintToChatAll("[{lime}Team Games{default}] {fullred}RED{default} team wins this round!");
				CPrintToChatAll("%t", "red_team_wins");
				PrintCenterTextAll("%t", "red_team_center_wins");
			}
		}
	}
	// TRIGGER MULTIPLE DETECTION
	if (StrEqual(class_name, "player", false))
	{
		if (StrEqual(trigger_name, "trigger_ball0", false))
		{
			if (g_bStop_Cooldown == false)
			{
				// BALL PREVIOUS OWNER IS DIFFERENT FROM NEW OWNER
				if (g_Ball_Owner != other)
				{
					// BALL OWNER SHOULD BE A VALID CLIENT
					if ((g_Ball_Owner != -1) && (IsClientInGame(g_Ball_Owner)))
					{
						// CHECKING TEAM DIFFERENCE
						if (IsPlayerRed(g_Ball_Owner))
						{
							if (IsPlayerRed(other))
							{
								// THEY ARE TEAMMATES - PREVIOUS OWNER IS THE NEW PASSER
								g_Ball_Passer = g_Ball_Owner;
								ClientCommand(g_Ball_Owner, "play *hl1/fvox/fuzz.wav");
								//CPrintToChat(g_Ball_Owner, "[{lime}SOCCERMOD{default}] Nice {yellow}pass{default} to your teammate {fullred}%s!", g_PlayerName[other]);
								CPrintToChat(g_Ball_Owner, "%t", "nice_pass_red", g_PlayerName[other]);
							}
							else if (IsPlayerBlue(other))
							{
								// BALL STEALING
								g_Ball_Passer = -1;
								ClientCommand(g_Ball_Owner, "play *ambient/alarms/warningbell1.wav");
								//CPrintToChat(g_Ball_Owner, "[{lime}SOCCERMOD{default}] You lost the {yellow}BALL{default} and now {fullblue}%s{default} has it!", g_PlayerName[other]);
								CPrintToChat(g_Ball_Owner, "%t", "you_lost_ball_red", g_PlayerName[other]);
							}
						}
						else if (IsPlayerBlue(g_Ball_Owner))
						{
							if (IsPlayerBlue(other))
							{
								// THEY ARE TEAMMATES - PREVIOUS OWNER IS THE NEW PASSER
								g_Ball_Passer = g_Ball_Owner;
								ClientCommand(g_Ball_Owner, "play *hl1/fvox/fuzz.wav");
								//CPrintToChat(g_Ball_Owner, "[{lime}SOCCERMOD{default}] Nice {yellow}pass{default} to your teammate {fullblue}%s!", g_PlayerName[other]);
								CPrintToChat(g_Ball_Owner, "%t", "nice_pass_blue", g_PlayerName[other]);
							}
							else if (IsPlayerRed(other))
							{
								// BALL STEALING
								g_Ball_Passer = -1;
								ClientCommand(g_Ball_Owner, "play *ambient/alarms/warningbell1.wav");
								//CPrintToChat(g_Ball_Owner, "[{lime}SOCCERMOD{default}] You lost the {yellow}BALL{default} and now {fullred}%s{default} has it!", g_PlayerName[other]);
								CPrintToChat(g_Ball_Owner, "%t", "you_lost_ball_blue", g_PlayerName[other]);
							}
						}
					}
					// THE PLAYER TOUCHING BALL IS THE NEW OWNER
					g_Ball_Owner = other;
					//CPrintToChat(other, "[{lime}SOCCERMOD{default}] YOU have the {yellow}BALL{default}");
					CPrintToChat(other, "%t", "you_have_ball");	
				}
				AcceptEntityInput(EntRefToEntIndex(g_SoccerBall), "DisableMotion");
				RequestFrame(FrameCallback, other);
			}
			g_Timer_CooldownCount = 0;
			g_bStop_Cooldown = true;
		}
		// PREVENTS ADDING SAME PLAYER TO SAME TEAM AGAIN
		if((IsPlayerRed(other) == true) || (IsPlayerBlue(other) == true))
		{
			return Plugin_Continue;
		}
		else if (StrEqual(trigger_name, "area_red", false))
		{
			// RED PLAYER JOINS THE MATCH
			RemoveFromTeam(other);
			AddPlayerToArray(other, g_RedPlayers);
			GetClientName(other, client_name, sizeof(client_name));
			//CPrintToChatAll("[{lime}Team Games{default}] %s has joined {fullred}RED{default} team.", client_name);
			CPrintToChatAll("%t", "joined_red_team", client_name);
        }
		else if (StrEqual(trigger_name, "area_blue", false))
		{
            // BLUE PLAYER JOINS THE MATCH
			RemoveFromTeam(other);
			AddPlayerToArray(other, g_BluePlayers);
			GetClientName(other, client_name, sizeof(client_name));
			//CPrintToChatAll("[{lime}Team Games{default}] %s has joined {fullblue}BLUE{default} team.", client_name);
			CPrintToChatAll("%t", "joined_blue_team", client_name);			
        }
    }
	return Plugin_Continue;
}

public void FrameCallback(any client)
{
	if(IsValidEntity(EntRefToEntIndex(g_SoccerBall)))
	{
		AcceptEntityInput(EntRefToEntIndex(g_SoccerBall), "EnableMotion");
		ClientCommand(client, "play *customsounds/ready.mp3");
	}
}

///---///////////---/// ADMIN MENU ///---///////////---///

public Action Menu_Main(int client, int args)
{
	if ((g_PluginEnabled == false) && (GetConVarFloat(cvar_tdm_enabled) == 1.0))
	{
		return Plugin_Handled;
	}
	if (g_GameMode == 0)
	{
		CPrintToChat(client, "[{lime}Team Games{default}] Menu disabled in this mode.");
		return Plugin_Handled;
	}
	
	Menu hMenu = new Menu(Callback_Menu_Main, MENU_ACTIONS_ALL);
	char display[128];
	
	Format(display, sizeof(display), "[SoccerMod Admin] \n by Ulreth \n");
	hMenu.SetTitle(display);
	
	Format(display, sizeof(display), "End Round");
	hMenu.AddItem("end_round", display, ITEMDRAW_DEFAULT);
	Format(display, sizeof(display), "Shuffle Teams");
	hMenu.AddItem("shuffle_teams", display, ITEMDRAW_DEFAULT);
	Format(display, sizeof(display), "Move Player To Team");
	hMenu.AddItem("move_player", display, ITEMDRAW_DEFAULT);
	
	hMenu.Display(client, MENU_TIME_FOREVER);
	return Plugin_Handled;
}

public int Callback_Menu_Main(Menu hMenu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_DrawItem:
		{
			char info[32];
			int style;
			hMenu.GetItem(param2, info, sizeof(info), style);
			return style;
		}
		case MenuAction_Select:
		{
			char info[32];
			hMenu.GetItem(param2, info, sizeof(info));
			if (StrEqual(info,"end_round")) Command_EndRound(param1,0);
			else if (StrEqual(info,"shuffle_teams")) Command_ForceRandom(param1,0);
			else if (StrEqual(info,"move_player")) Menu_MovePlayer(param1,0);
		}
		case MenuAction_End:
		{
			delete hMenu;
		}
	}
 	return 0;
}

public Action Menu_MovePlayer(int client, int args)
{
	Menu hMenu = new Menu(Callback_Menu_MovePlayer, MENU_ACTIONS_ALL);
	char display[128];
	
	Format(display, sizeof(display), "[SoccerMod Admin] Move Player To Team");
	hMenu.SetTitle(display);
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			GetClientName(i, g_PlayerName[i], sizeof(g_PlayerName[]));
			if (IsPlayerRed(i) == true)
			{
				Format(display, sizeof(display), "%s (RED)", g_PlayerName[i]);
				hMenu.AddItem(g_PlayerName[i], display, ITEMDRAW_DEFAULT);
			}
			else if (IsPlayerBlue(i) == true)
			{
				Format(display, sizeof(display), "%s (BLUE)", g_PlayerName[i]);
				hMenu.AddItem(g_PlayerName[i], display, ITEMDRAW_DEFAULT);
			}
			else if ((IsPlayerRed(i) == false) && (IsPlayerBlue(i) == false))
			{
				Format(display, sizeof(display), "%s (NO TEAM)", g_PlayerName[i]);
				hMenu.AddItem(g_PlayerName[i], display, ITEMDRAW_DEFAULT);
			}
		}
	}
	
	hMenu.ExitBackButton = true;
	hMenu.Display(client, MENU_TIME_FOREVER);
	return Plugin_Handled;
}

public int Callback_Menu_MovePlayer(Menu hMenu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_DrawItem:
		{
			char info[32];
			int style;
			hMenu.GetItem(param2, info, sizeof(info), style);
			return style;
		}
		case MenuAction_Select:
		{
			char info[32];
			hMenu.GetItem(param2, info, sizeof(info));
			
			for (int i = 1; i <= MaxClients; i++)
			{
				if ((StrEqual(info, g_PlayerName[i])) && (IsClientInGame(i)))
				{
					// TRY TO CHANGE TO RED TEAM
					if (IsPlayerBlue(i) == true)
					{
						if (g_RedCount >= TEAM_MAXPLAYERS-1)
						{
							//CPrintToChat(param1, "[{lime}Team Games{default}] {fullred}RED{default} team full, invalid command.");
							CPrintToChat(param1, "%t", "red_team_full");
							Menu_MovePlayer(param1,0);
							break;
						}
						if (i == g_GK_blue)
						{
							g_GK_blue = -1;
							ExecuteNPC_GK("trigger_multiple", "blue_trigger_npc_area", "Enable");
							ExecuteNPC_GK("npc_template_maker", "template_blue_gk", "Enable");
							ExecuteNPC_GK("trigger_hurt", "blue_hurt_npc", "Disable");
							//CPrintToChatAll("[{lime}Team Games{default}] Goalkeeper position for {fullblue}BLUE{default} team is available now.");
							CPrintToChatAll("%t", "blue_team_gk_available");
						}
						RemoveFromTeam(i);
						AddPlayerToArray(i, g_RedPlayers);
						if (IsPlayerAlive(i)) ForcePlayerSuicide(i);
						//CPrintToChatAll("[{lime}Team Games{default}] %s was moved to {fullred}RED{default} team.", g_PlayerName[i]);
						CPrintToChatAll("%t", "moved_to_red", g_PlayerName[i]);
						Menu_MovePlayer(param1,0);
						break;
					}
					if (IsPlayerRed(i) == true) // TRY TO CHANGE TO BLUE TEAM
					{
						if (g_BlueCount >= TEAM_MAXPLAYERS-1)
						{
							//CPrintToChat(param1, "[{lime}Team Games{default}] {fullblue}BLUE{default} team full, invalid command.");
							CPrintToChat(param1, "%t", "blue_team_full");
							Menu_MovePlayer(param1,0);
							break;
						}
						if (i == g_GK_red)
						{
							g_GK_red = -1;
							ExecuteNPC_GK("trigger_multiple", "red_trigger_npc_area", "Enable");
							ExecuteNPC_GK("npc_template_maker", "template_red_gk", "Enable");
							ExecuteNPC_GK("trigger_hurt", "red_hurt_npc", "Disable");
							//CPrintToChatAll("[{lime}Team Games{default}] Goalkeeper position for {fullred}RED{default} team is available now.");
							CPrintToChatAll("%t", "red_team_gk_available");
						}
						RemoveFromTeam(i);
						AddPlayerToArray(i, g_BluePlayers);
						if (IsPlayerAlive(i)) ForcePlayerSuicide(i);
						//CPrintToChatAll("[{lime}Team Games{default}] %s was moved to {fullblue}BLUE{default} team.", g_PlayerName[i]);
						CPrintToChatAll("%t", "moved_to_blue", g_PlayerName[i]);
						Menu_MovePlayer(param1,0);
						break;
					}
					else
					{
						if (g_RedCount >= TEAM_MAXPLAYERS-1)
						{
							// Move to blue
							AddPlayerToArray(i, g_BluePlayers);
							//PrintToChatAll("[{lime}Team Games{default}] %s was moved to {fullblue}BLUE{default} team.", g_PlayerName[i]);
							CPrintToChatAll("%t", "moved_to_blue", g_PlayerName[i]);
						}
						if (g_BlueCount >= TEAM_MAXPLAYERS-1)
						{
							// Move to red
							AddPlayerToArray(i, g_RedPlayers);
							//CPrintToChatAll("[{lime}Team Games{default}] %s was moved to {fullred}RED{default} team.", g_PlayerName[i]);
							CPrintToChatAll("%t", "moved_to_red", g_PlayerName[i]);
						}
						else
						{
							//CPrintToChatAll("[{lime}Team Games{default}] Unable to move %s, all teams are full!", g_PlayerName[i]);
							CPrintToChatAll("%t", "unable_to_move", g_PlayerName[i]);
						}
						Menu_MovePlayer(param1,0);
						break;
					}
				}
			}
		}
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack) Menu_Main(param1, 0);
		}
		case MenuAction_End:
		{
			delete hMenu;
		}
	}
 	return 0;
}

public Action Command_Shuffle(int client, int args)
{
	if ((g_PluginEnabled == false) && (GetConVarFloat(cvar_tdm_enabled) == 1.0))
	{
		return Plugin_Continue;
	}
	// ONLY ENABLED IN SOCCERMOD
	if (g_GameMode == 0)
	{
		CPrintToChat(client, "[{lime}Team Games{default}] Randomize team function disabled in this game mode.");
		return Plugin_Continue;
	}
	// ONLY ENABLED DURING MATCH
	if (g_Warmup == true)
	{
		CPrintToChat(client, "[{lime}Team Games{default}] Function disabled in warmup time.");
		return Plugin_Continue;
	}
	// CHECKS IF PLAYER ALREADY VOTED
	for (int i = 1; i <= MaxClients; i++)
	{
		if (client == g_VotingPlayers[i])
		{
			//CPrintToChat(client, "[{lime}Team Games{default}] You already voted to shuffle teams.");
			CPrintToChat(client, "%t", "already_vote_shuffle");
			return Plugin_Continue;
		}
	}
	// REGISTERS THEIR VOTE
	for (int i = 1; i <= MaxClients; i++)
	{
		// SEARCH FOR A FREE SPACE IN ARRAY
		if (g_VotingPlayers[i] == -1)
		{
			g_VotingPlayers[i] = client;
			g_VotingCount = (g_VotingCount + 1);
			//CPrintToChatAll("[{lime}Team Games{default}] +1 votes to randomize teams --- Total votes = (+%d)", g_VotingCount);
			CPrintToChatAll("%t", "voted_to_shuffle", g_VotingCount);
			ClientCommand(client, SOUND_WARNING_BELL);
			break;
		}
	}
	// CHECK IF AMOUNT OF VOTES IS ENOUGH
	if (g_VotingCount >= RoundToCeil(float(g_PlayerCount)/2.0))
	{
		MatchVariablesZero();
		for (int i = 1; i <= MaxClients; i++)
		{
			ClientCommand(i, SOUND_WARNING);
			g_VotingPlayers[i] = -1;
		}
		ForceRoundEnd();
		//CPrintToChatAll("[{lime}Team Games{default}] Votes acquired! Shuffling teams and restarting match!");
		CPrintToChatAll("%t", "enough_votes_shuffle");
		PrintCenterTextAll("Match restart! New teams will be created...");
		//EmitSoundToAll(SOUND_WARNING);
	}
	return Plugin_Continue;
}

public Action Command_ForceRandom(int client, int args)
{
	if ((g_PluginEnabled == false) && (GetConVarFloat(cvar_tdm_enabled) == 1.0))
	{
		return Plugin_Continue;
	}
	// ONLY ENABLED IN SOCCERMOD
	if (g_GameMode == 0)
	{
		CPrintToChat(client, "[{lime}Team Games{default}] Randomize team function disabled in this game mode.");
		return Plugin_Continue;
	}
	// ONLY ENABLED DURING MATCH
	if (g_Warmup == true)
	{
		CPrintToChat(client, "[{lime}Team Games{default}] Function disabled in warmup time.");
		return Plugin_Continue;
	}
	MatchVariablesZero();
	for (int i = 1; i <= MaxClients; i++)
	{
		g_VotingPlayers[i] = -1;
	}
	ForceRoundEnd();
	CPrintToChatAll("[{lime}Team Games{default}] Admin restarted match and randomized teams.");
	PrintCenterTextAll("Match restart! New teams will be created...");
	return Plugin_Continue;
}

public Action Command_GK(int client, int args)
{
	if ((g_PluginEnabled == false) && (GetConVarFloat(cvar_tdm_enabled) == 1.0))
	{
		return Plugin_Continue;
	}
	if (IsPlayerAlive(client) == false)
	{
		//CPrintToChat(client, "[{lime}Team Games{default}] You must be alive to be goalkeeper.");
		CPrintToChat(client, "%t", "you_must_alive_gk");
		return Plugin_Continue;
	}
	if (g_GameMode == 0)
	{
		//CPrintToChat(client, "[{lime}Team Games{default}] Goalkeeper disabled in this game mode.");
		CPrintToChat(client, "%t", "gk_disabled_mode");
		return Plugin_Continue;
	}
	if ((g_GK_red == client) || (g_GK_blue == client))
	{
		Command_GK_Disable(client, 0);
		return Plugin_Continue;
	}
	if ((IsPlayerRed(client) == true) && (g_GK_red != -1))
	{
		//CPrintToChat(client, "[{lime}Team Games{default}] You cannot be goalkeeper, there is one already in {fullred}red{default} team.");
		CPrintToChat(client, "%t", "gk_already_full_red");
		return Plugin_Continue;
	}
	if ((IsPlayerBlue(client) == true) && (g_GK_blue != -1))
	{
		//CPrintToChat(client, "[{lime}Team Games{default}] You cannot be goalkeeper, there is one already in {fullblue}blue{default} team.");
		CPrintToChat(client, "%t", "gk_already_full_blue");
		return Plugin_Continue;
	}
	char client_name[64];
	GetClientName(client, client_name, sizeof(client_name));
	if (IsPlayerRed(client) == true)
	{
		g_GK_red = client;
		ExecuteNPC_GK("trigger_multiple", "red_trigger_npc_area", "Disable");
		ExecuteNPC_GK("npc_template_maker", "template_red_gk", "Disable");
		ExecuteNPC_GK("trigger_hurt", "red_hurt_npc", "Enable");
		//SetEntityHealth(client, 1000);
		//CPrintToChat(client, "[{lime}Team Games{default}] You are now the goalkeeper of {fullred}RED{default} team, protected from ball damage");
		CPrintToChat(client, "%t", "you_are_gk_red");
		//EmitSoundToClient(client, SOUND_KLAXON);
		ClientCommand(client, SOUND_KLAXON);
		//CPrintToChatAll("[{lime}Team Games{default}] %s is now the goalkeeper of {fullred}RED{default} team", client_name);
		CPrintToChatAll("%t", "gk_announce_red", client_name);
	}
	else if (IsPlayerBlue(client) == true)
	{
		g_GK_blue = client;
		ExecuteNPC_GK("trigger_multiple", "blue_trigger_npc_area", "Disable");
		ExecuteNPC_GK("npc_template_maker", "template_blue_gk", "Disable");
		ExecuteNPC_GK("trigger_hurt", "blue_hurt_npc", "Enable");
		//SetEntityHealth(client, 1000);
		//CPrintToChat(client, "[{lime}Team Games{default}] You are now the goalkeeper of {fullblue}BLUE{default} team, protected from ball damage");
		CPrintToChat(client, "%t", "you_are_gk_blue");
		//EmitSoundToClient(client, SOUND_KLAXON);
		ClientCommand(client, SOUND_KLAXON);
		//CPrintToChatAll("[{lime}Team Games{default}] %s is now the goalkeeper of {fullblue}BLUE{default} team", client_name);
		CPrintToChatAll("%t", "gk_announce_blue", client_name);
	}
	return Plugin_Continue;
}
	
void ExecuteNPC_GK(char[] classname, char[] trigger_name, char[] input)
{
	// REMOVE NPC GKs
	int ent_t = -1;
	char tr_name[32];
	while ((ent_t = FindEntityByClassname(ent_t, classname)) != -1)
	{
		GetEntPropString(ent_t, Prop_Data, "m_iName", tr_name, sizeof(tr_name));
		if (StrEqual(tr_name, trigger_name, true))
		{
			AcceptEntityInput(ent_t, input);
			break;
		}
	}
}

public Action Command_GK_Disable(int client, int args)
{
	if ((g_PluginEnabled == false) && (GetConVarFloat(cvar_tdm_enabled) == 1.0))
	{
		return Plugin_Continue;
	}
	if (g_GameMode == 0)
	{
		//CPrintToChat(client, "[{lime}Team Games{default}] Goalkeeper disabled in this game mode.");
		CPrintToChat(client, "%t", "gk_disabled_mode");
		return Plugin_Continue;
	}
	if (g_GK_red == client)
	{
		g_GK_red = -1;
		ExecuteNPC_GK("trigger_multiple", "red_trigger_npc_area", "Enable");
		ExecuteNPC_GK("npc_template_maker", "template_red_gk", "Enable");
		ExecuteNPC_GK("trigger_hurt", "red_hurt_npc", "Disable");
		//SetEntityHealth(client, 200);
		//EmitSoundToClient(client, SOUND_ELEV_BELL);
		ClientCommand(client, SOUND_ELEV_BELL);
		//CPrintToChatAll("[{lime}Team Games{default}] Goalkeeper position for {fullred}RED{default} team is available now.");
		CPrintToChatAll("%t", "red_team_gk_available");
	}
	else if (g_GK_blue == client)
	{
		g_GK_blue = -1;
		ExecuteNPC_GK("trigger_multiple", "blue_trigger_npc_area", "Enable");
		ExecuteNPC_GK("npc_template_maker", "template_blue_gk", "Enable");
		ExecuteNPC_GK("trigger_hurt", "blue_hurt_npc", "Disable");
		//SetEntityHealth(client, 200);
		//EmitSoundToClient(client, SOUND_ELEV_BELL);
		ClientCommand(client, SOUND_ELEV_BELL);
		//CPrintToChatAll("[{lime}Team Games{default}] Goalkeeper position for {fullblue}BLUE{default} team is available now.");
		CPrintToChatAll("%t", "blue_team_gk_available");
	}
	return Plugin_Continue;
}

public Action Command_Red(int client, int args)
{
	if ((g_PluginEnabled == false) && (GetConVarFloat(cvar_tdm_enabled) == 1.0))
	{
		return Plugin_Continue;
	}
	// ONLY ALLOWED IN CERTAIN GAME MODES
	if (g_GameMode == 0)
	{
		CPrintToChat(client, "[{lime}Team Games{default}] Team change disabled in this mode.");
		return Plugin_Continue;
	}
	// AVOIDS JOINING SAME TEAM AGAIN
	if (IsPlayerRed(client) == true)
	{
		//CPrintToChat(client, "[{lime}Team Games{default}] Invalid action, you currently belong to {fullred}RED{default} team.");
		CPrintToChat(client, "%t", "invalid_team_red");
		return Plugin_Continue;
	}
	// AVOID TEAM UNBALANCE
	if (g_RedCount >= g_BlueCount)
	{
		//CPrintToChat(client, "[{lime}Team Games{default}] You cannot change team unless your current team has more players than enemy team.");
		CPrintToChat(client, "%t", "invalid_team_balance_change");
		return Plugin_Continue;
	}
	// AVOIDS JOINING FULL TEAM
	if (g_RedCount >= TEAM_MAXPLAYERS-1)
	{
		//CPrintToChat(client, "[{lime}Team Games{default}] {fullred}RED{default} team full, invalid command.");
		CPrintToChat(client, "%t", "red_team_full");
		return Plugin_Continue;
	}
	if (g_PlayerMenuCooldown[client] > 0)
	{
		float cooldown = float(g_PlayerMenuCooldown[client])/10.0;
		//CPrintToChat(client, "[{lime}Team Games{default}] You must wait {yellow}%0.1f{default} seconds to change your team.", cooldown);
		CPrintToChat(client, "%t", "team_change_cooldown", cooldown);
		return Plugin_Continue;
	}
	if (client == g_GK_blue)
	{
		g_GK_blue = -1;
		ExecuteNPC_GK("trigger_multiple", "blue_trigger_npc_area", "Enable");
		ExecuteNPC_GK("npc_template_maker", "template_blue_gk", "Enable");
		ExecuteNPC_GK("trigger_hurt", "blue_hurt_npc", "Disable");
		//CPrintToChatAll("[{lime}Team Games{default}] Goalkeeper position for {fullblue}BLUE{default} team is available now.");
		CPrintToChatAll("%t", "blue_team_gk_available");
	}
	else if (client == g_GK_red)
	{
		g_GK_red = -1;
		ExecuteNPC_GK("trigger_multiple", "red_trigger_npc_area", "Enable");
		ExecuteNPC_GK("npc_template_maker", "template_red_gk", "Enable");
		ExecuteNPC_GK("trigger_hurt", "red_hurt_npc", "Disable");
		//CPrintToChatAll("[{lime}Team Games{default}] Goalkeeper position for {fullred}RED{default} team is available now.");
		CPrintToChatAll("%t", "red_team_gk_available");
	}
	g_PlayerMenuCooldown[client] = RoundToNearest(GetConVarFloat(cvar_tdm_command_cd)*10.0); // 30 seconds CD
	RemoveFromTeam(client);
	AddPlayerToArray(client, g_RedPlayers);
	//EmitSoundToClient(client, SOUND_SURV_ALARM);
	ClientCommand(client, SOUND_SURV_ALARM);
	if (IsPlayerAlive(client)) ForcePlayerSuicide(client);
	char client_name[64];
	GetClientName(client, client_name, sizeof(client_name));
	CPrintToChat(client, "[{lime}Team Games{default}] Switched to {fullred}RED{default} team");
	//CPrintToChatAll("[{lime}Team Games{default}] %s has joined {fullred}RED{default} team.", client_name);
	CPrintToChatAll("%t", "joined_red_team", client_name);
	return Plugin_Continue;
}

public Action Command_Blue(int client, int args)
{
	if ((g_PluginEnabled == false) && (GetConVarFloat(cvar_tdm_enabled) == 1.0))
	{
		return Plugin_Continue;
	}
	// ONLY ALLOWED IN CERTAIN GAME MODES
	if (g_GameMode == 0)
	{
		CPrintToChat(client, "[{lime}Team Games{default}] Team change disabled in this mode.");
		return Plugin_Continue;
	}
	// AVOIDS JOINING SAME TEAM AGAIN
	if (IsPlayerBlue(client) == true)
	{
		//CPrintToChat(client, "[{lime}Team Games{default}] Invalid action, you currently belong to {fullblue}BLUE{default} team.");
		CPrintToChat(client, "%t", "invalid_team_blue");
		return Plugin_Continue;
	}
	// AVOID TEAM UNBALANCE
	if (g_BlueCount >= g_RedCount)
	{
		//CPrintToChat(client, "[{lime}Team Games{default}] You cannot change team unless your current team has more players than enemy team.");
		CPrintToChat(client, "%t", "invalid_team_balance_change");
		return Plugin_Continue;
	}
	// AVOIDS JOINING FULL TEAM
	if (g_BlueCount >= TEAM_MAXPLAYERS-1)
	{
		//CPrintToChat(client, "[{lime}Team Games{default}] {fullblue}BLUE{default} team full, invalid command.");
		CPrintToChat(client, "%t", "blue_team_full");
		return Plugin_Continue;
	}
	if (g_PlayerMenuCooldown[client] > 0)
	{
		float cooldown = float(g_PlayerMenuCooldown[client])/10.0;
		//CPrintToChat(client, "[{lime}Team Games{default}] You must wait {fullred}%0.1f{default} seconds to change your team.", cooldown);
		CPrintToChat(client, "%t", "team_change_cooldown", cooldown);
		return Plugin_Continue;
	}
	if (client == g_GK_blue)
	{
		g_GK_blue = -1;
		ExecuteNPC_GK("trigger_multiple", "blue_trigger_npc_area", "Enable");
		ExecuteNPC_GK("npc_template_maker", "template_blue_gk", "Enable");
		ExecuteNPC_GK("trigger_hurt", "blue_hurt_npc", "Disable");
		//CPrintToChatAll("[{lime}Team Games{default}] Goalkeeper position for {fullblue}BLUE{default} team is available now.");
		CPrintToChatAll("%t", "blue_team_gk_available");
	}
	else if (client == g_GK_red)
	{
		g_GK_red = -1;
		ExecuteNPC_GK("trigger_multiple", "red_trigger_npc_area", "Enable");
		ExecuteNPC_GK("npc_template_maker", "template_red_gk", "Enable");
		ExecuteNPC_GK("trigger_hurt", "red_hurt_npc", "Disable");
		//CPrintToChatAll("[{lime}Team Games{default}] Goalkeeper position for {fullred}RED{default} team is available now.");
		CPrintToChatAll("%t", "red_team_gk_available");
	}
	g_PlayerMenuCooldown[client] = RoundToNearest(GetConVarFloat(cvar_tdm_command_cd)*10.0); // 30 seconds CD
	RemoveFromTeam(client);
	AddPlayerToArray(client, g_BluePlayers);
	//EmitSoundToClient(client, SOUND_SURV_ALARM);
	ClientCommand(client, SOUND_SURV_ALARM);
	if (IsPlayerAlive(client)) ForcePlayerSuicide(client);
	char client_name[64];
	GetClientName(client, client_name, sizeof(client_name));
	CPrintToChat(client, "[{lime}Team Games{default}] Switched to {fullblue}BLUE{default} team");
	//CPrintToChatAll("[{lime}Team Games{default}] %s has joined {fullblue}BLUE{default} team.", client_name);
	CPrintToChatAll("%t", "joined_blue_team", client_name);
	return Plugin_Continue;
}

public Action Command_EndRound(int client, int args)
{
	if ((g_PluginEnabled == false) && (GetConVarFloat(cvar_tdm_enabled) == 1.0))
	{
		return Plugin_Continue;
	}
	ForceRoundEnd();
	return Plugin_Continue;
}

public Action Event_PlayerJoin(Event event, const char[] name, bool no_broadcast)
{
	if ((g_PluginEnabled == false) && (GetConVarFloat(cvar_tdm_enabled) == 1.0))
	{
		return Plugin_Continue;
	}
	int client = event.GetInt("index");
	CreateTimer(0.2, Timer_PlayerSpawn, client);
	return Plugin_Continue;
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool no_broadcast)
{
	if ((g_PluginEnabled == false) && (GetConVarFloat(cvar_tdm_enabled) == 1.0))
	{
		return Plugin_Continue;
	}
	int userid = event.GetInt("userid");
	int client = GetClientOfUserId(userid);
	CreateTimer(0.2, Timer_PlayerSpawn, client);
	return Plugin_Continue;
}

public Action Timer_PlayerSpawn(Handle timer, any client)
{
	if (client > 0)
	{
		if (IsClientInGame(client))
		{
			if (IsPlayerAlive(client))
			{
				char client_name[64];
				GetClientName(client, client_name, sizeof(client_name));
				// AT SPAWN WILL CHECK IF PLAYER CAN BE ADDED TO A TEAM
				// CHECK IF POSSIBLE TO ADD TO RED TEAM
				// MORE ACTIONS AFTER CHECKING TEAM
				if (IsPlayerRed(client) == true)
				{
					DispatchKeyValue(client, "glowable", "1"); 
					DispatchKeyValue(client, "glowblip", "1");
					DispatchKeyValue(client, "glowcolor", "255 0 0");
					DispatchKeyValue(client, "glowdistance", "9999");
					AcceptEntityInput(client, "enableglow");
					SetEntityRenderColor(client, 255, 92, 92, 255);
					if (g_GameMode == 1)
					{
						TeleportBackRed(client);
					}
					return Plugin_Continue;
				}
				else if (IsPlayerBlue(client) == true)
				{
					DispatchKeyValue(client, "glowable", "1"); 
					DispatchKeyValue(client, "glowblip", "1");
					DispatchKeyValue(client, "glowcolor", "0 0 255");
					DispatchKeyValue(client, "glowdistance", "9999");
					AcceptEntityInput(client, "enableglow");
					SetEntityRenderColor(client, 92, 92, 255, 255);
					if (g_GameMode == 1)
					{
						TeleportBackBlue(client);
					}
					return Plugin_Continue;
				}
				if (g_GameMode == 1)
				{
					if ((g_RedCount < (TEAM_MAXPLAYERS-1)) && (g_RedCount <= g_BlueCount))
					{
						RemoveFromTeam(client);
						AddPlayerToArray(client, g_RedPlayers);
						//CPrintToChatAll("[{lime}Team Games{default}] %s has joined {fullred}RED{default} team.", client_name);
						CPrintToChatAll("%t", "joined_red_team", client_name);
					}
					else if ((g_BlueCount < (TEAM_MAXPLAYERS-1)) && (g_BlueCount < g_RedCount))
					{
						// CHECK IF POSSIBLE TO ADD TO BLUE TEAM
						RemoveFromTeam(client);
						AddPlayerToArray(client, g_BluePlayers);
						//CPrintToChatAll("[{lime}Team Games{default}] %s has joined {fullblue}BLUE{default} team.", client_name);
						CPrintToChatAll("%t", "joined_blue_team", client_name);
					}
				}
			}
		}
	}
	return Plugin_Continue;
}

public void OnClientDisconnect(int client)
{
	if (g_PluginEnabled == true)
	{
		SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage_SDK);
		RemoveFromTeam(client);
	}
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	if ((g_PluginEnabled == false) && (GetConVarFloat(cvar_tdm_enabled) == 1.0)) return;
	
	//g_RoundStart = false;
	if (g_Warmup == true)
	{
		g_Warmup = false;
	}
	g_PlayerCount = 0;
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsPlayerAlive(i))
		{
			g_PlayerCount = (g_PlayerCount + 1);
		}
	}
	// REMOVE NPCs FROM GOAL IF THERE IS ANY GK ACTIVE
	if (g_GK_red > 0)
	{
		ExecuteNPC_GK("trigger_multiple", "red_trigger_npc_area", "Disable");
		ExecuteNPC_GK("npc_template_maker", "template_red_gk", "Disable");
		ExecuteNPC_GK("trigger_hurt", "red_hurt_npc", "Enable");
		ExecuteNPC_GK("npc_nmrih_runnerzombie", "npc_gk_red", "Kill");
	}
	if (g_GK_blue > 0)
	{
		ExecuteNPC_GK("trigger_multiple", "blue_trigger_npc_area", "Disable");
		ExecuteNPC_GK("npc_template_maker", "template_blue_gk", "Disable");
		ExecuteNPC_GK("trigger_hurt", "blue_hurt_npc", "Enable");
		ExecuteNPC_GK("npc_nmrih_runnerzombie", "npc_gk_blue", "Kill");
	}
	// GET BALL LOCATION AND REFERENCE
	if (g_GameMode == 1)
	{
		int ball0 = -1;
		char ball0_name[64];
		while ((ball0 = FindEntityByClassname(ball0, "prop_physics")) != -1)
		{
			GetEntPropString(ball0, Prop_Data, "m_iName", ball0_name, sizeof(ball0_name));
			if (StrEqual(ball0_name, "pelota0", false))
			{
				//GetEntPropVector(ball0, Prop_Data, "m_vecOrigin", g_SoccerBall_pos);
				GetEntityAbsOrigin(ball0, g_SoccerBall_pos);
				g_SoccerBall = EntIndexToEntRef(ball0);
				break;
			}
		}
		// CLEAN SOME EXTRA WELDERS
		RemoveExtraWelders();
		CPrintToChatAll("%t", "round_start_announce");
	}
	// FINAL PRINT
	if (GetConVarFloat(cvar_tdm_debug) == 1.0) CPrintToChatAll("[{lime}Team Games{default}] %i players in-game.", g_PlayerCount);
	if (GetConVarFloat(cvar_tdm_debug) == 1.0) CPrintToChatAll("[{lime}Team Games{default}] %i players in {fullblue}BLUE{default} team.", g_BlueCount);
	if (GetConVarFloat(cvar_tdm_debug) == 1.0) CPrintToChatAll("[{lime}Team Games{default}] %i players in {fullred}RED{default} team.", g_RedCount);
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	if ((g_PluginEnabled == false) && (GetConVarFloat(cvar_tdm_enabled) == 1.0)) return;
	int client = GetClientOfUserId(event.GetInt("userid"));

	char client_name[64];
	GetClientName(client, client_name, sizeof(client_name));
	
	switch (g_GameMode)
	{
		case 0:
		{
			RemoveFromTeam(client);
			// COUNTS LIVING PLAYERS AND EXECUTE EXTRACTION
			if (g_ExtractionStarted == false)
			{
				if ((g_RedCount == 0) && (g_BlueCount > 0))
				{
					ForceExtractTeam(g_BluePlayers);
					g_BlueScore = (g_BlueScore + 1);
					//CPrintToChatAll("[{lime}Team Games{default}] All members of {fullred}RED{default} team died!");
					CPrintToChatAll("%t", "all_red_died");
					//CPrintToChatAll("[{lime}Team Games{default}] {fullblue}BLUE{default} team {gold}wins{default} the round!");
					CPrintToChatAll("%t", "blue_team_wins");
					PrintCenterTextAll("%t", "blue_team_center_wins");
				}
				else if ((g_BlueCount == 0) && (g_RedCount > 0))
				{
					// SAME FOR OTHER TEAM
					ForceExtractTeam(g_RedPlayers);
					g_RedScore = (g_RedScore + 1);
					//CPrintToChatAll("[{lime}Team Games{default}] All members of {fullblue}BLUE{default} team died!");
					CPrintToChatAll("%t", "all_blue_died");
					//CPrintToChatAll("[{lime}Team Games{default}] {fullred}RED{default} team {gold}wins{default} the round!");
					CPrintToChatAll("%t", "red_team_wins");
					PrintCenterTextAll("%t", "red_team_center_wins");
				}
			}
		}
		case 1:
		{
			AcceptEntityInput(client, "disableglow");
		}
	}
}

public void Event_ExtractionBegin(Event event, const char[] name, bool dontBroadcast)
{
	if ((g_PluginEnabled == false) && (GetConVarFloat(cvar_tdm_enabled) == 1.0)) return;
	//g_ExtractionStarted = true;
	CreateTimer(2.0, Timer_ExtractionStart);
}

public Action Timer_ExtractionStart(Handle timer)
{
	g_ExtractionStarted = true;
	return Plugin_Continue;
}

public void Event_ResetVariables(Event event, const char[] name, bool dontBroadcast)
{
	if ((g_PluginEnabled == false) && (GetConVarFloat(cvar_tdm_enabled) == 1.0)) return;
	VariablesToZero();
}

public void Event_PracticeStart(Event event, const char[] name, bool dontBroadcast)
{
	if ((g_PluginEnabled == false) && (GetConVarFloat(cvar_tdm_enabled) == 1.0)) return;
	g_RedScore = 0;
	g_BlueScore = 0;
	g_Warmup = true;
	//g_RoundStart = false;
	SearchSpawns();
}

public void Event_ResetMap(Event event, const char[] name, bool dontBroadcast)
{
	if ((g_PluginEnabled == false) && (GetConVarFloat(cvar_tdm_enabled) == 1.0)) return;
	//g_RoundStart = true;
	VariablesToZero();
}

// BALL TAKE DAMAGE EVENT
/*
public void PropTakeDamage(const char[] output, int caller, int activator, float delay)
{
	if (caller == EntRefToEntIndex(g_SoccerBall))
	{
		if (IsValidEntity(EntRefToEntIndex(g_TriggerBall)))
		{
			g_bStop_Cooldown = true;
			g_Timer_CooldownCount = 0;
		}
	}
}
*/
void ForceExtractTeam(const int[] team)
{
	int ent = -1;
	while (((ent = FindEntityByClassname(ent, "nmrih_objective_boundary")) != -1) && (g_ExtractionStarted == false))
	{
		if (IsValidEntity(ent))
		{
			AcceptEntityInput(ent, "ObjectiveComplete");
		}
	}
	
	// NEW FAST TELEPORT MODE
	if (GetConVarFloat(cvar_tdm_insta_extract) == 1.0)
	{
		// 1 = Red team | 2 = Blue team
		for (int i = 1; i <= MaxClients; i++)
		{
			if (team[i] > 0)
			{
				if (IsClientInGame(team[i]))
				{
					// TESTING IF DEAD PLAYERS CAN ALSO BE EXTRACTED
					//if (IsPlayerAlive(team[i])) ServerCommand("extractplayer %d", GetClientUserId(team[i]));
					ServerCommand("extractplayer %d", GetClientUserId(team[i]));
				}
			}
		}
		return;
	}
	
	// AUTOMATIC TELEPORT TO EXTRACTION ZONE
	if (g_GameMode == 0)
	{
		ent = -1;
		while (((ent = FindEntityByClassname(ent, "func_nmrih_extractionzone")) != -1) && (g_ExtractionStarted == false))
		{
			if (IsValidEntity(ent))
			{
				//AcceptEntityInput(ent, "Start");
				float ent_origin[3];
				//GetEntPropVector(ent, Prop_Data, "m_vecOrigin", ent_origin);
				GetEntityAbsOrigin(ent, ent_origin);
				ent_origin[2] += 32.0;
				Handle trace;
				trace = TR_TraceRayEx(ent_origin, {90.0, 0.0, 0.0}, MASK_SHOT_HULL, RayType_Infinite);
				float target_pos[3];
				if(TR_DidHit(trace))
				{
					TR_GetEndPosition(target_pos, trace);
					target_pos[2] += 32.0;
				}
				CloseHandle(trace);
				for (int i = 1; i <= MaxClients; i++)
				{
					if (team[i] != -1)
					{
						if (IsClientInGame(team[i]))
						{
							if (IsPlayerAlive(team[i])) TeleportEntity(team[i], target_pos, NULL_VECTOR, NULL_VECTOR);
							else ServerCommand("extractplayer %d", GetClientUserId(team[i]));
						}
					}
				}
			}
		}
	}
}

bool ForceRoundEnd()
{
	int state = GetGameStateEntity();
	if(IsValidEntity(state))
		return AcceptEntityInput(state, "RestartRound");
	return false;
}

int GetGameStateEntity()
{
	int nmrih_game_state = -1;
	while((nmrih_game_state = FindEntityByClassname(nmrih_game_state, "nmrih_game_state")) != -1)
		return nmrih_game_state;
	nmrih_game_state = CreateEntityByName("nmrih_game_state");
	if(IsValidEntity(nmrih_game_state) && DispatchSpawn(nmrih_game_state))
		return nmrih_game_state;
	return -1;
}
	
void KillTeam(const int[] team)
{
	// Loop through players and kill them
	for (int i = 1; i <= MaxClients; i++)
	{
		if (team[i] > 0)
		{
			if (IsClientInGame(team[i]))
			{
				if (IsPlayerAlive(team[i]))
				{
					ForcePlayerSuicide(team[i]);
				}
			}
		}
	}
	// REMOVES PLAYER RESPAWN POINTS
	int ent = -1;
	int j = 0;
	char ent_name[64];
	while (((ent = FindEntityByClassname(ent,"info_player_nmrih")) != -1) && (j < 8))
	{
		GetEntPropString(ent, Prop_Data, "m_iName", ent_name, sizeof(ent_name));
		if ((StrEqual(ent_name, "t_player", true)) || (StrEqual(ent_name, "ct_player", true)))
		{
			AcceptEntityInput(ent, "Kill");
			j = (j+1);
		}
	}
}

void TeleportBackRed(int client)
{
	//float client_angles[3];
	float client_eye_pos[3];
	float resultant[3];
	float angles[3];
	// ALGEBRA TO FACE TRUE TARGET
	
	//GetClientEyeAngles(client, client_angles);
	GetClientEyePosition(client, client_eye_pos);
	MakeVectorFromPoints(g_OriginBlue, client_eye_pos, resultant);
	GetVectorAngles(resultant, angles);
	angles[0] = 0.0;
	angles[1] -= 180;
	//angles[2] = client_angles[2];
	
	// TELEPORTS RED PLAYER (OR GK) TO BASE
	if (client == g_GK_red)
	{
		float dest_gk_location[3];
		dest_gk_location[0] = (g_OriginRed[0] + g_Origin_Red_Goal[0])/2.0;
		dest_gk_location[1] = (g_OriginRed[1] + g_Origin_Red_Goal[1])/2.0;
		dest_gk_location[2] = (g_OriginRed[2] + g_Origin_Red_Goal[2])/2.0;
		TeleportEntity(client, dest_gk_location, angles, NULL_VECTOR);
		//CPrintToChat(client, "[{lime}Team Games{default}] You spawned as {fullred}RED GOALKEEPER{default} inside your goal!");
		CPrintToChat(client, "%t", "spawned_as_red_gk");
	}
	else
	{
		if (g_LastScore == 2)
		{
			float new_pos[3];
			new_pos[0] = (g_OriginRed[0] + g_SoccerBall_origin[0])/2.0;
			new_pos[1] = (g_OriginRed[1] + g_SoccerBall_origin[1])/2.0;
			new_pos[2] = g_OriginRed[2];
			
			// Only 1 player will spawn near ball
			g_LastScore = 0;
			TeleportEntity(client, new_pos, angles, NULL_VECTOR);
			//CPrintToChat(client, "[{lime}Team Games{default}] You spawned near the ball, use the {fullred}kick-off{default} wisely!");
			CPrintToChat(client, "%t", "spawned_near_ball_red");
		}
		else
		{
			TeleportEntity(client, g_OriginRed, angles, NULL_VECTOR);
		}
	}
	LookAtTarget(client, g_SoccerBall);
	SpawnWelderForClient(client);
}

void TeleportBackBlue(int client)
{
	//float client_angles[3];
	float client_eye_pos[3];
	float resultant[3];
	float angles[3];
	
	// ALGEBRA TO FACE TRUE TARGET
	//GetClientEyeAngles(client, client_angles);
	GetClientEyePosition(client, client_eye_pos);
	MakeVectorFromPoints(g_OriginRed, client_eye_pos, resultant);
	GetVectorAngles(resultant, angles);
	angles[0] = 0.0;
	angles[1] -= 180;
	//angles[2] = client_angles[2];
	
	// TELEPORTS BLUE PLAYER TO BASE
	if (client == g_GK_blue)
	{
		float dest_gk_location[3];
		dest_gk_location[0] = (g_OriginBlue[0] + g_Origin_Blue_Goal[0])/2.0;
		dest_gk_location[1] = (g_OriginBlue[1] + g_Origin_Blue_Goal[1])/2.0;
		dest_gk_location[2] = (g_OriginBlue[2] + g_Origin_Blue_Goal[2])/2.0;
		TeleportEntity(client, dest_gk_location, angles, NULL_VECTOR);
		//CPrintToChat(client, "[{lime}Team Games{default}] You spawned as {fullblue}BLUE GOALKEEPER{default} inside your goal!");
		CPrintToChat(client, "%t", "spawned_as_blue_gk");
	}
	else
	{
		if (g_LastScore == 1)
		{
			float new_pos[3];
			new_pos[0] = (g_OriginBlue[0] + g_SoccerBall_origin[0])/2.0;
			new_pos[1] = (g_OriginBlue[1] + g_SoccerBall_origin[1])/2.0;
			new_pos[2] = g_OriginBlue[2];
			
			// Only 1 player will spawn near ball
			g_LastScore = 0;
			TeleportEntity(client, new_pos, angles, NULL_VECTOR);
			//CPrintToChat(client, "[{lime}Team Games{default}] You spawned near the ball, use the {fullblue}kick-off{default} wisely!");
			CPrintToChat(client, "%t", "spawned_near_ball_blue");
		}
		else
		{
			TeleportEntity(client, g_OriginBlue, angles, NULL_VECTOR);
		}
	}
	LookAtTarget(client, g_SoccerBall);
	SpawnWelderForClient(client);
}

void SpawnWelderForClient(int client)
{
	if (!IsClientInGame(client))
	{
		return;
	}
	if (!IsPlayerAlive(client))
	{
		return;
	}
    // CREATES A WELDER
	int welder = CreateEntityByName("tool_welder");
	if (welder != -1)
    {
        // MOVE THE WELDER TO CLIENT POSITION
        float origin[3];
        GetClientEyePosition(client, origin);
        DispatchKeyValueVector(welder, "origin", origin);

        // SPAWN THE WELDER
        if (DispatchSpawn(welder))
        {
            AcceptEntityInput(welder, "Use", client, client);
        }
    }
}

public void VariablesToZero()
{
	g_ExtractionStarted = false;
	switch (g_GameMode)
	{
		// Classic TDM
		case 0:
		{
			g_PlayerCount = 0;
			g_BlueCount = 0;
			g_RedCount = 0;
			for (int i = 1; i <= MaxClients; i++)
			{
				g_BluePlayers[i] = -1;
				g_RedPlayers[i] = -1;
			}
		}
		// SoccerMod
		case 1:
		{
			g_Ball_Owner = -1;
			g_Ball_Shooter = -1;
			g_Ball_Passer = -1;
			g_bStop_Cooldown = false;
			g_MI_trail = PrecacheModel("materials/trails/beam_01.vmt");
			//g_MI_trail = PrecacheModel("materials/sprites/laserbeam.vmt");
		}
	}
}

void MatchVariablesZero()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		g_VotingPlayers[i] = -1;
		g_BluePlayers[i] = -1;
		g_RedPlayers[i] = -1;
		//RemoveHat(i);
	}
	g_RedScore = 0;
	g_BlueScore = 0;
	g_GK_red = -1;
	g_GK_blue = -1;
	g_PlayerCount = 0;
	g_VotingCount = 0;
	g_LastScore = 0;
	Format(sMessageColor_Red, sizeof(sMessageColor_Red), "255 0 0");
	Format(sMessageColor_Blue, sizeof(sMessageColor_Blue), "0 0 255");
	Format(sMessageEffect, sizeof(sMessageEffect), "2");
	Format(sMessageChannel, sizeof(sMessageChannel), "4");
	Format(sMessagePosX, sizeof(sMessagePosX), "0.8");
	Format(sMessagePosY, sizeof(sMessagePosY), "0.1");
	Format(sMessageFadeIn, sizeof(sMessageFadeIn), "0.1");
	Format(sMessageFadeOut, sizeof(sMessageFadeOut), "0.1");
	Format(sMessageHoldTime, sizeof(sMessageHoldTime), "9.0");
	Format(sMessage_RedTeam, sizeof(sMessage_RedTeam), "%t", "red_team_game_text");
	Format(sMessage_BlueTeam, sizeof(sMessage_BlueTeam), "%t", "blue_team_game_text");
	Format(sMessage_RedGK, sizeof(sMessage_RedGK), "%t", "red_gk_game_text");
	Format(sMessage_BlueGK, sizeof(sMessage_BlueGK), "%t", "blue_gk_game_text");
}

public void AddPlayerToArray(int client, int[] array)
{
	// USAGE
	// AddPlayerToArray(client, g_BluePlayers);
	if (client < 1) return;
	// SEARCH A FREE SLOT INSIDE ARRAY
	
	// ADDS CLIENT INDEX TO ARRAY
	array[client] = client;
	if (IsPlayerRed(client))
	{
		g_RedCount++;
		DispatchKeyValue(client, "glowable", "1"); 
		DispatchKeyValue(client, "glowblip", "1");
		DispatchKeyValue(client, "glowcolor", "255 0 0");
		DispatchKeyValue(client, "glowdistance", "9999");
		AcceptEntityInput(client, "enableglow");
	}
	else if (IsPlayerBlue(client))
	{
		g_BlueCount++;
		DispatchKeyValue(client, "glowable", "1"); 
		DispatchKeyValue(client, "glowblip", "1");
		DispatchKeyValue(client, "glowcolor", "0 0 255");
		DispatchKeyValue(client, "glowdistance", "9999");
		AcceptEntityInput(client, "enableglow");
	}
}

void RemoveFromTeam(int client)
{
	if (g_RedPlayers[client] == client)
	{
		g_RedPlayers[client] = -1;
		g_RedCount--;
		AcceptEntityInput(client, "disableglow");
		//CPrintToChat(client, "[{lime}Team Games{default}] Removed from {fullred}RED{default} team.");
		CPrintToChat(client, "%t", "removed_from_red");
	}
	else if (g_BluePlayers[client] == client)
	{
		g_BluePlayers[client] = -1;
		g_BlueCount--;
		AcceptEntityInput(client, "disableglow");
		//CPrintToChat(client, "[{lime}Team Games{default}] Removed from {fullblue}BLUE{default} team.");
		CPrintToChat(client, "%t", "removed_from_blue");
	}
}

void SearchSpawns()
{
	char ent_name[64];
	int ent = -1;
	int loop_count;
	switch (g_GameMode)
	{
		case 0:
		{
			// CLASSIC TDM - SIMPLE WAY TO GET ORIGINS FROM SPAWNS
			while ((ent = FindEntityByClassname(ent, "info_player_nmrih")) != -1)
			{
				GetEntPropString(ent, Prop_Data, "m_iName", ent_name, sizeof(ent_name));
				if (StrContains(ent_name, "defender_", false) != -1)
				{
					//GetEntPropVector(ent, Prop_Data, "m_vecOrigin", g_OriginBlue);
					GetEntityAbsOrigin(ent, g_OriginBlue);
					if (GetConVarFloat(cvar_tdm_debug) == 1.0)
					{
						PrintToServer("[TDM] Successfully found %s origin.", ent_name);
						LogMessage("[TDM] Successfully found %s origin.", ent_name);
					}
				}
				else if (StrContains(ent_name, "attacker_", false) != -1)
				{
					//GetEntPropVector(ent, Prop_Data, "m_vecOrigin", g_OriginRed);
					GetEntityAbsOrigin(ent, g_OriginRed);
					if (GetConVarFloat(cvar_tdm_debug) == 1.0)
					{
						PrintToServer("[TDM] Successfully found %s origin.", ent_name);
						LogMessage("[TDM] Successfully found %s origin.", ent_name);
					}
				}
			}
		}
		case 1:
		{
			ent = -1;
			while ((ent = FindEntityByClassname(ent, "prop_physics")) != -1)
			{
				GetEntPropString(ent, Prop_Data, "m_iName", ent_name, sizeof(ent_name));
				if (StrEqual(ent_name, "pelota0", false))
				{
					//GetEntPropVector(ent, Prop_Data, "m_vecOrigin", g_SoccerBall_pos);
					GetEntityAbsOrigin(ent, g_SoccerBall_origin);
					g_SoccerBall_pos = g_SoccerBall_origin;
					g_SoccerBall = EntIndexToEntRef(ent);
					if (GetConVarFloat(cvar_tdm_debug) == 1.0)
					{
						PrintToServer("[TDM] Successfully found %s origin.", ent_name);
						LogMessage("[TDM] Successfully found %s origin.", ent_name);
						PrintToServer("[TDM] MAIN BALL origin X = %0.1f", g_SoccerBall_pos[0]);
						PrintToServer("[TDM] MAIN BALL origin Y = %0.1f", g_SoccerBall_pos[1]);
						PrintToServer("[TDM] MAIN BALL origin Z = %0.1f", g_SoccerBall_pos[2]);
					}
					break;
				}
			}
			// SoccerMod - SIMPLE WAY TO GET TELEPORTS ORIGINS
			ent = -1;
			loop_count = 0;
			while ((ent = FindEntityByClassname(ent,"info_teleport_destination")) != -1)
			{
				GetEntPropString(ent, Prop_Data, "m_iName", ent_name, sizeof(ent_name));
				if (StrEqual(ent_name, "TeledestinationCt", false))
				{
					//GetEntPropVector(ent, Prop_Data, "m_vecOrigin", g_OriginBlue);
					GetEntityAbsOrigin(ent, g_OriginBlue);
					if (GetConVarFloat(cvar_tdm_debug) == 1.0)
					{
						PrintToServer("[TDM] Successfully found %s origin.", ent_name);
						LogMessage("[TDM] Successfully found %s origin.", ent_name);
						PrintToServer("[TDM] BLUE origin X = %0.1f", g_OriginBlue[0]);
						PrintToServer("[TDM] BLUE origin Y = %0.1f", g_OriginBlue[1]);
						PrintToServer("[TDM] BLUE origin Z = %0.1f", g_OriginBlue[2]);
					}
					loop_count++;
				}
				else if (StrEqual(ent_name, "TeledestinationT", false))
				{
					//GetEntPropVector(ent, Prop_Data, "m_vecOrigin", g_OriginRed);
					GetEntityAbsOrigin(ent, g_OriginRed);
					if (GetConVarFloat(cvar_tdm_debug) == 1.0)
					{
						PrintToServer("[TDM] Successfully found %s origin.", ent_name);
						LogMessage("[TDM] Successfully found %s origin.", ent_name);
						PrintToServer("[TDM] RED origin X = %0.1f", g_OriginRed[0]);
						PrintToServer("[TDM] RED origin Y = %0.1f", g_OriginRed[1]);
						PrintToServer("[TDM] RED origin Z = %0.1f", g_OriginRed[2]);
					}
					loop_count++;
				}
				if (loop_count >= 2) break;
			}
			// SoccerMod - GOAL LINE POSITION + BALL STOP TRIGGER Entity
			ent = -1;
			loop_count = 0;
			while ((ent = FindEntityByClassname(ent, "trigger_multiple")) != -1)
			{
				GetEntPropString(ent, Prop_Data, "m_iName", ent_name, sizeof(ent_name));
				if (StrEqual(ent_name, "terro_But", true))
				{
					//GetEntPropVector(ent, Prop_Data, "m_vecOrigin", g_Origin_Red_Goal);
					GetEntityAbsOrigin(ent, g_Origin_Red_Goal);
					PrintToServer("[TDM] Successfully found %s origin.", ent_name);
					LogMessage("[TDM] Successfully found %s origin.", ent_name);
					loop_count++;
				}
				else if (StrEqual(ent_name, "ct_But", true))
				{
					//GetEntPropVector(ent, Prop_Data, "m_vecOrigin", g_Origin_Blue_Goal);
					GetEntityAbsOrigin(ent, g_Origin_Blue_Goal);
					PrintToServer("[TDM] Successfully found %s origin.", ent_name);
					LogMessage("[TDM] Successfully found %s origin.", ent_name);
					loop_count++;
				}
				else if (StrEqual(ent_name, "trigger_ball0", true))
				{
					//g_TriggerBall = EntIndexToEntRef(ent);
					loop_count++;
				}
				if (loop_count >= 3) break;
			}
		}
	}
}

bool IsPlayerRed(int client)
{
	bool player_red = false;
	if(g_RedPlayers[client] == client)
	{
		player_red = true;
	}
	return player_red;
}

bool IsPlayerBlue(int client)
{
	bool player_blue = false;
	if(g_BluePlayers[client] == client)
	{
		player_blue = true;
	}
	return player_blue;
}

public Action Timer_Global(Handle timer)
{
	if ((h_T_Global != timer) || (h_T_Global == null)) return Plugin_Stop;
	
	if (!g_PluginEnabled) return Plugin_Continue;
	if (GetConVarFloat(cvar_tdm_enabled) != 1.0) return Plugin_Continue;
	
	// BALL TRAIL
	//TE_SetupBeamFollow(EntRefToEntIndex(g_SoccerBall), PrecacheModel("materials/sprites/laserbeam.vmt", true), 0, 0.5, 3.0, 0.5, 1, BALL_DEBRIS_COLOR);
	//TE_SendToAll();
	
	// REFRESH PLAYER COLORS & SCOREBOARD
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			if ((IsPlayerAlive(i)) && (g_GameMode == 1))
			{
				// PLAYER HAS NO TEAM FIRST
				if ((IsPlayerRed(i) == false) && (IsPlayerBlue(i) == false))
				{
					// PREVENTS ADDING SAME PLAYER TO SAME TEAM AGAIN
					if ((g_RedCount < (TEAM_MAXPLAYERS-1)) && (g_RedCount <= g_BlueCount))
					{
						RemoveFromTeam(i);
						AddPlayerToArray(i, g_RedPlayers);
						GetClientName(i, g_PlayerName[i], sizeof(g_PlayerName[]));
						//CPrintToChatAll("[{lime}Team Games{default}] %s has joined {fullred}RED{default} team.", g_PlayerName[i]);
						CPrintToChatAll("%t", "joined_red_team", g_PlayerName[i]);
					}
					else if ((g_BlueCount < (TEAM_MAXPLAYERS-1)) && (g_BlueCount < g_RedCount))
					{
						// CHECK IF POSSIBLE TO ADD TO BLUE TEAM
						RemoveFromTeam(i);
						AddPlayerToArray(i, g_BluePlayers);
						GetClientName(i, g_PlayerName[i], sizeof(g_PlayerName[]));
						//CPrintToChatAll("[{lime}Team Games{default}] %s has joined {fullblue}BLUE{default} team.", g_PlayerName[i]);
						CPrintToChatAll("%t", "joined_blue_team", g_PlayerName[i]);
					}
				}
				else
				{
					// AUTO TEAM BALANCE
					if ((g_RedCount - g_BlueCount) >= 2) Command_Blue(i, 0);
					else if ((g_BlueCount - g_RedCount) >= 2) Command_Red(i, 0);
				}
				// GLOW AND TRAIL FOR GOALKEEPERS
				if (i == g_GK_red)
				{
					if (g_GK_red_distance <= SOCCERMOD_GK_DISTANCE)
					{
						TE_SetupBeamFollow(g_GK_red, g_MI_trail, 0, 0.2, 3.0, 0.5, 8, GK_RED_TRAIL_COLOR);
						TE_SendToAll();
					}
					DispatchKeyValue(g_GK_red, "glowcolor", RED_GK_COLOR);
					SetEntityRenderColor(g_GK_red, 255, 255, 255, 255);
				}
				else if (i == g_GK_blue)
				{
					if (g_GK_blue_distance <= SOCCERMOD_GK_DISTANCE)
					{
						TE_SetupBeamFollow(g_GK_blue, g_MI_trail, 0, 0.2, 3.0, 0.5, 8, GK_BLUE_TRAIL_COLOR);
						TE_SendToAll();
					}
					DispatchKeyValue(g_GK_blue, "glowcolor", BLUE_GK_COLOR);
					SetEntityRenderColor(g_GK_blue, 255, 255, 255, 255);
				}
			}
			if ((g_Warmup == false) && (g_TimerCount >= HINT_INTERVAL))
			{
				if (IsPlayerRed(i))
				{
					if (i == g_GK_red)
					{
						//PrintHintText(i, "YOU ARE RED *GOALKEEPER*   |   RED %d  -  BLUE %d   |", g_RedScore, g_BlueScore);
						PrintHintText(i, "%t", "red_gk_spam_hint", g_RedScore, g_BlueScore);
						HudMessage(i, sMessageColor_Red, sMessageColor_Red, sMessageEffect, sMessageChannel, sMessage_RedGK, sMessagePosX, sMessagePosY, sMessageFadeIn, sMessageFadeOut, sMessageHoldTime);
					}
					else
					{
						SetEntityRenderColor(i, 255, 92, 92, 255);
						DispatchKeyValue(i, "glowcolor", RED_COLOR_2);
						HudMessage(i, sMessageColor_Red, sMessageColor_Red, sMessageEffect, sMessageChannel, sMessage_RedTeam, sMessagePosX, sMessagePosY, sMessageFadeIn, sMessageFadeOut, sMessageHoldTime);
						//PrintHintText(i, "|   RED %d  -  BLUE %d   |   YOU ARE RED PLAYER", g_RedScore, g_BlueScore);
						PrintHintText(i, "%t", "red_player_spam_hint", g_RedScore, g_BlueScore);
					}
					
				}
				else if (IsPlayerBlue(i))
				{
					if (i == g_GK_blue)
					{
						//PrintHintText(i, "YOU ARE BLUE *GOALKEEPER*   |   BLUE %d  -  RED %d   |", g_BlueScore, g_RedScore);
						PrintHintText(i, "%t", "blue_gk_spam_hint", g_BlueScore, g_RedScore);
						HudMessage(i, sMessageColor_Blue, sMessageColor_Blue, sMessageEffect, sMessageChannel, sMessage_BlueGK, sMessagePosX, sMessagePosY, sMessageFadeIn, sMessageFadeOut, sMessageHoldTime);
					}
					else
					{
						SetEntityRenderColor(i, 92, 92, 255, 255);
						DispatchKeyValue(i, "glowcolor", BLUE_COLOR_2);
						HudMessage(i, sMessageColor_Blue, sMessageColor_Blue, sMessageEffect, sMessageChannel, sMessage_BlueTeam, sMessagePosX, sMessagePosY, sMessageFadeIn, sMessageFadeOut, sMessageHoldTime);
						//PrintHintText(i, "|   BLUE %d  -  RED %d   |   YOU ARE BLUE PLAYER", g_BlueScore, g_RedScore);
						PrintHintText(i, "%t", "blue_player_spam_hint", g_BlueScore, g_RedScore);
					}
				}
			}
		}
		// DECREASING COOLDOWN FOR PLAYER COMMAND
		if (g_PlayerMenuCooldown[i] > 0) g_PlayerMenuCooldown[i]--;
		else g_PlayerMenuCooldown[i] = 0;
	}
	
	// USEFUL FOR HINT TEXT WITHOUT SPAM
	if (g_TimerCount >= HINT_INTERVAL)
	{
		g_TimerCount = 0;
	}
	g_TimerCount++;
	
	// USEFUL FOR BALL COOLDOWN
	if (g_Timer_CooldownCount >= BALL_STOP_COOLDOWN)
	{
		//if (IsValidEntity(EntRefToEntIndex(g_TriggerBall))) AcceptEntityInput(EntRefToEntIndex(g_TriggerBall), "Enable");
		g_Timer_CooldownCount = 0;
		g_bStop_Cooldown = false;
	}
	if (g_bStop_Cooldown == true) g_Timer_CooldownCount++;
	// COOLDOWN ONLY COUNTS AFTER A TAKE DAMAGE EVENT
	
	if (g_GameMode != 1) return Plugin_Continue;
	
	// GOALKEEPER IN-GAME CHECK
	if (g_GK_red > 0)
	{
		if (IsClientInGame(g_GK_red))
		{
			ExecuteNPC_GK("npc_template_maker", "template_red_gk", "Disable");
			ExecuteNPC_GK("npc_nmrih_runnerzombie", "npc_gk_red", "Kill");
		}
		else
		{
			g_GK_red = -1;
			ExecuteNPC_GK("trigger_multiple", "red_trigger_npc_area", "Enable");
			ExecuteNPC_GK("npc_template_maker", "template_red_gk", "Enable");
			ExecuteNPC_GK("trigger_hurt", "red_hurt_npc", "Disable");
			//CPrintToChatAll("[{lime}Team Games{default}] Goalkeeper position for {fullred}RED{default} team is available now.");
			CPrintToChatAll("%t", "red_team_gk_available");
		}
	}
	if (g_GK_blue > 0)
	{
		if (IsClientInGame(g_GK_blue))
		{
			ExecuteNPC_GK("npc_template_maker", "template_blue_gk", "Disable");
			ExecuteNPC_GK("npc_nmrih_runnerzombie", "npc_gk_blue", "Kill");
		}
		else
		{
			g_GK_blue = -1;
			ExecuteNPC_GK("trigger_multiple", "blue_trigger_npc_area", "Enable");
			ExecuteNPC_GK("npc_template_maker", "template_blue_gk", "Enable");
			ExecuteNPC_GK("trigger_hurt", "blue_hurt_npc", "Disable");
			//CPrintToChatAll("[{lime}Team Games{default}] Goalkeeper position for {fullblue}BLUE{default} team is available now.");
			CPrintToChatAll("%t", "blue_team_gk_available");
		}
	}
	
	// BALL DYNAMIC TRAIL + BALL DYNAMIC COLOR
	if (EntRefToEntIndex(g_SoccerBall) > 0)
	{
		if (IsValidEntity(EntRefToEntIndex(g_SoccerBall)))
		{
			// BALL DYNAMIC TRAIL + BALL DYNAMIC COLOR
			GetEntPropVector(EntRefToEntIndex(g_SoccerBall), Prop_Send, "m_vecOrigin", g_SoccerBall_pos);
				
			if ((GetVectorDistance(g_SoccerBall_pos, g_Origin_Red_Goal) <= SOCCERMOD_BALL_DISTANCE) || (GetVectorDistance(g_SoccerBall_pos, g_Origin_Blue_Goal) <= SOCCERMOD_BALL_DISTANCE) || (FloatAbs(g_SoccerBall_origin[2]-g_SoccerBall_pos[2]) >= SOCCERMOD_CRITICAL_HEIGHT))
			{
				// BALL BECOMES SOLID NOW
				TE_SetupBeamFollow(EntRefToEntIndex(g_SoccerBall), g_MI_trail, 0, 0.2, 8.0, 0.5, 8, g_Ball_Trail_Color);
			}
			else
			{
				// BALL BECOMES DEBRIS
				TE_SetupBeamFollow(EntRefToEntIndex(g_SoccerBall), g_MI_trail, 0, 0.2, 8.0, 0.5, 8, g_Ball_Trail_Color);
			}
			TE_SendToAll();
		}
	}
	
	return Plugin_Continue;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &iImpulse, float fVelocity[3], float fAngles[3], int &iWeapon) 
{
	// FUNCTION ONLY USED IN SOCCERMOD
	if (g_GameMode != 1) return Plugin_Continue;
	
	if (IsClientInGame(client))
	{
		// BALL POSITION + BALL DYNAMIC TRAIL + BALL DYNAMIC COLOR
		if (EntRefToEntIndex(g_SoccerBall) > 0)
		{
			if (IsValidEntity(EntRefToEntIndex(g_SoccerBall)))
			{
				GetEntPropVector(EntRefToEntIndex(g_SoccerBall), Prop_Send, "m_vecOrigin", g_SoccerBall_pos);
				//GetEntityAbsOrigin(EntRefToEntIndex(g_SoccerBall), g_SoccerBall_pos);
				
				if ((GetVectorDistance(g_SoccerBall_pos, g_Origin_Red_Goal) <= SOCCERMOD_BALL_DISTANCE) || (GetVectorDistance(g_SoccerBall_pos, g_Origin_Blue_Goal) <= SOCCERMOD_BALL_DISTANCE) || (FloatAbs(g_SoccerBall_origin[2]-g_SoccerBall_pos[2]) >= SOCCERMOD_CRITICAL_HEIGHT))
				{
					// BALL BECOMES SOLID NOW
					g_Ball_Trail_Color = BALL_TRAIL_SOLID;
					SetEntProp(EntRefToEntIndex(g_SoccerBall), Prop_Send, "m_CollisionGroup", 0);
					SetEntProp(EntRefToEntIndex(g_SoccerBall), Prop_Send, "m_usSolidFlags", 0x0010);
					SetEntProp(EntRefToEntIndex(g_SoccerBall), Prop_Data, "m_nSolidType", 6);
					//DispatchKeyValue(EntRefToEntIndex(g_SoccerBall), "solid", "6");
					DispatchKeyValue(EntRefToEntIndex(g_SoccerBall), "glowcolor", BALL_SOLID_COLOR);
					//TE_SetupBeamFollow(EntRefToEntIndex(g_SoccerBall), g_MI_trail, 0, 0.1, 2.0, 0.5, 4, BALL_TRAIL_SOLID);
				}
				else
				{
					// BALL BECOMES DEBRIS
					g_Ball_Trail_Color = BALL_TRAIL_DEBRIS;
					SetEntProp(EntRefToEntIndex(g_SoccerBall), Prop_Data, "m_CollisionGroup", 2);
					DispatchKeyValue(EntRefToEntIndex(g_SoccerBall), "glowcolor", BALL_DEBRIS_COLOR);
					//TE_SetupBeamFollow(EntRefToEntIndex(g_SoccerBall), g_MI_trail, 0, 0.1, 2.0, 0.5, 4, BALL_TRAIL_DEBRIS);
				}
				//TE_SendToAll();
			}
		}
		
		if (IsPlayerAlive(client))
		{
			// CHECKING GOALKEEPER CONDITIONS NEXT
			if (client == g_GK_red)
			{
				GetClientAbsOrigin(g_GK_red, g_GK_red_position);
				g_GK_red_position[2] += 8.0;
				g_GK_red_distance = GetVectorDistance(g_GK_red_position, g_Origin_Red_Goal);
					
				if (g_GK_red_distance <= SOCCERMOD_GK_DISTANCE)
				{
					if (GetEntityFlags(client) & FL_DUCKING)
					{
						SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", 1.5);
					}
					else
					{
						SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", 1.0);
					}
					/*
					if (buttons & IN_DUCK)
					{
						SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", 1.5);
					}
					else
					{
						SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", 1.0);
					}
					*/
				}
				else
				{
					SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", 1.0);
				}
			}
			else if (client == g_GK_blue)
			{
				GetClientAbsOrigin(g_GK_blue, g_GK_blue_position);
				g_GK_blue_position[2] += 8.0;
				g_GK_blue_distance = GetVectorDistance(g_GK_blue_position, g_Origin_Blue_Goal);
				
				if (g_GK_blue_distance <= SOCCERMOD_GK_DISTANCE)
				{
					if (GetEntityFlags(client) & FL_DUCKING)
					{
						SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", 1.5);
					}
					else
					{
						SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", 1.0);
					}
					/*
					if (buttons & IN_DUCK)
					{
						SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", 1.5);
					}
					else
					{
						SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", 1.0);
					}
					*/
				}
				else
				{
					SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", 1.0);
				}
			}
		}
	}
	return Plugin_Continue;
}

void GetEntityAbsOrigin(int entity, float origin[3])
{
	char class[32];
	int offs;
	
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", origin);
	
	if (!GetEntityNetClass(entity, class, sizeof(class)) || (offs = FindSendPropInfo(class, "m_vecMins")) == -1)
	{
		return;
	}
	
	float mins[3];
	float maxs[3];
	
	GetEntDataVector(entity, offs, mins);
	GetEntPropVector(entity, Prop_Send, "m_vecMaxs", maxs);
	
	origin[0] += (mins[0] + maxs[0]) * 0.5;
	origin[1] += (mins[1] + maxs[1]) * 0.5;
	origin[2] += (mins[2] + maxs[2]) * 0.5;
}

void RemoveExtraWelders()
{
	// METHOD 2
	/*
	int maxent = GetMaxEntities();
	char weapon[64];
	for (int i = MaxClients+1; i < maxent; i++)
	{
		if (IsValidEntity(i))
		{
			GetEdictClassname(i, weapon, sizeof(weapon));
			if ((StrContains(weapon, "tool_welder", false) != -1) && (GetEntPropEnt(i, Prop_Data, "m_hOwner") == 0))
			{
				AcceptEntityInput(i, "Kill");
			}
		}
	}
	*/
	// METHOD 1
	int weapon_index = -1;
	while ((weapon_index = FindEntityByClassname(weapon_index, "tool_welder")) != -1)
	{
		if (GetEntPropEnt(weapon_index, Prop_Data, "m_hOwnerEntity") < 1)
		{
			//RemoveEdict(weapon_index);
			RemoveEntity(weapon_index);
			AcceptEntityInput(weapon_index, "Kill");
		}
	}
}

void LookAtTarget(any client, any target)
{ 
	float angles[3];
	float clientEyes[3];
	float targetEyes[3];
	float resultant[3];
	
	GetClientEyePosition(client, clientEyes);
	
	if(target > 0 && target <= MaxClients && IsClientInGame(target))
	{
		GetClientEyePosition(target, targetEyes);
	}
	else
	{
		if (target > 0)
		{
			if (IsValidEntity(target)) GetEntPropVector(target, Prop_Send, "m_vecOrigin", targetEyes);
		}
	}
	
	MakeVectorFromPoints(targetEyes, clientEyes, resultant); 
	GetVectorAngles(resultant, angles); 
	
	if(angles[0] >= 270)
	{ 
		angles[0] -= 270; 
		angles[0] = (90-angles[0]); 
    }
	else
	{ 
		if(angles[0] <= 90)
		{ 
			angles[0] *= -1; 
		} 
	} 
	
	angles[1] -= 180; 
	TeleportEntity(client, NULL_VECTOR, angles, NULL_VECTOR); 
}

stock void HudMessage(int client, const char[] color,const char[] color2, const char[] effect, const char[] channel, const char[] message, const char[] posx, const char[] posy, const char[] fadein, const char[] fadeout, const char[] holdtime)
{
	char szHoldTime[32];
	Format(szHoldTime, sizeof(szHoldTime), "!self,Kill,,%s,-1", holdtime);
	int iGameText = CreateEntityByName("game_text");
	DispatchKeyValue(iGameText, "channel", channel);
	DispatchKeyValue(iGameText, "color", color);
	DispatchKeyValue(iGameText, "color2", color2);
	DispatchKeyValue(iGameText, "effect", effect);
	DispatchKeyValue(iGameText, "fadein", fadein);
	DispatchKeyValue(iGameText, "fadeout", fadeout);
	DispatchKeyValue(iGameText, "fxtime", "0.5");
	DispatchKeyValue(iGameText, "holdtime", holdtime);
	DispatchKeyValue(iGameText, "message", message);
	DispatchKeyValue(iGameText, "spawnflags", "0");
	DispatchKeyValue(iGameText, "x", posx);
	DispatchKeyValue(iGameText, "y", posy);
	DispatchSpawn(iGameText);
	SetVariantString("!activator");
	AcceptEntityInput(iGameText,"display",client);
	DispatchKeyValue(iGameText, "OnUser1", szHoldTime);
	AcceptEntityInput(iGameText, "FireUser1");
}