# Especificação técnica — Emissão de proposta como dossier interno no Cegid PHC CS

| | |
|---|---|
| Versão | 1.1 |
| Data | 2026-10-23 |
| Sistema de destino | Cegid PHC CS (gamas Advanced ou Enterprise, com PHC On) |
| Sistema de origem | Software externo de propostas |
| Instalação | Matobra |
| Documento PHC | Dossier interno do tipo Proposta |

Este documento é o contrato entre o software externo e o PHC. Os dois lados implementam as mesmas mensagens, as mesmas regras e os mesmos códigos de erro.

## 1. Objetivo

O software externo emite uma proposta na Matobra criando um dossier interno no PHC.

Antes de emitir, o software externo consulta o PHC:

1. Confirma se o contacto já existe. Se não existir, cria-o.
2. Confirma, linha a linha, se cada artigo já existe.

O resultado dessas consultas determina o conteúdo do XML de emissão.

## 2. Âmbito

Entram neste contrato sete operações. Cada operação é um endpoint com o seu código de script, o seu pedido e a sua resposta. A pesquisa de um registo e a lista do catálogo são endpoints diferentes.

| Código do script (`code`) | Função |
|---|---|
| `MATOBRA_CONSULTA_SESSAO` | Listar ou localizar os registos da tabela `atendimento` para mapear quem emite a proposta |
| `MATOBRA_CONSULTA_CONTACTO` | Procurar um contacto por um único critério: NIF, email, telefone ou número interno |
| `MATOBRA_CATALOGO_CONTACTOS` | Listar os contactos introduzidos ou alterados depois de um instante |
| `MATOBRA_CRIAR_CONTACTO` | Criar a ficha de um contacto que a consulta não encontrou |
| `MATOBRA_CONSULTA_ARTIGO` | Verificar uma referência de artigo |
| `MATOBRA_CATALOGO_ARTIGOS` | Listar as referências introduzidas ou alteradas depois de um instante |
| `MATOBRA_EMITIR_PROPOSTA` | Criar o dossier interno da proposta |

Fora de âmbito: alterar ou anular uma proposta já emitida, emitir documentos de faturação, alterar fichas de contacto existentes, criar artigos no catálogo e lançar movimentos de stock. O artigo em falta fica identificado na linha para análise posterior no PHC. A proposta não cria a ficha de artigo nem a ficha de contacto.

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
| `code` | Um dos sete códigos da tabela anterior |
| `parameter` | Mensagem XML desta especificação |

O valor de `parameter` chega ao programa interno do script na variável `mstamp`. O script devolve uma string. Essa string é o XML de resposta definido neste documento.

O namespace SOAP, o `SOAPAction` e o nome do elemento de resposta SOAP leem-se do WSDL publicado pela instalação (`wscript.asmx?WSDL`). O XML de negócio vai dentro de `parameter` e dentro da string devolvida, com a declaração `<?xml version="1.0" encoding="UTF-8"?>` e sem namespace XML. A ausência de namespace permite ao script PHC ler os elementos pelo nome.

Uma rejeição de negócio continua a ser uma resposta SOAP com sucesso de transporte. O insucesso vai no elemento `sucesso` do XML de negócio. Falha de autenticação, de rede ou de indisponibilidade do PHC é uma falha de transporte.

Todas as respostas têm a mesma forma: `sucesso`, os dados da operação quando `sucesso=true`, e `erros` com um ou mais elementos `erro` quando `sucesso=false`. Cada `erro` tem `codigo`, `mensagem` e, quando se aplica, `elemento` com o caminho do elemento do pedido que causou o erro.

## 4. Fluxo

```text
Software externo                         PHC CS
      |                                    |
      |  MATOBRA_CONSULTA_SESSAO           |
      |  (credenciais da plataforma)       |
      |----------------------------------->|
      |  registos de atendimento           |
      |<-----------------------------------|
      |                                    |
      |  Mapeia a pessoa da área reservada |
      |                                    |
      |  MATOBRA_CONSULTA_CONTACTO         |
      |  (um critério)                     |
      |----------------------------------->|
      |  encontrado + ficha, ou vazio      |
      |<-----------------------------------|
      |                                    |
      |  Se vazio:                         |
      |  MATOBRA_CRIAR_CONTACTO            |
      |----------------------------------->|
      |  numero do contacto novo           |
      |<-----------------------------------|
      |                                    |
      |  MATOBRA_CONSULTA_ARTIGO           |
      |  (uma referência por pedido)       |
      |----------------------------------->|
      |  encontrado + ficha, ou vazio      |
      |<-----------------------------------|
      |                                    |
      |  Monta o XML da proposta           |
      |  MATOBRA_EMITIR_PROPOSTA           |
      |----------------------------------->|
      |  obrano, bostamp                   |
      |<-----------------------------------|
```

A consulta de sessão autentica-se com as credenciais da plataforma e devolve a base da tabela `atendimento`. A plataforma associa a pessoa da área reservada a um desses registos, por email, telemóvel, iniciais ou nome. A emissão usa o `numero` desse registo. A consulta de sessão pode ser feita no acesso à área reservada e reutilizada enquanto a base não mudar.

Os catálogos (`MATOBRA_CATALOGO_CONTACTOS` e `MATOBRA_CATALOGO_ARTIGOS`) ficam fora do fluxo de uma proposta. Servem para a plataforma manter uma cópia local dos contactos e dos artigos, carregada uma vez e atualizada por sincronização incremental. Com essa cópia, a plataforma pode resolver o contacto e os artigos localmente e chamar as consultas unitárias só para confirmar antes de emitir.

A emissão da proposta exige sempre o `numero` do contacto. Esse número vem da consulta ou da criação. O software externo guarda `idOrigem`, `bostamp`, `ndos`, `boano`, `obrano`, o `numero` do contacto e o `numero` de atendimento.

## 5. Contacto

A ficha de contacto no PHC CS é a tabela `cl`. A chave técnica é `cl.no` + `cl.estab`.

### 5.1 Consulta de um contacto

Endpoint `MATOBRA_CONSULTA_CONTACTO`. Pedido `consultaContacto`. Resposta `consultaContactoResposta`.

O pedido traz uma tag para cada critério, pela ordem `nif`, `email`, `telefone`, `numero` e `estabelecimento`. Exatamente uma das quatro tags de pesquisa tem conteúdo. As restantes vão vazias.

```xml
<consultaContacto versao="1.0">
  <nif>501964843</nif>
  <email></email>
  <telefone></telefone>
  <numero></numero>
  <estabelecimento></estabelecimento>
</consultaContacto>
```

