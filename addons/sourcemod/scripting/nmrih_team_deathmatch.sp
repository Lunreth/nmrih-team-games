#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <autoexecconfig>
#include <multicolors>

#pragma semicolon 1
#pragma newdecls required
#pragma dynamic 131072

#define PLUGIN_AUTHOR "Ulreth*"
#define PLUGIN_VERSION "1.2.0" // 13-11-2021
#define PLUGIN_NAME "[NMRiH] Team Deathmatch Mod"

#define FL_DUCKING (1<<1)

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
NOT WORKING - RED "trigger_teleport" (TeledestinationT) --> RED team base teleport 
NOT WORKING - BLUE "trigger_teleport" (TeledestinationCt)--> BLUE team base teleport
- RED Template Maker "npc_template_maker" (template_red_gk)
- BLUE Template Maker "npc_template_maker" (template_blue_gk)
- RED "trigger_hurt" (red_hurt_npc)
- BLUE "trigger_hurt" (blue_hurt_npc)
- RED "trigger_multiple" (red_trigger_npc_area)
- BLUE "trigger_multiple" (blue_trigger_npc_area)
- RED "npc_nmrih_runnerzombie" (npc_gk_red)
- BLUE "npc_nmrih_runnerzombie" (npc_gk_blue)

Important note: Case sensitive for entity targetname
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
*/

#define TEAM_MAXPLAYERS 5
#define SOCCERMOD_GK_DISTANCE 320.0

#define SOUND_WARNING_BELL "play *ambient/alarms/warningbell1.wav"
#define SOUND_KLAXON "play *ambient/alarms/klaxon1.wav"
#define SOUND_WARNING "play *common/warning.wav"
#define SOUND_SURV_ALARM "play *survival/surv_alarm.wav"
#define SOUND_ELEV_BELL "play *plats/elevbell1.wav"

#define RED_COLOR_1 "255 0 1"
#define RED_COLOR_2 "254 1 0"
#define RED_COLOR_3 "254 0 1"
#define RED_COLOR_4 "253 1 0"
#define RED_COLOR_5 "253 0 1"

#define BLUE_COLOR_1 "1 0 255"
#define BLUE_COLOR_2 "0 1 254"
#define BLUE_COLOR_3 "1 0 254"
#define BLUE_COLOR_4 "0 1 253"
#define BLUE_COLOR_5 "1 0 253"

// CONVARS
ConVar cvar_tdm_enabled;
ConVar cvar_tdm_debug;

// TDM CFG FILE
KeyValues hConfig;

// GAME STATES
int g_GameMode = 0; // 0 = Classic TDM | 1 = SoccerMod
bool g_PluginEnabled = true;
bool g_Warmup = true;
bool g_RoundStart = false;
bool g_ExtractionStarted = false;
int g_LastScore = 0; // 0 = No goals scored | 1 = RED team scored previous round | 2 = BLUE team scored previous round

// PLAYERS COUNT
int g_PlayerCount = 0;
int g_BlueCount = 0; // Count alive BLUE players in TDM | Count BLUE also dead players in SoccerMod
int g_RedCount = 0; // Count alive RED players | Count also RED dead players in SoccerMod
char g_PlayerName[10][64];

// BLUE PLAYERS
int g_GK_blue = -1;
int g_BluePlayers[TEAM_MAXPLAYERS]; // Saves index of BLUE players
float g_OriginBlue[3]; // Saves spawn origins of RED players
float g_Origin_Blue_Goal[3]; // Saves origin of CT button

// RED PLAYERS
int g_GK_red = -1;
int g_RedPlayers[TEAM_MAXPLAYERS]; // Saves index of RED players
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
	AutoExecConfig_SetFile("nmrih_team_deathmatch");
	AutoExecConfig_SetCreateFile(true);
	AutoExecConfig_CreateConVar("sm_tdm_version", PLUGIN_VERSION, PLUGIN_NAME, FCVAR_NONE);
	cvar_tdm_enabled = AutoExecConfig_CreateConVar("sm_tdm_enable", "1.0", "Enable or disable Team Deathmatch plugin.", FCVAR_NONE, true, 0.0, true, 1.0);
	cvar_tdm_debug = AutoExecConfig_CreateConVar("sm_tdm_debug", "0.0", "Debug mode for plugin - Will spam messages in console if set to 1", FCVAR_NONE, true, 0.0, true, 1.0);
	AutoExecConfig_ExecuteFile();
	AutoExecConfig_CleanFile();
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
	HookEventEx("extraction_begin", Event_ExtractionBegin);
	HookEventEx("objective_fail", Event_ResetVariables);
	HookEventEx("player_join", Event_PlayerJoin, EventHookMode_Post);
	HookEventEx("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
	// OnClientPutInServer
	// OnClientDisconnect
	// OnMapStart
	// OnMapEnd
	// OnTakeDamage
	// PLAYER LOOP
	for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
        {
            SDKHook(i, SDKHook_OnTakeDamage, OnTakeDamage);
        }
    }
	// TIMER FOR PLAYER COLOR
	h_T_Global = CreateTimer(3.0, Timer_Global, _, TIMER_REPEAT);
}

public void OnMapStart()
{
	if (GetConVarFloat(cvar_tdm_enabled) == 0.0)
	{
		g_PluginEnabled = false;
		return;
	}
	
	char map[65];
	GetCurrentMap(map, sizeof(map));
	for (int i = 1; i <= 2; i++)
	{
		if (i == 1) hConfig = new KeyValues("team_deathmatch");
		else hConfig = new KeyValues("soccermod");
		char path[PLATFORM_MAX_PATH];
		if (i == 1) BuildPath(Path_SM, path, sizeof(path), "configs/nmrih_tdm_maps.cfg");
		else BuildPath(Path_SM, path, sizeof(path), "configs/nmrih_soccermod_maps.cfg");
		hConfig.ImportFromFile(path);
		if(hConfig.JumpToKey("valid_maps", false))
		{
			if(hConfig.JumpToKey(map, false))
			{
				g_PluginEnabled = true;
				if (i == 1) g_GameMode = 0;
				else g_GameMode = 1;
				delete hConfig;
				break;
			}
		}
		else
		{
			g_PluginEnabled = false;
			PrintToServer("[NMRiH] Map not found inside CFG file");
			LogMessage("[NMRiH] Map not found inside CFG file");
		}
		delete hConfig;
	}
	VariablesToZero();
	MatchVariablesZero();
	SearchSpawns();
}

