# Importação de movimentos de ponto → `hs`

Improved routine: `prg/hs_import_timecontrol.prg`

Drop-in for the PHC screen **Horas de Funcionário** (`hs`). Imports Excel/CSV from
the time-control system as:

| Tipo | Descrição | Tabelas de apoio | Campos hs principais |
|---|---|---|---|
| 1 | Horas Extraordinárias | `hshe` | `hshecod`, `tipohora`, `horas`, `factor` |
| 2 | Faltas | `ty` | `tyfalta`, `horasfalta`, `diasref` |
| 3 | Sub. refeição (mov. variáveis) | `cm6` + `pe` | `cr`, `rqtt`, `re`/`rvu` |

Layout Excel (inalterado): coluna **B** código, **C** funcionário, **D** data, **F** horas/quantidade. Linha 1 = cabeçalho.

## Bugs fixed

| Issue | Original | Fix |
|---|---|---|
| **Quantidade sem `:`** | `VAL("1") + VAL("1")/60` → **1.02** no subsídio de refeição | `func_parseHoras`: sem `:` usa o número; HH:MM só quando há `:` |
| **Tipo de ficheiro** | Combo = `Horas Extraordinárias`, teste = `'Horas Extra'` (depende de `SET EXACT`) | `func_codTipoFich` com `==` / `Left` / `Atc` |
| **xVars** | `Locate` + `Skip` na ordem física | `Locate For no = 1/2/3` |
| **Linha de erro** | `proc_insErr(Recno(), …)` depois de `GetUmValorString` (área de trabalho errada) | Número de linha Excel gravado em `crsFileImport.Linha` |
| **`mDescTipo`** | Não era limpo; o código da linha anterior podia “validar” a seguinte | Reiniciado em cada `Scan` |
| **Datas** | `.Text` + `CToD` (locale, coluna estreita → `#####`) | `.Value` COM: data, datetime, serial Excel, `dd/mm/yyyy`, ISO |
| **Folha Excel** | `UsedRange.Rows.Count` (falha se o intervalo não começa na linha 1); índice em vez do nome | `End(xlUp)` nas colunas B/C/D/F; picker `"2 - FolhaX"` |
| **Buracos na folha** | A primeira célula D vazia **parava** a importação | Linhas vazias são ignoradas; lê até à última linha real |
| **Excel zombie** | Sem `Quit`; `DisplayAlerts` antes de validar o COM; `Throw` sem `Catch` | `Try/Catch/Finally`, `ReadOnly`, `Quit` + `.NULL.` |
| **SQL injection / nomes** | `INSERT … '<<Nome>>'` parte em `D'Almeida` | `func_sqlLit` duplica aspas |
| **INSERT silencioso** | `u_sqlexec` `.T.` mesmo com 0 linhas | `SET NOCOUNT ON` + `@@ROWCOUNT`; rollback se 0 |
| **Falha a meio** | Registos 1–49 gravados, 50 falha | `BEGIN TRANSACTION` / `COMMIT` / `ROLLBACK` |
| **Duplicados** | Reimportar o mesmo ficheiro cria movimentos a dobrar | Cruzamento com `hs` do mês (`no`+`data`+código) |
| **Preview vs erros** | Utilizador confirma e só depois vê os erros | Erros primeiro; preview só se a validação passar |
| **Regua de inserção** | `Regua(1, mtotal, …)` sempre a 100% | `Regua(1, Recno(), …)` |

## Structure improvements

- Lookups em lote (`pe`, `hshe`/`ty`/`cm6`) com `LOCATE FOR` em vez de `GetUmValorString` por linha (cursores SPT do PHC costumam ser só de leitura, sem `INDEX`)
- Leitura Excel em bloco (`Range("B2:F n").Value`) com fallback célula-a-célula
- Datas fora do mês de processamento: aviso no preview (`crsDados.Aviso`), não bloqueiam
- `LOCAL`, restauro do alias original, `Fecha` de todos os cursores em `proc_hsImpCleanup`
- Mapeamento `INSERT … SELECT` original da `hs` mantido (factor, `diasref`, valores de refeição em `pe`)

## Drop-in notes

Still depends on PHC helpers: `Mensagem`, `GetFile`, `Getnome`, `Docomando`/`usqlvar`,
`Mostrameisto`, `Browlist`, `Fecha`, `Regua`, `u_val`, `u_sqlexec`, `Astr`, `Adec_tr`,
`DToSQL`, `Declare`/`Aadd`/`Alen`/`Release` (arrays PHC).

Requires Microsoft Excel installed (COM `Excel.Application`).

Employee active check remains `pe.status = 1` as in the original. Some PHC
installs use `inactivo = 0` instead — adjust `proc_hsImpLoadLookups` if needed.

Transactions assume `u_sqlexec` reuses the same SQL connection (normal in PHC CS).
