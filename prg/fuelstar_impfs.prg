*==============================================================================*
* FuelStar → PHC — importação de documentos XML (versão melhorada)
*
* Entrada:  proc_impFS()
* Relatório de sincronização: proc_recImp()
*
* Melhorias face ao original (2025.11.28):
*  - Lotes SE em cursor ReadWrite (SPT do PHC é só de leitura)
*  - FIFO por ref+armazém; parte linhas quando um lote não chega
*  - Stock virtual NÃO é revertido após o split (UPDATE…FROM inválido em VFP)
*  - Acerto de cêntimos só na ÚLTIMA fatia (não REPLACE … ALL)
*  - NC/devolução acrescenta stock no lote; não consome
*  - FI.ecusto/epcp passam a sair do epcult do lote (o original gravava 0)
*  - usalote=0 quando o lote fica vazio (o trigger de SE não corre em vão)
*  - Sem lote: Lote='' + erro (já não inventa lote '*')
*  - TipoDoc C(10) (FT_tran / FT_guia já não são truncados a 'FT')
*  - NIF como texto; datas ISO inválidas → data vazia
*  - Aspas em nomes (O'Brien) escapadas no SQL
*  - Pagamentos NC: soma Abs(valor)*sinal (já não Abs(running+novo)*sinal)
*  - Lista de XML sem SET DEFAULT / SET PATH TO cDefaultPath
*  - Entidades/artigos: lookup na leitura; criação só após confirmar
*  - Ficheiro .importado só quando todos os docs desse XML ficaram ok
*  - Anulados não consomem lotes; armazém 0 → 1
*==============================================================================*

#IFNDEF FUELSTAR_IMPFS
#DEFINE FUELSTAR_IMPFS .T.
#ENDIF

#DEFINE FS_QTY_EPS 0.0001

Procedure proc_impFS
	PRIVATE mIdImport, mDefPath, mFPath, mOldAlias

	mOldAlias = Alias()
	mDefPath = Sys(5) + CurDir()
	mFPath = '\\192.168.20.1\FuelStar\'
	*!* mFPath = 'C:\DadosPHC\PHC\PHCSOFTWARE\FuelStar\'

	ActForm('Carregando informação inicial')

	Create Cursor crsFList (FName C(200), FPath C(200))
	Create Cursor crsMapDocs (codDoc C(8), tipoDoc C(10), importPHC L)
	Create Cursor crsCliCache (noFS N(10,0), ncont C(20), noPHC N(8,0))
	Create Cursor crsRefCache (RefFS C(20), RefPHC C(18), Usalote L, PCusto N(12,4))

	Create Cursor crsDocCab (IDImport N(10,0), Area C(1), EstadoDocumento C(1), TipoDoc C(10), ;
		NumDoc C(20), DataDoc D, Cliente N(10,0), Moeda C(5), ValorIva N(12,5), ValorDesconto N(12,5), ;
		ValorTotal N(12,5), CondicaoPag C(10), DataRegisto D, HoraRegisto C(8), TipoArtigo C(4), ;
		IvaPeloAdquirente N(12,2), DataVencimento D, Nome C(100), Morada C(200), Localidade C(100), ;
		NumContribuinte C(12), HashDGCI M, ControlHash N(2), TipoDocHash C(4), CodPostal4 N(4,0), ;
		CodPostal3 N(3,0), Serie C(20), RetencaoIRS N(12,2), InvoiceNo C(20), DocumentoComIva N(1,0), ;
		Cambio N(12,5), ID N(10,0), ATCUD C(20), NumeroSerie N(10,0), TabPHC C(10), SeriePHC N(4), ;
		ClientePHC N(8,0), Iva1Inc N(12,2), Iva1Iva N(12,2), Iva2Inc N(12,2), Iva2Iva N(12,2), Iva3Inc N(12,2), ;
		Iva3Iva N(12,2), Iva4Inc N(12,2), Iva4Iva N(12,2), TotalQtt N(12,2), TotalCusto N(12,2), ;
		Numerario N(12,2), Multibanco N(12,2), MbTerm C(4), Cheque N(12,2), TrfBanc N(12,2), Sentido N(2,0), ;
		TipoNumDoc N(4), TipoTerceiro C(1), Terceiro N(10,0), NomeTerceiro C(100), Fornecedor N(10,0), ;
		DataDocTerceiro D, DocTerceiro C(20), DataDocOrig D, Estado N(1), Observacoes C(200), ;
		Autor C(20), GuiaFacturada N(1), DescontoCliente N(12,5), HashComPreco N(1), DataPagamento D, ;
		GuiaTransporte N(1), NumDocOrig N(8), Armazem N(8), Matricula C(20), Existe L, Ficheiro C(40), ;
		Sinal N(2), Ignorar L, ImportOk L)

	Create Cursor crsDocLin (IDImport N(10,0), Area C(1), ID N(10,0), NumLinha N(6,0), Produto C(20), ;
		Designacao C(40), Quantidade N(12,5), PrecoUnitario N(12,6), Desconto1 N(12,5), Desconto2 N(12,5), ;
		DescontoValor N(12,4), PercIva N(6,2), IvaIncluido N(1,0), Observacoes C(200), TipoArtigo C(4), ;
		CodIsencaoIva C(10), IsencaoIva C(200), IrsRetido N(12,2), Familia N(10), ValorLinha N(12,5), ;
		PUnitIliqIva N(12,6), DescTipo C(10), DescCodigo N(10), DescSubCod N(10), DescDescricao C(20), ;
		DescValorTotal N(12,2), refPHC C(18), PCusto N(12,4), Usalote L, Lote C(20))

	Create Cursor crsDocIVA (IDImport N(10,0), ID N(10,0), Taxa N(5,0), Valor N(12,5), ValorProd N(12,5), ;
		IvaIncluido N(1), IsencaoIva C(100), CodIsencaoIva C(10), CodigoIVA C(10))

	Create Cursor crsDocPag (IDImport N(10,0), Area C(1), ID N(10,0), Linha N(2,0), Codigo N(8), ;
		DescModoPagamento C(100), Valor N(12,5))

	If Used('crsErr')
		Select crsErr
		Zap
	Else
		Create Cursor crsErr (Classe C(20), Info C(200), Ficheiro C(40))
	EndIf

	If !u_sqlexec([Select codigo,taxa From taxasiva (Nolock) Where codigo<5], [crsTxIva])
		DeactForm()
		proc_impFSCleanup(mOldAlias, mDefPath)
		Return
	EndIf
	If Reccount('crsTxIva') = 0
		DeactForm()
		proc_impFSCleanup(mOldAlias, mDefPath)
		Return
	EndIf

	mIdImport = 1

	proc_mapDocs('190', 'DC', .T.)
	proc_mapDocs('192', 'CI', .T.)
	proc_mapDocs('248', 'RS', .T.)
	proc_mapDocs('298', 'RS', .F.)
	proc_mapDocs('B', 'ND', .T.)
	proc_mapDocs('C', 'NC', .T.)
	proc_mapDocs('D', 'FT_tran', .T.)
	proc_mapDocs('F', 'FT_guia', .T.)
	proc_mapDocs('G', 'FR', .T.)
	proc_mapDocs('W', 'FS', .T.)
	proc_mapDocs('184', 'GT', .T.)
	proc_mapDocs('181', 'GR', .F.)

	ActForm('Preparando os documentos para importar')
	If !func_getFileList(mFPath)
		DeactForm()
		proc_impFSCleanup(mOldAlias, mDefPath)
		Return
	EndIf

	DeactForm()
	Regua(0, Reccount('crsFList'), 'A processar os ficheiros recolhidos')
	Select crsFList
	Scan
		Regua(1, Recno(), 'Processando o ficheiro ' + Astr(Recno()) + ' de ' + Astr(Reccount('crsFList')))
		If !proc_getDocs(Addbs(Alltrim(crsFList.FPath)) + Alltrim(crsFList.FName))
			proc_insErr('XML', 'Falha a ler XML ' + Alltrim(crsFList.FName), Alltrim(crsFList.FName))
		EndIf
	EndScan
	Regua(2)

	If !func_prepDocs()
		proc_impFSCleanup(mOldAlias, mDefPath)
		Return
	EndIf

	m.escolheu = .F.
	proc_showDocs()
	If !m.escolheu
		proc_impFSCleanup(mOldAlias, mDefPath)
		Return
	EndIf

	If !func_insDocs()
		proc_impFSCleanup(mOldAlias, mDefPath)
		Return
	EndIf

	proc_chkImportedFiles()

	If Reccount('crsErr') > 0
		Mostrameisto([crsErr])
	Else
		Mensagem('Registos importados com sucesso', 'Directa')
	EndIf

	proc_impFSCleanup(mOldAlias, mDefPath)
EndProc

Procedure proc_impFSCleanup
	Lparameters mOldAlias, mDefPath

	Fecha([crsDocCab])
	Fecha([crsDocLin])
	Fecha([crsDocIVA])
	Fecha([crsDocPag])
	Fecha([crsTxIva])
	Fecha([crsMapDocs])
	Fecha([crsFList])
	Fecha([crsErr])
	Fecha([crsLotes])
	Fecha([crsLotesSql])
	Fecha([crsDLin])
	Fecha([crsCliCache])
	Fecha([crsRefCache])
	Fecha([crsSerFt])
	Fecha([crsSerBo])
	Fecha([crsSeries])
	Fecha([crsMapSeries])
	Fecha([crsLinhas])
	Fecha([crsLinLote])
	Fecha([crsTTIva])
	Fecha([crsFCtrl])
	Fecha([crsTmp])
	Fecha([crsICl])
	Fecha([crsISt])
	Fecha([crsIFt])
	Fecha([crsIFi])
	Fecha([crsIBO])
	Fecha([crsIBI])
	Fecha([crsSyncDoc])

	If !Empty(mDefPath)
		Try
			Set Default To (mDefPath)
		Catch
		EndTry
	EndIf
	If !Empty(mOldAlias) And Used(mOldAlias)
		Select (mOldAlias)
	EndIf
EndProc

*==============================================================================*
* Helpers
*==============================================================================*

Function func_sqlLit
	Lparameters mStr
	Return "'" + Strtran(Alltrim(Nvl(mStr, '')), "'", "''") + "'"
EndFunc

Function func_sqlNum
	Lparameters mVal, mDec
	If Pcount() < 2 Or Empty(mDec)
		mDec = 4
	EndIf
	Return Chrtran(Alltrim(Str(Nvl(mVal, 0), 22, mDec)), ',', '.')
EndFunc

Function func_formatDate
	Lparameters mDate
	Local mTxt, mY, mM, mD
	mTxt = Alltrim(Nvl(mDate, ''))
	If Len(mTxt) < 10
		Return {}
	EndIf
	mY = u_val(Left(mTxt, 4))
	mM = u_val(Substr(mTxt, 6, 2))
	mD = u_val(Substr(mTxt, 9, 2))
	If mY < 1900 Or mM < 1 Or mM > 12 Or mD < 1 Or mD > 31
		Return {}
	EndIf
	Try
		Return Date(mY, mM, mD)
	Catch
		Return {}
	EndTry
EndFunc

Function func_formatHour
	Lparameters mDate
	Local mTxt, mAt
	mTxt = Alltrim(Nvl(mDate, ''))
	mAt = At('T', mTxt)
	If mAt = 0
		Return ''
	EndIf
	Return Left(Substr(mTxt, mAt + 1), 8)
EndFunc

Function func_formatString
	Lparameters mStr
	Local mOut
	mOut = Alltrim(Nvl(mStr, ''))
	mOut = Strtran(Strtran(Strtran(mOut, Chr(39), Chr(180)), Chr(2), Chr(32)), Chr(1), Chr(32))
	Do While At('  ', mOut) > 0
		mOut = Strtran(mOut, '  ', ' ')
	EndDo
	Return mOut
EndFunc

Function func_getTabIva
	Lparameter mIVA
	Local mOld
	mOld = Alias()
	Select crsTxIva
	Locate For crsTxIva.taxa = mIVA
	If Found()
		If !Empty(mOld) And Used(mOld)
			Select (mOld)
		EndIf
		Return crsTxIva.codigo
	EndIf
	If !Empty(mOld) And Used(mOld)
		Select (mOld)
	EndIf
	Return 0
EndFunc

Function func_armazem
	Lparameters mArm
	If Empty(mArm) Or mArm = 0
		Return 1
	EndIf
	Return mArm
EndFunc

Function func_docCode
	Lparameters mArea, mTipoDoc, mTipoNum
	If Alltrim(Nvl(mArea, '')) = 'D'
		Return Alltrim(Nvl(mTipoDoc, ''))
	EndIf
	Return Alltrim(Astr(Nvl(mTipoNum, 0)))
EndFunc

*==============================================================================*
* Entidades / artigos — lookup na leitura, criação só na inserção
*==============================================================================*

Function func_getEntidade
	Lparameters mArea, mNum, mNIF
	Local mCliente, mNifTxt

	mNifTxt = Alltrim(Nvl(mNIF, ''))
	mCliente = 0

	If mNum = 0
		Return 1
	EndIf

	Select crsCliCache
	Locate For crsCliCache.noFS = mNum
	If Found() And crsCliCache.noPHC > 0
		Return crsCliCache.noPHC
	EndIf
	If !Empty(mNifTxt)
		Locate For Alltrim(crsCliCache.ncont) == mNifTxt
		If Found() And crsCliCache.noPHC > 0
			Return crsCliCache.noPHC
		EndIf
	EndIf

	mCliente = GetUmValorNumerico([cl], [no], [no=] + Astr(mNum))
	If mCliente = 0 And !Empty(mNifTxt)
		mCliente = GetUmValorNumerico([cl], [no], [ncont=] + func_sqlLit(mNifTxt))
	EndIf

	If mCliente > 0
		Select crsCliCache
		Append Blank
		Replace crsCliCache.noFS With mNum, ;
			crsCliCache.ncont With mNifTxt, ;
			crsCliCache.noPHC With mCliente
	EndIf
	Select crsDocCab
	Return mCliente
EndFunc

Function func_ensureEntidade
	Lparameters mId
	Local mCliente, mClStamp, insCl

	Select crsDocCab
	Locate For crsDocCab.IDImport = mId
	If !Found()
		Return 0
	EndIf
	If crsDocCab.clientePHC > 0
		Return crsDocCab.clientePHC
	EndIf

	mCliente = func_getEntidade(crsDocCab.Area, crsDocCab.Cliente, crsDocCab.NumContribuinte)
	If mCliente > 0
		Replace crsDocCab.clientePHC With mCliente
		Return mCliente
	EndIf

	mClStamp = u_stamp()
	Text To insCl TextMerge NoShow
		Declare @Counter Int
		Begin Transaction

		Insert Into cl (clstamp,nome,no,ncont,moeda,morada,local,codpost,tipo,
			vencimento,preco,pais,conta,pagamento,tpstamp,tpdesc,pncont,radicaltipoemp,
			descregiva,ousrinis,ousrdata,ousrhora,usrinis,usrdata,usrhora)
		Values (<<func_sqlLit(mClStamp)>>,<<func_sqlLit(crsDocCab.Nome)>>,<<Astr(crsDocCab.Cliente)>>,
			<<func_sqlLit(crsDocCab.NumContribuinte)>>,'EURO',<<func_sqlLit(crsDocCab.Morada)>>,
			<<func_sqlLit(crsDocCab.Localidade)>>,
			<<func_sqlLit(Padl(Astr(crsDocCab.CodPostal4),4,'0')+'-'+Padl(Astr(crsDocCab.CodPostal3),3,'0'))>>,
			'',0,1,1,<<func_sqlLit(Astr(21111000000+crsDocCab.Cliente))>>,'','',
			<<func_sqlLit(crsDocCab.CondicaoPag)>>,'PT',1,'PT',
			'Fuel',Convert(Date,Getdate()),Convert(Varchar(5),GetDate(),108),
			'Fuel',Convert(Date,Getdate()),Convert(Varchar(5),GetDate(),108))

		Insert Into cl2 (cl2stamp,codpais,descpais,ousrinis,ousrdata,ousrhora,usrinis,usrdata,usrhora)
		Values (<<func_sqlLit(mClStamp)>>, 'PT', 'Portugal',
			'Fuel',Convert(Date,Getdate()),Convert(Varchar(5),GetDate(),108),
			'Fuel',Convert(Date,Getdate()),Convert(Varchar(5),GetDate(),108))

		Select @Counter = Count(*) From cl (Nolock) Inner Join cl2 (Nolock) On cl.clstamp=cl2.cl2stamp
		Where cl.clstamp=<<func_sqlLit(mClStamp)>>

		If @Counter=1
			Begin
			Commit Transaction
			End
		Else
			Begin
			Rollback Transaction
			End
		Select no From cl (Nolock) Where cl.clstamp=<<func_sqlLit(mClStamp)>>
	EndText

	If !u_sqlexec(insCl, [crsICl])
		proc_insErr('Entidades', 'Erro inserir cliente: ' + Alltrim(crsDocCab.Nome), Alltrim(crsDocCab.Ficheiro))
		Return 0
	EndIf
	If Reccount('crsICl') > 0
		Select crsICl
		mCliente = crsICl.no
	EndIf
	Fecha([crsICl])
	If mCliente > 0
		Select crsDocCab
		Replace crsDocCab.clientePHC With mCliente
		Select crsCliCache
		Append Blank
		Replace crsCliCache.noFS With crsDocCab.Cliente, ;
			crsCliCache.ncont With crsDocCab.NumContribuinte, ;
			crsCliCache.noPHC With mCliente
	EndIf
	Select crsDocCab
	Return mCliente
EndFunc

Function func_getRef
	Lparameter mRefFS
	Local mRef, mKey, mUsalote, mCusto

	mKey = Alltrim(Nvl(mRefFS, ''))
	mRef = ''
	If Empty(mKey)
		Select crsDocLin
		Return ''
	EndIf

	Select crsRefCache
	Locate For Alltrim(crsRefCache.RefFS) == mKey
	If Found()
		mRef = Alltrim(crsRefCache.RefPHC)
		Select crsDocLin
		Return mRef
	EndIf

	mRef = GetUmValorString([stobs], [ref], [u_RefFS=] + func_sqlLit(mKey))
	If Empty(mRef)
		mRef = GetUmValorString([st], [ref], [ref=] + func_sqlLit(mKey))
	EndIf

	mUsalote = .F.
	mCusto = 0
	If !Empty(mRef)
		mUsalote = GetUmValorNumerico([st], [usalote], [ref=] + func_sqlLit(mRef)) <> 0
		mCusto = GetUmValorNumerico([st], [epcpond], [ref=] + func_sqlLit(mRef))
		Select crsRefCache
		Append Blank
		Replace crsRefCache.RefFS With mKey, ;
			crsRefCache.RefPHC With mRef, ;
			crsRefCache.Usalote With mUsalote, ;
			crsRefCache.PCusto With mCusto
	EndIf
	Select crsDocLin
	Return mRef
EndFunc

Function func_refUsalote
	Lparameters mRef
	Select crsRefCache
	Locate For Alltrim(crsRefCache.RefPHC) == Alltrim(Nvl(mRef, ''))
	If Found()
		Return crsRefCache.Usalote
	EndIf
	If Empty(mRef)
		Return .F.
	EndIf
	Return GetUmValorNumerico([st], [usalote], [ref=] + func_sqlLit(mRef)) <> 0
EndFunc

Function func_refPCusto
	Lparameters mRef
	Select crsRefCache
	Locate For Alltrim(crsRefCache.RefPHC) == Alltrim(Nvl(mRef, ''))
	If Found()
		Return crsRefCache.PCusto
	EndIf
	If Empty(mRef)
		Return 0
	EndIf
	Return GetUmValorNumerico([st], [epcpond], [ref=] + func_sqlLit(mRef))
EndFunc

Function func_ensureRef
	Lparameters mId, mLin
	Local mRef, mStStamp, insSt

	Select crsDocLin
	Locate For crsDocLin.IDImport = mId And crsDocLin.NumLinha = mLin
	If !Found()
		Return ''
	EndIf
	If !Empty(crsDocLin.refPHC)
		Return Alltrim(crsDocLin.refPHC)
	EndIf

	mRef = func_getRef(Alltrim(crsDocLin.Produto))
	If !Empty(mRef)
		Replace crsDocLin.refPHC With mRef, ;
			crsDocLin.Usalote With func_refUsalote(mRef), ;
			crsDocLin.PCusto With Iif(crsDocLin.PCusto = 0, func_refPCusto(mRef), crsDocLin.PCusto)
		Return Alltrim(mRef)
	EndIf

	mStStamp = u_stamp()
	Text To insSt TextMerge NoShow
		Declare @Counter Int
		Begin Transaction

		Insert Into st (ststamp,ref,design,familia,faminome,stns,
			unidade,codigo,tabiva,ivaincl,epv1,pv1,iva1incl,
			ousrinis,ousrdata,ousrhora,usrinis,usrdata,usrhora)
		Values (<<func_sqlLit(mStStamp)>>,<<func_sqlLit(crsDocLin.Produto)>>,
			<<func_sqlLit(crsDocLin.Designacao)>>,'','',0,'','',
			<<Astr(func_getTabIva(crsDocLin.PercIva))>>,
			<<Astr(crsDocLin.IvaIncluido)>>,
			<<Astr(Adec_Tr(crsDocLin.PrecoUnitario))>>,
			<<Astr(Adec_Tr(crsDocLin.PrecoUnitario*200.482))>>,
			<<Astr(crsDocLin.IvaIncluido)>>,
			'Fuel',Convert(Date,Getdate()),Convert(Varchar(5),GetDate(),108),
			'Fuel',Convert(Date,Getdate()),Convert(Varchar(5),GetDate(),108))

		Insert Into stobs (stobsstamp,ref,codmotiseimp,motiseimp,tipoprod,
			u_reffs,ousrinis,ousrdata,ousrhora,usrinis,usrdata,usrhora)
		Values (<<func_sqlLit(mStStamp)>>,<<func_sqlLit(crsDocLin.Produto)>>,
			<<func_sqlLit(crsDocLin.CodIsencaoIva)>>,<<func_sqlLit(crsDocLin.IsencaoIva)>>,
			<<func_sqlLit(crsDocLin.TipoArtigo)>>,<<func_sqlLit(crsDocLin.Produto)>>,
			'Fuel',Convert(Date,Getdate()),Convert(Varchar(5),GetDate(),108),
			'Fuel',Convert(Date,Getdate()),Convert(Varchar(5),GetDate(),108))

		Select @Counter = Count(*) From st (Nolock) Inner Join stobs (Nolock) On st.ref=stobs.ref
		Where st.ststamp=<<func_sqlLit(mStStamp)>>

		If @Counter=1
			Begin
			Commit Transaction
			End
		Else
			Begin
			Rollback Transaction
			End
		Select ref From st (Nolock) Where ststamp=<<func_sqlLit(mStStamp)>>
	EndText

	If !u_sqlexec(insSt, [crsISt])
		proc_insErr('Artigo', 'Erro inserir artigo: ' + Alltrim(crsDocLin.Designacao), '')
		Return ''
	EndIf
	If Reccount('crsISt') > 0
		Select crsISt
		mRef = Alltrim(crsISt.ref)
	EndIf
	Fecha([crsISt])
	If !Empty(mRef)
		Select crsDocLin
		Replace crsDocLin.refPHC With mRef
		Select crsRefCache
		Append Blank
		Replace crsRefCache.RefFS With Alltrim(crsDocLin.Produto), ;
			crsRefCache.RefPHC With mRef, ;
			crsRefCache.Usalote With .F., ;
			crsRefCache.PCusto With 0
	EndIf
	Select crsDocLin
	Return mRef
EndFunc

*==============================================================================*
* Ficheiros XML
*==============================================================================*

Function func_getFileList
	Lparameters mPath
	Local mNFiles, mF, mFile, mP

	If Empty(mPath)
		Mensagem('Diretoria inválida', 'DIRECTA')
		Return .F.
	EndIf

	mP = Addbs(Alltrim(mPath))
	mNFiles = Adir(a_DirFiles, mP + '*.XML')
	If mNFiles < 1
		Mensagem('Sem registos de importação para atualizar', 'DIRECTA')
		Return .F.
	EndIf

	For mF = 1 To mNFiles
		mFile = Alltrim(a_DirFiles[mF, 1])
		Select crsFList
		Append Blank
		Replace crsFList.FName With mFile, crsFList.FPath With mP
	EndFor
	Release mFile
	Return .T.
EndFunc

Procedure proc_getDocs
	Lparameters mFPName
	Local mXmlFile, i, j, lnCount_i, lnCount_j, mFich, mRef
	Local oErr

	mFich = JustFName(mFPName)
	mXmlFile = .NULL.
	Try
		mXmlFile = CreateObject('Chilkat_9_5_0.Xml')
	Catch To oErr
		mXmlFile = .NULL.
	EndTry
	If Vartype(mXmlFile) <> 'O' Or Isnull(mXmlFile)
		Return .F.
	EndIf
	If mXmlFile.LoadXmlFile(mFPName) = 0
		mXmlFile = .NULL.
		Return .F.
	EndIf

	i = 0
	lnCount_i = mXmlFile.NumChildrenHavingTag('Documentos|Documento')
	Do While i < lnCount_i
		mXmlFile.I = i

		Select crsDocCab
		Append Blank
		Replace crsDocCab.IDImport With mIdImport, ;
			crsDocCab.Area With 'D', ;
			crsDocCab.EstadoDocumento With mXmlFile.GetChildContent('Documentos|Documento[i]|EstadoDocumento'), ;
			crsDocCab.TipoDoc With mXmlFile.GetChildContent('Documentos|Documento[i]|TipoDoc'), ;
			crsDocCab.NumDoc With mXmlFile.GetChildContent('Documentos|Documento[i]|NumDoc'), ;
			crsDocCab.DataDoc With func_formatDate(mXmlFile.GetChildContent('Documentos|Documento[i]|DataDoc')), ;
			crsDocCab.Cliente With mXmlFile.GetChildIntValue('Documentos|Documento[i]|Cliente'), ;
			crsDocCab.Moeda With mXmlFile.GetChildContent('Documentos|Documento[i]|Moeda'), ;
			crsDocCab.ValorIva With u_val(mXmlFile.GetChildContent('Documentos|Documento[i]|ValorIva')), ;
			crsDocCab.ValorDesconto With u_val(mXmlFile.GetChildContent('Documentos|Documento[i]|ValorDesconto')), ;
			crsDocCab.ValorTotal With u_val(mXmlFile.GetChildContent('Documentos|Documento[i]|ValorTotal')), ;
			crsDocCab.CondicaoPag With mXmlFile.GetChildContent('Documentos|Documento[i]|CondicaoPag'), ;
			crsDocCab.DataRegisto With func_formatDate(mXmlFile.GetChildContent('Documentos|Documento[i]|DataRegisto')), ;
			crsDocCab.HoraRegisto With func_formatHour(mXmlFile.GetChildContent('Documentos|Documento[i]|DataRegisto')), ;
			crsDocCab.TipoArtigo With mXmlFile.GetChildContent('Documentos|Documento[i]|TipoArtigo'), ;
			crsDocCab.IvaPeloAdquirente With mXmlFile.GetChildIntValue('Documentos|Documento[i]|IvaPeloAdquirente'), ;
			crsDocCab.DataVencimento With func_formatDate(mXmlFile.GetChildContent('Documentos|Documento[i]|DataVencimento')), ;
			crsDocCab.Nome With func_formatString(mXmlFile.GetChildContent('Documentos|Documento[i]|Nome')), ;
			crsDocCab.Morada With func_formatString(mXmlFile.GetChildContent('Documentos|Documento[i]|Morada')), ;
			crsDocCab.Localidade With mXmlFile.GetChildContent('Documentos|Documento[i]|Localidade'), ;
			crsDocCab.NumContribuinte With Alltrim(mXmlFile.GetChildContent('Documentos|Documento[i]|NumContribuinte')), ;
			crsDocCab.HashDGCI With mXmlFile.GetChildContent('Documentos|Documento[i]|HashDGCI'), ;
			crsDocCab.ControlHash With mXmlFile.GetChildIntValue('Documentos|Documento[i]|ControlHash'), ;
			crsDocCab.TipoDocHash With mXmlFile.GetChildContent('Documentos|Documento[i]|TipoDocHash'), ;
			crsDocCab.CodPostal4 With mXmlFile.GetChildIntValue('Documentos|Documento[i]|CodPostal4'), ;
			crsDocCab.CodPostal3 With mXmlFile.GetChildIntValue('Documentos|Documento[i]|CodPostal3'), ;
			crsDocCab.Serie With Alltrim(crsDocCab.TipoDoc) + ' ' + Alltrim(mXmlFile.GetChildContent('Documentos|Documento[i]|Serie')), ;
			crsDocCab.RetencaoIRS With u_val(mXmlFile.GetChildContent('Documentos|Documento[i]|RetencaoIRS')), ;
			crsDocCab.InvoiceNo With mXmlFile.GetChildContent('Documentos|Documento[i]|InvoiceNo'), ;
			crsDocCab.DocumentoComIva With mXmlFile.GetChildIntValue('Documentos|Documento[i]|DocumentoComIva'), ;
			crsDocCab.Cambio With u_val(mXmlFile.GetChildContent('Documentos|Documento[i]|Cambio')), ;
			crsDocCab.Matricula With mXmlFile.GetChildContent('Documentos|Documento[i]|Expedicao'), ;
			crsDocCab.ID With mXmlFile.GetChildIntValue('Documentos|Documento[i]|ID'), ;
			crsDocCab.ATCUD With mXmlFile.GetChildContent('Documentos|Documento[i]|ATCUD'), ;
			crsDocCab.NumeroSerie With mXmlFile.GetChildIntValue('Documentos|Documento[i]|NumeroSerie'), ;
			crsDocCab.Armazem With 1, ;
			crsDocCab.Ficheiro With mFich
		Replace crsDocCab.ClientePHC With func_getEntidade('D', crsDocCab.Cliente, crsDocCab.NumContribuinte)

		j = 0
		lnCount_j = mXmlFile.NumChildrenHavingTag('Documentos|Documento[i]|Linhas|Linha')
		Do While j < lnCount_j
			mXmlFile.J = j
			Select crsDocLin
			Append Blank
			Replace crsDocLin.IDImport With mIdImport, ;
				crsDocLin.Area With 'D', ;
				crsDocLin.ID With mXmlFile.GetChildIntValue('Documentos|Documento[i]|ID'), ;
				crsDocLin.NumLinha With mXmlFile.GetChildIntValue('Documentos|Documento[i]|Linhas|Linha[j]|NumLinha') * 100, ;
				crsDocLin.Produto With mXmlFile.GetChildContent('Documentos|Documento[i]|Linhas|Linha[j]|Produto'), ;
				crsDocLin.Designacao With func_formatString(mXmlFile.GetChildContent('Documentos|Documento[i]|Linhas|Linha[j]|Designacao')), ;
				crsDocLin.Quantidade With u_val(mXmlFile.GetChildContent('Documentos|Documento[i]|Linhas|Linha[j]|Quantidade')), ;
				crsDocLin.PUnitIliqIva With u_val(mXmlFile.GetChildContent('Documentos|Documento[i]|Linhas|Linha[j]|PrecoUnitario')), ;
				crsDocLin.Desconto1 With u_val(mXmlFile.GetChildContent('Documentos|Documento[i]|Linhas|Linha[j]|Desconto1')), ;
				crsDocLin.Desconto2 With u_val(mXmlFile.GetChildContent('Documentos|Documento[i]|Linhas|Linha[j]|Desconto2')), ;
				crsDocLin.PercIva With u_val(mXmlFile.GetChildContent('Documentos|Documento[i]|Linhas|Linha[j]|PercIva')), ;
				crsDocLin.IvaIncluido With mXmlFile.GetChildIntValue('Documentos|Documento[i]|Linhas|Linha[j]|IvaIncluido'), ;
				crsDocLin.Observacoes With mXmlFile.GetChildContent('Documentos|Documento[i]|Linhas|Linha[j]|observacoes'), ;
				crsDocLin.TipoArtigo With mXmlFile.GetChildContent('Documentos|Documento[i]|Linhas|Linha[j]|TipoArtigo'), ;
				crsDocLin.CodIsencaoIva With mXmlFile.GetChildContent('Documentos|Documento[i]|Linhas|Linha[j]|CodIsencaoIva'), ;
				crsDocLin.IsencaoIva With mXmlFile.GetChildContent('Documentos|Documento[i]|Linhas|Linha[j]|IsencaoIva'), ;
				crsDocLin.IrsRetido With mXmlFile.GetChildIntValue('Documentos|Documento[i]|Linhas|Linha[j]|IrsRetido'), ;
				crsDocLin.ValorLinha With u_val(mXmlFile.GetChildContent('Documentos|Documento[i]|Linhas|Linha[j]|ValorLinha')), ;
				crsDocLin.DescTipo With mXmlFile.GetChildContent('Documentos|Documento[i]|Linhas|Linha[j]|Descontos|Desconto|Tipo'), ;
				crsDocLin.DescCodigo With mXmlFile.GetChildIntValue('Documentos|Documento[i]|Linhas|Linha[j]|Descontos|Desconto|Codigo'), ;
				crsDocLin.DescDescricao With mXmlFile.GetChildContent('Documentos|Documento[i]|Linhas|Linha[j]|Descontos|Desconto|Descricao'), ;
				crsDocLin.DescValorTotal With u_val(mXmlFile.GetChildContent('Documentos|Documento[i]|Linhas|Linha[j]|Descontos|Desconto|ValorTotalDesconto'))
			Replace crsDocLin.DescontoValor With Round(Iif(crsDocLin.Quantidade = 0, 0, crsDocLin.DescValorTotal / crsDocLin.Quantidade), 2), ;
				crsDocLin.PrecoUnitario With crsDocLin.PUnitIliqIva - crsDocLin.DescontoValor
			mRef = func_getRef(Alltrim(crsDocLin.Produto))
			Replace crsDocLin.refPHC With mRef, ;
				crsDocLin.PCusto With func_refPCusto(mRef), ;
				crsDocLin.Usalote With func_refUsalote(mRef)
			j = j + 1
		EndDo

		j = 0
		lnCount_j = mXmlFile.NumChildrenHavingTag('Documentos|Documento[i]|ResumoIva|LinhaIva')
		Do While j < lnCount_j
			mXmlFile.J = j
			Select crsDocIVA
			Append Blank
			Replace crsDocIVA.IDImport With mIdImport, ;
				crsDocIVA.ID With mXmlFile.GetChildIntValue('Documentos|Documento[i]|ID'), ;
				crsDocIVA.Taxa With u_val(mXmlFile.GetChildContent('Documentos|Documento[i]|ResumoIva|LinhaIva[j]|Taxa')), ;
				crsDocIVA.Valor With u_val(mXmlFile.GetChildContent('Documentos|Documento[i]|ResumoIva|LinhaIva[j]|Valor')), ;
				crsDocIVA.ValorProd With u_val(mXmlFile.GetChildContent('Documentos|Documento[i]|ResumoIva|LinhaIva[j]|ValorProd')), ;
				crsDocIVA.IvaIncluido With mXmlFile.GetChildIntValue('Documentos|Documento[i]|ResumoIva|LinhaIva[j]|IvaIncluido'), ;
				crsDocIVA.IsencaoIva With mXmlFile.GetChildContent('Documentos|Documento[i]|ResumoIva|LinhaIva[j]|IsencaoIva'), ;
				crsDocIVA.CodIsencaoIva With mXmlFile.GetChildContent('Documentos|Documento[i]|ResumoIva|LinhaIva[j]|CodIsencaoIva'), ;
				crsDocIVA.CodigoIVA With mXmlFile.GetChildContent('Documentos|Documento[i]|ResumoIva|LinhaIva[j]|CodigoIVA')
			j = j + 1
		EndDo

		j = 0
		lnCount_j = mXmlFile.NumChildrenHavingTag('Documentos|Documento[i]|Pagamentos|Pagamento')
		Do While j < lnCount_j
			mXmlFile.J = j
			Select crsDocPag
			Append Blank
			Replace crsDocPag.IDImport With mIdImport, ;
				crsDocPag.Area With 'D', ;
				crsDocPag.ID With mXmlFile.GetChildIntValue('Documentos|Documento[i]|ID'), ;
				crsDocPag.Linha With mXmlFile.GetChildIntValue('Documentos|Documento[i]|Pagamentos|Pagamento[j]|Linha'), ;
				crsDocPag.Codigo With mXmlFile.GetChildIntValue('Documentos|Documento[i]|Pagamentos|Pagamento[j]|Codigo'), ;
				crsDocPag.DescModoPagamento With mXmlFile.GetChildContent('Documentos|Documento[i]|Pagamentos|Pagamento[j]|DescModoPagamento'), ;
				crsDocPag.Valor With u_val(mXmlFile.GetChildContent('Documentos|Documento[i]|Pagamentos|Pagamento[j]|Valor'))
			j = j + 1
		EndDo

		mIdImport = mIdImport + 1
		i = i + 1
	EndDo

	i = 0
	lnCount_i = mXmlFile.NumChildrenHavingTag('Movimentos|Movimento')
	Do While i < lnCount_i
		mXmlFile.I = i
		If Empty(mXmlFile.GetChildContent('Movimentos|Movimento[i]|TipoFac')) And ;
				mXmlFile.GetChildContent('Movimentos|Movimento[i]|TipoTerceiro') != 'F'

			Select crsDocCab
			Append Blank
			Replace crsDocCab.IDImport With mIdImport, ;
				crsDocCab.Area With 'M', ;
				crsDocCab.EstadoDocumento With mXmlFile.GetChildContent('Movimentos|Movimento[i]|EstadoDocumento'), ;
				crsDocCab.Sentido With mXmlFile.GetChildIntValue('Movimentos|Movimento[i]|Sentido'), ;
				crsDocCab.TipoNumDoc With mXmlFile.GetChildIntValue('Movimentos|Movimento[i]|TipoNumDoc'), ;
				crsDocCab.NumDoc With Astr(mXmlFile.GetChildIntValue('Movimentos|Movimento[i]|NumDoc')), ;
				crsDocCab.DataDoc With func_formatDate(mXmlFile.GetChildContent('Movimentos|Movimento[i]|DataDoc')), ;
				crsDocCab.TipoArtigo With mXmlFile.GetChildContent('Movimentos|Movimento[i]|TipoArtigo')
			Replace crsDocCab.TipoDoc With func_docType(Astr(crsDocCab.TipoNumDoc))
			Replace crsDocCab.TipoTerceiro With mXmlFile.GetChildContent('Movimentos|Movimento[i]|TipoTerceiro'), ;
				crsDocCab.Terceiro With mXmlFile.GetChildIntValue('Movimentos|Movimento[i]|Terceiro'), ;
				crsDocCab.NomeTerceiro With func_formatString(mXmlFile.GetChildContent('Movimentos|Movimento[i]|NomeTerceiro')), ;
				crsDocCab.Nome With func_formatString(mXmlFile.GetChildContent('Movimentos|Movimento[i]|NomeTerceiro')), ;
				crsDocCab.Fornecedor With mXmlFile.GetChildIntValue('Movimentos|Movimento[i]|Fornecedor'), ;
				crsDocCab.DataDocTerceiro With func_formatDate(mXmlFile.GetChildContent('Movimentos|Movimento[i]|DataDocTerceiro')), ;
				crsDocCab.DocTerceiro With mXmlFile.GetChildContent('Movimentos|Movimento[i]|DocTerceiro'), ;
				crsDocCab.DataDocOrig With func_formatDate(mXmlFile.GetChildContent('Movimentos|Movimento[i]|DataDocOrig')), ;
				crsDocCab.Moeda With mXmlFile.GetChildContent('Movimentos|Movimento[i]|Moeda'), ;
				crsDocCab.Estado With mXmlFile.GetChildIntValue('Movimentos|Movimento[i]|Estado'), ;
				crsDocCab.Observacoes With mXmlFile.GetChildContent('Movimentos|Movimento[i]|Observacoes'), ;
				crsDocCab.Autor With mXmlFile.GetChildContent('Movimentos|Movimento[i]|Autor'), ;
				crsDocCab.DataRegisto With func_formatDate(mXmlFile.GetChildContent('Movimentos|Movimento[i]|DataRegisto')), ;
				crsDocCab.HoraRegisto With func_formatHour(mXmlFile.GetChildContent('Movimentos|Movimento[i]|DataRegisto')), ;
				crsDocCab.GuiaFacturada With mXmlFile.GetChildIntValue('Movimentos|Movimento[i]|GuiaFacturada'), ;
				crsDocCab.IvaPeloAdquirente With mXmlFile.GetChildIntValue('Movimentos|Movimento[i]|IvaPeloAdquirente'), ;
				crsDocCab.ValorDesconto With u_val(mXmlFile.GetChildContent('Movimentos|Movimento[i]|ValorDescTotal')), ;
				crsDocCab.ValorTotal With u_val(mXmlFile.GetChildContent('Movimentos|Movimento[i]|ValorTotal')), ;
				crsDocCab.ValorIva With u_val(mXmlFile.GetChildContent('Movimentos|Movimento[i]|ValorIva')), ;
				crsDocCab.Morada With func_formatString(mXmlFile.GetChildContent('Movimentos|Movimento[i]|Morada')), ;
				crsDocCab.Localidade With mXmlFile.GetChildContent('Movimentos|Movimento[i]|Localidade'), ;
				crsDocCab.NumContribuinte With Alltrim(mXmlFile.GetChildContent('Movimentos|Movimento[i]|NumContribuinte')), ;
				crsDocCab.DescontoCliente With u_val(mXmlFile.GetChildContent('Movimentos|Movimento[i]|DescontoCliente')), ;
				crsDocCab.CodPostal4 With mXmlFile.GetChildIntValue('Movimentos|Movimento[i]|CodPostal4'), ;
				crsDocCab.CodPostal3 With mXmlFile.GetChildIntValue('Movimentos|Movimento[i]|CodPostal3'), ;
				crsDocCab.HashDGCI With mXmlFile.GetChildContent('Movimentos|Movimento[i]|HashDGCI'), ;
				crsDocCab.ControlHash With mXmlFile.GetChildIntValue('Movimentos|Movimento[i]|ControlHash'), ;
				crsDocCab.TipoDocHash With mXmlFile.GetChildContent('Movimentos|Movimento[i]|TipoDocHash'), ;
				crsDocCab.HashComPreco With mXmlFile.GetChildIntValue('Movimentos|Movimento[i]|HashComPreco'), ;
				crsDocCab.DataPagamento With func_formatDate(mXmlFile.GetChildContent('Movimentos|Movimento[i]|DataPagamento')), ;
				crsDocCab.Serie With Alltrim(crsDocCab.TipoDoc) + ' ' + Alltrim(mXmlFile.GetChildContent('Movimentos|Movimento[i]|Serie')), ;
				crsDocCab.RetencaoIRS With u_val(mXmlFile.GetChildContent('Movimentos|Movimento[i]|RetencaoIRS')), ;
				crsDocCab.InvoiceNo With mXmlFile.GetChildContent('Movimentos|Movimento[i]|InvoiceNo'), ;
				crsDocCab.GuiaTransporte With mXmlFile.GetChildIntValue('Movimentos|Movimento[i]|GuiaTransporte'), ;
				crsDocCab.DocumentoComIva With mXmlFile.GetChildIntValue('Movimentos|Movimento[i]|DocumentoComIva'), ;
				crsDocCab.NumeroSerie With mXmlFile.GetChildIntValue('Movimentos|Movimento[i]|NumeroSerie'), ;
				crsDocCab.ATCUD With mXmlFile.GetChildContent('Movimentos|Movimento[i]|ATCUD'), ;
				crsDocCab.Cliente With mXmlFile.GetChildIntValue('Movimentos|Movimento[i]|Cliente'), ;
				crsDocCab.NumDocOrig With mXmlFile.GetChildIntValue('Movimentos|Movimento[i]|NumDocOrig'), ;
				crsDocCab.Armazem With func_armazem(mXmlFile.GetChildIntValue('Movimentos|Movimento[i]|Armazem')), ;
				crsDocCab.Matricula With mXmlFile.GetChildContent('Movimentos|Movimento[i]|Expedicao|Expedicao|Expedicao'), ;
				crsDocCab.Ficheiro With mFich
			Replace crsDocCab.clientePHC With func_getEntidade('M', crsDocCab.Cliente, crsDocCab.NumContribuinte)
			If Empty(Alltrim(crsDocCab.NomeTerceiro)) And crsDocCab.ClientePHC = 1
				Replace crsDocCab.NomeTerceiro With GetUmValorString([ag], [nome], [no=] + Astr(crsDocCab.ClientePHC))
			EndIf

			j = 0
			lnCount_j = mXmlFile.NumChildrenHavingTag('Movimentos|Movimento[i]|Linhas|Linha')
			Do While j < lnCount_j
				mXmlFile.J = j
				Select crsDocLin
				Append Blank
				Replace crsDocLin.IDImport With mIdImport, ;
					crsDocLin.Area With 'M', ;
					crsDocLin.NumLinha With mXmlFile.GetChildIntValue('Movimentos|Movimento[i]|Linhas|Linha[j]|NumLinha') * 100, ;
					crsDocLin.Produto With mXmlFile.GetChildContent('Movimentos|Movimento[i]|Linhas|Linha[j]|Produto'), ;
					crsDocLin.Designacao With func_formatString(mXmlFile.GetChildContent('Movimentos|Movimento[i]|Linhas|Linha[j]|Designacao')), ;
					crsDocLin.Quantidade With u_val(mXmlFile.GetChildContent('Movimentos|Movimento[i]|Linhas|Linha[j]|Quantidade')), ;
					crsDocLin.PUnitIliqIva With u_val(mXmlFile.GetChildContent('Movimentos|Movimento[i]|Linhas|Linha[j]|PrecoUnitario')), ;
					crsDocLin.Desconto1 With u_val(mXmlFile.GetChildContent('Movimentos|Movimento[i]|Linhas|Linha[j]|Desconto1')), ;
					crsDocLin.Desconto2 With u_val(mXmlFile.GetChildContent('Movimentos|Movimento[i]|Linhas|Linha[j]|Desconto2')), ;
					crsDocLin.PercIva With u_val(mXmlFile.GetChildContent('Movimentos|Movimento[i]|Linhas|Linha[j]|PercIva')), ;
					crsDocLin.IvaIncluido With mXmlFile.GetChildIntValue('Movimentos|Movimento[i]|Linhas|Linha[j]|IvaIncluido'), ;
					crsDocLin.Observacoes With mXmlFile.GetChildContent('Movimentos|Movimento[i]|Linhas|Linha[j]|Observacoes'), ;
					crsDocLin.TipoArtigo With mXmlFile.GetChildContent('Movimentos|Movimento[i]|Linhas|Linha[j]|TipoArtigo'), ;
					crsDocLin.CodIsencaoIva With mXmlFile.GetChildContent('Movimentos|Movimento[i]|Linhas|Linha[j]|CodIsencaoIva'), ;
					crsDocLin.IsencaoIVA With mXmlFile.GetChildContent('Movimentos|Movimento[i]|Linhas|Linha[j]|IsencaoIVA'), ;
					crsDocLin.Familia With mXmlFile.GetChildIntValue('Movimentos|Movimento[i]|Linhas|Linha[j]|Familia'), ;
					crsDocLin.DescCodigo With mXmlFile.GetChildIntValue('Movimentos|Movimento[i]|Linhas|Linha[j]|Descontos|Desconto|Codigo'), ;
					crsDocLin.DescSubCod With mXmlFile.GetChildIntValue('Movimentos|Movimento[i]|Linhas|Linha[j]|Descontos|Desconto|SubCodigo'), ;
					crsDocLin.DescDescricao With mXmlFile.GetChildContent('Movimentos|Movimento[i]|Linhas|Linha[j]|Descontos|Desconto|Descricao'), ;
					crsDocLin.DescValorTotal With u_val(mXmlFile.GetChildContent('Movimentos|Movimento[i]|Linhas|Linha[j]|Descontos|Desconto|ValorTotalDesconto')), ;
					crsDocLin.DescTipo With mXmlFile.GetChildContent('Movimentos|Movimento[i]|Linhas|Linha[j]|Descontos|Desconto|Tipo')
				Replace crsDocLin.DescontoValor With Round(Iif(crsDocLin.Quantidade = 0, 0, crsDocLin.DescValorTotal / crsDocLin.Quantidade), 2), ;
					crsDocLin.PrecoUnitario With crsDocLin.PUnitIliqIva - crsDocLin.DescontoValor, ;
					crsDocLin.ValorLinha With crsDocLin.PUnitIliqIva * (1 - crsDocLin.Desconto1 / 100) * ;
						(1 - crsDocLin.Desconto2 / 100) * crsDocLin.Quantidade - crsDocLin.DescValorTotal
				mRef = func_getRef(Alltrim(crsDocLin.Produto))
				Replace crsDocLin.refPHC With mRef, ;
					crsDocLin.PCusto With func_refPCusto(mRef), ;
					crsDocLin.Usalote With func_refUsalote(mRef)
				j = j + 1
			EndDo

			j = 0
			lnCount_j = mXmlFile.NumChildrenHavingTag('Movimentos|Movimento[i]|Pagamentos|Pagamento')
			Do While j < lnCount_j
				mXmlFile.J = j
				Select crsDocPag
				Append Blank
				Replace crsDocPag.IDImport With mIdImport, ;
					crsDocPag.Area With 'M', ;
					crsDocPag.Linha With mXmlFile.GetChildIntValue('Movimentos|Movimento[i]|Pagamentos|Pagamento[j]|Linha'), ;
					crsDocPag.Codigo With mXmlFile.GetChildIntValue('Movimentos|Movimento[i]|Pagamentos|Pagamento[j]|Codigo'), ;
					crsDocPag.DescModoPagamento With mXmlFile.GetChildContent('Movimentos|Movimento[i]|Pagamentos|Pagamento[j]|DescModoPagamento'), ;
					crsDocPag.Valor With u_val(mXmlFile.GetChildContent('Movimentos|Movimento[i]|Pagamentos|Pagamento[j]|Valor'))
				j = j + 1
			EndDo
			mIdImport = mIdImport + 1
		EndIf
		i = i + 1
	EndDo

	mXmlFile = .NULL.
	Return .T.
EndProc

Procedure proc_mapDocs
	Lparameters mCod, mTipo, mImp
	Select crsMapDocs
	Append Blank
	Replace crsMapDocs.codDoc With mCod, ;
		crsMapDocs.tipoDoc With mTipo, ;
		crsMapDocs.importPHC With mImp
EndProc

Function func_docType
	Lparameter mDocCode
	Select crsMapDocs
	Locate For Alltrim(crsMapDocs.codDoc) == Alltrim(Nvl(mDocCode, ''))
	If Found() And crsMapDocs.importPHC
		Return Alltrim(crsMapDocs.tipoDoc)
	EndIf
	Return ''
EndFunc

Function func_serieToImport
	Lparameter mDocCode
	Select crsMapDocs
	Locate For Alltrim(crsMapDocs.codDoc) == Alltrim(Nvl(mDocCode, ''))
	If Found()
		Return Iif(crsMapDocs.importPHC, 1, 2)
	EndIf
	Return 0
EndFunc

*==============================================================================*
* Preparação: séries, totais, lotes SE
*==============================================================================*

Function func_prepDocs
	Local mSinal, mStamp, mArm

	ActForm('Verificando as séries documentais para importação')
	If !func_setDocSerie()
		proc_insErr('Séries documentais', 'Erro no mapeamento de séries documentais', '')
		DeactForm()
		Return .F.
	EndIf

	ActForm('Aguarde enquanto o sistema efetua a classificação do documentos a importar')
	Select crsDocCab
	Scan
		mSinal = 1
		Replace crsDocCab.Armazem With func_armazem(crsDocCab.Armazem)
		Replace crsDocCab.Ignorar With (func_serieToImport(func_docCode(crsDocCab.Area, crsDocCab.TipoDoc, crsDocCab.TipoNumDoc)) = 2)

		If crsDocCab.TabPHC = 'FT'
			mStamp = GetUmValorString([ft], [ftstamp], [ndoc=] + Astr(crsDocCab.SeriePHC) ;
				+ [ And ftano=] + Astr(Year(crsDocCab.DataDoc)) + [ And fno=] + Astr(crsDocCab.NumeroSerie))
			mSinal = Iif(GetUmValorNumerico([td], [tipodoc], [ndoc=] + Astr(crsDocCab.SeriePHC)) = 3, -1, 1)
		Else
			mStamp = GetUmValorString([bo], [bostamp], [ndos=] + Astr(crsDocCab.SeriePHC) ;
				+ [ And boano=] + Astr(Year(crsDocCab.DataDoc)) + [ And obrano=] + Astr(crsDocCab.NumeroSerie))
		EndIf
		Replace crsDocCab.Existe With !Empty(mStamp), crsDocCab.Sinal With mSinal

		If !crsDocCab.Existe And !crsDocCab.Ignorar
			If At('-', crsDocCab.ATCUD) = 0 And !Empty(Alltrim(crsDocCab.ATCUD))
				Replace crsDocCab.ATCUD With Alltrim(crsDocCab.ATCUD) + '-' + Astr(crsDocCab.NumeroSerie)
			EndIf
			proc_prepIvaPag(mSinal)
		EndIf
		Select crsDocCab
	EndScan

	DeactForm()
	If !func_assignLotes()
		Return .F.
	EndIf
	Return .T.
EndFunc

Procedure proc_prepIvaPag
	Lparameters mSinal

	Select Taxa, ValorProd, Valor From crsDocIVA ;
		Where crsDocIVA.IDImport = crsDocCab.IDImport ;
		Into Cursor crsTTIva ReadWrite

	Select crsTTIva
	Locate For crsTTIva.Taxa = 6
	If Found()
		Replace crsDocCab.Iva1Inc With Abs(crsTTIva.ValorProd) * mSinal, ;
			crsDocCab.Iva1Iva With Abs(crsTTIva.Valor) * mSinal In crsDocCab
	EndIf
	Locate For crsTTIva.Taxa = 13
	If Found()
		Replace crsDocCab.Iva3Inc With Abs(crsTTIva.ValorProd) * mSinal, ;
			crsDocCab.Iva3Iva With Abs(crsTTIva.Valor) * mSinal In crsDocCab
	EndIf
	Locate For crsTTIva.Taxa = 23
	If Found()
		Replace crsDocCab.Iva2Inc With Abs(crsTTIva.ValorProd) * mSinal, ;
			crsDocCab.Iva2Iva With Abs(crsTTIva.Valor) * mSinal In crsDocCab
	EndIf
	Locate For crsTTIva.Taxa = 0
	If Found()
		Replace crsDocCab.Iva4Inc With Abs(crsTTIva.ValorProd) * mSinal, ;
			crsDocCab.Iva4Iva With Abs(crsTTIva.Valor) * mSinal In crsDocCab
	EndIf
	Fecha([crsTTIva])

	Select crsDocPag
	Scan For crsDocPag.IDImport = crsDocCab.IDImport
		Do Case
		Case crsDocPag.Codigo = 1
			Replace crsDocCab.Numerario With crsDocCab.Numerario + Abs(crsDocPag.Valor) * mSinal In crsDocCab
		Case crsDocPag.Codigo = 2
			Replace crsDocCab.Cheque With crsDocCab.Cheque + Abs(crsDocPag.Valor) * mSinal In crsDocCab
		Case crsDocPag.Codigo = 3
			Replace crsDocCab.Multibanco With crsDocCab.Multibanco + Abs(crsDocPag.Valor) * mSinal, ;
				crsDocCab.MbTerm With Iif(Right(Alltrim(crsDocPag.DescModoPagamento), 3) = 'OPT', 'OPT', 'AS') In crsDocCab
		Case crsDocPag.Codigo = 4
			Replace crsDocCab.TrfBanc With crsDocCab.TrfBanc + Abs(crsDocPag.Valor) * mSinal In crsDocCab
		EndCase
	EndScan

	If mSinal = -1
		Replace crsDocCab.ValorIva With Abs(crsDocCab.ValorIva) * mSinal, ;
			crsDocCab.ValorDesconto With Abs(crsDocCab.ValorDesconto) * mSinal, ;
			crsDocCab.ValorTotal With Abs(crsDocCab.ValorTotal) * mSinal, ;
			crsDocCab.RetencaoIRS With Abs(crsDocCab.RetencaoIRS) * mSinal In crsDocCab
		Update crsDocLin Set ValorLinha = Abs(ValorLinha) * mSinal ;
			Where IDImport = crsDocCab.IDImport
	EndIf
EndProc

Function func_assignLotes
	Local mSel

	mSel = [Select ref,lote,stock,epcult,data,armazem From se (Nolock) Where stock>0 Order By ref,armazem,data,lote]
	If !u_sqlexec(mSel, [crsLotesSql])
		Mensagem('Erro a consultar lotes de artigos' + Chr(13) + Message(), 'Directa')
		Return .F.
	EndIf
	Select * From crsLotesSql Into Cursor crsLotes ReadWrite
	Fecha([crsLotesSql])

	Select crsDocLin.*, crsDocCab.DataDoc, crsDocCab.Sinal, crsDocCab.Armazem, ;
		crsDocCab.EstadoDocumento, crsDocCab.Ficheiro, crsDocCab.Existe, crsDocCab.Ignorar ;
		From crsDocCab Inner Join crsDocLin On crsDocCab.IDImport = crsDocLin.IDImport ;
		Where !crsDocCab.Existe And !crsDocCab.Ignorar And crsDocLin.Usalote And Empty(crsDocLin.Lote) ;
			And crsDocCab.EstadoDocumento <> 'A' ;
		Order By crsDocCab.DataDoc, crsDocCab.IDImport, crsDocLin.NumLinha ;
		Into Cursor crsDLin ReadWrite

	Regua(0, Reccount('crsDLin'), 'Atribuindo lotes em linhas de documentos')
	Select crsDLin
	Scan
		Regua(1, Recno(), 'Processando o registo ' + Astr(Recno()) + ' de ' + Astr(Reccount('crsDLin')))
		If crsDLin.Sinal < 0
			func_assignLoteDevolucao(crsDLin.IDImport, crsDLin.NumLinha, crsDLin.refPHC, ;
				crsDLin.Quantidade, crsDLin.Armazem, crsDLin.Ficheiro)
		Else
			func_assignLoteSaida(crsDLin.IDImport, crsDLin.NumLinha, crsDLin.refPHC, ;
				crsDLin.Quantidade, crsDLin.ValorLinha, crsDLin.Armazem, crsDLin.Ficheiro)
		EndIf
		Select crsDLin
	EndScan
	Regua(2)
	Fecha([crsDLin])
	Return .T.
EndFunc

Function func_assignLoteSaida
	Lparameters mId, mNLin, mRef, mQtd, mVal, mArm, mFich

	Select crsLotes
	Locate For Alltrim(crsLotes.ref) == Alltrim(mRef) And crsLotes.armazem = mArm And crsLotes.stock > FS_QTY_EPS
	If !Found()
		proc_insErr('Lotes', 'Sem stock de lote p/ ' + Alltrim(mRef) + ' linha ' + Astr(mNLin), Alltrim(mFich))
		Update crsDocLin Set Lote = '' Where IDImport = mId And NumLinha = mNLin
		Return .T.
	EndIf

	If crsLotes.stock >= mQtd
		Update crsDocLin Set Lote = Alltrim(crsLotes.lote), PCusto = crsLotes.epcult ;
			Where IDImport = mId And NumLinha = mNLin
		Replace crsLotes.stock With crsLotes.stock - mQtd
		Return .T.
	EndIf

	func_distribLote(mRef, mQtd, mVal, mId, mNLin, mArm, mFich)
	Return .T.
EndFunc

Function func_assignLoteDevolucao
	Lparameters mId, mNLin, mRef, mQtd, mArm, mFich
	Local mLote, mCusto, mSel

	mLote = ''
	mCusto = 0
	Select crsLotes
	Scan For Alltrim(crsLotes.ref) == Alltrim(mRef) And crsLotes.armazem = mArm
		mLote = Alltrim(crsLotes.lote)
		mCusto = crsLotes.epcult
	EndScan

	If Empty(mLote)
		mSel = [Select Top 1 lote,epcult From se (Nolock) Where ref=] + func_sqlLit(mRef) ;
			+ [ And armazem=] + Astr(mArm) + [ Order By data Desc]
		If u_sqlexec(mSel, [crsLotDev]) And Reccount('crsLotDev') > 0
			Select crsLotDev
			mLote = Alltrim(crsLotDev.lote)
			mCusto = crsLotDev.epcult
		EndIf
		Fecha([crsLotDev])
	EndIf

	If Empty(mLote)
		proc_insErr('Lotes', 'Sem lote p/ devolução ' + Alltrim(mRef) + ' linha ' + Astr(mNLin), Alltrim(mFich))
		Return .T.
	EndIf

	Update crsDocLin Set Lote = mLote, PCusto = mCusto Where IDImport = mId And NumLinha = mNLin

	Select crsLotes
	Locate For Alltrim(crsLotes.ref) == Alltrim(mRef) And Alltrim(crsLotes.lote) == mLote And crsLotes.armazem = mArm
	If Found()
		Replace crsLotes.stock With crsLotes.stock + mQtd
	Else
		Insert Into crsLotes (ref, lote, stock, epcult, armazem) ;
			Values (mRef, mLote, mQtd, mCusto, mArm)
	EndIf
	Return .T.
EndFunc

Function func_distribLote
	Lparameters mRef, mQtd, mVal, mId, mNLin, mArm, mFich
	Local mQtdResto, mNumLin, mTake, mOrigDesc, mTotalLin, mTotalDesc

	Select crsDocLin
	Locate For crsDocLin.IDImport = mId And crsDocLin.NumLinha = mNLin
	If !Found()
		Return .F.
	EndIf
	Scatter Name ValoresDosCampos Memo
	mOrigDesc = crsDocLin.DescValorTotal
	mQtdResto = mQtd
	mNumLin = 0

	Select * From crsDocLin Where 1 = 0 Into Cursor crsLinLote ReadWrite

	Do While mQtdResto > FS_QTY_EPS
		Select crsLotes
		Locate For Alltrim(crsLotes.ref) == Alltrim(mRef) And crsLotes.armazem = mArm And crsLotes.stock > FS_QTY_EPS
		If Found()
			mTake = Iif(crsLotes.stock < mQtdResto, crsLotes.stock, mQtdResto)
			If mQtdResto - mTake < FS_QTY_EPS
				mTake = mQtdResto
			EndIf
			Insert Into crsLinLote From Name ValoresDosCampos
			Replace crsLinLote.Lote With Alltrim(crsLotes.lote), ;
				crsLinLote.PCusto With crsLotes.epcult, ;
				crsLinLote.Quantidade With mTake, ;
				crsLinLote.ValorLinha With Round(mTake / mQtd * mVal, 2), ;
				crsLinLote.DescValorTotal With Round(mTake / mQtd * mOrigDesc, 2), ;
				crsLinLote.DescontoValor With Round(Iif(mTake = 0, 0, Round(mTake / mQtd * mOrigDesc, 2) / mTake), 2), ;
				crsLinLote.NumLinha With mNLin + mNumLin In crsLinLote
			Replace crsLotes.stock With crsLotes.stock - mTake In crsLotes
		Else
			Insert Into crsLinLote From Name ValoresDosCampos
			Replace crsLinLote.Lote With '', ;
				crsLinLote.Quantidade With mQtdResto, ;
				crsLinLote.ValorLinha With Round(mQtdResto / mQtd * mVal, 2), ;
				crsLinLote.DescValorTotal With Round(mQtdResto / mQtd * mOrigDesc, 2), ;
				crsLinLote.NumLinha With mNLin + mNumLin In crsLinLote
			proc_insErr('Lotes', 'Stock insuficiente ' + Alltrim(mRef) + ' resto ' + Astr(mQtdResto), Alltrim(mFich))
			mQtdResto = 0
			Exit
		EndIf
		mQtdResto = mQtdResto - crsLinLote.Quantidade
		mNumLin = mNumLin + 1
	EndDo

	Select crsLinLote
	Sum crsLinLote.ValorLinha, crsLinLote.DescValorTotal To mTotalLin, mTotalDesc
	Go Bottom
	If mTotalLin != mVal
		Replace crsLinLote.ValorLinha With crsLinLote.ValorLinha + (mVal - mTotalLin)
	EndIf
	If mTotalDesc != mOrigDesc
		Replace crsLinLote.DescValorTotal With crsLinLote.DescValorTotal + (mOrigDesc - mTotalDesc)
	EndIf

	Delete From crsDocLin Where IDImport = mId And NumLinha = mNLin
	Select crsLinLote
	Scan
		Scatter Name ValoresDosCampos Memo
		Insert Into crsDocLin From Name ValoresDosCampos
	EndScan
	Fecha([crsLinLote])
	Return .T.
EndFunc

Function func_setDocSerie
	Local mCtrl, ssUpd, serieSel

	mCtrl = .T.
	Do While mCtrl
		Text To ssUpd TextMerge NoShow
			UPDATE td2 SET u_oriserie='SoftSeguro'
			FROM td2 INNER JOIN td ON td2.td2stamp=td.tdstamp
			WHERE td.u_coddocss!='' AND td2.u_oriserie=''

			UPDATE ts2 SET u_oriserie='SoftSeguro'
			FROM ts2 INNER JOIN ts ON ts2.ts2stamp=ts.tsstamp
			WHERE ts.u_coddocss!='' AND ts2.u_oriserie=''
		EndText
		If !u_sqlexec(ssUpd)
			Mensagem('Erro a filtrar séries' + Chr(13) + Message(), 'Directa')
		EndIf

		Text To serieSel TextMerge NoShow
			Select 'FT' tab,ndoc,nmdoc,u_serieimp
			From td (Nolock) Inner join td2 (Nolock) On td.tdstamp=td2.td2stamp
			Where docsimport=1 And fechada=0 And u_oriserie In ('','AlvaShop')
			Union
			Select 'BO' tab,ndos,nmdos,u_serieimp
			From ts (Nolock) Inner join ts2 (Nolock) On ts.tsstamp=ts2.ts2stamp
			Where docsimport=1 And fechada=0 And u_oriserie In ('','AlvaShop')
		EndText
		If !u_sqlexec(serieSel, [crsSeries])
			Mensagem('Erro a listar as séries de documentos do PHC' + Chr(13) + Message(), 'Directa')
			Return .F.
		EndIf

		Select crsSeries
		Scan For !Empty(crsSeries.u_serieimp)
			Select crsDocCab
			Scan For Alltrim(crsDocCab.Serie) = Alltrim(crsSeries.u_serieimp)
				Replace crsDocCab.seriePHC With crsSeries.ndoc, ;
					crsDocCab.tabPHC With crsSeries.tab
			EndScan
			Select crsSeries
		EndScan

		Select Distinct 'Doc' segmento, crsDocCab.serie, Padr(crsMapDocs.TipoDoc, 8, ' ') TipoDoc, ;
			crsDocCab.tabPHC, crsDocCab.seriePHC, Space(20) descSerie, .T. Importa ;
			From crsDocCab Inner Join crsMapDocs On Alltrim(crsDocCab.TipoDoc) = Alltrim(crsMapDocs.codDoc) ;
			Where crsDocCab.Area = 'D' And Empty(crsDocCab.seriePHC) And !crsDocCab.Ignorar ;
			Into Cursor crsMapSeries ReadWrite

		Select Distinct crsDocCab.serie, crsDocCab.TipoNumDoc From crsDocCab ;
			Where crsDocCab.Area = 'M' And crsDocCab.TipoTerceiro != 'F' And Empty(crsDocCab.seriePHC) ;
				And func_serieToImport(Astr(crsDocCab.TipoNumDoc)) = 1 ;
			Into Cursor crsTmp ReadWrite

		Select crsTmp
		Scan
			Select crsMapSeries
			Append Blank
			Replace crsMapSeries.segmento With 'Mov', ;
				crsMapSeries.serie With crsTmp.serie, ;
				crsMapSeries.TipoDoc With func_docType(Astr(crsTmp.TipoNumDoc)), ;
				crsMapSeries.Importa With .T.
		EndScan
		Fecha([crsTmp])

		If Reccount('crsMapSeries') > 0
			Select crsMapSeries
			= CursorSetProp('Buffering', 5, [crsMapSeries])
			Declare list_tit(6), list_cam(6), list_tam(6), list_pic(6), list_rot(6)

			list_tit(1) = "Série doc. import."
			list_tit(2) = "Tipo doc."
			list_tit(3) = "Tabela PHC"
			list_tit(4) = "Série PHC"
			list_tit(5) = "Descrição PHC"
			list_tit(6) = "Mapeamento"

			list_cam(1) = "crsMapSeries.serie"
			list_cam(2) = "crsMapSeries.TipoDoc"
			list_cam(3) = "crsMapSeries.tabPHC"
			list_cam(4) = "crsMapSeries.seriePHC"
			list_cam(5) = "crsMapSeries.descSerie"
			list_cam(6) = ""

			list_pic = ""
			list_pic(6) = "BOTAO IMG:dataclip.bmp"
			list_tam = 8 * 20
			list_rot(6) = "proc_mapSerie()"

			m.escolheu = .F.
			Browlist('Seleção de séries', 'crsMapSeries', 'listTmp', .T., .F., .F., .T., .F., '', .T., .T.)
			If !m.escolheu
				Return .F.
			EndIf

			Select crsMapSeries
			Scan For !Empty(crsMapSeries.seriePHC)
				If crsMapSeries.tabPHC = 'FT'
					u_sqlexec([Update td2 Set u_serieimp=] + func_sqlLit(crsMapSeries.serie) + ;
						[,u_oriserie='AlvaShop' Where td2stamp In (Select tdstamp From td Where ndoc=] + ;
						Astr(crsMapSeries.seriePHC) + [)])
				Else
					u_sqlexec([Update ts2 Set u_serieimp=] + func_sqlLit(crsMapSeries.serie) + ;
						[,u_oriserie='AlvaShop' Where ts2stamp In (Select tsstamp From ts Where ndos=] + ;
						Astr(crsMapSeries.seriePHC) + [)])
				EndIf
			EndScan
		EndIf

		Select crsMapSeries
		Locate For Empty(crsMapSeries.seriePHC)
		If !Found()
			mCtrl = .F.
		EndIf
		Fecha([crsMapSeries])
		Fecha([crsSeries])
	EndDo
	Return .T.
EndFunc

Procedure proc_mapSerie
	Lparameters mParA, mParB

	Declare a_tab(1)
	a_tab = ''
	Aadd('a_tab', 'Faturação')
	Aadd('a_tab', 'Dossiers')

	m.escolheu = .F.
	mTab = GetNome('Destino da importação', 'Faturação', '', '', 1, .F., 'a_tab')
	If !m.escolheu Or Empty(mTab)
		Release a_tab
		Return
	EndIf

	Declare a_serie(1, 2)
	a_serie = ''
	Select crsSeries
	Scan For Empty(crsSeries.u_serieimp) And crsSeries.tab = Iif(mTab = 'Faturação', 'FT', 'BO')
		Aadd2('a_serie', crsSeries.nmdoc, crsSeries.ndoc)
	EndScan

	m.escolheu = .F.
	mSerie = GetNome('Série para mapeamento', 0, '', '', 1, .F., 'a_serie', .T.)
	If !m.escolheu Or mSerie <= 1
		Release a_tab
		Release a_serie
		Return
	EndIf

	Select crsMapSeries
	Replace crsMapSeries.tabPHC With Iif(mTab = 'Faturação', 'FT', 'BO')
	Replace crsMapSeries.seriePHC With a_serie(mSerie, 2)
	Replace crsMapSeries.descSerie With a_serie(mSerie, 1)
	Release mSerie
	m.escolheu = .F.
EndProc

Procedure proc_showDocs
	Select crsDocCab
	= CursorSetProp('Buffering', 5, [crsDocCab])
	Declare list_tit(11), list_cam(11), list_tam(11), list_pic(11), list_rot(11)

	list_tit(1) = "ID"
	list_tit(2) = "Documento"
	list_tit(3) = "Data"
	list_tit(4) = "Cliente"
	list_tit(5) = "NIF"
	list_tit(6) = "Moeda"
	list_tit(7) = "Valor Total"
	list_tit(8) = "Valor IVA"
	list_tit(9) = "Estado"
	list_tit(10) = "Tab.PHC"
	list_tit(11) = "Série PHC"

	list_cam(1) = "crsDocCab.IDImport"
	list_cam(2) = "Alltrim(crsDocCab.Serie)+'/'+Astr(crsDocCab.NumeroSerie)"
	list_cam(3) = "crsDocCab.DataDoc"
	list_cam(4) = "crsDocCab.Nome"
	list_cam(5) = "crsDocCab.NumContribuinte"
	list_cam(6) = "crsDocCab.Moeda"
	list_cam(7) = "crsDocCab.ValorTotal"
	list_cam(8) = "crsDocCab.ValorIva"
	list_cam(9) = "crsDocCab.EstadoDocumento"
	list_cam(10) = "crsDocCab.tabPHC"
	list_cam(11) = "crsDocCab.seriePHC"

	list_pic = ""
	list_pic(7) = "999 999.99"
	list_pic(8) = "999 999.99"
	list_tam = 8 * 20
	list_tam(4) = 8 * 40
	list_rot(2) = "proc_showDocLin()"

	Browlist('Documentos a importar', 'crsDocCab', 'listVendCab', .F., .F., .F., .T., .F., '', .T., .T.)
EndProc

Procedure proc_showDocLin
	Lparameters mParA, mParB

	Select crsDocCab
	Select * From crsDocLin Where crsDocLin.IDImport = crsDocCab.IDImport Into Cursor crsTmp ReadWrite
	Select crsTmp
	Declare list_tit(15), list_cam(15), list_tam(15), list_pic(15)

	list_tit(1) = "Nº Linha"
	list_tit(2) = "Produto"
	list_tit(3) = "Ref.PHC"
	list_tit(4) = "Designação"
	list_tit(5) = "Quant"
	list_tit(6) = "Preço Unit"
	list_tit(7) = "Valor Total"
	list_tit(8) = "Lote"
	list_tit(9) = "P.Custo"
	list_tit(10) = "Taxa IVA"
	list_tit(11) = "IVA Incl"
	list_tit(12) = "Tipo desconto"
	list_tit(13) = "Desconto"
	list_tit(14) = "Observ"
	list_tit(15) = "Isenção Iva"

	list_cam(1) = "crsTmp.NumLinha"
	list_cam(2) = "crsTmp.Produto"
	list_cam(3) = "crsTmp.refPHC"
	list_cam(4) = "crsTmp.Designacao"
	list_cam(5) = "crsTmp.Quantidade"
	list_cam(6) = "crsTmp.PrecoUnitario"
	list_cam(7) = "crsTmp.ValorLinha"
	list_cam(8) = "crsTmp.Lote"
	list_cam(9) = "crsTmp.PCusto"
	list_cam(10) = "crsTmp.PercIva"
	list_cam(11) = "crsTmp.IvaIncluido"
	list_cam(12) = "crsTmp.DescDescricao"
	list_cam(13) = "crsTmp.DescValorTotal"
	list_cam(14) = "crsTmp.Observacoes"
	list_cam(15) = "Iif(!Empty(crsTmp.CodIsencaoIva),Alltrim(crsTmp.CodIsencaoIva)+' - '+Alltrim(crsTmp.IsencaoIva),'')"

	list_pic = ""
	list_pic(5) = "999 999.99"
	list_pic(6) = "999 999.99"
	list_pic(7) = "999 999.99"
	list_pic(9) = "999 999.9999"
	list_pic(10) = "99%"
	list_pic(13) = "999 999.99"
	list_tam = 8 * 20
	list_tam(4) = 8 * 40
	list_tam(14) = 8 * 200
	list_tam(15) = 8 * 100

	Browlist(Alltrim(crsDocCab.InvoiceNo) + ' de ' + Astr(crsDocCab.DataDoc), 'crsTmp', 'listTmp', .F., .F., .F., .T., .F., '', .T., .T.)
	Fecha([crsTmp])
EndProc

*==============================================================================*
* Inserção PHC
*==============================================================================*

Function func_insDocs
	Local mCode

	Select crsDocCab
	Scan For !crsDocCab.Existe And !crsDocCab.Ignorar
		mCode = func_docCode(crsDocCab.Area, crsDocCab.TipoDoc, crsDocCab.TipoNumDoc)
		If (Empty(crsDocCab.TipoDoc) Or crsDocCab.seriePHC = 0 Or crsDocCab.clientePHC = 0) And func_serieToImport(mCode) = 1
			proc_insErr('Mapeamento', 'Falha mapeamento ' + Alltrim(crsDocCab.InvoiceNo) + ;
				' - série: ' + Astr(crsDocCab.seriePHC) + '/cliente: ' + Astr(crsDocCab.clientePHC), Alltrim(crsDocCab.Ficheiro))
		EndIf
	EndScan

	u_sqlexec([Select * From td (Nolock) Where docsimport=1], [crsSerFt])
	u_sqlexec([Select * From ts (Nolock) Where tsstamp In (Select ts2stamp From ts2 (Nolock) Where docsimport=1)], [crsSerBo])

	Select crsDocCab
	Regua(0, Reccount('crsDocCab'), 'Introduzindo os registos')
	Scan For !crsDocCab.Existe And !crsDocCab.Ignorar And crsDocCab.seriePHC != 0
		Regua(1, Recno('crsDocCab'), 'Processando o registo ' + Alltrim(crsDocCab.InvoiceNo) + ;
			' (' + Astr(Recno('crsDocCab')) + '/' + Astr(Reccount('crsDocCab')) + ')')
		If crsDocCab.clientePHC = 0
			func_ensureEntidade(crsDocCab.IDImport)
		EndIf
		If crsDocCab.clientePHC = 0
			proc_insErr('Mapeamento', 'Cliente em falta ' + Alltrim(crsDocCab.InvoiceNo), Alltrim(crsDocCab.Ficheiro))
			Loop
		EndIf
		If crsDocCab.tabPHC = 'FT'
			proc_insFT()
		EndIf
		If crsDocCab.tabPHC = 'BO'
			proc_insBO()
		EndIf
	EndScan
	Regua(2)
	Fecha([crsSerFt])
	Fecha([crsSerBo])
	Return .T.
EndFunc

Function func_linUsaLote
	Lparameters mLote
	Return Iif(Empty(Alltrim(Nvl(mLote, ''))), 0, 1)
EndFunc

Procedure proc_totaisLinha
	Lparameters mId
	Local mQtt, mCusto
	mQtt = 0
	mCusto = 0
	Select crsDocLin
	Scan For crsDocLin.IDImport = mId
		mQtt = mQtt + crsDocLin.Quantidade
		mCusto = mCusto + crsDocLin.PCusto * crsDocLin.Quantidade
	EndScan
	Select crsDocCab
	Replace crsDocCab.TotalQtt With mQtt, crsDocCab.TotalCusto With mCusto
EndProc

Procedure proc_insFT
	Local mDocStamp, mLinStamp, mNLin, mArm, mOk, insFT, insFi

	Select crsDocCab
	mDocStamp = u_stamp(Recno('crsDocCab'))
	mArm = func_armazem(crsDocCab.Armazem)
	proc_totaisLinha(crsDocCab.IDImport)

	Select crsSerFt
	Locate For crsDocCab.seriePHC = crsSerFt.ndoc
	If !Found()
		proc_insErr('Faturação', 'Erro info série nº' + Astr(crsDocCab.NumeroSerie), Alltrim(crsDocCab.Ficheiro))
		Return
	EndIf

	Text To insFT TextMerge NoShow
		Declare @Counter Int
		Begin Transaction

		INSERT INTO FT3 (ft3stamp,codpais,descpais,anexo40,anularetif,
			anulinis,anuldata,taxpointdt,atcud,u_ctrldata,ousrinis,
			ousrdata,ousrhora,usrinis,usrdata,usrhora)
		SELECT <<func_sqlLit(mDocStamp)>>,'PT','Portugal',td.tiporeg,
			<<func_sqlLit(Iif(crsDocCab.EstadoDocumento='A','Erro na emissão do documento',''))>>,
			<<func_sqlLit(Iif(crsDocCab.EstadoDocumento='A','Fuel',''))>>,
			'<<Dtosql(Iif(crsDocCab.EstadoDocumento='A',crsDocCab.DataRegisto,Date(1900,1,1)))>>',
			'<<Dtosql(crsDocCab.DataDoc)>>',<<func_sqlLit(crsDocCab.ATCUD)>>,
			'<<Dtosql(crsDocCab.DataDoc)>>',
			'Fuel',Convert(Date,Getdate()),Convert(Varchar(5),GetDate(),108),
			'Fuel',Convert(Date,Getdate()),Convert(Varchar(5),GetDate(),108)
		FROM td (NOLOCK) WHERE td.ndoc = <<Astr(crsDocCab.seriePHC)>>

		INSERT INTO FT2 (ft2stamp,vdollocal,vdcontado,vdlocal,olmoeda,pncont,
			formapag,assinatura,versaochave,descregiva,tiposaft,evdinheiro,
			vdinheiro,modop1,epaga1,paga1,modop2,epaga2,paga2,modop3,epaga3,paga3,
			modop4,epaga4,paga4,ousrinis,ousrdata,ousrhora,usrinis,usrdata,usrhora)
		SELECT <<func_sqlLit(mDocStamp)>>,td.vdollocal,td.vdcontado,td.vdlocal,td.olmoeda,
			'PT',1,<<func_sqlLit(crsDocCab.HashDGCI)>>,<<func_sqlLit(Astr(crsDocCab.ControlHash))>>,'PT',td.tiposaft,
			<<Astr(Adec_Tr(crsDocCab.Numerario))>>,<<Astr(Adec_Tr(crsDocCab.Numerario*200.482))>>,
			IIF(td.lancaol=1,'Multibanco',''),
			<<Iif(crsDocCab.MbTerm!='OPT',Astr(Adec_Tr(crsDocCab.Multibanco)),'0')>>,
			<<Iif(crsDocCab.MbTerm!='OPT',Astr(Adec_Tr(crsDocCab.Multibanco*200.482)),'0')>>,
			IIF(td.lancaol=1,'Cheque',''),<<Astr(Adec_Tr(crsDocCab.Cheque))>>,
			<<Astr(Adec_Tr(crsDocCab.Cheque*200.482))>>,
			IIF(td.lancaol=1,'Transf.Bancária',''),
			<<Astr(Adec_Tr(crsDocCab.TrfBanc))>>,<<Astr(Adec_Tr(crsDocCab.TrfBanc*200.482))>>,
			IIF(td.lancaol=1,'Multibanco OPT',''),
			<<Iif(crsDocCab.MbTerm='OPT',Astr(Adec_Tr(crsDocCab.Multibanco)),'0')>>,
			<<Iif(crsDocCab.MbTerm='OPT',Astr(Adec_Tr(crsDocCab.Multibanco*200.482)),'0')>>,
			'Fuel',Convert(Date,Getdate()),Convert(Varchar(5),GetDate(),108),
			'Fuel',Convert(Date,Getdate()),Convert(Varchar(5),GetDate(),108)
		FROM td (NOLOCK) WHERE td.ndoc = <<Astr(crsDocCab.seriePHC)>>

		INSERT INTO FT (ftstamp,pais,ndoc,nmdoc,tipodoc,fno,no,estab,nome,
			morada,local,codpost,ncont,vendedor,vendnm,tipo,fdata,ftano,
			ivatx1,ivatx2,ivatx3,ivatx4,ivain1,ivain2,ivain3,ivain4,ivav1,
			ivav2,ivav3,ivav4,eivain1,eivain2,eivain3,eivain4,eivav1,eivav2,
			eivav3,eivav4,qtt1,etot1,tot1,totqtt,ecusto,custo,moeda,memissao,
			ettiliq,ettiva,etotal,ttiliq,ttiva,total,anulado,saida,ousrinis,
			ousrdata,ousrhora,usrinis,usrdata,usrhora)
		SELECT <<func_sqlLit(mDocStamp)>>,1,td.ndoc,td.nmdoc,td.tipodoc,
			<<Astr(crsDocCab.NumeroSerie)>>,<<Astr(crsDocCab.clientePHC)>>,0,
			<<func_sqlLit(crsDocCab.Nome)>>,<<func_sqlLit(crsDocCab.Morada)>>,
			<<func_sqlLit(crsDocCab.Localidade)>>,
			<<func_sqlLit(Padl(Astr(crsDocCab.CodPostal4),4,'0')+'-'+Padl(Astr(crsDocCab.CodPostal3),3,'0'))>>,
			<<func_sqlLit(crsDocCab.NumContribuinte)>>,0,'','','<<Dtosql(crsDocCab.DataDoc)>>',
			<<Astr(Year(crsDocCab.DataDoc))>>,6,23,13,0,<<Astr(Adec_Tr(crsDocCab.Iva1Inc*200.482))>>,
			<<Astr(Adec_Tr(crsDocCab.Iva2Inc*200.482))>>,<<Astr(Adec_Tr(crsDocCab.Iva3Inc*200.482))>>,
			<<Astr(Adec_Tr(crsDocCab.Iva4Inc*200.482))>>,<<Astr(Adec_Tr(crsDocCab.Iva1Iva*200.482))>>,
			<<Astr(Adec_Tr(crsDocCab.Iva2Iva*200.482))>>,<<Astr(Adec_Tr(crsDocCab.Iva3Iva*200.482))>>,
			<<Astr(Adec_Tr(crsDocCab.Iva4Iva*200.482))>>,<<Astr(Adec_Tr(crsDocCab.Iva1Inc))>>,
			<<Astr(Adec_Tr(crsDocCab.Iva2Inc))>>,<<Astr(Adec_Tr(crsDocCab.Iva3Inc))>>,
			<<Astr(Adec_Tr(crsDocCab.Iva4Inc))>>,<<Astr(Adec_Tr(crsDocCab.Iva1Iva))>>,
			<<Astr(Adec_Tr(crsDocCab.Iva2Iva))>>,<<Astr(Adec_Tr(crsDocCab.Iva3Iva))>>,
			<<Astr(Adec_Tr(crsDocCab.Iva4Iva))>>,
			0,0,0,<<Astr(Adec_Tr(crsDocCab.TotalQtt))>>,
			<<Astr(Adec_Tr(crsDocCab.TotalCusto))>>,<<Astr(Adec_Tr(crsDocCab.TotalCusto*200.482))>>,
			'EURO','EURO',<<Astr(Adec_Tr(crsDocCab.ValorTotal-crsDocCab.ValorIva))>>,
			<<Astr(Adec_Tr(crsDocCab.ValorIva))>>,<<Astr(Adec_Tr(crsDocCab.ValorTotal))>>,
			<<Astr(Adec_Tr((crsDocCab.ValorTotal-crsDocCab.ValorIva)*200.482))>>,
			<<Astr(Adec_Tr(crsDocCab.ValorIva*200.482))>>,<<Astr(Adec_Tr(crsDocCab.ValorTotal*200.482))>>,
			<<Astr(Iif(crsDocCab.EstadoDocumento='A',1,0))>>,<<func_sqlLit(Left(crsDocCab.HoraRegisto,5))>>,
			'Fuel',Convert(Date,Getdate()),Convert(Varchar(5),GetDate(),108),
			'Fuel',Convert(Date,Getdate()),Convert(Varchar(5),GetDate(),108)
		FROM td (NOLOCK) WHERE td.ndoc = <<Astr(crsDocCab.seriePHC)>>

		Select @Counter = Count(*) From ft (Nolock)
			Inner Join ft2 (Nolock) On ft.ftstamp=ft2.ft2stamp
			Inner Join ft3 (Nolock) On ft.ftstamp=ft3.ft3stamp
		Where ft.ftstamp=<<func_sqlLit(mDocStamp)>>

		If @Counter=1
			Begin
			Commit Transaction
			End
		Else
			Begin
			Rollback Transaction
			End
		Select Cast(@Counter As Bit) 'rec'
	EndText

	If !u_sqlexec(insFT, [crsIFt])
		proc_insErr('Faturação', 'Erro inserir cabeçalho (1): nº' + Astr(crsDocCab.NumeroSerie), Alltrim(crsDocCab.Ficheiro))
		Return
	EndIf
	mOk = .F.
	If Reccount('crsIFt') > 0
		Select crsIFt
		mOk = crsIFt.rec
	EndIf
	Fecha([crsIFt])
	If !mOk
		proc_insErr('Faturação', 'Erro inserir cabeçalho (2): nº' + Astr(crsDocCab.NumeroSerie), Alltrim(crsDocCab.Ficheiro))
		Return
	EndIf

	Select * From crsDocLin Where crsDocLin.IDImport = crsDocCab.IDImport Into Cursor crsLinhas ReadWrite
	Select crsLinhas
	Scan
		func_ensureRef(crsLinhas.IDImport, crsLinhas.NumLinha)
		Select crsLinhas
		mLinStamp = u_stamp(Recno('crsLinhas'))
		mNLin = Iif(crsLinhas.Usalote And !Empty(crsLinhas.Lote), 1, 0)

		Text To insFi TextMerge NoShow
			Declare @FICount Int, @FI2Count Int
			Begin Transaction

			INSERT INTO FI (fistamp,ndoc,nmdoc,tipodoc,fno,ftstamp,rdata,lordem,
				ref,design,armazem,usalote,lote,familia,stns,usr1,usr2,usr3,usr4,
				usr5,usr6,unidade,qtt,iva,tabiva,desconto,desc2,u_puiviliq,pv,epv,
				tiliquido,etiliquido,tliquido,custo,ecusto,slvu,eslvu,sltt,esltt,
				pcp,epcp,cpoc,ivaincl,codmotiseimp,motiseimp,u_matricul,
				ousrinis,ousrdata,ousrhora,usrinis,usrdata,usrhora)
			SELECT <<func_sqlLit(mLinStamp)>>,td.ndoc,td.nmdoc,td.tipodoc,
				<<Astr(crsDocCab.NumeroSerie)>>,<<func_sqlLit(mDocStamp)>>,
				'<<Dtosql(crsDocCab.DataDoc)>>',<<Astr(crsLinhas.NumLinha)>>,
				st.ref,st.design,<<Astr(mArm)>>,<<Astr(func_linUsaLote(crsLinhas.Lote))>>,
				<<func_sqlLit(crsLinhas.Lote)>>,
				st.familia,st.stns,st.usr1,st.usr2,st.usr3,st.usr4,st.usr5,st.usr6,st.unidade,
				<<Astr(Adec_Tr(crsLinhas.Quantidade))>>,<<Astr(Adec_Tr(crsLinhas.PercIva))>>,
				<<Astr(func_getTabIva(crsLinhas.PercIva))>>,<<Astr(Adec_Tr(crsLinhas.Desconto1))>>,
				<<Astr(Adec_Tr(crsLinhas.Desconto2))>>,<<Astr(Adec_Tr(crsLinhas.PUnitIliqIva))>>,
				<<Astr(Adec_Tr(crsLinhas.PrecoUnitario*200.482))>>,<<Astr(Adec_Tr(crsLinhas.PrecoUnitario))>>,
				<<Astr(Adec_Tr(crsLinhas.ValorLinha*200.482))>>,<<Astr(Adec_Tr(crsLinhas.ValorLinha))>>,
				<<Astr(Adec_Tr(crsLinhas.ValorLinha*(1+crsLinhas.PercIva/100*Abs(crsLinhas.IvaIncluido-1))))>>,
				<<Astr(Adec_Tr(crsLinhas.PCusto*crsLinhas.Quantidade*200.482))>>,
				<<Astr(Adec_Tr(crsLinhas.PCusto*crsLinhas.Quantidade))>>,
				<<Astr(Adec_Tr(crsLinhas.PrecoUnitario/(1+crsLinhas.PercIva/100*crsLinhas.IvaIncluido)*200.482))>>,
				<<Astr(Adec_Tr(crsLinhas.PrecoUnitario/(1+crsLinhas.PercIva/100*crsLinhas.IvaIncluido)))>>,
				<<Astr(Adec_Tr(crsLinhas.ValorLinha/(1+crsLinhas.PercIva/100*crsLinhas.IvaIncluido)*200.482))>>,
				<<Astr(Adec_Tr(crsLinhas.ValorLinha/(1+crsLinhas.PercIva/100*crsLinhas.IvaIncluido)))>>,
				<<Astr(Adec_Tr(crsLinhas.PCusto*200.482))>>,<<Astr(Adec_Tr(crsLinhas.PCusto))>>,
				st.cpoc,<<Astr(crsLinhas.IvaIncluido)>>,<<func_sqlLit(crsLinhas.CodIsencaoIva)>>,
				<<func_sqlLit(crsLinhas.IsencaoIva)>>,<<func_sqlLit(crsDocCab.Matricula)>>,
				'Fuel',CONVERT(DATE,GETDATE()),CONVERT(VARCHAR(5),GETDATE(),108),
				'Fuel',CONVERT(DATE,GETDATE()),CONVERT(VARCHAR(5),GETDATE(),108)
			FROM st (NOLOCK), td (NOLOCK)
			WHERE st.ref=<<func_sqlLit(crsLinhas.refPHC)>> AND td.ndoc = <<Astr(crsDocCab.seriePHC)>>

			Select @FICount = @@RowCount

			INSERT INTO FI2 (fi2stamp,ftstamp,ousrinis,ousrdata,ousrhora,usrinis,usrdata,usrhora)
			VALUES(<<func_sqlLit(mLinStamp)>>,<<func_sqlLit(mDocStamp)>>,
				'Fuel',Convert(Date,Getdate()),Convert(Varchar(5),GetDate(),108),
				'Fuel',Convert(Date,Getdate()),Convert(Varchar(5),GetDate(),108))

			Select @FI2Count = @@RowCount

			If @FICount = @FI2Count And @FICount = 1
				Begin
				Commit Transaction
				Select Cast(1 As Bit) 'rec'
				End
			Else
				Begin
				Rollback Transaction
				Select Cast(0 As Bit) 'rec'
				End
		EndText

		If !u_sqlexec(insFi, [crsIFi])
			proc_insErr('Faturação', 'Erro inserir linhas: nº' + Astr(crsDocCab.NumeroSerie), Alltrim(crsDocCab.Ficheiro))
			Fecha([crsLinhas])
			Return
		EndIf
		If Reccount('crsIFi') > 0
			Select crsIFi
			If !crsIFi.rec
				proc_insErr('Faturação', 'Erro inserir linhas: nº' + Astr(crsDocCab.NumeroSerie), Alltrim(crsDocCab.Ficheiro))
				Fecha([crsIFi])
				Fecha([crsLinhas])
				Return
			EndIf
		EndIf
		Fecha([crsIFi])
		Select crsLinhas
	EndScan
	Fecha([crsLinhas])
	Select crsDocCab
	Replace crsDocCab.ImportOk With .T.
EndProc

Procedure proc_insBO
	Local mDocStamp, mLinStamp, mArm, mOk, insBO, insBI

	Select crsDocCab
	mDocStamp = u_stamp(Recno('crsDocCab'))
	mArm = func_armazem(crsDocCab.Armazem)
	proc_totaisLinha(crsDocCab.IDImport)

	Select crsSerBo
	Locate For crsDocCab.seriePHC = crsSerBo.ndos
	If !Found()
		proc_insErr('Dossier', 'Erro info. série nº' + Astr(crsDocCab.NumeroSerie), Alltrim(crsDocCab.Ficheiro))
		Return
	EndIf

	Text To insBO TextMerge NoShow
		Declare @Counter Int
		Begin Transaction

		Insert Into BO3 (bo3stamp,codpais,descpais,taxpointdt,atcud,
			ousrinis,ousrdata,ousrhora,usrinis,usrdata,usrhora)
		Values (<<func_sqlLit(mDocStamp)>>, 'PT', 'Portugal',
			'<<Dtosql(crsDocCab.DataDoc)>>',<<func_sqlLit(crsDocCab.ATCUD)>>,
			'Fuel',Convert(Date,Getdate()),Convert(Varchar(5),GetDate(),108),
			'Fuel',Convert(Date,Getdate()),Convert(Varchar(5),GetDate(),108))

		Insert Into BO2 (bo2stamp,tiposaft,idserie,anulado,
			totalciva,etotalciva,assinatura,versaochave,tkhhora,
			ousrinis,ousrdata,ousrhora,usrinis,usrdata,usrhora)
		SELECT <<func_sqlLit(mDocStamp)>>,ts.tiposaft,ts.idserie,
			<<Astr(Iif(crsDocCab.EstadoDocumento='A',1,0))>>,0,0,
			<<func_sqlLit(crsDocCab.HashDGCI)>>,<<Astr(crsDocCab.ControlHash)>>,
			<<func_sqlLit(Left(crsDocCab.HoraRegisto,5))>>,
			'Fuel',CONVERT(DATE,GETDATE()),CONVERT(VARCHAR(5),GETDATE(),108),
			'Fuel',CONVERT(DATE,GETDATE()),CONVERT(VARCHAR(5),GETDATE(),108)
		FROM ts (NOLOCK) WHERE ts.ndos=<<Astr(crsDocCab.seriePHC)>>

		Insert Into BO (bostamp,nmdos,obrano,dataobra,nome,totaldeb,etotaldeb,serie,
			sdeb4,sqtt14,stot4,no,obranome,boano,dataopen,total,obs,ndos,custo,
			moeda,morada,local,codpost,ncont,ccusto,esdeb4,estot4,etotal,ecusto,
			memissao,inome,ousrinis,ousrdata,ousrhora,usrinis,usrdata,usrhora)
		SELECT <<func_sqlLit(mDocStamp)>>,ts.nmdos,<<Astr(crsDocCab.NumeroSerie)>>,
			'<<Dtosql(crsDocCab.DataDoc)>>',<<func_sqlLit(crsDocCab.NomeTerceiro)>>,0,0,
			<<func_sqlLit(crsDocCab.Matricula)>>,0,0,0,<<Astr(crsDocCab.clientePHC)>>,'',
			<<Astr(Year(crsDocCab.DataDoc))>>,'<<Dtosql(crsDocCab.DataDoc)>>',
			<<Astr(Adec_Tr(crsDocCab.ValorTotal))>>,
			<<func_sqlLit(crsDocCab.Observacoes)>>,<<Astr(crsDocCab.seriePHC)>>,
			<<Astr(Adec_Tr(crsDocCab.TotalCusto*200.482))>>,'EURO',
			<<func_sqlLit(crsDocCab.Morada)>>,<<func_sqlLit(crsDocCab.Localidade)>>,
			<<func_sqlLit(Padl(Astr(crsDocCab.CodPostal4),4,'0')+'-'+Padl(Astr(crsDocCab.CodPostal3),3,'0'))>>,
			<<func_sqlLit(crsDocCab.NumContribuinte)>>,'',0,0,
			<<Astr(Adec_Tr(crsDocCab.ValorTotal))>>,<<Astr(Adec_Tr(crsDocCab.TotalCusto))>>,
			'EURO',<<func_sqlLit(crsDocCab.Autor)>>,
			'Fuel',CONVERT(DATE,GETDATE()),CONVERT(VARCHAR(5),GETDATE(),108),
			'Fuel',CONVERT(DATE,GETDATE()),CONVERT(VARCHAR(5),GETDATE(),108)
		FROM ts (NOLOCK) WHERE ts.ndos=<<Astr(crsDocCab.seriePHC)>>

		Select @Counter = Count(*) From bo (Nolock) Inner Join bo2 (Nolock) On bo.bostamp=bo2.bo2stamp
			Inner Join bo3 (Nolock) On bo.bostamp=bo3.bo3stamp
		Where bo.bostamp=<<func_sqlLit(mDocStamp)>>

		If @Counter=1
			Begin
			Commit Transaction
			End
		Else
			Begin
			Rollback Transaction
			End
		Select Cast(@Counter As Bit) 'rec'
	EndText

	If !u_sqlexec(insBO, [crsIBO])
		proc_insErr('Dossier', 'Erro inserir cabeçalho: nº' + Astr(crsDocCab.NumeroSerie), Alltrim(crsDocCab.Ficheiro))
		Return
	EndIf
	mOk = .F.
	If Reccount('crsIBO') > 0
		Select crsIBO
		mOk = crsIBO.rec
	EndIf
	Fecha([crsIBO])
	If !mOk
		proc_insErr('Dossier', 'Erro inserir cabeçalho: nº' + Astr(crsDocCab.NumeroSerie), Alltrim(crsDocCab.Ficheiro))
		Return
	EndIf

	Select * From crsDocLin Where crsDocLin.Area = crsDocCab.Area And crsDocLin.IDImport = crsDocCab.IDImport ;
		Into Cursor crsLinhas ReadWrite
	Select crsLinhas
	Scan
		func_ensureRef(crsLinhas.IDImport, crsLinhas.NumLinha)
		Select crsLinhas
		mLinStamp = u_stamp(Recno('crsLinhas'))

		Text To insBI TextMerge NoShow
			Declare @BICount Int, @BI2Count Int
			Begin Transaction

			Insert Into BI (bistamp,nmdos,obrano,ref,design,qtt,iva,tabiva,armazem,pu,debito,
				prorc,stipo,no,pcusto,ndos,dataobra,dataopen,rdata,lordem,local,morada,codpost,
				nome,ivaincl,epu,edebito,eprorc,epcusto,ttdeb,ettdeb,codigo,cpoc,stns,unidade,
				familia,slvu,eslvu,sltt,esltt,desconto,desc2,ccusto,bostamp,u_puiviliq,lobs3,
				usalote,lote,ousrinis,ousrdata,ousrhora,usrinis,usrdata,usrhora)
			SELECT <<func_sqlLit(mLinStamp)>>,ts.nmdos,<<Astr(crsDocCab.NumeroSerie)>>,
				st.ref,st.design,<<Astr(Adec_Tr(crsLinhas.Quantidade))>>,
				<<Astr(Adec_Tr(crsLinhas.PercIva))>>,<<Astr(func_getTabIva(crsLinhas.PercIva))>>,
				<<Astr(mArm)>>,<<Astr(Adec_Tr(crsLinhas.PrecoUnitario*200.482))>>,
				<<Astr(Adec_Tr(crsLinhas.PrecoUnitario*200.482))>>,
				<<Astr(Adec_Tr(crsLinhas.PrecoUnitario*200.482))>>,ts.ocupacao,
				<<Astr(crsDocCab.clientePHC)>>,<<Astr(Adec_Tr(crsLinhas.PCusto*200.482))>>,
				ts.ndos,'<<Dtosql(crsDocCab.DataDoc)>>','<<Dtosql(crsDocCab.DataDoc)>>',
				'<<Dtosql(crsDocCab.DataDoc)>>',<<Astr(crsLinhas.NumLinha)>>,
				<<func_sqlLit(crsDocCab.Localidade)>>,<<func_sqlLit(crsDocCab.Morada)>>,
				<<func_sqlLit(Padl(Astr(crsDocCab.CodPostal4),4,'0')+'-'+Padl(Astr(crsDocCab.CodPostal3),3,'0'))>>,
				<<func_sqlLit(crsDocCab.NomeTerceiro)>>,<<Astr(crsLinhas.IvaIncluido)>>,
				<<Astr(Adec_Tr(crsLinhas.PrecoUnitario))>>,<<Astr(Adec_Tr(crsLinhas.PrecoUnitario))>>,
				<<Astr(Adec_Tr(crsLinhas.PrecoUnitario))>>,<<Astr(Adec_Tr(crsLinhas.PCusto))>>,
				<<Astr(Adec_Tr(crsLinhas.ValorLinha*200.482))>>,<<Astr(Adec_Tr(crsLinhas.ValorLinha))>>,
				st.codigo,st.cpoc,st.stns,st.unidade,st.familia,
				<<Astr(Adec_Tr(crsLinhas.PrecoUnitario*200.482))>>,<<Astr(Adec_Tr(crsLinhas.PrecoUnitario))>>,
				<<Astr(Adec_Tr(crsLinhas.ValorLinha*200.482))>>,<<Astr(Adec_Tr(crsLinhas.ValorLinha))>>,
				<<Astr(Adec_Tr(crsLinhas.Desconto1))>>,<<Astr(Adec_Tr(crsLinhas.Desconto2))>>,'',
				<<func_sqlLit(mDocStamp)>>,<<Astr(Adec_Tr(crsLinhas.PUnitIliqIva))>>,
				<<func_sqlLit(crsDocCab.Matricula)>>,
				<<Astr(func_linUsaLote(crsLinhas.Lote))>>,<<func_sqlLit(crsLinhas.Lote)>>,
				'Fuel',CONVERT(DATE,GETDATE()),CONVERT(VARCHAR(5),GETDATE(),108),
				'Fuel',CONVERT(DATE,GETDATE()),CONVERT(VARCHAR(5),GETDATE(),108)
			FROM st (NOLOCK), ts (NOLOCK)
			WHERE st.ref=<<func_sqlLit(crsLinhas.refPHC)>> AND ts.ndos=<<Astr(crsDocCab.seriePHC)>>

			Select @BICount = @@RowCount

			Insert Into BI2 (bi2stamp,bostamp,ousrinis,ousrdata,ousrhora,usrinis,usrdata,usrhora)
			Values(<<func_sqlLit(mLinStamp)>>,<<func_sqlLit(mDocStamp)>>,
				'Fuel',Convert(Date,Getdate()),Convert(Varchar(5),GetDate(),108),
				'Fuel',Convert(Date,Getdate()),Convert(Varchar(5),GetDate(),108))

			Select @BI2Count = @@RowCount

			If @BICount = @BI2Count And @BICount = 1
				Begin
				Commit Transaction
				Select Cast(1 As Bit) 'rec'
				End
			Else
				Begin
				Rollback Transaction
				Select Cast(0 As Bit) 'rec'
				End
		EndText

		If !u_sqlexec(insBI, [crsIBI])
			proc_insErr('Dossier', 'Erro inserir linhas: nº' + Astr(crsDocCab.NumeroSerie), Alltrim(crsDocCab.Ficheiro))
			Fecha([crsLinhas])
			Return
		EndIf
		If Reccount('crsIBI') > 0
			Select crsIBI
			If !crsIBI.rec
				proc_insErr('Dossier', 'Erro inserir linhas: nº' + Astr(crsDocCab.NumeroSerie), Alltrim(crsDocCab.Ficheiro))
				Fecha([crsIBI])
				Fecha([crsLinhas])
				Return
			EndIf
		EndIf
		Fecha([crsIBI])
		Select crsLinhas
	EndScan
	Fecha([crsLinhas])
	Select crsDocCab
	Replace crsDocCab.ImportOk With .T.
EndProc

Procedure proc_insErr
	Lparameters mClass, mInf, mFich
	Local mOld
	mOld = Alias()
	Select crsErr
	Append Blank
	Replace crsErr.Classe With Alltrim(mClass), ;
		crsErr.Info With Alltrim(mInf), ;
		crsErr.Ficheiro With Alltrim(mFich)
	If !Empty(mOld) And Used(mOld)
		Select (mOld)
	EndIf
EndProc

Procedure proc_chkImportedFiles
	Local mFile, mHasErr, mFail, mTot

	Select crsFList
	Scan
		mFile = Alltrim(crsFList.FName)
		Select crsErr
		Locate For Alltrim(crsErr.Ficheiro) == mFile
		mHasErr = Found()

		Select crsDocCab
		Count For Alltrim(crsDocCab.Ficheiro) == mFile To mTot
		Count For Alltrim(crsDocCab.Ficheiro) == mFile And !(crsDocCab.ImportOk Or crsDocCab.Existe Or crsDocCab.Ignorar) To mFail

		If !mHasErr And mFail = 0 And mTot > 0
			Select crsFList
			Rename Addbs(Alltrim(crsFList.FPath)) + Alltrim(crsFList.FName) ;
				To Addbs(Alltrim(crsFList.FPath)) + Alltrim(crsFList.FName) + '.importado'
		EndIf
		Select crsFList
	EndScan
	DeactForm()
	Return .T.
EndProc

*==============================================================================*
* Mapa de documentos importados (inalterado na lógica de consulta)
*==============================================================================*

Procedure proc_recImp
	Local mCtrl, mDIMapa, mDFMapa, synDocSel

	Create Cursor xVars (no N(5), tipo C(1), Nome C(40), Pict C(100), ;
		lOrdem N(10), nValor N(18,5), cValor C(250), dValor D)

	Select xVars
	Append Blank
	Replace xVars.no With 1, xVars.tipo With 'D', xVars.Nome With 'Data inicial', ;
		xVars.lOrdem With 1, xVars.dValor With Date()
	Append Blank
	Replace xVars.no With 2, xVars.tipo With 'D', xVars.Nome With 'Data final', ;
		xVars.lOrdem With 2, xVars.dValor With Date()

	mCtrl = .T.
	m.Escolheu = .F.
	m.mCaption = 'Registo de documentos importados'

	Do While mCtrl
		DoComando("do form usqlvar with 'xvars',m.mCaption,.F.")
		If !m.Escolheu
			Mensagem('Operação interrompida!', 'Directa')
			Return
		EndIf
		Select xVars
		Locate For xVars.no = 1
		mDIMapa = xVars.dValor
		Locate For xVars.no = 2
		mDFMapa = xVars.dValor
		If Datavazia(mDIMapa) Or Datavazia(mDFMapa) Or mDIMapa > mDFMapa
			Mensagem('Datas inválidas', 'Directa')
			Loop
		EndIf
		mCtrl = .F.
	EndDo

	Text To synDocSel TextMerge NoShow
		SELECT 'Faturação' origem,td.ndoc cod,td.nmdoc serie, MIN(fno) inicio, MAX(fno) fim, MAX(fno)-MIN(fno)+1 esperado,
			COUNT(ftstamp) importado, MAX(fno)-MIN(fno)+1-COUNT(ftstamp) diferenca
		FROM td (NOLOCK) INNER JOIN ft (NOLOCK) ON td.ndoc=ft.ndoc
		WHERE docsimport=1 AND fdata BETWEEN '<<Dtosql(mDIMapa)>>' AND '<<Dtosql(mDFMapa)>>'
		GROUP BY td.ndoc,td.nmdoc
		UNION
		SELECT 'Dossiers' origem,ts.ndos cod,ts.nmdos serie, MIN(obrano) inicio, MAX(obrano) fim, MAX(obrano)-MIN(obrano)+1 esperado,
			COUNT(bostamp) importado, MAX(obrano)-MIN(obrano)+1-COUNT(bostamp) diferenca
		FROM ts (NOLOCK) INNER JOIN bo (NOLOCK) ON ts.ndos=bo.ndos INNER JOIN ts2 (NOLOCK) ON ts.tsstamp=ts2.ts2stamp
		WHERE docsimport=1 AND dataobra BETWEEN '<<Dtosql(mDIMapa)>>' AND '<<Dtosql(mDFMapa)>>'
		GROUP BY ts.ndos,ts.nmdos
		ORDER BY 1,3
	EndText
	If !u_sqlexec(synDocSel, [crsSyncDoc])
		Mensagem('Erro a consultar documentos sincronizados do periodo selecionado' + Chr(13) + Message(), 'Directa')
		Return
	EndIf
	If Reccount('crsSyncDoc') = 0
		Mensagem('Sem registos para exibir', 'Directa')
		Return
	EndIf

	Select crsSyncDoc
	Declare list_tit(8), list_cam(8), list_tam(8), list_pic(8)
	list_tit(1) = "Origem"
	list_tit(2) = "Código"
	list_tit(3) = "Série"
	list_tit(4) = "Início"
	list_tit(5) = "Fim"
	list_tit(6) = "Esperado"
	list_tit(7) = "Importado"
	list_tit(8) = "Diferença"
	list_cam(1) = "crsSyncDoc.origem"
	list_cam(2) = "crsSyncDoc.cod"
	list_cam(3) = "crsSyncDoc.serie"
	list_cam(4) = "crsSyncDoc.inicio"
	list_cam(5) = "crsSyncDoc.fim"
	list_cam(6) = "crsSyncDoc.esperado"
	list_cam(7) = "crsSyncDoc.importado"
	list_cam(8) = "crsSyncDoc.diferenca"
	list_pic = "999 999"
	list_pic(1) = ""
	list_pic(3) = ""
	list_tam = 8 * 10
	list_tam(3) = 8 * 20
	Browlist('Registos importados (' + Astr(mDIMapa) + ' - ' + Astr(mDFMapa) + ')', ;
		'crsSyncDoc', 'listSyncDoc', .F., .F., .F., .T., .F., '', .T.)
EndProc