public void OnClientPutInServer(int client)
{
	if ((g_PluginEnabled == true) && (GetConVarFloat(cvar_tdm_enabled) == 1.0))
	{
		SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
		GetClientName(client, g_PlayerName[client], sizeof(g_PlayerName[]));
	}
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
	if ((g_PluginEnabled == false) && (GetConVarFloat(cvar_tdm_enabled) == 1.0))
	{
		return Plugin_Continue;
	}
	// NO DAMAGE FOR GKs
	char classname1[256];
	char classname2[256];
	GetEdictClassname(inflictor, classname1, sizeof(classname1));
	GetEdictClassname(attacker, classname2, sizeof(classname2));
	
	if ((attacker != 0) && ((victim == g_GK_red) || (victim == g_GK_blue)))
	{
		if(StrEqual(classname1, "func_physbox", false) || StrEqual(classname1, "prop_physics", false) || StrEqual(classname1, "prop_physics_multiplayer", false) || StrEqual(classname1, "prop_physics_override", false) || StrEqual(classname2, "func_physbox", false) || StrEqual(classname2, "prop_physics", false))
		{
			float victim_pos[3];
			GetClientAbsOrigin(victim, victim_pos);
			
			float distance;
			if (victim == g_GK_red) distance = GetVectorDistance(victim_pos, g_Origin_Red_Goal);
			else if (victim == g_GK_blue) distance = GetVectorDistance(victim_pos, g_Origin_Blue_Goal);
			if (distance <= SOCCERMOD_GK_DISTANCE)
			{
				damage = 0.0;
				PrintHintText(victim, "[SoccerMod] Ball stopped without taking damage!");
				return Plugin_Changed;
			}
		}
	}
	
	// CHECK FRIENDLY FIRE
	if ((victim > 0) && (victim <= MaxClients) && (attacker > 0) && (attacker <= MaxClients) && (victim != attacker))
	{
		// BOTH VICTIM AND ATTACKER ARE VALID CLIENTS AND THEY ARE DIFFERENT FROM EACH OTHER
		if (((IsPlayerRed(victim) == true) && (IsPlayerRed(attacker) == true)) || ((IsPlayerBlue(victim) == true) && (IsPlayerBlue(attacker) == true)))
		{
			// DETECTED FRIENDLY FIRE
			damage = 0.0;
			PrintHintText(attacker,"[TDM] Friendly Fire disabled.");
			return Plugin_Changed;
		}
	}
	return Plugin_Continue;
}

