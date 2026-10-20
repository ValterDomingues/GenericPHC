# Especificação técnica — Emissão de proposta como dossier interno no Cegid PHC CS

| | |
|---|---|
| Versão | 1.0 |
| Data | 2026-10-20 |
| Sistema de destino | Cegid PHC CS (gamas Advanced ou Enterprise, com PHC On) |
| Sistema de origem | Software externo de propostas |
| Instalação | Matobra |
| Documento PHC | Dossier interno do tipo Proposta |

Este documento é o contrato entre o software externo e o PHC. Os dois lados implementam as mesmas mensagens, as mesmas regras e os mesmos códigos de erro.

## 1. Objetivo

O software externo emite uma proposta na Matobra criando um dossier interno no PHC.

Antes de emitir, o software externo consulta o PHC:

1. Confirma se o contacto já existe.
2. Confirma, linha a linha, se cada artigo já existe.

O resultado dessas consultas determina o conteúdo do XML de emissão.

## 2. Âmbito

Entram neste contrato três operações:

| Código do script (`code`) | Função |
|---|---|
| `MATOBRA_CONSULTA_CONTACTO` | Procurar um contacto por NIF, email, telefone ou número interno, ou listar o catálogo |
| `MATOBRA_CONSULTA_ARTIGO` | Verificar referências de artigo ou listar as referências disponíveis |
| `MATOBRA_EMITIR_PROPOSTA` | Criar o dossier interno da proposta |

Fora de âmbito: alterar ou anular uma proposta já emitida, emitir documentos de faturação, criar artigos no catálogo e lançar movimentos de stock. O artigo em falta fica identificado na linha para análise posterior no PHC. A proposta não cria a ficha de artigo.

## 3. Canal

O software externo chama o webservice do PHC CS Web:

```text
{url da aplicação}/ws/wscript.asmx
```

Método: `RunCode`.

| Parâmetro | Conteúdo |
|---|---|
| `userName` | Utilizador técnico de integração |
| `password` | Palavra-passe desse utilizador |
| `code` | Um dos três códigos da tabela anterior |
| `parameter` | Mensagem XML desta especificação |

O valor de `parameter` chega ao programa interno do script na variável `mstamp`. O script devolve uma string. Essa string é o XML de resposta definido neste documento.

O namespace SOAP, o `SOAPAction` e o nome do elemento de resposta SOAP leem-se do WSDL publicado pela instalação (`wscript.asmx?WSDL`). O XML de negócio vai dentro de `parameter` e dentro da string devolvida, com a declaração `<?xml version="1.0" encoding="UTF-8"?>` e sem namespace XML. A ausência de namespace permite ao script PHC ler os elementos pelo nome.

Uma rejeição de negócio continua a ser uma resposta SOAP com sucesso de transporte. O insucesso vai no elemento `sucesso` do XML de negócio. Falha de autenticação, de rede ou de indisponibilidade do PHC é uma falha de transporte.

## 4. Fluxo

```text
Software externo                         PHC CS
      |                                    |
      |  MATOBRA_CONSULTA_CONTACTO         |
      |----------------------------------->|
      |  encontrado + ficha, ou vazio      |
      |<-----------------------------------|
      |                                    |
      |  MATOBRA_CONSULTA_ARTIGO           |
      |  (todas as referências da proposta)|
      |----------------------------------->|
      |  encontrado por referência         |
      |<-----------------------------------|
      |                                    |
      |  Monta o XML da proposta           |
      |  MATOBRA_EMITIR_PROPOSTA           |
      |----------------------------------->|
      |  obrano, bostamp, numero do        |
      |  contacto                          |
      |<-----------------------------------|
```

A emissão só segue depois das duas consultas. O software externo guarda `idOrigem`, `bostamp`, `ndos`, `boano`, `obrano` e o `numero` do contacto devolvido.

## 5. Contacto

A ficha de contacto no PHC CS é a tabela `cl`. A chave técnica é `cl.no` + `cl.estab`.

### 5.1 Consulta

O pedido é sempre o mesmo. Traz uma tag para cada parâmetro, pela ordem `nif`, `email`, `telefone`, `numero`, `estabelecimento` e `alteradoDesde`. A tag vai vazia quando o software externo não tem esse dado. O software externo não escolhe o critério: envia o pedido e o endpoint decide qual parâmetro usar.

```xml
<consultaContacto versao="1.0">
  <nif></nif>
  <email></email>
  <telefone></telefone>
  <numero></numero>
  <estabelecimento></estabelecimento>
  <alteradoDesde>2026-10-01T00:00:00</alteradoDesde>
</consultaContacto>
```

O endpoint escolhe um único parâmetro, nesta ordem, e ignora os restantes:

1. `numero`, quando a tag tem conteúdo. `estabelecimento` só entra neste caso. Vazio ou `0` em `estabelecimento` devolve todos os estabelecimentos desse número.
2. `nif`, quando `numero` está vazio e `nif` tem conteúdo.
3. `email`, quando os anteriores estão vazios e `email` tem conteúdo.
4. `telefone`, quando os anteriores estão vazios e `telefone` tem conteúdo.
5. Catálogo, quando as quatro tags de pesquisa estão vazias. Neste caso `alteradoDesde` é obrigatório.

