# Relatório de Incidências — PDF não é criado nem anexado

## Diagnóstico

O email pode ser enviado com sucesso (`mResult = 0`) **mesmo sem PDF**. Em PHC/`u_sendmailhtml`, se o ficheiro do 4.º parâmetro não existir, o anexo é normalmente ignorado e o envio continua.

A causa está quase sempre **antes** do `u_sendmailhtml`: o `IduToPdf()` não grava o ficheiro (falha silenciosa), e o código original **nunca valida** `FILE(m.FileName)` antes de enviar.

## Causas mais frequentes (por ordem)

### 1. Pasta `backup` inexistente (muito comum)

```foxpro
m.FileName = Sys(5)+Curdir()+'backup\RelatorioIncidencia.pdf'
```

Se `backup` não existir sob o `Curdir()` actual, o motor de PDF do PHC falha sem erro visível. O email segue sem anexo.

### 2. Sem verificação após `IduToPdf`

O código chama `IduToPdf(...)` e passa logo para o HTML/email. Sem:

```foxpro
If !File(m.FileName) Or Fsize(m.FileName) = 0
```

nunca se detecta a falha.

### 3. Caminho / `Curdir()` instável

`Gensqlp`, `mostrameisto` e `IduToPdf` podem alterar o directório corrente. O caminho deve ser **absoluto e fixado cedo**, e a pasta criada explicitamente:

```foxpro
m.cPdfDir = Addbs(Sys(5) + Curdir()) + 'backup'
If !Directory(m.cPdfDir)
	Md (m.cPdfDir)
EndIf
m.FileName = Forcepath('RelatorioIncidencia_' + Alltrim(Astr(u_reccli.norec)) + '.pdf', m.cPdfDir)
```

### 4. Ficheiro anterior bloqueado / 0 bytes

Se `RelatorioIncidencia.pdf` já estiver aberto (Adobe, Explorer preview) ou a geração anterior tiver ficado a 0 bytes, a nova gravação pode falhar. Apagar o ficheiro antigo (se existir) e esperar até `Fsize() > 0` antes de anexar.

### 5. Parâmetros / nome do IDU

O nome tem de coincidir **exactamente** com o IDU em manutenção:

```foxpro
mIDU = 'Relatório de Incidências (Rosto)'
```

Se o nome, aliases (`SQLTMP`, `IDUUSQLMDC`/`IDUUSQLMDL`) ou o 7.º parâmetro (`295`) não forem os esperados por esse IDU, `IduToPdf` pode não gerar ficheiro sem levantar erro. Confirmar na TECLA/rotina que já imprime este IDU com sucesso (botão PDF do ecrã).

## Correção recomendada (trecho)

Substituir o bloco desde a definição de `m.FileName` até ao envio do email pelo padrão em `prg/enviar_relatorio_incidencia_pdf_email.prg`:

1. Criar a pasta `backup` se não existir  
2. Nome de PDF único por incidência  
3. Apagar PDF antigo se existir  
4. Chamar `IduToPdf`  
5. **Só enviar email se `FILE()` e `FSIZE() > 0`**  
6. Mensagem clara se o PDF não foi gerado  

## Como validar rapidamente

Depois de `IduToPdf`, temporariamente:

```foxpro
MessageBox(m.FileName + Chr(13) + ;
	'Existe: ' + Iif(File(m.FileName), 'SIM', 'NÃO') + Chr(13) + ;
	'Tamanho: ' + Transform(Iif(File(m.FileName), Fsize(m.FileName), 0)))
```

- Se **NÃO** / tamanho 0 → problema é `IduToPdf` / pasta / IDU (não o email).  
- Se **SIM** com tamanho > 0 mas o mail vai sem anexo → problema é `u_sendmailhtml` / caminho passado no 4.º argumento.
