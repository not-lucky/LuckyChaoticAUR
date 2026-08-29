#!/bin/bash
ELECTRON=/usr/bin/electron
if [ ! -x "$ELECTRON" ]; then
    ELECTRON=/usr/lib/electron/electron
fi
if [ ! -x "$ELECTRON" ]; then
    ELECTRON=/usr/bin/electron43
fi
exec "$ELECTRON" /opt/workbuddy-ai/app.asar "$@"
