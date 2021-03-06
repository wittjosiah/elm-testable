#!/bin/bash

set -ex

elm package install --yes

rm -Rf elm-stuff/build-artifacts
rm -Rf tests/elm-stuff/build-artifacts
rm -Rf examples/elm-stuff/build-artifacts
rm -Rf examples/tests/elm-stuff/build-artifacts

elm make --yes
./run-tests.sh

cd examples
elm package install --yes
./run-tests.sh
elm make --yes RandomGif.elm --output RandomGif.js
elm make --yes Spelling.elm --output Spelling.js
elm make --yes WebSockets.elm --output WebSockets.js
open index.html || true
