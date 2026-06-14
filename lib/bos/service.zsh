#!/bin/zsh

bos_write_service_script() {
  local profile="$1" runtime model output context runtime_bin cache_name offline=0 arg
  runtime="$(bos_profile_value "$profile" runtime)"
  model="$(bos_profile_value "$profile" model)"
  output="$(bos_profile_value "$profile" output)"
  context="$(bos_profile_value "$profile" context)"
  cache_name="$(bos_profile_value "$profile" cache)"
  [[ -n "$cache_name" && -d "$HOME/.cache/huggingface/hub/$cache_name" &&
    -z "$(find "$HOME/.cache/huggingface/hub/$cache_name" -name '*.incomplete' -print -quit 2>/dev/null)" ]] && offline=1

  {
    print '#!/bin/zsh'
    print 'set -euo pipefail'
    print -r -- "export HF_HUB_OFFLINE=${offline}"
    print -r -- "export HF_HOME=${(q)HOME}/.cache/huggingface"
    case "$runtime" in
      mlx)
        runtime_bin="$BOS_MLX_VENV/bin/mlx_lm.server"
        [[ -x "$runtime_bin" ]] || { bos_die "MLX runtime missing. Run: $BOS_ROOT/install.sh"; return 1; }
        printf 'exec %q --model %q --host 127.0.0.1 --port %q --max-tokens %q' "$runtime_bin" "$model" "$BOS_PORT" "$output"
        ;;
      vllm)
        runtime_bin="$(bos_vllm_bin)"
        [[ -x "$runtime_bin" ]] || { bos_die "vLLM not found. Install it or set BOS_VLLM_BIN."; return 1; }
        printf 'exec %q serve %q --host 127.0.0.1 --port %q --served-model-name %q --max-model-len %q' "$runtime_bin" "$model" "$BOS_PORT" "$model" "$context"
        ;;
      *) bos_die "Unsupported runtime: $runtime"; return 1 ;;
    esac
    while IFS= read -r arg; do printf ' %q' "$arg"; done < <(jq -r --arg profile "$profile" --arg platform "$BOS_PLATFORM" '.profiles[$profile].platforms[$platform].args[]? // empty' "$BOS_MODELS")
    print
  } > "$BOS_SERVICE_SCRIPT"
  chmod +x "$BOS_SERVICE_SCRIPT"
}

bos_write_macos_service() {
  cat > "$BOS_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$BOS_LAUNCHD_LABEL</string>
  <key>ProgramArguments</key><array><string>$BOS_SERVICE_SCRIPT</string></array>
  <key>WorkingDirectory</key><string>$BOS_DATA_HOME</string>
  <key>StandardOutPath</key><string>$BOS_LOG_DIR/model.log</string>
  <key>StandardErrorPath</key><string>$BOS_LOG_DIR/model.error.log</string>
  <key>ProcessType</key><string>Interactive</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><false/>
</dict></plist>
EOF
}

bos_write_linux_service() {
  cat > "$BOS_SYSTEMD_UNIT" <<EOF
[Unit]
Description=Builder OS local model service
After=network.target

[Service]
Type=simple
ExecStart=$BOS_SERVICE_SCRIPT
WorkingDirectory=$BOS_DATA_HOME
StandardOutput=append:$BOS_LOG_DIR/model.log
StandardError=append:$BOS_LOG_DIR/model.error.log
Restart=no

[Install]
WantedBy=default.target
EOF
}

bos_service_start() {
  local profile="$1"
  bos_write_service_script "$profile"
  case "$BOS_PLATFORM" in
    darwin)
      bos_write_macos_service
      launchctl bootout "gui/$(id -u)/$BOS_LAUNCHD_LABEL" >/dev/null 2>&1 || true
      launchctl bootstrap "gui/$(id -u)" "$BOS_PLIST"
      ;;
    linux)
      bos_write_linux_service
      mkdir -p "$HOME/.config/systemd/user"
      ln -sfn "$BOS_SYSTEMD_UNIT" "$HOME/.config/systemd/user/builder-os-model.service"
      systemctl --user daemon-reload
      systemctl --user start builder-os-model.service
      ;;
    *) bos_die "Unsupported platform: $BOS_PLATFORM"; return 1 ;;
  esac
}

bos_service_stop() {
  case "$BOS_PLATFORM" in
    darwin) launchctl bootout --wait "gui/$(id -u)/$BOS_LAUNCHD_LABEL" ;;
    linux) systemctl --user stop builder-os-model.service ;;
    *) return 1 ;;
  esac
}