| Critério | Regra |
|---|---|
| `numero` | `cl.no`. Com `estabelecimento` preenchido e diferente de zero, também `cl.estab`. Vazio ou `0` em `estabelecimento` devolve todos os estabelecimentos desse número |
| `nif` | `cl.ncont` igual ao NIF, sem espaços. Nove dígitos e dígito de controlo válido (módulo 11). `999999990` não é aceite |
| `email` | `cl.email` igual ao valor, sem espaços nas extremidades e sem distinguir maiúsculas |
| `telefone` | Os dígitos do valor coincidem com os dígitos de `cl.telefone` ou de `cl.tlmvl`. A tag tem de conter pelo menos 6 dígitos |

`estabelecimento` só acompanha `numero`. Não conta como critério de pesquisa.

O endpoint recusa o pedido nestes casos, sem pesquisar:

| Situação | Código |
|---|---|
| As quatro tags de pesquisa estão vazias | `CONTACTO_PARAMETRO_OBRIGATORIO` |
| Mais do que uma tag de pesquisa tem conteúdo | `CONTACTO_INFORMACAO_REDUNDANTE` |
| `estabelecimento` tem conteúdo e `numero` está vazio | `CONTACTO_INFORMACAO_REDUNDANTE` |
| O critério enviado tem valor inválido | `NIF_INVALIDO`, `EMAIL_INVALIDO`, `TELEFONE_INVALIDO` ou `CONTACTO_NUMERO_INVALIDO` |

O nome e a designação não servem de critério de pesquisa. Não existe pesquisa por catálogo neste endpoint: para isso existe `MATOBRA_CATALOGO_CONTACTOS`.

A resposta traz `encontrado`, `total` e a lista `contactos`. A ordem é `numero` e `estabelecimento`. Cada ficha traz `numero`, `estabelecimento`, `nome`, `morada`, `localidade`, `codigoPostal`, `nif`, `email`, `telefone` e `ativo`.

Uma pesquisa sem correspondência é um resultado válido: `sucesso=true`, `encontrado=false`, `total=0`. Não é um erro de NIF nem de número.

| `total` | Significado para a emissão |
|---|---|
| 0 | O contacto não existe. A plataforma chama `MATOBRA_CRIAR_CONTACTO` antes de emitir |
| 1 | O contacto existe. Na emissão seguem `numero`, `estabelecimento`, `nome`, `morada`, `codigoPostal` e `nif` devolvidos por esta consulta |
| maior que 1 | Há vários contactos. A plataforma escolhe um `numero` e um `estabelecimento` antes de emitir |

Um contacto inativo (`cl.inactivo`) vem na lista com `ativo=false`. Esse registo não pode ser usado na emissão.

### 5.2 Catálogo de contactos

Endpoint `MATOBRA_CATALOGO_CONTACTOS`. Pedido `catalogoContactos`. Resposta `catalogoContactosResposta`.

O pedido tem um único elemento, `alteradoDesde`, obrigatório:

```xml
<catalogoContactos versao="1.0">
  <alteradoDesde>2026-10-01T00:00:00</alteradoDesde>
</catalogoContactos>
```

A resposta inclui os contactos da tabela `cl`, ativos e inativos, cuja introdução ou última alteração é posterior a `alteradoDesde`. A comparação usa `ousrdata` com `ousrhora` para a introdução e `usrdata` com `usrhora` para a alteração. Hora em falta conta como `00:00:00`. O instante indicado fica de fora: entra o registo em que um dos dois momentos é maior do que `alteradoDesde`. A hora é local, em Lisboa, no formato `AAAA-MM-DDThh:mm:ss`, sem fuso. A primeira carga pode usar `1900-01-01T00:00:00`.

Sem `alteradoDesde` a resposta é `ALTERADO_DESDE_OBRIGATORIO`. Com valor ilegível é `ALTERADO_DESDE_INVALIDO`.

A ordem é `numero` e `estabelecimento`. Cada ficha tem os mesmos elementos da consulta unitária, incluindo `ativo`. O elemento `total` é o número de contactos devolvidos. Uma lista vazia é um resultado válido, com `total=0`.

### 5.3 Criação de um contacto

Endpoint `MATOBRA_CRIAR_CONTACTO`. Pedido `criarContacto`. Resposta `criarContactoResposta`.

A plataforma chama este endpoint quando a consulta devolveu `total=0`. A emissão da proposta não cria contactos.

| Elemento | Obrigatoriedade |
|---|---|
| `nome` | Obrigatório |
| `morada` | Obrigatória |
| `localidade` | Obrigatória. A ficha do PHC guarda a localidade à parte do código postal (`cl.local` e `cl.codpost`) |
| `codigoPostal` | Obrigatório, no formato `NNNN-NNN` |
| `nif` | Obrigatório. Nove dígitos e dígito de controlo válido. `999999990` não é aceite |
| `email` | Opcional. Formato `local@dominio` |
| `telefone` | Opcional. Pelo menos 6 dígitos |

```xml
<criarContacto versao="1.0">
  <nome>Nova Metalomecânica Lda</nome>
  <morada>Avenida da República 250</morada>
  <localidade>Porto</localidade>
  <codigoPostal>4000-123</codigoPostal>
  <nif>509876323</nif>
  <email>rui.costa@novametal.pt</email>
  <telefone>220000000</telefone>
</criarContacto>
```

O script procura o NIF imediatamente antes de criar a ficha. Se já existir uma ficha com esse NIF, a resposta é `CONTACTO_JA_EXISTE`, com `numero` e `estabelecimento` dessa ficha, e não é criado um segundo contacto. A plataforma usa esse número na emissão. Esta verificação cobre o caso em que dois pedidos tentam criar o mesmo contacto ao mesmo tempo.

O PHC atribui `cl.no` e `cl.estab = 0`. A gravação faz-se pelo objeto de negócio da ficha de cliente, para correr numeração e valores por omissão. A resposta devolve `numero` e `estabelecimento`.

A criação não tem identificador de origem. A chave natural é o NIF: repetir o pedido com o mesmo NIF devolve `CONTACTO_JA_EXISTE` com o número já atribuído, e a plataforma segue com esse número.

### 5.4 Contacto na emissão

O elemento `contacto/numero` é obrigatório e tem de ser o número devolvido pela consulta ou pela criação. `estabelecimento` repete o valor devolvido. Na omissão, o PHC usa 0.

São igualmente obrigatórios, e seguem no mesmo pedido, os valores da ficha:

- `nome`
- `morada`
- `codigoPostal`
- `nif`

