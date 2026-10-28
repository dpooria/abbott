package abbott

import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "odin-gtk/glib"
import "odin-gtk/glib/gio"
import gobj "odin-gtk/glib/gobject"
import "odin-gtk/gtk"

app_context: runtime.Context
lib := Library {
    selected = -1,
    speed    = 1,
}
p: rawptr
active := -1
pending: bool
paused := true
chapters: [dynamic]Chapter
window: ^gtk.Window
library_list: ^gtk.ListBox
chapter_picker: ^gtk.DropDown
chapter_model: ^gtk.StringList
global_label: ^gtk.Label
seek_target: f64 = -1
seek_after: i64
title_label, file_label, time_label, status_label: ^gtk.Label
play_button, sleep_button, speed_button: ^gtk.Button
player_box: ^gtk.Widget
seek_bar: ^gtk.Range
updating: bool
sleep_at: i64
saved_at: i64

// Widget helpers
text_label :: proc(text: string) -> ^gtk.Widget {
    widget := gtk.label_new(cstr(text))
    gtk.label_set_xalign(gtk.LABEL(widget), 0)
    gtk.label_set_ellipsize(gtk.LABEL(widget), .ELLIPSIZE_END)
    return widget
}

margin :: proc(widget: ^gtk.Widget, amount: i32) {
    gtk.widget_set_margin_top(widget, amount)
    gtk.widget_set_margin_bottom(widget, amount)
    gtk.widget_set_margin_start(widget, amount)
    gtk.widget_set_margin_end(widget, amount)
}

add_button :: proc(box: ^gtk.Box, title: string, callback: $T, data: rawptr = nil) -> ^gtk.Button {
    widget := gtk.button_new_with_label(cstr(title))
    gtk.box_append(box, widget)
    gobj.signal_connect(widget, "clicked", callback, data)
    return gtk.BUTTON(widget)
}

icon_button :: proc(box: ^gtk.Box, icon, tooltip: string, action: int) -> ^gtk.Button {
    widget := gtk.button_new_from_icon_name(cstr(icon))
    gtk.widget_set_tooltip_text(widget, cstr(tooltip))
    gtk.box_append(box, widget)
    gobj.signal_connect(widget, "clicked", on_control, rawptr(uintptr(action)))
    return gtk.BUTTON(widget)
}

scroll_list :: proc(list: ^gtk.ListBox) -> ^gtk.Widget {
    scroll := gtk.scrolled_window_new()
    gtk.scrolled_window_set_policy(gtk.SCROLLED_WINDOW(scroll), .POLICY_NEVER, .POLICY_AUTOMATIC)
    gtk.scrolled_window_set_child(gtk.SCROLLED_WINDOW(scroll), gtk.WIDGET(list))
    gtk.widget_set_vexpand(scroll, true)
    return scroll
}

clear_list :: proc(list: ^gtk.ListBox) {
    for {
        child := gtk.WIDGET(gtk.list_box_get_row_at_index(list, 0))
        if child == nil {break}
        gtk.list_box_remove(list, child)
    }
}

refresh_library :: proc() {
    clear_list(library_list)
    for book in lib.books {
        row := gtk.box_new(.VERTICAL, 5)
        margin(row, 12)
        heading := text_label(book.title)
        gtk.widget_add_css_class(heading, "heading")
        gtk.box_append(gtk.BOX(row), heading)
        detail := text_label(
            fmt.tprintf(
                "File %d of %d · %s",
                book.track + 1,
                len(book.files),
                clock_text(book.position),
            ),
        )
        gtk.widget_add_css_class(detail, "dim-label")
        gtk.box_append(gtk.BOX(row), detail)
        gtk.list_box_append(library_list, row)
    }
    if active >=
       0 {gtk.list_box_select_row(library_list, gtk.list_box_get_row_at_index(library_list, i32(active)))}
}

// Playback controls
load_book :: proc(autoplay := true) {
    book := &lib.books[active]
    if book.track < 0 || book.track >= len(book.files) {book.track = 0; book.position = 0}
    pending = true
    seek_target = -1
    updating = true
    gtk.drop_down_set_model(chapter_picker, nil)
    updating = false
    for ch in chapters {delete(ch.title)}; clear(&chapters)
    gtk.label_set_text(title_label, cstr(book.title))
    gtk.label_set_text(
        file_label,
        cstr(
            fmt.tprintf(
                "File %d of %d · %s",
                book.track + 1,
                len(book.files),
                filepath.base(book.files[book.track]),
            ),
        ),
    )
    gtk.widget_set_sensitive(player_box, false)
    status = "Opening audiobook…"
    paused = !autoplay
    mpv_set_property_string(p, "pause", "yes" if paused else "no")
    if !command(p, "loadfile", book.files[book.track]) {status = "Could not open audiobook"}
    set_number(p, "speed", lib.speed)
}

