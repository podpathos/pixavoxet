tool
extends Spatial

export var vox_file_path = ""
export var model_index = 0
export var offset_pivot = Vector3(0,-0.5,0)
export var voxel_size = 1.0
export(String, "cube", "sphere") var voxel_shape = "cube"
export(Mesh) var voxel_custom_shape = null
var magica_voxel_file = null
var multi_mesh_instance = MultiMeshInstance.new()
var multi_mesh_color_lookup = {}
var multi_mesh_color_index = {}

class Voxel:
	var position = Vector3(0,0,0)
	var color_index = 0

	func read(stream):
		position.z = stream.get_8()
		position.x = stream.get_8()
		position.y = stream.get_8()
		color_index = stream.get_8()-1

class STRING:
	var text = ""
	func read(stream):
		var buffer_size = stream.get_32()
		var arr = PoolByteArray([])
		for i in range(buffer_size):
			arr.append(stream.get_8())
		text = arr.get_string_from_ascii()

class MVDictionary:
	var dictionary = {}

	func read(stream):
		var key = STRING.new()
		key.read(stream)
		var value = null
		if(key.text == "_name"):
			value = STRING.new()
			value.read(stream)
		elif(key.text == "_hidden"):
			value = stream.get_buffer(1)[0]
		elif(key.text == "_r"):
			value = stream.get_8()
		elif(key.text == "_t"):
			value = Vector3(0,0,0)
			value.x = stream.get_32()
			value.y = stream.get_32()
			value.z = stream.get_32()
		dictionary[key] = value

class Model:
	var id
	var voxels
	var size

class MagicaVoxelFile:
	var models = null
	var palette = null

var wait = 0

func _ready():
	if(!magica_voxel_file):
		if(vox_file_path != ""):
			magica_voxel_file = _load(vox_file_path)
			render_voxels()
		else:
			print("Missing Voxel Model Path for " + get_name())

func _process(delta):
	if(Input.is_key_pressed(KEY_TAB) || !magica_voxel_file):
		if(vox_file_path != ""):
			magica_voxel_file = _load(vox_file_path)
			render_voxels()
		else:
			print("Missing Voxel Model Path for " + get_name())

func render_voxels():
	print("Rendering Voxels for " + get_name())
	multi_mesh_color_lookup = {}
	multi_mesh_color_index = {}
	var palette = magica_voxel_file.palette
	if(model_index >= magica_voxel_file.models.size()):
		print("There is/are only " + str(magica_voxel_file.models.size()) + " models!!!")
		return
	var model = magica_voxel_file.models[model_index]
	var material = SpatialMaterial.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.flags_unshaded = true
	var cube_mm = MultiMesh.new()
	if(!voxel_custom_shape):
		var cube = null
		if(voxel_shape == "cube"):
			cube = CubeMesh.new()
		if(voxel_shape == "sphere"):
			cube = SphereMesh.new()
		if(cube is SphereMesh):
			cube.radius = voxel_size
			cube.height = voxel_size*2
		if(cube is CubeMesh):
			cube.size = Vector3(voxel_size,voxel_size,voxel_size)
		cube.material = material
		cube_mm.mesh = cube
	else:
		multi_mesh_instance.set_material_override(material)
		cube_mm.mesh = voxel_custom_shape
	cube_mm.color_format = MultiMesh.COLOR_FLOAT
	cube_mm.transform_format = MultiMesh.TRANSFORM_3D
	cube_mm.instance_count = model.voxels.keys().size()
	multi_mesh_instance.multimesh = cube_mm

	var size = model.size
	var offset = Vector3(size.y/2,0,size.x/2) + offset_pivot

	var voxel_positions = model.voxels.keys()
	var index = 0
	for position in voxel_positions:
		var color_index = model.voxels[position]
		var color =  palette[color_index]
		multi_mesh_instance.multimesh.set_instance_color(index, color)
		multi_mesh_instance.multimesh.set_instance_transform(index, Transform(Basis(), position - offset))
		multi_mesh_color_lookup[index] = color
		multi_mesh_color_index[index] = color_index
		index += 1
	get_tree().get_edited_scene_root().call_deferred('add_child',multi_mesh_instance)
	#multi_mesh_instance.set_owner(get_tree().get_edited_scene_root())


func _load(_path):
	var stream = File.new()
	stream.open(_path,1)
	var data = []
	var colors = []
	var voxelData = []
	var a = PoolByteArray([])
	for i in range(4):
		a.append(stream.get_8())
	var MAGIC = a.get_string_from_ascii()
	var VERSION = stream.get_32()

	var models = []
	var sizes = []
	if (MAGIC == "VOX "):
		var last_position = stream.get_position()
		while (stream.get_position() < stream.get_len()):
			a = PoolByteArray([])
			for i in range(4):
				a.append(stream.get_8())
			var CHUNK_ID = a.get_string_from_ascii()
			var CHUNK_SIZE = stream.get_32()
			var CHILD_CHUNKS = stream.get_32()
			var desired_position = stream.get_position() + CHUNK_SIZE
			var CHUNK_NAME = CHUNK_ID
			var numModels = 1
			if (CHUNK_NAME == "PACK"):
				numModels = stream.get_32()
			elif (CHUNK_NAME == "SIZE"):
				var sizex = stream.get_32()
				var sizey = stream.get_32()
				var sizez = stream.get_32()
				sizes.append(Vector3(sizex, sizey, sizez))
				for i in range(CHUNK_SIZE - 4 * 3):
					stream.get_8()
			elif (CHUNK_NAME == "XYZI"):
				var model = {}
				var numVoxels = stream.get_32()
				var div = 1
				for i in range(numVoxels):
					var vox = Voxel.new()
					vox.read(stream)
					model[vox.position] = vox.color_index
				models.append(model)
			elif (CHUNK_NAME == "RGBA"):
				colors = []
				for i in range(0,256):
					var color = Color8(stream.get_8(),stream.get_8(),stream.get_8(),stream.get_8())
					colors.append(color)
			stream.seek(desired_position)
	var MODELS = []
	for i in range(0,models.size()):
		var voxels = models[i]
		var model = Model.new()
		model.id = i
		var culled_voxels = {}
		for p in voxels.keys():
			var bordered = 0
			if(voxels.keys().has(p + Vector3(1,0,0))):
				bordered += 1
			if(voxels.keys().has(p + Vector3(-1,0,0))):
				bordered += 1
			if(voxels.keys().has(p + Vector3(0,1,0))):
				bordered += 1
			if(voxels.keys().has(p + Vector3(0,-1,0))):
				bordered += 1
			if(voxels.keys().has(p + Vector3(0,0,1))):
				bordered += 1
			if(voxels.keys().has(p + Vector3(0,0,-1))):
				bordered += 1
			if(bordered != 6):
				culled_voxels[p] = voxels[p]
		model.voxels = culled_voxels
		model.size = sizes[i]
		MODELS.append(model)
	var MVFILE = MagicaVoxelFile.new()
	MVFILE.models = MODELS
	MVFILE.palette = colors
	return MVFILE