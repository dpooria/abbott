#!/bin/sh
set -eu
mkdir -p .build
glib-compile-resources assets/abbott.gresource.xml --sourcedir=assets --target=.build/abbott.gresource
fixture_dir=$(mktemp -d)
trap 'rm -rf "$fixture_dir"' EXIT
cat > "$fixture_dir/chapters.txt" <<'CHAPTERS'
;FFMETADATA1
[CHAPTER]
TIMEBASE=1/1000
START=0
END=2000
title=Opening
[CHAPTER]
TIMEBASE=1/1000
START=2000
END=4000
title=Second chapter
CHAPTERS
ffmpeg -v error -f lavfi -i anullsrc=r=44100:cl=mono -i "$fixture_dir/chapters.txt" -map_metadata 1 -t 4 -c:a aac "$fixture_dir/book.m4b"
ABBOTT_TEST_AUDIO="$fixture_dir/book.m4b" odin test . -out:"$fixture_dir/abbott-tests"
