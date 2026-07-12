#!/bin/bash
set -e

mkdir -p docs

echo "=> Generating documentation..."
odin doc . -all-packages -doc-format -out:docs/odin.odin-doc

echo "=> Documentation generated successfully in docs/odin.odin-doc"
