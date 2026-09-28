#!/bin/sh

# ./build.sh        Debug + Release builds
# ./build.sh test   run the unit tests (lsNoteTests)
if [ "$1" = "test" ]; then
    exec xcodebuild test -scheme lsNote -derivedDataPath build -destination 'platform=macOS'
fi

xcodebuild -scheme lsNote -configuration Debug -derivedDataPath build
xcodebuild -scheme lsNote -configuration Release -derivedDataPath build
