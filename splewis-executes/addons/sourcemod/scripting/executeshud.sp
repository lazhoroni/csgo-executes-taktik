#include <sourcemod>
#include <sdktools>
#include <executes>

#pragma newdecls required


#define PLUGIN_AUTHOR "Czar and Franc1sco franug"
#define PLUGIN_VERSION "1.3"

Handle cvar_red = INVALID_HANDLE;
Handle cvar_green = INVALID_HANDLE;
Handle cvar_blue = INVALID_HANDLE;
Handle cvar_fadein = INVALID_HANDLE;
Handle cvar_fadeout = INVALID_HANDLE;
Handle cvar_xcord = INVALID_HANDLE;
Handle cvar_ycord = INVALID_HANDLE;
Handle cvar_holdtime = INVALID_HANDLE;

public Plugin myinfo = 
{
	name = "Executes hud",
	author = PLUGIN_AUTHOR,
	description = "Bombsite Hud",
	version = PLUGIN_VERSION,
	url = ""
};

public void OnPluginStart()
{
	cvar_red = CreateConVar("sm_executes_redhud", "255");
	cvar_green = CreateConVar("sm_executes_greenhud", "255");
	cvar_blue = CreateConVar("sm_executes_bluehud", "255");
	cvar_fadein = CreateConVar("sm_executes_fadein", "0.5");
	cvar_fadeout = CreateConVar("sm_executes_fadeout", "0.5");
	cvar_holdtime = CreateConVar("sm_executes_holdtime", "5.0");
	cvar_xcord = CreateConVar("sm_executes_xcord", "0.42");
	cvar_ycord = CreateConVar("sm_executes_ycord", "0.3");
	
	AutoExecConfig(true, "executeshud");
	HookEvent("round_start", Event_OnRoundStart);
	
}
public void Event_OnRoundStart(Handle event, const char[] name, bool dontBroadcast)
{
	CreateTimer(1.0, Timer_Advertise);
}

public Action Timer_Advertise(Handle timer)
{
	displayHud();
}

public void displayHud()
{
	char sitechar[3];
	
	if(Executes_GetCurrrentBombsite() == BombsiteA)sitechar = "A";
	else sitechar = "B";
	
	int red = GetConVarInt(cvar_red);
	int green = GetConVarInt(cvar_green);
	int blue = GetConVarInt(cvar_blue);
	float fadein = GetConVarFloat(cvar_fadein);
	float fadeout = GetConVarFloat(cvar_fadeout);
	float holdtime = GetConVarFloat(cvar_holdtime);
	float xcord = GetConVarFloat(cvar_xcord);
	float ycord = GetConVarFloat(cvar_ycord);
	if (GameRules_GetProp("m_bWarmupPeriod") == 0) 
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsClientInGame(i) && !IsFakeClient(i))
			{
					SetHudTextParams(xcord, ycord, holdtime, red, green, blue, 255, 0, 0.25, fadein, fadeout);
					ShowHudText(i, 5, "Executes Bombsite: %s", sitechar);
			}
		}
	}
}
