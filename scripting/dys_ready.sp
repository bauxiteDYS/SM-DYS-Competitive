#include <sourcemod>
#include <sdktools>

Handle g_forceTimer;
Handle g_listTimer;
static char g_soundLive[] = "buttons/button17.wav";
bool g_isReady[33+1];
bool g_isLive;
bool g_forceLive;
bool g_listCooldown;
bool g_godEnabled;
int g_timerBeeps;
int g_forceConfirm;

public Plugin myinfo = {
	name = "Dys Comp Ready and Godmode",
	description = "Players can !ready up to start a comp game, godmode is enabled during warmup",
	author = "bauxite",
	version = "0.1.9",
	url = "https://github.com/bauxiteDYS/SM-DYS-Ready",
};

public OnPluginStart()
{
	RegAdminCmd("sm_god", Command_God, ADMFLAG_GENERIC);	
	RegAdminCmd("sm_forcelive", Command_ForceLive, ADMFLAG_GENERIC);
	HookEvent("round_end", OnRoundEndPost, EventHookMode_Post);
	HookEvent("player_team", OnPlayerTeamPost, EventHookMode_Post);
	HookEvent("player_spawn", OnPlayerSpawnPost, EventHookMode_Post);
	HookEvent("player_class", OnPlayerSpawnPost, EventHookMode_Post);
	AddCommandListener(OnLayoutDone, "layoutdone")
	RegConsoleCmd("sm_ready", Cmd_Ready);
	RegConsoleCmd("sm_readylist", Cmd_ReadyList);
	RegConsoleCmd("sm_live", Cmd_Live);
}

void ResetVariables()
{
	g_listCooldown = false;
	g_isLive = false;
	g_forceLive = false;
	g_forceConfirm = 0;
	g_godEnabled = true;
	
	for(int i = 1; i <= MaxClients; i++)
	{
		g_isReady[i] = false;
	}
}

void PlayLiveBeep()
{
	float volume = 1.0;	// Volume between 0.0 - 1.0 (original volume is 1.0)
	int pitch = 160;	// Pitch between 0 - 255 (original pitch is 100)
	EmitSoundToAll(g_soundLive, _, _, _, _, volume, pitch);
}

public Action Command_ForceLive(int client, int args)
{
	++g_forceConfirm;
	
	if(g_forceConfirm == 2)
	{
		g_forceConfirm = 0;
		
		if(g_isLive)
		{
			EndLive();
			return Plugin_Handled;
		}
	
		g_forceLive = true;
		CheckStartMatch();
		CloseHandle(g_forceTimer);
		return Plugin_Handled;
	}
	
	PrintToChatAll("Use command again within 10s to force %s round", g_isLive ? "end" : "start");
	
	if(!IsValidHandle(g_forceTimer))
	{
		g_forceTimer = CreateTimer(10.0, ResetForce, _, TIMER_FLAG_NO_MAPCHANGE);
	}
	
	return Plugin_Handled;
}

public Action ResetForce(Handle timer)
{
	g_forceConfirm = 0;
	return Plugin_Stop;
}

public void OnPlayerTeamPost(Handle event, const char[] name, bool dontBroadcast)
{
	if(!g_isLive)
	{
		int client = GetClientOfUserId(GetEventInt(event, "userid"));
		
		if(g_isReady[client])
		{
			g_isReady[client] = false;
			PrintToChatAll("%N moved team, they are NOT ready", client);
		}
	}
}

public void OnPlayerSpawnPost(Handle event, const char[] name, bool dontBroadcast)
{
	if(g_godEnabled)
	{
		int client = GetClientOfUserId(GetEventInt(event, "userid"));
		RequestFrame(SetGodMode, client);
	}
}

public Action OnLayoutDone(int client, const char[] command, int argc)
{
	if(g_godEnabled)
	{
		RequestFrame(SetGodMode, client);
	}
	
	return Plugin_Continue;
}

public void OnMapStart()
{
	ResetVariables();
	PrecacheSound(g_soundLive);
}

public void OnRoundEndPost(Event event, const char[] name, bool dontBroadcast)
{
	EndLive();
}

