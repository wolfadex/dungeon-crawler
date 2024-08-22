package main

import "core:fmt"
import "core:log"
import "core:mem"
import "core:math"
import "core:math/linalg"
import "core:math/rand"
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
    material: ^Material,
}

Sphere :: struct {
    center: vec3,
    radius: f64,
    material: Material,
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
        carl : Material = sphere.material
        hit_rec.material = &carl

        return true
    }
}

// MATERIAL

Material_Lambertian :: struct {
    albedo: vec3,
}

Material_Metal :: struct {
    albedo: vec3,
    fuzz: f64,
}

Material_Dielectric :: struct {
    refraction_index: f64,
}

Material :: union {Material_Dielectric,Material_Lambertian, Material_Metal}

scatter_dielectric ::proc(ray_in: Ray, hit_rec: ^Hit, material: Material_Dielectric) -> (attenuation: vec3, scattered: Ray, ok: bool) {
    refraction_index := hit_rec.is_front_face ? (1.0 / material.refraction_index) : material.refraction_index

    unit_direction := linalg.normalize(ray_in.direction)
    // refracted := linalg.refract(unit_direction, hit_rec.normal, refraction_index)
    cos_theta := math.min(linalg.dot(-unit_direction, hit_rec.normal), 1.0)
    sin_theta := math.sqrt(1.0 - cos_theta * cos_theta)

    cannot_refract := refraction_index * sin_theta > 1.0
    direction : vec3

    if cannot_refract || reflectance(cos_theta, refraction_index) > rand.float64() {
        direction = linalg.reflect(unit_direction, hit_rec.normal)
    } else{
        direction = linalg.refract(unit_direction, hit_rec.normal, refraction_index)
    }

    attenuation = {1.0, 1.0, 1.0}
    scattered = { origin = hit_rec.point, direction = direction }
    ok = true

    return attenuation, scattered, ok
}

scatter_metal :: proc(ray_in: Ray, hit_rec: ^Hit, material: Material_Metal) -> (attenuation: vec3, scattered: Ray, ok: bool) {
    reflected := linalg.reflect(ray_in.direction, hit_rec.normal)
    reflected = linalg.normalize(reflected) + (material.fuzz * rand_unit_vec3())

    attenuation = material.albedo
    scattered = { origin = hit_rec.point, direction = reflected }
    ok = linalg.dot(scattered.direction, hit_rec.normal) > 0

    return attenuation, scattered, ok
}

scatter_lambertian :: proc(ray_in: Ray, hit_rec: ^Hit, material: Material_Lambertian) -> (attenuation: vec3, scattered: Ray, ok: bool) {
    scatter_direction := hit_rec.normal + rand_unit_vec3()

    // Catch degenerate scatter direction
    if vec3_near_zero(scatter_direction) {
        scatter_direction = hit_rec.normal
    }

    attenuation = material.albedo
    scattered = { origin = hit_rec.point, direction = scatter_direction }
    ok = true

    return attenuation, scattered, ok
}

// CAMERA

Camera :: struct {
    // Set manually
    aspect_ratio : f64,        // Ratio of image width over height
    image_width : uint,        // Rendered image width in pixel count
    center : vec3,             // Camera center / Point camera is looking from
    samples_per_pixel: uint,   // Count of random samples for each pixel
    vertical_fov: f64,         // Vertical view angle (field of view)
    look_at : vec3,            // Point camera is looking at
    up_direction : vec3,       // Camera-relative "up" direction
    defocus_angle : f64,       // Variation angle of rays through each pixel
    focus_dist : f64,          // Distance from camera lookfrom point to plane of perfect focus

    // Calculated
    image_height : uint,       // Rendered image height
    pixel_delta_u : vec3,      // Offset to pixel to the right
    pixel_delta_v : vec3,      // Offset to pixel below
    pixel00_loc : vec3,        // Location of pixel 0, 0
    pixel_samples_scale : f64, // Count of random samples for each pixel
    max_depth  : uint,         // Maximum number of ray bounces into scene
    defocus_disk_u : vec3,     // Defocus disk horizontal radius
    defocus_disk_v : vec3,     // Defocus disk vertical radius
}

