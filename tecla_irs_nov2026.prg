*==============================================================================
* TECLA DE UTILIZADOR: Redução de 50% da retenção de IRS (novembro de 2026)
* Despacho n.º 12523-A/2026 (continente)
*------------------------------------------------------------------------------
* O que faz:
*   1. Lê as linhas de IRS dos recibos de novembro de 2026 que cumprem as
*      condições do despacho.
*   2. Mostra-as numa grelha para o utilizador confirmar o que quer processar.
*   3. Para cada recibo assinalado: reduz o IRS a metade, recalcula o recibo
*      (prprocf), acerta o IRS acumulado e grava numa transação SQL.
*   4. Apresenta a lista de recibos alterados e não alterados.
*
* Zona: PE.czonag = C (continente). O n.º 4 do despacho exclui os Açores e a
* Madeira. Os Açores têm o Despacho n.º 12610-A/2026 e a Madeira tem despacho
* regional, com tabelas próprias: não entram nesta tecla.
*
* Limite (n.º 3): o sujeito da remuneração (vencimento, subsídio de Natal ou
* subsídio de férias), e não a fatia de cada linha, não pode exceder o limite
* superior do penúltimo escalão da tabela do continente:
*   - Com deficiência (tabelas IV a VII) ......................... 20 468,00
*   - Sem deficiência, casado e único titular (tabela III) ....... 20 265,00
*   - Restantes casos (tabelas I e II) ........................... 20 221,00
* Quem está no limite entra. Quem o ultrapassa fica de fora. Estas tabelas são
* de trabalho dependente; as pensões têm limites mais baixos e não são tratadas
* aqui.
*
* IRS Jovem, Programa Regressar e horas extra: a taxa gravada na linha (dqtt)
* não sai de "IRS / sujeito da linha". Nesses casos a taxa nova é metade da
* taxa que já está na linha. Nas restantes, a taxa nova reflete o IRS já
* reduzido a metade sobre o sujeito da linha.
*==============================================================================

*------------------------------------------------------------------------------
* Declaração de variáveis
*------------------------------------------------------------------------------
local lcsql, lcflds, lctits, lni, lnrec, lnerr, lntotrec, lccols
local lclimdef, lclimtit, lclimout, lnlimdef, lnlimtit, lnlimout, lnano, lcano
local ldini, ldfim, lczonas, lcmarcador, lcoldpr, lcoldprre, lcoldprde, lcoldprcc
local loerr, lcparou
private bescolheu, fazu_tabupdate

store 0 to lnrec, lnerr

*------------------------------------------------------------------------------
* PARÂMETROS
*------------------------------------------------------------------------------
ldini = date(2026, 11, 1)
ldfim = date(2026, 12, 1)
lnano = 2026
lnlimdef = 20468
lnlimtit = 20265
lnlimout = 20221
lcano = alltrim(str(m.lnano, 4, 0))
lclimdef = alltrim(str(m.lnlimdef, 10, 0))
lclimtit = alltrim(str(m.lnlimtit, 10, 0))
lclimout = alltrim(str(m.lnlimout, 10, 0))
lcmarcador = "12523-A"

* PE.czonag. Manter só o continente: os limites acima não servem para A nem M.
lczonas = "'C'"

*------------------------------------------------------------------------------
* 1. Validações iniciais
*------------------------------------------------------------------------------
if not is_exept() or (type("_screen.activeform.editing") = "L" and (_screen.activeform.adding or _screen.activeform.editing))
	msg("Esta tecla é para Portugal e deve ser executada com o recibo gravado (fora de introdução ou alteração).")
	return
endif

if type("pe_arirs") = "U"
	do peparas
endif

if not pergunta("Aplicação da redução de IRS em 50% aos recibos de novembro de 2026," + chr(13) + ;
		"nos termos do Despacho n.º 12523-A/2026 (continente)." + chr(13) + chr(13) + ;
		"Pretende continuar?", 2, , .t.)
	return
endif

