# Aprovação da resolução da incidência

O responsável da incidência (`u_reccli.respadm`) regista, antes do fecho, a decisão de resolução.

A decisão tem duas perguntas independentes:

1. **Devolução autorizada?** Se sim, a quantidade da referência segue um destino: **entra em stock** ou **devolve ao fornecedor**.
2. **Há lugar à emissão de nota de crédito?** Se sim, pode haver **desvalorização**. Com desvalorização, a percentagem é obrigatória. O valor creditado é o valor da linha no documento de origem (`doccl`) multiplicado por `(1 − percentagem / 100)`. Sem desvalorização, o crédito é o valor integral dessa linha.

A aprovação guarda a decisão e escreve a evolução. A emissão do documento de stock, da devolução ao fornecedor e da nota de crédito é o passo seguinte e preenche o número do documento.

## Ligações

- `u_recref.u_recclistamp` e `u_recevol.u_recclistamp` ligam à incidência `u_reccli.u_recclistamp`.
- `u_reccli.numtpre` liga ao tipo em `u_tprec.numtpre`.
- A decisão vigente de cada artigo fica em `u_recref`.
- O histórico fica em `u_recevol`. Cada gravação acrescenta uma linha; as linhas anteriores mantêm-se.
- `u_recref.doccl` continua a ser o documento de origem do cliente. O número da nota de crédito fica noutro campo.
- `u_recref.docfl` continua a ser o documento do fornecedor e passa a receber a devolução ao fornecedor.

Quando a incidência tem referências, a grelha de `u_recref` é a origem da decisão. Quando não tem referências, as mesmas perguntas gravam-se no cabeçalho.

## Campos novos

Comprimento e decimais no formato já usado nas tabelas (o comprimento do lógico é o do ecrã).

### u_tprec

| nomecampo | titulo | tipo | comprimento | decimais |
| --- | --- | --- | --- | --- |
| exaprov | Exige aprovação da resolução | L | 10 | 0 |

`exaprov` verdadeiro obriga a situação `Concluída` para fechar a incidência desse tipo.

### u_reccli

| nomecampo | titulo | tipo | comprimento | decimais |
| --- | --- | --- | --- | --- |
| sitaprov | Situação da aprovação | C | 12 | 0 |
| dtaprov | Data da aprovação | D | 10 | 0 |
| hraprov | Hora da aprovação | C | 8 | 0 |
| usraprov | Aprovado por | C | 30 | 0 |
| devaut | Devolução autorizada? | L | 10 | 0 |
| entstock | Entra em Stock | L | 10 | 0 |
| devforn | Devolve a Fornecedor | L | 10 | 0 |
| eminc | Há lugar a Nota de Crédito? | L | 10 | 0 |
| desval | Desvalorização? | L | 10 | 0 |
| percdesv | % Desvalorização | N | 6 | 2 |

`sitaprov` usa exactamente um destes valores: `Pendente`, `Parcial`, `Concluída`.

`dtaprov`, `hraprov` e `usraprov` no cabeçalho marcam o momento em que a aprovação ficou concluída. Enquanto a situação for `Pendente` ou `Parcial`, estes três campos ficam vazios.

`devaut`, `entstock`, `devforn`, `eminc`, `desval` e `percdesv` no cabeçalho só se usam quando a incidência não tem linhas em `u_recref`. Com linhas, ficam vazios e ocultos.

### u_recref

| nomecampo | titulo | tipo | comprimento | decimais |
| --- | --- | --- | --- | --- |
| devaut | Devolução autorizada? | L | 10 | 0 |
| entstock | Entra em Stock | L | 10 | 0 |
| devforn | Devolve a Fornecedor | L | 10 | 0 |
| eminc | Há lugar a Nota de Crédito? | L | 10 | 0 |
| desval | Desvalorização? | L | 10 | 0 |
| percdesv | % Desvalorização | N | 6 | 2 |
| dtaprov | Data da decisão | D | 10 | 0 |
| hraprov | Hora da decisão | C | 8 | 0 |
| usraprov | Decidido por | C | 30 | 0 |
| docstock | Documento entrada stock | C | 80 | 0 |
| docnc | Nota de crédito | C | 80 | 0 |