on_book :: proc "c" (_: ^gtk.ListBox, row: ^gtk.ListBoxRow, _: rawptr) {
    context = app_context
    defer free_all(context.temp_allocator)
    save(&lib)
    active = int(gtk.list_box_row_get_index(row))
    lib.selected = active
    load_book(false)
}

queue_seek :: proc(target: f64, delay: i64 = 0) {
    if active < 0 || pending {return}
    seek_target = clamp(target, 0, max(0, lib.books[active].duration - 0.05))
    seek_after = glib.get_monotonic_time() + delay
}

on_chapter :: proc "c" (_: ^gobj.Object, _: ^gobj.ParamSpec, _: rawptr) {
    context = app_context
    defer free_all(context.temp_allocator)
    if updating || pending {return}
    i := int(gtk.drop_down_get_selected(chapter_picker))
    if i >= 0 && i < len(chapters) {queue_seek(chapters[i].start)}
}

on_seek :: proc "c" (range: ^gtk.Range, _: rawptr) {
    context = app_context
    defer free_all(context.temp_allocator)
    if !updating && !pending && active >= 0 {
        book := &lib.books[active]
        _, start, _ := chapter_bounds(chapters[:], book.position, book.duration)
        queue_seek(start + gtk.range_get_value(range), 150000)
    }
}

on_control :: proc "c" (_: ^gtk.Button, data: rawptr) {
    context = app_context
    defer free_all(context.temp_allocator)
    if active < 0 || pending {return}
    book := &lib.books[active]
    switch int(uintptr(data)) {
    case 1:
        if flag(p, "eof-reached") {queue_seek(0); paused = true}
        paused = !paused
        mpv_set_property_string(p, "pause", "yes" if paused else "no")
    case 2:
        queue_seek((seek_target if seek_target >= 0 else book.position) - 30)
    case 3:
        queue_seek((seek_target if seek_target >= 0 else book.position) + 30)
    case 4:
        if book.track > 0 {book.track -= 1; book.position = 0; load_book()}
    case 5:
        if book.track + 1 < len(book.files) {book.track += 1; book.position = 0; load_book()}
    case 6:
        lib.speed += 0.25
        if lib.speed > 2 {lib.speed = 0.75}
        set_number(p, "speed", lib.speed)
    case 7:
        sleep_at = 0 if sleep_at > 0 else glib.get_monotonic_time() + 1800 * 1000000
    case 8:
        append(&book.bookmarks, Bookmark{book.track, book.position}); status = "Bookmark saved"
        save(&lib)
    case 10, 11:
        index, _, _ := chapter_bounds(chapters[:], book.position, book.duration)
        index = clamp(index + (-1 if int(uintptr(data)) == 10 else 1), 0, len(chapters) - 1)
        if index >= 0 {queue_seek(chapters[index].start)}
    case 9:
        if len(book.bookmarks) > 0 {
            mark := book.bookmarks[len(book.bookmarks) - 1]
            book.track = mark.track; book.position = mark.position; load_book()
        }
    }
}

// Importing books
on_chooser_response :: proc "c" (dialog: ^gtk.NativeDialog, response: i32, _: rawptr) {
    context = app_context
    defer free_all(context.temp_allocator)
    if response == i32(gtk.ResponseType.RESPONSE_ACCEPT) {
        file := gtk.file_chooser_get_file(gtk.FILE_CHOOSER(dialog))
        if file != nil {
            path := gio.file_get_path(file)
            if path !=
               nil {import_book(&lib, string(path)); glib.free(rawptr(path)); refresh_library()}
            gobj.object_unref(file)
        }
    }
    gtk.native_dialog_destroy(dialog)
    gobj.object_unref(dialog)
}

