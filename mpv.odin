package abbott

import "core:fmt"
import "core:strings"

foreign import mpv "system:libmpv.so.2"

foreign mpv {
    mpv_create :: proc() -> rawptr ---
    mpv_initialize :: proc(_: rawptr) -> i32 ---
    mpv_terminate_destroy :: proc(_: rawptr) ---
    mpv_set_option_string :: proc(_: rawptr, _: cstring, _: cstring) -> i32 ---
    mpv_command_async :: proc(_: rawptr, _: u64, _: [^]cstring) -> i32 ---
    mpv_command :: proc(_: rawptr, _: [^]cstring) -> i32 ---
    mpv_get_property :: proc(_: rawptr, _: cstring, _: i32, _: rawptr) -> i32 ---
    mpv_set_property_string :: proc(_: rawptr, _: cstring, _: cstring) -> i32 ---
    mpv_wait_event :: proc(_: rawptr, _: f64) -> ^Mpv_Event ---
    mpv_get_property_string :: proc(_: rawptr, _: cstring) -> cstring ---
    mpv_free :: proc(_: rawptr) ---
}

Mpv_Event :: struct {
    id:       i32,
    error:    i32,
    userdata: u64,
    data:     rawptr,
}

cstr :: proc(s: string) -> cstring {return strings.clone_to_cstring(s, context.temp_allocator)}

command :: proc(p: rawptr, args: ..string) -> bool {
    values: [dynamic]cstring
    defer delete(values)
    for a in args {append(&values, cstr(a))}
    append(&values, nil)
    return mpv_command(p, raw_data(values)) >= 0
}

number :: proc(p: rawptr, key: string) -> f64 {
    value: f64
    mpv_get_property(p, cstr(key), 5, &value)
    return value
}

property_text :: proc(p: rawptr, key: string) -> string {
    value := mpv_get_property_string(p, cstr(key))
    if value == nil {return ""}
    defer mpv_free(rawptr(value))
    return strings.clone(string(value))
}

set_number :: proc(p: rawptr, key: string, value: f64) {
    mpv_set_property_string(p, cstr(key), cstr(fmt.tprintf("%.3f", value)))
}

flag :: proc(p: rawptr, key: string) -> bool {
    value: i32
    mpv_get_property(p, cstr(key), 3, &value)
    return value != 0
}

seek_to :: proc(p: rawptr, target, duration: f64) -> bool {
    was_eof := flag(p, "eof-reached")
    target := clamp(target, 0, max(0, duration - 0.05))
    args := [4]cstring{"seek", cstr(fmt.tprintf("%.3f", target)), "absolute+exact", nil}
    if mpv_command_async(p, 1, raw_data(args[:])) < 0 {return false}
    if was_eof {mpv_set_property_string(p, "pause", "no")}
    return true
}

chapter_bounds :: proc(
    chapters: []Chapter,
    position, duration: f64,
) -> (
    index: int,
    start, end: f64,
) {
    end = duration
    for chapter, i in chapters {
        if chapter.start > position {end = min(duration, chapter.start); break}
        index = i
        start = chapter.start
    }
    end = max(start, end)
    return
}

