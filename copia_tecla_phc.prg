*==============================================================================
* Copia ou atualiza teclas de utilizador (TC / TI) entre bases PHC
* da mesma instância de SQL Server.
*------------------------------------------------------------------------------
* Executar na janela de comandos do PHC, com a ligação aberta:
*   DO copia_tecla_phc
*
* TC  cabeçalho: identifica o ecrã (tc.ecran, tc.tcstamp).
* TI  linhas:    a tecla, identificada por ti.tistamp, que tem de ser o mesmo
*                em todas as bases. A conjugação (por exemplo SHIFT+F1) pode
*                diferir: se já estiver ocupada naquele ecrã, usa-se a
*                seguinte livre (SHIFT+F2, SHIFT+F3, ...).
*
* Bases sem as tabelas TC e TI (não são PHC, ou não estão acessíveis) ficam
* de fora. A ligação do PHC não muda de base: o SQL usa nomes em três partes.
*
* Depois de gravar, reabrir o ecrã (ou reiniciar o PHC) para ele reler as teclas.
*==============================================================================

local lcBdOrigem, lcTiStamp, lcCampoTecla, lcCampoEcra
local lcBdAtual, lcEsqOrigem, lcSql, llOk, lnTotal, lnFeito
local lcBase, lcEsq, lcStamp, lcMsg, loerr
private bescolheu, fazu_tabupdate, lnIns, lnAtu, lnFalhas, lnSeqStamp

store 0 to lnIns, lnAtu, lnFalhas, lnSeqStamp

*------------------------------------------------------------------------------
* PARÂMETROS
*------------------------------------------------------------------------------
* Vazio = base de dados da sessão PHC.
lcBdOrigem = ""

* Vazio = escolher na grelha, sem nenhuma tecla marcada.
* Preenchido = só esse ti.tistamp, já marcado.
lcTiStamp = ""

* Vazio = detetar. O primeiro que existir nesta lista: tecla, teclas, tikey,
* chave, atalho, hotkey, combinacao.
lcCampoTecla = ""

* Vazio = detetar. O primeiro que existir: ecran, ecra, tctab, tabela.
lcCampoEcra = ""

*------------------------------------------------------------------------------
* 1. Ligação
*------------------------------------------------------------------------------
if type("m.con_dbhandle") <> "N"
	msg("Esta rotina tem de ser executada dentro do PHC, com a ligação ao SQL Server ativa.")
	return
endif
if m.con_dbhandle <= 0
	msg("Esta rotina tem de ser executada dentro do PHC, com a ligação ao SQL Server ativa.")
	return
endif

lcBdAtual = alltrim(nvl(sql_valor("SELECT DB_NAME() AS v"), ""))
if empty(m.lcBdAtual)
	msg("Não foi possível obter o nome da base de dados atual.")
	return
endif
if empty(m.lcBdOrigem)
	lcBdOrigem = m.lcBdAtual
endif
lcBdOrigem = alltrim(m.lcBdOrigem)

if not pergunta("Copiar teclas de utilizador da base " + m.lcBdOrigem + " para as outras bases PHC desta instância?" + chr(13) + chr(13) + ;
		"A tecla é a mesma quando ti.tistamp coincide. Se a conjugação já estiver ocupada no ecrã, será usada uma conjugação seguinte livre.", 2, , .t.)
	return
endif

*------------------------------------------------------------------------------
* 2. Origem: esquema, campos e teclas
*------------------------------------------------------------------------------
lcEsqOrigem = esquema_phc(m.lcBdOrigem)
if empty(m.lcEsqOrigem)
	msg("A base " + m.lcBdOrigem + " não tem as tabelas TC e TI, ou não está acessível.")
	return
endif

if not carrega_colunas(m.lcBdOrigem, m.lcEsqOrigem, "ti", "c_col_ti_src") or not carrega_colunas(m.lcBdOrigem, m.lcEsqOrigem, "tc", "c_col_tc_src")
	msg("Não foi possível ler as colunas de TC e TI na base de origem.")
	limpa_cursors()
	return
endif

if not coluna_existe("c_col_ti_src", "tistamp") or not coluna_existe("c_col_ti_src", "tcstamp") or not coluna_existe("c_col_tc_src", "tcstamp")
	msg("As tabelas TC e TI não têm tcstamp/tistamp. Confirme que a origem é uma base PHC.")
	limpa_cursors()
	return
endif

lcCampoTecla = escolhe_coluna(m.lcCampoTecla, "c_col_ti_src", "tecla,teclas,tikey,chave,atalho,hotkey,combinacao")
lcCampoEcra = escolhe_coluna(m.lcCampoEcra, "c_col_tc_src", "ecran,ecra,tctab,tabela")
if empty(m.lcCampoTecla) or empty(m.lcCampoEcra)
	msg("Não encontrei o campo da conjugação de teclas ou o campo do ecrã." + chr(13) + ;
		"Preencha lcCampoTecla e lcCampoEcra no início do programa com os nomes reais.")
	limpa_cursors()
	return
endif

lcSql = "SELECT tc." + qid(m.lcCampoEcra) + " AS ecran, ti." + qid(m.lcCampoTecla) + " AS tecla, " + ;
	"ti.tistamp, ti.tcstamp " + ;
	"FROM " + qtab(m.lcBdOrigem, m.lcEsqOrigem, "ti") + " ti " + ;
	"INNER JOIN " + qtab(m.lcBdOrigem, m.lcEsqOrigem, "tc") + " tc ON tc.tcstamp = ti.tcstamp "
