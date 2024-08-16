package main

import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import SDL "vendor:sdl2"
// import SDL_Image "vendor:sdl2/image"
// import gl "vendor:OpenGL"
// import glm "core:math/linalg/glsl"
import "core:time"

import NS "core:sys/darwin/Foundation"
import Metal "vendor:darwin/Metal"
import CA "vendor:darwin/QuartzCore"


// state := struct {
//     // resources
//     // texture_patterns: rl.Texture,
//     // texture_font:     rl.Font,
// }{}

// main :: proc() {
//     when ODIN_DEBUG {
//         // setup debug logging
//         logger := log.create_console_logger()
//         context.logger = logger

//         // setup tracking allocator for making sure all memory is cleaned up
//         default_allocator := context.allocator
//         tracking_allocator: mem.Tracking_Allocator
//         mem.tracking_allocator_init(&tracking_allocator, default_allocator)
//         context.allocator = mem.tracking_allocator(&tracking_allocator)

//         reset_tracking_allocator :: proc(a: ^mem.Tracking_Allocator) -> bool {
//             err := false

//             for _, value in a.allocation_map {
//                 fmt.printfln("%v: Leaked %v bytes", value.location, value.size)
//                 err = true
//             }

//             mem.tracking_allocator_clear(a)

//             return err
//         }

//         defer reset_tracking_allocator(&tracking_allocator)
//     }

//     WINDOW_WIDTH  :: 854
// 	WINDOW_HEIGHT :: 480

//     window : ^SDL.Window
//     windowSurface : ^SDL.Surface
//     imageSurface : ^SDL.Surface
//     image_rw : ^SDL.RWops
//     is_running := true

//     if SDL.Init({SDL.InitFlag.VIDEO, SDL.InitFlag.EVENTS}) < 0 {
//         // log.error("SDL failed to initialize. SDL Error:", SDL.GetError())
//         log.debug("SDL failed to initialize. SDL Error:", SDL.GetError())
//     } else {
//         defer SDL.Quit()
//         window = SDL.CreateWindow("SDL Tutorial", SDL.WINDOWPOS_UNDEFINED, SDL.WINDOWPOS_UNDEFINED, WINDOW_WIDTH, WINDOW_HEIGHT, {SDL.WindowFlag.SHOWN})
//         defer SDL.DestroyWindow(window)

//         if window == nil {
//             // log.error("SDL failed to create window. SDL Error:", SDL.GetError())
//             log.debug("SDL failed to create window. SDL Error:", SDL.GetError())
//         } else {
//             gl_context := SDL.GL_CreateContext(window)
//             SDL.GL_MakeCurrent(window, gl_context)
//             // load the OpenGL procedures once an OpenGL context has been established
//             gl.load_up_to(3, 3, SDL.gl_set_proc_address)

//             // useful utility procedures that are part of vendor:OpenGl
//             program, program_ok := gl.load_shaders_source(vertex_source, fragment_source)
//             if !program_ok {
//                fmt.eprintln("Failed to create GLSL program")
//                return
//             }
//             defer gl.DeleteProgram(program)

//             gl.UseProgram(program)

//             uniforms := gl.get_uniforms_from_program(program)
//             defer delete(uniforms)

//             vao: u32
//             gl.GenVertexArrays(1, &vao); defer gl.DeleteVertexArrays(1, &vao)

//             // initialization of OpenGL buffers
//             vbo, ebo: u32
//             gl.GenBuffers(1, &vbo); defer gl.DeleteBuffers(1, &vbo)
//             gl.GenBuffers(1, &ebo); defer gl.DeleteBuffers(1, &ebo)

//             // struct declaration
//             Vertex :: struct {
//                pos: glm.vec3,
//                col: glm.vec4,
//             }

