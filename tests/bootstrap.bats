load helpers

@test "installs repo packages from all listed modules in one pacman call" {
    module m1 a "# a comment" "" b
    module m2 c
    run "$BOOTSTRAP" --modules m1,m2
    [ "$status" -eq 0 ]
    [ "$(calls sudo)" = "sudo pacman -S --needed --noconfirm a b c" ]
}

@test "installs aur packages with paru after pacman" {
    module m1 a
    printf '%s\n' "# aur" x y > "$REPO/m1/packages.aur.txt"
    run "$BOOTSTRAP" --modules m1
    [ "$status" -eq 0 ]
    [ "$(calls paru)" = "paru -S --needed --noconfirm x y" ]
    pacman_line=$(grep -n '^sudo pacman' "$CALLS" | cut -d: -f1)
    paru_line=$(grep -n '^paru' "$CALLS" | cut -d: -f1)
    [ "$pacman_line" -lt "$paru_line" ]
}

@test "skips paru when no module has aur packages" {
    module m1 a
    run "$BOOTSTRAP" --modules m1
    [ "$status" -eq 0 ]
    [ -z "$(calls paru)" ]
}

@test "runs install.sh before stowing that module" {
    module m1 a
    install_script m1
    run "$BOOTSTRAP" --modules m1
    [ "$status" -eq 0 ]
    install_line=$(grep -n '^install m1' "$CALLS" | cut -d: -f1)
    stow_line=$(grep -n '^stow ' "$CALLS" | grep -v -- ' --no ' | grep -- '--restow m1$' | cut -d: -f1)
    [ "$install_line" -lt "$stow_line" ]
}

@test "runs install.sh in module order after package installs" {
    module m1 a
    module m2 b
    install_script m1
    install_script m2
    run "$BOOTSTRAP" --modules m2,m1
    [ "$status" -eq 0 ]
    [ "$(grep -v '^stow' "$CALLS" | tail -n 2 | paste -sd,)" = "install m2,install m1" ]
}

@test "skips install.sh that is not executable" {
    module m1 a
    printf '#!/usr/bin/env bash\necho "install m1" >> "$CALLS"\n' > "$REPO/m1/install.sh"
    run "$BOOTSTRAP" --modules m1
    [ "$status" -eq 0 ]
    ! grep -q '^install m1' "$CALLS"
}

@test "runs post-install.sh after every module is stowed, in module order" {
    module m1 a
    module m2 b
    post_install_script m1
    post_install_script m2
    run "$BOOTSTRAP" --modules m2,m1
    [ "$status" -eq 0 ]
    last_stow=$(grep -n '^stow ' "$CALLS" | grep -v -- ' --no ' | sed -n '$s/:.*//p')
    first_post=$(grep -n '^post-install ' "$CALLS" | sed -n '1s/:.*//p')
    [ "$first_post" -gt "$last_stow" ]
    [ "$(grep '^post-install ' "$CALLS" | paste -sd,)" = "post-install m2,post-install m1" ]
}

@test "skips post-install.sh that is absent or not executable" {
    module m1 a
    module m2 b
    printf '#!/usr/bin/env bash\necho "post-install m1" >> "$CALLS"\n' > "$REPO/m1/post-install.sh"
    run "$BOOTSTRAP" --modules m1,m2
    [ "$status" -eq 0 ]
    [ -z "$(grep '^post-install ' "$CALLS" || true)" ]
}

@test "stows each module with target HOME" {
    module m1 a
    module m2 b
    run "$BOOTSTRAP" --modules m1,m2
    [ "$status" -eq 0 ]
    stows=$(calls stow | grep -v -- ' --no ')
    [[ "$stows" == *"stow --dir=$REPO --target=$HOME "*"--restow m1"* ]]
    [[ "$stows" == *"--restow m2"* ]]
    [[ "$stows" == *"--no-folding"* ]]
    [[ "$(calls stow | grep -- ' --no ')" == *"--no-folding"* ]]
}