camera_create :: proc() -> Camera {
    aspect_ratio := 1.0
    image_width : uint = 100
    image_height := uint(f64(image_width) / aspect_ratio)
    center : vec3 = {0, 0, 0}
    vertical_fov : f64 = 90

    look_at : vec3 = {0,0,-1}
    up_direction : vec3 = {0,1,0}
    defocus_angle : f64 = 0
    focus_dist : f64 = 10

    // Determine viewport dimensions.
    theta := math.to_radians(vertical_fov)
    h := math.tan(theta / 2)
    viewport_height := 2 * h * focus_dist
    viewport_width := viewport_height * (f64(image_width) / f64(image_height))

    // Calculate the u,v,w unit basis vectors for the camera coordinate frame.
    w : vec3 = linalg.normalize(center - look_at)
    u : vec3 = linalg.normalize(linalg.cross(up_direction, w))
    v : vec3 = linalg.cross(w, u)

    // Calculate the vectors across the horizontal and down the vertical viewport edges.
    viewport_u : vec3 = viewport_width * u    // Vector across viewport horizontal edge
    viewport_v : vec3 = viewport_height * -v  // Vector down viewport vertical edge

    // Calculate the horizontal and vertical delta vectors from pixel to pixel.
    pixel_delta_u := viewport_u / f64(image_width)
    pixel_delta_v := viewport_v / f64(image_height)
    viewport_upper_left := center - (focus_dist * w) - viewport_u / 2 - viewport_v / 2

    // Calculate the camera defocus disk basis vectors.
    defocus_radius := focus_dist * math.tan(math.to_radians(defocus_angle / 2))
    defocus_disk_u := u * defocus_radius
    defocus_disk_v := v * defocus_radius

    samples_per_pixel : uint = 10

    return Camera {
        aspect_ratio = aspect_ratio,
        image_width = image_width,
        image_height = image_height,

        center = center,
        look_at = look_at,
        up_direction = up_direction,

        defocus_angle = defocus_angle,
        focus_dist = focus_dist,

        pixel_delta_u = pixel_delta_u,
        pixel_delta_v = pixel_delta_v,

        // Calculate the location of the upper left pixel.
        pixel00_loc = viewport_upper_left + 0.5 * (pixel_delta_u + pixel_delta_v),

        samples_per_pixel = samples_per_pixel,
        pixel_samples_scale = 1.0 / f64(samples_per_pixel),
        max_depth = 10,
        vertical_fov = vertical_fov,

        defocus_disk_u = defocus_disk_u,
        defocus_disk_v = defocus_disk_v,
    }
}