on_add :: proc "c" (_: ^gtk.Button, data: rawptr) {
    context = app_context
    action := gtk.FileChooserAction.OPEN if data == nil else gtk.FileChooserAction.SELECT_FOLDER
    dialog := gtk.file_chooser_native_new("Add audiobook", window, action, "Add", "Cancel")
    gobj.signal_connect(dialog, "response", on_chooser_response)
    gtk.native_dialog_show(gtk.NATIVE_DIALOG(dialog))
}

on_drop :: proc "c" (
    _: ^gtk.DropTarget,
    value: ^gobj.Value,
    _: f64,
    _: f64,
    _: rawptr,
) -> glib.boolean {
    context = app_context
    defer free_all(context.temp_allocator)
    files := gtk.gdk_file_list_get_files(cast(^gtk.FileList)gobj.value_get_boxed(value))
    for node := files; node != nil; node = node.next {
        path := gio.file_get_path(cast(^gio.File)node.data)
        if path != nil {import_book(&lib, string(path)); glib.free(rawptr(path))}
    }
    refresh_library()
    return true
}

// Playback updates
tick :: proc "c" (_: rawptr) -> glib.boolean {
    context = app_context
    defer free_all(context.temp_allocator)
    for {
        event := mpv_wait_event(p, 0)
        if event.id == 0 {break}
        if event.id == 8 && active >= 0 {
            book := &lib.books[active]
            seek_to(p, book.position, number(p, "duration"))
            pending = false
            gtk.widget_set_sensitive(player_box, true)
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
            updating = true
            chapter_model = gtk.string_list_new(nil)
            for ch, i in chapters {
                gtk.string_list_append(chapter_model, cstr(fmt.tprintf("%d. %s", i + 1, ch.title)))
            }
            gtk.drop_down_set_model(chapter_picker, gio.LIST_MODEL(chapter_model))
            gobj.object_unref(chapter_model)
            updating = false
            status = "Progress saves automatically"
        }
        if event.id == 7 && event.data != nil {
            end := cast(^[2]i32)event.data
            if end[0] ==
               4 {status = "Playback failed. Check that the file is available."; pending = true}
        }
    }
    now := glib.get_monotonic_time()
    if seek_target >= 0 && now >= seek_after && !pending {
        if !seek_to(p, seek_target, lib.books[active].duration) {status = "Could not seek"}
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
           0 {book.duration = duration; if !seeking {book.position = number(p, "time-pos")}}
        pause_flag, eof: i32
        mpv_get_property(p, "pause", 3, &pause_flag)
        mpv_get_property(p, "eof-reached", 3, &eof)
        paused = pause_flag != 0 || eof != 0
        gtk.button_set_icon_name(
            play_button,
            "media-playback-start-symbolic" if paused else "media-playback-pause-symbolic",
        )
        gtk.widget_set_tooltip_text(gtk.WIDGET(play_button), "Play" if paused else "Pause")
        index, start, end := chapter_bounds(chapters[:], book.position, book.duration)
        if seek_target < 0 && !seeking {
            gtk.label_set_text(
                time_label,
                cstr(
                    fmt.tprintf(
                        "%s  /  %s",
                        clock_text(book.position - start),
                        clock_text(end - start),
                    ),
                ),
            )
            updating = true
            gtk.range_set_range(seek_bar, 0, max(1, end - start))
            gtk.range_set_value(seek_bar, book.position - start)
            if gtk.drop_down_get_selected(chapter_picker) != u32(index) {
                gtk.drop_down_set_selected(chapter_picker, u32(index))
            }
            updating = false
        }
        gtk.label_set_text(
            global_label,
            cstr(
                fmt.tprintf(
                    "File %d of %d · %s / %s",
                    book.track + 1,
                    len(book.files),
                    clock_text(book.position),
                    clock_text(book.duration),
                ),
            ),
        )
        if seeking ||
           seek_target >=
               0 {status = "Seeking…"} else if flag(p, "paused-for-cache") {status = "Buffering…"} else if eof != 0 {status = "Finished"} else if paused {status = "Paused"} else {status = "Playing"}
        if eof != 0 &&
           book.track + 1 < len(book.files) {book.track += 1; book.position = 0; load_book()}
    }
    gtk.button_set_label(speed_button, cstr(fmt.tprintf("%.2f×", lib.speed)))
    gtk.button_set_label(sleep_button, "Cancel sleep" if sleep_at > 0 else "Sleep 30m")
    gtk.label_set_text(status_label, cstr(status))
    if now - saved_at >= 5 * 1000000 {save(&lib); saved_at = now}
    return true
}

