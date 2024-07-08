#include <sdktools>

ConVar g_stvName;
ConVar g_demoPath;
ConVar g_cvarAutoRecord = null;
Handle g_forceTimer;
Handle g_listTimer;
Handle g_liveTimer;
static char g_newDemoPath[128];
static char g_soundLive[] = "buttons/button17.wav";

bool g_isTVRecording;
bool g_autoRecording;
int g_stvID = -1;
int g_botLive = -1;
int g_botNot = -1;

bool g_isReady[65+1];
bool g_isPlaying[65+1];
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

public Plugin myinfo = {
	name = "Dys Competitive",
	description = "Players can !ready up to start a comp round",
	author = "bauxite",
	version = "0.5.1",
	url = "https://github.com/bauxiteDYS/SM-DYS-Competitive",
};

public void OnPluginStart()
{
	RegAdminCmd("sm_god", Command_God, ADMFLAG_GENERIC);	
	RegAdminCmd("sm_forcelive", Command_ForceLive, ADMFLAG_GENERIC);
	HookEvent("round_end", OnRoundEndPost, EventHookMode_Post);
	HookEvent("player_team", OnPlayerTeamPost, EventHookMode_Post);
	HookEvent("player_spawn", OnPlayerSpawnPost, EventHookMode_Post);
	HookEvent("player_class", OnPlayerSpawnPost, EventHookMode_Post);
	HookEvent("player_connect_client", OnBotPre, EventHookMode_Pre);
	HookEvent("player_disconnect", OnBotPre, EventHookMode_Pre);
	AddCommandListener(OnLayoutDone, "layoutdone")
	RegConsoleCmd("sm_ready", Cmd_Ready);
	RegConsoleCmd("sm_unready", Cmd_Ready);
	RegConsoleCmd("sm_readylist", Cmd_ReadyList);
	RegConsoleCmd("sm_start", Cmd_Start);
	g_demoPath = CreateConVar("sm_comp_demo_path", "comp_demos", "Folder to save STV demos into, relative to game folder");
}

public void OnMapStart()
{
	ResetVariables();
	RequestFrame(StatBots);
	PrecacheSound(g_soundLive);
}

public void OnConfigsExecuted()
{
	g_cvarAutoRecord = FindConVar("tv_autorecord");
		
	if (g_cvarAutoRecord != null)
	{
		g_autoRecording = g_cvarAutoRecord.BoolValue;
		PrintToServer("STV Auto Record %s", g_autoRecording ? "enabled" : "disabled");
	}
	else
	{
		g_autoRecording = false;
	}
	
	CreateDemoPath();
	RequestFrame(StatBots);
}

public void OnMapEnd()
{
	ResetOnceOnMapEnd();
}

public void OnClientConnected(int client)
{
	g_isReady[client] = false;
	g_isPlaying[client] = false;
	RequestFrame(StatBots);
}

public Action OnBotPre(Handle event, const char[] name, bool dontBroadcast)
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
	if(!g_isReady[client])
	{
		return;
	}
	
	g_isReady[client] = false;
	
	if(g_goingLive)
	{
		CheckStartMatch();
	}
}

void CreateDemoPath()
{
	if(g_autoRecording)
	{
		return;
	}
	
	char path[64+1];
	
	g_demoPath.GetString(path, sizeof(path));
	TrimString(path);
	int len = strlen(path);
	
	if(len != 0)
	{
		for(int chr = 0; chr < len; chr++)
		{
			if(IsCharAlpha(path[chr]) || IsCharNumeric(path[chr]) || path[chr] == '_' || path[chr] == '-')
			{
				continue;
			}
		
			path[chr] = '0';
		}
	
		strcopy(g_newDemoPath, sizeof(g_newDemoPath), path);
	}
	else
	{
		strcopy(g_newDemoPath, sizeof(g_newDemoPath), "comp_demos");
	}
	
	if(!DirExists(g_newDemoPath, false))
	{
		CreateDirectory(g_newDemoPath, 0o775); // 509 in decimal, using octal to make it easier
	}
}

void ResetOnceOnMapEnd()
{
	g_isTVRecording = false;
	g_botLive = -1;
	g_botNot = -1;
	g_stvID = -1;
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
		g_isPlaying[i] = false;
	}
}

