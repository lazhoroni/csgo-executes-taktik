#pragma semicolon 1
#include <sourcemod>
#include <cstrike>
#include <sdktools>
#include <sdkhooks>
#include <clientprefs>
#include <smlib>

public Plugin:myinfo = 
{
	name        = "Executes",
	author      = "Ofir", 
	description = "Execute Simulation",
	version     = "1.0b",
	url         = "https://forums.alliedmods.net/member.php?u=190571"
};

//Enums and Contstants
#define PREFIX " \x05[Executes]\x04 "
#define MAXSPAWNS 64

#define A 0
#define B 1

#define MAX_T 4
#define MAX_CT 5

//#define DEBUG

enum Spawn
{
	Id,
	SpawnType:Type,
	Float:Location[3],
	Float:Angles[3],
	execID,
	bool:Used
};

enum Smoke
{
	Id,
	execID,
	Float:Location[3],
	Float:Velocity[3]
};

enum Execute
{
	Id,
	String:Name[64],
	Site
};

#define FL_USED_CT (1 << 0)
#define FL_USED_T (1 << 1)
#define GRENADESSETCOUNT 4

new const String:gs_GrenadeSets[][][64] = {
	{"weapon_hegrenade", "weapon_flashbang"},
	{"weapon_hegrenade", "none"},
	{"weapon_flashbang", "none"},
	{"moli", "none"}
};

new gi_GrenadeSetsFlags[GRENADESSETCOUNT];

//Cvars Handlers
new Handle:gh_PistolRoundsCount = INVALID_HANDLE;
new Handle:gh_WinRowScramble = INVALID_HANDLE;

//Cvars Vars
new gi_PistolRoundsCount;
new gi_WinRowScramble;

//Players Arrays
new bool:gb_PreferenceLoaded[MAXPLAYERS+1] = {false, ...};
new gi_WantAwp[MAXPLAYERS+1] = {0, ...};
new bool:gb_WantSilencer[MAXPLAYERS+1] = {false, ...};
new gi_DamageCount[MAXPLAYERS+1];
new gi_NextRoundTeam[MAXPLAYERS+1] = {-1, ...};
new bool:gb_Warnned[MAXPLAYERS+1] = {false, ...};
new bool:gb_PluginSwitchingTeam[MAXPLAYERS+1] = {false, ...};
new bool:gb_Voted[MAXPLAYERS+1] = {false, ...};
new Float:gf_UsedVP[MAXPLAYERS+1];

//Global Vars
//new bool:gb_EditMode = false;
new bool:gb_EditMode = true;
new bool:gb_Scrambling = false;
new bool:gb_WaitForPlayers = true;
new bool:gb_WarmUp = false;
new bool:gb_balancedTeams = false;
new bool:gb_newClientsJoined = false;
new bool:gb_OnlyPistols = false;
new String:gs_CurrentMap[64];
new gi_MoneyOffset;
new gi_HelmetOffset;
new g_precacheLaser;
new g_Spawns[MAXSPAWNS][Spawn];
new g_SpawnsCount = 0;
new g_Smokes[MAXSPAWNS][Smoke];
new g_SmokesCount = 0;
new g_Executes[MAXSPAWNS][Execute];
new g_ExecutesCount = 0;
new gi_WinRowCounter = 0;
new gi_PlayerQueue[MAXPLAYERS+1];
new gi_QueueCounter;
new Float:gf_MapLoadTime;
new Float:gf_StartRoundTime;
new Handle:gh_MapLoadTimer;
new gi_Voters = 0;				// Total voters connected. Doesn't include fake clients.
new gi_Votes = 0;				// Total number of "say rtv" votes
new gi_VotesNeeded = 0;			// Necessary votes before map vote begins. (voters * percent_needed)
new gi_CurrentExecute;
new gi_CurrentExecuteSite;

//Cookies
new Handle:gh_SilencedM4 = INVALID_HANDLE;
new Handle:gh_WantAwp = INVALID_HANDLE;

//Sql
new Handle:gh_Sql = INVALID_HANDLE;
new gi_ReconncetCounter = 0;

//Admin
new gi_EditedExecuteID = -1;
new String:gs_ExecuteName[128];
new gi_EditedExecuteSite;
new bool:gb_AddingSmoke[MAXPLAYERS+1];
new Float:gf_AdminSmokePos[MAXPLAYERS+1][3];
new Float:gf_AdminSmokeVel[MAXPLAYERS+1][3];
new bool:gb_Editing = false;

int gi_Bot;
int gi_Stage;
int g_iNextAttackOffset = -1;
int gi_CurrentSmoke = -1;
new Float:gf_BotSmokePos[3];
new Float:gf_BotSmokeVel[3];


public OnPluginStart()
{
	g_iNextAttackOffset = FindSendPropOffs("CCSPlayer", "m_flNextAttack");

	//Convars
	gh_PistolRoundsCount = CreateConVar("executes_pistols", "5", "How much Pistols Rounds should be. 0 to disable", _, true, 0.0);
	gh_WinRowScramble = CreateConVar("executes_winrow", "7", "How much row the T's need to win for scramble. 0 to disable", _, true, 0.0);

	gi_PistolRoundsCount = GetConVarInt(gh_PistolRoundsCount);
	gi_WinRowScramble = GetConVarInt(gh_WinRowScramble);

	HookConVarChange(gh_PistolRoundsCount, Action_OnSettingsChange);
	HookConVarChange(gh_WinRowScramble, Action_OnSettingsChange);

	AutoExecConfig(true, "executes");
	//Admin Commands
	RegAdminCmd("sm_start", Command_Start, ADMFLAG_ROOT);
	RegAdminCmd("sm_scramble", Command_Scramble, ADMFLAG_ROOT);
	RegAdminCmd("sm_pistols", Command_OnlyPistols, ADMFLAG_ROOT);
	RegAdminCmd("sm_add", Command_AddExecute, ADMFLAG_ROOT);
	RegAdminCmd("sm_addct", Command_AddCTSpawn, ADMFLAG_ROOT);
	RegAdminCmd("sm_delct", Command_DeleteCTSpawn, ADMFLAG_ROOT);
	RegAdminCmd("sm_edit", Command_Edit, ADMFLAG_ROOT);
	RegAdminCmd("sm_execs", Command_Executes, ADMFLAG_ROOT);
	RegAdminCmd("sm_name", Command_Name, ADMFLAG_ROOT);
	RegAdminCmd("sm_site", Command_Site, ADMFLAG_ROOT);
	//Client Commands
	RegConsoleCmd("sm_guns", Command_Guns);
	RegConsoleCmd("sm_awp", Command_Guns);
	RegConsoleCmd("sm_m4", Command_Guns);
	RegConsoleCmd("sm_m4a1", Command_Guns);
	RegConsoleCmd("sm_m4a4", Command_Guns);
	RegConsoleCmd("sm_vp", Command_VotePistols);
	AddCommandListener(Command_Say, "say");
	AddCommandListener(Command_Say, "say_team");
	//Events
	HookEvent("round_prestart", Event_OnRoundPreStart);
	HookEvent("round_poststart", Event_OnRoundPostStart);
	HookEvent("round_end", Event_OnRoundEnd);
	HookEvent("player_connect_full", Event_OnFullConnect);
	HookEvent("player_team", Event_OnPlayerChangeTeam, EventHookMode_Pre);
	HookEvent("player_hurt", Event_OnPlayerDamaged);
	HookEvent("bomb_defused", Event_OnBombDefused);
	HookEvent("round_freeze_end", Event_OnFreezeTimeEnd);
	HookEvent("bomb_beginplant", Event_OnBombBeginPlant);
	//Listeners
	AddCommandListener(Hook_ChangeTeam, "jointeam");
	//Offsets
	gi_MoneyOffset = FindSendPropOffs("CCSPlayer", "m_iAccount");
	gi_HelmetOffset = FindSendPropOffs("CCSPlayer", "m_bHasHelmet");
	//Coockies
	gh_WantAwp = RegClientCookie("executes_awp", "Executes allow player play with awp", CookieAccess_Protected);
	gh_SilencedM4 = RegClientCookie("executes_m4", "Executes play with m4a1s or m4a4", CookieAccess_Protected);
	
	//Sql
	ConnectSQL();
	//Add Tag
	AddServerTag("executes");


	if(GetClientCountFix() >= 2)
	{
		gb_WaitForPlayers = false;
		SetConfig(false);
	}
}

public Action_OnSettingsChange(Handle:cvar, const String:oldvalue[], const String:newvalue[])
{
	if (cvar == gh_PistolRoundsCount)
	{
		gi_PistolRoundsCount = StringToInt(newvalue);
	}
	else if(cvar == gh_WinRowScramble)
	{
		gi_WinRowScramble = StringToInt(newvalue);
	}
}


