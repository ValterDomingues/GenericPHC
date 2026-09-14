# GenericPHC

PHC / Visual FoxPro utilities and fixes.

## Importação de movimentos de ponto (`hs`)

See `docs/hs-import-timecontrol.md` and `prg/hs_import_timecontrol.prg`.

Fixes hours parsing (`1` → `1.02`, `1,5` → `1.53`), fragile Excel COM usage, wrong error line
numbers after lookups, unescaped SQL names, and missing transaction/duplicate
checks when importing overtime, absences and meal subsidy into `hs`.