| Parâmetro escolhido | Critério |
|---|---|
| `numero` | `cl.no`. Com `estabelecimento` preenchido e diferente de zero, também `cl.estab` |
| `nif` | `cl.ncont` igual ao NIF, sem espaços. Nove dígitos e dígito de controlo válido (módulo 11). `999999990` não é aceite |
| `email` | `cl.email` igual ao valor, sem espaços nas extremidades e sem distinguir maiúsculas |
| `telefone` | Os dígitos do valor coincidem com os dígitos de `cl.telefone` ou de `cl.tlmvl`. A tag tem de conter pelo menos 6 dígitos |

O valor do parâmetro escolhido é validado. Se for inválido, a resposta traz o código de erro correspondente e o endpoint não passa ao parâmetro seguinte. As outras tags, mesmo preenchidas, não entram na pesquisa. `alteradoDesde` só é lido no catálogo; numa pesquisa por `numero`, `nif`, `email` ou `telefone` o endpoint ignora essa tag.

No catálogo, a resposta inclui os contactos da tabela `cl`, ativos e inativos, cuja introdução ou última alteração é posterior a `alteradoDesde`. A comparação usa `ousrdata` com `ousrhora` para a introdução e `usrdata` com `usrhora` para a alteração. Hora em falta conta como `00:00:00`. O instante indicado fica de fora: entra o registo em que um dos dois momentos é maior do que `alteradoDesde`. A hora é local, em Lisboa, no formato `AAAA-MM-DDThh:mm:ss`, sem fuso. A primeira carga pode usar `1900-01-01T00:00:00`. Sem esta tag, ou com valor ilegível, o endpoint não devolve o catálogo.

A ordem é `numero` e `estabelecimento`. Cada ficha traz `ativo`. O elemento `total` é o número de contactos devolvidos. `encontrado` é verdadeiro quando `total` é maior que zero.

Uma pesquisa sem correspondência é um resultado válido: `sucesso=true`, `encontrado=false`, `total=0`. Não é um erro de NIF nem de número.

O nome não serve de parâmetro de pesquisa.

A resposta traz `encontrado` e `total`:

| `total` | Significado para a emissão |
|---|---|
| 0 | O contacto não existe. Na emissão o elemento `numero` fica ausente |
| 1 | O contacto existe. Na emissão seguem `numero`, `estabelecimento`, `nome`, `morada`, `codigoPostal` e `nif` devolvidos por esta consulta |
| maior que 1 | Há vários contactos. A emissão fica em espera até se escolher um `numero` e um `estabelecimento` |

Um contacto inativo (`cl.inactivo`) vem na lista com `ativo=false`, inclusive no catálogo. Esse registo não pode ser usado na emissão.

### 5.2 Emissão quando o contacto existe

O elemento `contacto/numero` é obrigatório e tem de ser o número devolvido pela consulta. `estabelecimento` repete o valor devolvido. Na omissão, o PHC usa 0.

São igualmente obrigatórios, e seguem no mesmo pedido, os valores da ficha:

- `nome`
- `morada`
- `codigoPostal`
- `nif`

O script identifica a ficha por `numero` + `estabelecimento`. O NIF enviado tem de ser o NIF dessa ficha. Nome, morada e código postal ficam gravados no cabeçalho do dossier. A ficha `cl` não é alterada por este pedido.

### 5.3 Emissão quando o contacto não existe

O elemento `numero` fica ausente. Ficam preenchidos:

- `nome`
- `morada`
- `localidade`
- `codigoPostal`
- `nif`

`localidade` é obrigatória neste caso porque a ficha de contacto do PHC guarda a localidade à parte do código postal (`cl.local` e `cl.codpost`).

O script volta a procurar o NIF imediatamente antes de criar a ficha. Se outro pedido já tiver criado esse NIF, a resposta é `CONTACTO_JA_EXISTE`, com o `numero` encontrado, e não é criado um segundo contacto. O software externo repete a emissão com esse número.

O PHC atribui `cl.no` e `cl.estab = 0`. A resposta devolve esse número em `numeroContacto`.

Um `numero` preenchido que não exista na tabela `cl` produz o erro `CONTACTO_NUMERO_INVALIDO`. A ausência do elemento é que indica criação. O valor `0` equivale a ausência.

## 6. Artigos e linhas

A ficha de artigo é a tabela `st`. A referência é `st.ref`.

### 6.1 Consulta

O pedido leva uma ou mais referências, ou vai sem referências para obter o catálogo.

O pedido de catálogo não traz nenhum elemento `referencia` com texto depois de removidos os espaços. Leva obrigatoriamente `alteradoDesde`. Servem os dois formatos:

```xml
<consultaArtigos versao="1.0">
  <alteradoDesde>2026-10-01T00:00:00</alteradoDesde>
</consultaArtigos>
```

```xml
<consultaArtigos versao="1.0">
  <referencias/>
  <alteradoDesde>2026-10-01T00:00:00</alteradoDesde>
</consultaArtigos>
```

