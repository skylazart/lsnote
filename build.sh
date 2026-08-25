#!/bin/sh

xcodebuild -scheme lsNote -configuration Debug -derivedDataPath build
xcodebuild -scheme lsNote -configuration Release -derivedDataPath build
