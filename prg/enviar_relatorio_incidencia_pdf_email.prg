*===============================================================================
* Envio do Relatório de Incidências por email com PDF anexo
*
* Problema original: IduToPdf falhava em silêncio (pasta backup inexistente /
* sem validação de FILE), e u_sendmailhtml enviava o email sem anexo.
*
* Correção: garantir pasta, caminho absoluto, validar PDF antes do envio.
*===============================================================================

If !Used([u_reccli])
	Return
Else
	If Empty(u_reccli.u_recclistamp)
		Return
	EndIf
EndIf

Select u_reccli

If !Used([usql])
	Do DBFUSEUSQL
EndIf

v_usqlstamp = 'Adm26071634087,4110000-1'
u_requery([usql])

Select usql
u_sqlexec([SELECT ] + usqlfields() + [ FROM usql WHERE usqlstamp='] + usql.usqlstamp + ['],[tempsql])

Select tempsql
Replace tempsql.lindex With 1

If !Gensqlp([IduUsql])
	Return
EndIf

LOCAL mIDU, cPdfDir, cHtmlArtigos, mResult
mIDU = 'Relatório de Incidências (Rosto)'

*--- Caminho absoluto estável + pasta backup ---
cPdfDir = Addbs(Sys(5) + Curdir()) + 'backup'
If !Directory(m.cPdfDir)
	Md (m.cPdfDir)
EndIf

* Nome único evita locks de ficheiro anterior com o mesmo nome
m.FileName = Forcepath('RelatorioIncidencia_' + Alltrim(Astr(u_reccli.norec)) + '.pdf', m.cPdfDir)

mostrameisto([SQLTMP])

If Reccount([SQLTMP]) = 0
	msg('sem dados')
	Return
EndIf

* Remover PDF anterior (se existir e não estiver bloqueado)
If File(m.FileName)
	Try
		Delete File (m.FileName)
	Catch
		Mensagem('Não foi possível substituir o PDF existente:' + Chr(13) + m.FileName + ;
			Chr(13) + 'Feche o ficheiro se estiver aberto e tente novamente.','Directa')
		Return
	EndTry
EndIf

IduToPdf([SQLTMP], [], [usqlcampos With 'SQLTMP.','STD'], [iduusqlcampos With 'SQLTMP.','STD'], ;
	[IDUUSQLMDC], [IDUUSQLMDL], 295, m.mIDU, m.FileName, [], [], .T., [IDUUSQL], [])

*--- Validação obrigatória: sem PDF válido, não enviar email ---
If !File(m.FileName) Or Fsize(m.FileName) = 0
	Mensagem('O PDF do relatório da incidência nº ' + Alltrim(Astr(u_reccli.norec)) + ;
		' não foi gerado.' + Chr(13) + Chr(13) + ;
		'Caminho: ' + m.FileName + Chr(13) + Chr(13) + ;
		'Verifique o IDU "' + m.mIDU + '", a pasta backup e tente novamente.','Directa')
	Return
EndIf

*--- 1. Linhas HTML da tabela de artigos ---
cHtmlArtigos = ''

Select u_recref
Scan
	cHtmlArtigos = m.cHtmlArtigos + '<tr>' + ;
		"<td style='padding: 8px; border-bottom: 1px solid #DBDBDB;'><font color='#333333' size='2' face='Segoe UI'>" + Alltrim(u_recref.ref) + '</font></td>' + ;
		"<td style='padding: 8px; border-bottom: 1px solid #DBDBDB;'><font color='#333333' size='2' face='Segoe UI'>" + Alltrim(u_recref.design) + '</font></td>' + ;
		"<td style='padding: 8px; border-bottom: 1px solid #DBDBDB; text-align: center;'><font color='#333333' size='2' face='Segoe UI'>" + Transform(u_recref.qtt) + '</font></td>' + ;
		'</tr>'
EndScan