public OnMapStart()
{
	//Map String to LowerCase
	GetCurrentMap(gs_CurrentMap, sizeof(gs_CurrentMap));
	new len = strlen(gs_CurrentMap);
	for(new i=0;i < len;i++)
	{
		gs_CurrentMap[i] = CharToLower(gs_CurrentMap[i]);
	}
	gb_EditMode = false;
	gb_OnlyPistols = false;
	LoadSpawns(true); // Load Spawns
	//Precahche models for edit mode
	g_precacheLaser = PrecacheModel("materials/sprites/laserbeam.vmt");
	gi_EditedExecuteID = -1;

	//thanks shavit
	ConVar cvar = FindConVar("bot_controllable");

	if(cvar != null)
	{
		cvar.SetBool(false);
	}

	cvar = FindConVar("bot_quota_mode");
	cvar.SetString("normal");

	cvar = FindConVar("mp_autoteambalance");
	cvar.SetBool(false);

	cvar = FindConVar("mp_limitteams");
	cvar.SetInt(0);

	cvar = FindConVar("bot_join_after_player");
	cvar.SetBool(false);

	cvar = FindConVar("bot_chatter");
	cvar.SetString("off");

	cvar = FindConVar("bot_auto_vacate");
	cvar.SetBool(false);

	cvar = FindConVar("bot_zombie");
	cvar.Flags = cvar.Flags & ~FCVAR_CHEAT;
	cvar.SetBool(true);

	cvar = FindConVar("bot_join_team");
	cvar.SetString("T");

	cvar = FindConVar("bot_join_after_player");
	cvar.SetBool(false);

	cvar = FindConVar("bot_stop");
	cvar.Flags = cvar.Flags & ~FCVAR_CHEAT;
	cvar.SetBool(true);

	ServerCommand("bot_kick");

	ServerCommand("bot_quota 1");

	#if defined DEBUG
	gb_EditMode = true;
	PrintToChatAll("%sEdit mode is now %s", PREFIX, gb_EditMode ? "Enabled":"Disabled");
	if(gb_EditMode)
	{
		CreateTimer(0.1, DrawAdminPanel, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	}
	SetConfig(gb_EditMode);
	ServerCommand("mp_restartgame 1");
	#else
	SetConfig(true);
	gi_QueueCounter  = 0;
	for (new i = 1; i < MaxClients; i++)
	{
		if(IsClientInGame(i) && !IsFakeClient(i))
		{
			LoadClientCoockies(i);
			if(GetClientTeam(i) == 1)
			{
				AddPlayerToQueue(i);
			}
		}
	}
	
	gb_WarmUp = true;
	PrintToChatAll("%sExecutes will start in 30 seconds", PREFIX);
	gh_MapLoadTimer = CreateTimer(30.0, Timer_MapLoadDelay, _);
	gf_MapLoadTime = GetEngineTime();
	CreateTimer(0.1, Timer_PrintHintWarmup, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

	gi_WinRowCounter = 0;
	gi_Voters = 0;
	gi_Votes = 0;
	gi_VotesNeeded = 0;

	for (new i=1; i<=MaxClients; i++)
	{
		if (IsClientConnected(i))
		{
			OnClientConnected(i);	
		}	
	}
	#endif
}

public OnClientConnected(client)
{
	gb_Voted[client] = false;

	gi_Voters++;
	gi_VotesNeeded = RoundToFloor(float(gi_Voters) * 0.5);
	gf_UsedVP[client] = -100.0;
	return;
}

public OnClientDisconnect(client)
{
	if(gb_Voted[client])
	{
		gi_Votes--;
	}
	
	gi_Voters--;
	
	gi_VotesNeeded = RoundToFloor(float(gi_Voters) * 0.5);
	
	if (gi_VotesNeeded < 1)
	{
		return;	
	}
	
	if (gi_Votes && 
		gi_Voters && 
		gi_Votes >= gi_VotesNeeded 
		) 
	{
		ToggleVP();
	}	
}

LoadClientCoockies(client)
{
	if(IsFakeClient(client))
	return;
	decl String:buffer[16];
	new bool:openGunsMenu = false;

	GetClientCookie(client, gh_WantAwp, buffer, sizeof(buffer));
	if(!StrEqual(buffer, ""))
	gi_WantAwp[client] = StringToInt(buffer);
	else
	openGunsMenu = true;

	GetClientCookie(client, gh_SilencedM4, buffer, sizeof(buffer));
	if(!StrEqual(buffer, ""))
	gb_WantSilencer[client] = bool:StringToInt(buffer);
	else
	openGunsMenu = true;

	gb_PreferenceLoaded[client] = !openGunsMenu;
}

public OnClientCookiesCached(client)
{
	LoadClientCoockies(client);
}

public Event_OnFullConnect(Handle:event, const String:name[], bool:dontBroadcast) 
{
	if(!gb_EditMode && !gb_WarmUp)
	{
		new client = GetClientOfUserId(GetEventInt(event, "userid"));
		if(GetClientCountFix() > 1)
		{
			SetEntPropFloat(client, Prop_Send, "m_fForceTeam", 3600.0);
		}
		if(!gb_PreferenceLoaded[client])
		{
			Command_Guns(client, 0);
		}
	}
}

AddPlayerToQueue(client)
{
	if(IsClientSourceTV(client) || IsFakeClient(client))
	return;

	for (new i = 0; i < gi_QueueCounter; i++)
	{
		if(client == gi_PlayerQueue[i])
		{
			return;
		}
	}
	gi_PlayerQueue[gi_QueueCounter] = client;
	gi_QueueCounter++;
	PrintToChat(client, "%sYou are now \x02%d\x04 place in the queue", PREFIX, gi_QueueCounter);
	if(gi_QueueCounter == MAXPLAYERS)
	{
		gi_QueueCounter = 0;
	}
	return;
}

public OnClientDisconnect_Post(client)
{
	gb_Warnned[client] = false;
	gi_NextRoundTeam[client] = -1;
	if(!gb_WaitForPlayers && GetClientCountFix() < 2)
	{
		gb_WaitForPlayers = true;
		SetConfig(true);
	}
	gb_PreferenceLoaded[client] = false;
	new index = -1;
	for (new i = 0; i < gi_QueueCounter; i++)
	{
		if(client == gi_PlayerQueue[i])
		{
			index = i;
			break;
		}
	}
	if(index != -1)
	{
		DeletePlayerFromQueue(client);
	}
}

public Action:Event_OnPlayerChangeTeam(Handle:event, const String:name[], bool:dontBroadcast) 
{
	dontBroadcast = true;
	if(!gb_WarmUp && gb_WaitForPlayers)
	{
		if(GetClientCountFix() >= 2)
		{
			gb_WaitForPlayers = false;
			ServerCommand("mp_restartgame 5");
			SetConfig(false);
		}
		else
		{
			PrintToChatAll("%sWaiting for players to join", PREFIX);
		}
	}
	return Plugin_Changed;
}

public Action:Event_OnPlayerDamaged(Handle:event, const String:name[],bool:dontBroadcast)
{
	new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	new dhealth = GetEventInt(event, "dmg_health");

	gi_DamageCount[attacker] += dhealth;
}

public Action:Event_OnBombDefused(Handle:event, const String:name[],bool:dontBroadcast)
{
	new defuser = GetClientOfUserId(GetEventInt(event, "userid"));
	if(GetTeamAliveClientCount(2) > 0)
	{
		PrintToChatAll("%sNINJA DEFUSE", PREFIX);
		gi_DamageCount[defuser] += 100;
	}
}

public Action:Event_OnBombBeginPlant(Handle:event, const String:name[],bool:dontBroadcast)
{
	new bomber = GetClientOfUserId(GetEventInt(event, "userid"));
	new index = FindEntityByClassname(-1, "cs_player_manager");
	if (index != -1)
	{
		new Float:fOrg[3];
		GetClientAbsOrigin(bomber, fOrg);

		new Float:vecBombsiteCenterA[3];
		new Float:vecBombsiteCenterB[3];
		GetEntPropVector(index, Prop_Send, "m_bombsiteCenterA", vecBombsiteCenterA);
		GetEntPropVector(index, Prop_Send, "m_bombsiteCenterB", vecBombsiteCenterB);

		new Float:distA = GetVectorDistance(vecBombsiteCenterA, fOrg);
		new Float:distB = GetVectorDistance(vecBombsiteCenterB, fOrg);

		if(distB > distA)
		{
			//planted at A
			if(gi_CurrentExecuteSite != A)
			{
				KickClient(bomber, "You cant plant the bomb at this site");
			}
		}
		else
		{
			//planted at B
			if(gi_CurrentExecuteSite != B)
			{
				KickClient(bomber, "You cant plant the bomb at this site");
			}
		}
	}
}

public Event_OnFreezeTimeEnd(Handle:event, const String:name[], bool:dontBroadcast) 
{
	if(!gb_EditMode && !gb_WaitForPlayers && !gb_WarmUp)
	{
		for (new i = 0; i < g_SmokesCount; i++)
		{
			if(g_Smokes[i][execID] != gi_CurrentExecute)
			continue;

			gi_CurrentSmoke = i;
			new Float:org[3], Float:vel[3];
			Array_Copy(g_Smokes[i][Location], org, 3);
			Array_Copy(g_Smokes[i][Velocity], vel, 3);
			ThrowSmoke(org, vel);
			break;
		}
	}
}

public Action:Hook_ChangeTeam(client, const String:command[], args)
{
	if (args < 1)
	return Plugin_Handled;

	char arg[4];
	GetCmdArg(1, arg, sizeof(arg));
	int team_to = StringToInt(arg);
	int team_from = GetClientTeam(client);

	if ((team_from == team_to && team_from != CS_TEAM_NONE) || gb_PluginSwitchingTeam[client] || IsFakeClient(client) || gb_EditMode || gb_WaitForPlayers || gb_WarmUp) 
	{
		return Plugin_Continue;
	}
	
	if ((team_from == CS_TEAM_CT && team_to == CS_TEAM_T )
		|| (team_from == CS_TEAM_T  && team_to == CS_TEAM_CT)) 
	{
		return Plugin_Handled;
	}

	SwitchPlayerTeam(client, 1);
	AddPlayerToQueue(client);
	return Plugin_Handled;
}

public Event_OnRoundPreStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	if(!gb_EditMode)
	{	
		if(!gb_balancedTeams)
		{
			SetQueueClients();
			gb_balancedTeams = true;
		}
		else
		{
			gb_balancedTeams = false;
		}
		if(!gb_newClientsJoined)
		{
			for (new i = 1; i <= MaxClients; i++)
			{
				if(IsClientInGame(i) && !IsFakeClient(i) && gi_NextRoundTeam[i] == -1)
				{
					gi_NextRoundTeam[i] = GetClientTeam(i);
				}
			}
			BalanceTeams();
		}
		gb_newClientsJoined = false;
		for (new i = 1; i <= MaxClients; i++)
		{
			if(IsClientInGame(i) && !IsClientSourceTV(i) && !IsFakeClient(i) && gi_NextRoundTeam[i] != -1)
			{
				if(gi_NextRoundTeam[i] == 1)
				{
					SwitchPlayerTeam(i, 1);
				}
				else
				{
					SwitchPlayerTeam(i, gi_NextRoundTeam[i], false);
					CS_UpdateClientModel(i);
				}
			}
		}
		for (new i = 0; i < MAXPLAYERS; i++)
		{
			gi_NextRoundTeam[i] = -1;
		}
	}
}

public Event_OnRoundPostStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	if(!gb_EditMode && !gb_WaitForPlayers && !gb_WarmUp)
	{
		new executeIndex = GetRandomInt(0, g_ExecutesCount-1);
		gi_CurrentExecute = g_Executes[executeIndex][Id];
		gi_CurrentExecuteSite = g_Executes[executeIndex][Site];

		//Reset spawn use and roundkills
		for (new i = 0; i < GRENADESSETCOUNT; i++)
		{
			gi_GrenadeSetsFlags[i] = 0;
		}
		for (new i = 0; i < g_SpawnsCount; i++)
		{
			g_Spawns[i][Used] = false;
		}
		for (new i = 0; i < MAXPLAYERS; i++)
		{
			gi_DamageCount[i] = 0;
		}

		//Random awper for each team
		new awpCt = GetRandomAwpPlayer(3);
		new awpT = GetRandomAwpPlayer(2);

		//Get Bomber
		new bomber = GetRandomPlayerFromTeam(2);
		new randomSpawn = -1;
		new randomGrenadeSet = -1;
		new Float:loc[3], Float:ang[3];
		new bool:pistols = CS_GetTeamScore(3) + CS_GetTeamScore(2) < gi_PistolRoundsCount || gb_OnlyPistols;
		for (new i = 1; i <= MaxClients; i++)
		{
			if(IsClientInGame(i) && !IsClientSourceTV(i) && GetClientTeam(i) != 1)
			{
				if(IsFakeClient(i))
				{
					TeleportEntity(i, Float:{-35000.0, -35000.0, -35000.0}, Float:{0.0, 0.0, 0.0}, Float:{0.0, 0.0, 0.0});
					continue;
				}
				//Set Money to 0$
				SetEntData(i, gi_MoneyOffset, 0);
				SetEntProp(i, Prop_Data, "m_ArmorValue", 100);
				Client_RemoveAllWeapons(i);
				randomSpawn = -1;
				if(GetClientTeam(i) == 3)
				{
					randomSpawn = GetRandomCTSpawn();
					if(randomSpawn != -1)
					{
						Array_Copy(g_Spawns[randomSpawn][Location], loc, 3);
						Array_Copy(g_Spawns[randomSpawn][Angles], ang, 3);
						g_Spawns[randomSpawn][Used] = true;
						TeleportEntity(i, loc, ang, NULL_VECTOR);
					}
				}
				else
				{
					PrintToChat(i, "%sExecuted: \x02%s", PREFIX, g_Executes[executeIndex][Name]);
					if(bomber == i)
						GivePlayerItem(i, "weapon_c4");
					randomSpawn = GetRandomTSpawn(gi_CurrentExecute);
					if(randomSpawn != -1)
					{
						Array_Copy(g_Spawns[randomSpawn][Location], loc, 3);
						Array_Copy(g_Spawns[randomSpawn][Angles], ang, 3);
						g_Spawns[randomSpawn][Used] = true;
						TeleportEntity(i, loc, ang, NULL_VECTOR);
					}
				}
				//Give Grenades
				if(!pistols)
				{
					SetEntData(i, gi_HelmetOffset, 1);
					randomGrenadeSet = GetRandomGrenadeSet(GetClientTeam(i));
					if(randomGrenadeSet != -1)
					{
						if(GetClientTeam(i) == 3)
							gi_GrenadeSetsFlags[randomGrenadeSet] = gi_GrenadeSetsFlags[randomGrenadeSet] | FL_USED_CT;
						else if(GetClientTeam(i) == 2)
							gi_GrenadeSetsFlags[randomGrenadeSet] = gi_GrenadeSetsFlags[randomGrenadeSet] | FL_USED_T;
						for (new k = 0; k < 2; k++)
						{
							if(!StrEqual("none", gs_GrenadeSets[randomGrenadeSet][k]))
							{
								if(!StrEqual("moli", gs_GrenadeSets[randomGrenadeSet][k]))
									GivePlayerItem(i, gs_GrenadeSets[randomGrenadeSet][k]);
								else if(GetClientTeam(i) == 3)
									GivePlayerItem(i, "weapon_incgrenade");
								else
									GivePlayerItem(i, "weapon_molotov");
								
							}
						}
					}
				}
				if(pistols)
				{
					SetEntData(i, gi_HelmetOffset, 0);
				}
				//Give Weapons
				GivePlayerItem(i, "weapon_knife");
				if((awpCt == i || awpT == i) && !pistols)
				{
					GivePlayerItem(i, "weapon_awp");
					if(GetClientTeam(i) == 3)
					GivePlayerItem(i, "weapon_hkp2000");
					else
					GivePlayerItem(i, "weapon_glock");
				}
				else
				{
					if(GetClientTeam(i) == 3)
					{
						if(!pistols)
						{
							if(!gb_WantSilencer[i])
							GivePlayerItem(i, "weapon_m4a1");
							else
							GivePlayerItem(i, "weapon_m4a1_silencer");
						}
						GivePlayerItem(i, "weapon_hkp2000");
					}
					else
					{
						if(!pistols)
						{
							GivePlayerItem(i, "weapon_ak47");
						}
						GivePlayerItem(i, "weapon_glock");
					}
				}
			}
		}	
		if(bomber != -1)
			if(IsClientInGame(bomber) && !IsFakeClient(bomber))
				FakeClientCommand(bomber, "use weapon_c4");
	}
}

