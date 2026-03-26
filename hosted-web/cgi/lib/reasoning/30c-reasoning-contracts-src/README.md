# 30c Reasoning Contracts Source Shards

`30c-reasoning-contracts.sh` is generated from ordered `.part` files in this directory.

Edit these shards, then rebuild:

```sh
sh tools/build-cgi-shards.sh
```

The build concatenates shards lexicographically (`01-...`, `02-...`, ...).
These shards are fragments, not standalone shell scripts.