`dtaprov` vazio significa decisão por registar. `dtaprov` preenchido significa que as duas perguntas já foram respondidas, incluindo a resposta negativa.

`u_recevol` não leva campos novos. `operacao` (220) leva a frase da decisão. `informacao` leva o detalhe.

## As nove decisões válidas

| Devolução | Destino | Nota de crédito | Desvalorização | Efeito |
| --- | --- | --- | --- | --- |
| Não | — | Não | — | Sem movimento de material e sem crédito |
| Não | — | Sim | Não | Nota de crédito integral, sem movimento |
| Não | — | Sim | Sim, p% | Nota de crédito com desvalorização p%, sem movimento |
| Sim | Entra em stock | Não | — | Entrada em stock, sem crédito |
| Sim | Entra em stock | Sim | Não | Entrada em stock e nota de crédito integral |
| Sim | Entra em stock | Sim | Sim, p% | Entrada em stock e nota de crédito com desvalorização p% |
| Sim | Devolve ao fornecedor | Não | — | Devolução ao fornecedor, sem crédito |
| Sim | Devolve ao fornecedor | Sim | Não | Devolução ao fornecedor e nota de crédito integral |
| Sim | Devolve ao fornecedor | Sim | Sim, p% | Devolução ao fornecedor e nota de crédito com desvalorização p% |

A quantidade movimentada e a quantidade creditada são a `qtt` da referência.

## Regras do ecrã

Página **Aprovação** no ecrã da incidência.

Com referências, a grelha mostra `ref`, `design`, `qtt`, `aplicado`, `doccl`, `docfl` e os campos novos da decisão. Sem referências, o mesmo bloco de perguntas aparece no cabeçalho.

Ligação entre campos, na validação de cada controlo:

- Marcar `entstock` marca `devaut` e limpa `devforn`.
- Marcar `devforn` marca `devaut` e limpa `entstock`.
- Desmarcar `devaut` limpa `entstock` e `devforn`.
- Marcar `desval` marca `eminc`.
- Desmarcar `eminc` limpa `desval` e põe `percdesv` a 0.
- Desmarcar `desval` põe `percdesv` a 0.

Qualquer alteração a `devaut`, `entstock`, `devforn`, `eminc`, `desval` ou `percdesv` limpa `dtaprov`, `hraprov` e `usraprov` dessa linha e recalcula `sitaprov`. A evolução já gravada mantém-se. A nova frase só entra quando se carrega outra vez em **Registar decisão**.

Botões:

- **Registar decisão** — grava a linha actual, ou o cabeçalho quando não há referências.
- **Aplicar às linhas pendentes** — copia as respostas da linha actual para as linhas com `dtaprov` vazio e sem `docstock`, `docfl` e `docnc`, e regista cada uma.

Mensagens:

- Destino em falta: «A devolução autorizada tem de indicar um destino: entra em stock ou devolve ao fornecedor.»
- Dois destinos: «A devolução fica com um único destino.»
- Percentagem: «Indique a percentagem de desvalorização, entre 0,01 e 100.»
- Material aplicado, com destino preenchido, em pergunta de confirmação: «O material desta referência está marcado como aplicado. Confirme que foi retirado da obra.»
- Documento já emitido: «Esta resposta já tem documento emitido. A decisão correspondente mantém-se.»
- Incidência fechada: «A incidência está fechada. A aprovação fica só para consulta.»

Bloqueios depois de haver documento:

- `docstock` preenchido fixa `entstock`.
- `docfl` preenchido fixa `devforn`.
- `docnc` preenchido fixa `eminc`, `desval` e `percdesv`.

`respadm` é o responsável funcional. `usraprov` guarda o utilizador da sessão que carregou em **Registar decisão**, truncado a 30 caracteres. Os dois podem ser pessoas diferentes.

## Registar decisão

A gravação só avança com uma das nove decisões válidas e com a incidência aberta (`fechada` falso).

