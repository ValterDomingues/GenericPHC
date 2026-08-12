# E-fatura — reduzir tempo de execução (limite 300)

## Why day-by-day got slower

The AT webservice caps each `obterDocumentosAdquirente` call at **300** documents. Fetching **one day at a time** avoids the cap but creates many list HTTP calls (e.g. ~30/month, ~365/year) even when most days have few invoices.

The dominant cost in the original flow is usually worse: **one `detalheDocumentoAdquirente` HTTP call per document** to scrape the IVA breakdown. For 800 docs that is ~800 detail round-trips — far heavier than the list calls.

## Recommended approach (implemented)

In `prg/efatura_compras_improved.prg`:

### 1. Adaptive date splitting (not always daily)

1. Request the **full** selected range in one call.
2. If the response has `< 300` docs → done for that range.
3. If it hits **300** and the range is longer than one day → **bisect** the range and queue both halves.
4. Repeat until every piece is under the cap (or a single day still returns 300 — warn: possible truncation).

Typical quiet month: **1 list request**. Busy month that hits 300: a handful of bisects — still far fewer than 28–31 daily calls.

### 2. Lazy IVA detail (largest win)

- List import loads **header fields only** (totals already on the list JSON).
- `detalheDocumentoAdquirente` runs only for:
  - rows the user **selected** (`pick`), after the browlist, or
  - the current row when opening **detail**.
- Optional full enrich: `func_getDocs(.T.)` or `func_enrichDocDetails(.T.)` if you truly need every line’s rate split up front.

Selecting 40 of 800 documents ⇒ ~40 detail calls instead of 800.

## Other options (if still slow)

| Option | When it helps |
|---|---|
| Shorter date filters in the UI | Fewer docs / less bisecting |
| Cache `SessionId` and reuse within the session | Avoids re-login |
| Batch supplier account lookup by distinct NIF | Less SQL if `pc` is large |
| Chilkat multi-Http / async for details | Advanced; VFP single-thread limits benefit |
| Persist last import watermark | Incremental sync instead of full period |

## What not to do

- Don’t default to day-by-day “just in case” — only split when `numElementos` / linhas ≥ 300.
- Don’t call detail for every document before the user has chosen what to book.