`localidade` é opcional na emissão. Quando vem, fica no cabeçalho do dossier.

O script identifica a ficha por `numero` + `estabelecimento`. O NIF enviado tem de ser o NIF dessa ficha. Nome, morada, localidade e código postal ficam gravados no cabeçalho do dossier. A ficha `cl` não é alterada por este pedido.

Um `numero` ausente, igual a `0`, inexistente em `cl` ou de um contacto inativo produz `CONTACTO_NUMERO_INVALIDO`. A emissão não cria contactos.

## 6. Artigos e linhas

A ficha de artigo é a tabela `st`. A referência é `st.ref`.

### 6.1 Consulta de um artigo

Endpoint `MATOBRA_CONSULTA_ARTIGO`. Pedido `consultaArtigo`. Resposta `consultaArtigoResposta`.

O pedido traz uma referência. A referência é o único critério de pesquisa. A designação, a família, a marca e o fornecedor não servem de critério.

```xml
<consultaArtigo versao="1.0">
  <referencia>MAT-100</referencia>
</consultaArtigo>
```

O endpoint recusa o pedido nestes casos, sem pesquisar:

| Situação | Código |
|---|---|
| `referencia` ausente ou vazia depois de removidos os espaços | `ARTIGO_REFERENCIA_OBRIGATORIA` |
| Mais do que um elemento `referencia` | `ARTIGO_INFORMACAO_REDUNDANTE` |

A comparação com `st.ref` ignora espaços nas extremidades e maiúsculas. Não existe pesquisa por catálogo neste endpoint: para isso existe `MATOBRA_CATALOGO_ARTIGOS`.

A resposta traz `encontrado`, `total` e a lista `artigos`. Quando o artigo existe, `total=1` e o elemento `artigo` traz:

| Elemento | Origem no PHC | Conteúdo |
|---|---|---|
| `referencia` | `st.ref` | Referência tal como está gravada. A emissão usa este valor |
| `designacao` | `st.design` | Designação do artigo |
| `unidade` | `st.unidade` | Unidade de venda |
| `usaLote` | `st.usalote` | Verdadeiro quando a ficha está configurada para lotes |
| `preco` | `st.epv1` | Preço da tabela 1, ou o preço de tabela aplicável ao contacto quando a consulta o puder determinar |
| `referenciaFornecedor` | `st.forref` | Referência do artigo no fornecedor habitual. Vazio se a ficha não a tiver |
| `nomeFornecedor` | `fl.nome` | Nome do fornecedor habitual. O número está em `st.fornecedor` e a ficha é a da tabela `fl` com esse número e estabelecimento 0. Vazio se o artigo não tiver fornecedor habitual |
| `numeroFornecedor` | `st.fornecedor` | Número do fornecedor habitual. Zero ou vazio quando o artigo não tem fornecedor habitual. É a chave para agrupar a taxa energética |
| `familia` | `st.familia` | Código da família do artigo |
| `nomeFamilia` | `st.faminome` | Designação da família |
| `subfamilia` | `st.usr2` | Subfamília do artigo. Vazio se a ficha não a tiver |
| `marca` | `st.usr1` | Marca do artigo. Vazio se a ficha não a tiver |

Uma referência sem correspondência é um resultado válido: `sucesso=true`, `encontrado=false`, `total=0`, lista `artigos` vazia. Não é um erro da consulta. Na emissão, essa linha vai como `G00001` com designação própria.

### 6.2 Catálogo de artigos

Endpoint `MATOBRA_CATALOGO_ARTIGOS`. Pedido `catalogoArtigos`. Resposta `catalogoArtigosResposta`.

O pedido tem um único elemento, `alteradoDesde`, obrigatório:

```xml
<catalogoArtigos versao="1.0">
  <alteradoDesde>2026-10-01T00:00:00</alteradoDesde>
</catalogoArtigos>
```

A resposta lista as referências disponíveis introduzidas ou alteradas depois de `alteradoDesde`: registos de `st` com `ref` preenchida, não inativos (`st.inactivo = 0`, quando a coluna existir na instalação), em que `ousrdata`/`ousrhora` ou `usrdata`/`usrhora` é posterior ao instante pedido. Hora em falta conta como `00:00:00`. O instante indicado fica de fora. A hora é local, em Lisboa, no formato `AAAA-MM-DDThh:mm:ss`, sem fuso. A primeira carga pode usar `1900-01-01T00:00:00`.

Sem `alteradoDesde` a resposta é `ALTERADO_DESDE_OBRIGATORIO`. Com valor ilegível é `ALTERADO_DESDE_INVALIDO`.

A ordem é a da referência. Cada elemento `artigo` tem os mesmos elementos da consulta unitária. `G00001` e `TXENERG` entram nesta lista quando existirem em `st` e cumprirem o filtro. O elemento `total` indica quantas referências foram devolvidas. Uma lista vazia é um resultado válido, com `total=0`.

### 6.3 Linha de artigo encontrado

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

### 6.4 Linha de artigo não encontrado

| Elemento | Obrigatoriedade |
|---|---|
| `referencia` | Obrigatória e fixa: `G00001` |
| `designacao` | Obrigatória. Texto livre para análise e abertura posterior da ficha no PHC |
| `quantidade` | Obrigatória, superior a zero |
| `preco`, `desconto1`, `desconto2` | Os mesmos critérios da linha de artigo encontrado |
| `lote` | Não se envia |

`G00001` é um artigo já existente no PHC, criado para linhas fora de catálogo. A emissão não cria artigos. A designação enviada fica na linha do dossier (`bi.design`) e não altera a designação genérica em `st`.

### 6.5 Taxa energética

Quando o fornecedor habitual de um artigo tem uma taxa energética, a proposta leva uma linha dessa taxa. A plataforma calcula a linha. O PHC grava-a como as restantes.

Cada taxa está associada ao número do fornecedor habitual (`numeroFornecedor`, `st.fornecedor`) e tem:

| Campo | Conteúdo |
|---|---|
| `descricao` | Texto da taxa. Passa a ser a designação da linha |
| `tipo` | `EUR_M2` ou `PERCENTAGEM` |
| `valor` | Decimal com 2 casas. Em `EUR_M2` é euros por m2. Em `PERCENTAGEM` é a percentagem |

Um fornecedor pode ter várias taxas. Cada taxa produz no máximo uma linha, com a referência fixa `TXENERG`. `TXENERG` existe em `st`, sem movimento de stock, como `G00001`. A designação genérica de `TXENERG` não é usada: a linha leva a `descricao` da taxa. Não leva lote nem descontos.

