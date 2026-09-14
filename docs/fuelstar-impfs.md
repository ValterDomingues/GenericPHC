# FuelStar → PHC document import

Improved routine: `prg/fuelstar_impfs.prg`

Drop-in for `proc_impFS()` (and `proc_recImp()`). Reads FuelStar daily XML from the
UNC folder, maps document types to PHC FT/BO series, assigns **SE lots** (FIFO)
to fuel lines, then inserts FT/FI or BO/BI. Filling `FI.lote` / `BI.lote` lets
the PHC trigger update `SE.stock`; `epcult` of the lot is written as the line
cost (`FI.ecusto` / `FI.epcp`).

## Lot / stock (SE → FI)

| Rule | Behaviour |
|---|---|
| Source | `SELECT ref,lote,stock,epcult,data,armazem FROM se WHERE stock>0 ORDER BY ref,armazem,data,lote` copied into a **ReadWrite** cursor (SPT cursors are not updatable) |
| Sales | Oldest lot first; if one lot cannot cover the line, the line is split (`lordem` 100, 101, 102…) |
| Shortage | Remainder is imported **without** lote; an error row is logged (no invented `*` lot) |
| Credit notes | Do **not** consume; qty is added back to the newest lot of that ref/warehouse so a later sale in the same run can use it |
| Cancelled (`EstadoDocumento='A'`) | No lot assignment (trigger would still move stock) |
| Warehouse | `Armazem=0` → 1; lots are filtered by warehouse (FI/BI no longer hard-code armazém 1) |

The PHC trigger remains the only writer of real `SE` stock. The cursor is only
a planner so two XML lines in the same run cannot both take the same litres.

## Bugs fixed

| Issue | Original | Fix |
|---|---|---|
| **Compile error** | `Where … NumLinhaReplace crsDocLin.Lote With '*'` | Two statements were concatenated |
| **Invalid VFP SQL** | `UPDATE crsLotes SET stock = crsLotesRef.stock FROM crsLotesRef …` | VFP has no `UPDATE…FROM`; stock is replaced on `crsLotes` directly |
| **FIFO undone after split** | After `func_distribLote` the pre-split `crsLotesRef` was written back | Single ReadWrite `crsLotes`; no revert |
| **Cêntimos** | `REPLACE ValorLinha WITH ValorLinha+(mVal-mTotalLin) ALL` | Remainder on the **last** slice only; discounts prorated |
| **FI cost = 0** | `custo,ecusto,pcp,epcp` hardcoded 0 | From `se.epcult` × quantity |
| **Lote `*`** | Marker when SE had no stock; trigger still fired | Empty lote + `usalote=0` + `crsErr` |
| **SPT stock** | `u_sqlexec` cursor is typically read-only | `INTO CURSOR crsLotes ReadWrite` copy |
| **TipoDoc C(2)** | `FT_tran` / `FT_guia` stored as `FT` | `TipoDoc C(10)` |
| **NIF** | `GetChildIntValue` drops letters / leading zeros | `GetChildContent` |
| **SET PATH** | `SET PATH TO cDefaultPath` (undefined) after `ADIR` | `ADIR(Addbs(path)+"*.XML")` — default dir untouched |
| **NC payments** | `Abs(running+new)*sinal` → second cash line on NC is wrong | `running + Abs(new)*sinal` |
| **SQL quotes** | `O'Brien` broke INSERT | `func_sqlLit` |
| **Create CL/ST on parse** | Cancel after preview still created cards | Lookup while reading; insert only after confirm |
| **`.importado`** | Any XML without an error row was renamed, including skipped docs | Rename only when every doc is ImportOk / already Existe / Ignorar |
| **proc_recImp dates** | `Locate` + `Skip` | `Locate For no = 1/2` |

## Drop-in notes

Still depends on PHC helpers: `Mensagem`, `ActForm`, `DeactForm`, `Browlist`,
`Mostrameisto`, `Fecha`, `Regua`, `GetNome`, `GetUmValorString`,
`GetUmValorNumerico`, `u_sqlexec`, `u_stamp`, `u_val`, `Astr`, `Adec_Tr`,
`Dtosql`, `Datavazia`, `DoComando`/`usqlvar`, `Addbs`, `JustFName`.

Requires Chilkat `Chilkat_9_5_0.Xml`. Path default remains
`\\192.168.20.1\FuelStar\` (local override is commented next to it).

Document-type map is unchanged (`W`→FS, `G`→FR, `C`→NC, `190`→DC, `181`/`298`
not imported, …). Destination table (FT vs BO) is still chosen in the series
mapping grid.

Header+lines are still separate SQL transactions per original PHC pattern: a
line failure can leave an orphan FT/BO header (logged in `crsErr`; the XML is
**not** renamed).