Em cada referência registada:

- `dtaprov` = data do dia
- `hraprov` = hora no formato de 8 caracteres (`hh:mm:ss`)
- `usraprov` = utilizador da sessão
- `percdesv` = 0 quando não há desvalorização

Situação do cabeçalho, contando as linhas da incidência:

- Sem linhas: `Concluída` se o cabeçalho tiver `dtaprov`; senão `Pendente`.
- Nenhuma linha decidida: `Pendente`.
- Algumas linhas decididas: `Parcial`.
- Todas as linhas decididas: `Concluída`. Nesse momento o cabeçalho recebe `dtaprov`, `hraprov` e `usraprov` desta gravação.

Fora de `Concluída`, `dtaprov`, `hraprov` e `usraprov` do cabeçalho ficam vazios. As datas de cada referência mantêm-se na própria linha.

### Evolução

Acrescentar uma linha em `u_recevol` pelo cursor filho do ecrã, para o PHC gerar `u_recevolstamp` e os campos de auditoria. Preencher:

| Campo | Valor |
| --- | --- |
| u_recclistamp | stamp da incidência |
| data | data do dia |
| hora | hora em 8 caracteres |
| ref | `u_recref.ref` (vazio na decisão de cabeçalho) |
| design | `u_recref.design` |
| respinterno | `respadm` truncado a 20; se `respadm` estiver vazio, o utilizador da sessão truncado a 20 |
| operacao | frase abaixo, no máximo 220 caracteres |
| informacao | detalhe abaixo |
| docori | vazio nesta linha |
| concluido | verdadeiro |
| comunicacao | valor interno já usado para evoluções internas; «Interna» quando a lista o aceitar |
| relatoriocliente | falso |
| relatoriofornec | falso |

Frase de `operacao`. Na primeira gravação da linha o prefixo é `Aprovação`. Quando a linha já tinha `dtaprov`, o prefixo é `Aprovação alterada`.

```
Aprovação — devolução autorizada, entra em stock; nota de crédito com desvalorização de 15,00%.
Aprovação — devolução autorizada, devolve ao fornecedor; nota de crédito integral.
Aprovação — devolução não autorizada; sem nota de crédito.
```

A frase mais longa, com o prefixo `Aprovação alterada` e 100,00%, fica abaixo de 220 caracteres.

`informacao`:

```
Referência: {ref}
Designação: {design}
Quantidade: {qtt}
Material aplicado: Sim/Não
Documento cliente: {doccl}
Devolução autorizada: Sim/Não
Destino: Entra em Stock | Devolve a Fornecedor | (vazio)
Nota de crédito: Sim/Não
Desvalorização: {percdesv}% | Não
Decidido por: {usraprov}
```

## Emissão dos documentos

Depois da decisão, a emissão preenche o número e acrescenta outra evolução, com `concluido` verdadeiro e `docori` igual aos primeiros 20 caracteres do número.

| Decisão | Documento | Número gravado em | Evolução |
| --- | --- | --- | --- |
| entstock | Entrada em stock / devolução do cliente | u_recref.docstock | Entrada em stock |
| devforn | Devolução ao fornecedor | u_recref.docfl | Devolução a fornecedor |
| eminc | Nota de crédito de cliente sobre `doccl` | u_recref.docnc | Nota de crédito |

Na nota de crédito, o valor da linha é o valor de origem vezes `(1 − percdesv / 100)`. Com `desval` falso, `percdesv` é 0 e o crédito é integral.

Na evolução da nota de crédito, `relatoriocliente` pode ficar verdadeiro quando o documento segue para o cliente. Na evolução da devolução ao fornecedor, `relatoriofornec` pode ficar verdadeiro quando o documento segue para o fornecedor. A evolução da aprovação deixa os dois relatórios em falso.

## Fecho da incidência

No tipo com `exaprov` verdadeiro, `fechada` só passa a verdadeiro quando `sitaprov` é `Concluída`.

Mensagem: «Não é possível fechar a incidência. A aprovação da resolução ainda não está concluída.»

