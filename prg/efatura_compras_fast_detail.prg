*==============================================================================*
* E-FATURA — Importação de compras (versão completa / alternativa rápida)
*
* Ficheiro: efatura_compras_fast_detail.prg
*
* Fluxo:
*   1. Autenticação no portal (acesso.gov.pt → e-fatura)
*   2. Pedido de CABEÇALHOS com partição adaptativa (limite 300 docs/pedido)
*   3. Breakdown IVA por documento, nesta ordem:
*        a) cache local (DBF)          → dostamp = 'C'
*        b) inferência pelos totais    → dostamp = 'I'   (sem HTTP)
*        c) detalheDocumentoAdquirente → dostamp = 'D'   (HTTP, só se preciso)
*
* Não existe API oficial em lote para o detalhe IVA do adquirente.
* A inferência mono-taxa evita a maioria dos pedidos HTTP de detalhe.
*==============================================================================*

#DEFINE EFATURA_MAX_DOCS 300
#DEFINE EFATURA_IVA_TOL  0.05

*--- Objecto HTTP e flags ---*
Public mHttp, mDebug, mFormatBrow
If Type('mDebug') <> 'L'
	mDebug = .F.
EndIf
mFormatBrow = .F.

*--- Cursor configurações ---*
If !Used('crsCfgItg')
	Create Cursor crsCfgItg (Token C(254), UsrAt C(20), PwdAt C(20), ;
		Sign M, UserId C(254), SessionId C(254), Nif C(20), Tc C(254), ;
		Tv C(254), Username C(254), PartId C(254), infoMenuP C(100), ;
		DataIni D, DataFim D)
	Select crsCfgItg
	Append Blank
EndIf

proc_ensureDocCache()

mHttp = func_httpCreate()
If Isnull(mHttp)
	Mensagem('Não foi possível inicializar o componente HTTP (Chilkat).', 'Directa')
	Return
EndIf

proc_credenciaisAT()
If !func_AutentAT()
	Mensagem('Falha no acesso ao portal E-fatura', 'Directa')
	proc_httpCleanup()
	Return
EndIf

proc_comprasEfatura()

Fecha([crsCompras])
proc_httpCleanup()
Return


*##############################################################################
*#  HTTP
*##############################################################################

Function func_httpCreate
	LOCAL oHttp
	Try
		oHttp = CreateObject('Chilkat_9_5_0.Http')
	Catch
		oHttp = .Null.
	EndTry
	If Isnull(oHttp)
		Return .Null.
	EndIf

	oHttp.CloseAllConnections()
	oHttp.SaveCookies = 1
	oHttp.CookieDir = 'memory'
	oHttp.SendCookies = 1
	oHttp.KeepAlive = 1
	oHttp.SetRequestHeader('Content-Type', 'application/x-www-form-urlencoded')
	oHttp.SetRequestHeader('User-Agent', ;
		'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/49.0.2623.87 Safari/537.36')
	Return oHttp
EndFunc


Procedure proc_httpCleanup
	If Used('crsDocCache')
		Try
			Use In Select('crsDocCache')
		Catch
		EndTry
	EndIf
	If Used('crsRanges')
		Try
			Use In Select('crsRanges')
		Catch
		EndTry
	EndIf
	If Type('mHttp') = 'O' And !Isnull(mHttp)
		Try
			mHttp.CloseAllConnections()
		Catch
		EndTry
		Release mHttp
	EndIf
EndProc


Procedure proc_addAuthParams
	Lparameters toReq
	Select crsCfgItg
	toReq.AddParam('sign', Alltrim(crsCfgItg.Sign))
	toReq.AddParam('userID', Alltrim(crsCfgItg.UserId))
	toReq.AddParam('sessionID', Alltrim(crsCfgItg.SessionId))
	toReq.AddParam('nif', Alltrim(crsCfgItg.Nif))
	toReq.AddParam('tc', Alltrim(crsCfgItg.Tc))
	toReq.AddParam('tv', Alltrim(crsCfgItg.Tv))
	toReq.AddParam('userName', Alltrim(crsCfgItg.Username))
	toReq.AddParam('partID', Alltrim(crsCfgItg.PartId))
	toReq.HttpVerb = 'POST'
	toReq.ContentType = 'application/x-www-form-urlencoded'
EndProc


*##############################################################################
*#  HELPERS
*##############################################################################

Function func_isoDate
	Lparameters tdDate
	If Vartype(tdDate) <> 'D' Or Empty(tdDate)
		Return ''
	EndIf
	Return Padl(Transform(Year(tdDate)), 4, '0') + '-' + ;
		Padl(Transform(Month(tdDate)), 2, '0') + '-' + ;
		Padl(Transform(Day(tdDate)), 2, '0')
EndFunc


Function func_centsToNum
	Lparameters tcCents
	Return u_val(Alltrim(Nvl(tcCents, '0'))) / 100
EndFunc


Function func_safeStr
	Lparameters tcVal
	Return Alltrim(Nvl(tcVal, ''))
EndFunc


Function func_htmlToPlain
	Lparameters tcHtml
	LOCAL oTxt, lcOut
	If Empty(Nvl(tcHtml, ''))
		Return ''
	EndIf
	oTxt = CreateObject('Chilkat_9_5_0.HtmlToText')
	lcOut = func_safeStr(oTxt.ToText(tcHtml))
	Release oTxt
	Return lcOut
EndFunc


Function func_extractToken
	Lparameters tcBody
	LOCAL lnStart, lnEnd, lcChunk
	lnStart = At([token: `], tcBody)
	If lnStart = 0
		lnStart = At([token: '], tcBody)
		If lnStart = 0
			Return ''
		EndIf
		lcChunk = Substr(tcBody, lnStart + 8)
		lnEnd = At(['], lcChunk)
	Else
		lcChunk = Substr(tcBody, lnStart + 8)
		lnEnd = At([`], lcChunk)
	EndIf
	If lnEnd <= 1
		Return ''
	EndIf
	Return Alltrim(Left(lcChunk, lnEnd - 1))
