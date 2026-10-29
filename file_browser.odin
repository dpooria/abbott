package abbott

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import rl "vendor:raylib"

browser_open, browser_folder, path_edit: bool
browser_path: [4096]u8
browser_scroll: int
browser_entries: [dynamic]string
browser_directory: string

browse_directory :: proc(path: string) {
    absolute, err := filepath.abs(path, context.temp_allocator)
    if err != nil || !os.is_dir(absolute) {status = "Choose an existing folder"; return}
    delete(browser_directory)
    browser_directory = strings.clone(absolute)
    browser_path = {}
    copy(browser_path[:len(browser_path) - 1], absolute)
    for entry in browser_entries {delete(entry)}
    clear(&browser_entries)
    entries, read_err := os.read_all_directory_by_path(absolute, context.allocator)
    if read_err != nil {status = "Could not read folder"; return}
    defer os.file_info_slice_delete(entries, context.allocator)
    for entry in entries {
        if entry.type == .Directory ||
           (!browser_folder &&
                   audio_file(entry.name)) {append(&browser_entries, strings.clone(entry.name))}
    }
    slice.sort(browser_entries[:])
    browser_scroll = 0
}

open_browser :: proc(folder: bool) {
    browser_folder = folder
    browser_open = true
    path_edit = false
    path := browser_directory
    if path == "" {path, _ = os.user_home_dir(context.temp_allocator)}
    browse_directory(path)
}

draw_browser :: proc(width, height: f32) {
    box := rl.Rectangle{60, 65, width - 120, height - 130}
    panel(box, "Add folder" if browser_folder else "Add file")
    if rl.GuiTextBox(
        {box.x + 16, box.y + 42, box.width - 132, 32},
        cast(cstring)&browser_path[0],
        len(browser_path),
        path_edit,
    ) {path_edit = !path_edit}
    if icon_button(box.x + box.width - 106, box.y + 42, "\uf12d", "Clear path") {browser_path = {}; path_edit = true}
    if icon_button(box.x + box.width - 56, box.y + 42, "\uf061", "Open path") ||
       (path_edit && rl.IsKeyPressed(.ENTER)) {
        path := buffer_text(browser_path[:])
        if !browser_folder &&
           os.is_file(
               path,
           ) {import_book(&lib, path); browser_open = false} else {browse_directory(path)}
        path_edit = false
    }
    if icon_button(box.x + 16, box.y + 86, "\uf062", "Parent folder") {browse_directory(filepath.dir(browser_directory))}
    label(
        {box.x + 110, box.y + 86, box.width - 126, 32},
        "Open a folder to browse; click an audio file to add it.",
    )
    list := rl.Rectangle{box.x + 16, box.y + 132, box.width - 32, box.height - 200}
    last := scroll_rows(list, len(browser_entries), &browser_scroll)
    for i in browser_scroll ..< last {
        name := browser_entries[i]
        path, _ := filepath.join({browser_directory, name}, context.temp_allocator)
        directory := os.is_dir(path)
        if button(
            list.x,
            list.y + f32((i - browser_scroll) * 38),
            list.width,
            fmt.tprintf("%s%s", "\uf07b " if directory else "\uf15b ", name),
        ) {
            if directory {browse_directory(path); break} else {import_book(&lib, path); browser_open = false}
        }
    }
    y := box.y + box.height - 48
    if browser_folder && icon_button(box.x + 16, y, "\uf067", "Add this folder") {import_book(&lib, browser_directory); browser_open = false}
    if icon_button(box.x + box.width - 56, y, "\uf00d", "Cancel") || rl.IsKeyPressed(.ESCAPE) {browser_open = false}
}
