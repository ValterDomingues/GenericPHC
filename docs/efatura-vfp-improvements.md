# E-fatura VFP — code improvements

Improved routine: `prg/efatura_compras_improved.prg`

## Bugs fixed

| Issue | Original | Fix |
|---|---|---|
| **`Nvl` argument order** | `Nvl('', Alltrim(...))` always returned `''` (first arg is never null) | `Nvl(value, '')` via `func_safeStr` / `func_htmlToPlain` |
| **`impAdicVal` arithmetic** | `valorTotal - base + iva` | `valorTotal - base - iva` |
| **`func_getDocs` returns** | bare `Return` on errors (ambiguous) | always `Return .T.` / `Return .F.` |
| **`proc_cToD` dd-mm-yyyy** | `Date(day, month, year)` — wrong VFP order | `Date(year, month, day)` |
| **Fragile CSRF/XML scrape** | Triple-nested Chilkat paths through `head\|link\|…\|script` | `func_extractToken()` on `BodyStr` |
| **Fragile auth form scrape** | 8 hard-coded `input\|input\|…` depths + empty script loop | `proc_parseAuthFormFields()` walks every `<input>` |
| **`DoComando` Replace by portal name** | Dynamic field name, easy to break | Explicit `Do Case` map (`sessionID`→`SessionId`, etc.) |

## Structure improvements

- Shared helpers: `func_isoDate`, `func_centsToNum`, `func_safeStr`, `func_htmlToPlain`, `proc_addAuthParams`
- HTTP lifecycle: `func_httpCreate` / `proc_httpCleanup`
- COM objects released after use in the detail loop
- `LOCAL` declarations; `Round(..., 2)` on totals reconciliation
- Typo alias kept: `proc_credendiaisAT` → `proc_credenciaisAT`

## Drop-in notes

- Still depends on PHC helpers: `Mensagem`, `GetNome`, `GetUmValorString`, `Browlist`, `Mostrameisto`, `Fecha`, `Regua`, `Dpergunta`, `u_val`, `Astr`, `Datavazia`, form `usqlvar`
- External procs still expected elsewhere: `proc_valAcessoAT`, `proc_cfgDocCtbCompras`, `proc_importSaftFt`, `proc_importSaftCtb`
- Requires Chilkat `Chilkat_9_5_0.Http` (and Json/Xml/HtmlToText as before)
