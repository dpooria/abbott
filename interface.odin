package abbott

import "core:fmt"
import "core:path/filepath"
import "core:strings"
import rl "vendor:raylib"

library_scroll, chapter_scroll: int
chapter_search: [256]u8
search_edit: bool
chapters_open: bool
button_hint: string

label :: proc(bounds: rl.Rectangle, text: string) {
    rl.BeginScissorMode(i32(bounds.x), i32(bounds.y), i32(bounds.width), i32(bounds.height))
    rl.GuiLabel(bounds, cstr(text))
    rl.EndScissorMode()
}

button :: proc(x, y, width: f32, text: string, hint: string = "") -> bool {
    bounds := rl.Rectangle{x, y, width, 32}
    clicked := rl.GuiButton(bounds, cstr(text))
    bevel(bounds)
    if hint != "" && rl.GuiGetState() != i32(rl.GuiState.STATE_DISABLED) && rl.CheckCollisionPointRec(rl.GetMousePosition(), bounds) {button_hint = hint}
    return clicked
}

icon_button :: proc(x, y: f32, symbol, hint: string) -> bool {
    return button(x, y, 40, symbol, hint)
}

show_button_hint :: proc() {
    if button_hint == "" {return}
    mouse := rl.GetMousePosition()
    width := rl.MeasureTextEx(ui_font, cstr(button_hint), 16, 0).x + 20
    x := clamp(mouse.x + 12, 8, f32(rl.GetScreenWidth()) - width - 8)
    y := min(mouse.y + 24, f32(rl.GetScreenHeight()) - 40)
    rl.DrawRectangleRec({x, y, width, 30}, theme.panel)
    rl.DrawRectangleLinesEx({x, y, width, 30}, 1, theme.border)
    rl.DrawTextEx(ui_font, cstr(button_hint), {x + 10, y + 7}, 16, 0, theme.text)
}

buffer_text :: proc(buffer: []u8) -> string {
    for value, i in buffer {if value == 0 {return string(buffer[:i])}}
    return string(buffer)
}

scroll_rows :: proc(bounds: rl.Rectangle, count: int, scroll: ^int, row_height: int = 38) -> int {
    visible := max(1, int(bounds.height) / row_height)
    if rl.CheckCollisionPointRec(rl.GetMousePosition(), bounds) {
        scroll^ -= int(rl.GetMouseWheelMove() * 3)
    }
    scroll^ = clamp(scroll^, 0, max(0, count - visible))
    return min(count, scroll^ + visible)
}

