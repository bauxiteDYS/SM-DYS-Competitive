# SM-DYS-Competitive
Sourcemod plugin for Dystopia that assists competitive play, players can `!ready` up to go live, "godmode" is enabled during warmup rounds.
Credits to Rain for the help and for writing a lot of code to learn from :)  

# Instructions for server admins  
Add the cvar `sm_comp_demo_path "your_demo_dir"` into `server.cfg` to customise the default path which is `comp_demos`, it can't be greater than 64 characters, and can only include `a-z`, `0-9`, `_` and `-` characters.  

**Note:** The plugin will record STV demos for live rounds if `tv_autorecord 0` is set, but if it's set to `tv_autorecord 1` then the plugin will not record any demos and let the server handle the recording instead.
