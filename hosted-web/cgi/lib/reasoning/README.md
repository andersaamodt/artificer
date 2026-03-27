# Reasoning Runtime Modules

`../30-reasoning-programming.sh` loads these modules in order:

1. `30a-core-budget-normalization.sh`
2. `30b-programming-branching.sh`
3. `30c-reasoning-contracts.sh`
4. `30d-task-specializations.sh`
5. `30e-model-adapters-salvage.sh`

`30c-reasoning-contracts.sh` is canonical runtime source, not a generated artifact.

`30c-reasoning-contracts.sh` is a stable loader over these concern modules:

- `30c-reasoning-contracts-modules/00-contract-basics.sh`
- `30c-reasoning-contracts-modules/10-anchor-and-focus.sh`
- `30c-reasoning-contracts-modules/20-scenario-depth.sh`
- `30c-reasoning-contracts-modules/30-reasoning-lines.sh`
- `30c-reasoning-contracts-modules/40-compact-contract.sh`
- `30c-reasoning-contracts-modules/50-cross-domain-lenses.sh`
- `30c-reasoning-contracts-modules/60-runtime-evidence.sh`