Nesse caso a resposta lista as referências disponíveis introduzidas ou alteradas depois de `alteradoDesde`: registos de `st` com `ref` preenchida, não inativos (`st.inactivo = 0`, quando a coluna existir na instalação), em que `ousrdata`/`ousrhora` ou `usrdata`/`usrhora` é posterior ao instante pedido. Hora em falta conta como `00:00:00`. O instante indicado fica de fora. A hora é local, em Lisboa, no formato `AAAA-MM-DDThh:mm:ss`, sem fuso. A primeira carga pode usar `1900-01-01T00:00:00`. Sem `alteradoDesde`, ou com valor ilegível, o endpoint não devolve o catálogo.

A ordem é a da referência. Cada elemento `artigo` com `encontrado=true` traz a referência tal como está gravada em `st.ref`, a designação (`st.design`), a unidade, o indicador `usaLote`, o preço da tabela 1 e os dados do quadro seguinte. `G00001` entra nesta lista quando existir em `st` e cumprir o filtro. O elemento `total` indica quantas referências foram devolvidas.

| Elemento | Origem no PHC | Conteúdo |
|---|---|---|
| `referenciaFornecedor` | `st.forref` | Referência do artigo no fornecedor habitual. Vazio se a ficha não a tiver |
| `nomeFornecedor` | `fl.nome` | Nome do fornecedor habitual. O número está em `st.fornecedor` e a ficha é a da tabela `fl` com esse número e estabelecimento 0. Vazio se o artigo não tiver fornecedor habitual |
| `familia` | `st.familia` | Código da família do artigo |
| `nomeFamilia` | `st.faminome` | Designação da família |
| `subfamilia` | Coluna de `st` configurada na Matobra como subfamília | Valor da subfamília. Vazio se o artigo não a tiver |
| `marca` | Coluna de `st` configurada na Matobra como marca | Valor da marca. No PHC este título corresponde, por defeito, a `st.usr1` |

Quando o pedido traz referências, `alteradoDesde` não se envia e o endpoint não filtra por data. A comparação ignora espaços nas extremidades e maiúsculas. Cada referência pedida aparece na resposta, encontrada ou não. Uma referência em falta não é um erro da consulta.

Quando o artigo existe, a resposta inclui os mesmos elementos do quadro, com o preço de tabela aplicável ao contacto quando a consulta o puder determinar. A emissão usa a referência exata devolvida em `referencia`. Uma referência não encontrada traz só `referenciaPedida` e `encontrado=false`.

`usaLote` é verdadeiro quando a ficha do artigo está configurada para lotes.

### 6.2 Linha de artigo encontrado

| Elemento | Obrigatoriedade |
|---|---|
| `referencia` | Obrigatória. É a referência devolvida pela consulta |
| `quantidade` | Obrigatória, superior a zero |
| `preco` | Opcional. Quando vem, substitui o preço unitário. Quando fica ausente, o PHC aplica a tabela de preços do contacto |
| `desconto1` | Opcional. Percentagem de 0 a 100. Ausente significa 0 |
| `desconto2` | Opcional. Percentagem de 0 a 100. Ausente significa 0 |
| `lote` | Opcional. Só se envia quando o lote é específico e `usaLote` é verdadeiro |

A designação da linha é a da ficha do artigo. O XML não a envia neste caso.

O lote enviado tem de existir para essa referência (tabela `se`). Um lote enviado para um artigo sem controlo de lote produz `LOTE_NAO_APLICAVEL`.

### 6.3 Linha de artigo não encontrado

| Elemento | Obrigatoriedade |
|---|---|
| `referencia` | Obrigatória e fixa: `G00001` |
| `designacao` | Obrigatória. Texto livre para análise e abertura posterior da ficha no PHC |
| `quantidade` | Obrigatória, superior a zero |
| `preco`, `desconto1`, `desconto2` | Os mesmos critérios da linha de artigo encontrado |
| `lote` | Não se envia |

`G00001` é um artigo já existente no PHC, criado para linhas fora de catálogo. A emissão não cria artigos. A designação enviada fica na linha do dossier (`bi.design`) e não altera a designação genérica em `st`.

A proposta tem pelo menos uma linha e no máximo 500. A ordem das linhas no XML é a ordem no dossier.

## 7. Cabeçalho da proposta

### 7.1 Identificação

`idOrigem` é obrigatório. É o identificador do documento no software de origem, estável e único por proposta. Caracteres permitidos: letras, algarismos, ponto, hífen e sublinhado. Comprimento de 1 a 40.

### 7.2 Elementos obrigatórios

| Elemento | Conteúdo |
|---|---|
| `data` | Data da proposta, `AAAA-MM-DD`, no calendário de Lisboa |
| `responsavel/nome` | Nome da pessoa do contacto responsável pelo pedido |
| `responsavel/telefone` ou `responsavel/email` | Pelo menos um. Os dois podem vir preenchidos |
| `utilizadorAtendimento` | Nome do utilizador da tabela de atendimento interno da Matobra que emitiu a proposta |

