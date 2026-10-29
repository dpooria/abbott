package abbott

import "core:os"
import "core:path/filepath"
import rl "vendor:raylib"

menu_book := -1
folder_process: os.Process

show_folder :: proc(path: string) {
    args: []string
    when ODIN_OS == .Windows {args = []string{"explorer.exe", path}} else {args = []string{"xdg-open", path}}
    if folder_process.pid != 0 {return}
    process, err := os.process_start({command = args})
    if err != nil {status = "Could not open the folder"; return}
    folder_process = process
}

draw_book_menu :: proc(width, height: f32) {
    x, y := width / 2 - 160, height / 2 - 75
    panel({x, y, 320, 150}, "Library")
    if icon_button(x + 16, y + 48, "\uf07c", "Show in folder") {
        book := &lib.books[menu_book]
        show_folder(filepath.dir(book.files[book.track]))
        menu_book = -1
    }
    if icon_button(x + 66, y + 48, "\uf1f8", "Remove from library; keep audio files") {
        index := menu_book
        menu_book = -1
        if active == index {
            command(p, "stop")
            active = -1
            pending = false
            paused = true
            seek_target = -1
            seek_position = -1
            sleep_at = 0
            for ch in chapters {delete(ch.title)}
            clear(&chapters)
        } else if active > index {active -= 1}
        remove_book(&lib, index)
        status = "Removed from library. Audio files kept."
        save(&lib)
    }
    label({x + 16, y + 105, 288, 24}, "Audio files are kept.")
    if icon_button(x + 264, y + 48, "\uf00d", "Cancel") || rl.IsKeyPressed(.ESCAPE) {menu_book = -1}
}