public void OnEntityCreated(int entity, const char[] classname)
{
    if ((StrEqual(classname, "trigger_multiple")) && (g_PluginEnabled == true))
    {
		// HOOKS EVENTS FOR TRIGGER_MULTIPLE
		SDKHookEx(entity, SDKHook_Touch, OnTouch);
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
		CPrintToChat(client, "[{lime}TDM{default}] Menu disabled in this mode.");
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
			if (IsPlayerBlue(i) == true)
			{
				Format(display, sizeof(display), "%s (BLUE)", g_PlayerName[i]);
				hMenu.AddItem(g_PlayerName[i], display, ITEMDRAW_DEFAULT);
			}
			if ((IsPlayerRed(i) == false) && (IsPlayerBlue(i) == false))
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
							CPrintToChat(param1, "[{lime}TDM{default}] {fullred}RED{default} team full, invalid command.");
							Menu_MovePlayer(param1,0);
							break;
						}
						if (i == g_GK_blue)
						{
							g_GK_blue = -1;
							ExecuteNPC_GK("trigger_multiple", "blue_trigger_npc_area", "Enable");
							ExecuteNPC_GK("npc_template_maker", "template_blue_gk", "Enable");
							ExecuteNPC_GK("trigger_hurt", "blue_hurt_npc", "Disable");
							CPrintToChatAll("[{lime}TDM{default}] Goalkeeper position for {fullblue}BLUE{default} team is available now.");
						}
						RemoveFromTeam(i);
						AddPlayerToArray(i, g_RedPlayers, false);
						if (IsPlayerAlive(i)) ForcePlayerSuicide(i);
						CPrintToChatAll("[{lime}TDM{default}] %s was moved to {fullred}RED{default} team.", g_PlayerName[i]);
						Menu_MovePlayer(param1,0);
						break;
					}
					if (IsPlayerRed(i) == true) // TRY TO CHANGE TO BLUE TEAM
					{
						if (g_BlueCount >= TEAM_MAXPLAYERS-1)
						{
							CPrintToChat(param1, "[{lime}TDM{default}] {fullblue}BLUE{default} team full, invalid command.");
							Menu_MovePlayer(param1,0);
							break;
						}
						if (i == g_GK_red)
						{
							g_GK_red = -1;
							ExecuteNPC_GK("trigger_multiple", "red_trigger_npc_area", "Enable");
							ExecuteNPC_GK("npc_template_maker", "template_red_gk", "Enable");
							ExecuteNPC_GK("trigger_hurt", "red_hurt_npc", "Disable");
							CPrintToChatAll("[{lime}TDM{default}] Goalkeeper position for {fullred}RED{default} team is available now.");
						}
						RemoveFromTeam(i);
						AddPlayerToArray(i, g_BluePlayers, false);
						if (IsPlayerAlive(i)) ForcePlayerSuicide(i);
						CPrintToChatAll("[{lime}TDM{default}] %s was moved to {fullblue}BLUE{default} team.", g_PlayerName[i]);
						Menu_MovePlayer(param1,0);
						break;
					}
					else
					{
						if (g_RedCount >= TEAM_MAXPLAYERS-1)
						{
							// Move to blue
							AddPlayerToArray(i, g_BluePlayers, false);
							CPrintToChatAll("[{lime}TDM{default}] %s was moved to {fullblue}BLUE{default} team.", g_PlayerName[i]);
						}
						if (g_BlueCount >= TEAM_MAXPLAYERS-1)
						{
							// Move to red
							AddPlayerToArray(i, g_RedPlayers, false);
							CPrintToChatAll("[{lime}TDM{default}] %s was moved to {fullred}RED{default} team.", g_PlayerName[i]);
						}
						else
						{
							CPrintToChatAll("[{lime}TDM{default}] Unable to move %s, all teams are full!", g_PlayerName[i]);
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
		CPrintToChat(client, "[{lime}{lime}TDM{default}{default}] Randomize team function disabled in this game mode.");
		return Plugin_Continue;
	}
	// ONLY ENABLED DURING MATCH
	if (g_Warmup == true)
	{
		CPrintToChat(client, "[{lime}TDM{default}] Function disabled in warmup time.");
		return Plugin_Continue;
	}
	// CHECKS IF PLAYER ALREADY VOTED
	for (int i = 1; i <= MaxClients; i++)
	{
		if (client == g_VotingPlayers[i])
		{
			CPrintToChat(client, "[{lime}TDM{default}] You already voted to shuffle teams.");
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
			CPrintToChatAll("[{lime}TDM{default}] +1 votes to randomize teams --- Total votes = (+%d)", g_VotingCount);
			ClientCommand(client, SOUND_WARNING_BELL);
			break;
		}
	}
	// CHECK IF AMOUNT OF VOTES IS ENOUGH
	if (g_VotingCount >= RoundToCeil(float(g_PlayerCount)/2.0))
	{
		ForceRoundEnd();
		MatchVariablesZero();
		for (int i = 1; i <= MaxClients; i++)
		{
			ClientCommand(i, SOUND_WARNING);
			g_VotingPlayers[i] = -1;
		}
		CPrintToChatAll("[{lime}TDM{default}] Votes acquired! Shuffling teams and restarting match!");
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
		CPrintToChat(client, "[{lime}TDM{default}] Randomize team function disabled in this game mode.");
		return Plugin_Continue;
	}
	// ONLY ENABLED DURING MATCH
	if (g_Warmup == true)
	{
		CPrintToChat(client, "[{lime}TDM{default}] Function disabled in warmup time.");
		return Plugin_Continue;
	}
	ForceRoundEnd();
	MatchVariablesZero();
	for (int i = 1; i <= MaxClients; i++)
	{
		g_VotingPlayers[i] = -1;
	}
	CPrintToChatAll("[{lime}TDM{default}] Admin restarted match and randomized teams.");
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
		CPrintToChat(client, "[{lime}TDM{default}] You must be alive to be goalkeeper.");
		return Plugin_Continue;
	}
	if (g_GameMode == 0)
	{
		CPrintToChat(client, "[{lime}TDM{default}] Goalkeeper disabled in this game mode.");
		return Plugin_Continue;
	}
	if ((g_GK_red == client) || (g_GK_blue == client))
	{
		Command_GK_Disable(client, 0);
		return Plugin_Continue;
	}
	if ((IsPlayerRed(client) == true) && (g_GK_red != -1))
	{
		CPrintToChat(client, "[{lime}TDM{default}] You cannot be goalkeeper, there is one already in {fullred}red{default} team.");
		return Plugin_Continue;
	}
	if ((IsPlayerBlue(client) == true) && (g_GK_blue != -1))
	{
		CPrintToChat(client, "[{lime}TDM{default}] You cannot be goalkeeper, there is one already in {fullblue}blue{default} team.");
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
		CPrintToChat(client, "[{lime}TDM{default}] You are now the goalkeeper of {fullred}RED{default} team, protected from ball damage");
		//EmitSoundToClient(client, SOUND_KLAXON);
		ClientCommand(client, SOUND_KLAXON);
		CPrintToChatAll("[{lime}TDM{default}] %s is now the goalkeeper of {fullred}RED{default} team", client_name);
	}
	if (IsPlayerBlue(client) == true)
	{
		g_GK_blue = client;
		ExecuteNPC_GK("trigger_multiple", "blue_trigger_npc_area", "Disable");
		ExecuteNPC_GK("npc_template_maker", "template_blue_gk", "Disable");
		ExecuteNPC_GK("trigger_hurt", "blue_hurt_npc", "Enable");
		//SetEntityHealth(client, 1000);
		CPrintToChat(client, "[{lime}TDM{default}] You are now the goalkeeper of {fullblue}BLUE{default} team, protected from ball damage");
		//EmitSoundToClient(client, SOUND_KLAXON);
		ClientCommand(client, SOUND_KLAXON);
		CPrintToChatAll("[{lime}TDM{default}] %s is now the goalkeeper of {fullblue}BLUE{default} team", client_name);
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
		CPrintToChat(client, "[{lime}TDM{default}] Goalkeeper disabled in this game mode.");
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
		CPrintToChatAll("[{lime}TDM{default}] Goalkeeper position for {fullred}RED{default} team is available now.");
	}
	if (g_GK_blue == client)
	{
		g_GK_blue = -1;
		ExecuteNPC_GK("trigger_multiple", "blue_trigger_npc_area", "Enable");
		ExecuteNPC_GK("npc_template_maker", "template_blue_gk", "Enable");
		ExecuteNPC_GK("trigger_hurt", "blue_hurt_npc", "Disable");
		//SetEntityHealth(client, 200);
		//EmitSoundToClient(client, SOUND_ELEV_BELL);
		ClientCommand(client, SOUND_ELEV_BELL);
		CPrintToChatAll("[{lime}TDM{default}] Goalkeeper position for {fullblue}BLUE{default} team is available now.");
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
		CPrintToChat(client, "[{lime}TDM{default}] Team change disabled in this mode.");
		return Plugin_Continue;
	}
	// AVOIDS JOINING SAME TEAM AGAIN
	if (IsPlayerRed(client) == true)
	{
		CPrintToChat(client, "[{lime}TDM{default}] Invalid action, you currently belong to {fullred}RED{default} team.");
		return Plugin_Continue;
	}
	// AVOIDS JOINING FULL TEAM
	if (g_RedCount >= TEAM_MAXPLAYERS-1)
	{
		CPrintToChat(client, "[{lime}TDM{default}] {fullred}RED{default} team full, invalid command.");
		return Plugin_Continue;
	}
	if (client == g_GK_blue)
	{
		g_GK_blue = -1;
		ExecuteNPC_GK("trigger_multiple", "blue_trigger_npc_area", "Enable");
		ExecuteNPC_GK("npc_template_maker", "template_blue_gk", "Enable");
		ExecuteNPC_GK("trigger_hurt", "blue_hurt_npc", "Disable");
		CPrintToChatAll("[{lime}TDM{default}] Goalkeeper position for {fullblue}BLUE{default} team is available now.");
	}
	if (client == g_GK_red)
	{
		g_GK_red = -1;
		ExecuteNPC_GK("trigger_multiple", "red_trigger_npc_area", "Enable");
		ExecuteNPC_GK("npc_template_maker", "template_red_gk", "Enable");
		ExecuteNPC_GK("trigger_hurt", "red_hurt_npc", "Disable");
		CPrintToChatAll("[{lime}TDM{default}] Goalkeeper position for {fullred}RED{default} team is available now.");
	}
	RemoveFromTeam(client);
	AddPlayerToArray(client, g_RedPlayers, false);
	//EmitSoundToClient(client, SOUND_SURV_ALARM);
	ClientCommand(client, SOUND_SURV_ALARM);
	if (IsPlayerAlive(client)) ForcePlayerSuicide(client);
	char client_name[64];
	GetClientName(client, client_name, sizeof(client_name));
	CPrintToChat(client, "[{lime}TDM{default}] Switched to {fullred}RED{default} team");
	CPrintToChatAll("[{lime}TDM{default}] %s has joined {fullred}RED{default} team.", client_name);
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
		CPrintToChat(client, "[{lime}TDM{default}] Team change disabled in this mode.");
		return Plugin_Continue;
	}
	// AVOIDS JOINING SAME TEAM AGAIN
	if (IsPlayerBlue(client) == true)
	{
		CPrintToChat(client, "[{lime}TDM{default}] Invalid action, you currently belong to {fullblue}BLUE{default} team.");
		return Plugin_Continue;
	}
	// AVOIDS JOINING FULL TEAM
	if (g_BlueCount >= TEAM_MAXPLAYERS-1)
	{
		CPrintToChat(client, "[{lime}TDM{default}] {fullblue}BLUE{default} team full, invalid command.");
		return Plugin_Continue;
	}
	if (client == g_GK_blue)
	{
		g_GK_blue = -1;
		ExecuteNPC_GK("trigger_multiple", "blue_trigger_npc_area", "Enable");
		ExecuteNPC_GK("npc_template_maker", "template_blue_gk", "Enable");
		ExecuteNPC_GK("trigger_hurt", "blue_hurt_npc", "Disable");
		CPrintToChatAll("[{lime}TDM{default}] Goalkeeper position for {fullblue}BLUE{default} team is available now.");
	}
	if (client == g_GK_red)
	{
		g_GK_red = -1;
		ExecuteNPC_GK("trigger_multiple", "red_trigger_npc_area", "Enable");
		ExecuteNPC_GK("npc_template_maker", "template_red_gk", "Enable");
		ExecuteNPC_GK("trigger_hurt", "red_hurt_npc", "Disable");
		CPrintToChatAll("[{lime}TDM{default}] Goalkeeper position for {fullred}RED{default} team is available now.");
	}
	RemoveFromTeam(client);
	AddPlayerToArray(client, g_BluePlayers, false);
	//EmitSoundToClient(client, SOUND_SURV_ALARM);
	ClientCommand(client, SOUND_SURV_ALARM);
	if (IsPlayerAlive(client)) ForcePlayerSuicide(client);
	char client_name[64];
	GetClientName(client, client_name, sizeof(client_name));
	CPrintToChat(client, "[{lime}TDM{default}] Switched to {fullblue}BLUE{default} team");
	CPrintToChatAll("[{lime}TDM{default}] %s has joined {fullblue}BLUE{default} team.", client_name);
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
		if (((StrEqual(trigger_name, "ct_But", false)) || (StrEqual(trigger_name, "terro_But", false))) && (g_ExtractionStarted == false))
		{
			if (StrEqual(trigger_name, "terro_But", false))
			{
				// WINNER: BLUE TEAM
				g_LastScore = 2;
				g_BlueScore = (g_BlueScore + 1);
				KillTeam(g_RedPlayers);
				ForceExtractTeam(g_BluePlayers);
				CPrintToChatAll("[{lime}TDM{default}] {fullblue}BLUE{default} team wins the round!");
				PrintCenterTextAll("BLUE team wins this round!");
			}
			if (StrEqual(trigger_name, "ct_But", false))
			{
				// WINNER: RED TEAM
				g_LastScore = 1;
				g_RedScore = (g_RedScore + 1);
				KillTeam(g_BluePlayers);
				ForceExtractTeam(g_RedPlayers);
				CPrintToChatAll("[{lime}TDM{default}] {fullred}RED{default} team wins the round!");
				PrintCenterTextAll("RED team wins this round!");
			}
		}
	}
	// TRIGGER MULTIPLE DETECTION
	if (StrEqual(class_name, "player", false))
	{
		// PREVENTS ADDING SAME PLAYER TO SAME TEAM AGAIN
		if((IsPlayerRed(other) == true) || (IsPlayerBlue(other) == true))
		{
			return Plugin_Continue;
		}
		if(StrEqual(trigger_name, "area_red", false))
		{
			// RED PLAYER JOINS THE MATCH
			AddPlayerToArray(other, g_RedPlayers, false);
			GetClientName(other, client_name, sizeof(client_name));
			CPrintToChatAll("[{lime}TDM{default}] %s has joined {fullred}RED{default} team.", client_name);
        }
		else if(StrEqual(trigger_name, "area_blue", false))
		{
            // BLUE PLAYER JOINS THE MATCH
			AddPlayerToArray(other, g_BluePlayers, false);
			GetClientName(other, client_name, sizeof(client_name));
			CPrintToChatAll("[{lime}TDM{default}] %s has joined {fullblue}BLUE{default} team.", client_name);			
        }
    }
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
			//if (IsPlayerAlive(client))
			//{
				char client_name[64];
				GetClientName(client, client_name, sizeof(client_name));
				// AT SPAWN WILL CHECK IF PLAYER CAN BE ADDED TO A TEAM
				// CHECK IF POSSIBLE TO ADD TO RED TEAM
				if (g_GameMode == 1)
				{
					if ((g_RedCount < (TEAM_MAXPLAYERS-1)) && (g_RedCount < g_BlueCount) && (IsPlayerRed(client) == false) && (IsPlayerBlue(client) == false))
					{
						AddPlayerToArray(client, g_RedPlayers, false);
						CPrintToChatAll("[{lime}TDM{default}] %s has joined {fullred}RED{default} team.", client_name);
					}
					if ((g_BlueCount < (TEAM_MAXPLAYERS-1)) && (g_BlueCount <= g_RedCount) && (IsPlayerRed(client) == false) && (IsPlayerBlue(client) == false))
					{
						// CHECK IF POSSIBLE TO ADD TO BLUE TEAM
						AddPlayerToArray(client, g_BluePlayers, false);
						CPrintToChatAll("[{lime}TDM{default}] %s has joined {fullblue}BLUE{default} team.", client_name);
					}
				}
				// MORE ACTIONS AFTER CHECKING TEAM
				if (IsPlayerRed(client) == true)
				{
					DispatchKeyValue(client, "glowable", "1"); 
					DispatchKeyValue(client, "glowblip", "1");
					DispatchKeyValue(client, "glowcolor", "255 0 0");
					DispatchKeyValue(client, "glowdistance", "9999");
					AcceptEntityInput(client, "enableglow");
					SetEntityRenderColor(client, 255, 92, 92, 255);
					if (g_GameMode == 1) TeleportBackRed(client);
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
					if (g_GameMode == 1) TeleportBackBlue(client);
					return Plugin_Continue;
				}
			//}
		}
	}
	return Plugin_Continue;
}