public Event_OnRoundEnd(Handle:event, const String:name[], bool:dontBroadcast)
{
	new bool:queueplayers = true;
	if(!gb_EditMode)
	{
		gb_balancedTeams = true;
		if(GetEventInt(event, "winner") == 3)
		{
			gi_WinRowCounter = 0;
			//Move top Killers to T
			new DamageList[MaxClients];
			new IndexList[MaxClients];
			new count = 0;
			new terrorCount = RoundToFloor(GetClientCountFix(false) / 2.0);
			if(terrorCount > MAX_T)
				terrorCount = MAX_T;
			for (new i = 1; i <= MaxClients; i++)
			{
				if(IsClientInGame(i) && !IsFakeClient(i))
				{
					if(GetClientTeam(i) == 3)
					{
						DamageList[count] = gi_DamageCount[i];
						IndexList[count] = i;
						count++;
					}
					else if (GetClientTeam(i) == 2)
					{
						gi_NextRoundTeam[i] = 3;
					}
				}
			}
			new temp;
			new temp2;
			for (new i = 0; i < count; i++)
			{
				for (new j = i+1; j < count; j++)
				{
					if(DamageList[i] < DamageList[j])
					{
						temp = DamageList[i];
						temp2 = IndexList[i];
						DamageList[i] = DamageList[j];
						IndexList[i] = IndexList[j];
						DamageList[j] = temp;
						IndexList[j] = temp2;
					}
				}
			}
			for (new i = 0; i < terrorCount; i++)
			{
				gi_NextRoundTeam[IndexList[i]] = 2;
			}
		}
		else if (GetEventInt(event, "winner") == 2)
		{
			gi_WinRowCounter++;
			if(gi_WinRowCounter == gi_WinRowScramble || gb_Scrambling)
			{
				//Scramble Players
				gi_WinRowCounter = 0;
				gb_Scrambling = false;
				queueplayers = false;
				ScrambleTeams(false);
			}
			else
			{
				for (new i = 1; i < MaxClients; i++)
				{
					if(IsClientInGame(i) && !IsFakeClient(i) && gi_NextRoundTeam[i] == -1)
					{
						gi_NextRoundTeam[i] = GetClientTeam(i);
					}
				}
				if(gi_WinRowCounter > gi_WinRowScramble - 3)
				PrintToChatAll("%sThe Terror need to take \x02%d\x04 more rounds in a row to scramble", PREFIX, gi_WinRowScramble - gi_WinRowCounter);
			}
		}
		if(queueplayers)
			SetQueueClients();
	}
}

