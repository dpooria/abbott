package abbott

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:testing"
import "core:time"

@(test)
progress_roundtrip :: proc(t: ^testing.T) {
    original := Book {
        title    = "Test",
        track    = 2,
        position = 123.5,
        duration = 500,
    }
    append(&original.files, "one.mp3", "two.mp3", "three.mp3")
    append(&original.bookmarks, Bookmark{2, 90})
    defer delete(original.files)
    defer delete(original.bookmarks)
    data, err := json.marshal(original)
    testing.expect(t, err == nil)
    defer delete(data)
    restored: Book
    testing.expect(t, json.unmarshal(data, &restored) == nil)
    defer delete(restored.title)
    defer delete(restored.files)
    defer delete(restored.bookmarks)
    defer for file in restored.files {delete(file)}
    testing.expect(t, restored.track == 2 && restored.position == 123.5)
    testing.expect(t, restored.files[2] == "three.mp3" && restored.bookmarks[0].position == 90)
}

@(test)
embedded_chapters_and_seek :: proc(t: ^testing.T) {
    fixture := os.get_env("ABBOTT_TEST_AUDIO", context.allocator)
    defer delete(fixture)
    if fixture == "" {fmt.println("Set ABBOTT_TEST_AUDIO to run playback integration"); return}
    p := mpv_create()
    defer mpv_terminate_destroy(p)
    mpv_set_option_string(p, "ao", "null")
    mpv_set_option_string(p, "vo", "null")
    mpv_set_option_string(p, "pause", "yes")
    testing.expect(t, mpv_initialize(p) >= 0)
    testing.expect(t, command(p, "loadfile", fixture))
    loaded := false
    for i in 0 ..< 100 {
        if mpv_wait_event(p, 0.05).id == 8 {loaded = true; break}
    }
    testing.expect(t, loaded)
    testing.expect(t, int(number(p, "chapters")) == 2)
    testing.expect(t, number(p, "chapter-list/1/time") == 2)
    set_number(p, "time-pos", 2.5)
    for i in 0 ..< 100 {
        if number(p, "time-pos") >= 2 {break}
        time.sleep(10 * time.Millisecond)
    }
    testing.expect(t, number(p, "time-pos") >= 2)
}

@(test)
legacy_library :: proc(t: ^testing.T) {
    data := `{"books":[],"selected":-1,"light":true,"speed":1.25}`
    restored: Library
    testing.expect(t, json.unmarshal(transmute([]byte)data, &restored) == nil)
    testing.expect(t, restored.selected == -1 && restored.speed == 1.25)
    delete(restored.books)
}

@(test)
chapter_local_times :: proc(t: ^testing.T) {
    marks := [3]Chapter{{"One", 0}, {"Two", 60}, {"Three", 150}}
    index, start, end := chapter_bounds(marks[:], 90, 240)
    testing.expect(t, index == 1 && start == 60 && end == 150)
    testing.expect(t, 90 - start == 30 && end - start == 90)
    index, start, end = chapter_bounds(marks[:], 150, 240)
    testing.expect(t, index == 2 && start == 150 && end == 240)
    index, start, end = chapter_bounds(nil, 10, 240)
    testing.expect(t, index == 0 && start == 0 && end == 240)
}

@(test)
long_book_seeking :: proc(t: ^testing.T) {
    fixture := os.get_env("ABBOTT_LONG_AUDIO", context.allocator)
    defer delete(fixture)
    if fixture == "" {return}
    player := mpv_create()
    defer mpv_terminate_destroy(player)
    mpv_set_option_string(player, "ao", "null")
    mpv_set_option_string(player, "vo", "null")
    mpv_set_option_string(player, "video", "no")
    mpv_set_option_string(player, "keep-open", "yes")
    testing.expect(t, mpv_initialize(player) >= 0)
    testing.expect(t, command(player, "loadfile", fixture))
    loaded := false
    for i in 0 ..< 200 {
        if mpv_wait_event(player, 0.05).id == 8 {loaded = true; break}
    }
    testing.expect(t, loaded)
    duration := number(player, "duration")
    testing.expect(t, duration > 3600 && number(player, "chapters") > 1)
    targets := [3]f64{duration * 0.85, 100, -30}
    for target in targets {
        began := time.tick_now()
        testing.expect(t, seek_to(player, target, duration))
        reached := false
        for i in 0 ..< 500 {
            time.sleep(10 * time.Millisecond)
            pos := number(player, "time-pos")
            if !flag(player, "seeking") && abs(pos - max(0, target)) < 2 {reached = true; break}
        }
        testing.expect(t, reached)
        before := number(player, "time-pos")
        time.sleep(250 * time.Millisecond)
        testing.expect(t, number(player, "time-pos") > before + 0.05)
        testing.expect(t, !flag(player, "pause") && !flag(player, "eof-reached"))
        fmt.printf(
            "Seek to %.0fs: %v; playback advanced\n",
            max(0, target),
            time.tick_since(began),
        )
    }
    mpv_set_property_string(player, "pause", "yes")
    testing.expect(t, seek_to(player, 100, duration))
    time.sleep(300 * time.Millisecond)
    testing.expect(t, flag(player, "pause"))
    mpv_set_property_string(player, "pause", "no")
    testing.expect(t, seek_to(player, duration + 100, duration))
    for i in 0 ..< 500 {
        if flag(player, "eof-reached") {break}
        time.sleep(10 * time.Millisecond)
    }
    testing.expect(t, flag(player, "eof-reached"))
    testing.expect(t, seek_to(player, 0, duration))
    time.sleep(500 * time.Millisecond)
    testing.expect(t, !flag(player, "pause") && !flag(player, "eof-reached"))
    testing.expect(t, number(player, "time-pos") > 0 && number(player, "time-pos") < 2)
}

