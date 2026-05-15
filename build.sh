#!/bin/bash

echo "Building KeyRemapper..."
clang -fobjc-arc -framework Foundation -framework ApplicationServices -framework Carbon KeyRemapper.m -o "KeyRemapper"
if [ $? -eq 0 ]; then
    chmod +x "KeyRemapper"
    echo "Successfully built KeyRemapper."
    echo "To run it, type: ./KeyRemapper"
else
    echo "Build failed!"
    exit 1
fi