EndFunc


Function func_extractInputAttr
	Lparameters tcInput, tcAttr
	LOCAL lcPat, lnPos, lcRest, lnEnd, lcQuote
	lcPat = Lower(tcAttr) + '='
	lnPos = Atc(lcPat, tcInput)
	If lnPos = 0
		Return ''
	EndIf
	lcRest = Alltrim(Substr(tcInput, lnPos + Len(lcPat)))
	If Empty(lcRest)
		Return ''
	EndIf
	lcQuote = Left(lcRest, 1)
	If !Inlist(lcQuote, ["], ['])
		lnEnd = At(' ', lcRest)
		If lnEnd = 0
			lnEnd = At('>', lcRest)
		EndIf
		If lnEnd <= 1
			Return ''
		EndIf
		Return Left(lcRest, lnEnd - 1)
	EndIf
	lcRest = Substr(lcRest, 2)
	lnEnd = At(lcQuote, lcRest)
	If lnEnd = 0
		Return ''
	EndIf
	Return Left(lcRest, lnEnd - 1)
EndFunc


Procedure proc_parseAuthFormFields
	Lparameters tcHtml
	LOCAL lnPos, lnEnd, lcInput, lcName, lcValue, lcRemain
	lcRemain = tcHtml
	Do While .T.
		lnPos = Atc('<input', lcRemain)
		If lnPos = 0
			Exit
		EndIf
		lcRemain = Substr(lcRemain, lnPos)
		lnEnd = At('>', lcRemain)
		If lnEnd = 0
			Exit
		EndIf
		lcInput = Left(lcRemain, lnEnd)
		lcRemain = Substr(lcRemain, lnEnd + 1)
		lcName = func_extractInputAttr(lcInput, 'name')
		lcValue = func_extractInputAttr(lcInput, 'value')
		If !Empty(lcName)
			proc_getAuthInf(lcName, lcValue)
		EndIf
	EndDo
EndProc


Procedure proc_cToD
	Lparameters mStrDate
	LOCAL mSepPos, lcDate
	If Vartype(mStrDate) = 'D'
		Return mStrDate
	EndIf
	If Vartype(mStrDate) <> 'C' Or Empty(Alltrim(mStrDate))
		Return {}
	EndIf
	lcDate = Alltrim(mStrDate)
	mSepPos = At('-', lcDate)
	If mSepPos = 0
		mSepPos = At('.', lcDate)
	EndIf
	If mSepPos = 0
		mSepPos = At('/', lcDate)
	EndIf
	* yyyy-mm-dd
	If mSepPos = 5
		Return Date(u_val(Left(lcDate, 4)), u_val(Substr(lcDate, 6, 2)), u_val(Right(lcDate, 2)))
	EndIf
	* dd-mm-yyyy
	If mSepPos = 3
		Return Date(u_val(Right(lcDate, 4)), u_val(Substr(lcDate, 4, 2)), u_val(Left(lcDate, 2)))
	EndIf
	Return {}
EndProc


Function func_getTIva
	Lparameters mTxIv
	Return GetUmValorNumerico([taxasiva], [codigo], [taxa=] + Astr(mTxIv))
EndFunc


Procedure proc_assignIvaBucket
	* Atribui base/iva/total a isenta / red / int / nor conforme a taxa %
	Lparameters tnRate, tnBase, tnIva
	LOCAL lnTot
	lnTot = Round(tnBase + tnIva, 2)
	Do Case
		Case tnRate = 0
			Replace crsCompras.incIse With tnBase
		Case InList(tnRate, 4, 5, 6)
			Replace crsCompras.incRed With tnBase, ;
				crsCompras.ivaRed With tnIva, ;
				crsCompras.txRed With tnRate, ;
				crsCompras.totRed With lnTot
		Case InList(tnRate, 9, 12, 13)
			Replace crsCompras.incInt With tnBase, ;
				crsCompras.ivaInt With tnIva, ;
				crsCompras.txInt With tnRate, ;
				crsCompras.totInt With lnTot
		Otherwise
			Replace crsCompras.incNor With tnBase, ;
				crsCompras.ivaNor With tnIva, ;
				crsCompras.txNor With tnRate, ;
				crsCompras.totNor With lnTot
	EndCase
EndProc


Procedure proc_clearIvaBuckets
	Replace crsCompras.incIse With 0, ;
		crsCompras.incRed With 0, crsCompras.ivaRed With 0, crsCompras.txRed With 0, crsCompras.totRed With 0, ;
		crsCompras.incInt With 0, crsCompras.ivaInt With 0, crsCompras.txInt With 0, crsCompras.totInt With 0, ;
		crsCompras.incNor With 0, crsCompras.ivaNor With 0, crsCompras.txNor With 0, crsCompras.totNor With 0, ;
		crsCompras.impAdicDesc With '', crsCompras.impAdicTx With 0, crsCompras.impAdicVal With 0
EndProc


Procedure proc_reconcileTotals
	If Round(crsCompras.valorTotalBaseTributavel + crsCompras.valorTotalIva + crsCompras.impAdicVal, 2) ;
			!= Round(crsCompras.valorTotal, 2)
		Replace crsCompras.impAdicVal With ;
			Round(crsCompras.valorTotal - crsCompras.valorTotalBaseTributavel - crsCompras.valorTotalIva, 2)
	EndIf
	If Round(crsCompras.incIse + crsCompras.incRed + crsCompras.incInt + crsCompras.incNor, 2) ;
			!= Round(crsCompras.valorTotalBaseTributavel, 2)
		Replace crsCompras.incIse With ;
			Round(crsCompras.valorTotalBaseTributavel - crsCompras.incRed - crsCompras.incInt - crsCompras.incNor, 2)
	EndIf
EndProc


*##############################################################################
*#  AUTENTICAÇÃO
*##############################################################################

Procedure proc_credenciaisAT
	If Reccount('crsCfgItg') = 0
		Select crsCfgItg
		Append Blank
	EndIf
	Replace crsCfgItg.UsrAt With Alltrim(GetNome('E-fatura: Utilizador', ;
		GetUmValorString([e1], [ncont], [estab=0]))) In crsCfgItg
	Replace crsCfgItg.PwdAt With Alltrim(GetNome('E-fatura: Password', ;
		Alltrim(crsCfgItg.PwdAt), '', '', 1, .T.)) In crsCfgItg
EndProc


Function func_AutentAT
	LOCAL mLogInResp, mAuthReq, mAuthResp, lcUrl, lcToken

	If Type('mHttp') <> 'O' Or Isnull(mHttp)
		mHttp = func_httpCreate()
		If Isnull(mHttp)
			Mensagem('Componente HTTP indisponível.', 'Directa')
			Return .F.
		EndIf
	EndIf

	mHttp.CloseAllConnections()
	mHttp.SaveCookies = 1
	mHttp.CookieDir = 'memory'
	mHttp.SendCookies = 1
	mHttp.KeepAlive = 1
	mHttp.SetRequestHeader('Content-Type', 'application/x-www-form-urlencoded')
	mHttp.SetRequestHeader('User-Agent', ;
		'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/49.0.2623.87 Safari/537.36')

	* 1) Página de login → CSRF token
	mLogInResp = mHttp.QuickRequest('POST', ;
		'https://www.acesso.gov.pt/jsp/loginRedirectForm.jsp?path=painelAdquirente.action&partID=EFPF')
	If mHttp.LastMethodSuccess = 0
		Mensagem(mHttp.LastErrorText, 'Directa')
		Return .F.
	EndIf
	If mLogInResp.StatusCode != 200
		Mensagem('Autenticação E-Fatura - Erro ' + Chr(13) + Astr(mLogInResp.StatusCode), 'Directa')
		Return .F.
	EndIf

	lcToken = func_extractToken(mLogInResp.BodyStr)
	If Empty(lcToken)
		Mensagem('Erro a obter o Token do portal E-fatura', 'Directa')
		Return .F.
	EndIf
	Replace crsCfgItg.Token With lcToken In crsCfgItg

	* 2) Submissão username/password + CSRF
	lcUrl = 'https://www.acesso.gov.pt/jsp/submissaoFormularioLogin' + ;
		'?path=painelAdquirente.action&partID=EFPF&authVersion=1&selectedAuthMethod=N'

	mAuthReq = CreateObject('Chilkat_9_5_0.HttpRequest')
	mAuthReq.AddParam('username', Alltrim(crsCfgItg.UsrAt))
	mAuthReq.AddParam('password', Alltrim(crsCfgItg.PwdAt))
	mAuthReq.AddParam('_csrf', Alltrim(crsCfgItg.Token))
	mAuthReq.HttpVerb = 'POST'
	mAuthReq.ContentType = 'application/x-www-form-urlencoded'

	mAuthResp = mHttp.PostUrlEncoded(lcUrl, mAuthReq)
	If mHttp.LastMethodSuccess = 0
		Mensagem(mHttp.LastErrorText, 'Directa')
		Return !Empty(crsCfgItg.SessionId)
	EndIf
	If mAuthResp.StatusCode != 200
		Mensagem('Autenticação - Erro ' + Astr(mAuthResp.StatusCode), 'Directa')
		Return !Empty(crsCfgItg.SessionId)
	EndIf

	* 3) Campos hidden do formulário de continuação
	proc_parseAuthFormFields(mAuthResp.BodyStr)
	Return !Empty(crsCfgItg.SessionId)