void ToggleTV()
{
	if(g_autoRecording)
	{
		return;
	}
	
	if(g_isLive && !g_isTVRecording)
	{
		char mapName[32];
		GetCurrentMap(mapName, sizeof(mapName));
		
		char timestamp[16];
		FormatTime(timestamp, sizeof(timestamp), "%Y%m%d-%H%M");
		
		char demoName[PLATFORM_MAX_PATH];
		Format(demoName, sizeof(demoName), "%s_%s", mapName, timestamp);
		
		ServerCommand("tv_stoprecord");
		ServerCommand("tv_record \"%s\\%s\"", g_newDemoPath, demoName);
		
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

public void OnPlayerTeamPost(Handle event, const char[] name, bool dontBroadcast)
{
	if(g_isLive)
	{
		return;
	}
	
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

public void OnPlayerSpawnPost(Handle event, const char[] name, bool dontBroadcast)
{
	if(g_isLive)
	{
		return;
	}
	
	if(g_godEnabled && !g_isLive)
	{
		int client = GetClientOfUserId(GetEventInt(event, "userid"));
		RequestFrame(SetGodMode, client);
	}
}

public Action OnLayoutDone(int client, const char[] command, int argc)
{
	if(g_isLive)
	{
		return Plugin_Continue;
	}
	
	if(g_godEnabled && !g_isLive)
	{
		RequestFrame(SetGodMode, client);
	}
	
	return Plugin_Continue;
}

int FindSTV()
{
	char tvName[MAX_NAME_LENGTH];
	g_stvName = FindConVar("tv_name");
	g_stvName.GetString(tvName, sizeof(tvName));

	char clientName[MAX_NAME_LENGTH];
	
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client) || !IsFakeClient(client))
		{
			continue;
		}
		
		GetClientName(client, clientName, sizeof(clientName));

		if (StrEqual(clientName, tvName) || StrEqual(clientName, "SourceTV"))
		{
			return client;
		}
	}

	return -1;
}

void StatBots()
{
	int realClientCount;
	int fakeCount;
	int statBotsCount;
	int idBotNot;
	int idBotLive;
	char name[8];
	
	g_stvID = FindSTV();
		
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
		if(!IsClientConnected(client) || !IsFakeClient(client))
		{
			continue;
		}
					
		if(client == idBotLive || client == idBotNot || client == g_stvID)
		{
			continue;
		}
		
		GetClientName(client, name, sizeof(name));
		
		if(StrContains(name, "Live", true) == -1)
		{
			continue;
		}
		
		KickClient(client, "extra StatBots?");
		--fakeCount;	
	}
	
	if(realClientCount == 0 || (realClientCount + fakeCount) == MaxClients)
	{
		PrintToChatAll("Couldn't create StatBot as server is full");
		return;
	}
	
	if(statBotsCount == 0) // In case bots were manually kicked
	{
		g_botLive = -1;
		g_botNot = -1;
	}
	
	if(g_isLive == true)
	{
		if(idBotNot > 0)
		{
			KickClient(idBotNot, "live");
			g_botNot = -1;
		}
		
		if(idBotLive > 0)
		{
			//Live bot is already connected
			return;
		}
		
		g_botLive = CreateFakeClient("Live");
		FakeClientCommand(g_botLive, "jointeam 1");
		
	}
	else if(g_isLive == false)
	{
		if(idBotLive > 0)
		{
			KickClient(idBotLive, "not live");
			g_botLive = -1;
		}
		
		if(idBotNot > 0)
		{
			//NotLive bot is already connected
			return;
		}
		
		g_botNot = CreateFakeClient("NotLive");
		FakeClientCommand(g_botNot, "jointeam 1");
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
	int unReady;
	
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
			++unReady;
		}
	}
	
	if(unReady != 0)
	{
		readyMsg[strlen(readyMsg) - 2] = '\0';
	}
	else if(unReady == 0)
	{
		strcopy(readyMsg, sizeof(readyMsg), "Everyone is ready! Probably expecting !start");
	}
	
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

	char cmdName[4 + 1];
	GetCmdArg(0, cmdName, sizeof(cmdName));
	char readyChr = CharToLower(cmdName[3]);
	bool ready = readyChr == 'r' ? true : false;
	
	if(!ready)
	{
		if(!g_isReady[client])
		{
			PrintToChat(client, "You are already marked as unready");
			return Plugin_Handled;
		}
	
		g_isReady[client] = false;
		PrintToChatAll("%N is NOT ready", client);
	}
	else if(ready)
	{
		if(g_isReady[client])
		{
			PrintToChat(client, "You are already marked as ready, use !unready to revert this");
			return Plugin_Handled;
		}
	
		g_isReady[client] = true;
		PrintToChatAll("%N is ready", client);
	}

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
	
	if(g_forceLive)
	{
		if(!g_goingLive)
		{
			StartingMatch()
			return;
		}
		else if (g_goingLive)
		{
			return;
		}
	}
	
	if(g_goingLive)
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(g_isPlaying[i] && !g_isReady[i])
			{
				CancelLive();
				break;
			}
		}
		
		return;
	}
	
	int unReady;
	
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && GetClientTeam(i) > 1 && !g_isReady[i])
		{
			++unReady;	
		}
	}
	
	if(unReady == 0)
	{
		return;
	}
		
	if(GetTeamClientCount(2) != 5 && GetTeamClientCount(3) != 5)
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
		
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && GetClientTeam(i) > 1)
		{
			g_isPlaying[i] = true;
		}
	}
	
	StartingMatch();
}

void StartingMatch()
{
	g_goingLive = true;
		
	if(!IsValidHandle(g_liveTimer))
	{
		g_liveTimer = CreateTimer(1.0, GoingLive, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action GoingLive(Handle timer)
{
	if(!g_goingLive || g_isLive)
	{
		g_timerBeeps = 0;
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
			g_isPlaying[i] = false;
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
