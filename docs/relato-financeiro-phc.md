# Relato financeiro no ERP PHC — fluxos, entradas, saídas e relatórios

Lista de referência dos elementos associados ao **relato financeiro** na Solução Financeira do PHC CS / Cegid PHC Contabilidade (e módulos complementares). O foco é o caminho dos dados: de onde entram, como são processados e o que sai (mapas, ficheiros, obrigações).

Fontes principais: descritivo oficial *PHC CS Solução Financeira*, documentação Cegid PHC Contabilidade e Help Center PHC GO (Demonstração de Fluxos de Caixa).

---

## 1. Âmbito e módulos

| Módulo | Papel no relato financeiro |
| --- | --- |
| **PHC Contabilidade CS** | Núcleo: plano de contas, diários, movimentos, balancetes, apuramentos, mapas oficiais, SAF-T Contabilidade |
| **PHC Gestão CS** (integração) | Origem operacional: faturação, compras, recebimentos, pagamentos, tesouraria, reconciliação bancária |
| **PHC Imobilizado CS** | Ativos, amortizações/depreciações, reavaliações, imparidades, abates → integração na contabilidade |
| **PHC Pessoal CS** | Remunerações, retenções IRS/IRC, imposto de selo (quando integrado) |
| **PHC Letras CS** | Títulos de dívida a receber/pagar; impacto em tesouraria e contabilidade |
| **PHC Consolidação CS** | Integração de saldos entre sociedades, ajustamentos, DF consolidadas |
| **PHC InterOp CS** | Execução multi-empresa: mapas, IVA, balancetes, integrações, calendário fiscal |
| **PHC Dashboard CS** | Indicadores, pesos de contas/centros, comparativos anuais |
| **PHC dContabilidade CS** | Consulta/lançamento remoto (balancetes, diários, extratos, movimentos) |
| **Add-on Fluxos de Caixa** (PHC GO / store) | Demonstração de fluxos de caixa a partir de códigos de tesouraria |

---

## 2. Visão geral dos fluxos de dados

```text
[Gestão / RH / Imobilizado / Letras / Importações]
        │  integração online ou batch
        ▼
[Contabilidade: diários + documentos + linhas]
        │  tempo real (sem “atualização” intermédia)
        ▼
[Apuramentos: IVA · CMVMC · resultados · imposto de selo]
        │
        ├──► Mapas de gestão / DF / balancetes / extratos
        ├──► Monitor de Obrigações Declarativas
        ├──► Ficheiros AT (SAF-T, IES, M22, M30, anexos IVA, …)
        └──► Dashboard / exportações / consolidados
```

Características transversais:

- Contabilidade em **tempo real**: após gravar o movimento, balancetes e mapas já refletem o valor.
- Até **17 meses contabilísticos** acessíveis sem fecho obrigatório do mês.
- Proteção por **utilizador / data fechada**.
- Multi-empresa: uma BD e arquivo por empresa.

---

## 3. Entradas (inputs)

### 3.1 Parametrização de base

| Entrada | Descrição |
| --- | --- |
| Plano de contas (SNC / taxonomias) | Estrutura de contas; grelha de transição entre exercícios |
| Diários | Regras (ex.: débito = crédito), documento pré-definido, numeração |
| Documentos pré-definidos | Modelos de lançamento ligados às contas habituais |
| Centros de custo / chaves de imputação | Contabilidade analítica; reflexões em cascata |
| Orçamentos | Abertura a partir do ano anterior; comparação real vs orçamentado |
| Códigos de tesouraria (fluxos de caixa) | Ex.: R10001 recebimentos clientes, P10001 pagamentos fornecedores, … |
| Tabelas fiscais / células de mapas | Fórmulas IES, Declaração Periódica IVA, mapas de gestão |
| Acessos e data fechada | Quem pode lançar/alterar e até que data |

### 3.2 Movimentos operacionais (via Gestão / outros módulos)

Integração típica **Gestão → Contabilidade** (e vice-versa, quando online):

| Origem | Exemplos de documentos integrados |
| --- | --- |
| Vendas / faturação | Faturas, notas de crédito/débito, auto-faturação |
| Compras | Faturas de fornecedor, despesas |
| Contas correntes | Recibos de clientes, pagamentos a fornecedores |
| Tesouraria | Depósitos, movimentos de caixa, transferências conta–caixa / conta–conta |
| Reconciliação bancária | Estado reconciliado repercutido na contabilidade (com Gestão) |
| Pessoal | Ordenados / retenções (integração com Contabilidade) |
| Imobilizado | Depreciações, reavaliações, imparidades, revalorizações, abates |
| Letras | Emissão, desconto, cobrança, reforma, imposto de selo do título |
| Bases exteriores | Importação para gabinetes / grupos (integração de BD exteriores) |
| Monitor de dados / SAF-T | Importação de clientes, fornecedores, produtos, plano de contas |

### 3.3 Lançamentos manuais na Contabilidade

- Introdução tipo folha de cálculo (sem rato, duplicação, defaults).
- Documentos pré-definidos e numeração sequencial.
- Movimentos diretos de consolidação / ajustamentos particulares.
- Inventário final de existências (para apuramento CMVMC / variação de produção).

