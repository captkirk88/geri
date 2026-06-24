#!/bin/bash
OUTPUT_DIR="${1:-build/}"
mkdir -p "$OUTPUT_DIR"

ODIN_ROOT=$(odin root | tr -d '\r\n')
# Find all vendor imports
VENDOR_IMPORTS=$(grep -rhoE 'import\s+([a-zA-Z_]\w*\s+)?"vendor:([^/"]+)' --include="*.odin" . | sed -E 's/.*"vendor:([^/"]+)/\1/' | sort -u)

for PKG in $VENDOR_IMPORTS; do
    VENDOR_PATH="$ODIN_ROOT/vendor/$PKG"
    if [ -d "$VENDOR_PATH" ]; then
        echo "=> Checking vendor package: $PKG at $VENDOR_PATH"
        # Find all .so and .dylib files
        find "$VENDOR_PATH" -type f \( -name "*.so" -o -name "*.dylib" \) | while read -r lib; do
            lib_name=$(basename "$lib")
            if [ ! -f "$OUTPUT_DIR/$lib_name" ]; then
                cp "$lib" "$OUTPUT_DIR/"
                echo "Copied $lib_name to $OUTPUT_DIR"
            fi
        done
    fi
done
