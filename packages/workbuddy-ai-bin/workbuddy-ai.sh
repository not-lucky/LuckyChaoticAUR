#!/bin/bash
ELECTRON=/usr/lib/electron37/electron
if [ ! -x "$ELECTRON" ]; then
    ELECTRON=/usr/bin/electron
fi
exec "$ELECTRON" /opt/workbuddy-ai/app.asar "$@"
