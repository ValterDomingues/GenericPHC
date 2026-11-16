# Manual de utilizador

## Redução de 50% da retenção de IRS — novembro de 2026

Despacho n.º 12523-A/2026

Tecla de utilizador do PHC, módulo de vencimentos.

Este manual descreve o que a tecla faz, quem entra no processamento, o que é gravado em cada recibo e como ler o resultado.

---

## 1. Para que serve

A tecla reduz a metade o IRS das linhas elegíveis dos recibos de novembro de 2026 que ainda não estão pagos.

Não trata um único funcionário. Percorre os recibos de novembro que cumpram as condições e mostra-os todos numa grelha. Só grava as linhas que deixar assinaladas.

Em cada linha gravada:

- o valor de IRS passa a metade do valor que estava na linha;
- a taxa gravada na linha é atualizada;
- a observação da linha fica marcada com `Desp.12523-A/26`, para a tecla não voltar a reduzir a mesma linha;
- o recibo é recalculado (descontos, líquido e IRS acumulado);
- o IRS acumulado dos recibos seguintes do mesmo funcionário, no ano de 2026, é reduzido pelo mesmo valor.

---

## 2. Quando a executar

Execute a tecla depois de os recibos de novembro de 2026 estarem calculados e ainda por pagar.

A tecla só corre numa instalação de Portugal. O recibo que estiver no ecrã tem de estar gravado: não pode estar em introdução nem em alteração. Se estiver, a tecla termina com a mensagem «Esta tecla é para Portugal e deve ser executada com o recibo gravado (fora de introdução ou alteração).»

Convém correr primeiro um recibo de ensaio: na grelha, retire a seleção de todas as linhas menos as desse recibo, confirme o líquido e o IRS acumulado, e só depois volte a executar a tecla para os restantes. As linhas já marcadas com `12523-A` não voltam a aparecer.

---

## 3. Como executar

1. Grave o recibo que estiver aberto. Saia do modo de introdução ou de alteração.
2. Execute a tecla.
3. Leia a pergunta «Aplicação da redução de IRS em 50% aos recibos de novembro de 2026 conforme Despacho n.º 12523-A/2026. Pretende continuar». Escolha **Sim** para avançar.
4. A tecla lê os recibos. Se não houver linhas por tratar, aparece a mensagem «Não encontrámos linhas de IRS de novembro de 2026 por tratar» e não é alterado nada.
5. Na grelha, todas as linhas começam assinaladas. Retire o visto das linhas que não quer processar. A coluna **Processar?** é a coluna de seleção.
6. Confirme a grelha. Se cancelar, ou se não deixar nenhuma linha assinalada, não é alterado nada.
7. A tecla trata recibo a recibo e mostra o progresso com o nome do funcionário.
8. No fim abre a lista do que foi alterado e do que não foi. O ecrã do recibo aberto é atualizado com os valores gravados.

A tecla pode ser executada outra vez. As linhas já gravadas com a marca `12523-A` ficam de fora. Entram as que falharam ou as que tinha deixado por assinalar.

---

## 4. A grelha de confirmação

Título da grelha: «Redução de 50% do IRS de novembro de 2026: assinale as linhas a processar».

| Coluna | O que mostra |
| --- | --- |
| Processar? | Visto para gravar a linha. Começa assinalada. |
| Recibo | Número do recibo. |
| Funcionário | Nome do funcionário. |
| Valor sujeito a IRS | Parte da remuneração daquele tipo que a tecla atribui à linha. É este valor que é comparado com o limite. |
| Taxa efetiva atual | Taxa que a linha tem hoje. No IRS Jovem, no Programa Regressar e nas horas extra é a taxa já gravada na linha. Nos outros casos é o IRS da linha a dividir pelo valor sujeito. |
| Valor IRS atual | IRS que a linha tem hoje. |
| Taxa efetiva nova | Taxa que ficará gravada. Nos casos de IRS Jovem, Programa Regressar e horas extra é metade da taxa atual. Nos restantes é a taxa que corresponde ao IRS novo sobre o valor sujeito. |
| Valor IRS novo | Metade do IRS atual, com o arredondamento do PHC. |

