# Test sandbox for bootstrap.sh: a temp $HOME, a throwaway copy of the repo
# runner, and fake system commands on PATH. Every fake appends "<cmd> <args>"
# to $CALLS so tests can assert on calls and their order.

# shellcheck disable=SC2034  # used by the .bats files
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

setup() {
    export FAKE_DIR="$BATS_TEST_TMPDIR"
    export HOME="$FAKE_DIR/home"
    export CALLS="$FAKE_DIR/calls.log"
    export REPO="$FAKE_DIR/repo"
    mkdir -p "$HOME" "$FAKE_DIR/bin" "$REPO"
    : > "$CALLS"
    export PATH="$FAKE_DIR/bin:$PATH"

    # The runner locates the repo from its own path, so test against a copy.
    cp "$REPO_ROOT/bootstrap.sh" "$REPO/bootstrap.sh" 2>/dev/null || true
    BOOTSTRAP="$REPO/bootstrap.sh"

    # sudo only logs: nothing runs as root, pacman is never reached.
    fake sudo < /dev/null
    fake paru < /dev/null
    fake stow < /dev/null
}

# fake <name> [--no-log] < body — write an executable fake command.
fake() {
    local name="$1" log=1
    [[ ${2:-} == --no-log ]] && log=0
    {
        echo '#!/bin/bash'
        (( log )) && echo "echo \"$name \$*\" >> \"\$CALLS\""
        cat
    } > "$FAKE_DIR/bin/$name"
    chmod +x "$FAKE_DIR/bin/$name"
}

# module <name> [pkgs...] — create a fixture module, with packages.txt if pkgs given.
module() {
    local name="$1"
    shift
    mkdir -p "$REPO/$name"
    (( $# )) && printf '%s\n' "$@" > "$REPO/$name/packages.txt"
    return 0
}

# list <name> <modules...> — write a modules.<name> list file in the fixture repo.
list() {
    local name="$1"
    shift
    printf '%s\n' "$@" > "$REPO/modules.$name"
}

# install_script <module> — executable install.sh that logs "install <module>".
install_script() {
    printf '#!/usr/bin/env bash\necho "install %s" >> "$CALLS"\n' "$1" > "$REPO/$1/install.sh"
    chmod +x "$REPO/$1/install.sh"
}

# use_real_stow — drop the stow fake; skip the test when stow is not installed.
use_real_stow() {
    rm -f "$FAKE_DIR/bin/stow"
    command -v stow > /dev/null || skip "stow is not installed"
}

# conf_module <name> — module with a config file at .config/<name>/conf plus metadata files.
conf_module() {
    module "$1" "pkg-$1"
    mkdir -p "$REPO/$1/.config/$1" "$REPO/$1/tests" "$REPO/$1/system"
    echo "conf" > "$REPO/$1/.config/$1/conf"
    echo "t" > "$REPO/$1/tests/t.bats"
    echo "s" > "$REPO/$1/system/s.conf"
    echo "aur" > "$REPO/$1/packages.aur.txt"
    printf '#!/usr/bin/env bash\ntrue\n' > "$REPO/$1/install.sh"
    chmod +x "$REPO/$1/install.sh"
}

# calls <cmd> — logged calls for one fake.
calls() {
    grep "^$1 " "$CALLS" || true
}