O responsável é a pessoa do lado do contacto. O utilizador de atendimento é a pessoa da Matobra. São dados diferentes.

`utilizadorAtendimento` tem de coincidir com um nome ativo dessa tabela, sem diferenças de maiúsculas e sem espaços nas extremidades. O software externo não consulta essa tabela: envia o nome, e o PHC valida.

O telefone aceita dígitos, espaços e o prefixo `+`. O email tem de ter o formato habitual `local@dominio`.

### 7.3 Elementos opcionais

| Elemento | Conteúdo |
|---|---|
| `observacoes` | Texto livre do cabeçalho |
| `requisicao` | Número da requisição do contacto |
| `obra` | Obra a que a proposta se destina |
| `descarga` | Morada de descarga |

O grupo `descarga`, quando existe, traz:

| Elemento | Obrigatoriedade dentro do grupo |
|---|---|
| `morada` | Obrigatória |
| `codigoPostal` | Obrigatório, no formato `NNNN-NNN` |
| `localidade` | Obrigatória |
| `latitude` e `longitude` | Opcionais. Enviam-se quando o software de origem as tiver. Se uma coordenada vier, a outra é obrigatória |

Coordenadas em graus decimais WGS84, com ponto decimal. Latitude de -90 a 90. Longitude de -180 a 180. Até 6 casas decimais.

## 8. Mensagens

Os exemplos completos estão em `docs/exemplos/`. O esquema estrutural está em `docs/xsd/proposta-dossier-interno.xsd`. As regras condicionais deste texto prevalecem sobre o XSD: o XSD fixa a forma, e a secção 10 fixa quando um elemento opcional na estrutura passa a ser exigido.

### 8.1 Consulta de contacto

Pedido com NIF. As outras tags vão no mesmo pedido e ficam vazias. O endpoint usa o NIF porque `numero` está vazio:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<consultaContacto versao="1.0">
  <nif>501964843</nif>
  <email></email>
  <telefone></telefone>
  <numero></numero>
  <estabelecimento></estabelecimento>
  <alteradoDesde></alteradoDesde>
</consultaContacto>
```

Resposta quando existe um único contacto:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<consultaContactoResposta versao="1.0">
  <sucesso>true</sucesso>
  <encontrado>true</encontrado>
  <total>1</total>
  <contactos>
    <contacto>
      <numero>12045</numero>
      <estabelecimento>0</estabelecimento>
      <nome>Oficinas do Tejo Lda</nome>
      <morada>Rua das Flores 10</morada>
      <localidade>Lisboa</localidade>
      <codigoPostal>1200-001</codigoPostal>
      <nif>501964843</nif>
      <email>geral@oficinasdotejo.pt</email>
      <telefone>210000000</telefone>
      <ativo>true</ativo>
    </contacto>
  </contactos>
</consultaContactoResposta>
```

Resposta quando não existe:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<consultaContactoResposta versao="1.0">
  <sucesso>true</sucesso>
  <encontrado>false</encontrado>
  <total>0</total>
  <contactos/>
</consultaContactoResposta>
```

`sucesso=false` reserva-se para pedido inválido, por exemplo NIF mal formado, email sem `@` ou telefone com menos de 6 dígitos. Não existir contacto é um resultado válido, com `sucesso=true` e `encontrado=false`.

O mesmo pedido, com outra tag preenchida. Em cada caso o endpoint escolhe o primeiro parâmetro com conteúdo:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<consultaContacto versao="1.0">
  <nif></nif>
  <email>geral@oficinasdotejo.pt</email>
  <telefone></telefone>
  <numero></numero>
  <estabelecimento></estabelecimento>
  <alteradoDesde></alteradoDesde>
</consultaContacto>
```

```xml
<?xml version="1.0" encoding="UTF-8"?>
<consultaContacto versao="1.0">
  <nif></nif>
  <email></email>
  <telefone>+351 210 000 000</telefone>
  <numero></numero>
  <estabelecimento></estabelecimento>
  <alteradoDesde></alteradoDesde>
</consultaContacto>
```

```xml
<?xml version="1.0" encoding="UTF-8"?>
<consultaContacto versao="1.0">
  <nif></nif>
  <email></email>
  <telefone></telefone>
  <numero>12045</numero>
  <estabelecimento></estabelecimento>
  <alteradoDesde></alteradoDesde>
</consultaContacto>
```

Pedido com as tags de pesquisa vazias e `alteradoDesde` preenchido. O endpoint devolve os contactos introduzidos ou alterados depois desse instante:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<consultaContacto versao="1.0">
  <nif></nif>
  <email></email>
  <telefone></telefone>
  <numero></numero>
  <estabelecimento></estabelecimento>
  <alteradoDesde>2026-10-01T00:00:00</alteradoDesde>
