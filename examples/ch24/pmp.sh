#!/usr/bin/env bash
# A sampling profiler made of gdb and a shell loop ("poor man's profiler").
# Starts PROGRAM under gdb, interrupts it every INTERVAL seconds, and has
# gdb print the stack each time. Summarize the output with pmp_summary.py.
#
#   usage: pmp.sh SAMPLES INTERVAL PROGRAM [ARGS...] > stacks.txt
set -u
samples=$1
interval=$2
shift 2

# gdb stops on SIGINT without passing it on, prints 12 frames, continues;
# after the last sample it kills the program instead of continuing.
cmds=(-iex "set debuginfod enabled off" -ex "set pagination off" -ex "set width 0"
      -ex "set print frame-arguments none"
      -ex "handle SIGINT stop print nopass" -ex run -ex "bt 12")
for ((i = 1; i < samples; i++)); do cmds+=(-ex continue -ex "bt 12"); done
gdb -batch -nx "${cmds[@]}" -ex kill --args "$@" &
gdb_pid=$!

# The program is gdb's child: gdb started it, so it may trace it even
# where attaching to a running process is forbidden.
pid=""
while [ -z "$pid" ]; do
  sleep 0.1
  pid=$(pgrep -P "$gdb_pid" | head -1)
done
for ((i = 0; i < samples; i++)); do
  sleep "$interval"
  kill -INT "$pid" 2>/dev/null || break
done
wait "$gdb_pid"