@test "directories are created, not folded" {
    use_real_stow
    conf_module m1
    run "$BOOTSTRAP" --modules m1
    [ "$status" -eq 0 ]
    [ -d "$HOME/.config/m1" ] && [ ! -L "$HOME/.config/m1" ]
    [ -L "$HOME/.config/m1/conf" ]
}

@test "module metadata is never stowed" {
    use_real_stow
    conf_module m1
    run "$BOOTSTRAP" --modules m1
    [ "$status" -eq 0 ]
    [ -f "$HOME/.config/m1/conf" ]
    [ ! -e "$HOME/packages.txt" ]
    [ ! -e "$HOME/packages.aur.txt" ]
    [ ! -e "$HOME/install.sh" ]
    [ ! -e "$HOME/post-install.sh" ]
    [ ! -e "$HOME/tests" ]
    [ ! -e "$HOME/system" ]
}

@test "stops and lists conflicts when a real file is at a stow target" {
    use_real_stow
    conf_module m1
    conf_module m2
    mkdir -p "$HOME/.config/m1"
    echo "mine" > "$HOME/.config/m1/conf"
    run "$BOOTSTRAP" --modules m1,m2
    [ "$status" -ne 0 ]
    [[ "$output" == *".config/m1/conf"* ]]
    [ ! -e "$HOME/.config/m2" ]
    [ ! -L "$HOME/.config/m1/conf" ]
    [ "$(cat "$HOME/.config/m1/conf")" = "mine" ]
}

@test "--adopt takes over conflicting files" {
    use_real_stow
    conf_module m1
    mkdir -p "$HOME/.config/m1"
    echo "mine" > "$HOME/.config/m1/conf"
    run "$BOOTSTRAP" --modules m1 --adopt
    [ "$status" -eq 0 ]
    [ -L "$HOME/.config/m1/conf" ]
}

@test "second run is a no-op" {
    use_real_stow
    conf_module m1
    run "$BOOTSTRAP" --modules m1
    [ "$status" -eq 0 ]
    run "$BOOTSTRAP" --modules m1
    [ "$status" -eq 0 ]
    [ -f "$HOME/.config/m1/conf" ]
}

@test "unknown module name fails before installing anything" {
    module m1 a
    run "$BOOTSTRAP" --modules m1,nope
    [ "$status" -ne 0 ]
    [[ "$output" == *"nope"* ]]
    [ ! -s "$CALLS" ]
}

@test "--dry-run prints the plan and calls nothing" {
    module m1 a b
    printf '%s\n' x > "$REPO/m1/packages.aur.txt"
    install_script m1
    post_install_script m1
    run "$BOOTSTRAP" --modules m1 --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"post-install: m1/post-install.sh"* ]]
    [[ "$output" == *"a b"* ]]
    [[ "$output" == *"x"* ]]
    [[ "$output" == *"m1"* ]]
    [ ! -s "$CALLS" ]
}

@test "--lists reads modules.<list> files in order" {
    module m1 a
    module m2 b
    list base m1
    list desktop "# comment" "" m2
    run "$BOOTSTRAP" --lists base,desktop
    [ "$status" -eq 0 ]
    [ "$(calls sudo)" = "sudo pacman -S --needed --noconfirm a b" ]
    calls stow | grep -- '--restow' | head -n 1 | grep -q 'm1$'
}

@test "default lists are base and desktop" {
    module m1 a
    module m2 b
    list base m1
    list desktop m2
    run "$BOOTSTRAP"
    [ "$status" -eq 0 ]
    [ "$(calls sudo)" = "sudo pacman -S --needed --noconfirm a b" ]
}

@test "unknown option fails" {
    run "$BOOTSTRAP" --bogus
    [ "$status" -ne 0 ]
    [ ! -s "$CALLS" ]
}
