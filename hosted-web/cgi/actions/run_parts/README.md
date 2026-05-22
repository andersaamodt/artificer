# Run Pipeline Modules

`run.sh` sources these files in order:

1. `run-part-001.sh`
2. `run-part-002.sh`
3. `run-part-003.sh`
4. `run-part-004.sh`

`run-part-004.sh` is canonical runtime source, not a generated artifact.

`run-part-004.sh` now acts as a stable loader over:

- `run-part-004-modules/00-quick-and-routing.sh`
- `run-part-004-modules/10-runtime-and-finalization.sh`

The loader file remains the contract surface used by `run.sh`.
