# Input and HUD

## Touch (`scripts/input/touch_controls.gd`)
- Left 42 % of the screen: floating move stick, which appears where the thumb lands.
- Right side: drag anywhere to aim. **FIRE also aims while held**, so you can shoot and turn with one thumb.
- Buttons: FIRE, R (reload), SWAP (weapon), USE (shown only near a buy or ammo point), REVIVE (replaces USE next to a downed teammate; hold it), II (pause).
- Fully multi-touch: each finger is tracked by touch index. Button presses are latched until the next sim tick, so short taps are never lost.
- Look: 0.16° per pixel of the 720 px view × the setting (vertical × 0.8), with a speed curve (slow drags are precise at 0.6×, fast swipes reach 1.2×) and about 25 ms of smoothing against finger jitter. An invert option is available.
- Aim assist (touch only, visual): the look slows to 0.55× while the crosshair is over a visible zombie. The server still validates every shot.
- Browser quirk: Godot's web runtime turns every `pointermove`, touch fingers included, into mouse motion. That made the move-stick finger turn the camera and doubled the look speed. `shell.html` drops non-mouse `pointermove`s, and the controls ignore mouse events for 1.5 s after a real touch (the compatibility clicks phones send after a tap).
- Desktop: WASD, mouse look (click to capture), LMB fire, R, Q swap, E use (hold E or F to revive), Esc pause.

## HUD (`scripts/ui/hud.gd`)
Health bar, wave and remaining count or intermission countdown, credits with +reward pop-ups, ammo and weapon name, reload or no-ammo status, interaction prompt with price (greyed out when you can't afford it or ammo is full), crosshair that widens while moving, hit markers (red for head or kill), damage vignette, wave banners, game-over panel.
Phase 5 adds the team list under the health bar (name and health of each teammate, or DOWN with the bleed-out seconds, REVIVING, or DEAD); a pulsing red cross over each downed teammate with the distance, pinned to the screen edge with an arrow when off screen or behind you; a revive progress bar (yours or the one being done on you); the downed screen (bleed-out countdown, "being revived", or "no one left"); "back at the next wave" after bleeding out; and the game-over table (kills, headshots, downs, revives per player, from the server's `scoreboard` online).

## Settings (`scripts/core/settings.gd`, autoload)
Saved to `user://settings.cfg`: sensitivity, invert-Y, quality, show FPS, volume.