if not empty(m.lcTiStamp)
	lcSql = m.lcSql + "WHERE RTRIM(ti.tistamp) = " + sql_txt(alltrim(m.lcTiStamp), "varchar") + " "
endif
lcSql = m.lcSql + "ORDER BY 1, 2"

if not u_sqlexec(m.lcSql, "c_chaves_raw")
	msg("Não foi possível ler as teclas da base de origem.")
	limpa_cursors()
	return
endif

select iif(not empty(m.lcTiStamp), .t., .f.) as marca, alltrim(nvl(ecran, "")) as ecran, ;
	alltrim(nvl(tecla, "")) as tecla, alltrim(nvl(tistamp, "")) as tistamp, alltrim(nvl(tcstamp, "")) as tcstamp ;
	from c_chaves_raw ;
	into cursor c_chaves readwrite
fecha("c_chaves_raw")

if reccount("c_chaves") = 0
	msg("Não há teclas para copiar" + iif(empty(m.lcTiStamp), ".", " com o tistamp indicado."))
	limpa_cursors()
	return
endif

if not mostra_grelha("Teclas a copiar a partir de " + m.lcBdOrigem, "c_chaves", "cpytecla", ;
		"marca,ecran,tecla,tistamp", "Copiar?|Ecrã|Conjugação|tistamp")
	limpa_cursors()
	return
endif

select c_chaves
count for marca to lnTotal
if m.lnTotal = 0
	msg("Não assinalou nenhuma tecla. Não foi alterado nada.")
	limpa_cursors()
	return
endif

*------------------------------------------------------------------------------
* 3. Bases de destino
*------------------------------------------------------------------------------
if not u_sqlexec("SELECT name AS base FROM sys.databases WHERE state = 0 AND database_id > 4 AND HAS_DBACCESS(name) = 1 ORDER BY name", "c_dbs")
	msg("Não foi possível listar as bases de dados da instância.")
	limpa_cursors()
	return
endif

create cursor c_bases (marca L, base C(128), esquema C(128))
select c_dbs
scan
	lcEsq = esquema_phc(alltrim(c_dbs.base))
	if not empty(m.lcEsq) and not (upper(alltrim(c_dbs.base)) == upper(m.lcBdOrigem))
		insert into c_bases (marca, base, esquema) values (.t., alltrim(c_dbs.base), m.lcEsq)
	endif
	select c_dbs
endscan
fecha("c_dbs")

if reccount("c_bases") = 0
	msg("Não há outras bases PHC acessíveis, com as tabelas TC e TI, nesta instância.")
	limpa_cursors()
	return
endif

if not mostra_grelha("Bases PHC de destino (as que não têm TC e TI já foram excluídas)", "c_bases", "cpytdb", ;
		"marca,base,esquema", "Atualizar?|Base de dados|Esquema")
	limpa_cursors()
	return
endif

select c_bases
count for marca to lnFeito
if m.lnFeito = 0
	msg("Não assinalou nenhuma base de destino. Não foi alterado nada.")
	limpa_cursors()
	return
endif

select c_chaves
count for marca to lnTotal
lnTotal = m.lnTotal * m.lnFeito
if not pergunta("Vão ser aplicadas " + alltrim(str(m.lnTotal)) + " operações (tecla x base)." + chr(13) + chr(13) + "Pretende continuar?", 2, , .t.)
	limpa_cursors()
	return
endif

*------------------------------------------------------------------------------
* 4. Cópia
*------------------------------------------------------------------------------
lnFeito = 0
regua(0, m.lnTotal, "A copiar teclas ...")
try
	select c_bases
	scan for marca
		lcBase = alltrim(c_bases.base)
		lcEsq = alltrim(c_bases.esquema)
		regua(1, m.lnFeito + 1, "<§" + m.lcBase + "§>")
		if not carrega_colunas(m.lcBase, m.lcEsq, "ti", "c_col_ti_dst") or not carrega_colunas(m.lcBase, m.lcEsq, "tc", "c_col_tc_dst")
			lnFalhas = m.lnFalhas + 1
			aadderros(m.lcBase + ": não foi possível ler as colunas de TC/TI. Nada foi gravado nesta base.")
		else
			select c_chaves
			scan for marca
				lnFeito = m.lnFeito + 1
				regua(1, m.lnFeito, "<§" + m.lcBase + " " + alltrim(c_chaves.ecran) + "§>")
				lcStamp = alltrim(c_chaves.tistamp)
				aplica_tecla(m.lcBase, m.lcEsq, m.lcStamp, m.lcBdOrigem, m.lcEsqOrigem, m.lcCampoTecla, m.lcCampoEcra)
				select c_chaves
			endscan
		endif
		select c_bases
	endscan
catch to loerr
	lnFalhas = m.lnFalhas + 1
	aadderros("Processamento interrompido: " + m.loerr.message)
finally
	try
		regua(2)
	catch
	endtry
endtry

*------------------------------------------------------------------------------
* 5. Resultado
*------------------------------------------------------------------------------
aadderros("Concluído. Inseridas: " + alltrim(str(m.lnIns)) + ". Atualizadas: " + alltrim(str(m.lnAtu)) + ". Não gravadas: " + alltrim(str(m.lnFalhas)) + ".")
mostraerros()
limpa_cursors()
release bescolheu, fazu_tabupdate, lnIns, lnAtu, lnFalhas, lnSeqStamp
return .t.