</consultaContacto>
```

A resposta seguinte ilustra a forma. Na instalação, `contactos` contém as fichas introduzidas ou alteradas depois de `alteradoDesde` e `total` é o número real dessas fichas.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<consultaContactoResposta versao="1.0">
  <sucesso>true</sucesso>
  <encontrado>true</encontrado>
  <total>2</total>
  <contactos>
    <contacto>
      <numero>12045</numero>
      <estabelecimento>0</estabelecimento>
      <nome>Oficinas do Tejo Lda</nome>
      <morada>Rua das Flores 10</morada>
      <localidade>Lisboa</localidade>
      <codigoPostal>1200-001</codigoPostal>
      <nif>501964843</nif>
      <email>geral@oficinasdotejo.pt</email>
      <telefone>210000000</telefone>
      <ativo>true</ativo>
    </contacto>
    <contacto>
      <numero>12046</numero>
      <estabelecimento>0</estabelecimento>
      <nome>Nova Metalomecânica Lda</nome>
      <morada>Avenida da República 250</morada>
      <localidade>Porto</localidade>
      <codigoPostal>4000-123</codigoPostal>
      <nif>509876323</nif>
      <email>rui.costa@novametal.pt</email>
      <telefone>220000000</telefone>
      <ativo>true</ativo>
    </contacto>
  </contactos>
</consultaContactoResposta>
```

### 8.2 Consulta de artigos

```xml
<?xml version="1.0" encoding="UTF-8"?>
<consultaArtigos versao="1.0">
  <referencias>
    <referencia>MAT-100</referencia>
    <referencia>ESPECIAL-1200</referencia>
  </referencias>
</consultaArtigos>
```

```xml
<?xml version="1.0" encoding="UTF-8"?>
<consultaArtigosResposta versao="1.0">
  <sucesso>true</sucesso>
  <artigos>
    <artigo>
      <referenciaPedida>MAT-100</referenciaPedida>
      <encontrado>true</encontrado>
      <referencia>MAT-100</referencia>
      <designacao>Perfil de alumínio 40 mm</designacao>
      <unidade>MT</unidade>
      <usaLote>true</usaLote>
      <preco>15.50</preco>
      <referenciaFornecedor>FOR-100</referenciaFornecedor>
      <nomeFornecedor>Alumínios do Norte Lda</nomeFornecedor>
      <familia>PERFIL</familia>
      <nomeFamilia>Perfis de alumínio</nomeFamilia>
      <subfamilia>40MM</subfamilia>
      <marca>Matobra</marca>
    </artigo>
    <artigo>
      <referenciaPedida>ESPECIAL-1200</referenciaPedida>
      <encontrado>false</encontrado>
    </artigo>
  </artigos>
</consultaArtigosResposta>
```

A segunda referência, na emissão, vai como `G00001` com designação própria.

Pedido sem referências, para receber as referências disponíveis introduzidas ou alteradas depois de `alteradoDesde`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<consultaArtigos versao="1.0">
  <alteradoDesde>2026-10-01T00:00:00</alteradoDesde>
</consultaArtigos>
```

A resposta seguinte ilustra a forma. Na instalação, `artigos` contém as referências disponíveis que cumprem o filtro e `total` é o número real dessas fichas.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<consultaArtigosResposta versao="1.0">
  <sucesso>true</sucesso>
  <total>2</total>
  <artigos>
    <artigo>
      <referenciaPedida>G00001</referenciaPedida>
      <encontrado>true</encontrado>
      <referencia>G00001</referencia>
      <designacao>Artigo genérico para análise</designacao>
      <unidade>UN</unidade>
      <usaLote>false</usaLote>
      <preco>0</preco>
      <referenciaFornecedor></referenciaFornecedor>
      <nomeFornecedor></nomeFornecedor>
      <familia></familia>
      <nomeFamilia></nomeFamilia>
      <subfamilia></subfamilia>
      <marca></marca>
    </artigo>
    <artigo>
      <referenciaPedida>MAT-100</referenciaPedida>
      <encontrado>true</encontrado>
      <referencia>MAT-100</referencia>
      <designacao>Perfil de alumínio 40 mm</designacao>
      <unidade>MT</unidade>
      <usaLote>true</usaLote>
      <preco>15.50</preco>
      <referenciaFornecedor>FOR-100</referenciaFornecedor>
      <nomeFornecedor>Alumínios do Norte Lda</nomeFornecedor>
      <familia>PERFIL</familia>
      <nomeFamilia>Perfis de alumínio</nomeFamilia>
      <subfamilia>40MM</subfamilia>
      <marca>Matobra</marca>
    </artigo>
  </artigos>
</consultaArtigosResposta>
```

### 8.3 Emissão com contacto existente e linhas mistas

