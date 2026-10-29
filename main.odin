package abbott

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"
import rl "vendor:raylib"

lib := Library {
    selected = -1,
    speed    = 1,
    volume   = 100,
}

p: rawptr
active := -1
pending: bool
paused := true
chapters: [dynamic]Chapter
seek_target: f64 = -1
seek_position: f64 = -1
seek_after: i64
sleep_at: i64
saved_at: i64

clock_start := time.tick_now()

monotonic_time :: proc() -> i64 {
    return i64(time.tick_since(clock_start)) / 1000
}

load_book :: proc(autoplay := true) {
    book := &lib.books[active]
    if book.track < 0 || book.track >= len(book.files) {book.track = 0; book.position = 0}
    pending = true
    seek_target = -1
    seek_position = -1
    for ch in chapters {delete(ch.title)}; clear(&chapters)
    status = "Opening audiobook…"
    paused = !autoplay
    mpv_set_property_string(p, "pause", "yes" if paused else "no")
    if !command(p, "loadfile", book.files[book.track]) {status = "Could not open audiobook"}
    set_number(p, "speed", lib.speed)
}

queue_seek :: proc(target: f64, delay: i64 = 0) {
    if active < 0 || pending {return}
    seek_target = clamp(target, 0, max(0, lib.books[active].duration - 0.05))
    seek_after = monotonic_time() + delay
}

playback_position :: proc() -> f64 {
    if seek_target >= 0 {return seek_target}
    if seek_position >= 0 {return seek_position}
    return lib.books[active].position
}

apply_volume :: proc() {
    set_number(p, "volume", lib.volume)
    mpv_set_property_string(p, "mute", "yes" if lib.muted else "no")
}

on_control :: proc(action: int) {
    if active < 0 || pending {return}
    book := &lib.books[active]
    switch action {
    case 1:
        if flag(p, "eof-reached") {
            queue_seek(0)
            paused = true
        }
        paused = !paused
        mpv_set_property_string(p, "pause", "yes" if paused else "no")
    case 2:
        queue_seek(playback_position() - 30)
    case 3:
        queue_seek(playback_position() + 30)
    case 4:
        if book.track > 0 {book.track -= 1; book.position = 0; load_book()}
    case 5:
        if book.track + 1 < len(book.files) {book.track += 1; book.position = 0; load_book()}
    case 6:
        lib.speed += 0.25
        if lib.speed > 2 {lib.speed = 0.75}
        set_number(p, "speed", lib.speed)
    case 7:
        sleep_at = 0 if sleep_at > 0 else monotonic_time() + 1800 * 1000000
    case 8:
        added := toggle_bookmark(book, playback_position())
        status = "Bookmark saved" if added else "Bookmark removed"
        save(&lib)
    case 9:
        bookmarks_open = true
        bookmark_scroll = 0
    case 10, 11:
        index, _, _ := chapter_bounds(chapters[:], playback_position(), book.duration)
        index = clamp(index + (-1 if action == 10 else 1), 0, len(chapters) - 1)
        if index >= 0 {queue_seek(chapters[index].start)}
    case 12:
        lib.muted = !lib.muted
        apply_volume()
        save(&lib)
    }
}

jump_to_bookmark :: proc(mark: Bookmark) {
    book := &lib.books[active]
    if mark.track == book.track {queue_seek(mark.position)}
    else {book.track = mark.track; book.position = mark.position; load_book(!paused)}
}

tick :: proc() {
    if folder_process.pid != 0 {
        _, err := os.process_wait(folder_process, timeout = 0)
        if err != .Timeout {folder_process = {}}
    }
    for {
        event := mpv_wait_event(p, 0)
        if event.id == 0 {break}
        if event.id == 8 && active >= 0 {
            book := &lib.books[active]
            seek_to(p, book.position, number(p, "duration"))
            pending = false
            count := int(number(p, "chapters"))
            for i in 0 ..< count {
                title := property_text(p, fmt.tprintf("chapter-list/%d/title", i))
                if title == "" {title = fmt.aprintf("Chapter %d", i + 1)}
                append(
                    &chapters,
                    Chapter{title, number(p, fmt.tprintf("chapter-list/%d/time", i))},
                )
            }
            if count == 0 {append(&chapters, Chapter{strings.clone("Entire file"), 0})}
            status = "Progress saves automatically"
        }
        if event.id == 21 && seek_position >= 0 && active >= 0 {
            lib.books[active].position = number(p, "time-pos")
            seek_position = -1
        }
        if event.id == 5 && event.userdata == 1 && event.error < 0 {
            seek_position = -1
            status = "Could not seek"
        }
        if event.id == 7 && event.data != nil {
            end := cast(^[2]i32)event.data
            if end[0] == 4 {
                status = "Playback failed. Check that the file is available."
                pending = true
            }
        }
    }
    now := monotonic_time()
    if seek_target >= 0 && seek_position < 0 && now >= seek_after && !pending {
        if seek_to(
            p,
            seek_target,
            lib.books[active].duration,
        ) {seek_position = seek_target} else {status = "Could not seek"}
        seek_target = -1
    }
    if sleep_at > 0 && now >= sleep_at {
        mpv_set_property_string(p, "pause", "yes"); sleep_at = 0
    }
    if active >= 0 && !pending {
        book := &lib.books[active]
        duration := number(p, "duration")
        seeking := flag(p, "seeking")
        if duration >
           0 {book.duration = duration; if !seeking && seek_position < 0 {book.position = number(p, "time-pos")}}
        pause_flag, eof: i32
        mpv_get_property(p, "pause", 3, &pause_flag)
        mpv_get_property(p, "eof-reached", 3, &eof)
        paused = pause_flag != 0 || eof != 0
        if seeking ||
           seek_position >= 0 ||
           seek_target >=
               0 {status = "Seeking…"} else if flag(p, "paused-for-cache") {status = "Buffering…"} else if eof != 0 {status = "Finished"} else if paused {status = "Paused"} else {status = "Playing"}
        if eof != 0 &&
           seek_target < 0 &&
           seek_position < 0 &&
           book.track + 1 < len(book.files) {book.track += 1; book.position = 0; load_book()}
    }
    if now - saved_at >= 5 * 1000000 {save(&lib); saved_at = now}
}

