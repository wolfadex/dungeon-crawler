package main

import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import SDL "vendor:sdl2"
import SDL_Image "vendor:sdl2/image"
import gl "vendor:OpenGL"
import glm "core:math/linalg/glsl"
import "core:time"

state := struct {
    // resources
    // texture_patterns: rl.Texture,
    // texture_font:     rl.Font,
}{}

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

    window : ^SDL.Window
    windowSurface : ^SDL.Surface
    imageSurface : ^SDL.Surface
    image_rw : ^SDL.RWops
    is_running := true

    if SDL.Init({SDL.InitFlag.VIDEO, SDL.InitFlag.EVENTS}) < 0 {
        // log.error("SDL failed to initialize. SDL Error:", SDL.GetError())
        log.debug("SDL failed to initialize. SDL Error:", SDL.GetError())
    } else {
        window = SDL.CreateWindow("SDL Tutorial", SDL.WINDOWPOS_UNDEFINED, SDL.WINDOWPOS_UNDEFINED, 1024, 768, {SDL.WindowFlag.SHOWN})

        if window == nil {
            // log.error("SDL failed to create window. SDL Error:", SDL.GetError())
            log.debug("SDL failed to create window. SDL Error:", SDL.GetError())
        } else {
            windowSurface = SDL.GetWindowSurface(window)
            image_rw = SDL.RWFromFile("resources/patternPack_tilesheet@2.png", "r")
            imageSurface = SDL_Image.LoadPNG_RW(image_rw)

            if imageSurface == nil {
                log.debug("SDL failed to load a png. SDL Error:", SDL.GetError())
                is_running = false
            }

            event : ^SDL.Event

            for is_running {
                for event: SDL.Event; SDL.PollEvent(&event); {
                    #partial switch event.type {
                    case SDL.EventType.QUIT:
                        is_running = false
                    case SDL.EventType.KEYDOWN:
                        #partial switch event.key.keysym.sym {
                        case SDL.Keycode.Q:
                            is_running = false
                        }
                    }
                }

                src_rect := SDL.Rect { x = 1_536, y = 512, w = 512, h = 512 }
                dest_rect := SDL.Rect { x = 0, y = 0, w = 512, h = 512 }

                SDL.BlitSurface(
                    imageSurface,
                    &src_rect,
                    windowSurface,
                    &dest_rect,
                )
                SDL.Delay(10)
                SDL.UpdateWindowSurface(window)
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