//             vertices := []Vertex{
//                {{-0.5, +0.5, 0}, {1.0, 0.0, 0.0, 0.75}},
//                {{-0.5, -0.5, 0}, {1.0, 1.0, 0.0, 0.75}},
//                {{+0.5, -0.5, 0}, {0.0, 1.0, 0.0, 0.75}},
//                {{+0.5, +0.5, 0}, {0.0, 0.0, 1.0, 0.75}},
//             }

//             indices := []u16{
//                0, 1, 2,
//                2, 3, 0,
//             }

//             gl.BindBuffer(gl.ARRAY_BUFFER, vbo)
//             gl.BufferData(gl.ARRAY_BUFFER, len(vertices)*size_of(vertices[0]), raw_data(vertices), gl.STATIC_DRAW)
//             gl.EnableVertexAttribArray(0)
//             gl.EnableVertexAttribArray(1)
//             gl.VertexAttribPointer(0, 3, gl.FLOAT, false, size_of(Vertex), offset_of(Vertex, pos))
//             gl.VertexAttribPointer(1, 4, gl.FLOAT, false, size_of(Vertex), offset_of(Vertex, col))

//             gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, ebo)
//             gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, len(indices)*size_of(indices[0]), raw_data(indices), gl.STATIC_DRAW)

//             // high precision timer
//             start_tick := time.tick_now()

//             //
//             // windowSurface = SDL.GetWindowSurface(window)
//             // defer SDL.FreeSurface(windowSurface)
//             // image_rw = SDL.RWFromFile("resources/patternPack_tilesheet@2.png", "r")
//             // defer SDL.FreeRW(image_rw)
//             // imageSurface = SDL_Image.LoadPNG_RW(image_rw)
//             // defer SDL.FreeSurface(imageSurface)

//             // if imageSurface == nil {
//             //     log.debug("SDL failed to load a png. SDL Error:", SDL.GetError())
//             //     is_running = false
//             // }

//             event : ^SDL.Event

//             game_loop: for {
//                 duration := time.tick_since(start_tick)
//                 t := f32(time.duration_seconds(duration))

//                 for event: SDL.Event; SDL.PollEvent(&event); {
//                     #partial switch event.type {
//                     case SDL.EventType.QUIT:
//                         break game_loop
//                     case SDL.EventType.KEYDOWN:
//                         #partial switch event.key.keysym.sym {
//                         case SDL.Keycode.Q:
//                             break game_loop
//                         }
//                     }
//                 }

//                 // Native support for GLSL-like functionality
//                 pos := glm.vec3{
//                    glm.cos(t*2),
//                    glm.sin(t*2),
//                    0,
//                 }

//                 // array programming support
//                 pos *= 0.3

//                 // matrix support
//                 // model matrix which a default scale of 0.5
//                 model := glm.mat4{
//                    0.5,   0,   0, 0,
//                    0, 0.5,   0, 0,
//                    0,   0, 0.5, 0,
//                    0,   0,   0, 1,
//                 }

//                 // matrix indexing and array short with `.x`
//                 model[0, 3] = -pos.x
//                 model[1, 3] = -pos.y
//                 model[2, 3] = -pos.z

//                 // native swizzling support for arrays
//                 model[3].yzx = pos.yzx

//                 model = model * glm.mat4Rotate({0, 1, 1}, t)

//                 view := glm.mat4LookAt({0, -1, +1}, {0, 0, 0}, {0, 0, 1})
//                 proj := glm.mat4Perspective(45, 1.3, 0.1, 100.0)

//                 // matrix multiplication
//                 u_transform := proj * view * model

//                 // matrix types in Odin are stored in column-major format but written as you'd normal write them
//                 gl.UniformMatrix4fv(uniforms["u_transform"].location, 1, false, &u_transform[0, 0])

//                 gl.Viewport(0, 0, WINDOW_WIDTH, WINDOW_HEIGHT)
//                 gl.ClearColor(0.5, 0.7, 1.0, 1.0)
//                 gl.Clear(gl.COLOR_BUFFER_BIT)

