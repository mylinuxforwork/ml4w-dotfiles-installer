#!/usr/bin/env bats

setup() {
    source ./lib/colors.sh
    source ./lib/helpers.sh
    LOG_FILE="$BATS_TEST_TMPDIR/test.log"
    : > "$LOG_FILE"
}

@test "run_logged writes command output to the logfile only" {
    run run_logged bash -c 'echo to-stdout; echo to-stderr >&2'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    grep -q "to-stdout" "$LOG_FILE"
    grep -q "to-stderr" "$LOG_FILE"
}

@test "run_logged passes the exit code through" {
    run run_logged bash -c 'exit 3'
    [ "$status" -eq 3 ]
    grep -q "exit code: 3" "$LOG_FILE"
}

@test "run_logged shows output in verbose mode" {
    VERBOSE=true
    run run_logged echo visible
    [ "$status" -eq 0 ]
    [ "$output" = "visible" ]
    grep -q "visible" "$LOG_FILE"
}

@test "info messages are mirrored to the logfile" {
    run info "hello log"
    grep -q "\[INFO\] hello log" "$LOG_FILE"
}

@test "init_log keeps only the newest logfiles" {
    LOG_DIR="$BATS_TEST_TMPDIR/logs"
    mkdir -p "$LOG_DIR"
    for i in $(seq -w 1 12); do touch "$LOG_DIR/install-200001${i}_000000.log"; done
    init_log
    [ "$(ls "$LOG_DIR" | wc -l)" -eq "$LOG_KEEP" ]
    [ -f "$LOG_FILE" ]
    [ ! -f "$LOG_DIR/install-20000101_000000.log" ]
}
