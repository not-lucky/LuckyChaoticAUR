#!/bin/bash
flock --close /tmp/lockfile3 bash -c 'echo "Inside"; lslocks | grep /tmp/lockfile3'