activate :: proc "c" (app: ^gtk.Application, _: rawptr) {
    context = app_context
    defer free_all(context.temp_allocator)
    if window != nil {
        gtk.window_present(window)
        return
    }

    window = gtk.WINDOW(gtk.application_window_new(app))
    register_judy_icon()
    gtk.window_set_icon_name(window, "io.abbott.Player")
    gtk.window_set_title(window, "abbott")
    gtk.window_set_default_size(window, 960, 560)

    // Header
    root := gtk.box_new(.VERTICAL, 0)
    gtk.window_set_child(window, root)
    header := gtk.header_bar_new()
    gtk.header_bar_set_title_widget(gtk.HEADER_BAR(header), gtk.label_new("abbott"))
    gtk.window_set_titlebar(window, header)
    add_box := gtk.box_new(.HORIZONTAL, 6)
    add_button(gtk.BOX(add_box), "Add file", on_add)
    add_button(gtk.BOX(add_box), "Add folder", on_add, rawptr(uintptr(1)))
    gtk.header_bar_pack_start(gtk.HEADER_BAR(header), add_box)

    // Library sidebar
    body := gtk.paned_new(.HORIZONTAL)
    gtk.widget_set_vexpand(body, true)
    gtk.box_append(gtk.BOX(root), body)
    sidebar := gtk.box_new(.VERTICAL, 12)
    margin(sidebar, 12)
    gtk.widget_set_size_request(sidebar, 230, -1)
    gtk.box_append(gtk.BOX(sidebar), text_label("Library"))
    library_list = gtk.LIST_BOX(gtk.list_box_new())
    gtk.list_box_set_activate_on_single_click(library_list, true)
    setup_book_menu()
    gtk.box_append(gtk.BOX(sidebar), scroll_list(library_list))
    gtk.box_append(gtk.BOX(sidebar), judy_picture())
    gtk.box_append(gtk.BOX(sidebar), text_label("Drop audio files or folders here"))
    gtk.paned_set_start_child(gtk.PANED(body), sidebar)
    gtk.paned_set_resize_start_child(gtk.PANED(body), false)
    gtk.paned_set_shrink_start_child(gtk.PANED(body), false)

    // Player
    content := gtk.box_new(.VERTICAL, 18)
    margin(content, 24)
    gtk.paned_set_end_child(gtk.PANED(body), content)
    title := text_label(judy_quotes[glib.random_int_range(0, i32(len(judy_quotes)))])
    title_label = gtk.LABEL(title)
    gtk.label_set_wrap(title_label, true)
    gtk.label_set_ellipsize(title_label, .ELLIPSIZE_NONE)
    gtk.label_set_max_width_chars(title_label, 40)
    gtk.widget_add_css_class(title, "title-1")
    gtk.box_append(gtk.BOX(content), title)
    file_label = gtk.LABEL(text_label("Pick a book"))
    gtk.widget_add_css_class(gtk.WIDGET(file_label), "dim-label")
    gtk.box_append(gtk.BOX(content), gtk.WIDGET(file_label))
    player_box = gtk.box_new(.VERTICAL, 12)
    gtk.box_append(gtk.BOX(content), player_box)
    gtk.widget_set_sensitive(player_box, false)

    // Chapters and progress
    chapter_row := gtk.box_new(.HORIZONTAL, 8)
    gtk.box_append(gtk.BOX(player_box), chapter_row)
    icon_button(gtk.BOX(chapter_row), "go-previous-symbolic", "Previous chapter", 10)
    chapter_picker = gtk.DROP_DOWN(gtk.drop_down_new(nil, nil))
    gtk.drop_down_set_enable_search(chapter_picker, true)
    gtk.widget_set_hexpand(gtk.WIDGET(chapter_picker), true)
    gtk.box_append(gtk.BOX(chapter_row), gtk.WIDGET(chapter_picker))
    icon_button(gtk.BOX(chapter_row), "go-next-symbolic", "Next chapter", 11)
    seek_bar = gtk.RANGE(gtk.scale_new_with_range(.HORIZONTAL, 0, 1, 1))
    gtk.scale_set_draw_value(gtk.SCALE(seek_bar), false)
    gtk.box_append(gtk.BOX(player_box), gtk.WIDGET(seek_bar))
    time_label = gtk.LABEL(gtk.label_new("00:00:00 / 00:00:00"))
    gtk.box_append(gtk.BOX(player_box), gtk.WIDGET(time_label))
    // Transport and options
    controls := gtk.box_new(.HORIZONTAL, 12)
    gtk.widget_set_halign(controls, .CENTER)
    gtk.box_append(gtk.BOX(player_box), controls)
    icon_button(gtk.BOX(controls), "media-skip-backward-symbolic", "Previous file", 4)
    add_button(gtk.BOX(controls), "−30s", on_control, rawptr(uintptr(2)))
    play_button = icon_button(gtk.BOX(controls), "media-playback-start-symbolic", "Play", 1)
    gtk.widget_add_css_class(gtk.WIDGET(play_button), "circular")
    add_button(gtk.BOX(controls), "+30s", on_control, rawptr(uintptr(3)))
    icon_button(gtk.BOX(controls), "media-skip-forward-symbolic", "Next file", 5)
    options := gtk.box_new(.HORIZONTAL, 8)
    gtk.widget_set_halign(options, .CENTER)
    gtk.box_append(gtk.BOX(player_box), options)
    speed_button = add_button(gtk.BOX(options), "1.00×", on_control, rawptr(uintptr(6)))
    sleep_button = add_button(gtk.BOX(options), "Sleep 30m", on_control, rawptr(uintptr(7)))
    icon_button(gtk.BOX(options), "bookmark-new-symbolic", "Save bookmark", 8)
    icon_button(gtk.BOX(options), "go-jump-symbolic", "Resume last bookmark", 9)
    details := gtk.expander_new("File progress")
    global_label = gtk.LABEL(text_label(""))
    gtk.expander_set_child(gtk.EXPANDER(details), gtk.WIDGET(global_label))
    gtk.box_append(gtk.BOX(content), details)
    status_label = gtk.LABEL(text_label(status))
    margin(gtk.WIDGET(status_label), 12)
    gtk.widget_add_css_class(gtk.WIDGET(status_label), "dim-label")
    gtk.box_append(gtk.BOX(root), gtk.WIDGET(status_label))
    // Signals and updates
    gobj.signal_connect(library_list, "row-activated", on_book)
    gobj.signal_connect(chapter_picker, "notify::selected", on_chapter)
    gobj.signal_connect(seek_bar, "value-changed", on_seek)
    drop := gtk.drop_target_new(gtk.gdk_file_list_get_type(), .ACTION_COPY)
    gobj.signal_connect(drop, "drop", on_drop)
    gtk.widget_add_controller(gtk.WIDGET(window), gtk.EVENT_CONTROLLER(drop))
    refresh_library()
    glib.timeout_add(200, tick, nil)
    gtk.window_present(window)
}