O processamento é por recibo. Se assinalar só algumas linhas de um recibo, as outras linhas desse recibo mantêm-se.

---

## 5. Que linhas entram

Uma linha aparece na grelha quando se verificam todas as condições seguintes.

**Datas.** A data do recibo e a data de referência da linha de IRS estão ambas entre 1 e 30 de novembro de 2026.

**Recibo.** O recibo não está pago, a moeda é euro (ou está em branco) e o recibo não tem taxa de IRS fixa nem está marcado como residente no estrangeiro.

**Funcionário.** A zona fiscal (`PE.czonag`) é uma das zonas abrangidas. Nesta versão são o Continente (`C`), os Açores (`A`) e a Madeira (`M`). O funcionário não tem taxa de IRS fixa e não está marcado como organização.

**Linha de IRS.** A rubrica está marcada como sujeita a IRS. O valor de IRS da linha é diferente de zero. A linha não é um acerto de IRS nem uma taxa extraordinária. A observação ainda não contém `12523-A`. O valor sujeito da linha não ultrapassa o limite do funcionário. Um valor igual ao limite entra.

**Valor sujeito.** A tecla separa a remuneração em vencimento normal, subsídio de Natal, subsídio de férias, ou Natal e férias na mesma linha. O valor sujeito da grelha é a remuneração desse tipo. Quando o recibo tem várias linhas de IRS do mesmo tipo, esse valor é repartido entre elas na proporção do IRS de cada uma.

---

## 6. Que linhas ficam de fora

Não aparecem na grelha, e portanto não são alteradas:

- recibos pagos, ou com data fora de novembro de 2026;
- linhas cuja data de referência está fora de novembro de 2026;
- linhas cujo valor sujeito ultrapassa o limite do funcionário;
- linhas já tratadas (a observação contém `12523-A`);
- linhas com IRS igual a zero, acertos de IRS e taxas extraordinárias;
- funcionários com zona fiscal diferente de Continente, Açores ou Madeira;
- funcionários ou recibos com taxa de IRS fixa;
- residentes no estrangeiro;
- funcionários marcados como organização;
- recibos cuja moeda não é euro.

Durante a gravação, um recibo que entretanto tenha sido marcado como pago é saltado. A mensagem é «não foi alterado (recibo entretanto marcado como pago)».

Se, entre a abertura da grelha e a gravação, o IRS da linha deixar de ser o valor que estava na grelha, essa linha não é substituída. Quando nenhuma das linhas assinaladas do recibo puder ser alterada, a mensagem é «não foi alterado (as linhas foram alteradas entretanto)». Quando pelo menos uma linha ainda coincidir, o recibo é gravado só com essas linhas.

---

## 7. Limites de rendimento

O limite aplica-se ao valor sujeito de cada linha, não à soma do mês.

| Situação do funcionário | Limite |
| --- | --- |
| Com deficiência | 20 468,00 € |
| Sem deficiência, casado e único titular | 20 265,00 € |
| Restantes casos | 20 221,00 € |

A deficiência lê-se da ficha do funcionário. «Casado e único titular» lê-se do estado civil e do número de titulares.

Estes três valores são os que a tecla usa em todas as zonas que tiver abrangidas. A tecla não muda o limite conforme a zona seja Continente, Açores ou Madeira.

---

## 8. IRS Jovem, Programa Regressar e horas extra

O valor de IRS novo é, em todos os casos, metade do IRS que a linha tem hoje.

A diferença está na taxa que fica gravada:

- **IRS Jovem, Programa Regressar ou linha de horas extra.** A taxa nova é metade da taxa que já está na linha. A tecla não recalcula essa taxa a partir do valor sujeito. No IRS Jovem e no Programa Regressar a taxa da linha é a taxa efetiva sobre a remuneração bruta, já com a isenção retirada do valor sujeito. Nas horas extra, o valor sujeito da grelha reparte a remuneração do tipo e não isola só o valor das horas extra.
- **Restantes linhas.** A taxa nova é o IRS novo a dividir pelo valor sujeito da linha.

