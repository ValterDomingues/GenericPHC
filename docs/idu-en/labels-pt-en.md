# PHC “Documentos por regularizar” — Portuguese to English

English replacements for the printed labels and letter text on the PHC IDU **Documentos por regularizar** (outstanding / overdue documents). Sample: LABQUIP IRELAND LTD, dated 11.09.2026.

Amounts, dates, document numbers, the customer name, street address and IBAN stay as on the original.

## How to apply in PHC

In the IDU of this letter, replace each hardcoded Portuguese caption with the English string below. Do not change field expressions.

To generate an English-labelled PDF from an existing printout:

```bash
python3 -m pip install -r scripts/requirements-recibo.txt
python3 scripts/translate_phc_idu_letter_labels.py \
  path/to/IduReport_pt.pdf \
  docs/idu-en/samples/IduReport_en.pdf
python3 scripts/check_idu_en_labels.py
```

## Label map

| Location | Portuguese | English |
| --- | --- | --- |
| Address / salutation | Exmo.(s) Sr.(s): / Exmo.(s) Sr(s): | Dear Sir(s): |
| Country caption | IRLANDA | IRELAND |
| Letter date | Data: | Date: |
| Subject | Assunto:Documentos por regularizar | Subject: Outstanding documents |
| Opening | Os n/ melhores cumprimentos. | Our best regards. |
| Body | Vimos informar que se encontra (m) vencida (s) a (s) nossa (s) factura (s) abaixo indicada (s). | Please be advised that the invoice(s) listed below is/are overdue. |
| Body | Lembramos que as condições de crédito oportunamente acordadas se encontram ultrapassadas. | Please note that the credit terms previously agreed have been exceeded. |
| Table header | Documento | Document |
| Table header | Número | Number |
| Table header | Data | Date |
| Table header | Vencimento | Due date |
| Table header | Valor Emissão | Issue amount |
| Table header | Valor por Regularizar | Amount outstanding |
| Table header | Idade | Age |
| Document type | N/Factura | Our Invoice |
| Document type | N/Nt. Crédito | Our Credit Note |
| Totals | Total em Falta | Balance due |
| Payment | Agradecemos o pagamento por transferência bancária para o nosso IBAN: … | Please make payment by bank transfer to our IBAN: … *(keep the IBAN)* |
| Payment | (CGD), indicando no campo referência o seu nome e número de cliente ou em alternativa envio de cheque | (CGD), quoting your name and customer number in the reference, or alternatively by cheque |
| Disclaimer | Se esta carta se tiver cruzado com o vosso pagamento, por favor não a considere. | If this letter has crossed with your payment, please disregard it. |
| Closing | Com os melhores cumprimentos | Yours faithfully |
| Sign-off | Atentamente | Yours sincerely |

## Left unchanged

- Customer: LABQUIP IRELAND LTD and the English street address
- Invoice 295 / credit note 172, dates, amounts and age (17)
- IBAN `PT50003505070069997273074` and bank short name CGD
