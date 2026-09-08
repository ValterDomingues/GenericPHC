*==============================================================================*
* lista_pick_csv.prg
*
* Depois de cada Browlist, percorre o cursor e concatena numa variável de
* texto os valores da coluna chave (no / cm) dos registos com pick = .T.,
* separados por vírgula.
*
* Resultado:
*   m.listaNo  →  "12,45,108"
*   m.listaCm  →  "100,210,310"
*
* As duas listas podem ser usadas depois, por exemplo:
*   ... WHERE no IN (" + m.listaNo + ") ...
*   ... WHERE cm IN (" + m.listaCm + ") ...
*==============================================================================*

If !U_sqlexec([SELECT no,nome,CAST(1 AS BIT) pick FROM pe (NOLOCK) WHERE inactivo=0],[crsPE])
	Mensagem('Erro a consultar funcionários'+Chr(13)+Message(),'Directa')
	Return
EndIf

If !U_sqlexec([SELECT cm,cmdesc,CAST(1 AS BIT) pick FROM cm6 (NOLOCK) WHERE inactivo=0],[crsCM6])
	Mensagem('Erro a consultar codigos de remuneração/descontos'+Chr(13)+Message(),'Directa')
	Return
EndIf

&& Seleção de funcionários
Select crsPE
=CURSORSETPROP('Buffering',5,[crsPE])
DECLARE list_tit(3),list_cam(3),list_tam(3),list_pic(3),list_ronly(3)

list_tit(1)="Nº"
list_tit(2)="Nome"
list_tit(3)="Seleção"

list_cam(1)="crsPE.no"
list_cam(2)="crsPE.nome"
list_cam(3)="crsPE.pick"

list_ronly=.T.
list_ronly(3)=.F.

list_pic(1)="99999"
list_pic(2)=""
list_pic(3)="LOGIC"

list_tam=8*6
list_tam(2)=8*40

m.escolheu=.f.
Browlist('Seleção de funcionários','crsPE','listPE',.T.,.F.,.F.,.T.,.F.,'',.t.)
If !m.escolheu
	Return
Else
	Select crsPE
	Locate For crsPE.pick
	If !Found()
		Mensagem('Sem registo selecionados','Directa')
		Return
	EndIf
EndIf

* Números de funcionário seleccionados, separados por vírgula
m.listaNo = func_ListaPick('crsPE', 'no')

&& Seleção de códigos de remuneração/descontos
Select crsCM6
=CURSORSETPROP('Buffering',5,[crsCM6])
DECLARE list_tit(3),list_cam(3),list_tam(3),list_pic(3),list_ronly(3)

list_tit(1)="Código"
list_tit(2)="Descrição"
list_tit(3)="Seleção"

list_cam(1)="crsCM6.cm"
list_cam(2)="crsCM6.cmdesc"
list_cam(3)="crsCM6.pick"

list_ronly=.T.
list_ronly(3)=.F.

list_pic(1)="9999"
list_pic(2)=""
list_pic(3)="LOGIC"

list_tam=8*6
list_tam(2)=8*40

m.escolheu=.f.
Browlist('Seleção de códigos remuneração/desconto','crsCM6','listCM6',.T.,.F.,.F.,.T.,.F.,'',.t.)
If !m.escolheu
	Return
Else
	Select crsCM6
	Locate For crsCM6.pick
	If !Found()
		Mensagem('Sem registo selecionados','Directa')
		Return
	EndIf
EndIf

* Códigos de remuneração/desconto seleccionados, separados por vírgula
m.listaCm = func_ListaPick('crsCM6', 'cm')

* m.listaNo e m.listaCm estão prontas a usar


*==============================================================================*
* func_ListaPick
* Percorre tcAlias e devolve os valores de tcCampo concatenados com vírgula
* para as linhas em que a coluna pick está a .T.
*
* Se o código for colado num slot PHC que não aceita Function, substituir
* cada chamada pela versão inline (SCAN) documentada no fim deste ficheiro.
*==============================================================================*
Function func_ListaPick
Lparameters tcAlias, tcCampo
	Local lcLista, lcAlias, lcCampo, lnArea, luValor, lcValor

	lcLista = ''
	lcAlias = Alltrim(tcAlias)
	lcCampo = Alltrim(tcCampo)

	If Empty(lcAlias) Or Empty(lcCampo) Or !Used(lcAlias)
		Return lcLista
	EndIf

	lnArea = Select()
	Select (lcAlias)
	Scan For Evaluate(lcAlias + '.pick')
		luValor = Evaluate(lcAlias + '.' + lcCampo)
		Do Case
			Case Vartype(luValor) $ 'NYB'
				* Inteiro sem espaços nem casas decimais (STR preenche à esquerda)
				lcValor = Alltrim(Str(luValor, 18, 0))
			Otherwise
				lcValor = Alltrim(Transform(luValor))
		EndCase
		If !Empty(lcValor)
			If !Empty(lcLista)
				lcLista = lcLista + ','
			EndIf
			lcLista = lcLista + lcValor
		EndIf
	EndScan
	Select (lnArea)

	Return lcLista
EndFunc


*------------------------------------------------------------------------------
* Versão inline (sem Function) — equivalente às duas chamadas acima:
*
*	m.listaNo = ''
*	Select crsPE
*	Scan For crsPE.pick
*		If !Empty(m.listaNo)
*			m.listaNo = m.listaNo + ','
*		EndIf
*		m.listaNo = m.listaNo + Alltrim(Str(crsPE.no, 18, 0))
*	EndScan
*
*	m.listaCm = ''
*	Select crsCM6
*	Scan For crsCM6.pick
*		If !Empty(m.listaCm)
*			m.listaCm = m.listaCm + ','
*		EndIf
*		m.listaCm = m.listaCm + Alltrim(Str(crsCM6.cm, 18, 0))
*	EndScan
*------------------------------------------------------------------------------
