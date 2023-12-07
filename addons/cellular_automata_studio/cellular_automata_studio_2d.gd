extends Node
class_name CellularAutomata2D

var current_pass 	: int = 0

# Put your GLSL code in the GLSL_main string below
# Here are all the accessible variables (uniforms) inside your GLSL code:
#   uint x,y     : from GlobalInvocationID.x and .y
#   uint p       : the position [x][y] in the invocation
#   uint WSX,WSY : the Global WorkSpace of invocations (generally match the data size)
#   int* data_0, data_1, etc : are the data treated (can be displayed by Sprite2D).
#                  Access them by data_0[p], data_1[p], etc
#   uint step    : simulation step of the execution. Incresed by 1 after nb_passes
#   uint nb_passes: the number of passes your code needs (by step).
# 					There is a barrier between each pass.
#   uint current_pass: pass currently executed (one pass per frame, nb_passes by step)

#region ComputeShaderStudio

var GLSL_header = """#version 450

// Invocations in the (x, y, z) dimension
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

// Bindings to the buffers we create in our script
layout(binding = 0) buffer Params {
	int step;
	int current_pass;
};

"""
## Print the current step.
@export var print_step:bool = false
## Print the current pass.
@export var print_passes:bool = false
## Print in Output all the generated code.
## Can be usefull for debugging.
@export var print_generated_code:bool = false
## Do not execute compute shader at launch.
@export var pause:bool = false
## Number of passes (synchronized code) needed.
@export var nb_passes		: int = 1
## Workspace Size X, usually it matches the x size of your Sprite2D image
@export var WSX				: int = 128
## Workspace Size Y, usually it matches the y size of your Sprite2D image
@export var WSY				: int = 128

@export var cell_states : Array[StringColor]= [StringColor.new()]

## Write your initialisation code here (in GLSL)
@export_multiline var init_code : String = """
// INITIALISATION CODE (step = 0)
// You will use the following variables:
//    uint x,y,p (cell position)
//    int present_state (cell state. An integer random value from int.MIN and int.MAX)
//    int future_state (the new cell state)
"""

## Write your execution code here (in GLSL)
@export_multiline var exec_code : String = """
// EXECUTION CODE (step >= 1)
// You will use the following variables:
//    uint x,y,p (cell position)
//    int present_state (current cell state. Do not modify)
//    int future_state (the new cell state)
"""

## Write your own functions here (in GLSL)
@export_multiline var functions_code : String = """
// FUNCTIONS CODE
"""

## Drag and drop your Sprite2D here.
@export var matrix:Sprite2D
@export var matrix_future:Sprite2D

var rd 				: RenderingDevice
var shader 			: RID
var buffers 		: Array[RID]
var buffer_params 	: RID

var uniforms		: Array[RDUniform]
#var uniform_2 		: RDUniform
var uniform_params 	: RDUniform

var bindings		: Array = []

var pipeline		: RID
var uniform_set		: RID

# Called when the node enters the scene tree for the first time.
#region _ready
#func _enter_tree():
#	cell_states = [StringColor.new(),StringColor.new()]
func _ready():
		compile()

func compile():
	# Create a local rendering device.
	rd = RenderingServer.create_local_rendering_device()
	if not rd:
		set_process(false)
		print("Compute shaders are not available")
		return
		
	# *********************
	# *  SHADER CREATION  *
	# *********************

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

	GLSL_header += """
uint nb_neigbhors_8(uint x,uint y, int state) {
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

	GLSL_header += functions_code

	var states_code : String = ""


	var GLSL_code : String = """
// Write your cell states HERE
int state_0 = 0xFF0000FF; // Red
int state_1 = 0xFF00FFFF; // Green

void main() {
	uint x = gl_GlobalInvocationID.x;
	uint y = gl_GlobalInvocationID.y;
	uint p = x + y * WSX;

	if(current_pass == 0) {
		int present_state = data_present[p];
		// Write your RULES below vvvvvvvvvvvvvvvvv
		int future_state = present_state;
		if(step == 0) { // Initialization ---------
		
		
		
			int threshold = 2147483647 - 10000000;
			if(present_state <= threshold)
				future_state = state_0;
			else
				future_state = state_1;
				
				
				
				
		} else { // Execution----------------------
		
		
		
		
			// STATE_0 behaviors
			if (present_state == state_0) {
				// Propagation
				if (nb_neigbhors_8(x,y,state_1) >= 1) {
					future_state = state_1;
				}
			}
			if (present_state == state_1) {
				future_state = state_1;
			}
			
			
			
			
			
			
			
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
	var shader_src := RDShaderSource.new()
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
	if is_instance_valid(matrix):
		display_values(matrix, output_bytes)
	var output_bytes_future :   PackedByteArray = rd.buffer_get_data(buffers[1])
	if is_instance_valid(matrix_future):
		display_values(matrix_future, output_bytes)

func display_values(sprite : Sprite2D, values : PackedByteArray): # PackedInt32Array):
	var image_format : int = Image.FORMAT_RGBA8
	var image := Image.create_from_data(WSX, WSY, false, image_format, values)
	sprite.set_texture(ImageTexture.create_from_image(image))

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

#endregion

func _on_button_step():
	pause = true
	compute() # current_pass = 0
	compute() # current_pass = 1
	display_all_values()


func _on_button_play():
	pause = false # Replace with function body.
