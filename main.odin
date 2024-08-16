package main

import "core:fmt"
import "core:log"
import "core:mem"
import "core:math"
import "core:math/linalg"
import "core:os"
import SDL "vendor:sdl2"
import SDL_Image "vendor:sdl2/image"
import "core:time"
import "core:c"

state := struct {
    // resources
    // texture_patterns: rl.Texture,
    // texture_font:     rl.Font,
}{}

vec3 :: distinct [3]f64
vec4 :: distinct [4]f64
Color :: distinct [4]u8

Ray :: struct {
    origin: vec3,
    direction: vec3,
}

// WHITE :: Color { 255, 255, 255, 255 }
// BLUE :: Color { 127, 178.2, 255, 255 }
RED :: Color { 255, 0, 0, 255 }

hit_sphere :: proc(center: vec3, radius: f64, ray : Ray) -> bool {
    oc := center - ray.origin
    a := linalg.dot(ray.direction, ray.direction)
    b := -2.0 * linalg.dot(ray.direction, oc)
    c := linalg.dot(oc, oc) - radius * radius
    discriminant := b * b - 4 * a * c
    return discriminant >= 0
}

ray_color :: proc(ray : Ray) -> Color {
    if hit_sphere({ 0, 0, -1 }, 0.5, ray) {
        return RED
    }

    unit_direction : vec3 = linalg.normalize(ray.direction)
    a := 0.5 * (unit_direction.y + 1.0)
    white : vec3 = { 255, 255, 255 }
    blue : vec3 = { 127, 178.2, 255 }
    col := (1.0 - a) * white + a * blue
    return { u8(col.r), u8(col.g), u8(col.b), 255}
}

