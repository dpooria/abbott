# abbott

A simple audiobook player for Linux, written in Odin with GTK4 and mpv.

* Automatic progress saving and resume
* Embedded chapters with search and chapter-local timing
* Multi-file books with automatic continuation
* Playback speed, bookmarks, and a sleep timer

## Build

Requires [Odin](https://odin-lang.org/), GTK4 development libraries (including `glib-compile-resources`), and `libmpv.so.2`.

```sh
git submodule update --init --recursive
./build.sh
./abbott
```

When cloning, use `git clone --recurse-submodules <repository-url>` to include [odin-gtk](https://github.com/PucklaJ/odin-gtk).

## Usage

Add files or folders using the toolbar, drag and drop, or the command line:

```sh
./abbott /path/to/book.m4b /path/to/audiobook-folder
```

Supports M4B, MP3, M4A, Ogg, Opus, OGA, FLAC, and WAV. Each folder becomes one book; tracks play in filename order (zero-padded track numbers `01`, `02`, ...)

Audio files stay in place; library and progress data are saved in `$XDG_CONFIG_HOME/abbott/library.json`.

## Tests

Requires ffmpeg.

```sh
./test-playback.sh
ABBOTT_LONG_AUDIO="/path/to/long-book.mp3" ./test-playback.sh
```

Inspired by [Voice](https://github.com/PaulWoitaschek/Voice) and [Cozy](https://github.com/geigi/cozy).