*==============================================================================
* Aplica uma tecla a uma base. Cada tecla é uma transação.
*==============================================================================
procedure aplica_tecla
	lparameters p_base, p_esq, p_tistamp, p_origem, p_esq_origem, p_campo_tecla, p_campo_ecra
	local llaberta, llmodoeu, lntrantes, llExiste, llTemTi, llTemTc, lcTcAlvo, lcTeclaUsar, lcTeclaOrig, lcEcra
	local lcNota, lcMsg, lcWhere, loerr, lnN

	llaberta = .f.
	llmodoeu = .f.
	lntrantes = 1
	lcMsg = ""
	lcNota = ""

	try
		llTemTi = u_sqlexec("SELECT * FROM " + qtab(m.p_origem, m.p_esq_origem, "ti") + " WHERE RTRIM(tistamp) = " + sql_txt(m.p_tistamp, "varchar"), "c_ti_src")
		if m.llTemTi and used("c_ti_src")
			llTemTi = reccount("c_ti_src") > 0
		else
			llTemTi = .f.
		endif
		if not m.llTemTi
			lcMsg = m.p_base + ": não encontrei a tecla " + m.p_tistamp + " na origem."
		else
			lcTcAlvo = alltrim(nvl(c_ti_src.tcstamp, ""))
			llTemTc = u_sqlexec("SELECT * FROM " + qtab(m.p_origem, m.p_esq_origem, "tc") + " WHERE RTRIM(tcstamp) = " + sql_txt(m.lcTcAlvo, "varchar"), "c_tc_src")
			if m.llTemTc and used("c_tc_src")
				llTemTc = reccount("c_tc_src") > 0
			else
				llTemTc = .f.
			endif
			if not m.llTemTc
				lcMsg = m.p_base + ": a tecla " + m.p_tistamp + " não tem cabeçalho TC na origem."
			else
				lcEcra = alltrim(nvl(evaluate("c_tc_src." + m.p_campo_ecra), ""))
				lcTeclaOrig = alltrim(nvl(evaluate("c_ti_src." + m.p_campo_tecla), ""))
				lntrantes = sqlgetprop(m.con_dbhandle, "Transactions")
				sqlsetprop(m.con_dbhandle, "Transactions", 2)
				llmodoeu = .t.
				llaberta = .t.

				lnN = sql_valor("SELECT COUNT(*) AS v FROM " + qtab(m.p_base, m.p_esq, "ti") + " WITH (UPDLOCK, HOLDLOCK) WHERE RTRIM(tistamp) = " + sql_txt(m.p_tistamp, "varchar"))
				if isnull(m.lnN)
					lcMsg = m.p_base + " | " + m.lcEcra + " | não gravada | não foi possível verificar se o tistamp já existe."
				else
				llExiste = m.lnN > 0
				lcTcAlvo = garante_ecra(m.p_base, m.p_esq, m.lcEcra, m.p_campo_ecra, @lcNota)
				if empty(m.lcTcAlvo)
					lcMsg = m.p_base + " | " + m.lcEcra + " | não gravada | não foi possível preparar o ecrã. " + m.lcNota
				else
					if not carrega_ocupadas(m.p_base, m.p_esq, m.lcEcra, m.p_campo_ecra, m.p_campo_tecla, m.p_tistamp)
						lcMsg = m.p_base + " | " + m.lcEcra + " | não gravada | não foi possível ler as conjugações já usadas."
					else
						lcTeclaUsar = escolhe_atalho(m.lcTeclaOrig, m.p_base)
						if empty(m.lcTeclaUsar)
							lcMsg = m.p_base + " | " + m.lcEcra + " | não gravada | não há conjugação livre a partir de " + m.lcTeclaOrig + "."
						else
							if not (upper(norm_tecla(m.lcTeclaUsar)) == upper(norm_tecla(m.lcTeclaOrig)))
								lcNota = alltrim(m.lcNota + " " + m.lcTeclaOrig + " ocupada, usada " + m.lcTeclaUsar)
							endif
							lcWhere = "RTRIM(tistamp) = " + sql_txt(m.p_tistamp, "varchar")
							if grava_linha(qtab(m.p_base, m.p_esq, "ti"), "c_ti_src", "c_col_ti_dst", iif(m.llExiste, "U", "I"), m.lcWhere, ;
									m.p_campo_tecla, m.lcTeclaUsar, m.lcTcAlvo, m.p_tistamp)
								sqlcommit(m.con_dbhandle)
								llaberta = .f.
								if m.llExiste
									lnAtu = m.lnAtu + 1
									lcMsg = m.p_base + " | " + m.lcEcra + " | atualizada | " + m.lcTeclaUsar + iif(empty(m.lcNota), "", " | " + alltrim(m.lcNota))
								else
									lnIns = m.lnIns + 1
									lcMsg = m.p_base + " | " + m.lcEcra + " | inserida | " + m.lcTeclaUsar + iif(empty(m.lcNota), "", " | " + alltrim(m.lcNota))
								endif
							else
								lcMsg = m.p_base + " | " + m.lcEcra + " | não gravada | erro ao " + iif(m.llExiste, "atualizar", "inserir") + " ti.tistamp " + m.p_tistamp + "."
							endif
						endif
					endif
				endif
				endif
			endif
		endif
	catch to loerr
		lcMsg = m.p_base + " | " + m.p_tistamp + " | não gravada | " + m.loerr.message
	finally
		if m.llaberta
			try
				sqlrollback(m.con_dbhandle)
			catch
			endtry
			llaberta = .f.
		endif
		if m.llmodoeu
			try
				sqlsetprop(m.con_dbhandle, "Transactions", m.lntrantes)
			catch
			endtry
		endif
		if used("c_ti_src")
			fecha("c_ti_src")
		endif
		if used("c_tc_src")
			fecha("c_tc_src")
		endif
		if used("c_ocup")
			fecha("c_ocup")
		endif
	endtry

	if not empty(m.lcMsg)
		aadderros(m.lcMsg)
		if not ("| inserida |" $ m.lcMsg or "| atualizada |" $ m.lcMsg)
			lnFalhas = m.lnFalhas + 1
		endif
	endif