main :: proc() {
    when ODIN_DEBUG {
        // setup debug logging
        logger := log.create_console_logger()
        context.logger = logger

        // setup tracking allocator for making sure all memory is cleaned up
        default_allocator := context.allocator
        tracking_allocator: mem.Tracking_Allocator
        mem.tracking_allocator_init(&tracking_allocator, default_allocator)
        context.allocator = mem.tracking_allocator(&tracking_allocator)

        reset_tracking_allocator :: proc(a: ^mem.Tracking_Allocator) -> bool {
            err := false

            for _, value in a.allocation_map {
                fmt.printfln("%v: Leaked %v bytes", value.location, value.size)
                err = true
            }

            mem.tracking_allocator_clear(a)

            return err
        }

        defer reset_tracking_allocator(&tracking_allocator)
    }

    ASPECT_RATIO :: 16.0 / 9.0;
    WINDOW_WIDTH :: 640
    WINDOW_HEIGHT :: WINDOW_WIDTH / ASPECT_RATIO

    VIEWPORT_HEIGHT :: 2.0
    VIEWPORT_WIDTH :: VIEWPORT_HEIGHT * (WINDOW_WIDTH / WINDOW_HEIGHT)


    // Camera
    focal_length := 1.0
    viewport_height := 2.0
    viewport_width := viewport_height * (f64(WINDOW_WIDTH) / WINDOW_HEIGHT)
    camera_center : vec3 = {0, 0, 0}

    // Calculate the vectors across the horizontal and down the vertical viewport edges.
    viewport_u : vec3 = {viewport_width, 0, 0}
    viewport_v : vec3 = {0, -viewport_height, 0}

    // Calculate the horizontal and vertical delta vectors from pixel to pixel.
    pixel_delta_u := viewport_u / WINDOW_WIDTH
    pixel_delta_v := viewport_v / WINDOW_HEIGHT

    // Calculate the location of the upper left pixel.
    viewport_upper_left := camera_center - vec3({0, 0, focal_length}) - viewport_u / 2 - viewport_v / 2
    pixel00_loc := viewport_upper_left + 0.5 * (pixel_delta_u + pixel_delta_v)




    window : ^SDL.Window
    windowSurface : ^SDL.Surface
    imageSurface : ^SDL.Surface
    image_rw : ^SDL.RWops
    is_running := true

    if SDL.Init({SDL.InitFlag.VIDEO, SDL.InitFlag.EVENTS}) < 0 {
        // log.error("SDL failed to initialize. SDL Error:", SDL.GetError())
        log.debug("SDL failed to initialize. SDL Error:", SDL.GetError())
    } else {
        window = SDL.CreateWindow("SDL Tutorial", SDL.WINDOWPOS_UNDEFINED, SDL.WINDOWPOS_UNDEFINED, WINDOW_WIDTH, WINDOW_HEIGHT, {SDL.WindowFlag.SHOWN})

        if window == nil {
            // log.error("SDL failed to create window. SDL Error:", SDL.GetError())
            log.debug("SDL failed to create window. SDL Error:", SDL.GetError())
        } else {
            renderer := SDL.CreateRenderer(window, -1, {SDL.RendererFlag.SOFTWARE})
            defer SDL.DestroyRenderer(renderer)
            SDL.SetRenderDrawColor(renderer, 0, 0, 0, 0);
            SDL.RenderClear(renderer);

            event : ^SDL.Event

            SDL.SetRenderDrawColor(renderer, 255, 0, 0, 255);

            for column : c.int = 0; column < WINDOW_WIDTH; column += 1 {
                SDL.RenderDrawPoint(renderer, column, column)
            }
            for y : c.int = 0; y < WINDOW_HEIGHT; y += 1 {
                // log.debug("Scan lines remaining: ", WINDOW_HEIGHT - y)
                for x : c.int = 0; x < WINDOW_WIDTH; x += 1 {
                    pixel_center := pixel00_loc + (f64(x) * pixel_delta_u) + (f64(y) * pixel_delta_v)
                    ray_direction := pixel_center - camera_center
                    r := Ray {origin = camera_center, direction = ray_direction}

                    pixel_color := ray_color(r);

                    SDL.SetRenderDrawColor(renderer, pixel_color.r, pixel_color.g, pixel_color.b, pixel_color.a)
                    SDL.RenderDrawPoint(renderer, x, y)
                }
            }

            SDL.RenderPresent(renderer);

            game_loop: for {
                for event: SDL.Event; SDL.PollEvent(&event); {
                    #partial switch event.type {
                    case SDL.EventType.QUIT:
                        break game_loop
                    case SDL.EventType.KEYDOWN:
                        #partial switch event.key.keysym.sym {
                        case SDL.Keycode.Q:
                            break game_loop
                        }
                    }
                }
            }
        }
    }

    SDL.FreeSurface(imageSurface)
    SDL.FreeRW(image_rw)
    SDL.DestroyWindow(window)
    SDL.Quit()


    // if window == nil {
 //        log.error("SDL failed to create window. SDL Error:", SDL.GetError())
 //        os.exit(1)
    // }

    // screenSurface := SDL.GetWindowSurface(window)
    // defer SDL.FreeSurface(screenSurface)

    // {
 //        // SDL_FillRect( screenSurface, NULL, SDL_MapRGB( screenSurface->format, 0xFF, 0xFF, 0xFF ) );
 //        rect := SDL.Rect{ w = 1024, h = 768}
    //     SDL.FillRect(screenSurface, &rect, SDL.MapRGB(screenSurface.format, 255, 255, 255))

 //        // Update the surface
 //        // SDL_UpdateWindowSurface( window );
 //        SDL.UpdateWindowSurface(window)

 //        // Hack to get window to stay up
 //        // SDL_Event e; bool quit = false; while( quit == false ){ while( SDL_PollEvent( &e ) ){ if( e.type == SDL_QUIT ) quit = true; } }
 //        event : ^SDL.Event
 //        quit : bool

 //        for !quit {
 //            for SDL.PollEvent(event) {
 //                #partial switch event.type {
 //                case SDL.EventType.QUIT:
 //                    quit = true
 //                }
 //            }
 //        }
    // }


    // state.texture_font = rl.LoadFontEx("resources/Bismillah Script.ttf", 32, {}, 62)
    // defer rl.UnloadFont(state.texture_font)

    // state.texture_patterns = rl.LoadTexture("resources/patternPack_tilesheet@2.png")
    // defer rl.UnloadTexture(state.texture_patterns)

}