Entram na base de cálculo as linhas de artigo de catálogo desse fornecedor. Ficam de fora as linhas `G00001`, as linhas `TXENERG` e os artigos sem fornecedor habitual.

O montante de uma linha de artigo é `quantidade × preco × (1 − desconto1 / 100) × (1 − desconto2 / 100)`, arredondado para 2 casas, metade para cima. O preço é o que a linha envia. Se a linha não enviar preço, usa-se o preço devolvido pela consulta do artigo.

| Tipo | Base | Linha `TXENERG` |
|---|---|---|
| `EUR_M2` | Soma das quantidades dos artigos desse fornecedor cuja unidade, sem espaços e sem distinguir maiúsculas, é `M2` | `quantidade` = essa soma; `preco` = `valor` |
| `PERCENTAGEM` | Soma dos montantes em euros das referências desse fornecedor | `quantidade` = 1; `preco` = base × `valor` / 100, arredondado para 2 casas |

A linha só é adicionada quando a base é maior que zero e, no tipo `PERCENTAGEM`, o preço calculado é maior que zero. As linhas `TXENERG` ficam depois das linhas de artigo, ordenadas pelo número do fornecedor e, dentro deste, pela descrição da taxa.

Exemplo. O artigo `MAT-100` do fornecedor 100 tem unidade `M2`, quantidade 12,5, preço 15,50, desconto 1 de 10% e desconto 2 de 5%. O montante da linha é 165,66 euros. Uma taxa `EUR_M2` de 1,50 euros com a descrição «Taxa energética de revestimento» gera:

```xml
<linha>
  <referencia>TXENERG</referencia>
  <designacao>Taxa energética de revestimento</designacao>
  <quantidade>12.5</quantidade>
  <preco>1.50</preco>
</linha>
```

Uma taxa `PERCENTAGEM` de 2,50 sobre o mesmo montante gera uma linha `TXENERG` com quantidade 1 e preço 4,14.

A proposta tem pelo menos uma linha e no máximo 500. A ordem das linhas no XML é a ordem no dossier.

## 7. Cabeçalho da proposta

### 7.1 Identificação

`idOrigem` é obrigatório. É o identificador do documento no software de origem, estável e único por proposta. Caracteres permitidos: letras, algarismos, ponto, hífen e sublinhado. Comprimento de 1 a 40.

### 7.2 Elementos obrigatórios

| Elemento | Conteúdo |
|---|---|
| `data` | Data da proposta no software de origem, `AAAA-MM-DD`, no calendário de Lisboa. Fica em `bo.dataopen` |
| `responsavel/nome` | Nome da pessoa do contacto responsável pelo pedido |
| `responsavel/telefone` ou `responsavel/email` | Pelo menos um. Os dois podem vir preenchidos |
| `atendimento/numero` | Número do registo da tabela `atendimento` da pessoa da Matobra que emite a proposta |

A data do dossier (`bo.dataobra`) é sempre a data do sistema no momento em que o PHC grava a proposta. O software externo não a escolhe. A data enviada em `data` fica guardada em `bo.dataopen` e identifica a data da proposta no software de origem. `data` tem de ser uma data válida; não pode ser posterior à data do sistema.

O responsável é a pessoa do lado do contacto. O atendimento é a pessoa da Matobra. São dados diferentes.

`atendimento/numero` tem de ser um `numero` devolvido pela consulta de sessão. O endpoint confirma-o na tabela `atendimento` e grava no dossier o número e o nome desse registo. A plataforma não envia o nome livre.

O telefone aceita dígitos, espaços e o prefixo `+`. O email tem de ter o formato habitual `local@dominio`.

### 7.3 Consulta de sessão

A plataforma externa autentica-se com as credenciais de integração e chama `MATOBRA_CONSULTA_SESSAO`. O pedido é sempre o mesmo e tem uma tag por coluna da tabela `atendimento`: `numero`, `nome`, `iniciais`, `telemovel` e `email`. A tag vai vazia quando não é usada como filtro. O endpoint escolhe um único critério e ignora os restantes:

1. `numero`, quando tem conteúdo.
2. `email`, quando `numero` está vazio e `email` tem conteúdo.
3. `telemovel`, quando os anteriores estão vazios e `telemovel` tem conteúdo. A comparação usa só os dígitos e exige pelo menos 6.
4. `iniciais`, quando os anteriores estão vazios e `iniciais` tem conteúdo. A comparação ignora maiúsculas e espaços nas extremidades.
5. `nome`, quando os anteriores estão vazios e `nome` tem conteúdo. A comparação ignora maiúsculas e espaços nas extremidades.
6. A base completa, quando as cinco tags estão vazias.

```xml
<consultaSessao versao="1.0">
  <numero></numero>
  <nome></nome>
  <iniciais></iniciais>
  <telemovel></telemovel>
  <email></email>
</consultaSessao>
```

A resposta traz os registos disponíveis para preencher o atendimento da proposta. Cada registo tem `numero`, `nome`, `iniciais`, `telemovel` e `email`. Estes cinco dados são a base de mapeamento para a área reservada da pessoa que emite a proposta: a plataforma associa a sua conta ao registo com o mesmo email, telemóvel, iniciais ou nome e guarda o `numero` para a emissão.

A tabela no PHC chama-se `atendimento`. As colunas são `numero`, `nome`, `iniciais`, `telemovel` e `email`. Uma pesquisa sem correspondência devolve `sucesso=true`, `total=0` e a lista vazia. Um valor inválido no critério escolhido devolve o erro e o endpoint não passa ao critério seguinte.

### 7.4 Elementos opcionais

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

Cada endpoint tem o seu elemento raiz de pedido e de resposta:

| Endpoint | Pedido | Resposta | Exemplos |
|---|---|---|---|
| `MATOBRA_CONSULTA_SESSAO` | `consultaSessao` | `consultaSessaoResposta` | `consulta-sessao-*.xml` |
| `MATOBRA_CONSULTA_CONTACTO` | `consultaContacto` | `consultaContactoResposta` | `consulta-contacto-*.xml` |
| `MATOBRA_CATALOGO_CONTACTOS` | `catalogoContactos` | `catalogoContactosResposta` | `catalogo-contactos-*.xml` |
| `MATOBRA_CRIAR_CONTACTO` | `criarContacto` | `criarContactoResposta` | `criar-contacto-*.xml` |
| `MATOBRA_CONSULTA_ARTIGO` | `consultaArtigo` | `consultaArtigoResposta` | `consulta-artigo-*.xml` |
| `MATOBRA_CATALOGO_ARTIGOS` | `catalogoArtigos` | `catalogoArtigosResposta` | `catalogo-artigos-*.xml` |
| `MATOBRA_EMITIR_PROPOSTA` | `emitirProposta` | `emitirPropostaResposta` | `emitir-proposta-*.xml` |