EndFunc


Procedure proc_getAuthInf
	Lparameters tcName, tcValue
	LOCAL lcKey, lcVal
	lcKey = Lower(Alltrim(Nvl(tcName, '')))
	lcVal = Alltrim(Nvl(tcValue, ''))
	If Empty(lcKey)
		Return
	EndIf
	Select crsCfgItg
	Do Case
		Case lcKey == 'tv'
			Replace crsCfgItg.Tv With lcVal
		Case lcKey == 'partid'
			Replace crsCfgItg.PartId With lcVal
		Case lcKey == 'sign'
			Replace crsCfgItg.Sign With lcVal
		Case lcKey == 'nif'
			Replace crsCfgItg.Nif With lcVal
		Case lcKey == 'sessionid'
			Replace crsCfgItg.SessionId With lcVal
		Case lcKey == 'username'
			Replace crsCfgItg.Username With lcVal
		Case lcKey == 'userid'
			Replace crsCfgItg.UserId With lcVal
		Case lcKey == 'tc'
			Replace crsCfgItg.Tc With lcVal
	EndCase
EndProc


*##############################################################################
*#  CACHE LOCAL (backup\efatura_doc_cache.dbf)
*##############################################################################

Procedure proc_ensureDocCache
	LOCAL lcPath, lcFile
	lcPath = Addbs(Sys(5) + Curdir()) + 'backup'
	If !Directory(lcPath)
		Md (lcPath)
	EndIf
	lcFile = Forcepath('efatura_doc_cache.dbf', lcPath)

	If Used('crsDocCache')
		Return
	EndIf

	If File(lcFile)
		Use (lcFile) In 0 Alias crsDocCache Shared
	Else
		Create Cursor crsDocCache ;
			(idDocumento C(20), hashDocumento C(10), ;
			incIse N(12,2), ;
			incRed N(12,2), ivaRed N(12,2), txRed N(8,2), totRed N(12,2), ;
			incInt N(12,2), ivaInt N(12,2), txInt N(8,2), totInt N(12,2), ;
			incNor N(12,2), ivaNor N(12,2), txNor N(8,2), totNor N(12,2), ;
			impAdicDesc C(10), impAdicTx N(12,2), impAdicVal N(12,2), ;
			origem C(1), updated D)
		Copy To (lcFile)
		Use In Select('crsDocCache')
		Use (lcFile) In 0 Alias crsDocCache Shared
	EndIf
EndProc