public void OnClientDisconnect(int client)
{
	if (g_PluginEnabled == true)
	{
		SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
		RemoveFromTeam(client);
	}
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	if ((g_PluginEnabled == false) && (GetConVarFloat(cvar_tdm_enabled) == 1.0)) return;
	g_RoundStart = false;
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
	}
	if (g_GK_blue > 0)
	{
		ExecuteNPC_GK("trigger_multiple", "blue_trigger_npc_area", "Disable");
		ExecuteNPC_GK("npc_template_maker", "template_blue_gk", "Disable");
		ExecuteNPC_GK("trigger_hurt", "blue_hurt_npc", "Enable");
	}
	// FINAL PRINT
	if (GetConVarFloat(cvar_tdm_debug) == 1.0) CPrintToChatAll("[{lime}TDM{default}] %i players in-game.", g_PlayerCount);
	if (GetConVarFloat(cvar_tdm_debug) == 1.0) CPrintToChatAll("[{lime}TDM{default}] %i players in {fullblue}BLUE{default} team.", g_BlueCount);
	if (GetConVarFloat(cvar_tdm_debug) == 1.0) CPrintToChatAll("[{lime}TDM{default}] %i players in {fullred}RED{default} team.", g_RedCount);
	if (g_GameMode == 1) CPrintToChatAll("[{lime}TDM{default}] Say {fullred}!red{default} or {fullblue}!blue{default} to switch teams \n Say {gold}!gk{default} to toggle between field player and GK mode.");
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
					CPrintToChatAll("[{lime}{lime}TDM{default}{default}] All members of {fullred}RED{default} team died!");
					CPrintToChatAll("[{lime}{lime}TDM{default}{default}] {fullblue}BLUE{default} team {gold}wins{default} the round!");
					PrintCenterTextAll("BLUE team wins this round!");
				}
				else if ((g_BlueCount == 0) && (g_RedCount > 0))
				{
					// SAME FOR OTHER TEAM
					ForceExtractTeam(g_RedPlayers);
					g_RedScore = (g_RedScore + 1);
					CPrintToChatAll("[{lime}{lime}TDM{default}{default}] All members of {fullblue}BLUE{default} team died!");
					CPrintToChatAll("[{lime}{lime}TDM{default}{default}] {fullred}RED{default} team {gold}wins{default} the round!");
					PrintCenterTextAll("RED team wins this round!");
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
	CreateTimer(3.0, Timer_ExtractionStart);
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
	g_RoundStart = false;
	SearchSpawns();
}