main :: proc() {
    folder: string
    when ODIN_OS == .Windows {
        executable_dir, err := os.get_executable_directory(context.temp_allocator)
        if err != nil {fmt.eprintln("Could not find the executable directory"); return}
        folder, _ = filepath.join({executable_dir, "data"}, context.temp_allocator)
    } else {
        config, _ := os.user_config_dir(context.temp_allocator)
        folder, _ = filepath.join({config, "abbott"}, context.temp_allocator)
    }
    if !os.exists(folder) {
        if os.mkdir_all(folder) != nil {
            fmt.eprintln("Could not create the library directory")
            return
        }
    }
    state_path, _ = filepath.join({folder, "library.json"}, context.allocator)
    if data, err := os.read_entire_file(state_path, context.allocator); err == nil {
        defer delete(data)
        if json.unmarshal(data, &lib) !=
           nil {fmt.eprintln("Could not read library; keeping existing file."); return}
    }
    if lib.speed <= 0 {lib.speed = 1}
    lib.volume = clamp(lib.volume, 0, 100)
    for arg in os.args[1:] {import_book(&lib, arg)}
    p = mpv_create()
    if p == nil {fmt.eprintln("Could not create mpv"); return}
    defer mpv_terminate_destroy(p)
    mpv_set_option_string(p, "vo", "null")
    mpv_set_option_string(p, "video", "no")
    mpv_set_option_string(p, "idle", "yes")
    mpv_set_option_string(p, "keep-open", "yes")
    if mpv_initialize(p) < 0 {fmt.eprintln("Could not initialize mpv"); return}
    apply_volume()
    rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
    rl.InitWindow(1000, 680, "abbott")
    if !rl.IsWindowReady() {fmt.eprintln("Could not open the player window"); return}
    defer rl.CloseWindow()
    rl.SetWindowMinSize(900, 620)
    rl.SetExitKey(.KEY_NULL)
    rl.SetTargetFPS(30)
    font_data :: #load("assets/AbbottMono.ttf")
    codepoints: [dynamic]rune
    for codepoint in rune(32) ..< rune(0x530) {append(&codepoints, codepoint)}
    for codepoint in rune(0x2000) ..< rune(0x2070) {append(&codepoints, codepoint)}
    for codepoint in ([?]rune {
            0xf00d,
            0xf017,
            0xf026,
            0xf028,
            0xf02e,
            0xf03a,
            0xf048,
            0xf049,
            0xf04b,
            0xf04c,
            0xf050,
            0xf051,
            0xf061,
            0xf062,
            0xf067,
            0xf07b,
            0xf07c,
            0xf097,
            0xf0a8,
            0xf0e4,
            0xf104,
            0xf105,
            0xf12d,
            0xf15b,
            0xf185,
            0xf186,
            0xf1f8,
        }) {append(&codepoints, codepoint)}
    ui_font = rl.LoadFontFromMemory(
        ".ttf",
        raw_data(font_data),
        i32(len(font_data)),
        32,
        raw_data(codepoints),
        i32(len(codepoints)),
    )
    delete(codepoints)
    defer rl.UnloadFont(ui_font)
    rl.SetTextureFilter(ui_font.texture, .BILINEAR)
    rl.GuiLoadStyleDefault()
    rl.GuiSetFont(ui_font)
    apply_theme()
    image_data :: #load("assets/judy.png")
    image := rl.LoadImageFromMemory(".png", raw_data(image_data), i32(len(image_data)))
    rl.SetWindowIcon(image)
    judy := rl.LoadTextureFromImage(image)
    rl.UnloadImage(image)
    defer rl.UnloadTexture(judy)
    quote := judy_quotes[rl.GetRandomValue(0, i32(len(judy_quotes)) - 1)]
    if lib.selected >= 0 && lib.selected < len(lib.books) {
        active = lib.selected
        load_book(false)
    }
    for !rl.WindowShouldClose() {
        tick()
        if rl.IsFileDropped() {
            files := rl.LoadDroppedFiles()
            for i in 0 ..< files.count {import_book(&lib, string(files.paths[i]))}
            rl.UnloadDroppedFiles(files)
        }
        rl.BeginDrawing()
        rl.ClearBackground(theme.background)
        draw_interface(judy, quote)
        rl.EndDrawing()
        free_all(context.temp_allocator)
    }
    save(&lib)
}

