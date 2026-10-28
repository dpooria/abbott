#!/bin/sh
set -eu
mkdir -p .build
glib-compile-resources assets/abbott.gresource.xml --sourcedir=assets --target=.build/abbott.gresource
odin build . -out:abbott "$@"
