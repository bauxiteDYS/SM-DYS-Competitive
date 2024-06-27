#include <sourcemod>
#include <sdktools>

Handle g_forceTimer;
Handle g_listTimer;
Handle g_liveTimer;
static char g_soundLive[] = "buttons/button17.wav";
bool g_isReady[65+1];
bool g_isLive;
bool g_goingLive;
bool g_forceLive;
bool g_listCooldown;
bool g_godEnabled;
bool g_start;
bool g_corpStart;
bool g_punkStart;
bool g_waitingForStart;
int g_timerBeeps;
int g_forceConfirm;

bool g_isTVRecording;
int g_botLive = -1;
int g_botNot = -1;

public Plugin myinfo = {
	name = "Dys Competitive",
	description = "Players can !ready up to start a comp round",
	author = "bauxite",
	version = "0.3.5",
	url = "",
};

public void OnPluginStart()
{
	RegAdminCmd("sm_god", Command_God, ADMFLAG_GENERIC);	
	RegAdminCmd("sm_forcelive", Command_ForceLive, ADMFLAG_GENERIC);
	HookEvent("round_end", OnRoundEndPost, EventHookMode_Post);
	HookEvent("player_team", OnPlayerTeamPost, EventHookMode_Post);
	HookEvent("player_spawn", OnPlayerSpawnPost, EventHookMode_Post);
	HookEvent("player_class", OnPlayerSpawnPost, EventHookMode_Post);
	HookEvent("player_connect_client", OnPlayerConnectPre, EventHookMode_Pre);
	HookEvent("player_disconnect", OnPlayerDisconnectPre, EventHookMode_Pre);
	AddCommandListener(OnLayoutDone, "layoutdone")
	RegConsoleCmd("sm_ready", Cmd_Ready);
	RegConsoleCmd("sm_unready", Cmd_UnReady);
	RegConsoleCmd("sm_readylist", Cmd_ReadyList);
	RegConsoleCmd("sm_start", Cmd_Start);
	
	if(!DirExists("demos", false))
	{
		CreateDirectory("demos",775);
	}
}

void ResetVariables()
{
	g_listCooldown = false;
	g_godEnabled = true;
	g_isLive = false;
	g_goingLive = false;
	g_forceLive = false;
	g_forceConfirm = 0;
	g_timerBeeps = 0;
	g_start = false;
	g_punkStart = false;
	g_corpStart = false;
	g_waitingForStart = false;
	
	for(int i = 1; i <= MaxClients; i++)
	{
		g_isReady[i] = false;
	}
}