public void Event_ResetMap(Event event, const char[] name, bool dontBroadcast)
{
	if ((g_PluginEnabled == false) && (GetConVarFloat(cvar_tdm_enabled) == 1.0)) return;
	g_RoundStart = true;
	VariablesToZero();
}

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
	ent = -1;
	while (((ent = FindEntityByClassname(ent, "func_nmrih_extractionzone")) != -1) && (g_ExtractionStarted == false))
	{
		if (IsValidEntity(ent))
		{
			//AcceptEntityInput(ent, "Start");
			float ent_origin[3];
			GetEntPropVector(ent, Prop_Data, "m_vecOrigin", ent_origin);
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
			
			for (int i = 0; i < TEAM_MAXPLAYERS; i++)
			{
				if (team[i] != -1)
				{
					if (IsClientInGame(team[i]))
					{
						if (IsPlayerAlive(team[i])) TeleportEntity(team[i], target_pos, NULL_VECTOR, NULL_VECTOR);
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
	for (int i = 0; i < TEAM_MAXPLAYERS; i++)
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
	/*
	angles[0] = 0.0;
	angles[1] -= 180.0;
	angles[2] = client_angles[2];
	*/
	if (angles[0] >= 270)
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
	// TELEPORTS RED PLAYER (OR GK) TO BASE
	if (client == g_GK_red)
	{
		float dest_gk_location[3];
		dest_gk_location[0] = (g_OriginRed[0] + g_Origin_Red_Goal[0])/2.0;
		dest_gk_location[1] = (g_OriginRed[1] + g_Origin_Red_Goal[1])/2.0;
		dest_gk_location[2] = (g_OriginRed[2] + g_Origin_Red_Goal[2])/2.0;
		TeleportEntity(client, dest_gk_location, angles, NULL_VECTOR);
	}
	else
	{
		TeleportEntity(client, g_OriginRed, angles, NULL_VECTOR);
	}
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
	/*
	angles[0] = 0.0;
	angles[1] -= 180.0;
	angles[2] = client_angles[2];
	*/
	if (angles[0] >= 270)
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
	// TELEPORTS BLUE PLAYER TO BASE
	if (client == g_GK_blue)
	{
		float dest_gk_location[3];
		dest_gk_location[0] = (g_OriginBlue[0] + g_Origin_Blue_Goal[0])/2.0;
		dest_gk_location[1] = (g_OriginBlue[1] + g_Origin_Blue_Goal[1])/2.0;
		dest_gk_location[2] = (g_OriginBlue[2] + g_Origin_Blue_Goal[2])/2.0;
		TeleportEntity(client, dest_gk_location, angles, NULL_VECTOR);
	}
	else
	{
		TeleportEntity(client, g_OriginBlue, angles, NULL_VECTOR);
	}
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
			for (int i = 0; i < TEAM_MAXPLAYERS; i++)
			{
				g_BluePlayers[i] = -1;
				g_RedPlayers[i] = -1;
			}
		}
		// SoccerMod
		/*
		case 1:
		{
			
		}
		*/
	}
}

void MatchVariablesZero()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		RemoveFromTeam(i);
		g_VotingPlayers[i] = -1;
		//RemoveHat(i);
	}
	for (int i = 0; i < TEAM_MAXPLAYERS; i++)
	{
		g_BluePlayers[i] = -1;
		g_RedPlayers[i] = -1;
	}
	g_BlueCount = 0;
	g_RedCount = 0;
	g_RedScore = 0;
	g_BlueScore = 0;
	g_GK_red = -1;
	g_GK_blue = -1;
	g_PlayerCount = 0;
	g_VotingCount = 0;
	g_LastScore = 0;
}