*--- 2. Corpo HTML do email ---
Text To m.EmailBody TextMerge NoShow
	<html xmlns:v="urn:schemas-microsoft-com:vml" xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:w="urn:schemas-microsoft-com:office:word" xmlns:m="http://schemas.microsoft.com/office/2004/12/omml" xmlns="http://www.w3.org/TR/REC-html40">
	<head>
		<title>Matobra</title>
		<meta http-equiv="Content-Type" content="text/html; charset=utf-8">
		<meta name="viewport" content="width=device-width, initial-scale=1.0">
		<link href="https://fonts.googleapis.com/css?family=Source+Sans+Pro" rel="stylesheet" type="text/css">
		<meta http-equiv=Content-Type content="text/html; charset=iso-8859-1">
		<meta name=Generator content="Microsoft Word 15 (filtered medium)">
		<!--[if !mso]><style>v\:* {behavior:url(#default#VML);}
		o\:* {behavior:url(#default#VML);}
		w\:* {behavior:url(#default#VML);}
		.shape {behavior:url(#default#VML);}
		</style><![endif]-->
		<style>
		@font-face {font-family:"Cambria Math"; panose-1:2 4 5 3 5 4 6 3 2 4;}
		@font-face {font-family:Calibri; panose-1:2 15 5 2 2 2 4 3 2 4;}
		@font-face {font-family:"Adobe Caslon Pro"; panose-1:2 5 5 2 5 5 10 2 4 3;}
		p.MsoNormal, li.MsoNormal, div.MsoNormal {margin:0cm; margin-bottom:.0001pt; font-size:11.0pt; font-family:"Calibri",sans-serif; color:#333333; mso-fareast-language:EN-US;}
		.MsoChpDefault {mso-style-type:export-only; font-family:"Calibri",sans-serif; mso-fareast-language:EN-US;}
		@page WordSection1 {size:612.0pt 792.0pt; margin:70.85pt 3.0cm 70.85pt 3.0cm;}
		div.WordSection1 {page:WordSection1;}
		body, table, td, p, span, div, font, b {
			font-family: Calibri, "Segoe UI", Arial, sans-serif !important;
		}
		</style>
	</head>
	<body lang=PT link="#0563C1" vlink="#954F72">
	<div class=WordSection1>
	<p class="MsoNormal" align="center" style="text-align:center"><b><span style="font-family:Calibri,sans-serif;color:white;opacity:0;mso-fareast-language:PT">Envio de documento.<o:p></o:p></span></b></p>

	<div align="center" style="text-align:center; margin-bottom: 20px;">
	<span style='font-size:12.0pt;color:black;mso-fareast-language:PT'>
	<img width=600 height=200 style='width:6.2083in;height:3.75in; max-width:100%; height:auto;' id="Imagem_x0020_1" src="https://www.jorinf.pt/wp-content/uploads/2026/04/matobra_EmailHeader.jpg"><o:p></o:p>
	</span>
	</div>

	<div class=WordSection1>
		<table class=MsoNormalTable border=0 align=center cellspacing=0 cellpadding=0 width=600 style='width:600px; background:white; border-collapse:collapse; mso-yfti-tbllook:1184; mso-padding-alt:0cm 0cm 0cm 0cm'>
			<tr style='mso-yfti-irow:0;mso-yfti-firstrow:yes'>
				<td width=600 colspan=2 style='width:600px;border:none;border-bottom:solid #efa80e 1.0pt; mso-border-bottom-alt:solid #efa80e .75pt;padding:0cm 0cm 3.0pt 0cm'>
					<p class=MsoNormal><span style='text-align: center; font-size:10.5pt;font-family:Calibri,sans-serif;color:#efa80e'><o:p>&nbsp;</o:p></span></p>
				</td>
			</tr>
		</table>
	</div>
	<p class=MsoNormal align=center style='text-align:center'>
	<span style='color:black;mso-fareast-language:PT'><o:p>&nbsp;</o:p></span>
	</p>
	<p class=MsoNormal align=center style='text-align:center;background:white'>
	<span style='color:black;mso-fareast-language:PT'>Estimado cliente,</span>
	</p>
	<p class=MsoNormal align=center style='text-align:center;background:white'>
	<span style='color:black;mso-fareast-language:PT'>Mais uma vez agradecemos a preferência em trabalhar com a Matobra.</span>
	</p>
	<p class=MsoNormal align=center style='text-align:center;background:white'>
	<span style='color:black;mso-fareast-language:PT'><o:p>&nbsp;</o:p></span>
	</p>
	<p class=MsoNormal align=center style='text-align:center;background:white'>
	<span style='color:black;mso-fareast-language:PT'>A sua comunicação relativa à incidência registada sob o nº <b><<Astr(u_reccli.norec)>></b> de <b><<Astr(u_reccli.data)>></b></span>
	</p>
	<p class=MsoNormal align=center style='text-align:center;background:white'>
	<span style='color:black;mso-fareast-language:PT'>mereceu a nossa melhor e imediata atenção.</span>
	</p>
	<p class=MsoNormal align=center style='text-align:center;background:white'>
	<span style='color:black;mso-fareast-language:PT'><o:p>&nbsp;</o:p></span>
	</p>
	<p class=MsoNormal align=center style='text-align:center;background:white'>
	<span style='color:black;mso-fareast-language:PT'>Submetemos em anexo o relatório de incidências para os seguintes artigos:</span>
	</p>
	<p class=MsoNormal align=center style='text-align:center;background:white'>
	<span style='color:black;mso-fareast-language:PT'><o:p>&nbsp;</o:p></span>
	</p>
	<div align="center">
	<center>
	<table class="b1" borderColor="#efa80e" cellSpacing="1" cellPadding="8" width="600" bgColor="#FFFFFF" borderColorLight="#DBDBDB" border="0" bordercolordark="#FFFFFF">
		<tr>
			<td vAlign="bottom" borderColorLight="#C0C0C0" borderColorDark="#FFFFFF" style="font-family:Calibri,sans-serif; filter:progid:DXImageTransform.Microsoft.Gradient(startColorStr='#FFFFFF', endColorStr='#AEC0EC', gradientType='0')"><font color="#545454" size="3" face="Calibri, sans-serif"><b>Referência</b></font></td>
			<td vAlign="bottom" borderColorLight="#C0C0C0" borderColorDark="#FFFFFF" style="font-family:Calibri,sans-serif; filter:progid:DXImageTransform.Microsoft.Gradient(startColorStr='#FFFFFF', endColorStr='#AEC0EC', gradientType='0')"><font color="#545454" size="3" face="Calibri, sans-serif"><b>Designação</b></font></td>
			<td vAlign="bottom" borderColorLight="#C0C0C0" borderColorDark="#FFFFFF" style="font-family:Calibri,sans-serif; filter:progid:DXImageTransform.Microsoft.Gradient(startColorStr='#FFFFFF', endColorStr='#AEC0EC', gradientType='0')"><font color="#545454" size="3" face="Calibri, sans-serif"><b>Quantidade</b></font></td>
		</tr>
		<<m.cHtmlArtigos>>
	</table>
	</center>
	</div>
	</div>
	<p class=MsoNormal align=center style='text-align:center;background:white'>
	<span style='color:black;mso-fareast-language:PT'><o:p>&nbsp;</o:p></span>
	</p>
	<div align="center">
	<table border="0" cellspacing="0" cellpadding="0" width="600" align="center" style="width:600px; margin: 20px auto 0 auto; border-top:1px solid #efa80e; padding-top:15px;">
		<tr>
			<td align="center" style="text-align:center; font-family:Calibri,sans-serif; font-size:11pt; color:#545454; line-height:1.5;">
				<strong>Matobra</strong><br>
				Rua Luís Ramos, Pedrulha, Coimbra | Telefone: 239 433 778 | E-mail: mail@matobra.pt<br>
				<a href="https://www.matobra.pt" target="_blank" style="color:#0563C1; text-decoration:none; font-family:Calibri,sans-serif;">www.matobra.pt</a>&nbsp;
				| <a href="https://df502dca-996b-4f5f-abe4-943cc8e8ec26.filesusr.com/ugd/224121_b09d1c191b03482b924bd23ade0921ba.pdf" target="_blank" style="color:#545454; text-decoration:underline; font-family:Calibri,sans-serif;">Política de Privacidade</a>
			</td>
		</tr>
	</table>
	</div>
	</body>
	</html>
EndText

*--- Configurações de Email ---
m.sSmtpServer = ret_defeito([usermain.gel_smtpserver],[C],space(50))
m.sUserSmtp   = ret_defeito([usermain.gel_usersmtp],[C],space(50))
m.sPassSmtp   = ret_defeito([usermain.gel_passsmtp],[C],space(50))
m.sPortaSmtp  = ret_defeito([usermain.gel_portasmtp],[C],space(50))
m.sLigSmtp    = ret_defeito([usermain.gel_ligsmtp],[N],2,0)
m.OpenClient  = .F.
m.Quiet       = .T.

m.SendTo  = 'valterjd@jorinf.pt'
m.Subject = 'Relatório da n/Incidência nº ' + Astr(u_reccli.norec)

mResult = u_sendmailhtml(m.SendTo, m.Subject, m.EmailBody, m.FileName, m.OpenClient, m.Quiet, '', ;
	m.sUserSmtp, m.sSmtpServer, m.sUserSmtp, m.sPassSmtp, m.sPortaSmtp, m.sLigSmtp)

If mResult != 0
	DeactForm()
	Mensagem('O relatório da incidência nº ' + Alltrim(Astr(u_reccli.norec)) + ;
		' não foi enviado. Verifique a sua ligação à internet e tente novamente.','Directa')
Else
	Mensagem('Email enviado com sucesso','Directa')
EndIf

Return