### 3.4 Parâmetros de produção de mapas / DF

| Parâmetro | Uso típico |
| --- | --- |
| Exercício / período inicial–final | Balancetes, DF, fluxos de caixa |
| Conta inicial / conta final | Filtro de balancete |
| Ver só contas de razão / com saldo / sem movimento | Análise de balancete |
| Excluir contas de movimento | Balancete |
| IVA não dedutível | Foco fiscal no balancete |
| Dimensões analíticas / centro de custo | Segmentação de mapas e fluxos de caixa |
| Sociedade(s) a consolidar | Consolidação / InterOp |

---

## 4. Processamento interno (transformações)

| Processo | Entrada principal | Resultado |
| --- | --- | --- |
| Integração documental | Docs Gestão/RH/Imobilizado/Letras | Movimentos a débito/crédito nos diários |
| Apuramento de IVA | Movimentos com IVA | Simulação ou lançamento; Declaração Periódica / Anual; extrato por célula |
| Reembolso de IVA | DP IVA | Anexos: relação clientes, fornecedores, sujeitos passivos (regularizações) |
| CMVMC / variação de produção | Inventário final por conta de existências | Lançamentos automáticos de apuramento |
| Apuramento de resultados | Contas de custos e proveitos | Saldo por contrapartida de resultados (global ou por centro de custo) |
| Imposto de selo | Movimentos / letras / (opcional) Pessoal | Simulação e suporte informático; retenções se Pessoal |
| Reconciliação | Extrato bancário + movimentos | Mapas reconciliados / não reconciliados |
| Transição de exercício | Plano antigo + saldos | Saldos iniciais no novo plano (SNC) |
| Consolidação | Saldos das sociedades | Integração total/proporcional, equivalência patrimonial, ajustamentos |
| Demonstração de fluxos de caixa | Saldos por código de tesouraria (+ contas 11/12/13, diferenças cambiais) | Mapa DFC (Ano N e N-1) |

---

## 5. Saídas (outputs)

### 5.1 Relatórios e mapas de gestão (consulta / impressão / exportação)

| Relatório / mapa | Notas |
| --- | --- |
| **Balancete contabilístico** | Débitos, créditos, saldos; filtros por período/conta; contas de razão; só com saldo; IVA não dedutível |
| **Balancete de contas por período** | Agrupado por exercício entre período inicial e final (PHC GO) |
| **Diários** | Listagens por diário / análise de diários |
| **Extrato de conta** | Evolução de uma conta (ficha da conta: movimentos, datas, saldos, gráficos) |
| **Mapas de movimentos contabilísticos** | Detalhe de lançamentos |
| **Balanço** | Demonstração financeira; notas às DF |
| **Demonstração de resultados** | Anual, ano anterior, desvio (€ / %); por centro de custo |
| **Demonstração de fluxos de caixa** | Operacionais / investimento / financiamento; códigos de tesouraria |
| **Notas às demonstrações financeiras** | Ligação anexo ↔ DF; apoio ao IES |
| **Mapas de gestão parametrizáveis** | Editor tipo folha de cálculo (fórmulas = valores de contas) |
| **Mapas recapitulativos** | Clientes/fornecedores por valor movimentado; exportação AT |
| **Livros selados** | Via InterOp / obrigações |
| **Mapas orçamentais** | Real vs orçamento; desvios por centro |
| **DF consolidadas** | Balanço e DR consolidados; balancetes/extratos/diários consolidados |
| **Dashboard Contabilidade** | Contas, pesos, centros analíticos, matriz de contas, comparativos |
| **Dashboard Letras** | Títulos por estado, vencimento, banco, centro, série |

### 5.2 Obrigações declarativas e ficheiros oficiais

Agrupadas tipicamente no **Monitor de Obrigações Declarativas** (atualizar, imprimir, instruções):

| Saída | Formato / destino |
| --- | --- |
| Declaração Periódica de IVA | Impressão / suporte; extrato por célula |
| Declaração Anual de IVA | Idem |
| Anexos reembolso IVA | Relação clientes / fornecedores / sujeitos passivos |
| **SAF-T PT Contabilidade** | Ficheiro auditoria; analisador/validador |
| **SAF-T PT Auto-faturação** | Ficheiro auditoria |
| **IES** | Eletrónico; fórmulas editáveis por célula |
| **Modelo 22** | Eletrónico / Internet |
| **Modelo 30** | Eletrónico (rendimentos de não residentes, etc.) |
| **Modelo 31 / 32** | Com módulo Imobilizado |
| Imposto de selo | Suportes informáticos |
| Mapas recapitulativos AT | Exportação |

### 5.3 Saídas do Imobilizado (impacto no relato)

| Saída | Descrição |
| --- | --- |
| Processamento de depreciações | Fiscal e contabilística; integração na Contabilidade |
| Histórico do ativo | Depreciações, reavaliações, imparidades, revalorizações |
| Mapas legais / oficiais | Impressão parametrizável |
| Inventário físico | Contagens, faltas e excessos |
| Etiquetas de identificação | Controlo patrimonial |
| Modelos 31/32 | Quando aplicável |