endproc


*------------------------------------------------------------------------------
* Garante o cabeçalho do ecrã. Devolve o tcstamp a usar na linha, ou vazio.
*------------------------------------------------------------------------------
procedure garante_ecra
	lparameters p_base, p_esq, p_ecra, p_campo_ecra, p_nota
	local lcStamp, lcSql, llAchou

	p_nota = ""
	lcSql = "SELECT RTRIM(tcstamp) AS v" + iif(coluna_existe("c_col_tc_dst", "inactivo"), ", inactivo", "") + ;
		" FROM " + qtab(m.p_base, m.p_esq, "tc") + " WITH (UPDLOCK, HOLDLOCK) " + ;
		"WHERE RTRIM(" + qid(m.p_campo_ecra) + ") = " + sql_txt(m.p_ecra, "varchar")
	if not u_sqlexec(m.lcSql, "c_tc_dst")
		p_nota = "falha ao ler TC"
		return ""
	endif

	llAchou = .f.
	if used("c_tc_dst")
		llAchou = reccount("c_tc_dst") > 0
	endif
	if m.llAchou
		lcStamp = alltrim(nvl(c_tc_dst.v, ""))
		if type("c_tc_dst.inactivo") <> "U" and campo_verdadeiro("c_tc_dst", "inactivo")
			p_nota = "o cabeçalho deste ecrã está inactivo"
		endif
		fecha("c_tc_dst")
		return m.lcStamp
	endif
	if used("c_tc_dst")
		fecha("c_tc_dst")
	endif

	lcStamp = alltrim(nvl(c_tc_src.tcstamp, ""))
	lcSql = "SELECT COUNT(*) AS v FROM " + qtab(m.p_base, m.p_esq, "tc") + " WHERE RTRIM(tcstamp) = " + sql_txt(m.lcStamp, "varchar")
	if nvl(sql_valor(m.lcSql), 1) > 0
		lcStamp = novo_stamp()
		p_nota = "criado cabeçalho novo porque o tcstamp de origem já identificava outro registo"
	else
		p_nota = "criado cabeçalho do ecrã"
	endif

	if not grava_linha(qtab(m.p_base, m.p_esq, "tc"), "c_tc_src", "c_col_tc_dst", "I", "", "", "", m.lcStamp, "")
		p_nota = "não foi possível inserir o cabeçalho TC"
		return ""
	endif
	return m.lcStamp
endproc


*------------------------------------------------------------------------------
* Grava uma linha de TI ou TC com as colunas comuns aos dois lados.
* p_modo: I inserir, U atualizar. p_where sem a palavra WHERE.
*------------------------------------------------------------------------------
procedure grava_linha
	lparameters p_tabela, p_dados, p_colunas, p_modo, p_where, p_campo_tecla, p_tecla, p_tcstamp, p_tistamp
	local lcCols, lcVals, lcSets, lcNome, lcTipo, lu, lcLit, lcSql

	lcCols = ""
	lcVals = ""
	lcSets = ""
	select (m.p_colunas)
	scan
		if campo_verdadeiro(m.p_colunas, "calculada") or campo_verdadeiro(m.p_colunas, "identidade")
			loop
		endif
		lcNome = alltrim(nome)
		lcTipo = lower(alltrim(tipo))
		if inlist(m.lcTipo, "timestamp", "rowversion", "image", "binary", "varbinary")
			loop
		endif
		do case
		case lower(m.lcNome) == "tistamp"
			if m.p_modo == "U" or empty(m.p_tistamp)
				loop
			endif
			lu = m.p_tistamp
		case lower(m.lcNome) == "tcstamp" and not empty(m.p_tcstamp)
			lu = m.p_tcstamp
		case lower(m.lcNome) == lower(m.p_campo_tecla) and not empty(m.p_campo_tecla)
			lu = m.p_tecla
		case type(m.p_dados + "." + m.lcNome) = "U"
			loop
		otherwise
			lu = evaluate(m.p_dados + "." + m.lcNome)
		endcase
		lcLit = sql_txt(m.lu, m.lcTipo)
		if isnull(m.lcLit)
			loop
		endif
		lcCols = m.lcCols + iif(empty(m.lcCols), "", ", ") + qid(m.lcNome)
		lcVals = m.lcVals + iif(empty(m.lcVals), "", ", ") + m.lcLit
		if not (lower(m.lcNome) == "tistamp")
			lcSets = m.lcSets + iif(empty(m.lcSets), "", ", ") + qid(m.lcNome) + " = " + m.lcLit
		endif
	endscan

	if m.p_modo == "I"
		if empty(m.lcCols)
			return .f.
		endif
		lcSql = "INSERT INTO " + m.p_tabela + " (" + m.lcCols + ") VALUES (" + m.lcVals + ")"
	else
		if empty(m.lcSets)
			return .t.
		endif
		lcSql = "UPDATE " + m.p_tabela + " SET " + m.lcSets + " WHERE " + m.p_where
	endif
	return u_sqlexec(m.lcSql)