draw_interface :: proc(judy: rl.Texture2D, quote: string) {
    button_hint = ""
    width, height := f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())
    modal := browser_open || chapters_open || menu_book >= 0
    rl.DrawRectangle(0, 0, i32(width), 64, theme.panel)
    rl.DrawRectangle(0, 64, 250, i32(height) - 108, theme.panel)
    rl.DrawRectangle(0, i32(height) - 44, i32(width), 44, theme.panel)
    rl.DrawLine(0, 63, i32(width), 63, theme.border)
    rl.DrawLine(0, i32(height) - 44, i32(width), i32(height) - 44, theme.border)
    if modal {rl.GuiDisable()}
    if icon_button(16, 16, "\uf15b", "Add audio file") {open_browser(false)}
    if icon_button(66, 16, "\uf07c", "Add audio folder") {open_browser(true)}
    label({270, 16, width - 460, 32}, "abbott / audiobook player")
    if icon_button(width - 56, 16, "\uf185" if !lib.light else "\uf186", "Switch to light / Lotus" if !lib.light else "Switch to dark / Dragon") {
        lib.light = !lib.light
        apply_theme()
        save(&lib)
    }
    rl.DrawLine(250, 64, 250, i32(height) - 44, theme.border)
    label({16, 70, 220, 30}, "Library")
    list := rl.Rectangle{16, 108, 218, height - 340}
    last := scroll_rows(list, len(lib.books), &library_scroll, 62)
    for i in library_scroll ..< last {
        book := &lib.books[i]
        row := rl.Rectangle{list.x, list.y + f32((i - library_scroll) * 62), list.width, 58}
        if rl.GuiButton(row, "") {
            save(&lib)
            active = i
            lib.selected = i
            load_book(false)
        }
        if i == active {
            rl.DrawRectangleRec(row, theme.accent)
            rl.GuiSetStyle(
                .LABEL,
                i32(rl.GuiControlProperty.TEXT_COLOR_NORMAL),
                transmute(i32)rl.ColorToInt(theme.background),
            )
            rl.GuiSetStyle(
                .LABEL,
                i32(rl.GuiControlProperty.TEXT_COLOR_DISABLED),
                transmute(i32)rl.ColorToInt(theme.background),
            )
        } else {bevel(row)}
        label({row.x + 8, row.y + 3, row.width - 16, 26}, book.title)
        label(
            {row.x + 8, row.y + 29, row.width - 16, 24},
            fmt.tprintf("%d/%d  %s", book.track + 1, len(book.files), clock_text(book.position)),
        )
        rl.GuiSetStyle(
            .LABEL,
            i32(rl.GuiControlProperty.TEXT_COLOR_NORMAL),
            transmute(i32)rl.ColorToInt(theme.text),
        )
        rl.GuiSetStyle(
            .LABEL,
            i32(rl.GuiControlProperty.TEXT_COLOR_DISABLED),
            transmute(i32)rl.ColorToInt(theme.muted),
        )
        if !modal &&
           rl.IsMouseButtonPressed(.RIGHT) &&
           rl.CheckCollisionPointRec(rl.GetMousePosition(), row) {menu_book = i}
    }
    rl.DrawTextureEx(judy, {12, height - 215}, 0, 0.85, rl.WHITE)
    label({16, height - 88, 220, 28}, "Drop files or folders here")
    label({16, height - 38, width - 32, 28}, status)
    x, content_width := f32(278), width - 310
    if active < 0 {
        rl.GuiSetStyle(
            .DEFAULT,
            i32(rl.GuiDefaultProperty.TEXT_WRAP_MODE),
            i32(rl.GuiTextWrapMode.TEXT_WRAP_WORD),
        )
        label({x, 110, content_width, 190}, quote)
        rl.GuiSetStyle(
            .DEFAULT,
            i32(rl.GuiDefaultProperty.TEXT_WRAP_MODE),
            i32(rl.GuiTextWrapMode.TEXT_WRAP_NONE),
        )
        label({x, 310, content_width, 32}, "Add an audiobook or choose one from your library.")
    } else {
        book := &lib.books[active]
        label({x, 90, content_width, 40}, book.title)
        label(
            {x, 140, content_width, 30},
            fmt.tprintf(
                "File %d of %d / %s",
                book.track + 1,
                len(book.files),
                filepath.base(book.files[book.track]),
            ),
        )
        if pending {rl.GuiDisable()}
        position := playback_position()
        index, start, end := chapter_bounds(chapters[:], position, book.duration)
        if icon_button(x, 200, "\uf104", "Previous chapter") {on_control(10)}
        chapter_title := chapters[index].title if index < len(chapters) else "Opening chapters..."
        if button(
            x + 50,
            200,
            content_width - 100,
            chapter_title,
            "Search and choose a chapter",
        ) {chapters_open = true; chapter_scroll = 0}
        if icon_button(x + content_width - 40, 200, "\uf105", "Next chapter") {on_control(11)}
        value := f32(position - start)
        previous := value
        rl.GuiSliderBar({x, 262, content_width, 24}, nil, nil, &value, 0, f32(max(1, end - start)))
        if value != previous {queue_seek(start + f64(value), 150000)}
        label(
            {x, 298, content_width, 30},
            fmt.tprintf("%s / %s", clock_text(position - start), clock_text(end - start)),
        )
        actions := [5]int{4, 2, 1, 3, 5}
        symbols := [5]string{"\uf048", "\uf049", "\uf04b" if paused else "\uf04c", "\uf050", "\uf051"}
        hints := [5]string{"Previous file", "Back 30 seconds", "Play (Space)" if paused else "Pause (Space)", "Forward 30 seconds", "Next file"}
        controls_x := x + (content_width - 240) / 2
        for symbol, i in symbols {
            if icon_button(controls_x + f32(i) * 50, 350, symbol, hints[i]) {on_control(actions[i])}
        }
        options_x := x + (content_width - 250) / 2
        if button(options_x, 408, 100, fmt.tprintf("\uf0e4 %.2fx", lib.speed), "Change playback speed") {on_control(6)}
        if icon_button(options_x + 110, 408, "\uf00d" if sleep_at > 0 else "\uf017", "Cancel sleep timer" if sleep_at > 0 else "Sleep in 30 minutes") {on_control(7)}
        if icon_button(options_x + 160, 408, "\uf02e", "Save bookmark") {on_control(8)}
        if icon_button(options_x + 210, 408, "\uf0a8", "Resume last bookmark") {on_control(9)}
        label(
            {x, 472, content_width, 30},
            fmt.tprintf(
                "File progress: %s / %s",
                clock_text(book.position),
                clock_text(book.duration),
            ),
        )
        if sleep_at >
           0 {label({x, 512, content_width, 30}, fmt.tprintf("Sleep in %s", clock_text(f64(sleep_at - monotonic_time()) / 1000000)))}
        if !modal && !pending && rl.IsKeyPressed(.SPACE) {on_control(1)}
    }
    rl.GuiEnable()
    if modal {
        if browser_open {draw_browser(width, height)} else if chapters_open {draw_chapters(width, height)} else if menu_book >= 0 {draw_book_menu(width, height)}
    }
    show_button_hint()
}

draw_chapters :: proc(width, height: f32) {
    box := rl.Rectangle{270, 100, width - 300, height - 165}
    panel(box, "Chapters / search")
    if rl.GuiTextBox(
        {box.x + 16, box.y + 42, box.width - 32, 32},
        cast(cstring)&chapter_search[0],
        len(chapter_search),
        search_edit,
    ) {search_edit = !search_edit}
    query := strings.to_lower(buffer_text(chapter_search[:]), context.temp_allocator)
    matches: [dynamic]int
    defer delete(matches)
    for chapter, i in chapters {
        if strings.contains(
            strings.to_lower(chapter.title, context.temp_allocator),
            query,
        ) {append(&matches, i)}
    }
    list := rl.Rectangle{box.x + 16, box.y + 90, box.width - 32, box.height - 150}
    last := scroll_rows(list, len(matches), &chapter_scroll)
    for row in chapter_scroll ..< last {
        i := matches[row]
        if button(
            list.x,
            list.y + f32((row - chapter_scroll) * 38),
            list.width,
            fmt.tprintf("%d. %s", i + 1, chapters[i].title),
        ) {
            queue_seek(chapters[i].start)
            chapters_open = false
            search_edit = false
        }
    }
    if icon_button(box.x + 16, box.y + box.height - 44, "\uf00d", "Close chapters") ||
       rl.IsKeyPressed(.ESCAPE) {chapters_open = false; search_edit = false}
}