//                 gl.DrawElements(gl.TRIANGLES, i32(len(indices)), gl.UNSIGNED_SHORT, nil)

//                 SDL.GL_SwapWindow(window)

//                 // src_rect := SDL.Rect { x = 1_536, y = 512, w = 512, h = 512 }
//                 // dest_rect := SDL.Rect { x = 0, y = 0, w = 512, h = 512 }

//                 // SDL.BlitSurface(
//                 //     imageSurface,
//                 //     &src_rect,
//                 //     windowSurface,
//                 //     &dest_rect,
//                 // )
//                 // SDL.Delay(10)
//                 // SDL.UpdateWindowSurface(window)
//             }
//         }
//     }

//     // if window == nil {
//  //        log.error("SDL failed to create window. SDL Error:", SDL.GetError())
//  //        os.exit(1)
//     // }

//     // screenSurface := SDL.GetWindowSurface(window)
//     // defer SDL.FreeSurface(screenSurface)

//     // {
//  //        // SDL_FillRect( screenSurface, NULL, SDL_MapRGB( screenSurface->format, 0xFF, 0xFF, 0xFF ) );
//  //        rect := SDL.Rect{ w = 1024, h = 768}
//     //     SDL.FillRect(screenSurface, &rect, SDL.MapRGB(screenSurface.format, 255, 255, 255))

//  //        // Update the surface
//  //        // SDL_UpdateWindowSurface( window );
//  //        SDL.UpdateWindowSurface(window)

//  //        // Hack to get window to stay up
//  //        // SDL_Event e; bool quit = false; while( quit == false ){ while( SDL_PollEvent( &e ) ){ if( e.type == SDL_QUIT ) quit = true; } }
//  //        event : ^SDL.Event
//  //        quit : bool

//  //        for !quit {
//  //            for SDL.PollEvent(event) {
//  //                #partial switch event.type {
//  //                case SDL.EventType.QUIT:
//  //                    quit = true
//  //                }
//  //            }
//  //        }
//     // }


//     // state.texture_font = rl.LoadFontEx("resources/Bismillah Script.ttf", 32, {}, 62)
//     // defer rl.UnloadFont(state.texture_font)

//     // state.texture_patterns = rl.LoadTexture("resources/patternPack_tilesheet@2.png")
//     // defer rl.UnloadTexture(state.texture_patterns)

// }


// vertex_source := `#version 330 core
// layout(location=0) in vec3 a_position;
// layout(location=1) in vec4 a_color;
// out vec4 v_color;
// uniform mat4 u_transform;
// void main() {
//     gl_Position = u_transform * vec4(a_position, 1.0);
//     v_color = a_color;
// }
// `

