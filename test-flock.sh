#!/bin/bash
echo "Process $$ acquiring lock"
flock /tmp/lockfile bash -c 'echo "Lock acquired"; sleep 1000 &'
echo "Process $$ released lock"
