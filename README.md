# Relatório de Incidência — PDF email fix

Diagnosis and corrected VFP routine for silent `IduToPdf` failure (email sent without PDF attachment).

## Problem

`IduToPdf` can fail silently (often because `backup\` does not exist). `u_sendmailhtml` still returns success and sends the HTML body without the attachment.

## Fix

- Create `backup` directory if missing
- Use absolute path + unique PDF filename per incidence
- Validate `FILE()` / `FSIZE()` after `IduToPdf` and abort before email if PDF was not created

See `docs/fix-relatorio-incidencia-pdf-email.md` and `prg/enviar_relatorio_incidencia_pdf_email.prg`.
