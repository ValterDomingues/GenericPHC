/*
	Cativos por faturar — encomendas (ndos 1 e 26).

	Rodapé:
	  @mDetalhe = 1
	      Soma de ValorPorFaturar e média de IdadeCativo.
	  @mDetalhe = 0, @mMostraAtend = 1
	      Soma de ValorPorFaturar e ValorFaturado e média de IdadeMediaCativo.
	  @mDetalhe = 0, @mMostraAtend = 0
	      Mesmas somas e a mesma média, no resumo só por vendedor.

	A média do rodapé é a média dos valores apresentados nessa coluna
	(no resumo, a média das médias do agrupamento, não ponderada pelo
	número de linhas). O corpo mantém a idade em dias inteiros; o rodapé
	mostra a média com 2 casas.

	ft/fi serve só para a data da primeira fatura da linha (MIN fdata),
	em qualquer modo. O resumo antigo repetia a linha de encomenda por
	cada linha de fatura e inflacionava somas e a média.
*/

SET NOCOUNT ON;

DECLARE @mDtIni DATETIME = '20260501';
DECLARE @mDtFin DATETIME = '20260531';
DECLARE @mVendedor VARCHAR(30) = 'ANDRE';
DECLARE @mAtendimento VARCHAR(30) = '';
DECLARE @mDetalhe BIT = 0;
DECLARE @mMostraAtend BIT = 0;

DECLARE @mAgora DATETIME = GETDATE();

IF OBJECT_ID('tempdb..#linhas') IS NOT NULL DROP TABLE #linhas;
IF OBJECT_ID('tempdb..#fatura') IS NOT NULL DROP TABLE #fatura;
IF OBJECT_ID('tempdb..#calc') IS NOT NULL DROP TABLE #calc;
IF OBJECT_ID('tempdb..#resumoAtend') IS NOT NULL DROP TABLE #resumoAtend;
IF OBJECT_ID('tempdb..#resumoVend') IS NOT NULL DROP TABLE #resumoVend;

-- Uma passagem pelos documentos do intervalo. A idade calcula-se depois,
-- já só com as faturas destas linhas.
SELECT
	bi.bistamp,
	CONVERT(VARCHAR(120), RTRIM(bi.nmdos) + ' N' + CHAR(186) + ' ' + CONVERT(VARCHAR(30), bi.obrano)) AS Documento,
	bi.obrano AS Obrano,
	CONVERT(DATE, bi.dataobra) AS DataDoc,
	bi.nome AS Cliente,
	vBase.cmdesc AS Vendedor,
	bo.u_design AS Atend,
	bi.ref AS Ref,
	bi.design AS Design,
	bi.qtt AS QtdEncom,
	bi.qtt2 AS QtdFornec,
	ROUND((bi.ettdeb / bi.qtt) * (bi.qtt - bi.qtt2), 2) AS ValorPorFaturarRaw,
	ROUND((bi.ettdeb / bi.qtt) * bi.qtt2, 2) AS ValorFaturadoRaw,
	bi2.u_dtcativo AS DtCativo,
	bo.datafecho AS DtFecho,
	bo.fechada
INTO #linhas
FROM bo (NOLOCK)
INNER JOIN bi (NOLOCK) ON bo.bostamp = bi.bostamp
INNER JOIN bi2 (NOLOCK) ON bi.bistamp = bi2.bi2stamp
INNER JOIN cm3 vEscal (NOLOCK) ON bi.vendedor = vEscal.cm
INNER JOIN cm3 vBase (NOLOCK) ON vEscal.u_utl = vBase.cm
WHERE bo.ndos IN (1, 26)
	AND bo.dataobra BETWEEN @mDtIni AND @mDtFin
	AND bi.qtt <> 0
	AND bi.cativo = 1
	-- YEAR(u_dtcativo) <> 1900, sem função sobre a coluna.
	AND (
		bi2.u_dtcativo < CONVERT(DATETIME, '19000101', 112)
		OR bi2.u_dtcativo >= CONVERT(DATETIME, '19010101', 112)
	)
	AND vBase.cmdesc = IIF(@mVendedor = '', bo.vendnm, @mVendedor)
	-- O resumo sem atendimento não filtra bo.u_design (igual à consulta original).
	AND (
		(@mDetalhe = 0 AND @mMostraAtend = 0)
		OR bo.u_design = IIF(@mAtendimento = '', bo.u_design, @mAtendimento)
	)
OPTION (RECOMPILE);

CREATE CLUSTERED INDEX IX_linhas_bistamp ON #linhas (bistamp);

SELECT
	fi.bistamp,
	MIN(ft.fdata) AS fdata
INTO #fatura
FROM #linhas l
INNER JOIN fi (NOLOCK) ON fi.bistamp = l.bistamp
INNER JOIN ft (NOLOCK) ON ft.ftstamp = fi.ftstamp
GROUP BY fi.bistamp;

CREATE CLUSTERED INDEX IX_fatura_bistamp ON #fatura (bistamp);

SELECT
	l.Documento,
	l.Obrano,
	l.DataDoc,
	l.Cliente,
	l.Vendedor,
	l.Atend,
	l.Ref,
	l.Design,
	l.QtdEncom,
	l.QtdFornec,
	l.ValorPorFaturarRaw,
	l.ValorFaturadoRaw,
	CONVERT(DATE, l.DtCativo) AS DataCativo,
	CONVERT(DATE, l.DtFecho) AS DataFecho,
	CONVERT(DATE, ISNULL(f.fdata, '')) AS DataFt,
	DATEDIFF(dd, l.DtCativo, ISNULL(f.fdata, IIF(l.fechada = 1, l.DtFecho, @mAgora))) AS IdadeCativo
