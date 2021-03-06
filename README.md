# NMRiH - Team Mini Games
This plugin will provide a much better experience in certain mini-game maps like sm_artificial_grass or tdm_castle_assault, people will be divided in teams of 4, match will be "Red vs Blue" and you will be able to identify your own goal and teammates.

https://forums.alliedmods.net/showthread.php?p=2689340

# Admin commands (SoccerMod)
- `sm_soccermod` = !soccermod
    "Opens admin menu"
- `sm_endround` = !endround
    "Instantly ends round"
- `sm_forcerandom` = !forcerandom
    "Shuffle teams and restart match"

# Client commands (SoccerMod)
- `sm_red` = !red
    "Instantly switch to red team"
- `sm_blue` = !blue
    "Instantly switch to blue team"
- `sm_shuffle` = !shuffle
    "Vote to shuffle or randomize teams"

# Install
- Simply copy and paste .smx inside addons/sourcemod/plugins folder
- Use both `nmrih_tdm_maps.cfg` and `nmrih_soccermod_maps.cfg` files located inside addons/sourcemod/configs folder

# Example maps:
- (Team Deathmatch) https://steamcommunity.com/sharedfiles/filedetails/?id=2040089546
- (SoccerMod) https://steamcommunity.com/sharedfiles/filedetails/?id=1971319798

# Map Requirements
- RED `trigger_multiple` (area_red) --> Adds players to RED team
- BLUE `trigger_multiple` (area_blue) --> Adds players to BLUE team
- RED `trigger_multiple` (terro_But) --> BLUE team will try to score in this net
- BLUE `trigger_multiple` (ct_But) --> RED team will try to score in this net
- RED Spawn `info_player_nmrih` (t_player) --> SoccerMod
- BLUE Spawn `info_player_nmrih` (ct_player) --> SoccerMod
- RED Spawn `info_player_nmrih` (attacker) --> Team Deathmatch
- BLUE Spawn `info_player_nmrih` (defender) --> Team Deathmatch
- Extraction Zone `func_nmrih_extractionzone`
- RED Teleport destination `trigger_teleport` (TeledestinationT) --> RED team base teleport
- BLUE Teleport destination `trigger_teleport` (TeledestinationCt)--> BLUE team base teleport
- RED `trigger_multiple` (red_trigger_npc_area)
- BLUE `trigger_multiple` (blue_trigger_npc_area)