endproc


*------------------------------------------------------------------------------
* Lê as conjugações já usadas no ecrã, exceto a própria tecla.
*------------------------------------------------------------------------------
procedure carrega_ocupadas
	lparameters p_base, p_esq, p_ecra, p_campo_ecra, p_campo_tecla, p_tistamp
	local lcSql, llSh, llCt, llAl, lcTecla, lnSh, lnCt, lnAl

	llSh = coluna_existe("c_col_ti_dst", "shift")
	llCt = coluna_existe("c_col_ti_dst", "ctrl")
	llAl = coluna_existe("c_col_ti_dst", "alt")
	lcSql = "SELECT RTRIM(ti." + qid(m.p_campo_tecla) + ") AS tecla, " + ;
		iif(m.llSh, "CAST(ISNULL(ti." + qid("shift") + ", 0) AS int)", "CAST(0 AS int)") + " AS sh, " + ;
		iif(m.llCt, "CAST(ISNULL(ti." + qid("ctrl") + ", 0) AS int)", "CAST(0 AS int)") + " AS ct, " + ;
		iif(m.llAl, "CAST(ISNULL(ti." + qid("alt") + ", 0) AS int)", "CAST(0 AS int)") + " AS al " + ;
		"FROM " + qtab(m.p_base, m.p_esq, "ti") + " ti " + ;
		"INNER JOIN " + qtab(m.p_base, m.p_esq, "tc") + " tc ON tc.tcstamp = ti.tcstamp " + ;
		"WHERE RTRIM(tc." + qid(m.p_campo_ecra) + ") = " + sql_txt(m.p_ecra, "varchar") + ;
		" AND RTRIM(ti.tistamp) <> " + sql_txt(m.p_tistamp, "varchar")
	if used("c_ocup")
		fecha("c_ocup")
	endif
	if not u_sqlexec(m.lcSql, "c_ocup_raw")
		return .f.
	endif
	create cursor c_ocup (tecla C(240), canon C(240), sh I, ct I, al I)
	if used("c_ocup_raw")
		select c_ocup_raw
		scan
			lcTecla = alltrim(nvl(tecla, ""))
			lnSh = valor_int(sh)
			lnCt = valor_int(ct)
			lnAl = valor_int(al)
			insert into c_ocup (tecla, sh, ct, al, canon) values (m.lcTecla, m.lnSh, m.lnCt, m.lnAl, canon_tecla(m.lcTecla, m.lnSh, m.lnCt, m.lnAl))
			select c_ocup_raw
		endscan
		fecha("c_ocup_raw")
	endif
	return .t.
endproc


*------------------------------------------------------------------------------
* Conjugação a gravar. Se a de origem estiver livre, mantém-se.
*------------------------------------------------------------------------------
procedure escolhe_atalho
	lparameters p_origem, p_base
	local lcDentro, llChaveta, lnPos, lcPref, lcKey, llEspaco, lnF, lni, lnTenta, lcNova, lcCandidata

	if not atalho_ocupado(m.p_origem)
		return m.p_origem
	endif

	lcDentro = alltrim(m.p_origem)
	llChaveta = left(m.lcDentro, 1) = "{" and right(m.lcDentro, 1) = "}"
	if m.llChaveta
		lcDentro = alltrim(substr(m.lcDentro, 2, len(m.lcDentro) - 2))
	endif
	lnPos = rat("+", m.lcDentro)
	if m.lnPos = 0
		lcPref = ""
		lcKey = alltrim(m.lcDentro)
		llEspaco = .f.
	else
		lcPref = left(m.lcDentro, m.lnPos)
		llEspaco = substr(m.lcDentro, m.lnPos + 1, 1) = " "
		lcKey = alltrim(substr(m.lcDentro, m.lnPos + 1))
	endif

	if e_tecla_f(m.lcKey)
		lnF = val(substr(upper(m.lcKey), 2))
		for lni = 1 to 11
			lnTenta = m.lnF + m.lni
			if m.lnTenta > 12
				lnTenta = m.lnTenta - 12
			endif
			lcCandidata = m.lcPref + iif(m.llEspaco, " ", "") + "F" + alltrim(str(m.lnTenta))
			if m.llChaveta
				lcCandidata = "{" + m.lcCandidata + "}"
			endif
			if not atalho_ocupado(m.lcCandidata)
				return m.lcCandidata
			endif
		next
		return ""
	endif

	if len(m.lcKey) = 1 and isalpha(m.lcKey)
		for lni = 1 to 25
			lcNova = chr(asc("A") + mod(asc(upper(m.lcKey)) - asc("A") + m.lni, 26))
			if m.lcKey = lower(m.lcKey)
				lcNova = lower(m.lcNova)
			endif
			lcCandidata = m.lcPref + iif(m.llEspaco, " ", "") + m.lcNova
			if m.llChaveta
				lcCandidata = "{" + m.lcCandidata + "}"
			endif
			if not atalho_ocupado(m.lcCandidata)
				return m.lcCandidata
			endif
		next
	endif
	return ""