```xml
<?xml version="1.0" encoding="UTF-8"?>
<emitirProposta versao="1.0">
  <idOrigem>CRM-2026-00045</idOrigem>
  <data>2026-10-20</data>
  <contacto>
    <numero>12045</numero>
    <estabelecimento>0</estabelecimento>
    <nome>Oficinas do Tejo Lda</nome>
    <morada>Rua das Flores 10</morada>
    <localidade>Lisboa</localidade>
    <codigoPostal>1200-001</codigoPostal>
    <nif>501964843</nif>
  </contacto>
  <responsavel>
    <nome>Ana Silva</nome>
    <telefone>+351210000000</telefone>
    <email>ana.silva@oficinasdotejo.pt</email>
  </responsavel>
  <utilizadorAtendimento>João Matobra</utilizadorAtendimento>
  <observacoes>Entregar na obra até sexta.</observacoes>
  <requisicao>REQ-778</requisicao>
  <obra>OB-2026-014</obra>
  <descarga>
    <morada>Parque industrial, lote 4</morada>
    <codigoPostal>2660-021</codigoPostal>
    <localidade>Loures</localidade>
    <latitude>38.830123</latitude>
    <longitude>-9.168456</longitude>
  </descarga>
  <linhas>
    <linha>
      <referencia>MAT-100</referencia>
      <quantidade>12.5</quantidade>
      <preco>15.50</preco>
      <desconto1>10</desconto1>
      <desconto2>5</desconto2>
      <lote>L2026-01</lote>
    </linha>
    <linha>
      <referencia>G00001</referencia>
      <designacao>Suporte especial a fabricar, medida 1200x300</designacao>
      <quantidade>1</quantidade>
    </linha>
  </linhas>
</emitirProposta>
```

### 8.4 Emissão com contacto novo

A diferença está no bloco `contacto`: não existe `numero`. Os restantes elementos do cabeçalho e das linhas obedecem às mesmas regras.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<emitirProposta versao="1.0">
  <idOrigem>CRM-2026-00046</idOrigem>
  <data>2026-10-20</data>
  <contacto>
    <nome>Nova Metalomecânica Lda</nome>
    <morada>Avenida da República 250</morada>
    <localidade>Porto</localidade>
    <codigoPostal>4000-123</codigoPostal>
    <nif>509876323</nif>
  </contacto>
  <responsavel>
    <nome>Rui Costa</nome>
    <email>rui.costa@novametal.pt</email>
  </responsavel>
  <utilizadorAtendimento>João Matobra</utilizadorAtendimento>
  <linhas>
    <linha>
      <referencia>G00001</referencia>
      <designacao>Grade de proteção à medida da nave B</designacao>
      <quantidade>3</quantidade>
      <preco>480</preco>
    </linha>
  </linhas>
</emitirProposta>
```

### 8.5 Resposta da emissão

```xml
<?xml version="1.0" encoding="UTF-8"?>
<emitirPropostaResposta versao="1.0">
  <sucesso>true</sucesso>
  <idOrigem>CRM-2026-00045</idOrigem>
  <duplicado>false</duplicado>
  <contactoCriado>false</contactoCriado>
  <numeroContacto>12045</numeroContacto>
  <estabelecimento>0</estabelecimento>
  <dossier>
    <ndos>15</ndos>
    <boano>2026</boano>
    <obrano>482</obrano>
    <bostamp>BOstampaDevolverPeloPHC</bostamp>
  </dossier>
</emitirPropostaResposta>
```

`ndos` é o número interno do tipo de dossier Proposta na instalação. `obrano` é o número do documento dentro do ano `boano`. `bostamp` é o identificador interno do cabeçalho.

Resposta de erro:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<emitirPropostaResposta versao="1.0">
  <sucesso>false</sucesso>
  <idOrigem>CRM-2026-00045</idOrigem>
  <erros>
    <erro>
      <codigo>UTILIZADOR_ATENDIMENTO_INVALIDO</codigo>
      <mensagem>O utilizador de atendimento não existe na tabela interna da Matobra.</mensagem>
      <elemento>utilizadorAtendimento</elemento>
    </erro>
  </erros>
</emitirPropostaResposta>
```

Quando há vários erros de validação, a resposta inclui-os todos e o PHC não grava nada.

## 9. Mapeamento para o PHC

A gravação faz-se pelos objetos de negócio da Framework, de modo a correr numeração, preços, IVA e totais. Não se faz `INSERT` direto em `bo` ou `bi`.

Na versão instalada na Matobra, a criação do dossier usa a função de framework `criabobi` ou a classe `bizlib.boclass.boaddreg` (linhas com `AddLineRef`, fecho com `ActTotais` e `Save`). A atualização de um dossier já aberto usa `bizlib.boclass.AlterBODoc`. O padrão publicado pela Cegid para o `RunCode` é este último, aplicado a dossiers existentes.

### 9.1 Campos standard

| XML | Destino | Notas |
|---|---|---|
| `contacto/numero` | `cl.no` e `bo.no` | Ausente: o PHC numera um `cl` novo |
| `contacto/estabelecimento` | `cl.estab` e `bo.estab` | Omissão = 0 |
| `contacto/nome` | `cl.nome` na criação; `bo.nome` sempre | |
| `contacto/morada` | `cl.morada` na criação; `bo.morada` sempre | |
| `contacto/localidade` | `cl.local` na criação; `bo.local` sempre | |
| `contacto/codigoPostal` | `cl.codpost` e `bo.codpost` | Formato `NNNN-NNN` |
| `contacto/nif` | `cl.ncont` e `bo.ncont` | |
| `data` | `bo.dataobra` | |
| `observacoes` | `bo.obs` | |
| `linhas/linha/referencia` | `bi.ref` | `G00001` quando o artigo não existe |
| `linhas/linha/designacao` | `bi.design` | Só na linha `G00001` |
| `linhas/linha/quantidade` | `bi.qtt` | |
| `linhas/linha/preco` | `bi.edebito` | Preço unitário sem IVA |
| `linhas/linha/desconto1` | `bi.desconto` | Percentagem |
| `linhas/linha/desconto2` | `bi.desc2` | Percentagem |
| `linhas/linha/lote` | `bi.lote` | |