A taxa gravada não ultrapassa 99,99.

---

## 9. O que fica gravado

Cada recibo é gravado à parte. Se a gravação de um recibo falhar, esse recibo fica como estava. Os recibos já gravados nessa execução mantêm-se. A mensagem de falha é «não foi alterado (erro de gravação). Consulte a análise interna.»

Num recibo gravado com sucesso:

1. Nas linhas assinaladas que ainda tinham o IRS mostrado na grelha, o IRS em euros e o valor correspondente em escudos passam a metade, a taxa é a taxa nova e a observação passa a começar por `Desp.12523-A/26`. A observação fica limitada a 50 caracteres: o texto que já lá estava pode ser cortado no fim. A marca `12523-A` mantém-se no início, e é ela que impede uma segunda redução.
2. O PHC recalcula o recibo (descontos, líquido e acumulados).
3. O IRS acumulado do próprio recibo desce pelo valor de IRS retirado. Se o recálculo do PHC já tiver feito esse acerto, a tecla não o faz segunda vez nesse recibo.
4. Os recibos seguintes do mesmo funcionário, do ano de 2026, têm o IRS acumulado reduzido pelo mesmo valor. Entram os recibos com data posterior e, no mesmo dia, os de número de recibo superior. Este acerto do acumulado também é feito nos recibos seguintes que já estejam pagos. O líquido desses recibos seguintes não é recalculado.

A lista final tem uma linha por recibo tratado, por exemplo «Recibo n.º 123 de Ana Silva: IRS reduzido em 150,00.», e o resumo «Concluído. Recibos alterados: … Recibos não alterados: …». Quando houver recibos não alterados, a mensagem indica que pode voltar a executar a tecla para os tratar.

---

## 10. Mensagens

| Mensagem | Significado |
| --- | --- |
| Esta tecla é para Portugal e deve ser executada com o recibo gravado… | A instalação não é de Portugal, ou o recibo do ecrã está em introdução ou alteração. Grave o recibo e volte a executar. |
| Pretende continuar | Pergunta inicial. Sim avança para a leitura. Não termina a tecla e não altera recibos. |
| Não foi possível ler os recibos de novembro de 2026… | A consulta à base de dados falhou. Nada foi alterado. |
| Não encontrámos linhas de IRS de novembro de 2026 por tratar… | Não há linhas elegíveis, ou as que havia já têm a marca `12523-A`. |
| Não assinalou nenhuma linha, pelo que não foi alterado nada. | Confirmou a grelha sem vistos. |
| Recibo n.º … : IRS reduzido em … | Esse recibo foi gravado. |
| … recibo entretanto marcado como pago. | Alguém pagou o recibo depois de a grelha abrir. |
| … as linhas foram alteradas entretanto. | Nenhuma linha assinalada desse recibo mantinha o IRS da grelha. |
| … erro de gravação. Consulte a análise interna. | A gravação desse recibo foi anulada. Os recibos anteriores desta execução ficam gravados. |
| Concluído. Recibos alterados: … Recibos não alterados: … | Resumo da execução. |

---

## 11. O que esta tecla não faz

- Não altera recibos pagos, recibos de outros meses, nem linhas cuja data de referência não seja de novembro de 2026.
- Não reduz uma linha cujo valor sujeito ultrapasse o limite.
- Não reduz segunda vez uma linha cuja observação já contenha `12523-A`.
- Não escolhe sozinha as linhas: grava as que deixou assinaladas.
- Não recalcula o líquido dos recibos seguintes. Nesses recibos só mexe no IRS acumulado.
- Não muda o limite conforme a região. Continente, Açores e Madeira usam a tabela da secção 7.

---

## 12. Nota para quem mantém a tecla

A lista de zonas está no início do programa, na variável `lczonas`. O valor gravado nesta versão é `'C','A','M'` (Continente, Açores e Madeira). Para limitar o processamento, altere essa lista antes de executar. `C` é o Continente, `A` os Açores e `M` a Madeira.

Os limites 20 468,00, 20 265,00 e 20 221,00 estão escritos na consulta e aplicam-se a todas as zonas incluídas em `lczonas`.