INTO #calc
FROM #linhas l
LEFT JOIN #fatura f ON f.bistamp = l.bistamp;

IF @mDetalhe = 1
BEGIN
	SELECT
		Documento,
		DataDoc,
		Cliente,
		Vendedor,
		Atend,
		Ref,
		Design,
		QtdEncom,
		QtdFornec,
		CONVERT(DECIMAL(12, 2), ValorPorFaturar) AS ValorPorFaturar,
		DataCativo,
		DataFecho,
		DataFt,
		IdadeCativo
	FROM (
		SELECT
			0 AS Ordem,
			Documento,
			Obrano,
			DataDoc,
			Cliente,
			Vendedor,
			Atend,
			Ref,
			Design,
			QtdEncom,
			QtdFornec,
			CONVERT(DECIMAL(12, 2), ValorPorFaturarRaw) AS ValorPorFaturar,
			DataCativo,
			DataFecho,
			DataFt,
			CONVERT(VARCHAR(30), IdadeCativo) AS IdadeCativo
		FROM #calc

		UNION ALL

		SELECT
			1,
			'Total',
			NULL,
			NULL,
			NULL,
			NULL,
			NULL,
			NULL,
			NULL,
			NULL,
			NULL,
			SUM(CONVERT(DECIMAL(12, 2), ValorPorFaturarRaw)),
			NULL,
			NULL,
			NULL,
			CONVERT(VARCHAR(30), CONVERT(DECIMAL(12, 2), AVG(CONVERT(DECIMAL(12, 2), IdadeCativo))))
		FROM #calc
		HAVING COUNT(*) > 0
	) d
	ORDER BY Ordem, DataDoc, Obrano, Ref;
END
ELSE IF @mMostraAtend = 1
BEGIN
	SELECT
		Vendedor,
		Atend,
		CONVERT(DECIMAL(12, 2), SUM(ValorPorFaturarRaw)) AS ValorPorFaturar,
		CONVERT(DECIMAL(12, 2), SUM(ValorFaturadoRaw)) AS ValorFaturado,
		AVG(IdadeCativo) AS IdadeMediaCativo
	INTO #resumoAtend
	FROM #calc
	GROUP BY Vendedor, Atend;

	SELECT
		Vendedor,
		Atend,
		CONVERT(DECIMAL(12, 2), ValorPorFaturar) AS ValorPorFaturar,
		CONVERT(DECIMAL(12, 2), ValorFaturado) AS ValorFaturado,
		IdadeMediaCativo
	FROM (
		SELECT
			0 AS Ordem,
			Vendedor,
			Atend,
			ValorPorFaturar,
			ValorFaturado,
			CONVERT(VARCHAR(30), IdadeMediaCativo) AS IdadeMediaCativo
		FROM #resumoAtend

		UNION ALL

		SELECT
			1,
			'Total',
			NULL,
			SUM(ValorPorFaturar),
			SUM(ValorFaturado),
			CONVERT(VARCHAR(30), CONVERT(DECIMAL(12, 2), AVG(CONVERT(DECIMAL(12, 2), IdadeMediaCativo))))
		FROM #resumoAtend
		HAVING COUNT(*) > 0
	) r
	ORDER BY Ordem, Vendedor, Atend;
END
ELSE
BEGIN
	SELECT
		Vendedor,
		CONVERT(DECIMAL(12, 2), SUM(ValorPorFaturarRaw)) AS ValorPorFaturar,
		CONVERT(DECIMAL(12, 2), SUM(ValorFaturadoRaw)) AS ValorFaturado,
		AVG(IdadeCativo) AS IdadeMediaCativo
	INTO #resumoVend
	FROM #calc
	GROUP BY Vendedor;

	SELECT
		Vendedor,
		CONVERT(DECIMAL(12, 2), ValorPorFaturar) AS ValorPorFaturar,
		CONVERT(DECIMAL(12, 2), ValorFaturado) AS ValorFaturado,
		IdadeMediaCativo
	FROM (
		SELECT
			0 AS Ordem,
			Vendedor,
			ValorPorFaturar,
			ValorFaturado,
			CONVERT(VARCHAR(30), IdadeMediaCativo) AS IdadeMediaCativo
		FROM #resumoVend

		UNION ALL

		SELECT
			1,
			'Total',
			SUM(ValorPorFaturar),
			SUM(ValorFaturado),
			CONVERT(VARCHAR(30), CONVERT(DECIMAL(12, 2), AVG(CONVERT(DECIMAL(12, 2), IdadeMediaCativo))))
		FROM #resumoVend
		HAVING COUNT(*) > 0
	) r
	ORDER BY Ordem, Vendedor;
END

DROP TABLE #calc;
DROP TABLE #fatura;
DROP TABLE #linhas;
IF OBJECT_ID('tempdb..#resumoAtend') IS NOT NULL DROP TABLE #resumoAtend;
IF OBJECT_ID('tempdb..#resumoVend') IS NOT NULL DROP TABLE #resumoVend;

/*
	Índices que mais ajudam, se ainda não existirem:

	CREATE INDEX IX_bo_ndos_dataobra
		ON bo (ndos, dataobra)
		INCLUDE (bostamp, u_design, vendnm, fechada, datafecho);

	CREATE INDEX IX_fi_bistamp
		ON fi (bistamp)
		INCLUDE (ftstamp);
*/