camera_reinitialize :: proc(cam: ^Camera) {
    image_height := uint(f64(cam.image_width) / cam.aspect_ratio)
    // focal_length := linalg.length(cam.center - cam.look_at)
    theta := math.to_radians(cam.vertical_fov)
    h := math.tan(theta / 2)
    // viewport_height := 2 * h * focal_length
    viewport_height := 2 * h * cam.focus_dist
    viewport_width := viewport_height * (f64(cam.image_width) / f64(image_height))

    // Calculate the u,v,w unit basis vectors for the camera coordinate frame.
    w : vec3 = linalg.normalize(cam.center - cam.look_at)
    u : vec3 = linalg.normalize(linalg.cross(cam.up_direction, w))
    v : vec3 = linalg.cross(w, u)

    // Calculate the vectors across the horizontal and down the vertical viewport edges.
    viewport_u : vec3 = viewport_width * u    // Vector across viewport horizontal edge
    viewport_v : vec3 = viewport_height * -v  // Vector down viewport vertical edge
    // viewport_u : vec3 = {viewport_width, 0, 0}
    // viewport_v : vec3 = {0, -viewport_height, 0}

    pixel_delta_u := viewport_u / f64(cam.image_width)
    pixel_delta_v := viewport_v / f64(image_height)
    viewport_upper_left := cam.center - (cam.focus_dist * w) - viewport_u / 2 - viewport_v / 2

    // Calculate the camera defocus disk basis vectors.
    defocus_radius := cam.focus_dist * math.tan(math.to_radians(cam.defocus_angle / 2))
    defocus_disk_u := u * defocus_radius
    defocus_disk_v := v * defocus_radius


    cam.pixel_delta_u = pixel_delta_u
    cam.pixel_delta_v = pixel_delta_v
    cam.image_height = image_height
    cam.pixel00_loc = viewport_upper_left + 0.5 * (pixel_delta_u + pixel_delta_v)
    cam.pixel_samples_scale = 1.0 / f64(cam.samples_per_pixel)
    cam.defocus_disk_u = defocus_disk_u
    cam.defocus_disk_v = defocus_disk_v
}


camera_to_ray :: proc(camera: Camera, x: int, y: int) -> Ray {
    // Construct a camera ray originating from the origin and directed
    // at randomly sampled point around the pixel location x, y.

    offset := sample_square()
    pixel_sample := camera.pixel00_loc + ((f64(x) + offset.x) * camera.pixel_delta_u) + ((f64(y) + offset.y) * camera.pixel_delta_v)
    origin := (camera.defocus_angle <= 0) ? camera.center : defocus_disk_sample(camera)
    direction := pixel_sample - origin

    return { origin = origin, direction = direction }
}

defocus_disk_sample :: proc(camera: Camera) -> vec3 {
    p := rand_in_unit_disk()
    return camera.center + (p.x * camera.defocus_disk_u) + (p.y * camera.defocus_disk_v)
}

// Returns the vector to a random point in the [-.5,-.5]-[+.5,+.5] unit square.
sample_square :: proc() -> vec2 {
    return { rand.float64() - 0.5, rand.float64() - 0.5 }
}

camera_render :: proc(camera: Camera, hittables : ^[dynamic]Hittable, renderer: ^SDL.Renderer) {
    height := c.int(camera.image_height)
    width := c.int(camera.image_width)

    for y : c.int = 0; y < height; y += 1 {
        log.debug("Scan lines remaining: ", height - y)
        for x : c.int = 0; x < width; x += 1 {
            pixel_color : vec3 = {0, 0, 0}

            for sample : uint = 0; sample < camera.samples_per_pixel; sample += 1 {
                r := camera_to_ray(camera, int(x), int(y))
                pixel_color += ray_color(r, camera.max_depth, hittables)
            }

            pixel_color *= camera.pixel_samples_scale

            for col, i in pixel_color {
                pixel_color[i] = math.clamp(linear_to_gamma(col), 0.000, 0.999)

            }

            final_color := vec3_to_color(pixel_color)

            SDL.SetRenderDrawColor(renderer, final_color.r, final_color.g, final_color.b, final_color.a)
            SDL.RenderDrawPoint(renderer, x, y)
        }
    }
}

ray_color :: proc(ray : Ray, depth: uint, hittables: ^[dynamic]Hittable) -> vec3 {
    // If we've exceeded the ray bounce limit, no more light is gathered.
    if (depth <= 0) {
        return {0,0,0}
    }

    hit_rec : Hit

    if (hit_many(hittables, ray, &hit_rec, { lower = 0.001, upper = math.INF_F64 })) {
        attenuation : vec3
        scattered : Ray
        ok : bool

        switch material in hit_rec.material {
        case Material_Dielectric:
            attenuation, scattered, ok = scatter_dielectric(ray, &hit_rec, material)
        case Material_Lambertian:
            attenuation, scattered, ok = scatter_lambertian(ray, &hit_rec, material)
        case Material_Metal:
            attenuation, scattered, ok = scatter_metal(ray, &hit_rec, material)
        }

        if  ok {
            return attenuation * ray_color(scattered, depth - 1, hittables)
        }

        return {0,0,0}
    }

    unit_direction : vec3 = linalg.normalize(ray.direction)
    a := 0.5 * (unit_direction.y + 1.0)
    white : vec3 = { 1, 1, 1 }
    blue : vec3 = { 0.5, 0.7, 1 }
    col := (1.0 - a) * white + a * blue
    return (col)
}