Com `exaprov` falso, o fecho mantém a regra actual. A página de aprovação continua disponível.

Com a incidência fechada, a página fica só para consulta.

## Validação

A mesma validação serve o botão e a saída da linha na grelha. `m.lCab` verdadeiro lê e grava os campos de decisão em `u_reccli`; falso, em `u_recref`.

```foxpro
PROCEDURE aprov_valida
LPARAMETERS m.lCab
LOCAL m.lDev, m.lStock, m.lForn, m.lNc, m.lDesv, m.nPerc, m.lAplic

IF m.lCab
  m.lDev = u_reccli.devaut
  m.lStock = u_reccli.entstock
  m.lForn = u_reccli.devforn
  m.lNc = u_reccli.eminc
  m.lDesv = u_reccli.desval
  m.nPerc = u_reccli.percdesv
  m.lAplic = .F.
ELSE
  m.lDev = u_recref.devaut
  m.lStock = u_recref.entstock
  m.lForn = u_recref.devforn
  m.lNc = u_recref.eminc
  m.lDesv = u_recref.desval
  m.nPerc = u_recref.percdesv
  m.lAplic = u_recref.aplicado
ENDIF

IF u_reccli.fechada
  * A incidência está fechada. A aprovação fica só para consulta.
  RETURN .F.
ENDIF

IF m.lDev AND m.lStock AND m.lForn
  * A devolução fica com um único destino.
  RETURN .F.
ENDIF

IF m.lDev AND NOT m.lStock AND NOT m.lForn
  * A devolução autorizada tem de indicar um destino:
  * entra em stock ou devolve ao fornecedor.
  RETURN .F.
ENDIF

IF NOT m.lDev AND (m.lStock OR m.lForn)
  RETURN .F.
ENDIF

IF m.lNc AND m.lDesv AND (m.nPerc <= 0 OR m.nPerc > 100)
  * Indique a percentagem de desvalorização, entre 0,01 e 100.
  RETURN .F.
ENDIF

IF (NOT m.lNc OR NOT m.lDesv) AND m.nPerc <> 0
  RETURN .F.
ENDIF

IF NOT m.lNc AND m.lDesv
  RETURN .F.
ENDIF

IF m.lAplic AND m.lDev
  * Confirmar: o material foi retirado da obra.
ENDIF

RETURN .T.
ENDPROC
```

Frase da evolução:

```foxpro
PROCEDURE aprov_operacao
LPARAMETERS m.lAlterada, m.lDev, m.lStock, m.lForn, m.lNc, m.lDesv, m.nPerc
LOCAL m.cDest, m.cNc, m.cPref

m.cPref = IIF(m.lAlterada, "Aprovação alterada", "Aprovação")

DO CASE
CASE NOT m.lDev
  m.cDest = "devolução não autorizada"
CASE m.lStock
  m.cDest = "devolução autorizada, entra em stock"
OTHERWISE
  m.cDest = "devolução autorizada, devolve ao fornecedor"
ENDCASE

DO CASE
CASE NOT m.lNc
  m.cNc = "sem nota de crédito"
CASE m.lDesv
  m.cNc = "nota de crédito com desvalorização de " + ;
    ALLTRIM(TRANSFORM(m.nPerc, "999.99")) + "%"
OTHERWISE
  m.cNc = "nota de crédito integral"
ENDCASE

RETURN LEFT(m.cPref + " — " + m.cDest + "; " + m.cNc + ".", 220)
ENDPROC
```

## Critérios adoptados

- A devolução autorizada tem um destino, stock ou fornecedor, para a quantidade da linha.
- A nota de crédito decide-se à parte e pode existir com ou sem devolução.
- A decisão vigente fica na referência. Sem referências, fica no cabeçalho. O histórico fica na evolução.
- A aprovação regista a decisão. A emissão, no passo seguinte, grava `docstock`, `docfl` ou `docnc`.
- A quantidade aprovada é a `qtt` da referência.
- `u_tprec.exaprov` define se o fecho espera pela situação `Concluída`.
