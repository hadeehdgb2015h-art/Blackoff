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
- Layout (phase 9): every control's position (normalised to the view) and size live in `Settings.layout` (`scripts/input/touch_layout.gd`, pure functions, tested). `LayoutEditor` (Settings → CONTROLS LAYOUT, or CONTROLS on the menu) lets the player drag the stick and buttons, resize the selected one, add a second FIRE button on the left, set the HUD opacity, Reset or Save. The controls read the layout on `Settings.changed`.

Online with voice chat the HUD also has **MIC** and **SPK** buttons (under the pause button by default, movable in CONTROLS like the rest): green when on, crossed when off, the mic ring pulses while the player is heard by the voice gate, grey and crossed when the browser refused the microphone (a toast says so). Taps go to `Net.set_voice_mic` / `Net.set_voice_speaker`.

Infection mode, playing infected: FIRE reads ATTACK (`melee_mode`), reload and swap are hidden.

## HUD (`scripts/ui/hud.gd`)
Health bar, wave and remaining count or intermission countdown, credits with +reward pop-ups, ammo and weapon name, reload or no-ammo status, interaction prompt with price (greyed out when you can't afford it or ammo is full), crosshair that widens while moving, hit markers (red for head or kill), damage vignette, wave banners, game-over panel.
Phase 5 adds the team list under the health bar (name and health of each teammate, or DOWN with the bleed-out seconds, REVIVING, or DEAD); a pulsing red cross over each downed teammate with the distance, pinned to the screen edge with an arrow when off screen or behind you; a revive progress bar (yours or the one being done on you); the downed screen (bleed-out countdown, "being revived", or "no one left"); "back at the next wave" after bleeding out; and the game-over table (kills, headshots, downs, revives per player, from the server's `scoreboard` online).

The team panel draws sound waves before the name of a teammate who is talking (`Net.voice_speaking()`). In infection mode the top shows ROUND, the clock and soldiers left (or the lobby countdown / waiting count), infected players are marked INFECTED (RESPAWNING while down) in green, the local infected sees CLAWS instead of ammo and "INFECTED · hunt the soldiers"; banners: ROUND n, YOU ARE INFECTED, SOLDIERS WIN / INFECTED WIN; toasts name who was infected.

## Look (`scripts/ui/ui_theme.gd`, phase 14)
Dark fantasy: near-black stone panels and buttons drawn from small generated gradient textures (9-slice) with an old-brass edge, ember red for the calls to action, bone text, Cinzel (OFL) for titles and buttons, a diamond rule as the only ornament (no stars, sigils or symbols), a radial vignette and slow embers behind the menu, spaced capitals for subtitles. The menu shows a loading curtain before the game scene loads. Helpers: `title`, `label`, `button`, `big_button`, `gold_button`, `rule`, `vignette`, `embers`, `panel_box`.

## Settings (`scripts/core/settings.gd`, autoload)
Graphics quality defaults to **auto**: phones start on the low tier and the game steps up while the frame rate holds above 56 for 12 s (never above medium on touch devices on its own) and steps down below 42 (`game.gd: _govern_quality`, 4-second windows). The frame cap (60 or 30 FPS, `Engine.max_fps`) is a setting: 30 runs cooler. The touch controls redraw only when their drawn state changes.
Saved to `user://settings.cfg`: sensitivity, invert-Y, quality, show FPS, volume.