### 8.1 Consulta de sessão

Pedido da base completa, para mapear a área reservada:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<consultaSessao versao="1.0">
  <numero></numero>
  <nome></nome>
  <iniciais></iniciais>
  <telemovel></telemovel>
  <email></email>
</consultaSessao>
```

Pedido pelo email da pessoa que está na área reservada. O endpoint usa o email porque `numero` está vazio:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<consultaSessao versao="1.0">
  <numero></numero>
  <nome></nome>
  <iniciais></iniciais>
  <telemovel></telemovel>
  <email>joao.matobra@matobra.pt</email>
</consultaSessao>
```

```xml
<?xml version="1.0" encoding="UTF-8"?>
<consultaSessaoResposta versao="1.0">
  <sucesso>true</sucesso>
  <total>1</total>
  <atendimentos>
    <atendimento>
      <numero>12</numero>
      <nome>João Matobra</nome>
      <iniciais>JM</iniciais>
      <telemovel>910000000</telemovel>
      <email>joao.matobra@matobra.pt</email>
    </atendimento>
  </atendimentos>
</consultaSessaoResposta>
```

A emissão envia `<atendimento><numero>12</numero></atendimento>`.

### 8.2 Consulta de um contacto

Pedido com NIF. As outras tags vão no mesmo pedido e ficam vazias:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<consultaContacto versao="1.0">
  <nif>501964843</nif>
  <email></email>
  <telefone></telefone>
  <numero></numero>
  <estabelecimento></estabelecimento>
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

Os mesmos pedidos por email, telefone e número interno. Em cada um, só uma tag de pesquisa tem conteúdo:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<consultaContacto versao="1.0">
  <nif></nif>
  <email>geral@oficinasdotejo.pt</email>
  <telefone></telefone>
  <numero></numero>
  <estabelecimento></estabelecimento>
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
</consultaContacto>
```

```xml
<?xml version="1.0" encoding="UTF-8"?>
<consultaContacto versao="1.0">
  <nif></nif>
  <email></email>
  <telefone></telefone>
  <numero>12045</numero>
  <estabelecimento>0</estabelecimento>
</consultaContacto>
```

Pedido com NIF e email ao mesmo tempo. O endpoint não pesquisa:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<consultaContacto versao="1.0">
  <nif>501964843</nif>
  <email>geral@oficinasdotejo.pt</email>
  <telefone></telefone>
  <numero></numero>
  <estabelecimento></estabelecimento>
</consultaContacto>
```

```xml
<?xml version="1.0" encoding="UTF-8"?>
<consultaContactoResposta versao="1.0">
  <sucesso>false</sucesso>
  <erros>
    <erro>
      <codigo>CONTACTO_INFORMACAO_REDUNDANTE</codigo>
      <mensagem>O pedido traz mais do que um critério de pesquisa. Preencha apenas nif, email, telefone ou numero.</mensagem>
      <elemento>consultaContacto</elemento>
    </erro>
  </erros>
</consultaContactoResposta>
```

### 8.3 Catálogo de contactos

```xml
<?xml version="1.0" encoding="UTF-8"?>
<catalogoContactos versao="1.0">
  <alteradoDesde>2026-10-01T00:00:00</alteradoDesde>
</catalogoContactos>
```

A resposta seguinte ilustra a forma. Na instalação, `contactos` contém as fichas introduzidas ou alteradas depois de `alteradoDesde` e `total` é o número real dessas fichas.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<catalogoContactosResposta versao="1.0">
  <sucesso>true</sucesso>
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
</catalogoContactosResposta>
```

### 8.4 Criação de um contacto

```xml
<?xml version="1.0" encoding="UTF-8"?>
<criarContacto versao="1.0">
  <nome>Nova Metalomecânica Lda</nome>
  <morada>Avenida da República 250</morada>
  <localidade>Porto</localidade>
  <codigoPostal>4000-123</codigoPostal>
  <nif>509876323</nif>
  <email>rui.costa@novametal.pt</email>
  <telefone>220000000</telefone>
</criarContacto>
```

```xml
<?xml version="1.0" encoding="UTF-8"?>
<criarContactoResposta versao="1.0">
  <sucesso>true</sucesso>
  <numero>12046</numero>
  <estabelecimento>0</estabelecimento>
</criarContactoResposta>
```

Resposta quando o NIF já tem ficha. A plataforma usa o número devolvido:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<criarContactoResposta versao="1.0">
  <sucesso>false</sucesso>
  <numero>12046</numero>
  <estabelecimento>0</estabelecimento>
  <erros>
    <erro>
      <codigo>CONTACTO_JA_EXISTE</codigo>
      <mensagem>Já existe um contacto com o NIF 509876323.</mensagem>
      <elemento>nif</elemento>
    </erro>
  </erros>
</criarContactoResposta>
```

### 8.5 Consulta de um artigo

```xml
<?xml version="1.0" encoding="UTF-8"?>
<consultaArtigo versao="1.0">
  <referencia>MAT-100</referencia>
</consultaArtigo>
```

Resposta quando o artigo existe:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<consultaArtigoResposta versao="1.0">
  <sucesso>true</sucesso>
  <encontrado>true</encontrado>
  <total>1</total>
  <artigos>
    <artigo>
      <referencia>MAT-100</referencia>
      <designacao>Perfil de alumínio 40 mm</designacao>
      <unidade>M2</unidade>
      <usaLote>true</usaLote>
      <preco>15.50</preco>
      <referenciaFornecedor>FOR-100</referenciaFornecedor>
      <nomeFornecedor>Alumínios do Norte Lda</nomeFornecedor>
      <numeroFornecedor>100</numeroFornecedor>
      <familia>PERFIL</familia>
      <nomeFamilia>Perfis de alumínio</nomeFamilia>
      <subfamilia>40MM</subfamilia>
      <marca>Matobra</marca>
    </artigo>
  </artigos>
</consultaArtigoResposta>
```

Resposta quando não existe. Na emissão, essa linha vai como `G00001` com designação própria:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<consultaArtigoResposta versao="1.0">
  <sucesso>true</sucesso>
  <encontrado>false</encontrado>
  <total>0</total>
  <artigos/>
</consultaArtigoResposta>
```

Pedido com duas referências. O endpoint não pesquisa:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<consultaArtigo versao="1.0">
  <referencia>MAT-100</referencia>
  <referencia>ESPECIAL-1200</referencia>