BalanceTeams()
{
	//Balance Team if not Balanced
	new terrorCount = RoundToFloor(GetClientCountFix(false) / 2.0);
	if(terrorCount > MAX_T)
		terrorCount = MAX_T;
	if(terrorCount < GetNextTeamCount(2, true))
	{
		new DamageList[MaxClients];
		new IndexList[MaxClients];
		new count = 0;
		for (new i = 1; i <= MaxClients; i++)
		{
			if(IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == 2)
			{
				DamageList[count] = GetClientFrags(i);
				IndexList[count] = i;
				count++;
			}
		}
		new temp;
		new temp2;
		for (new i = 0; i < count; i++)
		{
			for (new j = i+1; j < count; j++)
			{
				if(DamageList[i] < DamageList[j])
				{
					temp = DamageList[i];
					temp2 = IndexList[i];
					DamageList[i] = DamageList[j];
					IndexList[i] = IndexList[j];
					DamageList[j] = temp;
					IndexList[j] = temp2;
				}
			}
		}
		for (new i = 0; i < GetNextTeamCount(2, true) - terrorCount; i++)
		{
			gi_NextRoundTeam[IndexList[i]] = 3;
		}
	}
	else if(terrorCount > GetNextTeamCount(2, true))
	{
		new DamageList[MaxClients];
		new IndexList[MaxClients];
		new count = 0;
		for (new i = 1; i <= MaxClients; i++)
		{
			if(IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == 3)
			{
				DamageList[count] = GetClientFrags(i);
				IndexList[count] = i;
				count++;
			}
		}
		new temp;
		new temp2;
		for (new i = 0; i < count; i++)
		{
			for (new j = i+1; j < count; j++)
			{
				if(DamageList[i] > DamageList[j])
				{
					temp = DamageList[i];
					temp2 = IndexList[i];
					DamageList[i] = DamageList[j];
					IndexList[i] = IndexList[j];
					DamageList[j] = temp;
					IndexList[j] = temp2;
				}
			}
		}
		for (new i = 0; i < terrorCount - GetNextTeamCount(2, true); i++)
		{
			gi_NextRoundTeam[IndexList[i]] = 2;
		}
	}
}

ScrambleTeams(bool:includespec)
{
	PrintToChatAll("%sScrambling Teams", PREFIX);
	new terrorCount = RoundToFloor(GetClientCountFix(includespec) / 2.0);
	if(terrorCount > MAX_T)
		terrorCount = MAX_T;
	new randomPlayer = -1;
	for (new i = 0; i < MAXPLAYERS; i++)
	{
		gi_NextRoundTeam[i] = -1;
	}
	for (new i = 0; i < terrorCount; i++)
	{
		randomPlayer = GetRandomPlayer(includespec);
		if(randomPlayer != -1)
		{
			gi_NextRoundTeam[randomPlayer] = 2;
			if(GetClientTeam(randomPlayer) == 1)
			{
				DeletePlayerFromQueue(i);
			}
		}
	}
	new ctCount = GetClientCountFix(true) - terrorCount;
	if(ctCount > MAX_CT)
		ctCount = MAX_CT;
	for (int i = 0; i < ctCount; i++)
	{
		randomPlayer = GetRandomPlayer(includespec);
		if(randomPlayer != -1)
		{
			gi_NextRoundTeam[randomPlayer] = 3;
			if(GetClientTeam(randomPlayer) == 1)
			{
				DeletePlayerFromQueue(i);
			}
		}
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && !IsFakeClient(i) && gi_NextRoundTeam[i] == -1)
		{
			gi_NextRoundTeam[i] = 1;
			AddPlayerToQueue(i);
		}
	}
	gb_balancedTeams = true;
}

SetQueueClients()
{
	for (new i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && !IsFakeClient(i) && gi_NextRoundTeam[i] == -1 && GetClientTeam(i) != 1)
		{
			gi_NextRoundTeam[i] = GetClientTeam(i);
		}
	}
	new terror = GetNextTeamCount(2);
	new ct = GetNextTeamCount(3);
	if(terror == 0)
	{
		terror = GetTeamClientCountFix(2);
	}
	if(ct == 0)
	{
		ct = GetTeamClientCountFix(3);
	}
	new counter = gi_QueueCounter;
	new queue[counter];
	for (new i = 0; i < counter; i++)
	{
		queue[i] = gi_PlayerQueue[i];
	}
	for (new i = 0; i < counter; i++)
	{
		if(IsClientInGame(queue[i]) && !IsFakeClient(queue[i]))
		{
			if(ct > terror && terror < 4)
			{
				SwitchPlayerTeam(queue[i], 2);
				gi_NextRoundTeam[queue[i]] = 2;
				terror++;	
				DeletePlayerFromQueue(queue[i]);
				gb_newClientsJoined = true;
			}
			else if(ct < 5)
			{
				SwitchPlayerTeam(queue[i], 3);
				gi_NextRoundTeam[queue[i]] = 3;
				ct++;
				DeletePlayerFromQueue(queue[i]);
				gb_newClientsJoined = true;
			}
		}
	}
}

DeletePlayerFromQueue(client)
{
	new index = -1;
	for (new i = 0; i < gi_QueueCounter; i++)
	{
		if(client == gi_PlayerQueue[i])
		{
			index = i;
			break;
		}
	}
	if(index != -1)
	{
		for (new i = index+1; i < gi_QueueCounter; i++)
		{
			gi_PlayerQueue[i-1] = gi_PlayerQueue[i];
		}
		gi_QueueCounter--;
		if(gi_QueueCounter < 0)
		{
			gi_QueueCounter = 0;
		}
	}
}

public Action:Command_Start(client, args)
{
	gf_MapLoadTime -= 50;
	TriggerTimer(gh_MapLoadTimer, false);
	return Plugin_Handled;
}

public Action:Command_Scramble(client, args)
{
	gb_Scrambling = true;
	return Plugin_Handled;
}

public Action:Command_OnlyPistols(client, args)
{
	gb_OnlyPistols = !gb_OnlyPistols;
	PrintToChatAll("%sPistols Only is now \x02%s", PREFIX, gb_OnlyPistols ? "Enabled":"Disabled");
	return Plugin_Handled;
}

public Action:Command_VotePistols(int client, int args)
{	
	if(GetEngineTime() - gf_UsedVP[client] < 5)
	{
		PrintToChat(client, "%s\x02sm_vp\x04 is allowed once in 5 seconds", PREFIX);
		return Plugin_Handled;
	}

	gf_UsedVP[client] = GetEngineTime();
	
	if(CS_GetTeamScore(3) + CS_GetTeamScore(2) < gi_PistolRoundsCount)
	{
		PrintToChat(client, "%ssm_vp is allowed after \x02%d\x04 rounds", PREFIX, gi_PistolRoundsCount);
		return Plugin_Handled;
	}

	new String:name[64];
	GetClientName(client, name, sizeof(name));
	if(!gb_Voted[client])
	{
		gi_Votes++;
		PrintToChatAll("%s\x02%s\x04 wants to \x02%s%\x04 Only Pistols (%d votes, %d required)", PREFIX, name, gb_OnlyPistols ? "Disable":"Enable", gi_Votes, gi_VotesNeeded);
	}
	else
	{
		gi_Votes--;
		PrintToChatAll("%s\x02%s\x04 devoted (%d votes, %d required)", PREFIX, name, gi_Votes, gi_VotesNeeded);	
	}
	
	gb_Voted[client] = !gb_Voted[client];
	
	if (gi_Votes >= gi_VotesNeeded)
	{
		ToggleVP();
	}

	return Plugin_Handled;
}

ToggleVP()
{
	for (int i = 0; i < MAXPLAYERS; i++)
	{
		gb_Voted[i] = false;
	}
	gi_Votes = 0;
	gi_VotesNeeded = RoundToFloor(float(gi_Voters) * 0.5);

	gb_OnlyPistols = !gb_OnlyPistols;
	PrintToChatAll("%sPistols Only is now \x02%s", PREFIX, gb_OnlyPistols ? "Enabled":"Disabled");
}


