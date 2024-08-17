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

vec2 :: distinct [2]f64
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

// WORLD

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
Hittable :: union {Sphere}


hit_many :: proc(hittables : ^[dynamic]Hittable, ray : Ray, hit_rec : ^Hit, t_interval : Interval) -> bool {
    temp_hit : Hit
    hit_anything : bool
    closest_so_far := t_interval.upper

    hit_count : int
    for hittable, i in hittables {
        hit_next : bool
        switch h in hittable {
        case Sphere:
       	    hit_next = hit_sphere(h, ray, &temp_hit, { lower = t_interval.lower, upper = closest_so_far })
        }


        if hit_next {
            hit_anything = true
            hit_count += 1
            closest_so_far = temp_hit.t
            hit_rec^ = temp_hit
        }
    }

    return hit_anything
}

hit_sphere :: proc(sphere : Sphere, ray : Ray, hit_rec : ^Hit, t_interval : Interval) -> ( bool) {
    oc := sphere.center - ray.origin
    a := linalg.dot(ray.direction, ray.direction)
    c := linalg.dot(oc, oc) - sphere.radius * sphere.radius
    b := linalg.dot(ray.direction, oc)
    discriminant := b * b - a * c

    if discriminant < 0 {
        return false
    } else {
        sqrtd := math.sqrt(discriminant)

        // Find the nearest root that lies in the acceptable range.
        root := (b - sqrtd) / a
        // if root <= t_interval.lower || t_interval.upper <= root {
        if !interval_surrounds(t_interval, root) {
            root = (b + sqrtd) / a
            if !interval_surrounds(t_interval, root) {
                return false
            }
        }

        hit_rec.t = root
        hit_rec.point= ray_at(ray, hit_rec.t)
        outward_normal :=  (hit_rec.point - sphere.center) / sphere.radius
        hit_rec.is_front_face = linalg.dot(ray.direction, outward_normal) < 0
        hit_rec.normal = hit_rec.is_front_face ? outward_normal : -outward_normal

        return true
    }
}

// CAMERA

Camera :: struct {
    // Set manually
    aspect_ratio : f64,    // Ratio of image width over height
    image_width : uint,    // Rendered image width in pixel count
    center : vec3,         // Camera center
    focal_length : f64,
    viewport_height : f64,

    // Calculated
    image_height : uint,   // Rendered image height
    pixel_delta_u : vec3,  // Offset to pixel to the right
    pixel_delta_v : vec3,  // Offset to pixel below
    pixel00_loc : vec3,    // Location of pixel 0, 0
}

camera_create :: proc() -> Camera {
    aspect_ratio := 1.0
    image_width : uint = 100
    image_height := uint(f64(image_width) / aspect_ratio)
    center : vec3 = {0, 0, 0}

    // Determine viewport dimensions.
    focal_length := 1.0
    viewport_height := 2.0
    viewport_width := viewport_height * (f64(image_width) / f64(image_height))

    // Calculate the vectors across the horizontal and down the vertical viewport edges.
    viewport_u : vec3 = {viewport_width, 0, 0}
    viewport_v : vec3 = {0, -viewport_height, 0}

    // Calculate the horizontal and vertical delta vectors from pixel to pixel.
    pixel_delta_u := viewport_u / f64(image_width)
    pixel_delta_v := viewport_v / f64(image_height)
    viewport_upper_left := center - {0, 0, focal_length} - viewport_u / 2 - viewport_v / 2

    return Camera {
        aspect_ratio = aspect_ratio,
        image_width = image_width,
        image_height = image_height,
        center = center,

        focal_length = focal_length,
        viewport_height = viewport_height,

        pixel_delta_u = pixel_delta_u,
        pixel_delta_v = pixel_delta_v,

        // Calculate the location of the upper left pixel.
        pixel00_loc = viewport_upper_left + 0.5 * (pixel_delta_u + pixel_delta_v),
    }
}

camera_reinitialize :: proc(cam: ^Camera) {
    image_height := uint(f64(cam.image_width) / cam.aspect_ratio)
    viewport_width := cam.viewport_height * (f64(cam.image_width) / f64(image_height))

    viewport_u : vec3 = {viewport_width, 0, 0}
    viewport_v : vec3 = {0, -cam.viewport_height, 0}

    pixel_delta_u := viewport_u / f64(cam.image_width)
    pixel_delta_v := viewport_v / f64(image_height)
    viewport_upper_left := cam.center - {0, 0, cam.focal_length} - viewport_u / 2 - viewport_v / 2


    cam.pixel_delta_u = pixel_delta_u
    cam.pixel_delta_v = pixel_delta_v
    cam.image_height = image_height
    cam.pixel00_loc = viewport_upper_left + 0.5 * (pixel_delta_u + pixel_delta_v)
}