*------------------------------------------------------------------------------
* 2. Leitura das linhas de IRS elegíveis
*------------------------------------------------------------------------------
* Sem comentários dentro do TEXT. lczonas e os limites entram por TEXTMERGE.
*   basemes : sujeito da remuneração (vencimento, natal, férias ou férias+natal).
*             É este valor que se compara com o limite do penúltimo escalão.
*   suj     : parte desse sujeito atribuída à linha, em proporção ao IRS.
*             Serve para calcular a taxa efetiva da linha.
*   jovem   : 1 no IRS Jovem, no Programa Regressar e nas horas extra. A taxa
*             nova é metade de dqtt, porque suj não é a base dessa taxa.
* Os agregados de PRRE/PRDE ficam limitados a novembro de 2026 para não varrer
* o histórico. Linhas com IRS negativo ou zero não são redução de retenção.
text to m.lcsql textmerge noshow pretext 1+2
	SELECT pr.prstamp, pr.recibo, pr.no, pr.nome, pr.data AS prdata, d.prdestamp, d.ede, d.dqtt, d.obs,
	CASE WHEN ISNULL(pr.jovemisentoirs, 0) = 1 OR ISNULL(pr.prisentoirs, 0) = 1 OR ISNULL(d.hextra, 0) = 1 THEN 1 ELSE 0 END AS jovem,
	CASE WHEN ISNULL(pe.deficiente, 0) = 1 THEN <<m.lclimdef>>
	     WHEN ISNULL(pe2.casado, 0) = 1 AND ISNULL(pe.ntit, 0) = 1 THEN <<m.lclimtit>>
	     ELSE <<m.lclimout>> END AS lim,
	ISNULL(ROUND(CASE x.tp WHEN 0 THEN s.s0 WHEN 1 THEN s.s1 WHEN 2 THEN s.s2 ELSE s.s1 + s.s2 END, 2), 0) AS basemes,
	ISNULL(ROUND(CASE x.tp WHEN 0 THEN s.s0 WHEN 1 THEN s.s1 WHEN 2 THEN s.s2 ELSE s.s1 + s.s2 END * d.ede / NULLIF(t.tede, 0), 2), 0) AS suj
	FROM pr (nolock)
	INNER JOIN prde d (nolock) ON d.prstamp = pr.prstamp
	INNER JOIN cm6 c (nolock) ON c.cm = d.cd AND c.codirs = 1
	CROSS APPLY (SELECT CASE WHEN d.nat = 1 AND d.fer = 1 THEN 3 WHEN d.nat = 1 THEN 1 WHEN d.fer = 1 THEN 2 ELSE 0 END AS tp) x
	LEFT JOIN (SELECT r.prstamp,
		SUM(CASE WHEN m.natal = 0 AND m.ferias = 0 THEN r.ereirs ELSE 0 END) AS s0,
		SUM(CASE WHEN m.natal = 1 THEN r.ereirs ELSE 0 END) AS s1,
		SUM(CASE WHEN m.natal = 0 AND m.ferias = 1 THEN r.ereirs ELSE 0 END) AS s2
		FROM prre r (nolock)
		INNER JOIN pr pf (nolock) ON pf.prstamp = r.prstamp
		INNER JOIN cm6 m (nolock) ON m.cm = r.cr
		WHERE pf.ano = <<m.lcano>> AND pf.data >= '<<dtos(m.ldini)>>' AND pf.data < '<<dtos(m.ldfim)>>'
		GROUP BY r.prstamp) s ON s.prstamp = pr.prstamp
	LEFT JOIN (SELECT p.prstamp, y.tp, SUM(p.ede) AS tede
		FROM prde p (nolock)
		INNER JOIN pr pd (nolock) ON pd.prstamp = p.prstamp
		INNER JOIN cm6 k (nolock) ON k.cm = p.cd AND k.codirs = 1
		CROSS APPLY (SELECT CASE WHEN p.nat = 1 AND p.fer = 1 THEN 3 WHEN p.nat = 1 THEN 1 WHEN p.fer = 1 THEN 2 ELSE 0 END AS tp) y
		WHERE pd.ano = <<m.lcano>> AND pd.data >= '<<dtos(m.ldini)>>' AND pd.data < '<<dtos(m.ldfim)>>'
		GROUP BY p.prstamp, y.tp) t ON t.prstamp = pr.prstamp AND t.tp = x.tp
	LEFT JOIN pe (nolock) ON pe.no = pr.no
	LEFT JOIN pe2 (nolock) ON pe2.pe2stamp = pe.pestamp
	WHERE pr.ano = <<m.lcano>> AND pr.data >= '<<dtos(m.ldini)>>' AND pr.data < '<<dtos(m.ldfim)>>'
	AND pr.moeda IN ('', 'EURO') AND d.dtref >= '<<dtos(m.ldini)>>' AND d.dtref < '<<dtos(m.ldfim)>>' AND d.ede > 0
	AND pe.czonag IN (<<m.lczonas>>) AND pr.txirs = 0 AND pr.resestr = 0 AND ISNULL(pe.txirs, 0) = 0 AND ISNULL(pe2.organizacao, 0) = 0
	AND pr.pago = 0
	AND d.ajirs = 0 AND d.txextirs = 0 AND d.txextmirs = 0 AND d.ajtxextmirs = 0