Function func_applyCacheToCurrent
	LOCAL lcId, lcHash, ;
		lnIncIse, lnIncRed, lnIvaRed, lnTxRed, lnTotRed, ;
		lnIncInt, lnIvaInt, lnTxInt, lnTotInt, ;
		lnIncNor, lnIvaNor, lnTxNor, lnTotNor, ;
		lcImpDesc, lnImpTx, lnImpVal

	lcId = Alltrim(crsCompras.idDocumento)
	lcHash = Alltrim(crsCompras.hashDocumento)
	If Empty(lcId) Or !Used('crsDocCache')
		Return .F.
	EndIf

	Select crsDocCache
	Seek lcId
	If !Found()
		Locate For Alltrim(idDocumento) == lcId
	EndIf
	If !Found()
		Select crsCompras
		Return .F.
	EndIf

	If !Empty(lcHash) And !Empty(crsDocCache.hashDocumento) ;
			And Alltrim(crsDocCache.hashDocumento) <> lcHash
		Select crsCompras
		Return .F.
	EndIf

	lnIncIse = crsDocCache.incIse
	lnIncRed = crsDocCache.incRed
	lnIvaRed = crsDocCache.ivaRed
	lnTxRed  = crsDocCache.txRed
	lnTotRed = crsDocCache.totRed
	lnIncInt = crsDocCache.incInt
	lnIvaInt = crsDocCache.ivaInt
	lnTxInt  = crsDocCache.txInt
	lnTotInt = crsDocCache.totInt
	lnIncNor = crsDocCache.incNor
	lnIvaNor = crsDocCache.ivaNor
	lnTxNor  = crsDocCache.txNor
	lnTotNor = crsDocCache.totNor
	lcImpDesc = crsDocCache.impAdicDesc
	lnImpTx = crsDocCache.impAdicTx
	lnImpVal = crsDocCache.impAdicVal

	Select crsCompras
	Replace ;
		incIse With lnIncIse, ;
		incRed With lnIncRed, ivaRed With lnIvaRed, txRed With lnTxRed, totRed With lnTotRed, ;
		incInt With lnIncInt, ivaInt With lnIvaInt, txInt With lnTxInt, totInt With lnTotInt, ;
		incNor With lnIncNor, ivaNor With lnIvaNor, txNor With lnTxNor, totNor With lnTotNor, ;
		impAdicDesc With lcImpDesc, impAdicTx With lnImpTx, impAdicVal With lnImpVal, ;
		dostamp With 'C'
	Return .T.
EndFunc


Procedure proc_saveCurrentToCache
	Lparameters tcOrigem
	LOCAL lcId, lcHash, ;
		lnIncIse, lnIncRed, lnIvaRed, lnTxRed, lnTotRed, ;
		lnIncInt, lnIvaInt, lnTxInt, lnTotInt, ;
		lnIncNor, lnIvaNor, lnTxNor, lnTotNor, ;
		lcImpDesc, lnImpTx, lnImpVal

	If !Used('crsDocCache')
		Return
	EndIf

	lcId = Alltrim(crsCompras.idDocumento)
	lcHash = Alltrim(crsCompras.hashDocumento)
	lnIncIse = crsCompras.incIse
	lnIncRed = crsCompras.incRed
	lnIvaRed = crsCompras.ivaRed
	lnTxRed  = crsCompras.txRed
	lnTotRed = crsCompras.totRed
	lnIncInt = crsCompras.incInt
	lnIvaInt = crsCompras.ivaInt
	lnTxInt  = crsCompras.txInt
	lnTotInt = crsCompras.totInt
	lnIncNor = crsCompras.incNor
	lnIvaNor = crsCompras.ivaNor
	lnTxNor  = crsCompras.txNor
	lnTotNor = crsCompras.totNor
	lcImpDesc = crsCompras.impAdicDesc
	lnImpTx = crsCompras.impAdicTx
	lnImpVal = crsCompras.impAdicVal

	Select crsDocCache
	Seek lcId
	If !Found()
		Locate For Alltrim(idDocumento) == lcId
	EndIf
	If !Found()
		Append Blank
		Replace idDocumento With lcId
	EndIf
	Replace ;
		hashDocumento With lcHash, ;
		incIse With lnIncIse, ;
		incRed With lnIncRed, ivaRed With lnIvaRed, txRed With lnTxRed, totRed With lnTotRed, ;
		incInt With lnIncInt, ivaInt With lnIvaInt, txInt With lnTxInt, totInt With lnTotInt, ;
		incNor With lnIncNor, ivaNor With lnIvaNor, txNor With lnTxNor, totNor With lnTotNor, ;
		impAdicDesc With lcImpDesc, impAdicTx With lnImpTx, impAdicVal With lnImpVal, ;
		origem With Left(Nvl(tcOrigem, 'I'), 1), ;
		updated With Date()

	Select crsCompras
EndProc


*##############################################################################
*#  INFERÊNCIA IVA (sem HTTP) + DETALHE HTTP (fallback)
*##############################################################################

