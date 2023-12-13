extends Node
class_name CellularAutomata2D

var current_pass 	: int = 0

#region ComputeShaderStudio

var GLSL_header = ""
## Print the current step.
@export var print_step:bool = false
## Print the current pass.
var print_passes:bool = false
## Print in Output all the generated code.
## Can be usefull for debugging.
@export var print_generated_code:bool = false
## Do not execute compute shader at launch.
@export var pause:bool = false
## Number of passes (synchronized code) needed.
var nb_passes		: int = 2
## Workspace Size X, usually it matches the x size of your Sprite2D image
@export var WSX				: int = 128
## Workspace Size Y, usually it matches the y size of your Sprite2D image
@export var WSY				: int = 128

## Drag and drop your Sprite2D here.
@export var display_in:Node
#var matrix_future:Sprite2D

@export var cell_states : Array[StringColor] = [StringColor.new()]

## Write your initialisation code here (in GLSL)
@export_multiline var init_code : String = """
// INITIALISATION CODE (step = 0)
// You will use the following variables:
//    uint WSX, WSY (global WorkSpace in X and Y)
//    uint x,y,p (cell position)
//    int present_state (cell state. An integer random value from int.MIN and int.MAX)
//    int future_state (the new cell state)
"""

## Write your execution code here (in GLSL)
@export_multiline var exec_code : String = """
// EXECUTION CODE (step >= 1)
// You will use the following variables:
//    uint WSX, WSY (global WorkSpace in X and Y)
//    uint x,y,p (cell position)
//    int present_state (current cell state. Do not modify)
//    int future_state (the new cell state)
"""

## Write your own functions here (in GLSL)
@export_multiline var functions_code : String = """
// FUNCTIONS CODE
// Write all your functions here (in GLSL)
// You can use the following global variables:
//    uint WSX, WSY (global WorkSpace in X and Y)
// Example
// int your_function(int x, int y) {
//    if (x == WSX/2 && y == WSY/2)
//       return my_state_1
//    else
//       return my_state_2
// }
"""

var rd 				: RenderingDevice
var shader 			: RID
var shader_src 		: RDShaderSource
var buffers 		: Array[RID]
var buffer_params 	: RID

var uniforms		: Array[RDUniform]
#var uniform_2 		: RDUniform
var uniform_params 	: RDUniform

var buffers_init	: bool = false
var uniforms_init	: bool = false

var bindings		: Array = []

var pipeline		: RID
var uniform_set		: RID

# Called when the node enters the scene tree for the first time.
#region _ready
#func _enter_tree():
#	cell_states = [StringColor.new(),StringColor.new()]
func _ready():
	compile(init_code,exec_code,functions_code)

func compile(init, exec, functions):
	step = 0
	current_pass = 0
	# Create a local rendering device.
	if not rd:
		rd = RenderingServer.create_local_rendering_device()
	if not rd:
		set_process(false)
		print("Compute shaders are not available")
		return
		
	# *********************
	# *  SHADER CREATION  *
	# *********************

	GLSL_header = """#version 450

// Invocations in the (x, y, z) dimension
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

// Bindings to the buffers we create in our script
layout(binding = 0) buffer Params {
	int step;
	int current_pass;
};

"""

	var nb_buffers : int = 2

	# Create GLSL Header
	GLSL_header += """
uint WSX="""+str(WSX)+""";"""+"""
uint WSY="""+str(WSY)+""";
"""

	GLSL_header += """
layout(binding = 1) buffer Data0 {
	int data_present[];
};
"""
	GLSL_header += """
layout(binding = 2) buffer Data1 {
	int data_future[];
};
"""

	var states_code : String = "" # States of cells
	for s in cell_states:
		var col_html:String = s.color.to_html(true)
		var R:String = col_html.substr(0,2)
		var G:String = col_html.substr(2,2)
		var B:String = col_html.substr(4,2)
		var A:String = col_html.substr(6,2)
		var line : String = "int " +s.text+ " = 0x" +A+B+G+R+";"
		line += """
"""
		states_code += line
	GLSL_header += states_code


	GLSL_header += """
uint nb_neighbors_8(uint x,uint y, int state) {
	uint nb = 0;
	uint p = x + y * WSX;
	for(int i = int(x)-1; i <= int(x)+1; i++) {
		uint ii = uint((i+int(WSX))) % WSX;
		for(int j = int(y)-1; j <= int(y)+1; j++) {
			uint jj = uint((j+int(WSY))) % WSY;
			uint kk = ii + jj * WSX;
			if(data_present[kk] == state && kk != p)
				nb++;
		}
	}
	return nb;
}
"""

	GLSL_header += functions


	var GLSL_code : String = """
void main() {
	uint x = gl_GlobalInvocationID.x;
	uint y = gl_GlobalInvocationID.y;
	uint p = x + y * WSX;

	if(current_pass == 0) {
		int present_state = data_present[p];
		// Write your RULES below vvvvvvvvvvvvvvvvv
		int future_state = present_state;
		if(step == 0) { // Initialization ---------
""" + init + """
		} else { // Execution----------------------
""" + exec + """
		}
		// END of your RULES ^^^^^^^^^^^^^^^^^^^^^^
		data_future[p] = future_state;
	} else { // current_pass = 1
		data_present[p] = data_future[p];
	}

}
"""



	var GLSL_all : String = GLSL_header + GLSL_code
	if print_generated_code == true:
		print(GLSL_all)
	
	# Compile the shader by passing a string
	if not shader_src:
		shader_src = RDShaderSource.new()
	shader_src.set_stage_source(RenderingDevice.SHADER_STAGE_COMPUTE, GLSL_all)
	var shader_spirv := rd.shader_compile_spirv_from_source(shader_src)
	
	var err:String=shader_spirv.compile_error_compute
	
	if err != "":
		printerr(err)
		get_tree().quit()
	
	shader = rd.shader_create_from_spirv(shader_spirv)









	# *********************
	# *  BUFFERS CREATION *
	# *********************
	if buffers_init == false:
		# Buffer for current_pass
		var input_params :PackedInt32Array = PackedInt32Array()
		input_params.append(step)
		input_params.append(current_pass)
		var input_params_bytes := input_params.to_byte_array()
		buffer_params = rd.storage_buffer_create(input_params_bytes.size(), input_params_bytes)
		
		# Buffers from/for data (Sprite2D)
		for b in nb_buffers:
			var input :PackedInt32Array = PackedInt32Array()
			for i in range(WSX):
				for j in range(WSY):
					input.append(randi())
			var input_bytes :PackedByteArray = input.to_byte_array()
			buffers.append(rd.storage_buffer_create(input_bytes.size(), input_bytes))

	buffers_init = true

	# *********************
	# * UNIFORMS CREATION *
	# *********************
	
	# Create current_pass uniform pass
	uniform_params = RDUniform.new()
	uniform_params.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_params.binding = 0 # this needs to match the "binding" in our shader file
	uniform_params.add_id(buffer_params)
	
	var nb_uniforms : int = 2
	for b in nb_uniforms:
		var uniform = RDUniform.new()
		uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		uniform.binding = b+1 # this needs to match the "binding" in our shader file
		uniform.add_id(buffers[b])
		uniforms.append(uniform)

	# Create the uniform SET between CPU & GPU
	bindings = [uniform_params]
	for b in nb_buffers:
		bindings.append(uniforms[b])
	
	uniform_set = rd.uniform_set_create(bindings, shader, 0) # the last parameter (the 0) needs to match the "set" in our shader file

	# **************************
	# *  COMPUTE LIST CREATION *
	# **************************
	# Create a compute pipeline
	pipeline = rd.compute_pipeline_create(shader)
	
	# Execute once (should it stay?)
	# compute()
	# Read back the data from the buffer
	# display_all_values()
