*==============================================================================*
* Importação de movimentos de controlo de ponto → tabela hs (PHC)
*
* Tipos suportados (ecrã Horas de Funcionário):
*   1  Horas Extraordinárias  (hshe)
*   2  Faltas                 (ty)
*   3  Subsídio de refeição   (cm6 / movimentos variáveis)
*
* Melhorias face ao original:
*  - Mapeamento exacto do tipo de ficheiro (já não depende de SET EXACT)
*  - Leitura xVars por no= em vez de Skip na ordem física
*  - Excel: Value em bloco, última linha real (não UsedRange.Rows.Count),
*    folhas pelo nome, ReadOnly, Quit/Release em Finally (sem processos zombie)
*  - Não pára na primeira linha vazia; ignora buracos no meio da folha
*  - Datas a partir do Value COM (não .Text / CToD frágil)
*  - Horas HH:MM e quantidade decimal; "1" já não vira 1.02 nem "1,5" vira 1.53
*  - Recno() da linha Excel guardado ANTES dos lookups (linha de erro correcta)
*  - mDescTipo reiniciado por registo (já não herda o anterior)
*  - Aspas em nomes (D'Almeida) escapadas no INSERT
*  - Validação em lote (pe/hshe/ty/cm6 em cursor); duplicados no mês
*  - Erros mostrados ANTES do preview; transacção BEGIN/COMMIT/ROLLBACK
*  - Regua de importação com Recno() (já não fica sempre a 100%)
*  - Return antes dos PROCEDURE/FUNCTION (não cai no proc_insErr)
*==============================================================================*

#IFNDEF HS_IMPORT_TIMECONTROL
#DEFINE HS_IMPORT_TIMECONTROL .T.
#ENDIF
#DEFINE xlUp -4162

LOCAL mTipoFich, mAnoProc, mMesProc, mCodTpFich
LOCAL mImportFile, mSelSheet, mImportSheet, mLastRow, mDataProc
LOCAL mImportedRecords, mOldAlias, mHsIns, mOk, mNins, mExcelOk, mExcelMsg
LOCAL oExcel, oWorkbook, oSheet, oErr
LOCAL i, nSheets, nUsed

mOldAlias = Alias()
mTipoFich = ''
mAnoProc = Year(Date())
mMesProc = Month(Date())
mCodTpFich = 0
oExcel = .NULL.
oWorkbook = .NULL.
oSheet = .NULL.

*--- Controlo de registo em edição (quando corre no ecrã hs) ---*
If Type('SHs') = 'O' And !Isnull(SHs)
	If Used('hs')
		Select hs
	EndIf
	If SHs.Adding Or SHs.Editing
		Mensagem('O registo atual está em edição. Grave o seu trabalho antes de continuar.','Directa')
		Return .F.
	EndIf
EndIf

*--- Parâmetros de importação ---*
If !proc_hsImpAskParams(@mTipoFich, @mAnoProc, @mMesProc, @mCodTpFich)
	proc_hsImpCleanup(mOldAlias)
	Return .F.
EndIf

*--- Escolher ficheiro ---*
mImportFile = GetFile("Excel:xls,xlsx,xlsm,csv;CSV:csv", "Nome do ficheiro", "Ok", 0, ;
	"Escolha o ficheiro Excel a importar")
If Empty(mImportFile) Or !File(mImportFile)
	Mensagem('Ficheiro inválido.','Directa')
	proc_hsImpCleanup(mOldAlias)
	Return .F.
EndIf

*--- Excel COM (sempre libertado no Finally; sem RETURN dentro do Try) ---*
mExcelOk = .T.
mExcelMsg = ''
Try
	Try
		oExcel = CreateObject("Excel.Application")
	Catch
		oExcel = .NULL.
	EndTry
	If Vartype(oExcel) <> 'O' Or Isnull(oExcel)
		mExcelOk = .F.
		mExcelMsg = 'Não foi possível abrir a aplicação Microsoft Excel. Verifique se o Excel está instalado.'
	EndIf

	If mExcelOk
		oExcel.DisplayAlerts = .F.
		oExcel.Visible = .F.
		oExcel.ScreenUpdating = .F.

		* Open(FileName, UpdateLinks, ReadOnly)
		oWorkbook = oExcel.Workbooks.Open(mImportFile, 0, .T.)
		If Vartype(oWorkbook) <> 'O' Or Isnull(oWorkbook)
			mExcelOk = .F.
			mExcelMsg = 'Não foi possível abrir o ficheiro Excel.'
		EndIf
	EndIf

	If mExcelOk
		* Folhas com dados (nome visível; Val("2 - Folha") = 2)
		nSheets = oWorkbook.Worksheets.Count
		Declare a_sheets(1)
		a_sheets = ""
		For i = 1 To nSheets
			nUsed = func_excelLastRow(oWorkbook.Worksheets(i), "B,C,D,F")
			If nUsed >= 2
				Aadd("a_sheets", Astr(i) + " - " + Alltrim(oWorkbook.Worksheets(i).Name))
			EndIf
		EndFor

		Do Case
		Case Alen("a_sheets") <= 1
			mExcelOk = .F.
			mExcelMsg = 'O ficheiro seleccionado aparenta estar sem dados.'
		Case Alen("a_sheets") = 2
			mSelSheet = a_sheets(2)
		Otherwise
			mSelSheet = Getnome("Folha","","Qual a folha a usar para a importação","",1,.F.,"a_sheets",.F.)
		EndCase
		Release("a_sheets")
	EndIf

	If mExcelOk
		mImportSheet = Val(Nvl(mSelSheet, ''))
		If mImportSheet = 0
			mExcelOk = .F.
			mExcelMsg = 'Operação interrompida.'
		EndIf
	EndIf

	If mExcelOk
		oSheet = oWorkbook.Worksheets(mImportSheet)
		mLastRow = func_excelLastRow(oSheet, "B,C,D,F")
		If mLastRow < 2
			mExcelOk = .F.
			mExcelMsg = 'A folha seleccionada não tem linhas de dados.'
		EndIf
	EndIf

	If mExcelOk
		Regua(0, mLastRow, "A importar itens do Excel")
		func_excelReadSheet(oSheet, mLastRow, mCodTpFich)
		Regua(2)
	EndIf

Catch To oErr
	Regua(2)
	mExcelOk = .F.
	mExcelMsg = 'Erro a ler o Excel: ' + Nvl(oErr.Message, Message())

Finally
	proc_excelRelease(@oSheet, @oWorkbook, @oExcel)
EndTry

If !mExcelOk
	If !Empty(mExcelMsg)
		Mensagem(mExcelMsg,'Directa')
	EndIf
	proc_hsImpCleanup(mOldAlias)
	Return .F.
EndIf

If !Used('crsFileImport') Or Reccount('crsFileImport') = 0
	Mensagem('Não foram encontradas linhas para importar.','Directa')
	proc_hsImpCleanup(mOldAlias)
	Return .F.
EndIf

*--- Validação ---*
mDataProc = Date(mAnoProc, mMesProc, 1)
If !proc_hsImpValidate(mCodTpFich, mTipoFich, mDataProc)
	proc_hsImpCleanup(mOldAlias)
	Return .F.
EndIf

If Used('crsErros') And Reccount('crsErros') > 0
	proc_hsImpShowErros()
	proc_hsImpCleanup(mOldAlias)
	Return .F.
EndIf

*--- Preview e confirmação ---*
m.escolheu = .F.
Mostrameisto([crsDados])
If !m.Escolheu
	proc_hsImpCleanup(mOldAlias)
	Return .F.
EndIf

*--- Inserção em transacção ---*
mImportedRecords = 0
mOk = .T.
Select crsDados
Regua(0, Reccount('crsDados'), "A importar registos de " + Alltrim(mTipoFich) + " ...")

If !u_sqlexec("BEGIN TRANSACTION")
	Regua(2)
	Mensagem('Não foi possível iniciar a transacção.' + Chr(13) + Message(),'Directa')
	proc_hsImpCleanup(mOldAlias)
	Return .F.
EndIf

Select crsDados
Scan
	Regua(1, Recno(), "Importar " + Alltrim(mTipoFich) + " para " + Alltrim(crsDados.Nome))
	mHsIns = "SET NOCOUNT ON;" + Chr(13) + func_hsImpSql(mTipoFich, mDataProc) + ;
		Chr(13) + "SELECT @@ROWCOUNT AS nins"

	Fecha([crsNins])
	If !u_sqlexec(mHsIns, [crsNins])
		mOk = .F.
		Mensagem('Ocorreu um erro a inserir o registo do funcionário ' + ;
			Alltrim(crsDados.Nome) + '.' + Chr(13) + Message(),'Directa')
		Exit
	EndIf

	mNins = 0
	If Used('crsNins') And Reccount('crsNins') > 0
		Select crsNins
		Go Top
		mNins = Nvl(nins, 0)
	EndIf
	If mNins <= 0
		mOk = .F.
		Mensagem('O INSERT não gravou linhas para o funcionário ' + Alltrim(crsDados.Nome) + ;
			' (código ' + Astr(crsDados.CodTipo) + ').','Directa')
		Exit
	EndIf

	mImportedRecords = mImportedRecords + 1
	Select crsDados
EndScan
Regua(2)

If mOk
	If !u_sqlexec("COMMIT")
		u_sqlexec("ROLLBACK")
		Mensagem('Erro no COMMIT da importação.' + Chr(13) + Message(),'Directa')
		proc_hsImpCleanup(mOldAlias)
		Return .F.
	EndIf
	Mensagem('Foram importados ' + Astr(mImportedRecords) + ;
		' registos referentes a ' + Alltrim(mTipoFich) + '.','Directa')
Else
	u_sqlexec("ROLLBACK")
	Mensagem('A importação foi anulada. Nenhum movimento ficou gravado.','Directa')
	proc_hsImpCleanup(mOldAlias)
	Return .F.
EndIf

Fecha([crsNins])
proc_hsImpCleanup(mOldAlias)
Return .T.


*==============================================================================*
* Parâmetros (usqlvar)
*==============================================================================*

Function proc_hsImpAskParams
	Lparameters tcTipoFich, tnAno, tnMes, tnCodTipo
	LOCAL mCtrl, lcTipo, lnAno, lnMes, lnCod

	Fecha([xVars])
	Create Cursor xVars (no N(5), tipo C(1), Nome C(40), Pict C(100), lOrdem N(10), ;
		nValor N(18,5), cValor C(250), tBval M)

	Select xVars
	Append Blank
	Replace no With 1, tipo With "T", Nome With "Tipo ficheiro", Pict With "", ;
		lOrdem With 1, tBval With "Horas Extraordinárias,Faltas,Sub.Refeição"

	Append Blank
	Replace no With 2, tipo With "N", Nome With "Ano Processamento", Pict With "####", ;
		lOrdem With 2, nValor With tnAno

	Append Blank
	Replace no With 3, tipo With "N", Nome With "Mês Processamento", Pict With "##", ;
		lOrdem With 3, nValor With tnMes

	mCtrl = .T.
	Do While mCtrl
		m.Escolheu = .F.
		m.mCaption = "Seleção tipo de ficheiro a importar"
		Docomando("do form usqlvar with 'xvars',m.mCaption,.F.")

		If !m.Escolheu
			Mensagem("Operação interrompida.","Directa")
			Return .F.
		EndIf

		Select xVars
		Locate For no = 1
		lcTipo = Alltrim(Nvl(cValor, ''))
		Locate For no = 2
		lnAno = nValor
		Locate For no = 3
		lnMes = nValor

		lnCod = func_codTipoFich(lcTipo)
		Do Case
		Case lnCod = 0
			Mensagem('Selecione o tipo de ficheiro válido a importar.','Directa')
		Case !Between(lnAno, Year(Date()) - 1, Year(Date()) + 1)
			Mensagem('Selecione um ano válido para processamento.','Directa')
		Case !Between(lnMes, 1, 12)
			Mensagem('Selecione um mês válido para processamento.','Directa')
		Otherwise
			mCtrl = .F.
		EndCase
	EndDo

	tcTipoFich = lcTipo
	tnAno = lnAno
	tnMes = lnMes
	tnCodTipo = lnCod
	Return .T.
EndFunc


Function func_codTipoFich
	* Comparação exacta (==) — não depende de SET EXACT
	Lparameters tcTipo
	LOCAL lc
	lc = Alltrim(Nvl(tcTipo, ''))
	Do Case
	Case lc == 'Horas Extraordinárias' Or Upper(Left(lc, 11)) == 'HORAS EXTRA'
		Return 1
	Case Upper(lc) == 'FALTAS'
		Return 2
	Case lc == 'Sub.Refeição' Or Atc('Refei', lc) > 0
		Return 3
	Otherwise
		Return 0
	EndCase
EndFunc


*==============================================================================*
* Excel
*==============================================================================*

Function func_excelLastRow
	* Última linha com dados nas colunas indicadas (ex.: "B,C,D,F").
	* UsedRange.Rows.Count falha quando o intervalo não começa na linha 1.
	Lparameters toSheet, tcCols
	LOCAL nLast, i, lcCol, nCol, nR
	nLast = 1
	If Vartype(toSheet) <> 'O' Or Isnull(toSheet)
		Return 1
	EndIf
	For i = 1 To Getwordcount(Nvl(tcCols, 'A'), ',')
		lcCol = Upper(Alltrim(Getwordnum(tcCols, i, ',')))
		If Len(lcCol) <> 1
			Loop
		EndIf
		nCol = Asc(lcCol) - 64
		Try
			nR = toSheet.Cells(toSheet.Rows.Count, nCol).End(xlUp).Row
		Catch
			nR = 1
		EndTry
		nLast = Max(nLast, Nvl(nR, 1))
	EndFor
	Return nLast
EndFunc


Function func_excelReadSheet
	Lparameters toSheet, tnLastRow, tnTipo
	LOCAL nRow, oRange, lArray, nRows, oErrRead
	LOCAL ARRAY aXls[1]

	Fecha([crsFileImport])
	Create Cursor crsFileImport (Linha N(6), CodTipo C(20), Func C(10), DataRaw C(40), ;
		HorasRaw C(20), Data D, Horas N(12,2), nCod N(8), nFunc N(6))

	If tnLastRow < 2
		Return .T.
	EndIf

	lArray = .F.
	Try
		oRange = toSheet.Range("B2:F" + Transform(tnLastRow))
		aXls = oRange.Value
		lArray = (Type('aXls[1]') <> 'U')
	Catch To oErrRead
		lArray = .F.
	EndTry
	oRange = .NULL.

	If lArray And Alen(aXls, 2) >= 5
		nRows = Alen(aXls, 1)
		For nRow = 1 To nRows
			Regua(1, nRow + 1, "Aguarde - Importando " + Astr(nRow) + " de " + Astr(nRows))
			* B=1 C=2 D=3 E=4 F=5
			proc_excelAddRow(nRow + 1, aXls[nRow, 1], aXls[nRow, 2], aXls[nRow, 3], aXls[nRow, 5], tnTipo)
		EndFor
	Else
		If lArray And Alen(aXls, 2) = 0 And Alen(aXls, 1) >= 5
			* Uma só linha de dados: vector de 5 colunas
			proc_excelAddRow(2, aXls[1], aXls[2], aXls[3], aXls[5], tnTipo)
		Else
			For nRow = 2 To tnLastRow
				Regua(1, nRow, "Aguarde - Importando " + Astr(nRow) + " de " + Astr(tnLastRow))
				proc_excelAddRow(nRow, ;
					toSheet.Range("B" + Transform(nRow)).Value, ;
					toSheet.Range("C" + Transform(nRow)).Value, ;
					toSheet.Range("D" + Transform(nRow)).Value, ;
					toSheet.Range("F" + Transform(nRow)).Value, ;
					tnTipo)
			EndFor
		EndIf
	EndIf
	Return .T.
EndFunc


Procedure proc_excelAddRow
	Lparameters tnLinha, tuCod, tuFunc, tuData, tuHoras, tnTipo
	LOCAL lcCod, lcFunc, ldData, lnHoras, lnCod, lnFunc, lcHoras

	lcCod = func_cellStr(tuCod)
	lcFunc = func_cellStr(tuFunc)
	lcHoras = func_cellStr(tuHoras)
	ldData = func_parseData(tuData)
	lnHoras = func_parseHoras(tuHoras, tnTipo)

	If Vartype(tuCod) = 'N'
		lnCod = Int(tuCod)
	Else
		lnCod = Int(u_val(lcCod))
	EndIf
	If Vartype(tuFunc) = 'N'
		lnFunc = Int(tuFunc)
	Else
		lnFunc = Int(u_val(lcFunc))
	EndIf

	* Linha completamente vazia (buraco no meio da folha) — ignorar, não parar
	If Empty(lcCod) And Empty(lcFunc) And Empty(ldData) And Empty(lcHoras)
		Return
	EndIf

	Select crsFileImport
	Append Blank
	Replace Linha With tnLinha, ;
		CodTipo With Left(lcCod, 20), ;
		Func With Left(lcFunc, 10), ;
		DataRaw With Left(func_cellStr(tuData), 40), ;
		HorasRaw With Left(lcHoras, 20), ;
		Data With ldData, ;
		Horas With lnHoras, ;
		nCod With lnCod, ;
		nFunc With lnFunc
EndProc


Procedure proc_excelRelease
	Lparameters toSheet, toWorkbook, toExcel
	toSheet = .NULL.
	If Vartype(toWorkbook) = 'O' And !Isnull(toWorkbook)
		Try
			toWorkbook.Close(.F.)
		Catch
		EndTry
	EndIf
	toWorkbook = .NULL.
	If Vartype(toExcel) = 'O' And !Isnull(toExcel)
		Try
			toExcel.ScreenUpdating = .T.
			toExcel.DisplayAlerts = .T.
			toExcel.Quit()
		Catch
		EndTry
	EndIf
	toExcel = .NULL.
EndProc


*==============================================================================*
* Parsers
*==============================================================================*

Function func_cellStr
	Lparameters tuVal
	If Isnull(tuVal) Or Vartype(tuVal) = 'X'
		Return ''
	EndIf
	If Vartype(tuVal) = 'L'
		Return Iif(tuVal, '1', '0')
	EndIf
	Return Alltrim(Transform(tuVal))
EndFunc


Function func_parseData
	Lparameters tuVal
	LOCAL lc, ld, lnY, lnM, lnD, lc1, lc2, lc3
	If Isnull(tuVal) Or Vartype(tuVal) = 'X'
		Return {}
	EndIf
	Do Case
	Case Vartype(tuVal) = 'D'
		Return tuVal
	Case Vartype(tuVal) = 'T'
		Return TToD(tuVal)
	Case Vartype(tuVal) = 'N'
		If tuVal < 1
			Return {}
		EndIf
		Try
			Return Date(1899, 12, 30) + Int(tuVal)
		Catch
			Return {}
		EndTry
	Case Vartype(tuVal) = 'C'
		lc = Alltrim(tuVal)
		If Empty(lc)
			Return {}
		EndIf
		ld = CToD(lc)
		If !Empty(ld) And Year(ld) > 1900
			Return ld
		EndIf
		lc = Strtran(Strtran(Strtran(lc, '.', '/'), '-', '/'), ' ', '')
		If Occurs('/', lc) <> 2
			Return {}
		EndIf
		lc1 = Getwordnum(lc, 1, '/')
		lc2 = Getwordnum(lc, 2, '/')
		lc3 = Getwordnum(lc, 3, '/')
		If Val(lc1) > 31
			* yyyy/mm/dd
			lnY = Val(lc1)
			lnM = Val(lc2)
			lnD = Val(lc3)
		Else
			* dd/mm/yyyy (PT)
			lnD = Val(lc1)
			lnM = Val(lc2)
			lnY = Val(lc3)
		EndIf
		If lnY > 0 And lnY < 100
			lnY = lnY + Iif(lnY < 50, 2000, 1900)
		EndIf
		If !Between(lnM, 1, 12) Or !Between(lnD, 1, 31) Or !Between(lnY, 1990, 2100)
			Return {}
		EndIf
		Try
			Return Date(lnY, lnM, lnD)
		Catch
			Return {}
		EndTry
	Otherwise
		Return {}
	EndCase
EndFunc


Function func_parseHoras
	* HH:MM[/SS] → horas decimais; sem ':' → quantidade/horas (não soma minutos).
	* Value numérico 0..1 em tipos 1/2 = fracção Excel (hora do dia) × 24.
	* Tipo 3 (refeição) trata 0..1 como quantidade, nunca como hora do dia.
	Lparameters tuVal, tnTipo
	LOCAL lcTxt, lnH, lnM, lnS, lnTipo
	lnTipo = Nvl(tnTipo, 1)
	If Isnull(tuVal) Or Vartype(tuVal) = 'X'
		Return 0
	EndIf

	Do Case
	Case Vartype(tuVal) = 'T'
		Return Round(Hour(tuVal) + (Minute(tuVal) / 60.0) + (Sec(tuVal) / 3600.0), 2)
	Case Vartype(tuVal) = 'N'
		If lnTipo <> 3 And tuVal > 0 And tuVal < 1
			Return Round(tuVal * 24, 2)
		EndIf
		Return Round(tuVal, 2)
	EndCase

	lcTxt = Alltrim(Nvl(Transform(tuVal), ''))
	lcTxt = Strtran(Strtran(lcTxt, ' ', ''), ',', '.')
	If Empty(lcTxt) Or lcTxt == '.'
		Return 0
	EndIf

	If At(':', lcTxt) > 0
		lnH = Val(Getwordnum(lcTxt, 1, ':'))
		lnM = Val(Getwordnum(lcTxt, 2, ':'))
		lnS = Val(Getwordnum(lcTxt, 3, ':'))
		Return Round(lnH + (lnM / 60.0) + (lnS / 3600.0), 2)
	EndIf

	Return Round(Val(lcTxt), 2)
EndFunc


Function func_sqlLit
	Lparameters tcVal
	Return "'" + Strtran(Alltrim(Nvl(tcVal, '')), "'", "''") + "'"
EndFunc


*==============================================================================*
* Validação
*==============================================================================*

Function proc_hsImpValidate
	Lparameters tnTipo, tcTipoFich, tdProc
	LOCAL mLinha, mNomeFunc, mStatus, mDescTipo, mForaMes, nDup, lcOld

	lcOld = Alias()
	Fecha([crsErros])
	Fecha([crsDados])
	Create Cursor crsErros (Linha N(6,0), Descricao C(254))
	Create Cursor crsDados (Linha N(6), Tipo N(1), CodTipo N(8), DescTipo C(40), ;
		Func N(6), Nome C(55), Data D, Horas N(12,2), Aviso C(120))

	If !proc_hsImpLoadLookups(tnTipo, tdProc)
		Return .F.
	EndIf

	mForaMes = 0
	Regua(0, Reccount('crsFileImport'), "A tratar registos importados")
	Select crsFileImport
	Scan
		mLinha = crsFileImport.Linha
		Regua(1, Recno(), 'Registo ' + Astr(Recno()) + '/' + Astr(Reccount('crsFileImport')))

		Select crsDados
		Append Blank
		Replace Linha With mLinha, ;
			Tipo With tnTipo, ;
			CodTipo With crsFileImport.nCod, ;
			Func With crsFileImport.nFunc, ;
			Data With crsFileImport.Data, ;
			Horas With crsFileImport.Horas

		mNomeFunc = ''
		mDescTipo = ''

		If Empty(crsDados.Func)
			proc_insErr(mLinha, 'Funcionário em falta ou código inválido (' + ;
				Alltrim(crsFileImport.Func) + ')')
		Else
			If Used('crsPeLk')
				Select crsPeLk
				Locate For no = crsDados.Func
				If !Found()
					proc_insErr(mLinha, 'Funcionário com código ' + Astr(crsDados.Func) + ' não existe')
				Else
					mStatus = u_val(Transform(Nvl(status, 0)))
					If mStatus != 1
						proc_insErr(mLinha, 'Funcionário com código ' + Astr(crsDados.Func) + ' não está ativo')
					Else
						mNomeFunc = Alltrim(Nvl(nome, ''))
						Select crsDados
						Replace Nome With mNomeFunc
					EndIf
				EndIf
			EndIf
		EndIf

		If Empty(crsDados.CodTipo)
			proc_insErr(mLinha, 'Código de ' + Alltrim(tcTipoFich) + ' em falta')
		Else
			If Used('crsTipoLk')
				Select crsTipoLk
				Locate For codigo = crsDados.CodTipo
				If !Found()
					proc_insErr(mLinha, 'Código ' + Astr(crsDados.CodTipo) + ' de ' + ;
						Alltrim(tcTipoFich) + ' não existe')
				Else
					mDescTipo = Alltrim(Nvl(descricao, ''))
					Select crsDados
					Replace DescTipo With mDescTipo
				EndIf
			EndIf
		EndIf

		If Empty(crsDados.Data)
			proc_insErr(mLinha, 'Data inválida (' + Alltrim(crsFileImport.DataRaw) + ')')
		Else
			If Year(crsDados.Data) <> Year(tdProc) Or Month(crsDados.Data) <> Month(tdProc)
				mForaMes = mForaMes + 1
				Select crsDados
				Replace Aviso With 'Data fora do mês de processamento ' + ;
					Padl(Astr(Month(tdProc)), 2, '0') + '/' + Astr(Year(tdProc))
			EndIf
		EndIf

		If crsDados.Horas <= 0
			proc_insErr(mLinha, 'Horas/quantidade inválidas (' + Alltrim(crsFileImport.HorasRaw) + ')')
		EndIf

		If !Empty(crsDados.Func) And !Empty(crsDados.Data) And !Empty(crsDados.CodTipo) And Used('crsHsEx')
			nDup = func_hsImpCountDup(tnTipo, crsDados.Func, crsDados.Data, crsDados.CodTipo)
			If nDup > 0
				proc_insErr(mLinha, 'Já existe movimento do mesmo tipo para o funcionário ' + ;
					Astr(crsDados.Func) + ' em ' + Dtoc(crsDados.Data) + ;
					' (código ' + Astr(crsDados.CodTipo) + ')')
			EndIf
		EndIf

		Select crsFileImport
	EndScan
	Regua(2)

	If mForaMes > 0 And Reccount('crsErros') = 0
		Mensagem(Astr(mForaMes) + ' registo(s) com data fora do mês de processamento. ' + ;
			'Serão gravados com dtproc = ' + Dtoc(tdProc) + '. Confirme no ecrã seguinte.','Directa')
	EndIf

	If !Empty(lcOld) And Used(lcOld)
		Select (lcOld)
	EndIf
	Return .T.
EndFunc


Function proc_hsImpLoadLookups
	Lparameters tnTipo, tdProc
	LOCAL lcSql, ldFim

	Fecha([crsPeLk])
	Fecha([crsTipoLk])
	Fecha([crsHsEx])

	If !u_sqlexec("SELECT no, nome, status FROM pe", [crsPeLk])
		Mensagem('Erro a ler funcionários (pe).' + Chr(13) + Message(),'Directa')
		Return .F.
	EndIf

	Do Case
	Case tnTipo = 1
		lcSql = "SELECT codigo, descricao FROM hshe"
	Case tnTipo = 2
		lcSql = "SELECT codigo, descricao FROM ty"
	Case tnTipo = 3
		lcSql = "SELECT cm AS codigo, cmdesc AS descricao FROM cm6"
	Otherwise
		Mensagem('Tipo de ficheiro desconhecido.','Directa')
		Return .F.
	EndCase
	If !u_sqlexec(lcSql, [crsTipoLk])
		Mensagem('Erro a ler códigos de ' + Iif(tnTipo=1,'horas extra',Iif(tnTipo=2,'faltas','refeição')) + ;
			'.' + Chr(13) + Message(),'Directa')
		Return .F.
	EndIf

	ldFim = Gomonth(tdProc, 1)
	Text To lcSql TextMerge NoShow
		SELECT no, data, ntipo,
			CAST(ISNULL(hshecod,0) AS INT) AS hshecod,
			CAST(ISNULL(tyfalta,0) AS INT) AS tyfalta,
			CAST(ISNULL(cr,0) AS INT) AS cr
		FROM hs
		WHERE ntipo = <<Astr(tnTipo)>>
		  AND marcada = 1
		  AND data >= '<<DToSQL(tdProc)>>'
		  AND data < '<<DToSQL(ldFim)>>'
	EndText
	If !u_sqlexec(lcSql, [crsHsEx])
		* Não bloquear a importação se a pesquisa de duplicados falhar
		Fecha([crsHsEx])
	EndIf
	Return .T.
EndFunc


Function func_hsImpCountDup
	Lparameters tnTipo, tnFunc, tdData, tnCod
	LOCAL nCnt
	nCnt = 0
	If !Used('crsHsEx')
		Return 0
	EndIf
	Select crsHsEx
	Do Case
	Case tnTipo = 1
		Count For no = tnFunc And data = tdData And hshecod = tnCod To nCnt
	Case tnTipo = 2
		Count For no = tnFunc And data = tdData And tyfalta = tnCod To nCnt
	Case tnTipo = 3
		Count For no = tnFunc And data = tdData And cr = tnCod To nCnt
	EndCase
	Return nCnt
EndFunc


Procedure proc_hsImpShowErros
	Select crsErros
	Declare list_tit(2), list_cam(2), list_tam(2), list_pic(2)
	list_tit(1) = "Linha"
	list_tit(2) = "Erro"
	list_cam(1) = "crsErros.Linha"
	list_cam(2) = "crsErros.Descricao"
	list_pic = ""
	list_tam(1) = 8 * 6
	list_tam(2) = 8 * 200
	Browlist('Erros na importação de dados','crsErros','crsErros',.F.,.F.,.F.,.T.,.F.,'',.T.)
EndProc


*==============================================================================*
* SQL de inserção (mapeamento original da hs, com literais seguros)
*==============================================================================*

Function func_hsImpSql
	Lparameters tcTipoFich, tdProc
	LOCAL lcSql
	lcSql = ''
	Do Case
	Case crsDados.Tipo = 1
		Text To lcSql TextMerge NoShow
			INSERT INTO hs (hsstamp, nome, data, ntipo1, no, ntipo, hshecod,
				tipohora, horas, factor, tipofalta, usadtpr, dtproc,
				ousrinis, ousrdata, ousrhora, usrinis, usrdata, usrhora, marcada)
			SELECT LEFT(NEWID(),25), <<func_sqlLit(crsDados.Nome)>>, '<<DToSQL(crsDados.Data)>>',
				<<func_sqlLit(tcTipoFich)>>, <<Astr(crsDados.Func)>>, <<Astr(crsDados.Tipo)>>,
				hshe.codigo, hshe.descricao, <<Astr(Adec_tr(crsDados.Horas))>>, hshe.factor,
				hshe.descricao, 1, '<<DToSQL(tdProc)>>',
				'PHC', CONVERT(DATE, GETDATE()), CONVERT(VARCHAR, GETDATE(),108),
				'PHC', CONVERT(DATE, GETDATE()), CONVERT(VARCHAR, GETDATE(),108), 1
			FROM hshe WHERE codigo=<<Astr(crsDados.CodTipo)>>
		EndText
	Case crsDados.Tipo = 2
		Text To lcSql TextMerge NoShow
			INSERT INTO hs (hsstamp, nome, data, ntipo1, no, ntipo, tipofalta, desconta, just, refe,
				horasfalta, fdia, bsfalta, tyfalta, tydescricao, diasfalta, diasref, anabsen, usadtpr,
				dtproc, ousrinis, ousrdata, ousrhora, usrinis, usrdata, usrhora, marcada)
			SELECT LEFT(NEWID(),25), <<func_sqlLit(crsDados.Nome)>>, '<<DToSQL(crsDados.Data)>>',
				<<func_sqlLit(tcTipoFich)>>, <<Astr(crsDados.Func)>>, <<Astr(crsDados.Tipo)>>,
				ty.descricao, ty.desconta, ty.just, ty.refe, <<Astr(Adec_tr(crsDados.Horas))>>,
				2, ty.bsfalta, ty.codigo, ty.descricao, 0, <<Iif(crsDados.Horas>=4,1,0)>>,
				ty.anabsen, 1, '<<DToSQL(tdProc)>>',
				'PHC', CONVERT(DATE, GETDATE()), CONVERT(VARCHAR, GETDATE(),108),
				'PHC', CONVERT(DATE, GETDATE()), CONVERT(VARCHAR, GETDATE(),108), 1
			FROM ty WHERE codigo=<<Astr(crsDados.CodTipo)>>
		EndText
	Case crsDados.Tipo = 3
		Text To lcSql TextMerge NoShow
			INSERT INTO hs (hsstamp, nome, data, ntipo1, no, ntipo, horas, fdia, cr,
				rem, re, rqtt, rvu, ere, ervu, pctdia, usadtpr, dtproc,
				hs3tipo, ousrinis, ousrdata, ousrhora, usrinis, usrdata, usrhora, marcada)
			SELECT LEFT(NEWID(),25), <<func_sqlLit(crsDados.Nome)>>, '<<DToSQL(crsDados.Data)>>',
				'Movimentos Variáveis', <<Astr(crsDados.Func)>>, <<Astr(crsDados.Tipo)>>,
				1, 1, cm6.cm, cm6.cmdesc, pe.refeicao, <<Astr(Adec_tr(crsDados.Horas))>>,
				pe.refeicao, pe.erefeicao, pe.erefeicao, 100, 1, '<<DToSQL(tdProc)>>',
				1, 'PHC', CONVERT(DATE, GETDATE()), CONVERT(VARCHAR, GETDATE(),108),
				'PHC', CONVERT(DATE, GETDATE()), CONVERT(VARCHAR, GETDATE(),108), 1
			FROM cm6, pe WHERE cm6.cm=<<Astr(crsDados.CodTipo)>> AND pe.no=<<Astr(crsDados.Func)>>
		EndText
	EndCase
	Return lcSql
EndFunc


*==============================================================================*
* Utilitários
*==============================================================================*

Procedure proc_insErr
	Lparameters mLinha, mErro
	LOCAL lcOld
	lcOld = Alias()
	Select crsErros
	Append Blank
	Replace Linha With mLinha, Descricao With Left(Alltrim(Nvl(mErro, '')), 254)
	If !Empty(lcOld) And Used(lcOld)
		Select (lcOld)
	EndIf
EndProc


Procedure proc_hsImpCleanup
	Lparameters tcAlias
	Regua(2)
	Fecha([xVars])
	Fecha([crsFileImport])
	Fecha([crsDados])
	Fecha([crsErros])
	Fecha([crsPeLk])
	Fecha([crsTipoLk])
	Fecha([crsHsEx])
	Fecha([crsNins])
	If !Empty(Nvl(tcAlias, '')) And Used(tcAlias)
		Select (tcAlias)
	EndIf
EndProc