Function func_inferIvaFromHeader
	* Registo corrente em crsCompras.
	* .T. = breakdown preenchido com confiança (mono-taxa / isento).
	* .F. = precisa de detalheDocumentoAdquirente.
	LOCAL lnBase, lnIva, lnTot, lnOutros, lnRate, lnExpected, i, laRates(10)

	lnBase = Round(crsCompras.valorTotalBaseTributavel, 2)
	lnIva  = Round(crsCompras.valorTotalIva, 2)
	lnTot  = Round(crsCompras.valorTotal, 2)
	lnOutros = Round(lnTot - lnBase - lnIva, 2)

	proc_clearIvaBuckets()

	If lnOutros <> 0
		Replace crsCompras.impAdicVal With lnOutros, crsCompras.impAdicDesc With 'OUTROS'
	EndIf

	If lnBase = 0
		Replace crsCompras.dostamp With 'I'
		Return .T.
	EndIf

	If lnIva = 0
		Replace crsCompras.incIse With lnBase, crsCompras.dostamp With 'I'
		Return .T.
	EndIf

	* Taxas PT (continente + RA frequentes)
	laRates(1) = 23
	laRates(2) = 13
	laRates(3) = 6
	laRates(4) = 22
	laRates(5) = 16
	laRates(6) = 9
	laRates(7) = 5
	laRates(8) = 4
	laRates(9) = 12
	laRates(10) = 0

	For i = 1 To 10
		lnRate = laRates(i)
		lnExpected = Round(lnBase * lnRate / 100, 2)
		If Abs(lnExpected - lnIva) <= EFATURA_IVA_TOL
			proc_assignIvaBucket(lnRate, lnBase, lnIva)
			Replace crsCompras.dostamp With 'I'
			Return .T.
		EndIf
	EndFor

	* Rácio arredondado (ainda mono-taxa)
	lnRate = Round(lnIva / lnBase * 100, 0)
	If lnRate >= 0 And lnRate <= 30
		lnExpected = Round(lnBase * lnRate / 100, 2)
		If Abs(lnExpected - lnIva) <= EFATURA_IVA_TOL
			proc_assignIvaBucket(lnRate, lnBase, lnIva)
			Replace crsCompras.dostamp With 'I'
			Return .T.
		EndIf
	EndIf

	Return .F.
EndFunc


Function func_loadOneDocDetail
	* HTTP detalhe para o registo corrente crsCompras
	LOCAL mLinReq, mLinResp, mLinRespXml, mSearchXml, mDocIvaXml, mDocIvaStr
	LOCAL mTaxRespJSon, mJSonObj, mUrl, mCnt, mImposto, mTxIva
	LOCAL lcBase, lcIva, lcTot, lnTx

	mUrl = 'https://faturas.portaldasfinancas.gov.pt/detalheDocumentoAdquirente.action' + ;
		'?idDocumento=' + Alltrim(crsCompras.idDocumento) + ;
		'&dataEmissaoDocumento=' + Alltrim(crsCompras.dataEmissaoStr)

	mLinReq = CreateObject('Chilkat_9_5_0.HttpRequest')
	proc_addAuthParams(mLinReq)
	mLinResp = mHttp.PostUrlEncoded(mUrl, mLinReq)

	If mHttp.LastMethodSuccess != 1
		If mDebug
			Mensagem(mHttp.LastErrorText, 'Directa')
		EndIf
		Return .F.
	EndIf
	If mLinResp.StatusCode != 200
		If mDebug
			Mensagem('Detalhe - Erro HTTP ' + Astr(mLinResp.StatusCode), 'Directa')
		EndIf
		Return .F.
	EndIf

	proc_clearIvaBuckets()

	mLinRespXml = CreateObject('Chilkat_9_5_0.Xml')
	mLinRespXml.LoadXml(mLinResp.BodyStr)
	mSearchXml = mLinRespXml.GetSelf()
	mDocIvaXml = mLinRespXml.SearchAllForContent(mSearchXml, '*jQuery(document)*')

	If mLinRespXml.LastMethodSuccess = 1 And !Isnull(mDocIvaXml)
		mDocIvaStr = mDocIvaXml.Content
		If At('dadosLinhasDocumento', mDocIvaStr) > 0
			mDocIvaStr = Right(mDocIvaStr, Len(mDocIvaStr) - At('dadosLinhasDocumento', mDocIvaStr) + 1)
			mDocIvaStr = Strtran(Left(mDocIvaStr, At('];', mDocIvaStr)), 'dadosLinhasDocumento = ', '')

			mTaxRespJSon = CreateObject('Chilkat_9_5_0.JsonArray')
			If mTaxRespJSon.Load(mDocIvaStr) = 1
				mCnt = 0
				Do While mCnt < mTaxRespJSon.Size
					mJSonObj = mTaxRespJSon.ObjectAt(mCnt)
					mImposto = func_safeStr(mJSonObj.StringOf('tipoTaxaIva'))
					If mImposto = 'IVA'
						mTxIva = func_safeStr(mJSonObj.StringOf('taxaIva'))
						lcBase = func_centsToNum(mJSonObj.StringOf('valorBaseTributavel'))
						lcIva  = func_centsToNum(mJSonObj.StringOf('valorIva'))
						lcTot  = func_centsToNum(mJSonObj.StringOf('valorTotal'))
						Do Case
							Case mTxIva = 'null' Or mTxIva = '0'
								Replace crsCompras.incIse With crsCompras.incIse + lcBase

							Case mTxIva = '600'
								Replace crsCompras.incRed With crsCompras.incRed + lcBase, ;
									crsCompras.ivaRed With crsCompras.ivaRed + lcIva, ;
									crsCompras.totRed With crsCompras.totRed + lcTot, ;
									crsCompras.txRed With 6

							Case mTxIva = '1300'
								Replace crsCompras.incInt With crsCompras.incInt + lcBase, ;
									crsCompras.ivaInt With crsCompras.ivaInt + lcIva, ;
									crsCompras.totInt With crsCompras.totInt + lcTot, ;
									crsCompras.txInt With 13

							Case mTxIva = '2300'
								Replace crsCompras.incNor With crsCompras.incNor + lcBase, ;
									crsCompras.ivaNor With crsCompras.ivaNor + lcIva, ;
									crsCompras.totNor With crsCompras.totNor + lcTot, ;
									crsCompras.txNor With 23

							Otherwise
								lnTx = func_centsToNum(mTxIva)
								Do Case
									Case lnTx <= 6
										Replace crsCompras.incRed With crsCompras.incRed + lcBase, ;
											crsCompras.ivaRed With crsCompras.ivaRed + lcIva, ;
											crsCompras.totRed With crsCompras.totRed + lcTot, ;
											crsCompras.txRed With lnTx
									Case lnTx <= 13
										Replace crsCompras.incInt With crsCompras.incInt + lcBase, ;
											crsCompras.ivaInt With crsCompras.ivaInt + lcIva, ;
											crsCompras.totInt With crsCompras.totInt + lcTot, ;
											crsCompras.txInt With lnTx
									Otherwise
										Replace crsCompras.incNor With crsCompras.incNor + lcBase, ;
											crsCompras.ivaNor With crsCompras.ivaNor + lcIva, ;
											crsCompras.totNor With crsCompras.totNor + lcTot, ;
											crsCompras.txNor With lnTx
								EndCase
						EndCase
					Else
						If func_centsToNum(mJSonObj.StringOf('valorIva')) != 0
							Replace crsCompras.impAdicDesc With Alltrim(mImposto), ;
								crsCompras.impAdicTx With func_centsToNum(mJSonObj.StringOf('taxaIva')), ;
								crsCompras.impAdicVal With crsCompras.impAdicVal + ;
									func_centsToNum(mJSonObj.StringOf('valorIva'))
						EndIf
					EndIf
					Release mJSonObj
					mCnt = mCnt + 1
				EndDo
			EndIf
			Release mTaxRespJSon
		EndIf
	EndIf
	Release mLinRespXml, mLinReq, mLinResp

	proc_reconcileTotals()
	Replace crsCompras.dostamp With 'D'
	Return .T.
