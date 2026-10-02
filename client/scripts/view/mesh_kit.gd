class_name MeshKit
extends RefCounted
## Builds low-poly placeholder meshes from primitive parts, merged into one
## ArrayMesh (one surface per material) to keep draw calls low.


## parts: [{mesh: PrimitiveMesh, xform: Transform3D, mat: int}], mats: [Material]
static func merge(parts: Array, mats: Array) -> ArrayMesh:
	var tools := []
	for m in mats:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		tools.append(st)
	var used := {}
	for p in parts:
		var prim: PrimitiveMesh = p.mesh
		var arrays := prim.get_mesh_arrays()
		var tmp := ArrayMesh.new()
		tmp.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		tools[p.mat].append_from(tmp, 0, p.xform)
		used[p.mat] = true
	var out := ArrayMesh.new()
	for i in mats.size():
		if not used.has(i):
			continue
		var st: SurfaceTool = tools[i]
		st.set_material(mats[i])
		st.commit(out)
	return out


static func box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func capsule(radius: float, height: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = radius
	c.height = height
	c.radial_segments = 10
	c.rings = 4
	return c


static func sphere(radius: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2
	s.radial_segments = 12
	s.rings = 6
	return s


static func cylinder(radius: float, height: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = 8
	c.rings = 1
	return c


static func mat(color: Color, roughness := 0.85, emission := Color.BLACK) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	if emission != Color.BLACK:
		m.emission_enabled = true
		m.emission = emission
	return m


static func xf(pos: Vector3, rot := Vector3.ZERO) -> Transform3D:
	return Transform3D(Basis.from_euler(rot), pos)
