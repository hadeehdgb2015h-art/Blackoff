# Input and HUD

## Touch (`scripts/input/touch_controls.gd`)
- Left 42 % of the screen: floating move stick, which appears where the thumb lands.
- Right side: drag anywhere to aim. **FIRE also aims while held**, so you can shoot and turn with one thumb.
- Buttons: FIRE, R (reload), SWAP (weapon), USE (shown only near a buy or ammo point), REVIVE (phase 5), II (pause).
- Fully multi-touch: each finger is tracked by touch index. Button presses are latched until the next sim tick, so short taps are never lost.
- Sensitivity: 0.2° per pixel × the setting. An invert option is available.
- Desktop: WASD, mouse look (click to capture), LMB fire, R, Q swap, E use, F revive, Esc pause.

## HUD (`scripts/ui/hud.gd`)
Health bar, wave and remaining count or intermission countdown, credits with +reward pop-ups, ammo and weapon name, reload or no-ammo status, interaction prompt with price (greyed out when you can't afford it or ammo is full), crosshair that widens while moving, hit markers (red for head or kill), damage vignette, wave banners, downed timer, game-over panel.

## Settings (`scripts/core/settings.gd`, autoload)
Saved to `user://settings.cfg`: sensitivity, invert-Y, quality, show FPS, volume.