EndFunc


Procedure proc_enrichPendingDocs
	* cache → inferência → HTTP detalhe (só residual)
	LOCAL lnTot, lnDone, lnInfer, lnHttp, lnCache, lnFail

	Select crsCompras
	Count To lnTot For Empty(Alltrim(dostamp))
	If lnTot = 0
		Return
	EndIf

	lnDone = 0
	lnInfer = 0
	lnHttp = 0
	lnCache = 0
	lnFail = 0
	Regua(0, lnTot, 'A processar breakdown IVA…')

	Select crsCompras
	Scan For Empty(Alltrim(dostamp))
		lnDone = lnDone + 1
		Regua(1, lnDone, 'IVA ' + Astr(lnDone) + '/' + Astr(lnTot) + ;
			' (cache=' + Astr(lnCache) + ' infer=' + Astr(lnInfer) + ;
			' http=' + Astr(lnHttp) + ')')

		If func_applyCacheToCurrent()
			lnCache = lnCache + 1
			Loop
		EndIf

		If func_inferIvaFromHeader()
			lnInfer = lnInfer + 1
			proc_saveCurrentToCache('I')
			Loop
		EndIf

		If func_loadOneDocDetail()
			lnHttp = lnHttp + 1
			proc_saveCurrentToCache('D')
		Else
			lnFail = lnFail + 1
			Replace crsCompras.dostamp With 'E', ;
				crsCompras.obs With Left('Erro detalhe HTTP', 254)
			If mDebug
				Mensagem('Falha no detalhe do documento ' + Alltrim(crsCompras.idDocumento), 'Directa')
			EndIf
		EndIf
	EndScan
	Regua(2)

	Mensagem('Breakdown IVA concluído' + Chr(13) + Chr(13) + ;
		'Cache: ' + Astr(lnCache) + Chr(13) + ;
		'Inferidos (sem HTTP): ' + Astr(lnInfer) + Chr(13) + ;
		'HTTP detalhe: ' + Astr(lnHttp) + Chr(13) + ;
		'Falhas: ' + Astr(lnFail) + Chr(13) + ;
		'Total: ' + Astr(lnTot), 'Directa')
EndProc


*##############################################################################
*#  COMPRAS — ORQUESTRAÇÃO
*##############################################################################

Procedure proc_comprasEfatura
	LOCAL mCtrl, llWarn

	llWarn = .F.

	If Used('crsCompras')
		Use In Select('crsCompras')
	EndIf

	Create Cursor crsCompras (pick L, idDocumento C(20), oriRec C(8), oriRecDes C(20), nifEmitente C(20), ;
		nomeEmitente C(90), nifAdquirente C(20), nifAdquirIntern C(20), nomeAdquirente C(80), atcud C(30), ;
		tipoDocumento C(8), tipoDocumentoDesc C(20), numeroDocumento C(40), hashDocumento C(10), ;
		dataEmissaoDocumento D, dataEmissaoStr C(12), isDocEstrang L, valorTotalIva N(12,2), ;
		valorTotalBaseTributavel N(12,2), valorTotal N(12,2), impAdicDesc C(10), impAdicTx N(12,2), ;
		impAdicVal N(12,2), incIse N(12,2), incRed N(12,2), ivaRed N(12,2), txRed N(8,2), ;
		totRed N(12,2), incInt N(12,2), ivaInt N(12,2), txInt N(8,2), totInt N(12,2), ;
		incNor N(12,2), ivaNor N(12,2), txNor N(8,2), totNor N(12,2), diarioCod N(8,0), ;
		diarioNm C(20), docCtbCod N(8,0), docCtbNm C(20), CSNCCod C(10), CSNCPk C(25), contaEmitente C(25), ;
		paisEmitente C(3), contaIncIse C(25), contaIncRed C(25), contaIvaRed C(25), contaIva2Red C(25), ;
		contaIvaNDRed C(25), contaIncInt C(25), contaIvaInt C(25), contaIva2Int C(25), contaIvaNDInt C(25), ;
		contaIncNor C(25), contaIvaNor C(25), contaIva2Nor C(25), contaIvaNDNor C(25), percentNDed N(12,2), ;
		contaImpAdic C(25), contaDinheiro C(25), dostamp C(25), obs C(254))

	If Used('xVars')
		Use In Select('xVars')
	EndIf
	Create Cursor xVars (no N(5), tipo C(1), Nome C(40), Pict C(100), lOrdem N(10), dValor D)

	Select xVars
	Append Blank
	Replace no With 1, tipo With 'D', Nome With 'Data inicial', Pict With '', ;
		lOrdem With 1, dValor With crsCfgItg.DataIni
	Append Blank
	Replace no With 2, tipo With 'D', Nome With 'Data Final', Pict With '', ;
		lOrdem With 2, dValor With crsCfgItg.DataFim

	mCtrl = .T.
	m.Escolheu = .F.
	m.mCaption = 'Filtro para registos de compras'
	Do While mCtrl
		Docomando("Do Form usqlvar With 'xvars',m.mCaption,.T.")
		If !m.Escolheu
			Mensagem('Operação interrompida!', 'Directa')
			Return .F.
		EndIf
		Select xVars
		Locate
		Replace crsCfgItg.DataIni With xVars.dValor In crsCfgItg
		Skip
		Replace crsCfgItg.DataFim With xVars.dValor In crsCfgItg
		If Datavazia(crsCfgItg.DataIni) Or Datavazia(crsCfgItg.DataFim) Or crsCfgItg.DataIni > crsCfgItg.DataFim
			Loop
		EndIf
		mCtrl = .F.
	EndDo

	*--- 1) Cabeçalhos (partição adaptativa do intervalo) ---*
	If !func_getDocsHeaders(@llWarn)
		Return .F.
	EndIf
	If llWarn
		Mensagem('Atenção: pelo menos um dia atingiu o limite de ' + ;
			Astr(EFATURA_MAX_DOCS) + ' documentos.' + Chr(13) + ;
			'Podem faltar documentos nesse dia.', 'Directa')
	EndIf

	If Reccount('crsCompras') = 0
		Mensagem('Sem documentos no período seleccionado.', 'Directa')
		Return .F.
	EndIf

	*--- 2) Breakdown IVA: cache → inferência → HTTP residual ---*
	proc_enrichPendingDocs()

	*--- 3) Conta fornecedor (SQL local) ---*
	Select crsCompras
	Scan For Empty(contaEmitente) And !Empty(nifEmitente)
		Replace contaEmitente With GetUmValorString([pc], [conta], ;
			[ano=] + Astr(Year(crsCfgItg.DataIni)) + ;
			[ And ncont='] + Alltrim(nifEmitente) + [' And recapit='F'])
	EndScan

	*--- 4) Lista ---*
	proc_listCompras()
	Return .T.