### 5.4 Saídas multi-empresa (InterOp)

- Monitor de mapas a imprimir (por empresa / mapa)
- Monitor de processamentos e relatório
- Produção de suportes informáticos em lote
- Agenda / calendário fiscal / tarefas agendadas
- Cópia de impressões e parâmetros entre sociedades

### 5.5 Canais de saída

| Canal | Exemplos |
| --- | --- |
| Ecrã / PDF / impressora | Balancetes, DF, extratos |
| Exportação ficheiro | Excel/CSV (conforme mapa), anexos AT, SAF-T XML |
| Envio Internet / WebService | IES, M22, M30; documentos (PHC On) |
| Email | Relatórios custom (rotinas VFP / scripts do projeto) |
| dContabilidade / web | Consulta e lançamento remoto |
| Histórico de emissões DFC | Registo de produção do mapa (add-on) |

---

## 6. Demonstração de Fluxos de Caixa — detalhe de entrada/saída

A DFC é calculada sobretudo a partir de **códigos de tesouraria** (saldos acumulados). Resumo:

| Bloco | Exemplos de códigos | Conteúdo |
| --- | --- | --- |
| Atividades operacionais | R10001, P10001, P10002, P10003, R10002, P10004, R10003 | Clientes, fornecedores, pessoal, IRC, outros |
| Atividades de investimento | P20001–P20004, R20001–R20007 | Ativos tangíveis/intangíveis, investimentos, juros, subsídios |
| Atividades de financiamento | R30001–R30005, P30001–P30005 | Financiamentos, capital, juros, reduções de capital |
| Caixa e equivalentes | Contas **11, 12, 13** | Saldo abertura vs fim de período |
| Diferenças de câmbio | Contas 6863, 6887, 692, 7861, 7887, 793 | Efeito cambial (sinal negativo acumulado) |

Ano N-1 usa as mesmas fórmulas no período anterior.

---

## 7. Objetos de dados típicos (orientação técnica PHC CS)

Nomes e uso variam por versão/gama; lista orientadora para análise SQL / integrações:

| Área | Tabelas / objetos habituais (exemplos) | Conteúdo |
| --- | --- | --- |
| Contabilidade | Plano de contas, diários, cabeçalhos e linhas de movimento | CC / diários / documentos / linhas a débito-crédito |
| Analítica | Centros de custo, imputações | Dimensão analítica dos movimentos |
| Gestão (origem) | Faturação, linhas, contas correntes, tesouraria | FT/FL, CL, recibos, pagamentos, TE, etc. |
| Imobilizado | Fichas de ativo, processamentos | Amortizações e eventos patrimoniais |
| Letras | Títulos e operações | Carteira, descontos, cobranças |
| Consolidação | Sociedades, instruções, ajustamentos | Regras e movimentos de grupo |
| Fiscais | Células/fórmulas de mapas, produção IES/IVA | Monitor de obrigações |

> Em análises custom deste repositório, validar sempre os nomes reais na BD do cliente (Corporate / Advanced / Enterprise / GO).

---

## 8. Checklist rápida: o que alimentar vs o que extrair

### Para o relato ficar correto, garantir entradas

1. Plano de contas e diários alinhados ao SNC / exercício  
2. Integração Gestão ↔ Contabilidade ativa e reconciliada (bancos)  
3. Centros de custo preenchidos onde obrigatório  
4. Códigos de tesouraria corretos nos movimentos (para DFC)  
5. Inventários finais (CMVMC) e processamentos de imobilizado no período  
6. Apuramentos de IVA e resultados corridos (ou simulados e validados)  
7. Notas às DF / taxonomias se forem base do IES  

### Extrair / entregar

1. Balancete e extratos do período  
2. Balanço, DR, DFC (+ notas)  
3. Declaração IVA e anexos necessários  
4. SAF-T Contabilidade (e auto-faturação se aplicável)  
5. IES / Modelo 22 / Modelo 30 (e 31–32 se Imobilizado)  
6. Mapas de gestão e dashboards para administração  
7. Consolidados (se grupo) via Consolidação / InterOp  

---

## 9. Referências

- PHC CS — *Descritivo Solução Financeira* (`phc.pt/enews/Descritivo_Financeira.pdf`)
- [Cegid PHC Contabilidade](https://www.cegid.com/ib/pt/produtos/cegid-phc-software-gestao/modulo-contabilidade/)
- [PHC GO — Balancete de contas por período](https://helpcenter.phcgo.net/PT/sug/ptxview.aspx?stamp=5gd4eg25%3A3ff46497f35eg)
- [PHC GO — Como é calculada a Demonstração de Fluxos de Caixa](https://helpcenter.phcgo.net/pt/sug/ptxview.aspx?stamp=%21%21%215b671b4769g8fg9%3Afb254f)
- [Add-on Demonstração de Fluxos de Caixa](https://phcsoftware.com/pt/phc-go-store/software-de-demonstracao-de-fluxos-de-caixa)
