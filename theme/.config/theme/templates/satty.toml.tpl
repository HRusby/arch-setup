# Satty config (passed with --config). Keys are from satty's documented
# config.toml; command-line flags from `capture` take precedence.
[general]
copy-command = "wl-copy"
early-exit = ["copy", "save"]
initial-tool = "arrow"

[color-palette]
palette = ["{{red}}", "{{orange}}", "{{yellow}}", "{{green}}", "{{aqua}}", "{{blue}}", "{{purple}}", "{{fg}}"]
