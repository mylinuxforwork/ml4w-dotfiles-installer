#!/usr/bin/env bats

setup() {
    # Mocking pacman for the test environment
    pacman() {
        if [ "$2" == "bash" ]; then return 0; else return 1; fi
    }
    export -f pacman
    source ./lib/system.sh
}

@test "is_pkg_installed returns 0 for existing package" {
    run is_pkg_installed "bash"
    [ "$status" -eq 0 ]
}

@test "is_pkg_installed returns 1 for missing package" {
    run is_pkg_installed "nonexistent-pkg"
    [ "$status" -eq 1 ]
}