O preço enviado é sem IVA. O PHC aplica a taxa de IVA da ficha do artigo. Na linha `G00001` aplica-se a taxa configurada nesse artigo genérico. Se o tipo de dossier da Matobra estiver configurado com IVA incluído, este pressuposto tem de ser revisto antes da entrada em produção e o elemento `preco` passa a ser o preço com IVA.

### 9.2 Campos a criar na instalação

Estes dados não têm coluna standard garantida no dossier. Criam-se na configuração do dossier interno da Matobra, com o prefixo `u_`, e o script grava-os no cabeçalho:

| XML | Campo a criar | Tipo sugerido |
|---|---|---|
| `idOrigem` | `u_idorig` | Caractere (40), único, indexado |
| `responsavel/nome` | `u_respnome` | Caractere (55) |
| `responsavel/telefone` | `u_resptel` | Caractere (60) |
| `responsavel/email` | `u_respemail` | Caractere (100) |
| `utilizadorAtendimento` | `u_atend` | Caractere (55) |
| `requisicao` | `u_requis` | Caractere (40) |
| `obra` | `u_obra` | Caractere (40) |
| `descarga/morada` | Campo de morada de descarga do dossier, ou `u_descargamor` | Caractere (55) |
| `descarga/codigoPostal` | Campo de código postal de descarga, ou `u_descargacp` | Caractere (8) |
| `descarga/localidade` | Campo de localidade de descarga, ou `u_descargaloc` | Caractere (43) |
| `descarga/latitude` | `u_lat` | Numérico (9,6) |
| `descarga/longitude` | `u_lng` | Numérico (9,6) |

Se o ecrã do dossier já tiver um campo equivalente (morada de descarga, telefone, requisição), usa-se esse campo e não se cria outro. A tabela da secção 12 regista a decisão.

Comprimentos de referência do PHC CS, a confirmar no dicionário de dados da Matobra antes do desenvolvimento: `st.ref` 18, `cl.nome` e `cl.morada` 55, `cl.local` 43, `cl.codpost` 45, `cl.ncont` 20. A designação da linha `G00001` fica limitada ao tamanho real de `bi.design`.

### 9.3 Tipo de dossier e artigo genérico

O script usa o `ndos` do tipo de dossier Proposta configurado na Matobra. O software externo não escolhe o tipo.

Esse tipo de dossier não movimenta stock nem cria reservas. `G00001` existe em `st` como artigo ou serviço que pode entrar numa proposta sem existência de stock. A designação base de `G00001` no catálogo é genérica; a designação útil fica em cada linha.

## 10. Validações e códigos de erro

O script valida o pedido completo antes de gravar. A gravação do contacto novo e a gravação do dossier ocorrem na mesma transação. Se o dossier falhar, o contacto criado nesse pedido é revertido.

| Código | Situação |
|---|---|
| `XML_INVALIDO` | XML mal formado ou elemento desconhecido |
| `VERSAO_NAO_SUPORTADA` | `versao` diferente de `1.0` |
| `NIF_INVALIDO` | NIF enviado com formato inválido, dígito de controlo errado ou igual a `999999990` |
| `EMAIL_INVALIDO` | Email enviado sem `@` |
| `TELEFONE_INVALIDO` | Telefone enviado com menos de 6 dígitos |
| `CONTACTO_NUMERO_INVALIDO` | `numero` enviado e inexistente, ou contacto inativo |
| `CONTACTO_AMBIGUO` | A consulta encontrou vários registos e a emissão não identifica `numero` e `estabelecimento` |
| `CONTACTO_NIF_DIVERGENTE` | O NIF enviado não é o NIF da ficha desse `numero` |
| `CONTACTO_JA_EXISTE` | Criação recusada porque o NIF já tem ficha. A resposta inclui `numeroContacto` |
| `CONTACTO_DADOS_EM_FALTA` | Na criação falta nome, morada, localidade, código postal ou NIF |
| `CODIGO_POSTAL_INVALIDO` | Valor fora de `NNNN-NNN` |
| `ID_ORIGEM_INVALIDO` | Vazio, longo demais ou com caracteres fora do conjunto permitido |
| `ID_ORIGEM_CONFLITO` | O mesmo `idOrigem` já existe com conteúdo diferente |
| `DATA_INVALIDA` | Data ausente, ilegível ou em período fechado no PHC |
| `ALTERADO_DESDE_OBRIGATORIO` | Catálogo de contactos ou de artigos pedido sem `alteradoDesde` |
| `ALTERADO_DESDE_INVALIDO` | `alteradoDesde` ilegível ou com data inexistente |
| `RESPONSAVEL_INVALIDO` | Falta o nome, ou faltam telefone e email ao mesmo tempo |
| `UTILIZADOR_ATENDIMENTO_INVALIDO` | O nome não existe na tabela de atendimento interno |
| `ARTIGO_NAO_CATALOGADO` | A referência da linha não existe e não é `G00001` |
| `ARTIGO_GENERICO_SEM_DESCRICAO` | Linha `G00001` sem designação |
| `ARTIGO_GENERICO_INDISPONIVEL` | `G00001` não está criado no PHC |
| `QUANTIDADE_INVALIDA` | Quantidade ausente ou não positiva |
| `PRECO_INVALIDO` | Preço negativo |
| `DESCONTO_INVALIDO` | Desconto fora de 0 a 100 |
| `LOTE_INVALIDO` | O lote não existe para a referência |
| `LOTE_NAO_APLICAVEL` | Lote enviado para artigo sem lotes, ou para `G00001` |
| `LINHAS_INVALIDAS` | Zero linhas ou mais de 500 |
| `COORDENADAS_INVALIDAS` | Par incompleto ou valor fora dos limites |
| `ERRO_PHC` | A Framework recusou a gravação. A `mensagem` traz o texto devolvido pelo PHC |