public Action:Command_Edit(client, args)
{
	gb_EditMode = !gb_EditMode;
	PrintToChatAll("%sEdit mode is now %s", PREFIX, gb_EditMode ? "Enabled":"Disabled");
	if(gb_EditMode)
	{
		CreateTimer(0.1, DrawAdminPanel, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	}
	SetConfig(gb_EditMode);
	ServerCommand("mp_restartgame 1");
	ServerCommand("mp_playercashawards 0");
	ServerCommand("mp_teamcashawards 0");
	return Plugin_Handled;
}

public Action Command_Executes(int client, int args)
{
	new Handle:hmenu = CreateMenu(MenuHandler_EditExecute);
	SetMenuTitle(hmenu, "Select Execute");
	if(g_ExecutesCount > 0)
	{
		decl String:sDisplay[64];
		decl String:sInfo[64];
		for (new i = 0; i < g_ExecutesCount; i++)
		{
			FormatEx(sDisplay, sizeof(sDisplay), "%d# %s", (i+1), g_Executes[i][Name]);
			FormatEx(sInfo, sizeof(sInfo), "%d", g_Executes[i][Id]);
			AddMenuItem(hmenu, sInfo, sDisplay);
		}
		SetMenuExitButton(hmenu, true);
	}
	else
	{
		return Plugin_Handled;
	}
	DisplayMenu(hmenu, client, MENU_TIME_FOREVER);
	return Plugin_Handled;
}

public Action Command_Name(int client, int args)
{
	if(gi_EditedExecuteID != -1)
	{
		new String:sArg[128];
		GetCmdArgString(sArg, sizeof(sArg));
		strcopy(gs_ExecuteName, 128, sArg);
	}

	return Plugin_Handled;
}

public Action Command_Site(int client, int args)
{
	if(gi_EditedExecuteID != -1)
	{
		new String:sArg[8];
		GetCmdArg(1, sArg, sizeof(sArg));
		new site = -1;
		if(StrEqual("A", sArg))
		site = A;
		else if(StrEqual("B", sArg))
		site = B;
		else
		{
			ReplyToCommand(client, "[SM] sm_site <A, B>");
			return Plugin_Handled;
		}


		gi_EditedExecuteSite = site;
	}

	return Plugin_Handled;
}

public int MenuHandler_EditExecute(Handle menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_Select:
		{
			decl String:sInfo[32];		
			GetMenuItem(menu, param2, sInfo, sizeof(sInfo));
			gi_EditedExecuteID = StringToInt(sInfo);
			strcopy(gs_ExecuteName, sizeof(gs_ExecuteName), g_Executes[param2][Name]);
			gi_EditedExecuteSite = g_Executes[param2][Site];
			gb_Editing = true;
		}
	}
}

stock GetNextTeamCount(team, bool:next = true)
{
	if(!next)
	return GetTeamClientCountFix(team);
	new count = 0;
	for (new i = 1; i < MaxClients; i++)
	{
		if(gi_NextRoundTeam[i] == team)
		count++;
	}
	return count;
}

stock GetTeamClientCountFix(team)
{
	new count = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == team)
		{
			count++;
		}
	}
	return count;
}

stock GetTeamAliveClientCount(team)
{
	new count = 0;
	for (new i = 1; i < MaxClients; i++)
	{
		if(IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == team && IsPlayerAlive(i))
		count++;
	}
	return count;
}

stock GetRandomAwpPlayer(team)
{
	new iClients[MaxClients];
	new numClients;

	for (new i = 1; i < MaxClients; i++)
	{
		if(IsClientInGame(i) && !IsClientSourceTV(i) && !IsFakeClient(i) && gi_WantAwp[i] > 0 && GetClientTeam(i) == team)
		{
			iClients[numClients] = i;
			numClients++;
		}
	}

	if(numClients)
	{
		new awp = iClients[GetRandomInt(0, numClients-1)];
		if(gi_WantAwp[awp] == 2 && GetRandomInt(0, 1) == 1)
		{
			numClients = 0;
			for (new i = 1; i < MaxClients; i++)
			{
				if(IsClientInGame(i) && !IsClientSourceTV(i) && !IsFakeClient(i) && gi_WantAwp[i] == 1 && GetClientTeam(i) == team)
				{
					iClients[numClients] = i;
					numClients++;
				}
			}
			if(numClients)
			{
				return iClients[GetRandomInt(0, numClients-1)];
			}
			return -1;
		}
		return awp;
	}
	return -1;
}

stock GetRandomTSpawn(executeID)
{
	decl iSpawns[MaxClients];
	new numSpawns;

	for (new i = 0; i < g_SpawnsCount; i++)
	{
		if(!g_Spawns[i][Used] && g_Spawns[i][execID] == executeID)
		{
			iSpawns[numSpawns] = i;
			numSpawns++;
		}
	}

	if (numSpawns)
	{
		return iSpawns[GetRandomInt(0, numSpawns-1)];
	}
	return -1;
}

stock GetRandomCTSpawn()
{
	decl iSpawns[MaxClients];
	new numSpawns;

	for (new i = 0; i < g_SpawnsCount; i++)
	{
		if(!g_Spawns[i][Used] && g_Spawns[i][execID] == -1)
		{
			iSpawns[numSpawns] = i;
			numSpawns++;
		}
	}

	if (numSpawns)
	{
		return iSpawns[GetRandomInt(0, numSpawns-1)];
	}
	return -1;
}

stock GetRandomPlayer(bool:includespec = false)
{
	decl iClients[MaxClients];
	new numClients;

	for (new i = 1; i < MaxClients; i++)
	{
		if(IsClientInGame(i) && !IsClientSourceTV(i) && !IsFakeClient(i) && gi_NextRoundTeam[i] == -1 && (includespec || GetClientTeam(i) != 1))
		{
			iClients[numClients] = i;
			numClients++;
		}
	}

	if (numClients)
	{
		return iClients[GetRandomInt(0, numClients-1)];
	}
	return -1;
}

stock GetRandomPlayerFromTeam(team)
{
	decl iClients[MaxClients];
	new numClients = 0;

	for (new i = 1; i < MaxClients; i++)
	{
		if(IsClientInGame(i) && !IsClientSourceTV(i) && !IsFakeClient(i) && GetClientTeam(i) == team)
		{
			iClients[numClients] = i;
			numClients++;
		}
	}

	if (numClients)
	{
		return iClients[GetRandomInt(0, numClients-1)];
	}
	return -1;
}

stock GetRandomGrenadeSet(team)
{
	decl iSets[MaxClients];
	new numSets;
	new flag = FL_USED_CT;
	if(team == 2)
		flag = FL_USED_T;

	for (new i = 0; i < GRENADESSETCOUNT; i++)
	{
		if(!(gi_GrenadeSetsFlags[i] & flag))
		{
			iSets[numSets] = i;
			numSets++;
		}
	}

	if (numSets)
	{
    	return iSets[GetRandomInt(0, numSets-1)];
	}
	return -1;
}