main :: proc() {
    app_context = context
    config := os.get_env("XDG_CONFIG_HOME", context.allocator)
    if config == "" {config = fmt.aprintf("%s/.config", os.get_env("HOME", context.allocator))}
    folder := fmt.aprintf("%s/abbott", config)
    os.mkdir_all(folder)
    state_path = fmt.aprintf("%s/library.json", folder)
    load_path := state_path
    if !os.exists(state_path) {load_path = fmt.aprintf("%s/abot/library.json", config)}
    if data, err := os.read_entire_file(load_path, context.allocator); err == nil {
        defer delete(data)
        if json.unmarshal(data, &lib) !=
           nil {fmt.eprintln("Could not read library; keeping existing file."); return}
    }
    if lib.speed <= 0 {lib.speed = 1}
    for arg in os.args[1:] {import_book(&lib, arg)}
    p = mpv_create()
    if p == nil {fmt.eprintln("Could not create mpv"); return}
    defer mpv_terminate_destroy(p)
    mpv_set_option_string(p, "vo", "null")
    mpv_set_option_string(p, "video", "no")
    mpv_set_option_string(p, "idle", "yes")
    mpv_set_option_string(p, "keep-open", "yes")
    if mpv_initialize(p) < 0 {fmt.eprintln("Could not initialize mpv"); return}
    app := gtk.application_new("io.abbott.Player", .APPLICATION_NON_UNIQUE)
    defer gobj.object_unref(app)
    gobj.signal_connect(app, "activate", activate)
    gio.application_run(app, os.args[:1])
    save(&lib)
}

