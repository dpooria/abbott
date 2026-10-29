# abbott

A simple audiobook player based on mpv.

* Automatic progress saving and resume
* Embedded chapters with search and chapter-local timing
* Multi-file books with automatic continuation
* Playback speed, bookmarks, and a sleep timer

## Build

Requires a [Odin](https://odin-lang.org/) distribution (including its bundled raylib and raygui libraries), and `libmpv.so.2` on Linux.

```sh
odin build . -out:abbott
./abbott
```

## Windows

Requires `libmpv-2.dll` and its dependencies on `PATH` or beside `abbott.exe`.
Additionally install Odin and Visual Studio C++ Build Tools with the Windows SDK, then run:

```powershell
powershell -ExecutionPolicy Bypass -File .\build-windows.ps1
```

The script puts `abbott.exe`, and supporting runtime files `dist/windows/`. 

## Usage

Add files or folders using the toolbar’s built-in file browser, drag and drop, or the command line:

```sh
./abbott /path/to/book.m4b /path/to/audiobook-folder
```

Supports M4B, MP3, M4A, Ogg, Opus, OGA, FLAC, and WAV. Each folder becomes one book; tracks play in filename order (zero-padded track numbers `01`, `02`, ...)

Audio files stay in place; library and progress data are saved in `$XDG_CONFIG_HOME/abbott/library.json` on Linux and `data/library.json` beside the executable for Windows.

## Tests

Requires ffmpeg.

```sh
./test-playback.sh
ABBOTT_LONG_AUDIO="/path/to/long-book.mp3" ./test-playback.sh
```

Inspired by [Voice](https://github.com/PaulWoitaschek/Voice) and [Cozy](https://github.com/geigi/cozy).