public Action:Command_Say(client, const String:command[], argc)
{
	decl String:sText[192];
	GetCmdArgString(sText, sizeof(sText));
	StripQuotes(sText);
	if(StrEqual(sText, "guns") || StrEqual(sText, "weapons") || StrEqual(sText, "weps"))
	{
		Command_Guns(client, 0);
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public Action:Command_Guns(client, args)
{
	new Handle:menu = CreateMenu(MenuHandler_M4, MENU_ACTIONS_ALL);
	SetMenuTitle(menu, "Choose Ct Weapon:");
	AddMenuItem(menu, "0", "M4A4");
	AddMenuItem(menu, "1", "M4A1-S");
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
	return Plugin_Handled;
}

public MenuHandler_M4(Handle:menu, MenuAction:action, param1, param2)
{
	if(action == MenuAction_Select)
	{
		new String:sArg[6];
		GetMenuItem(menu, param2, sArg, sizeof(sArg));
		gb_WantSilencer[param1] = bool:StringToInt(sArg);
		new convInt = gb_WantSilencer[param1] ? 1 : 0;
		decl String:buffer[16];
		IntToString(convInt, buffer, sizeof(buffer));
		SetClientCookie(param1, gh_SilencedM4, buffer);
		
		new Handle:hmenu = CreateMenu(MenuHandler_Awp, MENU_ACTIONS_ALL);
		SetMenuTitle(hmenu, "Do you want to play with Awp:");
		AddMenuItem(hmenu, "1", "Always");
		AddMenuItem(hmenu, "2", "Sometimes");
		AddMenuItem(hmenu, "0", "Never");
		DisplayMenu(hmenu, param1, MENU_TIME_FOREVER);
	}
}

public MenuHandler_Awp(Handle:menu, MenuAction:action, param1, param2)
{
	if(action == MenuAction_Select)
	{
		new String:sArg[6];
		GetMenuItem(menu, param2, sArg, sizeof(sArg));
		gi_WantAwp[param1] = StringToInt(sArg);
		decl String:buffer[16];
		IntToString(gi_WantAwp[param1], buffer, sizeof(buffer));
		SetClientCookie(param1, gh_WantAwp, buffer);
	}
}

public Action:Command_AddCTSpawn(client, args)
{
	decl String:sQuery[512];
	new Float:loc[3], Float:ang[3];
	GetClientAbsOrigin(client, loc);
	GetClientEyeAngles(client, ang);
	ang[0] = 0.0;
	FormatEx(sQuery, sizeof(sQuery), "INSERT INTO spawns (map, execID, posx, posy, posz, angx, angy) VALUES ('%s', '-1', %f, %f, %f, %f, %f);", gs_CurrentMap, loc[0], loc[1], loc[2], ang[1], ang[0]);
	SQL_TQuery(gh_Sql, AddSpawnCallback, sQuery, client, DBPrio_Normal);
	return Plugin_Handled;
}

public Action Command_DeleteCTSpawn(int client, int args)
{
	DeleteSpawn(client, -1);
	return Plugin_Handled;
}

DeleteSpawn(client, executeID)
{
	new Float:fOrg[3];
	GetClientAbsOrigin(client, fOrg);
	new Float:fTmp[3];

	new closest = -1;
	new Float:fMinDist = 0.0;
	new Float:currentDist;

	for (int i = 0; i < g_SpawnsCount; i++)
	{
		if(g_Spawns[i][execID] != executeID)
			continue;

		Array_Copy(g_Spawns[i][Location], fTmp, 3);
		currentDist = GetVectorDistance(fTmp, fOrg);

		if(currentDist < fMinDist || closest == -1)
		{
			closest = i;
			fMinDist = currentDist;
		}
	}

	if(closest == -1)
		return;

	decl String:sQuery[512];
	FormatEx(sQuery, sizeof(sQuery), "DELETE FROM spawns WHERE execID = %d AND id = %d AND map = '%s'", executeID, g_Spawns[closest][Id], gs_CurrentMap);
	SQL_TQuery(gh_Sql, DeleteSpawnCallback, sQuery, client, DBPrio_Normal);
}

public DeleteSpawnCallback(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (hndl == INVALID_HANDLE)
	{
		LogError("SQL Error on DeleteSpawn: %s", error);
		return;
	}

	LoadSpawns();
}

public Action Command_AddExecute(int client, int args)
{
	//PrintToChat(client, "%sType execute name in chat, type cancel to cancel", PREFIX);
	gb_Editing = false;
	SQL_TQuery(gh_Sql, GetExecuteID, "SELECT `id` FROM `executes` ORDER BY id DESC LIMIT 1", client, DBPrio_Normal);
	return Plugin_Handled;
}

public GetExecuteID(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (hndl == INVALID_HANDLE)
	{
		LogError("SQL Error on GetExecuteID: %s", error);
		return;
	}

	if (SQL_FetchRow(hndl))
	{
		gi_EditedExecuteID = SQL_FetchInt(hndl, 0)+1;
	}
	else
	{
		gi_EditedExecuteID = 1;
	}

	gi_EditedExecuteSite = A;
	strcopy(gs_ExecuteName, 128, "");
}

public AddSpawnCallback(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (hndl == INVALID_HANDLE)
	{
		LogError("SQL Error on AddSpawnCallback: %s", error);
		return;
	}

	LoadSpawns();
}

stock GetClientCountFix(bool:includespec = true)
{
	new counter = 0;
	for (new i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && !IsClientSourceTV(i) && !IsFakeClient(i) && (includespec || GetClientTeam(i) != 1))
		{
			counter++;
		}
	}
	return counter;
}

//Sql
ConnectSQL()
{
	if (gh_Sql != INVALID_HANDLE)
	{
		CloseHandle(gh_Sql);
	}
	
	gh_Sql = INVALID_HANDLE;
	
	if (SQL_CheckConfig("executes"))
	{
		SQL_TConnect(ConnectSQLCallback, "executes");
	}
	else
	{
		SetFailState("PLUGIN STOPPED - Reason: no config entry found for 'executes' in databases.cfg - PLUGIN STOPPED");
	}
}

public ConnectSQLCallback(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (gi_ReconncetCounter >= 5)
	{
		LogError("PLUGIN STOPPED - Reason: reconnect counter reached max - PLUGIN STOPPED");
		return;
	}
	
	if (hndl == INVALID_HANDLE)
	{
		LogError("Connection to SQL database has failed, Reason: %s", error);
		
		gi_ReconncetCounter++;
		ConnectSQL();
		
		return;
	}
	
	decl String:sDriver[16];
	SQL_GetDriverIdent(owner, sDriver, sizeof(sDriver));
	
	gh_Sql = CloneHandle(hndl);		
	
	if (StrEqual(sDriver, "mysql", false))
	{
		SQL_TQuery(gh_Sql, CreateSQLTableCallback, "CREATE TABLE IF NOT EXISTS `executes` (`id` int(11) NOT NULL AUTO_INCREMENT, `map` varchar(32) NOT NULL, `name` varchar(64) NOT NULL, `site` int(11), PRIMARY KEY (`id`));");
		SQL_TQuery(gh_Sql, CreateSQLTableCallback, "CREATE TABLE IF NOT EXISTS `smokes` (`id` int(11) NOT NULL AUTO_INCREMENT, `execID` int(11) NOT NULL, `map` varchar(32) NOT NULL, `posx` float NOT NULL, `posy` float NOT NULL, `posz` float NOT NULL, `velx` float NOT NULL, `vely` float NOT NULL, `velz` float NOT NULL, PRIMARY KEY (`id`));");
		SQL_TQuery(gh_Sql, CreateSQLTableCallback, "CREATE TABLE IF NOT EXISTS `spawns` (`id` int(11) NOT NULL AUTO_INCREMENT, `execID` int(11) NOT NULL, `map` varchar(32) NOT NULL, `posx` float NOT NULL, `posy` float NOT NULL, `posz` float NOT NULL, `angx` float NOT NULL, `angy` float NOT NULL, PRIMARY KEY (`id`));");
		//SQL_TQuery(gh_Sql, CreateSQLTableCallback, "CREATE TABLE IF NOT EXISTS `players` (`auth` varchar(24) NOT NULL PRIMARY KEY, `kills` int(11) NOT NULL, `deaths` int(11) NOT NULL);");
	}
	else if (StrEqual(sDriver, "sqlite", false))
	{
		SQL_TQuery(gh_Sql, CreateSQLTableCallback, "CREATE TABLE IF NOT EXISTS `executes` (`id` INTEGER PRIMARY KEY, `map` varchar(32) NOT NULL, `name` varchar(64) NOT NULL, `site` INTEGER);");
		SQL_TQuery(gh_Sql, CreateSQLTableCallback, "CREATE TABLE IF NOT EXISTS `smokes` (`id` INTEGER PRIMARY KEY, `execID` INTEGER NOT NULL, `map` varchar(32) NOT NULL, `posx` float NOT NULL, `posy` float NOT NULL, `posz` float NOT NULL, `velx` float NOT NULL, `vely` float NOT NULL, `velz` float NOT NULL);");
		SQL_TQuery(gh_Sql, CreateSQLTableCallback, "CREATE TABLE IF NOT EXISTS `spawns` (`id` INTEGER PRIMARY KEY, `execID` INTEGER NOT NULL, `map` varchar(32) NOT NULL, `posx` float NOT NULL, `posy` float NOT NULL, `posz` float NOT NULL, `angx` float NOT NULL, `angy` float NOT NULL);");
	}
	
	gi_ReconncetCounter = 1;
}

public CreateSQLTableCallback(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (owner == INVALID_HANDLE)
	{		
		LogError("SQL:Reconnect");
		gi_ReconncetCounter++;
		ConnectSQL();
		
		return;
	}
	
	if (hndl == INVALID_HANDLE)
	{
		LogError("SQL CreateTable:%s", error);
		return;
	}
	
	LoadSpawns();
}

LoadSpawns(bool:mapstart = false)
{
	if (gh_Sql == INVALID_HANDLE)
	{
		ConnectSQL();
	}
	else
	{
		decl String:sQuery[384];
		FormatEx(sQuery, sizeof(sQuery), "SELECT id, execID, posx, posy, posz, angx, angy FROM spawns WHERE map = '%s'", gs_CurrentMap);
		SQL_TQuery(gh_Sql, LoadSpawnsCallBack, sQuery, mapstart, DBPrio_High);
	}
}

public LoadSpawnsCallBack(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (hndl == INVALID_HANDLE)
	{
		LogError("SQL Error on LoadSpawnsCallBack: %s", error);
		return;
	}
	
	g_SpawnsCount = 0;
	while (SQL_FetchRow(hndl) && g_SpawnsCount < MAXSPAWNS)
	{		
		g_Spawns[g_SpawnsCount][Id] = SQL_FetchInt(hndl, 0);
		g_Spawns[g_SpawnsCount][execID] = SQL_FetchInt(hndl, 1);
		g_Spawns[g_SpawnsCount][Location][0] = SQL_FetchFloat(hndl, 2);
		g_Spawns[g_SpawnsCount][Location][1] = SQL_FetchFloat(hndl, 3);
		g_Spawns[g_SpawnsCount][Location][2] = SQL_FetchFloat(hndl, 4);
		g_Spawns[g_SpawnsCount][Angles][0] = SQL_FetchFloat(hndl, 6);
		g_Spawns[g_SpawnsCount][Angles][1] = SQL_FetchFloat(hndl, 5);
		g_Spawns[g_SpawnsCount][Angles][2] = 0.0;

		g_SpawnsCount++;
	}

	if(data)
	{
		if(g_SpawnsCount == 0)
		{
			gb_EditMode = true;
			PrintToChatAll("%sEdit mode is now Enabled becuase there is no spawns", PREFIX);
			CreateTimer(0.1, DrawAdminPanel, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
		}
		else
		{
			gb_EditMode = false;
		}
	}

	LoadSmokes();
}

LoadSmokes()
{
	if (gh_Sql == INVALID_HANDLE)
	{
		ConnectSQL();
	}
	else
	{
		decl String:sQuery[384];
		FormatEx(sQuery, sizeof(sQuery), "SELECT id, execID, posx, posy, posz, velx, vely, velz FROM smokes WHERE map = '%s'", gs_CurrentMap);
		SQL_TQuery(gh_Sql, LoadSmokesCallBack, sQuery, _, DBPrio_High);
	}
}

public LoadSmokesCallBack(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (hndl == INVALID_HANDLE)
	{
		LogError("SQL Error on LoadSmokesCallBack: %s", error);
		return;
	}
	
	g_SmokesCount = 0;
	while (SQL_FetchRow(hndl) && g_SmokesCount < MAXSPAWNS)
	{		
		g_Smokes[g_SmokesCount][Id] = SQL_FetchInt(hndl, 0);
		g_Smokes[g_SmokesCount][execID] = SQL_FetchInt(hndl, 1);
		g_Smokes[g_SmokesCount][Location][0] = SQL_FetchFloat(hndl, 2);
		g_Smokes[g_SmokesCount][Location][1] = SQL_FetchFloat(hndl, 3);
		g_Smokes[g_SmokesCount][Location][2] = SQL_FetchFloat(hndl, 4);
		g_Smokes[g_SmokesCount][Velocity][0] = SQL_FetchFloat(hndl, 5);
		g_Smokes[g_SmokesCount][Velocity][1] = SQL_FetchFloat(hndl, 6);
		g_Smokes[g_SmokesCount][Velocity][2] = SQL_FetchFloat(hndl, 7);

		g_SmokesCount++;
	}

	LoadExecutes();
}


public Action:DrawAdminPanel(Handle:timer)
{
	if (!gb_EditMode)
	{
		return Plugin_Stop;
	}

	new g_DrawColor[4];
	new Float:Point1[3];
	new Float:Point2[3];
	for (new i = 0; i < g_SpawnsCount; i++)
	{
		//Set Color
		if(g_Spawns[i][execID] == -1) //CT
		{
			g_DrawColor[0] = 0;
			g_DrawColor[1] = 255;
			g_DrawColor[2] = 255;
		}
		else if (g_Spawns[i][execID] == gi_EditedExecuteID && gi_EditedExecuteID != -1) //Terror
		{
			g_DrawColor[0] = 255;
			g_DrawColor[1] = 0;
			g_DrawColor[2] = 0;
		}
		else
		{
			continue;
		}
		g_DrawColor[3] = 255;
		//Set Points
		Array_Copy(g_Spawns[i][Location], Point1, 3);
		Array_Copy(Point1, Point2, 3);
		Point2[2] += 100.0;
		//Draw Beam
		TE_SetupBeamPoints(Point1, Point2, g_precacheLaser, 0, 0, 0, 0.1, 3.0, 3.0, 10, 0.0, g_DrawColor, 0);TE_SendToAll(0.0);
	}

	g_DrawColor[0] = 255;
	g_DrawColor[1] = 255;
	g_DrawColor[2] = 0;
	g_DrawColor[3] = 255;

	if(gi_EditedExecuteID == -1)
	return Plugin_Continue;

	new Float:scale = 0.15;
	for (new i = 0; i < g_SmokesCount; i++)
	{
		if(g_Smokes[i][execID] != gi_EditedExecuteID)
		continue;

		Array_Copy(g_Smokes[i][Location], Point1, 3);
		Point2[0] = Point1[0] + g_Smokes[i][Velocity][0] * scale;
		Point2[1] = Point1[1] + g_Smokes[i][Velocity][1] * scale;
		Point2[2] = Point1[2] + g_Smokes[i][Velocity][2] * scale;
		TE_SetupBeamPoints(Point1, Point2, g_precacheLaser, 0, 0, 0, 0.1, 3.0, 3.0, 10, 0.0, g_DrawColor, 0);TE_SendToAll(0.0);
	}


	new Handle:panel = CreatePanel();
	new String:sBuffer[1024];
	FormatEx(sBuffer, sizeof(sBuffer), "Execute Id: %d\nExecute Name: %s (!name <>)\nSite: %s (!site <>)\n \n", gi_EditedExecuteID, gs_ExecuteName, gi_EditedExecuteSite == A ? "A":"B");
	DrawPanelText(panel, sBuffer);

	DrawPanelItem(panel, "Add T Spawn");
	DrawPanelItem(panel, "Add Smoke\n \n");
	DrawPanelItem(panel, "Throw All Smokes\n \n");
	DrawPanelItem(panel, "Delete T Spawn\n \n");
	if(gb_Editing)
	{
		DrawPanelItem(panel, "Finish Setup\n \n");
		DrawPanelItem(panel, "Delete Execute");
	}
	else
	{
		DrawPanelItem(panel, "Finish Setup\n \n");
		DrawPanelItem(panel, "Cancel");
	}


	for (int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && CheckCommandAccess(i, "sm_admin", ADMFLAG_GENERIC))
		{
			if(!gb_AddingSmoke[i])
			{
				SendPanelToClient(panel, i, PanelHandler, 1);
			}
			else
			{
				new Handle:clientPanel = CreatePanel();
				if(gf_AdminSmokeVel[i][0] == 0.0 && gf_AdminSmokeVel[i][1] == 0.0 && gf_AdminSmokeVel[i][2] == 0.0)
				{
					DrawPanelText(clientPanel, "Throw Smoke to Add it");
					DrawPanelItem(clientPanel, "Cancel");
					SendPanelToClient(clientPanel, i, SmokePanelHandler, 1);

					CloseHandle(clientPanel);
				}
				else
				{
					DrawPanelText(clientPanel, "Smoke Menu:\n \n");
					DrawPanelItem(clientPanel, "Throw Again");
					DrawPanelItem(clientPanel, "Confirm Smoke");
					DrawPanelItem(clientPanel, "Cancel");
					SendPanelToClient(clientPanel, i, SmokeConfirmPanelHandler, 1);

					CloseHandle(clientPanel);
				}
			}
		}
	}
	CloseHandle(panel);

	return Plugin_Continue;
}

public PanelHandler(Handle:menu, MenuAction:action, param1, param2)
{
	if(action == MenuAction_Select)
	{
		new client = param1;
		switch(param2)
		{
			case 1: //Add T Spawn
			{
				decl String:sQuery[512];
				new Float:loc[3], Float:ang[3];
				GetClientAbsOrigin(client, loc);
				GetClientEyeAngles(client, ang);
				ang[0] = 0.0;
				FormatEx(sQuery, sizeof(sQuery), "INSERT INTO spawns (map, execID, posx, posy, posz, angx, angy) VALUES ('%s', '%d', %f, %f, %f, %f, %f);", gs_CurrentMap, gi_EditedExecuteID, loc[0], loc[1], loc[2], ang[1], ang[0]);
				SQL_TQuery(gh_Sql, AddSpawnCallback, sQuery, client, DBPrio_Normal);
			}
			case 2: //Add Smoke
			{
				gb_AddingSmoke[client] = true;
				Array_Fill(gf_AdminSmokePos[client], 3, 0.0);
				Array_Fill(gf_AdminSmokeVel[client], 3, 0.0);
				GivePlayerItem(client, "weapon_smokegrenade");
				FakeClientCommand(client, "use weapon_smokegrenade");
			}
			case 3: //Throw All Smokes
			{
				for (new i = 0; i < g_SmokesCount; i++)
				{
					if(g_Smokes[i][execID] != gi_EditedExecuteID)
					continue;

					gi_CurrentSmoke = i;
					new Float:org[3], Float:vel[3];
					Array_Copy(g_Smokes[i][Location], org, 3);
					Array_Copy(g_Smokes[i][Velocity], vel, 3);
					ThrowSmoke(org, vel);
					break;
				}
			}
			case 4:
			{
				DeleteSpawn(client, gi_EditedExecuteID);
			}
			case 5: //Finish Setup
			{
				if(gb_Editing)
				{
					gi_EditedExecuteID = -1;
				}
				else
				{
					decl String:sQuery[512];
					FormatEx(sQuery, sizeof(sQuery), "INSERT INTO executes (map, name, site) VALUES ('%s', '%s', %d)", gs_CurrentMap, gs_ExecuteName, gi_EditedExecuteSite);
					SQL_TQuery(gh_Sql, FinishSetup, sQuery, client, DBPrio_Normal);
				}
			}
			case 6: //Cancel/Delete
			{
				decl String:sQuery[512];
				FormatEx(sQuery, sizeof(sQuery), "DELETE FROM spawns WHERE execID = %d AND map = '%s'", gi_EditedExecuteID, gs_CurrentMap);
				SQL_TQuery(gh_Sql, CancelSetup1, sQuery, client, DBPrio_Normal);
			}
		}
	}
}

public SmokePanelHandler(Handle:menu, MenuAction:action, param1, param2)
{
	if(action == MenuAction_Select)
	{
		new client = param1;
		switch(param2)
		{
			case 1:
			{
				gb_AddingSmoke[client] = false;
			}
		}
	}
}

public SmokeConfirmPanelHandler(Handle:menu, MenuAction:action, param1, param2)
{
	if(action == MenuAction_Select)
	{
		new client = param1;
		switch(param2)
		{
			case 1:
			{
				ThrowSmoke(gf_AdminSmokePos[client], gf_AdminSmokeVel[client]);
				gi_CurrentSmoke = -1;
			}
			case 2:
			{
				decl String:sQuery[512];
				FormatEx(sQuery, sizeof(sQuery), "INSERT INTO smokes (execID, map, posx, posy, posz, velx, vely, velz) VALUES ('%d', '%s', %f, %f, %f, %f, %f, %f);", gi_EditedExecuteID, gs_CurrentMap, gf_AdminSmokePos[client][0], gf_AdminSmokePos[client][1], gf_AdminSmokePos[client][2], gf_AdminSmokeVel[client][0], gf_AdminSmokeVel[client][1], gf_AdminSmokeVel[client][2]);
				SQL_TQuery(gh_Sql, AddSmokeCallback, sQuery, client, DBPrio_Normal);
				gb_AddingSmoke[client] = false;
			}
			case 3:
			{
				gb_AddingSmoke[client] = false;
			}
		}
	}
}

public AddSmokeCallback(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (hndl == INVALID_HANDLE)
	{
		LogError("SQL Error on AddSpawnCallback: %s", error);
		return;
	}

	//LoadSpawns();
	LoadSmokes();
}

public void ThrowSmoke(const Float:smokeOrigin[3], const Float:smokeVel[3])
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && IsFakeClient(i) && !IsClientSourceTV(i))
		{
			gi_Bot = i;
			break;
		}
	}
	SetClientName(gi_Bot, "Smoke Thrower (Ignore)");
	gi_Stage = 1;

	Array_Copy(smokeOrigin, gf_BotSmokePos, 3);
	Array_Copy(smokeVel, gf_BotSmokeVel, 3);
}

