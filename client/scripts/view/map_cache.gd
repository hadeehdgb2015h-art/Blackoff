class_name MapCache
extends RefCounted
## Prepared maps for the session: the authored scene with its art props placed
## (MapDecor) and its static meshes merged (MapBatcher). Preparing costs over a
## second in a phone's browser (the prop libraries are loaded and every mesh is
## merged), so it happens once, under the menu's curtain at start-up, and every
## match (and every "play again") takes a cheap duplicate that shares the
## merged meshes. Baking at build time was measured and rejected: 6 MB more on
## every update download.

static var _prepared := {}   ## scene path -> prepared root (never in the tree itself)


static func is_ready(path: String) -> bool:
	return _prepared.has(path)


## Builds the prepared map now (blocking); a no-op when it is cached.
static func prepare(path: String) -> void:
	if _prepared.has(path):
		return
	var t0 := Time.get_ticks_msec()
	var root := (load(path) as PackedScene).instantiate() as Node3D
	# props and merging work from transforms relative to the root: no scene tree
	# needed (this may run inside another scene's _ready)
	var props := MapDecor.decorate(root)
	var batches := MapBatcher.batch(root)
	root.scene_file_path = ""  # a prepared map is no longer the authored scene
	_prepared[path] = root
	print("[load] map prepared: %d props, %d merged meshes in %d ms" % [props, batches, Time.get_ticks_msec() - t0])


## A fresh copy of the prepared map for one match (meshes are shared).
static func instance(path: String) -> Node3D:
	prepare(path)
	# Not DUPLICATE_USE_INSTANTIATION (the default): that re-instantiates the
	# authored scene, unmerged meshes and all, under the merged ones (2x draws).
	return (_prepared[path] as Node3D).duplicate(Node.DUPLICATE_SIGNALS | Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS) as Node3D
