package abbott

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "odin-gtk/glib"

Bookmark :: struct {
    track:    int,
    position: f64,
}

Book :: struct {
    title:     string,
    files:     [dynamic]string,
    track:     int,
    position:  f64,
    duration:  f64,
    bookmarks: [dynamic]Bookmark,
}

Library :: struct {
    books:    [dynamic]Book,
    selected: int,
    speed:    f64,
}

Chapter :: struct {
    title: string,
    start: f64,
}

state_path: string
status := "Drop an audiobook here"

save :: proc(lib: ^Library) {
    data, err := json.marshal(lib^)
    if err != nil {status = "Could not encode library"; return}
    defer delete(data)
    tmp := fmt.aprintf("%s.tmp", state_path)
    defer delete(tmp)
    if os.write_entire_file(tmp, data) != nil || os.rename(tmp, state_path) != nil {
        status = "Could not save progress"
    }
}

// supported files
audio_file :: proc(path: string) -> bool {
    ext := strings.to_lower(filepath.ext(path), context.temp_allocator)
    return(
        ext == ".m4b" ||
        ext == ".mp3" ||
        ext == ".m4a" ||
        ext == ".ogg" ||
        ext == ".opus" ||
        ext == ".flac" ||
        ext == ".wav" ||
        ext == ".oga" \
    )
}

import_book :: proc(lib: ^Library, path: string) {
    path, err := filepath.abs(path, context.temp_allocator)
    if err != nil {status = "Could not resolve audiobook path"; return}
    book: Book
    if glib.file_test(cstr(path), .IS_REGULAR) {
        if !audio_file(path) {status = "Choose an audio file or folder"; return}
        append(&book.files, strings.clone(path))
        book.title = strings.clone(filepath.stem(path))
    } else {
        collect_audio(path, &book.files)
        slice.sort(book.files[:])
        book.title = strings.clone(filepath.base(strings.trim_right(path, "/\\")))
    }
    if len(book.files) == 0 {delete(book.title); status = "No supported audio files found"; return}
    for existing in lib.books {
        if existing.files[0] == book.files[0] {
            for file in book.files {delete(file)}; delete(book.files); delete(book.title)
            status = "This book is already in your library"; return
        }
    }
    append(&lib.books, book)
    status = "Book added"
    save(lib)
}

clock_text :: proc(seconds: f64) -> string {
    n := int(max(0, seconds))
    return fmt.tprintf("%02d:%02d:%02d", n / 3600, n / 60 % 60, n % 60)
}

collect_audio :: proc(path: string, files: ^[dynamic]string) {
    dir := glib.dir_open(cstr(path), 0, nil)
    if dir == nil {return}
    defer glib.dir_close(dir)
    for {
        name := glib.dir_read_name(dir)
        if name == nil {break}
        file, _ := filepath.join({path, string(name)}, context.allocator)
        defer delete(file)
        if glib.file_test(cstr(file), .IS_SYMLINK) {continue}
        if glib.file_test(
            cstr(file),
            .IS_DIR,
        ) {collect_audio(file, files)} else if audio_file(file) {append(files, strings.clone(file))}
    }
}


remove_book :: proc(lib: ^Library, index: int) {
    book := lib.books[index]
    delete(book.title)
    for file in book.files {delete(file)}
    delete(book.files)
    delete(book.bookmarks)
    ordered_remove(&lib.books, index)
    if lib.selected == index {lib.selected = -1}
    else if lib.selected > index {lib.selected -= 1}
}