</consultaArtigo>
```

```xml
<?xml version="1.0" encoding="UTF-8"?>
<consultaArtigoResposta versao="1.0">
  <sucesso>false</sucesso>
  <erros>
    <erro>
      <codigo>ARTIGO_INFORMACAO_REDUNDANTE</codigo>
      <mensagem>O pedido traz mais do que uma referência. Envie uma referência por pedido.</mensagem>
      <elemento>consultaArtigo</elemento>
    </erro>
  </erros>
</consultaArtigoResposta>
```

### 8.6 Catálogo de artigos

```xml
<?xml version="1.0" encoding="UTF-8"?>
<catalogoArtigos versao="1.0">
  <alteradoDesde>2026-10-01T00:00:00</alteradoDesde>
</catalogoArtigos>
```

A resposta seguinte ilustra a forma. Na instalação, `artigos` contém as referências disponíveis que cumprem o filtro e `total` é o número real dessas fichas.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<catalogoArtigosResposta versao="1.0">
  <sucesso>true</sucesso>
  <total>2</total>
  <artigos>
    <artigo>
      <referencia>G00001</referencia>
      <designacao>Artigo genérico para análise</designacao>
      <unidade>UN</unidade>
      <usaLote>false</usaLote>
      <preco>0</preco>
      <referenciaFornecedor></referenciaFornecedor>
      <nomeFornecedor></nomeFornecedor>
      <numeroFornecedor>0</numeroFornecedor>
      <familia></familia>
      <nomeFamilia></nomeFamilia>
      <subfamilia></subfamilia>
      <marca></marca>
    </artigo>
    <artigo>
      <referencia>MAT-100</referencia>
      <designacao>Perfil de alumínio 40 mm</designacao>
      <unidade>M2</unidade>
      <usaLote>true</usaLote>
      <preco>15.50</preco>
      <referenciaFornecedor>FOR-100</referenciaFornecedor>
      <nomeFornecedor>Alumínios do Norte Lda</nomeFornecedor>
      <numeroFornecedor>100</numeroFornecedor>
      <familia>PERFIL</familia>
      <nomeFamilia>Perfis de alumínio</nomeFamilia>
      <subfamilia>40MM</subfamilia>
      <marca>Matobra</marca>
    </artigo>
  </artigos>
</catalogoArtigosResposta>
```

### 8.7 Emissão da proposta

Contacto existente, cabeçalho completo e linhas mistas:

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
  <atendimento>
    <numero>12</numero>
  </atendimento>
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
    <linha>
      <referencia>TXENERG</referencia>
      <designacao>Taxa energética de revestimento</designacao>
      <quantidade>12.5</quantidade>
      <preco>1.50</preco>
    </linha>
  </linhas>
</emitirProposta>
```

Contacto acabado de criar pela secção 8.4 e cabeçalho mínimo. O bloco `contacto` leva o `numero` devolvido pela criação:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<emitirProposta versao="1.0">
  <idOrigem>CRM-2026-00046</idOrigem>
  <data>2026-10-20</data>
  <contacto>
    <numero>12046</numero>
    <estabelecimento>0</estabelecimento>
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
  <atendimento>
    <numero>12</numero>
  </atendimento>
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

### 8.8 Resposta da emissão

```xml
<?xml version="1.0" encoding="UTF-8"?>
<emitirPropostaResposta versao="1.0">
  <sucesso>true</sucesso>
  <idOrigem>CRM-2026-00045</idOrigem>
  <duplicado>false</duplicado>
  <numeroContacto>12045</numeroContacto>
  <estabelecimento>0</estabelecimento>
  <dossier>
    <ndos>15</ndos>
    <boano>2026</boano>
    <obrano>482</obrano>
    <dataDossier>2026-10-23</dataDossier>
    <bostamp>BOstampaDevolverPeloPHC</bostamp>
  </dossier>
</emitirPropostaResposta>
```

`ndos` é o número interno do tipo de dossier Proposta na instalação. `obrano` é o número do documento dentro do ano `boano`. `dataDossier` é a data do sistema com que o PHC gravou o dossier (`bo.dataobra`). `bostamp` é o identificador interno do cabeçalho.

Resposta de erro:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<emitirPropostaResposta versao="1.0">
  <sucesso>false</sucesso>
  <idOrigem>CRM-2026-00045</idOrigem>
  <erros>
    <erro>
      <codigo>UTILIZADOR_ATENDIMENTO_INVALIDO</codigo>
      <mensagem>O número de atendimento não existe na tabela atendimento.</mensagem>
      <elemento>atendimento/numero</elemento>
    </erro>
  </erros>
</emitirPropostaResposta>
```

Quando há vários erros de validação, a resposta inclui-os todos e o PHC não grava nada.

## 9. Mapeamento para o PHC

A gravação faz-se pelos objetos de negócio da Framework, de modo a correr numeração, preços, IVA e totais. Não se faz `INSERT` direto em `cl`, `bo` ou `bi`.

Na versão instalada na Matobra, a criação do dossier usa a função de framework `criabobi` ou a classe `bizlib.boclass.boaddreg` (linhas com `AddLineRef`, fecho com `ActTotais` e `Save`). A atualização de um dossier já aberto usa `bizlib.boclass.AlterBODoc`. O padrão publicado pela Cegid para o `RunCode` é este último, aplicado a dossiers existentes. A criação da ficha de cliente usa o objeto de negócio de `cl`.

### 9.1 Criação de contacto

| XML | Destino | Notas |
|---|---|---|
| `nome` | `cl.nome` | |
| `morada` | `cl.morada` | |
| `localidade` | `cl.local` | |
| `codigoPostal` | `cl.codpost` | Formato `NNNN-NNN` |
| `nif` | `cl.ncont` | Único na instalação |
| `email` | `cl.email` | Opcional |
| `telefone` | `cl.telefone` | Opcional |
| — | `cl.no` | Atribuído pelo PHC e devolvido em `numero` |
| — | `cl.estab` | 0 |

### 9.2 Emissão: campos standard