// fragment_source := `#version 330 core
// in vec4 v_color;
// out vec4 o_color;
// void main() {
//     o_color = v_color;
// }
// `
metal_main :: proc() -> (err: ^NS.Error) {
	SDL.SetHint(SDL.HINT_RENDER_DRIVER, "metal")
	SDL.setenv("METAL_DEVICE_WRAPPER_TYPE", "1", 0)
	SDL.Init({.VIDEO})
	defer SDL.Quit()

	window := SDL.CreateWindow(
		"Metal in Odin",
		SDL.WINDOWPOS_CENTERED,
		SDL.WINDOWPOS_CENTERED,
		854,
		480,
		{.ALLOW_HIGHDPI, .HIDDEN, .RESIZABLE},
	)
	defer SDL.DestroyWindow(window)

	window_system_info: SDL.SysWMinfo
	SDL.GetVersion(&window_system_info.version)
	SDL.GetWindowWMInfo(window, &window_system_info)
	assert(window_system_info.subsystem == .COCOA)

	native_window := (^NS.Window)(window_system_info.info.cocoa.window)

	device := Metal.CreateSystemDefaultDevice()

	fmt.println(device->name()->odinString())

	swapchain := CA.MetalLayer.layer()
	swapchain->setDevice(device)
	swapchain->setPixelFormat(.BGRA8Unorm_sRGB)
	swapchain->setFramebufferOnly(true)
	swapchain->setFrame(native_window->frame())

	native_window->contentView()->setLayer(swapchain)
	native_window->setOpaque(true)
	native_window->setBackgroundColor(nil)

	command_queue := device->newCommandQueue()

	compile_options := NS.new(Metal.CompileOptions)
	defer compile_options->release()


	program_source :: `
	using namespace metal;
	struct ColoredVertex {
		float4 position [[position]];
		float4 color;
	};
	vertex ColoredVertex vertex_main(constant float4 *position [[buffer(0)]],
	                                 constant float4 *color    [[buffer(1)]],
	                                 uint vid                  [[vertex_id]]) {
		ColoredVertex vert;
		vert.position = position[vid];
		vert.color    = color[vid];
		return vert;
	}
	fragment float4 fragment_main(ColoredVertex vert [[stage_in]]) {
		return vert.color;
	}
	`
	program_library := device->newLibraryWithSource(
		NS.AT(program_source),
		compile_options,
	) or_return

	vertex_program := program_library->newFunctionWithName(NS.AT("vertex_main"))
	fragment_program := program_library->newFunctionWithName(NS.AT("fragment_main"))
	assert(vertex_program != nil)
	assert(fragment_program != nil)


	pipeline_state_descriptor := NS.new(Metal.RenderPipelineDescriptor)
	pipeline_state_descriptor->colorAttachments()->object(0)->setPixelFormat(.BGRA8Unorm_sRGB)
	pipeline_state_descriptor->setVertexFunction(vertex_program)
	pipeline_state_descriptor->setFragmentFunction(fragment_program)

	pipeline_state := device->newRenderPipelineState(pipeline_state_descriptor) or_return

	positions := [?][4]f32{{0.0, 0.5, 0, 1}, {-0.5, -0.5, 0, 1}, {0.5, -0.5, 0, 1}}
	colors := [?][4]f32{{1, 0, 0, 1}, {0, 1, 0, 1}, {0, 0, 1, 1}}

	position_buffer := device->newBufferWithSlice(positions[:], {})
	color_buffer := device->newBufferWithSlice(colors[:], {})


	SDL.ShowWindow(window)
	game_loop: for {
		for e: SDL.Event; SDL.PollEvent(&e); {
			#partial switch e.type {
			case .QUIT:
				break game_loop
			case .KEYDOWN:
				if e.key.keysym.sym == .ESCAPE {
					break game_loop
				}
			}
		}

		NS.scoped_autoreleasepool()

		drawable := swapchain->nextDrawable()
		assert(drawable != nil)

		pass := Metal.RenderPassDescriptor.renderPassDescriptor()
		color_attachment := pass->colorAttachments()->object(0)
		assert(color_attachment != nil)
		color_attachment->setClearColor(Metal.ClearColor{0.25, 0.5, 1.0, 1.0})
		color_attachment->setLoadAction(.Clear)
		color_attachment->setStoreAction(.Store)
		color_attachment->setTexture(drawable->texture())


		command_buffer := command_queue->commandBuffer()
		render_encoder := command_buffer->renderCommandEncoderWithDescriptor(pass)

		render_encoder->setRenderPipelineState(pipeline_state)
		render_encoder->setVertexBuffer(position_buffer, 0, 0)
		render_encoder->setVertexBuffer(color_buffer, 0, 1)
		render_encoder->drawPrimitivesWithInstanceCount(.Triangle, 0, 3, 1)

		render_encoder->endEncoding()

		command_buffer->presentDrawable(drawable)
		command_buffer->commit()
	}

	return nil
}

main :: proc() {
	err := metal_main()
	if err != nil {
		fmt.eprintln(err->localizedDescription()->odinString())
		os.exit(1)
	}
}