public Action OnPlayerRunCmd(client, &buttons, &impulse, Float:vel[3], Float:angles[3], &weapon, &subtype, &cmdnum, &tickcount, &seed, mouse[2])
{
	if(IsFakeClient(client) && gi_Bot == client && gi_Stage > 0)
	{
		switch(gi_Stage)
		{
			case 1:
			{
				Client_RemoveAllWeapons(client);
				gi_Stage++;
			}
			case 2:
			{
				GivePlayerItem(client, "weapon_smokegrenade");
				gi_Stage++;
			}
			case 3:
			{
				SetEntData(client, g_iNextAttackOffset, GetGameTime());
				gi_Stage++;
			}
			case 4:
			{
				SetEntData(client, g_iNextAttackOffset, GetGameTime());
				gi_Stage++;
			}
			case 5:
			{
				new Float:fOrg[3];
				Entity_GetAbsOrigin(client, fOrg);

				new Float:fVel[3];
				fVel[0] = 0.0;
				fVel[1] = 0.0;
				fVel[2] = 0.0;

				new Float:fAngles[3];
				fAngles[0] = 0.0;
				fAngles[1] = 0.0;
				fAngles[2] = 0.0;

				TeleportEntity(client, fOrg, fAngles, fVel);

				buttons = IN_ATTACK;
				gi_Stage++;
			}
			case 6:
			{
				new Float:fOrg[3];
				Entity_GetAbsOrigin(client, fOrg);

				new Float:fVel[3];
				fVel[0] = 0.0;
				fVel[1] = 0.0;
				fVel[2] = 0.0;

				new Float:fAngles[3];
				fAngles[0] = 0.0;
				fAngles[1] = 0.0;
				fAngles[2] = 0.0;

				TeleportEntity(client, fOrg, fAngles, fVel);

				buttons = 0;
				gi_Stage++;
			}
			case 7:
			{
				gi_Stage = -1;
			}
		}
	}
}

