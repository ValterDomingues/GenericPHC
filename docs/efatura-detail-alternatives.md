# E-fatura — alternatives when document detail is too slow

## Hard limit

There is **no official bulk API** for adquirente IVA line breakdown.

| Endpoint | What you get | Cost |
|---|---|---|
| `json/obterDocumentosAdquirente.action` | Headers (totals, NIF, dates…) | 1 call / date range (max 300 rows) |
| `detalheDocumentoAdquirente.action` | `dadosLinhasDocumento` (rates) | **1 HTML call / document** |

The official AT webservice/SAF-T path is for **emitters communicating sales**, not for downloading purchase details as adquirente. Scraping the portal is the only automated option for that.

So if you call detail for every document, runtime grows linearly with document count. Day-by-day listing does not fix that.

## Practical alternatives (best → optional)

### 1. Infer IVA from header totals (biggest win) — implemented

Most purchase invoices use **one VAT rate**. From the list JSON you already have:

- `valorTotalBaseTributavel`
- `valorTotalIva`
- `valorTotal`

If `IVA ≈ Base × 6%|13%|23%` (within a few cents), assign the whole base/IVA to that bucket and **skip** `detalheDocumentoAdquirente`.

Only call detail when inference fails (mixed rates, odd rounding, ambiguous extras).

Typical result: **70–95% fewer detail HTTP calls**.

See `prg/efatura_compras_fast_detail.prg` → `func_inferIvaFromHeader` + `proc_enrichPendingDocs`.

`dostamp` meanings in that routine:

- `C` = from local cache  
- `I` = inferred (no HTTP)  
- `D` = loaded via detail HTTP  

### 2. Local cache by `idDocumento`

Persist inferred/detail breakdowns in `backup/efatura_doc_cache.dbf`. Re-imports of the same period reuse cache instead of hitting the portal again.

### 3. Adaptive header fetch (not day-by-day)

Request the full range; bisect only when the response hits 300. Fewer list calls than one request per day.

### 4. Defer detail until booking (if UX allows)

List + select first; run detail/inference only for `pick=.T.`. Fastest interactive path when users book a subset.

### 5. Parallel detail HTTP (diminishing returns)

Tools like the public C# e-fatura scrapers use `Parallel.ForEach`. In VFP/Chilkat you can batch `PostUrlEncodedAsync` with several Http objects, but:

- AT may throttle / drop sessions  
- You still pay N network round-trips for mixed-rate docs  
- Complexity is high vs inference  

Use only for the **residual** docs that failed inference.

### 6. What will not help

- Official “download all purchase lines” webservice — does not exist for adquirente  
- CSV from the consumer area — still capped / incomplete for rate split in the same way  
- Calling detail “in the same day loop” — same N calls, just interleaved  

## Minimal change to your current code

Inside your `Scan For Empty(crsCompras.dostamp)` **before** building `mUrl` / `PostUrlEncoded`:

```foxpro
If func_inferIvaFromHeader()
	* already filled inc*/iva*/tx* — skip HTTP
	Loop
EndIf
* ... existing detalheDocumentoAdquirente call ...
```

Keep HTTP detail as the fallback for mixed-rate documents only.