EndProc


Function func_getDocsHeaders
	Lparameters tlWarnDayCap
	LOCAL ldIni, ldFim, lnHits

	tlWarnDayCap = .F.

	Select crsCfgItg
	If Empty(crsCfgItg.SessionId)
		If !func_AutentAT()
			Mensagem('Falha no acesso ao portal E-fatura', 'Directa')
			Return .F.
		EndIf
	EndIf

	If Used('crsRanges')
		Use In Select('crsRanges')
	EndIf
	Create Cursor crsRanges (dIni D, dFim D, done L)
	Insert Into crsRanges Values (crsCfgItg.DataIni, crsCfgItg.DataFim, .F.)

	lnHits = 0
	Regua(0, 1, 'A obter cabeçalhos E-fatura…')
	Do While .T.
		Select crsRanges
		Locate For !done
		If !Found()
			Exit
		EndIf
		ldIni = crsRanges.dIni
		ldFim = crsRanges.dFim
		Replace crsRanges.done With .T.

		lnHits = lnHits + 1
		Regua(1, lnHits, 'Pedido ' + Astr(lnHits) + ': ' + Dtoc(ldIni) + ' → ' + Dtoc(ldFim))

		If !func_fetchDocsRange(ldIni, ldFim, @tlWarnDayCap)
			Regua(2)
			Return .F.
		EndIf
	EndDo
	Regua(2)
	Return .T.
EndFunc


Function func_fetchDocsRange
	Lparameters tdIni, tdFim, tlWarnDayCap
	LOCAL mDocReq, mDocResp, mDocRespJSon, mUrl, mNumDocs, mNumElem, i, ldMid

	mUrl = 'https://faturas.portaldasfinancas.gov.pt/json/obterDocumentosAdquirente.action' + ;
		'?dataInicioFilter=' + func_isoDate(tdIni) + ;
		'&dataFimFilter=' + func_isoDate(tdFim) + ;
		'&ambitoAquisicaoFilter=TODOS'

	mDocReq = CreateObject('Chilkat_9_5_0.HttpRequest')
	proc_addAuthParams(mDocReq)
	mDocResp = mHttp.PostUrlEncoded(mUrl, mDocReq)

	If mHttp.LastMethodSuccess != 1
		If mDebug
			Mensagem(mHttp.LastErrorText, 'Directa')
		Else
			Mensagem('Erro a transferir cabeçalhos E-Fatura', 'Directa')
		EndIf
		Return .F.
	EndIf
	If mDocResp.StatusCode != 200
		Mensagem('Consulta Docs - Erro ' + Astr(mDocResp.StatusCode), 'Directa')
		Return .F.
	EndIf

	mDocRespJSon = CreateObject('Chilkat_9_5_0.JsonObject')
	If mDocRespJSon.Load(mDocResp.BodyStr) <> 1
		Mensagem('Resposta JSON inválida do E-Fatura.', 'Directa')
		Return .F.
	EndIf

	mNumDocs = mDocRespJSon.SizeOfArray('linhas')
	mNumElem = mDocRespJSon.IntOf('numElementos')
	If mNumElem <= 0
		mNumElem = mNumDocs
	EndIf

	* Limite AT → bissectar intervalo (excepto dia único)
	If mNumElem >= EFATURA_MAX_DOCS Or mNumDocs >= EFATURA_MAX_DOCS
		If tdIni < tdFim
			ldMid = tdIni + Int((tdFim - tdIni) / 2)
			Insert Into crsRanges Values (tdIni, ldMid, .F.)
			Insert Into crsRanges Values (ldMid + 1, tdFim, .F.)
			Release mDocReq, mDocResp, mDocRespJSon
			Return .T.
		Else
			tlWarnDayCap = .T.
		EndIf
	EndIf

	i = 0
	Do While i < mNumDocs
		mDocRespJSon.I = i
		Select crsCompras
		Append Blank
		Replace ;
			pick With .F., ;
			dostamp With '', ;
			idDocumento With func_safeStr(mDocRespJSon.StringOf('linhas[i].idDocumento')), ;
			nifEmitente With func_safeStr(mDocRespJSon.StringOf('linhas[i].nifEmitente')), ;
			nomeEmitente With func_htmlToPlain(mDocRespJSon.StringOf('linhas[i].nomeEmitente')), ;
			nifAdquirente With func_safeStr(mDocRespJSon.StringOf('linhas[i].nifAdquirente')), ;
			nomeAdquirente With func_htmlToPlain(mDocRespJSon.StringOf('linhas[i].nomeAdquirente')), ;
			tipoDocumento With func_safeStr(mDocRespJSon.StringOf('linhas[i].tipoDocumento')), ;
			tipoDocumentoDesc With func_htmlToPlain(mDocRespJSon.StringOf('linhas[i].tipoDocumentoDesc')), ;
			numeroDocumento With func_htmlToPlain(mDocRespJSon.StringOf('linhas[i].numerodocumento')), ;
			hashDocumento With func_safeStr(mDocRespJSon.StringOf('linhas[i].hashDocumento')), ;
			dataEmissaoDocumento With proc_cToD(mDocRespJSon.StringOf('linhas[i].dataEmissaoDocumento')), ;
			dataEmissaoStr With func_safeStr(mDocRespJSon.StringOf('linhas[i].dataEmissaoDocumento')), ;
			valorTotal With func_centsToNum(mDocRespJSon.StringOf('linhas[i].valorTotal')), ;
			valorTotalIva With func_centsToNum(mDocRespJSon.StringOf('linhas[i].valorTotalIva')), ;
			valorTotalBaseTributavel With func_centsToNum(mDocRespJSon.StringOf('linhas[i].valorTotalBaseTributavel')), ;
			paisEmitente With 'PT', ;
			oriRec With func_safeStr(mDocRespJSon.StringOf('linhas[i].origemRegisto')), ;
			oriRecDes With func_safeStr(mDocRespJSon.StringOf('linhas[i].origemRegistoDesc')), ;
			nifAdquirIntern With func_safeStr(mDocRespJSon.StringOf('linhas[i].nifAdquirenteInternac')), ;
			atcud With func_safeStr(mDocRespJSon.StringOf('linhas[i].atcud')), ;
			isDocEstrang With (Lower(func_safeStr(mDocRespJSon.StringOf('linhas[i].isDocumentoEstrangeiro'))) <> 'false')
		i = i + 1
	EndDo

	Release mDocReq, mDocResp, mDocRespJSon
	Return .T.