public void AddPlayerToArray(int client, int[] array, bool alive)
{
	// USAGE
	// AddPlayerToArray(client, g_BluePlayers, true);
	if (client < 1) return;
	if ((alive == true) && (!IsPlayerAlive(client))) return;
	// SEARCH A FREE SLOT INSIDE ARRAY
	for (int i = 0; i < TEAM_MAXPLAYERS; i++)
	{
		// ADDS CLIENT INDEX TO ARRAY
		if (array[i] < 1)
		{
			array[i] = client;
			break;
		}
	}
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

void RemoveFromTeam (int client)
{
	for (int i = 0; i < TEAM_MAXPLAYERS; i++)
	{
		if (g_RedPlayers[i] == client)
		{
			g_RedPlayers[i] = -1;
			g_RedCount = g_RedCount - 1;
			AcceptEntityInput(client, "disableglow");
			CPrintToChat(client, "[{lime}TDM{default}] Removed from {fullred}RED{default} team.");
			break;
		}
		if (g_BluePlayers[i] == client)
		{
			g_BluePlayers[i] = -1;
			g_BlueCount = g_BlueCount - 1;
			AcceptEntityInput(client, "disableglow");
			CPrintToChat(client, "[{lime}TDM{default}] Removed from {fullblue}BLUE{default} team.");
			break;
		}
	}
}

void SearchSpawns()
{
	char ent_name[64];
	int ent = -1;
	bool b_active = false;
	switch (g_GameMode)
	{
		case 0:
		{
			// CLASSIC TDM - SIMPLE WAY TO GET ORIGINS FROM SPAWNS
			b_active = false;
			while (((ent = FindEntityByClassname(ent,"info_player_nmrih")) != -1) && (g_Warmup == true))
			{
				GetEntPropString(ent, Prop_Data, "m_iName", ent_name, sizeof(ent_name));
				if (StrContains(ent_name, "defender_", false) >= 0)
				{
					b_active = true;
					GetEntPropVector(ent, Prop_Data, "m_vecOrigin", g_OriginBlue);
					if (GetConVarFloat(cvar_tdm_debug) == 1.0)
					{
						PrintToServer("[TDM] Successfully found %s origin.", ent_name);
						LogMessage("[TDM] Successfully found %s origin.", ent_name);
					}
					break;
				}
			}
			if (b_active == false)
			{
				PrintToServer("[TDM] WARNING: Entity %s not found in map.", ent_name);
				LogMessage("[TDM] WARNING: Entity %s not found in map.", ent_name);
			}
			ent = -1;
			b_active = false;
			while (((ent = FindEntityByClassname(ent,"info_player_nmrih")) != -1) && (g_Warmup == true))
			{
				GetEntPropString(ent, Prop_Data, "m_iName", ent_name, sizeof(ent_name));
				if (StrContains(ent_name, "attacker_", false) >= 0)
				{
					b_active = true;
					GetEntPropVector(ent, Prop_Data, "m_vecOrigin", g_OriginRed);
					if (GetConVarFloat(cvar_tdm_debug) == 1.0)
					{
						PrintToServer("[TDM] Successfully found %s origin.", ent_name);
						LogMessage("[TDM] Successfully found %s origin.", ent_name);
					}
					break;
				}
			}
			if (b_active == false)
			{
				PrintToServer("[TDM] WARNING: Entity %s not found in map.", ent_name);
				LogMessage("[TDM] WARNING: Entity %s not found in map.", ent_name);
			}
		}
		case 1:
		{
			// SoccerMod - SIMPLE WAY TO GET TELEPORTS ORIGINS
			b_active = false;
			while (((ent = FindEntityByClassname(ent,"info_teleport_destination")) != -1) && (g_Warmup == true))
			{
				GetEntPropString(ent, Prop_Data, "m_iName", ent_name, sizeof(ent_name));
				if (StrEqual(ent_name, "TeledestinationCt", false))
				{
					b_active = true;
					GetEntPropVector(ent, Prop_Data, "m_vecOrigin", g_OriginBlue);
					if (GetConVarFloat(cvar_tdm_debug) == 1.0)
					{
						PrintToServer("[TDM] Successfully found %s origin.", ent_name);
						LogMessage("[TDM] Successfully found %s origin.", ent_name);
						PrintToServer("[TDM] BLUE origin X = %0.1f", g_OriginBlue[0]);
						PrintToServer("[TDM] BLUE origin Y = %0.1f", g_OriginBlue[1]);
						PrintToServer("[TDM] BLUE origin Z = %0.1f", g_OriginBlue[2]);
					}
					break;
				}
			}
			if (b_active == false)
			{
				PrintToServer("[TDM] WARNING: Entity %s not found in map.", ent_name);
				LogMessage("[TDM] WARNING: Entity %s not found in map.", ent_name);
			}
			ent = -1;
			b_active = false;
			while (((ent = FindEntityByClassname(ent,"info_teleport_destination")) != -1) && (g_Warmup == true))
			{
				GetEntPropString(ent, Prop_Data, "m_iName", ent_name, sizeof(ent_name));
				if (StrEqual(ent_name, "TeledestinationT", false))
				{
					b_active = true;
					GetEntPropVector(ent, Prop_Data, "m_vecOrigin", g_OriginRed);
					if (GetConVarFloat(cvar_tdm_debug) == 1.0)
					{
						PrintToServer("[TDM] Successfully found %s origin.", ent_name);
						LogMessage("[TDM] Successfully found %s origin.", ent_name);
						PrintToServer("[TDM] RED origin X = %0.1f", g_OriginRed[0]);
						PrintToServer("[TDM] RED origin Y = %0.1f", g_OriginRed[1]);
						PrintToServer("[TDM] RED origin Z = %0.1f", g_OriginRed[2]);
					}
					break;
				}
			}
			if (b_active == false)
			{
				PrintToServer("[TDM] WARNING: Entity %s not found in map.", ent_name);
				LogMessage("[TDM] WARNING: Entity %s not found in map.", ent_name);
			}
			// SoccerMod - GOAL LINE POSITION
			ent = -1;
			int k = 0;
			b_active = false;
			while ((ent = FindEntityByClassname(ent, "trigger_multiple")) != -1)
			{
				GetEntPropString(ent, Prop_Data, "m_iName", ent_name, sizeof(ent_name));
				if (StrEqual(ent_name, "terro_But", true))
				{
					b_active = true;
					GetEntPropVector(ent, Prop_Data, "m_vecOrigin", g_Origin_Red_Goal);
					PrintToServer("[TDM] Successfully found %s origin.", ent_name);
					LogMessage("[TDM] Successfully found %s origin.", ent_name);
					k++;
				}
				if (StrEqual(ent_name, "ct_But", true))
				{
					b_active = true;
					GetEntPropVector(ent, Prop_Data, "m_vecOrigin", g_Origin_Blue_Goal);
					PrintToServer("[TDM] Successfully found %s origin.", ent_name);
					LogMessage("[TDM] Successfully found %s origin.", ent_name);
					k++;
				}
				if (k >= 2) break;
			}
			if (b_active == false)
			{
				PrintToServer("[TDM] WARNING: Entity %s not found in map.", ent_name);
				LogMessage("[TDM] WARNING: Entity %s not found in map.", ent_name);
			}
			// END OF PRE-CONFIG
		}
	}
}

bool IsPlayerRed(int client)
{
	bool player_red = false;
	for (int i = 0; i < TEAM_MAXPLAYERS; i++)
	{
		if(g_RedPlayers[i] == client)
		{
			player_red = true;
			break;
		}
	}
	return player_red;
}

bool IsPlayerBlue(int client)
{
	bool player_blue = false;
	for (int i = 0; i < TEAM_MAXPLAYERS; i++)
	{
		if(g_BluePlayers[i] == client)
		{
			player_blue = true;
			break;
		}
	}
	return player_blue;
}

public Action Timer_Global(Handle timer)
{
	if ((h_T_Global != timer) || (h_T_Global == null)) return Plugin_Stop;
	if ((g_PluginEnabled == false) && (GetConVarFloat(cvar_tdm_enabled) == 1.0)) return Plugin_Continue;
	// REFRESH PLAYER COLORS & SCOREBOARD
	for (int i = 0; i < TEAM_MAXPLAYERS; i++)
	{
		if (g_RedPlayers[i] > 0)
		{
			if (IsClientInGame(g_RedPlayers[i]))
			{
				if (g_Warmup == false)
				{
					if (g_RedPlayers[i] == g_GK_red) PrintHintText(g_RedPlayers[i], "YOU ARE RED *GOALKEEPER*   |   RED %d  -  BLUE %d   |", g_RedScore, g_BlueScore);
					else PrintHintText(g_RedPlayers[i], "|   RED %d  -  BLUE %d   |   YOU ARE RED PLAYER", g_RedScore, g_BlueScore);
				}
				if (IsPlayerAlive(g_RedPlayers[i]))
				{
					//if (g_RoundStart) TeleportBackRed(g_RedPlayers[i]);
					if (i == 0) DispatchKeyValue(g_RedPlayers[i], "glowcolor", RED_COLOR_1);
					else if (i == 1) DispatchKeyValue(g_RedPlayers[i], "glowcolor", RED_COLOR_2);
					else if (i == 2) DispatchKeyValue(g_RedPlayers[i], "glowcolor", RED_COLOR_3);
					else if (i == 3) DispatchKeyValue(g_RedPlayers[i], "glowcolor", RED_COLOR_4);
					else if (i == 4) DispatchKeyValue(g_RedPlayers[i], "glowcolor", RED_COLOR_5);
					SetEntityRenderColor(g_RedPlayers[i], 255, 92, 92, 255);
				}
			}
		}
		if (g_BluePlayers[i] > 0)
		{
			if (IsClientInGame(g_BluePlayers[i]))
			{
				if (g_Warmup == false)
				{
					if (g_BluePlayers[i] == g_GK_blue) PrintHintText(g_BluePlayers[i], "YOU ARE BLUE *GOALKEEPER*   |   BLUE %d  -  RED %d   |", g_BlueScore, g_RedScore);
					else PrintHintText(g_BluePlayers[i], "|   BLUE %d  -  RED %d   |   YOU ARE BLUE PLAYER", g_BlueScore, g_RedScore);
				}
				if (IsPlayerAlive(g_BluePlayers[i]))
				{
					//if (g_RoundStart) TeleportBackBlue(g_BluePlayers[i]);
					if (i == 0) DispatchKeyValue(g_BluePlayers[i], "glowcolor", BLUE_COLOR_1);
					else if (i == 1) DispatchKeyValue(g_BluePlayers[i], "glowcolor", BLUE_COLOR_2);
					else if (i == 2) DispatchKeyValue(g_BluePlayers[i], "glowcolor", BLUE_COLOR_3);
					else if (i == 3) DispatchKeyValue(g_BluePlayers[i], "glowcolor", BLUE_COLOR_4);
					else if (i == 4) DispatchKeyValue(g_BluePlayers[i], "glowcolor", BLUE_COLOR_5);
					SetEntityRenderColor(g_BluePlayers[i], 92, 92, 255, 255);
				}
			}
		}
	}
	if (g_GK_red > 0)
	{
		if (IsPlayerAlive(g_GK_red))
		{
			DispatchKeyValue(g_GK_red, "glowcolor", "200 100 0");
			SetEntityRenderColor(g_GK_red, 255, 255, 255, 255);
		}
	}
	if (g_GK_blue > 0)
	{
		if (IsPlayerAlive(g_GK_blue))
		{
			DispatchKeyValue(g_GK_blue, "glowcolor", "100 200 255");
			SetEntityRenderColor(g_GK_blue, 255, 255, 255, 255);
		}
	}
	return Plugin_Continue;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &iImpulse, float fVelocity[3], float fAngles[3], int &iWeapon) 
{
	if (g_GameMode != 1) return Plugin_Continue;
	if (IsClientInGame(client))
	{
		if (IsPlayerAlive(client))
		{
			// PREVENTS ADDING SAME PLAYER TO SAME TEAM AGAIN
			if ((g_RedCount < (TEAM_MAXPLAYERS-1)) && (g_RedCount < g_BlueCount) && (IsPlayerRed(client) == false) && (IsPlayerBlue(client) == false))
			{
				AddPlayerToArray(client, g_RedPlayers, false);
				GetClientName(client, g_PlayerName[client], sizeof(g_PlayerName[]));
				CPrintToChatAll("[{lime}TDM{default}] %s has joined {fullred}RED{default} team.", g_PlayerName[client]);
			}
			if ((g_BlueCount < (TEAM_MAXPLAYERS-1)) && (g_BlueCount <= g_RedCount) && (IsPlayerRed(client) == false) && (IsPlayerBlue(client) == false))
			{
				// CHECK IF POSSIBLE TO ADD TO BLUE TEAM
				AddPlayerToArray(client, g_BluePlayers, false);
				GetClientName(client, g_PlayerName[client], sizeof(g_PlayerName[]));
				CPrintToChatAll("[{lime}TDM{default}] %s has joined {fullblue}BLUE{default} team.", g_PlayerName[client]);	
			}
			// CHECKS IF GK IS INSIDE HIS OWN AREA TO USE SPECIAL SKILL
			if ((client == g_GK_blue) || (client == g_GK_red))
			{
				float gk_pos[3];
				GetClientAbsOrigin(client, gk_pos);
				
				float distance;
				if (client == g_GK_red) distance = GetVectorDistance(gk_pos, g_Origin_Red_Goal);
				else if (client == g_GK_blue) distance = GetVectorDistance(gk_pos, g_Origin_Blue_Goal);
				if (distance <= SOCCERMOD_GK_DISTANCE)
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
			}
		}
	}
}