| XML | Destino | Notas |
|---|---|---|
| `contacto/numero` | `bo.no` | Obrigatório. Tem de existir em `cl` |
| `contacto/estabelecimento` | `bo.estab` | Omissão = 0 |
| `contacto/nome` | `bo.nome` | |
| `contacto/morada` | `bo.morada` | |
| `contacto/localidade` | `bo.local` | Quando enviada |
| `contacto/codigoPostal` | `bo.codpost` | Formato `NNNN-NNN` |
| `contacto/nif` | `bo.ncont` | |
| `data` | `bo.dataopen` | Data da proposta no software de origem |
| — | `bo.dataobra` | Data do sistema no momento da gravação. Devolvida em `dataDossier` |
| `observacoes` | `bo.obs` | |
| `linhas/linha/referencia` | `bi.ref` | `G00001` quando o artigo não existe; `TXENERG` na taxa energética |
| `linhas/linha/designacao` | `bi.design` | Só nas linhas `G00001` e `TXENERG` |
| `linhas/linha/quantidade` | `bi.qtt` | |
| `linhas/linha/preco` | `bi.edebito` | Preço unitário sem IVA |
| `linhas/linha/desconto1` | `bi.desconto` | Percentagem |
| `linhas/linha/desconto2` | `bi.desc2` | Percentagem |
| `linhas/linha/lote` | `bi.lote` | |

O preço enviado é sem IVA. O PHC aplica a taxa de IVA da ficha do artigo. Nas linhas `G00001` e `TXENERG` aplica-se a taxa configurada nesse artigo. Se o tipo de dossier da Matobra estiver configurado com IVA incluído, este pressuposto tem de ser revisto antes da entrada em produção e o elemento `preco` passa a ser o preço com IVA.

### 9.3 Emissão: campos a criar na instalação

Estes dados não têm coluna standard garantida no dossier. Criam-se na configuração do dossier interno da Matobra, com o prefixo `u_`, e o script grava-os no cabeçalho:

| XML | Campo a criar | Tipo sugerido |
|---|---|---|
| `idOrigem` | `u_idorig` | Caractere (40), único, indexado |
| `responsavel/nome` | `u_respnome` | Caractere (55) |
| `responsavel/telefone` | `u_resptel` | Caractere (60) |
| `responsavel/email` | `u_respemail` | Caractere (100) |
| `atendimento/numero` | `u_atendno` | Numérico. Chave do registo em `atendimento` |
| `atendimento/nome` | `u_atend` | Caractere (55). O endpoint copia `atendimento.nome` no momento da gravação. A plataforma não o envia |
| `requisicao` | `u_requis` | Caractere (40) |
| `obra` | `u_obra` | Caractere (40) |
| `descarga/morada` | Campo de morada de descarga do dossier, ou `u_descargamor` | Caractere (55) |
| `descarga/codigoPostal` | Campo de código postal de descarga, ou `u_descargacp` | Caractere (8) |
| `descarga/localidade` | Campo de localidade de descarga, ou `u_descargaloc` | Caractere (43) |
| `descarga/latitude` | `u_lat` | Numérico (9,6) |
| `descarga/longitude` | `u_lng` | Numérico (9,6) |

Se o ecrã do dossier já tiver um campo equivalente (morada de descarga, telefone, requisição), usa-se esse campo e não se cria outro. A tabela da secção 12 regista a decisão.

Comprimentos de referência do PHC CS, a confirmar no dicionário de dados da Matobra antes do desenvolvimento: `st.ref` 18, `cl.nome` e `cl.morada` 55, `cl.local` 43, `cl.codpost` 45, `cl.ncont` 20. A designação das linhas `G00001` e `TXENERG` fica limitada ao tamanho real de `bi.design`.

### 9.4 Tipo de dossier e artigos genéricos

O script usa o `ndos` do tipo de dossier Proposta configurado na Matobra. O software externo não escolhe o tipo.

Esse tipo de dossier não movimenta stock nem cria reservas. `G00001` e `TXENERG` existem em `st` como artigos ou serviços que podem entrar numa proposta sem existência de stock. A designação base destes artigos no catálogo é genérica; a designação útil fica em cada linha.

## 10. Validações e códigos de erro

Cada endpoint valida o pedido completo antes de executar. Na emissão, a gravação do dossier é uma transação: se uma linha falhar, nada fica gravado. A criação do contacto é um pedido à parte e não é revertida por uma emissão que falhe depois.

| Código | Endpoint | Situação |
|---|---|---|
| `XML_INVALIDO` | Todos | XML mal formado, elemento raiz errado para o endpoint ou elemento desconhecido |
| `VERSAO_NAO_SUPORTADA` | Todos | `versao` diferente de `1.0` |
| `NIF_INVALIDO` | Consulta, criação e emissão | NIF enviado com formato inválido, dígito de controlo errado ou igual a `999999990` |
| `EMAIL_INVALIDO` | Consulta, criação e emissão | Email enviado sem `@` |
| `TELEFONE_INVALIDO` | Consulta, criação e emissão | Telefone enviado com menos de 6 dígitos |
| `CONTACTO_PARAMETRO_OBRIGATORIO` | Consulta de contacto | As tags `nif`, `email`, `telefone` e `numero` estão todas vazias |
| `CONTACTO_INFORMACAO_REDUNDANTE` | Consulta de contacto | Mais do que uma tag de pesquisa com conteúdo, ou `estabelecimento` sem `numero` |
| `CONTACTO_NUMERO_INVALIDO` | Consulta de contacto e emissão | Na consulta, `numero` não numérico. Na emissão, `numero` ausente, `0`, inexistente em `cl` ou de contacto inativo |
| `CONTACTO_NIF_DIVERGENTE` | Emissão | O NIF enviado não é o NIF da ficha desse `numero` |
| `CONTACTO_JA_EXISTE` | Criação de contacto | O NIF já tem ficha. A resposta inclui `numero` e `estabelecimento` |
| `CONTACTO_DADOS_EM_FALTA` | Criação de contacto | Falta nome, morada, localidade, código postal ou NIF |
| `CODIGO_POSTAL_INVALIDO` | Criação e emissão | Valor fora de `NNNN-NNN` |
| `ALTERADO_DESDE_OBRIGATORIO` | Catálogos | Pedido sem `alteradoDesde` |
| `ALTERADO_DESDE_INVALIDO` | Catálogos | `alteradoDesde` ilegível ou com data inexistente |
| `ARTIGO_REFERENCIA_OBRIGATORIA` | Consulta de artigo | `referencia` ausente ou vazia |
| `ARTIGO_INFORMACAO_REDUNDANTE` | Consulta de artigo | Mais do que um elemento `referencia` no pedido |
| `ID_ORIGEM_INVALIDO` | Emissão | Vazio, longo demais ou com caracteres fora do conjunto permitido |
| `ID_ORIGEM_CONFLITO` | Emissão | O mesmo `idOrigem` já existe com conteúdo diferente |
| `DATA_INVALIDA` | Emissão | `data` ausente, ilegível, inexistente no calendário ou posterior à data do sistema |
| `RESPONSAVEL_INVALIDO` | Emissão | Falta o nome, ou faltam telefone e email ao mesmo tempo |
| `UTILIZADOR_ATENDIMENTO_INVALIDO` | Emissão | `atendimento/numero` não existe na tabela `atendimento` |
| `ARTIGO_NAO_CATALOGADO` | Emissão | A referência da linha não existe e não é `G00001` nem `TXENERG` |
| `ARTIGO_GENERICO_SEM_DESCRICAO` | Emissão | Linha `G00001` ou `TXENERG` sem designação |
| `ARTIGO_GENERICO_INDISPONIVEL` | Emissão | `G00001` ou `TXENERG` não está criado no PHC |
| `QUANTIDADE_INVALIDA` | Emissão | Quantidade ausente ou não positiva |
| `PRECO_INVALIDO` | Emissão | Preço negativo |
| `DESCONTO_INVALIDO` | Emissão | Desconto fora de 0 a 100 |
| `LOTE_INVALIDO` | Emissão | O lote não existe para a referência |
| `LOTE_NAO_APLICAVEL` | Emissão | Lote enviado para artigo sem lotes, para `G00001` ou para `TXENERG` |
| `LINHAS_INVALIDAS` | Emissão | Zero linhas ou mais de 500 |
| `COORDENADAS_INVALIDAS` | Emissão | Par incompleto ou valor fora dos limites |
| `ERRO_PHC` | Criação e emissão | A Framework recusou a gravação. A `mensagem` traz o texto devolvido pelo PHC |