void EndLive()
{
	ResetVariables();
	PrintToChatAll("Round ended");
}

public Action Cmd_Live(int client, int args)
{
	PrintToChat(client, "Round is %s", g_isLive ? "Live" : "NOT Live");
	return Plugin_Handled;
}

public Action Cmd_ReadyList(int client, int args)
{
	if(g_isLive)
	{
		PrintToChat(client, "Round is Live");
		return Plugin_Handled;
	}
	
	if(g_listCooldown)
	{
		PrintToChat(client, "List cooldown");
		return Plugin_Handled;
	}
	
	char readyMsg[128];
	StrCat(readyMsg, sizeof(readyMsg), "Not ready: ");
	char name[32];
	char list[] = ", ";
	int msgLength;
	int nameLength;
	
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && GetClientTeam(i) > 1 && !g_isReady[i])
		{
			Format(name, sizeof(name), "%N", i);
			nameLength = strlen(name);
			msgLength = strlen(readyMsg);
			
			if(nameLength + msgLength >= 125)
			{
				readyMsg[msgLength - 2] = '\0';
				PrintToChatAll("%s", readyMsg);
				PrintToConsoleAll("%s", readyMsg);
				Format(readyMsg, sizeof(readyMsg), "%s", "Not ready: ");
			}	
			
			StrCat(readyMsg, sizeof(readyMsg), name);
			StrCat(readyMsg, sizeof(readyMsg), list);
		}
	}
	
	readyMsg[strlen(readyMsg) - 2] = '\0';
	PrintToChatAll("%s", readyMsg);
	PrintToConsoleAll("%s", readyMsg);
	
	g_listCooldown = true;
	
	if(!IsValidHandle(g_listTimer))
	{
		g_listTimer = CreateTimer(5.0, ResetListCooldown, _, TIMER_FLAG_NO_MAPCHANGE);
	}
	
	return Plugin_Handled;
}

public Action ResetListCooldown(Handle timer)
{
	g_listCooldown = false;
	return Plugin_Stop;
}

public Action Cmd_Ready(int client, int args)
{
	if(client == 0)
	{
		return Plugin_Handled;
	}
	
	if(g_isLive)
	{
		PrintToChat(client, "Round is already Live!");
		return Plugin_Handled;
	}
	
	if(GetClientTeam(client) == 1)
	{
		return Plugin_Handled;
	}
	
	g_isReady[client] = !g_isReady[client];
	
	PrintToChatAll("%N is %s", client, g_isReady[client] ? "ready" : "NOT ready");
	CheckStartMatch();
	return Plugin_Handled;
}

void CheckStartMatch()
{
	int unReady;
	
	if(!g_forceLive)
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsClientInGame(i) && GetClientTeam(i) > 1 && !g_isReady[i])
			{
				++unReady;
			}
		}
	}
	
	if(unReady == 0)
	{
		g_isLive = true;
		g_forceLive = false;
		g_godEnabled = false;
		
		for(int i = 1; i <= MaxClients; i++)
		{
			g_isReady[i] = false;
		}
		
		CreateTimer(1.0, GoLive, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action GoLive(Handle timer)
{
	if(g_timerBeeps == 5)
	{
		g_timerBeeps = 0;
		ServerCommand("map_restart");
		PrintToChatAll("Round is live!");
		return Plugin_Stop;
	}
	
	PlayLiveBeep();
	++g_timerBeeps;
	PrintToChatAll("Round is going live");
	return Plugin_Continue;
}

public Action Command_God(int client, int args)
{
	if(g_isLive)
	{
		PrintToChatAll("Can't toggle Godmode when round is live");
		return Plugin_Handled;
	}
	
	g_godEnabled = !g_godEnabled;
	PrintToChatAll("Godmode is %s", g_godEnabled ? "enabled" : "disabled");
	
	for(int i = 1; i <= MaxClients; i++)
	{	
		if(IsClientInGame(i)) 
		{ 
			SetGodMode(i); 
		}
	}

	return Plugin_Handled;
}

void SetGodMode(int client)
{
	if (g_godEnabled)
	{
		SetEntityHealth(client, 99999);
	}
}