endtext

if not u_sqlexec(m.lcsql, "c_irs26raw")
	msg("Não foi possível ler os recibos de novembro de 2026. Verifique a ligação à base de dados e os campos da consulta.")
	return
endif

* A grelha mostra o sujeito da linha (suj), que é a base da taxa.
* O limite aplica-se a basemes, o sujeito da remuneração inteira.
select .t. as marca, recibo, nome, suj, ;
	iif(jovem = 1, dqtt, iif(suj > 0, round(ede / suj * 100, 2), dqtt)) as tx_atu, ede, ;
	iif(jovem = 1, round(dqtt / 2, 2), iif(suj > 0, round(round_value(.t., ede * 0.5) / suj * 100, 2), round(dqtt / 2, 2))) as tx_nova, ;
	round_value(.t., ede * 0.5) as ede_nova, ;
	prstamp, prdestamp, no, prdata, obs ;
	from c_irs26raw ;
	where basemes > 0 and basemes <= lim and not (m.lcmarcador $ nvl(obs, "")) ;
	order by recibo, nome, prdestamp ;
	into cursor c_irs26 readwrite
fecha("c_irs26raw")

if reccount("c_irs26") = 0
	fecha("c_irs26")
	msg("Não encontrámos linhas de IRS de novembro de 2026 por tratar: não existem recibos nestas condições ou já foram tratados.")
	return
endif

*------------------------------------------------------------------------------
* 3. Grelha de confirmação
*------------------------------------------------------------------------------
lcflds = "marca,recibo,nome,suj,tx_atu,ede,tx_nova,ede_nova"
lctits = "Processar?|Recibo|Funcionário|Valor sujeito a IRS|Taxa efetiva atual|Valor IRS atual|Taxa efetiva nova|Valor IRS novo"
lccols = getwordcount(m.lcflds, ",")

declare list_tit(m.lccols), list_pic(m.lccols), list_cam(m.lccols), list_tam(m.lccols), list_ronly(m.lccols)
for lni = 1 to m.lccols
	list_cam(m.lni) = "c_irs26." + getwordnum(m.lcflds, m.lni, ",")
	list_tit(m.lni) = getwordnum(m.lctits, m.lni, "|")
	list_pic(m.lni) = iif(m.lni = 1, "LOGIC", iif(m.lni >= 4, "999,999,999.99", ""))
	list_tam(m.lni) = 8 * iif(m.lni = 3, 30, 15)
	list_ronly(m.lni) = .t.
next
list_ronly(1) = .f.

=cursorsetprop("Buffering", 5, "c_irs26")
m.bescolheu = .f.
m.fazu_tabupdate = .f.

do browlist with "Redução de 50% do IRS de novembro de 2026: assinale as linhas a processar", "c_irs26", "irs1126", .t., .f., .f., .t., .f., "", .t.
release list_tit, list_pic, list_cam, list_tam, list_ronly

if not m.bescolheu
	fecha("c_irs26")
	release bescolheu, fazu_tabupdate
	return
endif

* A grelha grava a marca no buffer. Sem isto, o SELECT pode não ver o que foi desmarcado.
if cursorgetprop("Buffering", "c_irs26") > 1 and not tableupdate(.t., .t., "c_irs26")
	fecha("c_irs26")
	release bescolheu, fazu_tabupdate
	msg("Não foi possível ler a seleção feita na grelha. Não foi alterado nada.")
	return
endif

select distinct prstamp, no, prdata, recibo, nome from c_irs26 where marca into cursor c_irs26rec
if reccount("c_irs26rec") = 0
	fecha("c_irs26rec:c_irs26")
	release bescolheu, fazu_tabupdate
	msg("Não assinalou nenhuma linha, pelo que não foi alterado nada.")
	return
endif
lntotrec = reccount("c_irs26rec")