camera_render :: proc(camera: Camera, hittables : ^[dynamic]Hittable, renderer: ^SDL.Renderer) {
    height := c.int(camera.image_height)
    width := c.int(camera.image_width)

    for y : c.int = 0; y < height; y += 1 {
        // log.debug("Scan lines remaining: ", height - y)
        for x : c.int = 0; x < width; x += 1 {
            carl := f64(x) * camera.pixel_delta_u + f64(y) * camera.pixel_delta_v
            pixel_center := camera.pixel00_loc + {carl.x, carl.y, 0}
            ray_direction := pixel_center - camera.center
            r := Ray {origin = camera.center, direction = ray_direction}

            pixel_color := ray_color(r, hittables)

            SDL.SetRenderDrawColor(renderer, pixel_color.r, pixel_color.g, pixel_color.b, pixel_color.a)
            SDL.RenderDrawPoint(renderer, x, y)
        }
    }
}

ray_color :: proc(ray : Ray, hittables: ^[dynamic]Hittable) -> Color {
    hit_rec : Hit

    if (hit_many(hittables, ray, &hit_rec, { lower = 0, upper = math.INF_F64 })) {
        return vec3_to_color(0.5 * (hit_rec.normal + 1))
    }

    unit_direction : vec3 = linalg.normalize(ray.direction)
    a := 0.5 * (unit_direction.y + 1.0)
    white : vec3 = { 1, 1, 1 }
    blue : vec3 = { 0.5, 0.7, 1 }
    col := (1.0 - a) * white + a * blue
    return vec3_to_color(col)
}

// MAIN

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

    camera := camera_create()
    camera.aspect_ratio = ASPECT_RATIO
    camera.image_width = WINDOW_WIDTH
    camera_reinitialize(&camera)


    world : [dynamic]Hittable = {
        Sphere{ center = { 0, 0, -1 }, radius = 0.5 },
        Sphere{ center = { 0, -100.5, -1 }, radius = 100 },
    }
    defer delete(world)

    window : ^SDL.Window
    windowSurface : ^SDL.Surface
    imageSurface : ^SDL.Surface
    image_rw : ^SDL.RWops
    is_running := true

    if SDL.Init({SDL.InitFlag.VIDEO, SDL.InitFlag.EVENTS}) < 0 {
        // log.error("SDL failed to initialize. SDL Error:", SDL.GetError())
        log.debug("SDL failed to initialize. SDL Error:", SDL.GetError())
    } else {
        window = SDL.CreateWindow("SDL Tutorial", SDL.WINDOWPOS_UNDEFINED, SDL.WINDOWPOS_UNDEFINED, i32(camera.image_width), i32(camera.image_height), {SDL.WindowFlag.SHOWN})

        if window == nil {
            // log.error("SDL failed to create window. SDL Error:", SDL.GetError())
            log.debug("SDL failed to create window. SDL Error:", SDL.GetError())
        } else {
            renderer := SDL.CreateRenderer(window, -1, {SDL.RendererFlag.SOFTWARE})
            defer SDL.DestroyRenderer(renderer)
            SDL.SetRenderDrawColor(renderer, 0, 0, 0, 0)
            SDL.RenderClear(renderer)

            event : ^SDL.Event

            camera_render(camera, &world, renderer)

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


Interval :: struct {
    lower: f64,
    upper: f64,
}

INTERVAL_EMPTY :: Interval { lower = math.INF_F64, upper = -math.INF_F64 }
INTERVAL_UNIVERSE :: Interval { lower = -math.INF_F64, upper = math.INF_F64 }

interval_size :: proc(interval: Interval) -> f64 {
    return interval.upper - interval.lower
}

interval_contains :: proc(interval : Interval, x: f64) -> bool {
    return interval.lower <= x && x <= interval.upper
}

interval_surrounds :: proc(interval : Interval, x: f64) -> bool {
    return interval.lower < x && x < interval.upper
}