endproc


*------------------------------------------------------------------------------
procedure atalho_ocupado
	lparameters p_tecla
	local ll, lcCanon
	ll = .f.
	if not used("c_ocup")
		return .f.
	endif
	* Se a conjugação estiver partida (tecla F1 + coluna shift/ctrl/alt),
	* a comparação inclui essas marcas da tecla de origem.
	lcCanon = canon_tecla(m.p_tecla, flag_origem("shift"), flag_origem("ctrl"), flag_origem("alt"))
	select c_ocup
	locate for alltrim(canon) == m.lcCanon
	ll = found()
	return m.ll
endproc


*------------------------------------------------------------------------------
procedure flag_origem
	lparameters p_campo
	if not used("c_ti_src")
		return 0
	endif
	if type("c_ti_src." + m.p_campo) = "U"
		return 0
	endif
	return valor_int(evaluate("c_ti_src." + m.p_campo))
endproc


*------------------------------------------------------------------------------
procedure canon_tecla
	lparameters p_tecla, p_sh, p_ct, p_al
	local lc
	lc = norm_tecla(m.p_tecla)
	* Texto já com "+" traz os modificadores. Sem "+", as colunas shift/ctrl/alt
	* completam a conjugação (tecla F1 e shift = 1 equivale a SHIFT+F1).
	if not ("+" $ m.lc)
		if m.p_al <> 0
			lc = "ALT+" + m.lc
		endif
		if m.p_ct <> 0
			lc = "CTRL+" + m.lc
		endif
		if m.p_sh <> 0
			lc = "SHIFT+" + m.lc
		endif
	endif
	return ordena_atalho(m.lc)
endproc


*------------------------------------------------------------------------------
* Mesma conjugação, qualquer que seja a ordem dos modificadores.
*------------------------------------------------------------------------------
procedure ordena_atalho
	lparameters p_txt
	local lc, ln, lni, lcP, lcKey, lcMods
	lc = alltrim(nvl(m.p_txt, ""))
	lcKey = ""
	lcMods = ""
	ln = occurs("+", m.lc) + 1
	for lni = 1 to m.ln
		lcP = alltrim(getwordnum(m.lc, m.lni, "+"))
		do case
		case m.lcP == "SHIFT" or m.lcP == "SHFT"
			if not ("S" $ m.lcMods)
				lcMods = m.lcMods + "S"
			endif
		case m.lcP == "CTRL" or m.lcP == "CONTROL"
			if not ("C" $ m.lcMods)
				lcMods = m.lcMods + "C"
			endif
		case m.lcP == "ALT"
			if not ("A" $ m.lcMods)
				lcMods = m.lcMods + "A"
			endif
		otherwise
			if not empty(m.lcP)
				lcKey = m.lcP
			endif
		endcase
	next
	return iif("A" $ m.lcMods, "ALT+", "") + iif("C" $ m.lcMods, "CTRL+", "") + iif("S" $ m.lcMods, "SHIFT+", "") + m.lcKey
endproc


*------------------------------------------------------------------------------
procedure norm_tecla
	lparameters p_tecla
	local lc
	lc = upper(alltrim(nvl(m.p_tecla, "")))
	lc = strtran(m.lc, " ", "")
	lc = strtran(m.lc, "{", "")
	lc = strtran(m.lc, "}", "")
	return m.lc
endproc


*------------------------------------------------------------------------------
procedure e_tecla_f
	lparameters p_key
	local lc, lni, ln
	lc = upper(alltrim(m.p_key))
	if len(m.lc) < 2 or left(m.lc, 1) <> "F"
		return .f.
	endif
	for lni = 2 to len(m.lc)
		if not isdigit(substr(m.lc, m.lni, 1))
			return .f.
		endif
	next
	ln = val(substr(m.lc, 2))
	return m.ln >= 1 and m.ln <= 12
endproc


*------------------------------------------------------------------------------
* Esquema dbo (ou outro) onde existem as duas tabelas. Vazio = não é PHC.
*------------------------------------------------------------------------------
procedure esquema_phc
	lparameters p_base
	local lcSql, lcEsq, llTc, llTi
	lcSql = "SELECT t.name AS tabela, s.name AS esquema FROM " + qid(m.p_base) + ".sys.tables t " + ;
		"INNER JOIN " + qid(m.p_base) + ".sys.schemas s ON s.schema_id = t.schema_id " + ;
		"WHERE LOWER(t.name) IN ('tc', 'ti')"
	if not u_sqlexec(m.lcSql, "c_tabs")
		return ""
	endif
	lcEsq = ""
	select distinct esquema from c_tabs into cursor c_esq
	select c_esq
	scan
		llTc = .f.
		llTi = .f.
		select c_tabs
		locate for upper(alltrim(esquema)) == upper(alltrim(c_esq.esquema)) and upper(alltrim(tabela)) == "TC"
		llTc = found()
		locate for upper(alltrim(esquema)) == upper(alltrim(c_esq.esquema)) and upper(alltrim(tabela)) == "TI"
		llTi = found()
		if m.llTc and m.llTi
			if upper(alltrim(c_esq.esquema)) == "DBO" or empty(m.lcEsq)
				lcEsq = alltrim(c_esq.esquema)
			endif
		endif
		select c_esq
	endscan
	fecha("c_esq")
	fecha("c_tabs")
	return m.lcEsq
