package abbott

import "core:path/filepath"
import "odin-gtk/glib"
import "odin-gtk/glib/gio"
import gobj "odin-gtk/glib/gobject"
import "odin-gtk/gtk"

book_menu: ^gtk.Popover
menu_book := -1

setup_book_menu :: proc() {
    book_menu = gtk.POPOVER(gtk.popover_new())
    gtk.widget_set_parent(gtk.WIDGET(book_menu), gtk.WIDGET(library_list))
    box := gtk.box_new(.VERTICAL, 4)
    margin(box, 6)
    gtk.popover_set_child(book_menu, box)
    gobj.signal_connect(window, "close-request", on_library_menu_close)
    add_button(gtk.BOX(box), "Show in folder", on_book_action)
    remove := add_button(gtk.BOX(box), "Remove from library", on_book_action, rawptr(uintptr(1)))
    gtk.widget_set_tooltip_text(gtk.WIDGET(remove), "Removes saved progress and bookmarks. Audio files are kept.")
    gesture := gtk.gesture_click_new()
    gtk.gesture_single_set_button(gtk.GESTURE_SINGLE(gesture), 3)
    gobj.signal_connect(gesture, "pressed", on_book_menu)
    gtk.widget_add_controller(gtk.WIDGET(library_list), gtk.EVENT_CONTROLLER(gesture))
}

on_book_menu :: proc "c" (gesture: ^gtk.GestureClick, _: i32, x, y: f64, _: rawptr) {
    context = app_context
    row := gtk.list_box_get_row_at_y(library_list, i32(y))
    if row == nil {return}
    menu_book = int(gtk.list_box_row_get_index(row))
    gtk.list_box_select_row(library_list, row)
    rect := gtk.Rectangle{i32(x), i32(y), 1, 1}
    gtk.popover_set_pointing_to(book_menu, &rect)
    gtk.popover_popup(book_menu)
    gtk.gesture_set_state(gtk.GESTURE(gesture), .EVENT_SEQUENCE_CLAIMED)
}

on_book_action :: proc "c" (_: ^gtk.Button, action: rawptr) {
    context = app_context
    defer free_all(context.temp_allocator)
    index := menu_book
    menu_book = -1
    gtk.popover_popdown(book_menu)
    if index < 0 || index >= len(lib.books) {return}
    if action == nil {
        book := &lib.books[index]
        file := gio.file_new_for_path(cstr(filepath.dir(book.files[book.track])))
        defer gobj.object_unref(file)
        uri := gio.file_get_uri(file)
        defer glib.free(rawptr(uri))
        gtk.show_uri(window, uri, 0)
        return
    }
    if active == index {
        command(p, "stop")
        active = -1
        pending = false
        paused = true
        seek_target = -1
        sleep_at = 0
        for ch in chapters {delete(ch.title)}
        clear(&chapters)
        updating = true
        gtk.drop_down_set_model(chapter_picker, nil)
        gtk.range_set_range(seek_bar, 0, 1)
        gtk.range_set_value(seek_bar, 0)
        updating = false
        gtk.label_set_text(title_label, cstr(judy_quotes[glib.random_int_range(0, i32(len(judy_quotes)))]))
        gtk.label_set_text(file_label, "Pick a book.")
        gtk.label_set_text(time_label, "00:00:00 / 00:00:00")
        gtk.label_set_text(global_label, "")
        gtk.button_set_icon_name(play_button, "media-playback-start-symbolic")
        gtk.widget_set_sensitive(player_box, false)
    } else if active > index {
        active -= 1
    }
    remove_book(&lib, index)
    status = "Removed from library. Audio files kept."
    save(&lib)
    refresh_library()
    gtk.label_set_text(status_label, cstr(status))
}

on_library_menu_close :: proc "c" (_: ^gtk.Window, _: rawptr) -> glib.boolean {
    context = app_context
    gtk.widget_unparent(gtk.WIDGET(book_menu))
    book_menu = nil
    return false
}