EndFunc


*##############################################################################
*#  LISTAGEM
*##############################################################################

Procedure proc_listCompras
	mFormatBrow = .F.
	Select crsCompras
	Declare list_tit(14), list_cam(14), list_tam(14), list_pic(14), list_rot(14), list_DyCurrControl(14)

	list_tit(1) = 'Seleção'
	list_tit(2) = 'Emitente'
	list_tit(3) = 'Nif Emitente'
	list_tit(4) = 'Documento'
	list_tit(5) = 'Doc. nº'
	list_tit(6) = 'Data'
	list_tit(7) = 'Incidência'
	list_tit(8) = 'Iva'
	list_tit(9) = 'Out.Imposto'
	list_tit(10) = 'Total'
	list_tit(11) = 'Inc. Isenta'
	list_tit(12) = 'Inc. Red.'
	list_tit(13) = 'Inc. Interm.'
	list_tit(14) = 'Inc. Norm.'

	list_cam(1) = 'crsCompras.pick'
	list_cam(2) = 'crsCompras.nomeEmitente'
	list_cam(3) = 'crsCompras.nifEmitente'
	list_cam(4) = "'('+Alltrim(crsCompras.tipoDocumento)+') '+Alltrim(crsCompras.tipoDocumentoDesc)"
	list_cam(5) = 'crsCompras.numerodocumento'
	list_cam(6) = 'crsCompras.dataEmissaoDocumento'
	list_cam(7) = 'crsCompras.valorTotalBaseTributavel'
	list_cam(8) = 'crsCompras.valorTotalIva'
	list_cam(9) = 'crsCompras.impAdicVal'
	list_cam(10) = 'crsCompras.valorTotal'
	list_cam(11) = 'crsCompras.incIse'
	list_cam(12) = 'crsCompras.incRed'
	list_cam(13) = 'crsCompras.incInt'
	list_cam(14) = 'crsCompras.incNor'

	list_pic = ''
	list_pic(1) = 'LOGIC'
	list_tam = 8 * 20
	list_tam(2) = 8 * 40
	list_tam(4) = 8 * 40
	list_rot(5) = 'proc_showDetail()'
	list_DyCurrControl = 'proc_formatBrow()'

	Browlist('Listagem de documentos de compra', 'crsCompras', 'listCompras', ;
		.F., .F., .F., .T., .F., '', .T., .T.)
	Release list_tit, list_cam, list_tam, list_pic, list_rot, list_DyCurrControl
EndProc


Procedure proc_formatBrow
	Parameters cmp1, cmp2, campo_a, campo_b, campo_c
	If Type('mFormatBrow') <> 'L'
		Public mFormatBrow
		mFormatBrow = .F.
	EndIf
	If !mFormatBrow
		Zoom Window browlist Max
		browlist.Filtragrid1.Visible = .T.
		mFormatBrow = .T.
	EndIf
EndProc


Procedure proc_showDetail
	Lparameters mParA, mParB
	LOCAL mIdDoc

	* Se ainda sem breakdown, tenta enriquecer este registo
	If Empty(Alltrim(crsCompras.dostamp)) Or crsCompras.dostamp = 'E'
		If !func_applyCacheToCurrent()
			If !func_inferIvaFromHeader()
				func_loadOneDocDetail()
			Else
				proc_saveCurrentToCache('I')
			EndIf
		EndIf
	EndIf

	mIdDoc = crsCompras.idDocumento
	Select * From crsCompras Where crsCompras.idDocumento = mIdDoc Into Cursor crsTmp ReadWrite
	Mostrameisto([crsTmp])
	Fecha([crsTmp])
EndProc