endproc


*------------------------------------------------------------------------------
procedure carrega_colunas
	lparameters p_base, p_esq, p_tabela, p_cursor
	local lcSql, lcNome, lcTipo, lnMax, lnPrec, lnEscala, llAnula, llCalc, llIdent
	lcSql = "SELECT c.name AS nome, bt.name AS tipo, c.max_length AS maxlen, c.precision AS precisao, c.scale AS escala, " + ;
		"c.is_nullable AS anulavel, c.is_computed AS calculada, c.is_identity AS identidade " + ;
		"FROM " + qid(m.p_base) + ".sys.columns c " + ;
		"INNER JOIN " + qid(m.p_base) + ".sys.types bt ON bt.user_type_id = c.system_type_id " + ;
		"INNER JOIN " + qid(m.p_base) + ".sys.tables t ON t.object_id = c.object_id " + ;
		"INNER JOIN " + qid(m.p_base) + ".sys.schemas s ON s.schema_id = t.schema_id " + ;
		"WHERE LOWER(t.name) = " + sql_txt(lower(m.p_tabela), "varchar") + " AND s.name = " + sql_txt(m.p_esq, "varchar") + ;
		" ORDER BY c.column_id"
	if not u_sqlexec(m.lcSql, "c_cols_raw")
		return .f.
	endif
	if used(m.p_cursor)
		fecha(m.p_cursor)
	endif
	create cursor (m.p_cursor) (nome C(128), tipo C(30), maxlen I, precisao I, escala I, anulavel L, calculada L, identidade L)
	select c_cols_raw
	scan
		lcNome = alltrim(nvl(nome, ""))
		lcTipo = lower(alltrim(nvl(tipo, "")))
		lnMax = valor_int(maxlen)
		lnPrec = valor_int(precisao)
		lnEscala = valor_int(escala)
		llAnula = valor_logico(anulavel)
		llCalc = valor_logico(calculada)
		llIdent = valor_logico(identidade)
		insert into &p_cursor (nome, tipo, maxlen, precisao, escala, anulavel, calculada, identidade) ;
			values (m.lcNome, m.lcTipo, m.lnMax, m.lnPrec, m.lnEscala, m.llAnula, m.llCalc, m.llIdent)
		select c_cols_raw
	endscan
	fecha("c_cols_raw")
	select (m.p_cursor)
	return reccount() > 0
endproc


*------------------------------------------------------------------------------
procedure coluna_existe
	lparameters p_cursor, p_nome
	local ll
	ll = .f.
	if not used(m.p_cursor)
		return .f.
	endif
	select (m.p_cursor)
	locate for upper(alltrim(nome)) == upper(alltrim(m.p_nome))
	ll = found()
	return m.ll
endproc


*------------------------------------------------------------------------------
procedure escolhe_coluna
	lparameters p_pedida, p_cursor, p_candidatas
	local lni, lc
	if not empty(m.p_pedida)
		if coluna_existe(m.p_cursor, m.p_pedida)
			return alltrim(m.p_pedida)
		endif
		return ""
	endif
	for lni = 1 to getwordcount(m.p_candidatas, ",")
		lc = getwordnum(m.p_candidatas, m.lni, ",")
		if coluna_existe(m.p_cursor, m.lc)
			select (m.p_cursor)
			locate for upper(alltrim(nome)) == upper(m.lc)
			return alltrim(nome)
		endif
	next
	return ""
endproc


*------------------------------------------------------------------------------
procedure mostra_grelha
	lparameters p_titulo, p_cursor, p_id, p_campos, p_tits
	local lni, lncols, lcCampo
	lncols = getwordcount(m.p_campos, ",")
	declare list_tit(m.lncols), list_pic(m.lncols), list_cam(m.lncols), list_tam(m.lncols), list_ronly(m.lncols)
	for lni = 1 to m.lncols
		lcCampo = getwordnum(m.p_campos, m.lni, ",")
		list_cam(m.lni) = m.p_cursor + "." + m.lcCampo
		list_tit(m.lni) = getwordnum(m.p_tits, m.lni, "|")
		list_pic(m.lni) = iif(m.lni = 1, "LOGIC", "")
		list_tam(m.lni) = 8 * iif(inlist(m.lcCampo, "tistamp", "base", "ecran"), 28, 16)
		list_ronly(m.lni) = m.lni > 1
	next
	=cursorsetprop("Buffering", 5, m.p_cursor)
	m.bescolheu = .f.
	m.fazu_tabupdate = .f.
	do browlist with m.p_titulo, m.p_cursor, m.p_id, .t., .f., .f., .t., .f., "", .t.
	release list_tit, list_pic, list_cam, list_tam, list_ronly
	if m.bescolheu and cursorgetprop("Buffering", m.p_cursor) > 1
		tableupdate(.t., .t., m.p_cursor)
	endif
	return m.bescolheu
endproc


*------------------------------------------------------------------------------
procedure sql_valor
	lparameters p_sql
	local lu
	lu = .null.
	if u_sqlexec(m.p_sql, "c_sqlv")
		if used("c_sqlv")
			if reccount("c_sqlv") > 0
				lu = c_sqlv.v
			endif
		endif
	endif
	if used("c_sqlv")
		fecha("c_sqlv")
	endif
	return m.lu