public OnEntityCreated(entity, const String:classname[])
{
	if(StrEqual(classname, "smokegrenade_projectile"))
	{
		CreateTimer(0.000, Timer_OnSmokeThrow, entity);
	}
}

public Action:Timer_OnSmokeThrow(Handle:timer, any:entity)
{
	new owner = Entity_GetOwner(entity);
	if(owner > 0 && IsClientInGame(owner))
	{
		if(IsFakeClient(owner) && owner == gi_Bot)
		{
			TeleportEntity(entity, gf_BotSmokePos, NULL_VECTOR, gf_BotSmokeVel);
			NextSmoke();
		}
		else if(gb_AddingSmoke[owner])
		{
			Entity_GetAbsOrigin(entity, gf_AdminSmokePos[owner]);
			Entity_GetLocalVelocity(entity, gf_AdminSmokeVel[owner]);
		}
	}
}

NextSmoke()
{
	if(gi_CurrentSmoke != -1)
	{
		new exec = gi_CurrentExecute;
		if(gi_EditedExecuteID != -1)
		exec = gi_EditedExecuteID;

		for (new i = gi_CurrentSmoke+1; i < g_SmokesCount; i++)
		{
			if(g_Smokes[i][execID] != exec)
			continue;

			gi_CurrentSmoke = i;
			new Float:org[3], Float:vel[3];
			Array_Copy(g_Smokes[i][Location], org, 3);
			Array_Copy(g_Smokes[i][Velocity], vel, 3);
			ThrowSmoke(org, vel);
			return;
		}

		if(gi_EditedExecuteID == -1) //No More Smokes to Throw
		{
			CreateTimer(2.0, Timer_KillBot, _, TIMER_FLAG_NO_MAPCHANGE); //Killing the bot late to resolve spair smoke issue
		}
	}
}

public Action Timer_KillBot(Handle timer, any data)
{
	ForcePlayerSuicide(gi_Bot);
}

public CancelSetup1(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (hndl == INVALID_HANDLE)
	{
		LogError("SQL Error on CancelSetup1: %s", error);
		return;
	}

	decl String:sQuery[512];
	FormatEx(sQuery, sizeof(sQuery), "DELETE FROM smokes WHERE execID = %d AND map = '%s'", gi_EditedExecuteID, gs_CurrentMap);
	SQL_TQuery(gh_Sql, CancelSetup2, sQuery, data, DBPrio_Normal);
}

public CancelSetup2(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (hndl == INVALID_HANDLE)
	{
		LogError("SQL Error on CancelSetup2: %s", error);
		return;
	}

	if(gb_Editing)
	{
		decl String:sQuery[512];
		FormatEx(sQuery, sizeof(sQuery), "DELETE FROM executes WHERE id = %d  AND map = '%s'", gi_EditedExecuteID, gs_CurrentMap);
		SQL_TQuery(gh_Sql, CancelSetup3, sQuery, data, DBPrio_Normal);
	}
	else
	{
		gi_EditedExecuteID = -1;
		LoadSpawns();
	}
}

public CancelSetup3(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (hndl == INVALID_HANDLE)
	{
		LogError("SQL Error on CancelSetup1: %s", error);
		return;
	}

	gb_Editing = false;
	gi_EditedExecuteID = -1;
	LoadSpawns();
}

public FinishSetup(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (hndl == INVALID_HANDLE)
	{
		LogError("SQL Error on FinishSetup: %s", error);
		return;
	}

	gi_EditedExecuteID = -1;
	LoadExecutes();
}

LoadExecutes()
{
	if (gh_Sql == INVALID_HANDLE)
	{
		ConnectSQL();
	}
	else
	{
		decl String:sQuery[384];
		FormatEx(sQuery, sizeof(sQuery), "SELECT id, name, site FROM executes WHERE map = '%s'", gs_CurrentMap);
		SQL_TQuery(gh_Sql, LoadExecutesCallBack, sQuery, _, DBPrio_High);
	}
}

public LoadExecutesCallBack(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (hndl == INVALID_HANDLE)
	{
		LogError("SQL Error on LoadExecutesCallBack: %s", error);
		return;
	}

	g_ExecutesCount = 0;
	while (SQL_FetchRow(hndl) && g_ExecutesCount < MAXSPAWNS)
	{		
		g_Executes[g_ExecutesCount][Id] = SQL_FetchInt(hndl, 0);
		SQL_FetchString(hndl, 1, g_Executes[g_ExecutesCount][Name], 64);
		g_Executes[g_ExecutesCount][Site] = SQL_FetchInt(hndl, 2);

		g_ExecutesCount++;
	}
}

public Action:Timer_MapLoadDelay(Handle:timer)
{
	if(GetClientCountFix() >= 2)
	{
		gb_WaitForPlayers = false;
		gb_balancedTeams = false;
		ScrambleTeams(true);
		SetConfig(false);
		ServerCommand("mp_restartgame 1");
		ServerCommand("mp_warmup_end");
	}
	else
	{
		PrintToChatAll("%sWaiting for more players to join", PREFIX);
	}
	gb_WarmUp = false;
}

public Action:Timer_PrintHintWarmup(Handle:timer)
{
	if(GetEngineTime() - gf_MapLoadTime >= 30)
	return Plugin_Stop;
	PrintHintTextToAll("\n<font size='22'>Executes will start in:</font><font size='22' color='#E22C56'>%.00f seconds</font>", 30 - (GetEngineTime() - gf_MapLoadTime));
	return Plugin_Continue;
}

public Action:Timer_PrintHintSite(Handle:timer, any:site)
{
	if(GetEngineTime() - gf_StartRoundTime >= 3)
	return Plugin_Stop;
	//PrintHintTextToAll("       <font size='22'> <font color = '#01A9DB'>%d CT</font> vs <font color = '#FE2E2E'> %d T</font>\n Retake on Site:<font color='#E22C56'>%s</font></font>", GetTeamClientCountFix(3), GetTeamClientCountFix(2), site == SITEA ? "A":"B");
	return Plugin_Continue;
}

SetConfig(bool:warmup)
{
	ServerCommand("exec executes.cfg");
	if(!warmup)
	{
		ServerCommand("exec executes_live.cfg");
		ServerCommand("mp_defuser_allocation 2");
	}
	else
	{
		ServerCommand("exec executes_warmup.cfg");
	}
}

stock void SwitchPlayerTeam(int client, int team, bool change = true) 
{
	if (GetClientTeam(client) == team)
	return;

	gb_PluginSwitchingTeam[client] = true;
	if (!change) 
	{
		CS_SwitchTeam(client, team);
		CS_UpdateClientModel(client);
	} 
	else 
	{
		ChangeClientTeam(client, team);
	}
	gb_PluginSwitchingTeam[client] = false;
}