#endregion

func display_all_values():
	# Read back the data from the buffers
	var output_bytes :   PackedByteArray = rd.buffer_get_data(buffers[0])
	if is_instance_valid(display_in):
		display_values(display_in, output_bytes)
	var output_bytes_future :   PackedByteArray = rd.buffer_get_data(buffers[1])
	#if is_instance_valid(matrix_future):
	#	display_values(matrix_future, output_bytes)

func display_values(disp, values : PackedByteArray):
	var image_format : int = Image.FORMAT_RGBA8
	var image := Image.create_from_data(WSX, WSY, false, image_format, values)
	disp.set_texture(ImageTexture.create_from_image(image))

var step  : int = 0

func compute():
	if print_step == true && current_pass%nb_passes == 0:
		print("Step="+str(step))
	if print_passes == true:
		print(" CurrentPass="+str(current_pass))
	
	_update_uniforms()
	
	# Prepare the Computer List ############################################
	var compute_list : int = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_dispatch(compute_list, WSX>>3, WSY>>3, 1)
	rd.compute_list_end()
	#######################################################################

	# Submit to GPU and wait for sync
	rd.submit()
	rd.sync()
	
	# Update step and current_passe
	current_pass = (current_pass + 1) % nb_passes
	if current_pass == 0:
		step += 1

func _process(_delta):
	if pause == false:
		compute()
		display_all_values()

## Pass the interesting values from CPU to GPU
func _update_uniforms():
	# Buffer for current_pass
	var input_params :PackedInt32Array = PackedInt32Array()
	input_params.append(step)
	input_params.append(current_pass)
	var input_params_bytes := input_params.to_byte_array()
	buffer_params = rd.storage_buffer_create(input_params_bytes.size(), input_params_bytes)
	# Create current_pass uniform pass
	uniform_params = RDUniform.new()
	uniform_params.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform_params.binding = 0 # this needs to match the "binding" in our shader file
	uniform_params.add_id(buffer_params)
	bindings[0] = uniform_params
	
	uniform_set = rd.uniform_set_create(bindings, shader, 0)
	# Note: when changing the uniform set, use the same bindings Array (do not create a new Array)

func _notification(notif):
	# Object destructor, triggered before the engine deletes this Node.
	if notif == NOTIFICATION_PREDELETE:
		cleanup_gpu()
		
func cleanup_gpu():
	if rd == null:
		return
	# All resources must be freed after use to avoid memory leaks.
	rd.free_rid(pipeline)
	pipeline = RID()

	rd.free_rid(uniform_set)
	uniform_set = RID()

	rd.free_rid(shader)
	shader = RID()

	#rd.free()
	#rd = null

func clean_up_cpu():
	#buffers = []#.clear()
	#uniforms = []#.clear()
	#bindings = []#.clear()
	pass

#endregion

func _on_button_step():
	pause = true
	compute() # current_pass = 0
	compute() # current_pass = 1
	display_all_values()

func _on_button_play():
	pause = false # Replace with function body.
