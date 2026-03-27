reasoning_contract_modules_dir="${ARTIFICER_SCRIPT_DIR}/lib/reasoning/30c-reasoning-contracts-modules"

for reasoning_contract_module in "$reasoning_contract_modules_dir"/[0-9][0-9]-*.sh; do
  [ -f "$reasoning_contract_module" ] || continue
  # shellcheck disable=SC1090
  . "$reasoning_contract_module"
done