endproc


*------------------------------------------------------------------------------
procedure qid
	lparameters p_nome
	return "[" + strtran(alltrim(nvl(m.p_nome, "")), "]", "]]") + "]"
endproc


*------------------------------------------------------------------------------
procedure qtab
	lparameters p_base, p_esq, p_tab
	return qid(m.p_base) + "." + qid(m.p_esq) + "." + qid(m.p_tab)
endproc


*------------------------------------------------------------------------------
procedure sql_txt
	lparameters p_valor, p_tipo
	local lcTipo, lc, lcSep, lcPon
	lcTipo = lower(alltrim(nvl(m.p_tipo, "")))
	if isnull(m.p_valor)
		return "NULL"
	endif
	do case
	case inlist(m.lcTipo, "varchar", "char", "text", "nchar", "nvarchar", "ntext")
		lc = iif(vartype(m.p_valor) = "C" or vartype(m.p_valor) = "M", m.p_valor, transform(m.p_valor))
		return iif(inlist(m.lcTipo, "nchar", "nvarchar", "ntext"), "N", "") + "'" + strtran(m.lc, "'", "''") + "'"
	case inlist(m.lcTipo, "bit")
		if vartype(m.p_valor) = "L"
			return iif(m.p_valor, "1", "0")
		endif
		return iif(m.p_valor = 0, "0", "1")
	case inlist(m.lcTipo, "int", "bigint", "smallint", "tinyint")
		return alltrim(str(val(transform(m.p_valor)), 20, 0))
	case inlist(m.lcTipo, "decimal", "numeric", "money", "smallmoney", "float", "real")
		lcSep = set("SEPARATOR")
		lcPon = set("POINT")
		lc = alltrim(str(val(transform(m.p_valor)), 24, 8))
		if not empty(m.lcSep)
			lc = strtran(m.lc, m.lcSep, "")
		endif
		return strtran(m.lc, m.lcPon, ".")
	case m.lcTipo == "date"
		do case
		case empty(m.p_valor)
			return "'19000101'"
		case vartype(m.p_valor) = "T"
			return "'" + left(ttoc(m.p_valor, 1), 8) + "'"
		case vartype(m.p_valor) = "D"
			return "'" + dtos(m.p_valor) + "'"
		case vartype(m.p_valor) $ "CM"
			lc = strtran(strtran(alltrim(m.p_valor), "-", ""), "/", "")
			return "'" + left(m.lc, 8) + "'"
		otherwise
			return .null.
		endcase
	case inlist(m.lcTipo, "datetime", "datetime2", "smalldatetime")
		do case
		case empty(m.p_valor)
			return "'19000101 00:00:00'"
		case vartype(m.p_valor) = "D"
			return "'" + dtos(m.p_valor) + " 00:00:00'"
		case vartype(m.p_valor) = "T"
			return "'" + ttoc(m.p_valor, 3) + "'"
		case vartype(m.p_valor) $ "CM"
			return "'" + strtran(alltrim(m.p_valor), "'", "''") + "'"
		otherwise
			return .null.
		endcase
	otherwise
		return .null.
	endcase
endproc


*------------------------------------------------------------------------------
procedure valor_int
	lparameters p_valor
	if isnull(m.p_valor)
		return 0
	endif
	return int(val(transform(m.p_valor)))
endproc


*------------------------------------------------------------------------------
procedure valor_logico
	lparameters p_valor
	if isnull(m.p_valor)
		return .f.
	endif
	if vartype(m.p_valor) = "L"
		return m.p_valor
	endif
	return m.p_valor <> 0
endproc


*------------------------------------------------------------------------------
procedure campo_verdadeiro
	lparameters p_alias, p_campo
	local lu
	lu = evaluate(m.p_alias + "." + m.p_campo)
	return valor_logico(m.lu)
endproc


*------------------------------------------------------------------------------
procedure novo_stamp
	lnSeqStamp = m.lnSeqStamp + 1
	return left("CPY" + dtos(date()) + padl(alltrim(str(m.lnSeqStamp, 6, 0)), 6, "0") + right(strtran(sys(2015), "_", "X"), 8), 25)
endproc


*------------------------------------------------------------------------------
procedure limpa_cursors
	local la(12), lni
	la(1) = "c_chaves"
	la(2) = "c_chaves_raw"
	la(3) = "c_bases"
	la(4) = "c_dbs"
	la(5) = "c_tabs"
	la(6) = "c_esq"
	la(7) = "c_col_ti_src"
	la(8) = "c_col_tc_src"
	la(9) = "c_col_ti_dst"
	la(10) = "c_col_tc_dst"
	la(11) = "c_ti_src"
	la(12) = "c_tc_src"
	for lni = 1 to 12
		if used(la(m.lni))
			fecha(la(m.lni))
		endif
	next
	if used("c_ocup")
		fecha("c_ocup")
	endif
	if used("c_ocup_raw")
		fecha("c_ocup_raw")
	endif
	if used("c_cols_raw")
		fecha("c_cols_raw")
	endif
	if used("c_sqlv")
		fecha("c_sqlv")
	endif
	if used("c_tc_dst")
		fecha("c_tc_dst")
	endif
endproc