Numéricos no XML usam ponto decimal e não usam separador de milhares. Quantidade até 4 casas decimais. Preço até 6. Desconto até 2.

## 11. Repetição do mesmo pedido

`idOrigem` torna a emissão idempotente.

| Situação | Resultado |
|---|---|
| Primeira receção | Cria o dossier e devolve `duplicado=false` |
| A mesma `idOrigem` com o mesmo conteúdo | Não cria outro dossier. Devolve o documento já gravado, com `duplicado=true` e `sucesso=true` |
| A mesma `idOrigem` com conteúdo diferente | `ID_ORIGEM_CONFLITO`, sem gravar |

O conteúdo comparado é o XML canónico: elementos na ordem do esquema, sem espaços entre elementos, números no formato canónico e `idOrigem` incluído. O software externo pode repetir o pedido em caso de dúvida sobre a resposta.

A criação de contacto é idempotente pelo NIF: a repetição devolve `CONTACTO_JA_EXISTE` com o número já atribuído.

## 12. Parâmetros a fechar na instalação Matobra

| Parâmetro | Valor |
|---|---|
| URL de `wscript.asmx` | |
| Utilizador técnico | |
| `ndos` do dossier Proposta | |
| Nome físico da tabela de atendimento interno e coluna do nome | Tabela `atendimento`, colunas `numero`, `nome`, `iniciais`, `telemovel` e `email` |
| Campo PHC usado em cada linha da secção 9.3 | |
| `G00001` criado e sem movimento de stock | |
| `TXENERG` criado e sem movimento de stock | |
| IVA de `G00001` e de `TXENERG` | |
| Preço do XML sem IVA | Sim, salvo configuração contrária do dossier |
| Índice único em `u_idorig` | |
| `bo.dataopen` disponível no tipo de dossier Proposta | |

## 13. Segurança

- O acesso ao webservice é HTTPS, limitado à rede do software externo.
- O utilizador técnico só tem as permissões de consulta de contactos e artigos, de introdução de fichas de cliente e de introdução do dossier Proposta.
- O script lê o XML com analisador XML e executa SQL com parâmetros. Os valores do pedido não são concatenados em comandos SQL.
- Os registos de integração guardam `idOrigem`, o código da operação e o código de resultado. Não guardam a palavra-passe nem o XML completo quando este contenha dados pessoais além do necessário ao diagnóstico.
- As credenciais ficam no cofre do software externo, não no código-fonte.

## 14. Critério de aceitação

1. Consulta de contacto por NIF, email, telefone ou número interno existente devolve a ficha, com `numero`, `nome`, `morada`, `codigoPostal` e `nif`.
2. Consulta de contacto sem correspondência devolve `encontrado=false`. Consulta com mais do que um critério devolve `CONTACTO_INFORMACAO_REDUNDANTE`. Consulta sem critério devolve `CONTACTO_PARAMETRO_OBRIGATORIO`.
3. Catálogo de contactos com `alteradoDesde` devolve os contactos introduzidos ou alterados depois desse instante. Sem `alteradoDesde` devolve `ALTERADO_DESDE_OBRIGATORIO`.
4. Criação de contacto com nome, morada, localidade, código postal e NIF cria a ficha e devolve o `numero` novo. Repetir com o mesmo NIF devolve `CONTACTO_JA_EXISTE` com esse número.
5. Consulta de artigo com uma referência existente devolve a ficha, com referência do fornecedor habitual, nome e número desse fornecedor, família, subfamília e marca. Referência inexistente devolve `encontrado=false`. Mais do que uma referência devolve `ARTIGO_INFORMACAO_REDUNDANTE`.
6. Catálogo de artigos com `alteradoDesde` devolve as referências disponíveis introduzidas ou alteradas depois desse instante, com os mesmos dados.
7. Emissão com `numero` válido cria o dossier ligado a esse contacto e devolve `obrano`, `bostamp` e `dataDossier`.
8. Emissão sem `numero`, ou com `numero` inexistente, devolve `CONTACTO_NUMERO_INVALIDO` e não cria contacto nem dossier.
9. O dossier fica com `bo.dataobra` igual à data do sistema, `bo.dataopen` igual à `data` enviada, responsável, telefone ou email, e o número e o nome do registo de atendimento.
10. Observações, requisição, obra e morada de descarga, quando enviadas, aparecem no dossier, incluindo coordenadas.
11. Linha de artigo existente grava referência e quantidade. Preço, os dois descontos e o lote só aparecem quando foram enviados.
12. Linha desconhecida grava `G00001` e a designação enviada. Linha de taxa energética grava `TXENERG`, a descrição da taxa e o valor calculado.
13. Repetir o mesmo `idOrigem` não cria um segundo dossier.
14. Atendimento desconhecido, quantidade inválida ou `G00001` ou `TXENERG` sem designação devolvem o código desta especificação e não gravam dossier.
15. A consulta de sessão devolve `numero`, `nome`, `iniciais`, `telemovel` e `email`. Com todas as tags vazias devolve a base completa da tabela `atendimento`.
