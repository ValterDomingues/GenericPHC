# PHC Recibo labels — Portuguese to English

English replacements for the printed labels on a PHC **Recibo** (receipt), taken from `Normal n.º 195` (2nd copy / duplicate).

Only **labels, captions and legal notices** are translated. Amounts, dates, names, addresses, ATCUD and the AT certificate number stay as on the original.

## How to apply in PHC

In **IDU** (Impressão Definida pelo Utilizador) of the Recibo layout, replace each hardcoded Portuguese caption with the English string below. Do not change field expressions (`re.ndoc`, `re.data`, `cl.ncont`, totals, ATCUD, etc.).

To generate an English-labelled PDF from an existing printout:

```bash
python3 -m pip install -r scripts/requirements-recibo.txt
python3 scripts/translate_phc_recibo_labels.py \
  path/to/recibo_pt.pdf \
  docs/recibo-en/samples/recibo_en.pdf
python3 scripts/check_recibo_en_labels.py
```

## Label map

| Location | Portuguese | English |
| --- | --- | --- |
| Title | Recibo | Receipt |
| Document number prefix | nº | No. |
| Series | Serie: | Series: |
| Copy indicator | 2.ª Via | Duplicate |
| Addressee | Exmo(a).Snr(a) | To: |
| Customer NIF | Nº de Contribuinte: | VAT No.: |
| Receipt date | Data: | Date: |
| Notes | Observações: | Remarks: |
| Preamble | Nesta data recebemos de V.Exas. o seguinte: | On this date we received from you the following: |
| Table header | Documento | Document |
| Table header | Número | Number |
| Table header | Data | Date |
| Table header | Valor regularizado | Amount settled |
| Settled document type | N/Factura | Our Invoice |
| Phone notice | (Chamada para a rede fixa nacional) | (Call to the national landline network) |
| Certified software line | Software PHC - Emitido por programa certificado nº 0006/AT | PHC Software - Issued by certified program no. 0006/AT *(keep the certificate/build suffix)* |
| Totals box | Num total de | Total amount |
| Totals box | Desc.Fin.: | Fin. disc.: |
| Amount in words | São: | Say: |
| Amount in words (value) | Vinte e Sete Mil Euros | Twenty-Seven Thousand Euros |
| Signature line | (Assinatura e Carimbo) | (Signature and Stamp) |
| Issuer NIF | Contribuinte Nº | VAT No. |
| Disclaimer | Este documento so é válido após boa cobrança. | This document is only valid after cleared payment. |
| Company tagline | Desenvolvimento e fabrico de soluções inovadoras de automação, robótica e visão artificial | Development and manufacture of innovative automation, robotics and machine vision solutions |

`Phone:`, `Fax:` and `Email:` are already English and are left unchanged.

## Left unchanged (not labels)

- Legal company name: STREAK - Engenharia em Automação, Lda.
- Addresses, postcodes and place names
- Customer name (LABQUIP NDT Limited) and address
- Document no. 195 / 2026, series 1, invoice 285, date 21.08.2026, amount 27 000,00
- Amount in words is translated when it is a known Portuguese phrase (this receipt: *Vinte e Sete Mil Euros* → Twenty-Seven Thousand Euros)
- ATCUD `J6527NC5-195` and NIF `506313387` / `218097501`
