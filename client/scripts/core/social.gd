class_name Social
extends RefCounted
## Invite and challenge links (phase 19). A link is t.me/<bot>?startapp=sq<code>:
## it opens the game in Telegram and puts the friend in this player's game
## (the server honours it while the player is in a game with room).


## True when this session can make invite links (logged in, server knows the bot).
static func can_invite() -> bool:
	return Net.invite_link() != ""


## Opens the share sheet with the squad invite. Returns a toast for the
## player ("" when Telegram's own chat picker took over).
static func invite() -> String:
	return _share(TranslationServer.translate("Join my squad in BLACKOFF: hold the waves with me against the dead!"))


## The game-over challenge: the player's result plus the same invite link.
static func challenge(wave: int, kills: int) -> String:
	if kills == 1:
		return _share(str(TranslationServer.translate("I held out to wave %d in BLACKOFF and put down %d zombie. Think you can beat that? Join my squad:")) % [wave, kills])
	return _share(str(TranslationServer.translate("I held out to wave %d in BLACKOFF and put down %d zombies. Think you can beat that? Join my squad:")) % [wave, kills])


static func _share(text: String) -> String:
	var link := Net.invite_link()
	if link == "":
		return TranslationServer.translate("Invites work when you play from the Telegram bot")
	Platform.haptic("light")
	match Platform.share(link, text):
		"copied":
			return TranslationServer.translate("Invite link copied")
		"none":
			return TranslationServer.translate("Could not open sharing here")
	return ""
