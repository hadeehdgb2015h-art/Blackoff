class_name Progression
extends RefCounted
## Levels and ranks (phase 26), the client's copy of server/src/progression.ts
## (shared/tests/golden.json checks both). The server owns the XP: the client
## only shows levels and ranks, and estimates the XP of a game at game over.

const RANK_NAMES := {
	"recruit": "Recruit", "private": "Private", "corporal": "Corporal", "sergeant": "Sergeant",
	"staff_sergeant": "Staff Sergeant", "master_sergeant": "Master Sergeant", "lieutenant": "Lieutenant",
	"captain": "Captain", "major": "Major", "colonel": "Colonel", "general": "General",
	"warden_slayer": "Warden Slayer", "legend": "Legend",
}


static var _defs: Dictionary = {}


static func defs() -> Dictionary:
	if _defs.is_empty():
		var c: Dictionary = SharedData.constants if SharedData and SharedData.constants is Dictionary else {}
		if not c.has("progression"):
			# headless tests run without the autoloads: read the shared file directly
			c = JSON.parse_string(FileAccess.get_file_as_string("res://shared/constants.json"))
		_defs = c.progression
	return _defs


## Total XP needed to stand at `level` (level 1 needs none).
static func xp_to_reach(level: int) -> int:
	var p := defs()
	var n := maxi(0, mini(level, int(p.maxLevel)) - 1)
	return int(n * float(p.levelXpBase) + float(p.levelXpStep) * n * (n - 1) / 2.0)


static func level_for(xp: int) -> int:
	var max_level := int(defs().maxLevel)
	var level := 1
	while level < max_level and xp >= xp_to_reach(level + 1):
		level += 1
	return level


static func rank_for(level: int) -> Dictionary:
	var ranks: Array = defs().ranks
	var rank: Dictionary = ranks[0]
	for r in ranks:
		if level >= int(r.level):
			rank = r
	return rank


## XP of one game, as the server counts it (mode 0 zombies, 1 infection).
static func xp_for(kills: int, headshots: int, wave: int, seconds: float, mode: int) -> int:
	var p := defs()
	var base := kills * float(p.xpPerKill) + headshots * float(p.xpPerHeadshot)
	var extra := floorf(seconds / 60.0) * float(p.xpPerInfectionMinute) if mode == 1 else wave * float(p.xpPerWaveReached)
	return maxi(0, roundi(base + extra))


## The rank's name in the interface language.
static func rank_name(rank_id: String) -> String:
	match rank_id:
		"recruit": return TranslationServer.translate("Recruit")
		"private": return TranslationServer.translate("Private")
		"corporal": return TranslationServer.translate("Corporal")
		"sergeant": return TranslationServer.translate("Sergeant")
		"staff_sergeant": return TranslationServer.translate("Staff Sergeant")
		"master_sergeant": return TranslationServer.translate("Master Sergeant")
		"lieutenant": return TranslationServer.translate("Lieutenant")
		"captain": return TranslationServer.translate("Captain")
		"major": return TranslationServer.translate("Major")
		"colonel": return TranslationServer.translate("Colonel")
		"general": return TranslationServer.translate("General")
		"warden_slayer": return TranslationServer.translate("Warden Slayer")
		"legend": return TranslationServer.translate("Legend")
	return str(RANK_NAMES.get(rank_id, rank_id))