*------------------------------------------------------------------------------
* 4. Views do recibo. Guarda o recibo que está no ecrã para o repor no fim.
*------------------------------------------------------------------------------
lcoldpr = iif(type("v_prstamp") = "C", v_prstamp, "")
lcoldprre = iif(type("v_prreprstamp") = "C", v_prreprstamp, "")
lcoldprde = iif(type("v_prdeprstamp") = "C", v_prdeprstamp, "")
lcoldprcc = iif(type("v_prccstamp") = "C", v_prccstamp, "")

if not used("pr")
	do dbfusepr
endif
if not used("prre")
	do dbfuseprre
endif
if not used("prde")
	do dbfuseprde
endif
if not used("prcc")
	do dbfuseprcc
endif
irs26_limpa_views()

*------------------------------------------------------------------------------
* 5. Recibo a recibo
*------------------------------------------------------------------------------
lcparou = ""
regua(0, m.lntotrec, "A processar os recibos ...")
try
	select c_irs26rec
	scan
		regua(1, recno("c_irs26rec"), "<§" + alltrim(c_irs26rec.nome) + "§>")
		try
			irs26_requery(c_irs26rec.prstamp)
			if irs26_processa(c_irs26rec.prstamp, c_irs26rec.recibo, alltrim(c_irs26rec.nome), c_irs26rec.no, c_irs26rec.prdata, m.lnano, m.lcmarcador) = 1
				lnrec = m.lnrec + 1
			else
				lnerr = m.lnerr + 1
			endif
		catch to loerr
			lnerr = m.lnerr + 1
			irs26_reverte()
			aadderros("Recibo n.º " + astr(c_irs26rec.recibo) + " de " + alltrim(c_irs26rec.nome) + ": não foi alterado (erro inesperado: " + m.loerr.message + ").")
		finally
			if used("c_irs26rec")
				select c_irs26rec
			endif
		endtry
	endscan
catch to loparou
	lcparou = loparou.message
finally
	try
		regua(2)
	catch
	endtry
	irs26_restaura_ecra(m.lcoldpr, m.lcoldprre, m.lcoldprde, m.lcoldprcc)
endtry

if not empty(m.lcparou)
	aadderros("Processamento interrompido: " + m.lcparou)
endif

*------------------------------------------------------------------------------
* 6. Resultado
*------------------------------------------------------------------------------
fecha("c_irs26rec:c_irs26")
aadderros("Concluído. Recibos alterados: " + astr(m.lnrec) + ". Recibos não alterados: " + astr(m.lnerr) + iif(m.lnerr > 0, ". Pode voltar a executar a tecla para os tratar.", "."))
mostraerros()
release bescolheu, fazu_tabupdate

try
	if type("_screen.activeform") = "O" and not isnull(_screen.activeform)
		_screen.activeform.refresh()
	endif
catch
endtry

return .t.


