# Godot build profile for Blackoff's web export template (phase 17).
# The stock web template ships every engine module (37.7 MB wasm). The game
# draws 3D with its own simulation (no engine physics or navigation), talks
# over WebSocket, scripts in GDScript, and needs the advanced text server only
# to shape Arabic player names. Everything else is left out.
#   scons platform=web target=template_release profile=tools/engine/blackoff_web.py
threads = False
optimize = "size"          # smaller and faster to download/compile on phones; the hot code is GPU-bound
lto = "full"
deprecated = False
minizip = False
brotli = True             # the default font is WOFF2 (Brotli): without it HUD text shows boxes
disable_physics_2d = True
disable_physics_3d = True
disable_navigation_2d = True
disable_navigation_3d = True
disable_xr = True
disable_advanced_gui = True  # no RichTextLabel, Tree, TextEdit, dialogs... in the game UI
modules_enabled_by_default = False
module_gdscript_enabled = True
module_websocket_enabled = True
module_text_server_adv_enabled = True
module_freetype_enabled = True
module_webp_enabled = True
module_mbedtls_enabled = True
graphite = False           # text_server_adv: no Graphite fonts needed