void ToggleTV()
{
	if(g_isLive && !g_isTVRecording)
	{
		char mapName[32];
		GetCurrentMap(mapName, sizeof(mapName));
		
		char timestamp[16];
		FormatTime(timestamp, sizeof(timestamp), "%Y%m%d-%H%M");
		
		char demoName[PLATFORM_MAX_PATH];
		Format(demoName, sizeof(demoName), "%s_%s", mapName, timestamp);
		
		ServerCommand("tv_stoprecord");
		ServerCommand("tv_record \"demos\\%s\"", demoName);
		
		g_isTVRecording = true;
	}
	else if(!g_isLive)
	{
		ServerCommand("tv_stoprecord");
		g_isTVRecording = false;
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
	if(g_goingLive)
	{
		return Plugin_Handled;
	}
	
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

public Action OnPlayerConnectPre(Handle event, const char[] name, bool dontBroadcast)
{
	int bot = GetEventInt(event, "bot");
	
	if(bot == 1)
	{
		SetEventBroadcast(event, true);
	}
	
	return Plugin_Continue;
}

public Action OnPlayerDisconnectPre(Handle event, const char[] name, bool dontBroadcast)
{
	int bot = GetEventInt(event, "bot");
	
	if(bot == 1)
	{
		SetEventBroadcast(event, true);
	}
	
	return Plugin_Continue;
}

public void OnClientDisconnect_Post(int client)
{
	if(g_isReady[client] && g_goingLive)
	{
		g_isReady[client] = false;
		
		CheckStartMatch();
	}
}

public void OnPlayerTeamPost(Handle event, const char[] name, bool dontBroadcast)
{
	if(!g_isLive)
	{
		int client = GetClientOfUserId(GetEventInt(event, "userid"));
		
		if(client <= 0 || client >= 65)
		{
			return;
		}
		
		if(IsFakeClient(client))
		{
			return;
		}
		
		int oldTeam = GetEventInt(event, "oldteam");
		//int Team = GetEventInt(event, "team");
		
		if(g_isReady[client])
		{
			g_isReady[client] = false;
			PrintToChatAll("%N moved team, they are NOT ready", client);
		}
		
		if(g_goingLive)
		{
			CheckStartMatch();
		}
		
		if(g_waitingForStart)
		{
			if(oldTeam == 2)
			{
				g_punkStart = false;
			}
			else if(oldTeam == 3)
			{
				g_corpStart = false;
			}
		}
	}
}

public void OnPlayerSpawnPost(Handle event, const char[] name, bool dontBroadcast)
{
	if(g_godEnabled && !g_isLive)
	{
		int client = GetClientOfUserId(GetEventInt(event, "userid"));
		RequestFrame(SetGodMode, client);
	}
}

public Action OnLayoutDone(int client, const char[] command, int argc)
{
	if(g_godEnabled && !g_isLive)
	{
		RequestFrame(SetGodMode, client);
	}
	
	return Plugin_Continue;
}

public void OnMapStart()
{
	ResetVariables();
	RequestFrame(StatBots);
	PrecacheSound(g_soundLive);
}

public void OnMapEnd()
{
	g_isTVRecording = false;
}

void StatBots()
{
	int realClientCount;
	int fakeCount;
	int statBotsCount;
	int idBotNot;
	int idBotLive;
	char name[8];
	
	for(int client = 1; client <= MaxClients; client++)
	{
		if(IsClientConnected(client))
		{
			if(IsFakeClient(client))
			{
				GetClientName(client, name, sizeof(name));
				++fakeCount;
				
				if(StrEqual("NotLive", name))
				{
					idBotNot = client;
					++statBotsCount;
				}
				else if(StrEqual("Live", name))
				{
					idBotLive = client;
					++statBotsCount;
				}
			}
			else
			{
				++realClientCount;
			}
		}
	}
	
	for(int client = 1; client <= MaxClients; client++)
	{
		if(IsClientConnected(client))
		{
			if(IsFakeClient(client))
			{
				GetClientName(client, name, sizeof(name));
					
				if(client != idBotLive && client != idBotNot && (StrContains(name, "Live", true) >= 0))
				{
					KickClient(client, "extra StatBots?");
					--fakeCount;
				}
			}
		}
	}
	
	if(realClientCount == 0 || (realClientCount + fakeCount) == MaxClients)
	{
		PrintToChatAll("Couldn't create StatBot as server is full");
		return;
	}
	
	if(statBotsCount == 0)
	{
		g_botLive = -1;
		g_botNot = -1;
	}
	
	if(g_isLive == true)
	{
		if(idBotNot != 0)
		{
			KickClient(idBotNot, "live");
			g_botNot = -1;
		}
		
		if(idBotLive != 0)
		{
			//Live bot is already connected
			return;
		}
		
		g_botLive = CreateFakeClient("Live");
		FakeClientCommand(g_botLive, "jointeam 1");
		
	}
	else if(g_isLive == false)
	{
		if(idBotLive != 0)
		{
			KickClient(idBotLive, "not live");
			g_botLive = -1;
		}
		
		if(idBotNot != 0)
		{
			//NotLive bot is already connected
			return;
		}
		
		g_botNot = CreateFakeClient("NotLive");
		FakeClientCommand(g_botNot, "jointeam 1");
	}		
}

public void OnClientConnected(int client)
{
	if(!IsFakeClient(client))
	{
		g_isReady[client] = false;
		StatBots();
	}
}

public void OnRoundEndPost(Event event, const char[] name, bool dontBroadcast)
{
	EndLive();
}

void EndLive()
{
	ResetVariables();
	RequestFrame(StatBots);
	RequestFrame(ToggleTV);
	PrintToChatAll("Round ended, NOT Live");
}

void CancelLive()
{
	EndLive();
	PrintToChatAll("Round going Live was cancelled!");
}

public Action Cmd_Start(int client, int args)
{
	if(client == 0 || args > 0)
	{
		return Plugin_Handled;
	}
	
	if(g_isLive || g_start || !g_waitingForStart)
	{
		PrintToChat(client, "Not expecting !start");
		return Plugin_Handled;
	}
	
	if(GetClientTeam(client) == 2)
	{
		g_punkStart = true;
	}
	else if(GetClientTeam(client) == 3)
	{
		g_corpStart = true;
	}
	
	if(g_corpStart && g_punkStart)
	{
		g_start = true;
		CheckStartMatch();
	}
	
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

public Action Cmd_UnReady(int client, int args)
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
	
	if(!g_isReady[client])
	{
		PrintToChat(client, "You are already marked as unready");
		return Plugin_Handled;
	}
	
	g_isReady[client] = false;
	
	PrintToChatAll("%N is NOT ready", client);
	CheckStartMatch();
	return Plugin_Handled;
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
	
	if(g_isReady[client])
	{
		PrintToChat(client, "You are already marked as ready, use !unready to revert this");
		return Plugin_Handled;
	}
	
	g_isReady[client] = true;
	
	PrintToChatAll("%N is ready", client);
	CheckStartMatch();
	return Plugin_Handled;
}

void CheckStartMatch()
{
	if(g_isLive)
	{
		PrintToChatAll("Oops, trying to start match when already live");
		return;
	}
	
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
	
	if(unReady > 0 && g_goingLive)
	{
		CancelLive();
	}
	
	if(unReady == 0)
	{
		if(!g_forceLive && GetTeamClientCount(2) != 5 && GetTeamClientCount(3) != 5)
		{
			if(!g_start)
			{
				g_waitingForStart = true;
				PrintToChatAll("Both teams must use !start as teams are not 5v5");
				return;
			}
			else
			{
				g_start = false;
				g_corpStart = false;
				g_punkStart = false;
				g_waitingForStart = false;
			}
		}
		
		g_goingLive = true;
		
		if(!IsValidHandle(g_liveTimer))
		{
			g_liveTimer = CreateTimer(1.0, GoingLive, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
		}
	}
}

public Action GoingLive(Handle timer)
{
	if(!g_goingLive || g_isLive)
	{
		return Plugin_Stop;
	}
	
	if(g_timerBeeps == 9)
	{
		g_isLive = true;
		g_goingLive = false;
		g_forceLive = false;
		g_godEnabled = false;
		
		RequestFrame(StatBots);
		RequestFrame(ToggleTV);
		
		for(int i = 1; i <= MaxClients; i++)
		{
			g_isReady[i] = false;
		}
		
		g_timerBeeps = 0;
		
		ServerCommand("map_restart");
		PrintToChatAll("Round is live!");
		return Plugin_Stop;
	}
	
	PlayLiveBeep();
	++g_timerBeeps;
	PrintToChatAll("Round is going live in: %d", (10 - g_timerBeeps));
	return Plugin_Continue;
}

public Action Command_God(int client, int args)
{
	if(g_isLive || g_goingLive)
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
	else
	{
		SetEntityHealth(client, 75);
	}	
}