*==============================================================================
* Um recibo. Devolve 1 se gravou, 0 se não gravou. A mensagem fica em aadderros.
*==============================================================================
procedure irs26_processa
	lparameters p_stamp, p_recibo, p_nome, p_no, p_data, p_ano, p_marca
	local lnok, lndif, lnlinhas, lnmarcadas, lneirsantes, lndeltaesc
	local llok, llquery, lcchk, lcacum, lcdata, lcresultado, lcparcial, lllinhasok, llaberta, llmodoeu, lntrantes
	local loerr

	lnok = 0
	lcresultado = ""
	llaberta = .f.
	llmodoeu = .f.
	lntrantes = 1
	lndif = 0
	lnlinhas = 0
	lnmarcadas = 0

	try
		if not used("pr") or reccount("pr") = 0
			lcresultado = "Recibo n.º " + astr(m.p_recibo) + " de " + m.p_nome + ": não foi alterado (não foi possível abrir o recibo)."
		else
			select c_irs26
			count for marca and prstamp = m.p_stamp to lnmarcadas
			scan for marca and prstamp = m.p_stamp
				select prde
				locate for prde.prdestamp = c_irs26.prdestamp
				if found() and abs(prde.ede - c_irs26.ede) < 0.001 and not (m.p_marca $ nvl(prde.obs, ""))
					lndif = m.lndif + prde.ede - c_irs26.ede_nova
					replace prde.ede with c_irs26.ede_nova, ;
						prde.de with eurotoesc(c_irs26.ede_nova), ;
						prde.dqtt with min(max(c_irs26.tx_nova, 0), 99.99), ;
						prde.obs with left("Desp.12523-A/26 " + alltrim(nvl(prde.obs, "")), 50)
					lnlinhas = m.lnlinhas + 1
				endif
				select c_irs26
			endscan
			lndif = round(m.lndif, 2)

			if m.lnlinhas = 0
				lcresultado = "Recibo n.º " + astr(m.p_recibo) + " de " + m.p_nome + ": não foi alterado (as linhas foram alteradas entretanto)."
			else
				select pr
				lneirsantes = pr.eirsacum
				do prprocf

				lllinhasok = .t.
				select c_irs26
				scan for marca and prstamp = m.p_stamp
					select prde
					locate for prde.prdestamp = c_irs26.prdestamp
					if not found() or abs(prde.ede - c_irs26.ede_nova) >= 0.001
						lllinhasok = .f.
					endif
					select c_irs26
				endscan

				if not m.lllinhasok
					irs26_reverte()
					lcresultado = "Recibo n.º " + astr(m.p_recibo) + " de " + m.p_nome + ": não foi alterado (o recálculo do recibo repôs o IRS)."
				else
					select pr
					* O prprocf, quando mexe no acumulado, fá-lo só neste recibo.
					* Os recibos seguintes levam sempre a diferença das linhas (lndif).
					if abs(pr.eirsacum - m.lneirsantes) < 0.005
						replace pr.eirsacum with pr.eirsacum - m.lndif, ;
							pr.irsacum with pr.irsacum - eurotoesc(m.lndif)
					endif
					lndeltaesc = eurotoesc(m.lndif)

					if vartype(m.p_data) = "T"
						lcdata = left(ttoc(m.p_data, 1), 8)
					else
						lcdata = dtos(m.p_data)
					endif

					lcacum = ""
					if m.lndif > 0.005
						lcacum = "UPDATE pr SET eirsacum = eirsacum - " + dec_tr(m.lndif, 19, 6) + ;
							", irsacum = irsacum - " + dec_tr(m.lndeltaesc, 18, 5) + ;
							" WHERE no = " + astr(m.p_no) + " AND ano = " + irs26_num(m.p_ano) + ;
							" AND prstamp <> " + irs26_stamp(m.p_stamp) + ;
							" AND (data > '" + m.lcdata + "' OR (data = '" + m.lcdata + "' AND recibo > " + astr(m.p_recibo) + "))"
					endif

					lntrantes = sqlgetprop(m.con_dbhandle, "Transactions")
					sqlsetprop(m.con_dbhandle, "Transactions", 2)
					llmodoeu = .t.
					llaberta = .t.

					lcchk = "SELECT COUNT(*) AS n FROM pr WITH (UPDLOCK, ROWLOCK) WHERE prstamp = " + irs26_stamp(m.p_stamp) + ;
						" AND pago = 0 AND ano = " + irs26_num(m.p_ano)
					llquery = u_sqlexec(m.lcchk, "c_chk")
					llok = m.llquery and used("c_chk") and c_chk.n > 0
					if used("c_chk")
						fecha("c_chk")
					endif

					if not m.llok
						sqlrollback(m.con_dbhandle)
						llaberta = .f.
						irs26_reverte()
						if m.llquery
							lcresultado = "Recibo n.º " + astr(m.p_recibo) + " de " + m.p_nome + ": não foi alterado (recibo entretanto marcado como pago)."
						else
							lcresultado = "Recibo n.º " + astr(m.p_recibo) + " de " + m.p_nome + ": não foi alterado (não foi possível confirmar o estado do recibo)."
						endif
					else
						* Cabeçalho e linhas. O líquido fica no PR. PRRE/PRCC não se gravam:
						* o rendimento não muda; se o prprocf mexeu na conta-corrente, essa
						* alteração fica só em memória e o requery seguinte repõe-na.
						if u_tabupdate(.t., .t., "PR") and u_tabupdate(.t., .t., "PRDE") and (empty(m.lcacum) or u_sqlexec(m.lcacum))
							sqlcommit(m.con_dbhandle)
							llaberta = .f.
							lnok = 1
							lcparcial = iif(m.lnlinhas < m.lnmarcadas, " Ficaram de fora linhas que já não coincidiam com a grelha.", "")
							lcresultado = "Recibo n.º " + astr(m.p_recibo) + " de " + m.p_nome + ": IRS reduzido em " + alltrim(transform(m.lndif, "999,999,999.99")) + "." + m.lcparcial
						else
							sqlrollback(m.con_dbhandle)
							llaberta = .f.
							irs26_reverte()
							lcresultado = "Recibo n.º " + astr(m.p_recibo) + " de " + m.p_nome + ": não foi alterado (erro de gravação). Consulte a análise interna."
						endif
					endif
				endif
			endif
		endif
	catch to loerr
		if m.llaberta
			try
				sqlrollback(m.con_dbhandle)
			catch
			endtry
			llaberta = .f.
		endif
		irs26_reverte()
		lnok = 0
		lcresultado = "Recibo n.º " + astr(m.p_recibo) + " de " + m.p_nome + ": não foi alterado (erro: " + m.loerr.message + ")."
	finally
		if m.llaberta
			try
				sqlrollback(m.con_dbhandle)
			catch
			endtry
		endif
		if m.llmodoeu
			try
				sqlsetprop(m.con_dbhandle, "Transactions", m.lntrantes)
			catch
			endtry
		endif
		if used("c_chk")
			fecha("c_chk")
		endif
	endtry

	if not empty(m.lcresultado)
		aadderros(m.lcresultado)
	endif
	return m.lnok