Numéricos no XML usam ponto decimal e não usam separador de milhares. Quantidade até 4 casas decimais. Preço até 6. Desconto até 2.

## 11. Repetição do mesmo pedido

`idOrigem` torna a emissão idempotente.

| Situação | Resultado |
|---|---|
| Primeira receção | Cria o dossier e devolve `duplicado=false` |
| A mesma `idOrigem` com o mesmo conteúdo | Não cria outro dossier. Devolve o documento já gravado, com `duplicado=true` e `sucesso=true` |
| A mesma `idOrigem` com conteúdo diferente | `ID_ORIGEM_CONFLITO`, sem gravar |

O conteúdo comparado é o XML canónico: elementos na ordem do esquema, sem espaços entre elementos, números no formato canónico e `idOrigem` incluído. O software externo pode repetir o pedido em caso de dúvida sobre a resposta.

## 12. Parâmetros a fechar na instalação Matobra

| Parâmetro | Valor |
|---|---|
| URL de `wscript.asmx` | |
| Utilizador técnico | |
| `ndos` do dossier Proposta | |
| Nome físico da tabela de atendimento interno e coluna do nome | |
| Campo PHC usado em cada linha da secção 9.2 | |
| `G00001` criado e sem movimento de stock | |
| IVA de `G00001` | |
| Preço do XML sem IVA | Sim, salvo configuração contrária do dossier |
| Índice único em `u_idorig` | |
| Coluna de `st` usada como subfamília | |
| Coluna de `st` usada como marca | Por defeito `st.usr1`, se o título do campo na instalação for Marca |

## 13. Segurança

- O acesso ao webservice é HTTPS, limitado à rede do software externo.
- O utilizador técnico só tem as permissões de consulta de contactos e artigos e de introdução do dossier Proposta.
- O script lê o XML com analisador XML e executa SQL com parâmetros. Os valores do pedido não são concatenados em comandos SQL.
- Os registos de integração guardam `idOrigem`, o código da operação e o código de resultado. Não guardam a palavra-passe nem o XML completo quando este contenha dados pessoais além do necessário ao diagnóstico.
- As credenciais ficam no cofre do software externo, não no código-fonte.

## 14. Critério de aceitação

1. Consulta por NIF, email, telefone ou número interno existente devolve a ficha, com `numero`, `nome`, `morada`, `codigoPostal` e `nif`.
2. Consulta sem correspondência devolve `encontrado=false`. Consulta de contactos sem parâmetros, com `alteradoDesde`, devolve os contactos introduzidos ou alterados depois desse instante.
3. Consulta com referências devolve cada uma, encontrada ou não. Quando existe, a resposta inclui referência do fornecedor habitual, nome desse fornecedor, família, subfamília e marca. Consulta de artigos sem referências, com `alteradoDesde`, devolve as referências disponíveis introduzidas ou alteradas depois desse instante, com os mesmos dados.
4. Emissão com `numero` cria o dossier ligado a esse contacto e devolve `obrano` e `bostamp`.
5. Emissão sem `numero`, com nome, morada, localidade, código postal e NIF, cria a ficha e o dossier, e devolve o `numero` novo.
6. O dossier fica com data, responsável, telefone ou email, e utilizador de atendimento.
7. Observações, requisição, obra e morada de descarga, quando enviadas, aparecem no dossier, incluindo coordenadas.
8. Linha de artigo existente grava referência e quantidade. Preço, os dois descontos e o lote só aparecem quando foram enviados.
9. Linha desconhecida grava `G00001` e a designação enviada.
10. Repetir o mesmo `idOrigem` não cria um segundo dossier.
11. Utilizador de atendimento desconhecido, quantidade inválida ou `G00001` sem designação devolvem o código desta especificação e não gravam dossier.
