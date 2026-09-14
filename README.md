# GenericPHC

PHC / Visual FoxPro utilities and fixes.

## FuelStar document import (improved)

See `docs/fuelstar-impfs.md` and `prg/fuelstar_impfs.prg`.

FIFO allocation of `SE` lots onto `FI`/`BI` lines (cost from `epcult`, trigger
updates stock when `lote` is filled), plus fixes for the original split/stock
revert, `UPDATE…FROM`, FI costs left at 0, truncated `TipoDoc`, and XML files
marked imported when documents were skipped.