endproc


*------------------------------------------------------------------------------
* Stamp entre plicas, com plicas internas duplicadas.
*------------------------------------------------------------------------------
function irs26_stamp
	lparameters p_cstamp
	return "'" + strtran(alltrim(nvl(m.p_cstamp, "")), "'", "''") + "'"
endfunc


*------------------------------------------------------------------------------
* Número inteiro para SQL, sem espaços.
*------------------------------------------------------------------------------
function irs26_num
	lparameters p_n
	return alltrim(str(m.p_n, 16, 0))
endfunc


*------------------------------------------------------------------------------
* Desfaz alterações ainda não gravadas nas views do recibo.
*------------------------------------------------------------------------------
procedure irs26_reverte
	local laareas(4), lni
	laareas(1) = "PR"
	laareas(2) = "PRDE"
	laareas(3) = "PRRE"
	laareas(4) = "PRCC"
	for lni = 1 to 4
		if used(laareas(m.lni))
			try
				tablerevert(.t., laareas(m.lni))
			catch
			endtry
		endif
	next
endproc


*------------------------------------------------------------------------------
* Esvazia as views (stamp que não existe).
*------------------------------------------------------------------------------
procedure irs26_limpa_views
	v_prstamp = "*-*-*-*"
	u_requery("PR")
	v_prreprstamp = "*-*-*-*"
	u_requery("PRRE")
	v_prdeprstamp = "*-*-*-*"
	u_requery("PRDE")
	v_prccstamp = "*-*-*-*"
	u_requery("PRCC")
endproc


*------------------------------------------------------------------------------
* Carrega o recibo indicado.
*------------------------------------------------------------------------------
procedure irs26_requery
	lparameters p_qualstamp
	v_prstamp = m.p_qualstamp
	u_requery("PR")
	v_prreprstamp = m.p_qualstamp
	u_requery("PRRE")
	v_prdeprstamp = m.p_qualstamp
	u_requery("PRDE")
	v_prccstamp = m.p_qualstamp
	u_requery("PRCC")
endproc


*------------------------------------------------------------------------------
* Repõe o recibo que estava no ecrã antes da tecla.
*------------------------------------------------------------------------------
procedure irs26_restaura_ecra
	lparameters p_pr, p_prre, p_prde, p_prcc
	if type("v_prstamp") = "C"
		v_prstamp = m.p_pr
	endif
	if type("v_prreprstamp") = "C"
		v_prreprstamp = m.p_prre
	endif
	if type("v_prdeprstamp") = "C"
		v_prdeprstamp = m.p_prde
	endif
	if type("v_prccstamp") = "C"
		v_prccstamp = m.p_prcc
	endif
	try
		if used("pr") and not empty(m.p_pr)
			u_requery("PR")
		endif
		if used("prre") and not empty(m.p_prre)
			u_requery("PRRE")
		endif
		if used("prde") and not empty(m.p_prde)
			u_requery("PRDE")
		endif
		if used("prcc") and not empty(m.p_prcc)
			u_requery("PRCC")
		endif
	catch
	endtry
endproc