linear_to_gamma :: proc(linear_component: f64) -> f64 {
    if (linear_component > 0) {
        return math.sqrt(linear_component)
    }

    return 0
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

    camera := camera_create()
    // camera.aspect_ratio = 16.0 / 9.0
    // camera.image_width = 400
    // camera.samples_per_pixel = 100
    // camera.max_depth = 50
    // camera.vertical_fov = 20
    // camera.center = {-2,2,1}
    // camera.look_at = {0,0,-1}
    // camera.up_direction = {0,1,0}

    // camera.defocus_angle = 10.0
    // camera.focus_dist    = 3.4
    //
    camera.aspect_ratio      = 16.0 / 9.0
    camera.image_width       = 1200
    // camera.image_width       = 100
    camera.samples_per_pixel = 500
    camera.max_depth         = 50

    camera.vertical_fov     = 20
    camera.center = {13,2,3}
    camera.look_at   = {0,0,0}
    camera.up_direction      = {0,1,0}

    camera.defocus_angle = 0.6
    camera.focus_dist    = 10.0
    camera_reinitialize(&camera)

    // material_ground : Material = Material_Lambertian{ albedo = {0.8, 0.8, 0.0} }
    // material_center : Material = Material_Lambertian{ albedo = {0.1, 0.2, 0.5} }
    // material_left   : Material = Material_Dielectric{ refraction_index = 1.50 }
    // material_bubble : Material = Material_Dielectric{ refraction_index = 1.00 / 1.50 }
    // material_right  : Material = Material_Metal{ albedo = {0.8, 0.6, 0.2}, fuzz = 1.0 }

    // R := math.cos_f64(math.PI / 4)
    // material_left  : Material = Material_Lambertian{ albedo = {0,0,1} }
    // material_right : Material = Material_Lambertian{ albedo = {1,0,0} }

    world : [dynamic]Hittable = {
        // Sphere{ center = {  0.0, -100.5, -1.0} , radius = 100.0, material = &material_ground },
        // Sphere{ center = {  0.0,    0.0, -1.2} , radius =   0.5, material = &material_center },
        // Sphere{ center = { -1.0,    0.0, -1.0} , radius =   0.5, material = &material_left },
        // Sphere{ center = {-1.0,     0.0, -1.0} , radius =   0.4, material = &material_bubble },
        // Sphere{ center = {  1.0,    0.0, -1.0} , radius =   0.5, material = &material_right },
        //
        // Sphere{ center = {-R, 0, -1}, radius = R, material = &material_left },
        // Sphere{ center = { R, 0, -1}, radius = R, material = &material_right },
    }
    defer delete(world)

    ground_material : Material = Material_Lambertian{ albedo = {0.5, 0.5, 0.5} }
    append(&world, Sphere{ center = {  0.0, -1000.0, 0.0} , radius = 1000.0, material = ground_material })

    for a := -11; a < 11; a += 1 {
        for b := -11; b < 11; b += 1 {
            center : vec3 = {f64(a) + 0.9 * rand.float64(), 0.2, f64(b) + 0.9 * rand.float64()}

            if (linalg.length(center - {4, 0.2, 0}) > 0.9) {
                choose_mat := rand.float64()

                if (choose_mat < 0.8) {
                    // diffuse
                    albedo := rand_vec3(0, 1) * rand_vec3(0, 1)
                    sphere_material : Material = Material_Lambertian{ albedo = albedo }
                    append(&world, Sphere{ center = center , radius = 0.2, material = sphere_material })
                } else if (choose_mat < 0.95) {
                    // metal
                    albedo := rand_vec3(0.5, 1)
                    fuzz := rand.float64_range(0, 0.5)
                    sphere_material : Material = Material_Metal{ albedo = albedo, fuzz = fuzz }
                    append(&world, Sphere{ center = center , radius = 0.2, material = sphere_material })
                } else {
                    // glass
                    sphere_material : Material = Material_Dielectric{ refraction_index = 1.50 }
                    append(&world, Sphere{ center = center , radius = 0.2, material = sphere_material })
                }
            }
        }
    }

    material1 : Material = Material_Dielectric{ refraction_index = 1.50 }
    append(&world, Sphere{ center = {  0.0, 1.0, 0.0} , radius = 1.0, material = material1 })

    material2 : Material = Material_Lambertian{ albedo = {0.4, 0.2, 0.1} }
    append(&world, Sphere{ center = {  -4.0, 1.0, 0.0} , radius = 1.0, material = material2 })

    material3 : Material = Material_Metal{ albedo = {0.7, 0.6, 0.5}, fuzz = 0.0 }
    append(&world, Sphere{ center = {  4.0, 1.0, 0.0} , radius = 1.0, material = material3 })

    window : ^SDL.Window
    windowSurface : ^SDL.Surface
    imageSurface : ^SDL.Surface
    image_rw : ^SDL.RWops
    is_running := true

    if SDL.Init({SDL.InitFlag.VIDEO, SDL.InitFlag.EVENTS}) < 0 {
        // log.error("SDL failed to initialize. SDL Error:", SDL.GetError())
        log.debug("SDL failed to initialize. SDL Error:", SDL.GetError())
    } else {
        window = SDL.CreateWindow("SDL Tutorial", SDL.WINDOWPOS_UNDEFINED, SDL.WINDOWPOS_UNDEFINED, i32(camera.image_width), i32(camera.image_height), {SDL.WindowFlag.SHOWN, SDL.WindowFlag.RESIZABLE})

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

rand_vec3 :: proc(min: f64, max: f64) -> vec3 {
    return { rand.float64_range(min,max), rand.float64_range(min,max), rand.float64_range(min,max) }
}

rand_unit_vec3 :: proc() -> vec3 {
    return linalg.normalize(rand_in_unit_sphere())
}

rand_in_unit_sphere :: proc() -> vec3 {
    for {
        p := rand_vec3(-1,1)
        if (linalg.dot(p, p) < 1) {
            return p
        }
    }
}

rand_on_hemisphere :: proc(normal: vec3) -> vec3{
    on_unit_sphere := rand_in_unit_sphere()
    if linalg.dot(on_unit_sphere, normal) > 0.0 { // In the same hemisphere as the normal
        return on_unit_sphere
    } else {
        return -on_unit_sphere
    }
}

rand_in_unit_disk :: proc() -> vec2 {
    for {
        p : vec2 = {rand.float64_range(-1,1), rand.float64_range(-1,1)}
        if linalg.dot(p, p) < 1 {
            return p
        }
    }
}

NEAR_ZERO_LIMIT :: 1e-8

vec3_near_zero :: proc(v: vec3) -> bool {
    return v.x < NEAR_ZERO_LIMIT && v.y < NEAR_ZERO_LIMIT && v.z < NEAR_ZERO_LIMIT
}

// Use Schlick's approximation for reflectance.
reflectance :: proc(cosine: f64, refraction_index: f64) -> f64 {
    r0 := (1 - refraction_index) / (1 + refraction_index)
    r0 = r0 * r0
    return r0 + (1 - r0) * math.pow((1 - cosine), 5)
}
