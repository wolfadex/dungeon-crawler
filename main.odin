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

WHITE :: Color { 255, 255, 255, 255 }
BLUE :: Color { 127, 178, 255, 255 }
RED :: Color { 255, 0, 0, 255 }

ray_at :: proc(ray : Ray, t : f64) -> vec3 {
    return ray.origin + t * ray.direction
}

vec3_to_color :: proc(v : vec3) -> Color {
    return { u8(v.x * 255), u8(v.y * 255), u8(v.z * 255), 255 }
}

ray_color :: proc(ray : Ray) -> Color {
    hit, is_hit := hit_sphere({ center = { 0, 0, -1 }, radius = 0.5 }, ray)

    if (is_hit) {
        n : vec3 = linalg.normalize(ray_at(ray, hit.t) - { 0,0,-1 }) + 1
        return vec3_to_color(0.5 * n)
    }

    unit_direction : vec3 = linalg.normalize(ray.direction)
    a := 0.5 * (unit_direction.y + 1.0)
    white : vec3 = { 1, 1, 1 }
    blue : vec3 = { 0.5, 0.7, 1 }
    col := (1.0 - a) * white + a * blue
    return vec3_to_color(col)
}

Hit :: struct {
    point : vec3,
    normal : vec3,
    t: f64,
    is_front_face: bool,
}

Sphere :: struct {
    center: vec3,
    radius: f64,
}

hit_sphere :: proc(sphere : Sphere, ray : Ray, t_max : f64 = 100, t_min : f64 = 0) -> (Hit, bool) {
    oc := sphere.center - ray.origin
    a := linalg.dot(ray.direction, ray.direction)
    c := linalg.dot(oc, oc) - sphere.radius * sphere.radius
    b := linalg.dot(ray.direction, oc)
    discriminant := b * b - a * c

    if discriminant < 0 {
        return Hit {}, false
    } else {
        sqrtd := math.sqrt(discriminant)

        // Find the nearest root that lies in the acceptable range.
        root := (b - sqrtd) / a
        if root <= t_min || t_max <= root {
            root = (b + sqrtd) / a
            if (root <= t_min || t_max <= root){
                return Hit {}, false
            }
        }

        hit_point := ray_at(ray, root)
        outward_normal :=  (hit_point - sphere.center) / sphere.radius
        is_front_face := linalg.dot(ray.direction, outward_normal) < 0
        normal := is_front_face ? outward_normal : -outward_normal

        return Hit { point = hit_point, normal = normal, t = root, is_front_face = is_front_face }, true
    }
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

    ASPECT_RATIO :: 16.0 / 9.0
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
            SDL.SetRenderDrawColor(renderer, 0, 0, 0, 0)
            SDL.RenderClear(renderer)

            event : ^SDL.Event

            SDL.SetRenderDrawColor(renderer, 255, 0, 0, 255)

            for column : c.int = 0; column < WINDOW_WIDTH; column += 1 {
                SDL.RenderDrawPoint(renderer, column, column)
            }
            for y : c.int = 0; y < WINDOW_HEIGHT; y += 1 {
                // log.debug("Scan lines remaining: ", WINDOW_HEIGHT - y)
                for x : c.int = 0; x < WINDOW_WIDTH; x += 1 {
                    pixel_center := pixel00_loc + (f64(x) * pixel_delta_u) + (f64(y) * pixel_delta_v)
                    ray_direction := pixel_center - camera_center
                    r := Ray {origin = camera_center, direction = ray_direction}

                    pixel_color := ray_color(r)

                    SDL.SetRenderDrawColor(renderer, pixel_color.r, pixel_color.g, pixel_color.b, pixel_color.a)
                    SDL.RenderDrawPoint(renderer, x, y)
                }
            }

            SDL.RenderPresent(renderer)

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
